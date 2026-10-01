import Foundation
import XCTest
import VentilatorControl
@testable import VentilatorExperiment

final class BrokerRestartRecoveryTests: XCTestCase {
    private func fixture() throws -> (URL, ExperimentAuthority, ApprovedExperimentLedger, SimulatedStepDevice) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let authority = try ExperimentAuthority(directory: directory, domain: .simulation)
        let plan = CandidateExperimentPlan(binaries: .init(applicationSHA256: String(repeating: "a", count: 64), helperSHA256: String(repeating: "b", count: 64)))
        let owner = UUID(), boot = UUID(), device = SimulatedStepDevice(), date = Date()
        let challenge = try authority.prepare(owner: owner, plan: plan, boot: boot, now: 0)
        try authority.approveLocally(challengeID: challenge.id, planSHA256: plan.sha256(), boot: boot, now: 1)
        let ledger = try authority.begin(owner: owner, challengeID: challenge.id, plan: plan, binaries: plan.binaries,
            boot: boot, now: 2, observation: device.observation(at: date), date: date)
        return (directory, authority, ledger, device)
    }
    private func restart(_ authority: ExperimentAuthority, _ ledger: ApprovedExperimentLedger, now: Double = 3) throws -> BrokerRestartRecovery {
        try .init(authority: authority, sessionID: ledger.sessionID, boot: ledger.approval.challenge.bootSession,
                  binaries: ledger.approval.challenge.binaries, now: now, date: Date())
    }
    func testRestartClosesFixedAndIssuesOnlyRemainingAutoWithNewNonce() throws {
        let (directory, authority, ledger, _) = try fixture(); defer { try? FileManager.default.removeItem(at: directory) }
        let old = try RecoveryMonitor(ledger: ledger, now: 2)
        let recovery = try restart(authority, ledger)
        let monitor = try RecoveryMonitor(restarting: recovery, now: 3)
        XCTAssertEqual(monitor.phase, .restoring)
        XCTAssertNotEqual(monitor.scope.nonce, old.scope.nonce)
        XCTAssertEqual(recovery.remainingSteps, ExperimentStep.allCases.filter { !$0.isFixed })
        XCTAssertTrue(try authority.state().ledger!.fixedClosed)
        XCTAssertThrowsError(try FileSessionJournal(directory: directory).acquireDeviceExecutionLock(domain: .simulation))
        recovery.releaseForAutoChild()
        let lock = try FileSessionJournal(directory: directory).acquireDeviceExecutionLock(domain: .simulation)
        withExtendedLifetime(lock) {}
        XCTAssertThrowsError(try monitor.heartbeat(scope: monitor.scope, now: 3.1))
    }
    func testLiveDeviceLockPreventsAutoAndDoesNotCreateRestorationEpoch() throws {
        let (directory, authority, ledger, _) = try fixture(); defer { try? FileManager.default.removeItem(at: directory) }
        let deviceLock = try FileSessionJournal(directory: directory).acquireDeviceExecutionLock(domain: .simulation)
        XCTAssertThrowsError(try restart(authority, ledger)) { XCTAssertEqual($0 as? BrokerRestartError, .deviceStillActive) }
        let state = try authority.state().ledger!
        XCTAssertTrue(state.fixedClosed && state.pendingRestoration)
        XCTAssertNil(state.restoreStartedAt)
        XCTAssertTrue(state.attempts.isEmpty)
        withExtendedLifetime(deviceLock) {}
    }
    func testOriginalRestorationDeadlineAndAttemptBudgetSurviveRestart() throws {
        let (directory, authority, ledger, device) = try fixture(); defer { try? FileManager.default.removeItem(at: directory) }
        _ = try authority.closeFixedAndBeginRestoration(sessionID: ledger.sessionID, now: 3, date: Date())
        let date = Date(), executor = try ApprovedStepExecutor(authority: authority, sessionID: ledger.sessionID, device: device)
        try executor.perform(.autoZero, now: 3, date: date, observation: device.observation(at: date))
        let recovered = try restart(authority, ledger, now: 4)
        XCTAssertEqual(recovered.ledger.restoreStartedAt, 3)
        XCTAssertFalse(recovered.remainingSteps.contains(.autoZero))
        XCTAssertTrue(recovered.ambiguousAutoSteps.isEmpty)
        recovered.releaseForAutoChild()
        XCTAssertThrowsError(try restart(authority, ledger, now: 11)) {
            XCTAssertEqual($0 as? BrokerRestartError, .originalDeadlineExpired)
        }
        XCTAssertEqual(try authority.state().ledger!.restoreStartedAt, 3)
        XCTAssertEqual(try authority.state().ledger!.attempts, [.autoZero])
    }
    func testUnreturnedAutoIsNeverRepeatedOrDeclaredSuccessful() throws {
        let (directory, authority, ledger, device) = try fixture(); defer { try? FileManager.default.removeItem(at: directory) }
        _ = try authority.closeFixedAndBeginRestoration(sessionID: ledger.sessionID, now: 3, date: Date())
        let date = Date()
        _ = try authority.reserve(step: .autoZero, sessionID: ledger.sessionID, owner: ledger.approval.challenge.connectionOwner,
            boot: ledger.approval.challenge.bootSession, now: 3, observation: device.observation(at: date), date: date)
        let recovered = try restart(authority, ledger, now: 4)
        XCTAssertEqual(recovered.ambiguousAutoSteps, [.autoZero])
        XCTAssertFalse(recovered.remainingSteps.contains(.autoZero))
        XCTAssertTrue(try authority.state().ledger!.pendingRestoration)
    }
    func testWrongBootHashOrSessionCannotCloseOrRestore() throws {
        let (directory, authority, ledger, _) = try fixture(); defer { try? FileManager.default.removeItem(at: directory) }
        for (session, boot, binaries) in [
            (UUID(), ledger.approval.challenge.bootSession, ledger.approval.challenge.binaries),
            (ledger.sessionID, UUID(), ledger.approval.challenge.binaries),
            (ledger.sessionID, ledger.approval.challenge.bootSession,
             CandidateExperimentPlan.Binaries(applicationSHA256: String(repeating: "c", count: 64), helperSHA256: String(repeating: "b", count: 64)))
        ] {
            XCTAssertThrowsError(try BrokerRestartRecovery(authority: authority, sessionID: session, boot: boot, binaries: binaries, now: 3, date: Date()))
        }
        XCTAssertFalse(try authority.state().ledger!.fixedClosed)
        XCTAssertTrue(try authority.state().ledger!.attempts.isEmpty)
    }
}
