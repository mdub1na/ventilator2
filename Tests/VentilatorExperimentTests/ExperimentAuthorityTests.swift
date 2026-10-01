import Foundation
import VentilatorControl
import VentilatorExperiment
import XCTest

final class ExperimentAuthorityTests: XCTestCase {
    private let owner = UUID(), boot = UUID()
    private let plan = CandidateExperimentPlan(binaries: .init(applicationSHA256: String(repeating: "a", count: 64),
                                                              helperSHA256: String(repeating: "b", count: 64)))
    private func date(_ now: Double) -> Date { Date(timeIntervalSince1970: 1000 + now) }
    private func folder() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString) }

    private func approved(_ directory: URL) throws -> (ExperimentAuthority, ApprovedExperimentLedger, SimulatedStepDevice) {
        let authority = try ExperimentAuthority(directory: directory, domain: .simulation)
        let device = SimulatedStepDevice()
        let challenge = try authority.prepare(owner: owner, plan: plan, boot: boot, now: 0)
        try authority.approveLocally(challengeID: challenge.id, planSHA256: plan.sha256(), boot: boot, now: 1)
        let ledger = try authority.begin(owner: owner, challengeID: challenge.id, plan: plan, binaries: plan.binaries,
            boot: boot, now: 2, observation: device.observation(at: date(2)), date: date(2))
        return (authority, ledger, device)
    }

    func testApprovalMustMatchChallengeBootBinaryAndConnection() throws {
        let directory = folder(); defer { try? FileManager.default.removeItem(at: directory) }
        let authority = try ExperimentAuthority(directory: directory, domain: .simulation)
        let device = SimulatedStepDevice()
        let challenge = try authority.prepare(owner: owner, plan: plan, boot: boot, now: 0)
        func begin(_ actor: UUID, _ startedBoot: UUID, _ binaries: CandidateExperimentPlan.Binaries) throws {
            _ = try authority.begin(owner: actor, challengeID: challenge.id, plan: plan, binaries: binaries,
                boot: startedBoot, now: 2, observation: device.observation(at: date(2)), date: date(2))
        }
        XCTAssertThrowsError(try begin(owner, boot, plan.binaries))
        XCTAssertThrowsError(try authority.approveLocally(challengeID: UUID(), planSHA256: plan.sha256(), boot: boot, now: 1))
        XCTAssertThrowsError(try authority.approveLocally(challengeID: challenge.id, planSHA256: String(repeating: "f", count: 64), boot: boot, now: 1))
        try authority.approveLocally(challengeID: challenge.id, planSHA256: plan.sha256(), boot: boot, now: 1)
        XCTAssertThrowsError(try begin(UUID(), boot, plan.binaries))
        XCTAssertThrowsError(try begin(owner, UUID(), plan.binaries))
        XCTAssertThrowsError(try begin(owner, boot, .init(applicationSHA256: plan.binaries.applicationSHA256, helperSHA256: String(repeating: "c", count: 64))))
        XCTAssertNil(try authority.state().ledger)
        try begin(owner, boot, plan.binaries)
        XCTAssertEqual(try authority.state().ledger?.domain, .simulation)
    }

    func testExpiredApprovalAndAnotherConnectionCannotReplacePendingChallenge() throws {
        let directory = folder(); defer { try? FileManager.default.removeItem(at: directory) }
        let authority = try ExperimentAuthority(directory: directory, domain: .simulation)
        let device = SimulatedStepDevice()
        let challenge = try authority.prepare(owner: owner, plan: plan, boot: boot, now: 0)
        XCTAssertThrowsError(try authority.prepare(owner: UUID(), plan: plan, boot: boot, now: 1))
        try authority.approveLocally(challengeID: challenge.id, planSHA256: plan.sha256(), boot: boot, now: 1)
        XCTAssertThrowsError(try authority.begin(owner: owner, challengeID: challenge.id, plan: plan, binaries: plan.binaries,
            boot: boot, now: 300, observation: device.observation(at: date(300)), date: date(300)))
        XCTAssertNil(try authority.state().ledger)
    }

    func testConsumedApprovalSurvivesNewProcessObjectAndCannotResumeFixed() throws {
        let directory = folder(); defer { try? FileManager.default.removeItem(at: directory) }
        let (_, ledger, device) = try approved(directory)
        let restarted = try ExperimentAuthority(directory: directory, domain: .simulation)
        XCTAssertTrue(try XCTUnwrap(restarted.state().ledger).pendingRestoration)
        XCTAssertThrowsError(try restarted.begin(owner: owner, challengeID: ledger.approval.challenge.id, plan: plan,
            binaries: plan.binaries, boot: boot, now: 3, observation: device.observation(at: date(3)), date: date(3)))
        XCTAssertThrowsError(try restarted.prepare(owner: owner, plan: plan, boot: boot, now: 301))
    }

    func testEarlyModeStepClosesFixedAndStartsRestorationInsteadOfRetrying() throws {
        let directory = folder(); defer { try? FileManager.default.removeItem(at: directory) }
        let (authority, ledger, device) = try approved(directory)
        let executor = try ApprovedStepExecutor(authority: authority, sessionID: ledger.sessionID, device: device)
        try executor.perform(.unlock, now: 2, date: date(2), observation: device.observation(at: date(2)))
        XCTAssertThrowsError(try executor.perform(.manualZero, now: 4.9, date: date(4.9), observation: device.observation(at: date(4.9))))
        XCTAssertTrue(try XCTUnwrap(authority.state().ledger).fixedClosed)
        XCTAssertEqual(device.effects, [.unlock])
        XCTAssertThrowsError(try executor.perform(.manualZero, now: 5, date: date(5), observation: device.observation(at: date(5))))
    }

    func testPartialDeviceFailureIsConsumedBeforeIOAndRestorationBudgetDoesNotReset() throws {
        let directory = folder(); defer { try? FileManager.default.removeItem(at: directory) }
        let (authority, ledger, device) = try approved(directory)
        device.failAfterStep = .unlock
        let executor = try ApprovedStepExecutor(authority: authority, sessionID: ledger.sessionID, device: device)
        XCTAssertThrowsError(try executor.perform(.unlock, now: 2, date: date(2), observation: device.observation(at: date(2))))
        let pending = try XCTUnwrap(authority.state().ledger)
        XCTAssertEqual(pending.attempts, [.unlock])
        XCTAssertTrue(pending.pendingRestoration && pending.fixedClosed)
        XCTAssertEqual(pending.restoreStartedAt, 2)
        _ = try authority.closeFixedAndBeginRestoration(sessionID: ledger.sessionID, now: 5, date: date(5))
        XCTAssertEqual(try authority.state().ledger?.restoreStartedAt, 2)
        XCTAssertThrowsError(try executor.perform(.autoZero, now: 10, date: date(10), observation: device.observation(at: date(10))))
        XCTAssertEqual(device.effects, [.unlock])
    }

    func testAReservationCannotBeUsedTwiceOrConvertedToHardware() throws {
        let directory = folder(); defer { try? FileManager.default.removeItem(at: directory) }
        let (authority, ledger, device) = try approved(directory)
        let reservation = try authority.reserve(step: .unlock, sessionID: ledger.sessionID, owner: owner, boot: boot,
            now: 2, observation: device.observation(at: date(2)), date: date(2))
        XCTAssertThrowsError(try reservation.consume(domain: .hardware, sessionID: ledger.sessionID))
        try device.write(reservation)
        XCTAssertThrowsError(try device.write(reservation))
        XCTAssertEqual(device.effects, [.unlock])
        XCTAssertThrowsError(try authority.reserve(step: .unlock, sessionID: ledger.sessionID, owner: owner, boot: boot,
            now: 3, observation: device.observation(at: date(3)), date: date(3)))
    }

    func testFullSequenceAndRestorationKeepSpentApprovalAfterAutoCodes() throws {
        let directory = folder(); defer { try? FileManager.default.removeItem(at: directory) }
        let (authority, ledger, device) = try approved(directory)
        let executor = try ApprovedStepExecutor(authority: authority, sessionID: ledger.sessionID, device: device)
        for (step, now) in [(ExperimentStep.unlock, 2.0), (.manualZero, 5), (.manualOne, 5.1), (.targetZero, 5.2), (.targetOne, 5.3)] {
            try executor.perform(step, now: now, date: date(now), observation: device.observation(at: date(now)))
        }
        _ = try authority.closeFixedAndBeginRestoration(sessionID: ledger.sessionID, now: 6, date: date(6))
        for step in ExperimentStep.allCases.filter({ !$0.isFixed }) {
            try executor.perform(step, now: 6, date: date(6), observation: device.observation(at: date(6)))
        }
        let samples = (7...9).map { device.observation(at: date(Double($0))) }
        try authority.finishObservedRestoration(sessionID: ledger.sessionID, samples: samples, now: 9, date: date(9))
        let spent = try XCTUnwrap(authority.state().ledger)
        XCTAssertFalse(spent.pendingRestoration)
        XCTAssertEqual(spent.attempts, ExperimentStep.allCases)
        XCTAssertThrowsError(try authority.begin(owner: owner, challengeID: ledger.approval.challenge.id, plan: plan, binaries: plan.binaries,
            boot: boot, now: 10, observation: device.observation(at: date(10)), date: date(10)))
    }

    func testCorruptJournalPreventsDeviceIOAndOldSamplesCannotClearPendingState() throws {
        let directory = folder(); defer { try? FileManager.default.removeItem(at: directory) }
        let (authority, ledger, device) = try approved(directory)
        _ = try authority.closeFixedAndBeginRestoration(sessionID: ledger.sessionID, now: 6, date: date(6))
        let oldSamples = (3...5).map { device.observation(at: date(Double($0))) }
        XCTAssertThrowsError(try authority.finishObservedRestoration(sessionID: ledger.sessionID, samples: oldSamples, now: 7, date: date(7)))
        XCTAssertTrue(try XCTUnwrap(authority.state().ledger).pendingRestoration)
        let executor = try ApprovedStepExecutor(authority: authority, sessionID: ledger.sessionID, device: device)
        try Data("corrupt".utf8).write(to: directory.appendingPathComponent("authority-simulation.json"))
        XCTAssertThrowsError(try executor.perform(.autoZero, now: 7, date: date(7), observation: device.observation(at: date(7))))
        XCTAssertTrue(device.effects.isEmpty)
    }
}
