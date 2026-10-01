import Foundation
import VentilatorControl
import VentilatorExperiment
import XCTest

final class RecoveryMonitorTests: XCTestCase {
    private func fixture() throws -> (URL, ExperimentAuthority, ApprovedExperimentLedger, RecoveryMonitor) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let authority = try ExperimentAuthority(directory: directory, domain: .simulation)
        let plan = CandidateExperimentPlan(binaries: .init(applicationSHA256: String(repeating: "a", count: 64),
                                                          helperSHA256: String(repeating: "b", count: 64)))
        let owner = UUID(), boot = UUID(), device = SimulatedStepDevice(), date = Date()
        let challenge = try authority.prepare(owner: owner, plan: plan, boot: boot, now: 0)
        try authority.approveLocally(challengeID: challenge.id, planSHA256: plan.sha256(), boot: boot, now: 1)
        let ledger = try authority.begin(owner: owner, challengeID: challenge.id, plan: plan, binaries: plan.binaries,
            boot: boot, now: 2, observation: device.observation(at: date), date: date)
        return (directory, authority, ledger, try RecoveryMonitor(ledger: ledger, now: 2))
    }

    func testAutoCannotStartBeforeWriterExitAndTimeoutPreservesPendingLedger() throws {
        let (directory, authority, ledger, monitor) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertThrowsError(try monitor.confirmWriterExited(now: 2.1))
        let operation = UUID()
        try monitor.beginOperation(id: operation, now: 2.1)
        monitor.tick(now: 2.6)
        XCTAssertEqual(monitor.phase, .quiescing)
        XCTAssertEqual(monitor.reason, "writerTimeout")
        XCTAssertNil(monitor.restorationStartedAt)
        monitor.tick(now: 3.6)
        XCTAssertEqual(monitor.phase, .recoveryRequired)
        XCTAssertEqual(monitor.reason, "writerNotQuiescent")
        XCTAssertThrowsError(try monitor.confirmWriterExited(now: 3.7))
        XCTAssertTrue(try XCTUnwrap(authority.state().ledger).pendingRestoration)
        XCTAssertEqual(try authority.state().ledger?.attempts, ledger.attempts)
    }

    func testWrongNonceSessionAndOperationAcknowledgementCannotExtendLease() throws {
        let (directory, _, ledger, monitor) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let anotherNonce = RecoveryScope(ledger: ledger)
        XCTAssertTrue(anotherNonce.matches(ledger))
        XCTAssertThrowsError(try monitor.heartbeat(scope: anotherNonce, now: 3))
        let operation = UUID()
        try monitor.beginOperation(id: operation, now: 3)
        XCTAssertThrowsError(try monitor.acknowledge(id: UUID(), scope: monitor.scope, now: 3.1))
        XCTAssertThrowsError(try monitor.acknowledge(id: operation, scope: anotherNonce, now: 3.1))
        try monitor.acknowledge(id: operation, scope: monitor.scope, now: 3.1)
        try monitor.heartbeat(scope: monitor.scope, now: 3.2)
        for epoch in stride(from: 4.0, through: 11.0, by: 1) { try monitor.heartbeat(scope: monitor.scope, now: epoch) }
        XCTAssertThrowsError(try monitor.heartbeat(scope: monitor.scope, now: 12))
        XCTAssertEqual(monitor.phase, .quiescing)
        XCTAssertEqual(monitor.reason, "leaseExpired")
    }

    func testLateHeartbeatAndReplyCannotReviveWriter() throws {
        let (directory, _, _, monitor) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertThrowsError(try monitor.heartbeat(scope: monitor.scope, now: 4))
        XCTAssertEqual(monitor.phase, .quiescing)
        XCTAssertEqual(monitor.reason, "heartbeatLost")
        XCTAssertThrowsError(try monitor.beginOperation(id: UUID(), now: 4.1))
        try monitor.confirmWriterExited(now: 4.2)
        let operation = UUID()
        try monitor.beginOperation(id: operation, now: 4.3)
        XCTAssertThrowsError(try monitor.acknowledge(id: operation, scope: monitor.scope, now: 4.8))
        XCTAssertEqual(monitor.phase, .recoveryRequired)
        XCTAssertEqual(monitor.reason, "restorerTimeout")
    }

    func testRestorationDeadlineCannotBeExtendedAndBackwardClockCannotCorruptLedger() throws {
        let (directory, authority, ledger, monitor) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertThrowsError(try authority.closeFixedAndBeginRestoration(sessionID: ledger.sessionID, now: 1.5, date: Date()))
        XCTAssertNil(try authority.state().ledger?.restoreStartedAt)
        monitor.stop(reason: "explicitAuto", now: 3)
        try monitor.confirmWriterExited(now: 3.2)
        monitor.stop(reason: "anotherRequest", now: 4)
        XCTAssertEqual(monitor.restorationStartedAt, 3.2)
        monitor.tick(now: 11.2)
        XCTAssertEqual(monitor.phase, .recoveryRequired)
        XCTAssertEqual(monitor.reason, "restorationExpired")
    }

    func testDurableClosureBlocksLateWriterAndExistingRestoreEpochIsNotRenewed() throws {
        let (directory, authority, ledger, monitor) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        try authority.closeFixed(sessionID: ledger.sessionID, now: 3)
        let date = Date(), device = SimulatedStepDevice()
        XCTAssertThrowsError(try authority.reserve(step: .unlock, sessionID: ledger.sessionID,
            owner: ledger.approval.challenge.connectionOwner, boot: ledger.approval.challenge.bootSession,
            now: 3.1, observation: device.observation(at: date), date: date))
        XCTAssertNil(try authority.state().ledger?.restoreStartedAt)
        _ = try authority.closeFixedAndBeginRestoration(sessionID: ledger.sessionID, now: 3.2, date: date)
        monitor.stop(reason: "writerFailure", now: 3.2)
        try monitor.confirmWriterExited(now: 3.5, restorationStartedAt: 3.2)
        XCTAssertEqual(monitor.restorationStartedAt, 3.2)
        monitor.tick(now: 11.2)
        XCTAssertEqual(monitor.phase, .recoveryRequired)
        XCTAssertTrue(try XCTUnwrap(authority.state().ledger).pendingRestoration)
    }

    func testCorruptModelCannotBeReinitializedAndReservedAttemptRemainsSpent() throws {
        let (directory, authority, ledger, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = try FileSessionJournal(directory: directory)
        try journal.saveSimulationDevice(SimulationDeviceState())
        let reader = try FileSimulatedStepDevice(directory: directory, sessionID: ledger.sessionID)
        let date = Date()
        let reservation = try authority.reserve(step: .unlock, sessionID: ledger.sessionID,
            owner: ledger.approval.challenge.connectionOwner, boot: ledger.approval.challenge.bootSession,
            now: 2, observation: reader.observation(at: date), date: date)
        try Data("corrupt".utf8).write(to: directory.appendingPathComponent("simulation-device.json"))
        XCTAssertThrowsError(try reader.write(reservation))
        XCTAssertEqual(try authority.state().ledger?.attempts, [.unlock])
        XCTAssertThrowsError(try FileSimulatedStepDevice(directory: directory, sessionID: ledger.sessionID))
    }
}
