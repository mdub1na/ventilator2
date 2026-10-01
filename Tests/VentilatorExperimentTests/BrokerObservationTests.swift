import Foundation
import XCTest
import VentilatorControl
import VentilatorCore
@testable import VentilatorExperiment

final class BrokerObservationTests: XCTestCase {
    let date = Date(timeIntervalSince1970: 1_800_000_000)

    private func sample(pressure: ExperimentVerification.ThermalPressure = .nominal) -> BrokerObservation {
        let device = SimulatedStepDevice()
        let value = device.observation(at: date)
        return BrokerObservation(.init(observation: .init(snapshot: value.snapshot, thermalPressure: pressure, testModeCode: 0), readSeconds: 0.003))
    }

    private func changed(_ edit: (inout [String: Any]) -> Void) throws -> BrokerObservation {
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(sample())) as! [String: Any]
        edit(&json)
        return try JSONDecoder().decode(BrokerObservation.self, from: JSONSerialization.data(withJSONObject: json))
    }

    private func admit(_ sample: BrokerObservation, requested: Date? = nil, now: Double = 10.1, received: Date? = nil) throws -> ControlObservation {
        try sample.admitted(requestedAt: requested ?? date, deadline: 10.5, now: now, date: received ?? date.addingTimeInterval(0.1))
    }

    func testIndependentIPCUsesRequiredFanValuesAndPreservesZero() throws {
        let decoded = try JSONDecoder().decode(BrokerObservation.self, from: JSONEncoder().encode(sample()))
        let value = try admit(decoded)
        XCTAssertEqual(value.snapshot.fans.map(\.actualRPM), [0, 0])
        XCTAssertEqual(value.snapshot.fans.map(\.modeCode), [3, 3])
        XCTAssertEqual(value.testModeCode, 0)
        XCTAssertTrue(value.snapshot.temperatures.isEmpty)
    }

    func testReplyFromEarlierRequestAndFutureSampleAreRejected() {
        XCTAssertThrowsError(try admit(sample(), requested: date.addingTimeInterval(0.001)))
        XCTAssertThrowsError(try admit(sample(), received: date.addingTimeInterval(-0.001)))
        XCTAssertThrowsError(try admit(sample(), received: date.addingTimeInterval(0.501)))
    }

    func testLateReplyAndInvalidReadDurationDoNotBecomeEvidence() throws {
        XCTAssertThrowsError(try admit(sample(), now: 10.5))
        XCTAssertThrowsError(try admit(sample(), now: .nan))
        for duration in [-0.01, 0.501] {
            XCTAssertThrowsError(try admit(changed { $0["readSeconds"] = duration }))
        }
    }

    func testChangedProfileOrRangeAndUnreadableNumbersAreRejected() throws {
        for key in ["model", "version", "build"] {
            XCTAssertThrowsError(try admit(changed { json in
                var machine = json["machine"] as! [String: Any]; machine[key] = "changed"; json["machine"] = machine
            }))
        }
        for (key, value) in [("minimum", 1351), ("maximum", 5350), ("actual", -1), ("target", -1), ("mode", 2), ("index", 1)] {
            XCTAssertThrowsError(try admit(changed { json in
                var fans = json["fans"] as! [[String: Any]]; fans[0][key] = value; json["fans"] = fans
            }))
        }
        XCTAssertThrowsError(try admit(changed { json in
            var fans = json["fans"] as! [[String: Any]]; fans[0].removeValue(forKey: "actual"); json["fans"] = fans
        }))
        XCTAssertThrowsError(try admit(changed { $0["fans"] = [] }))
        XCTAssertThrowsError(try admit(changed { $0["testMode"] = 2 }))
        XCTAssertThrowsError(try admit(changed { $0.removeValue(forKey: "testMode") }))
    }

    func testPressureIsRetainedForClosingFixedAndNeverGuessed() throws {
        XCTAssertEqual(try admit(sample(pressure: .elevated)).thermalPressure, .elevated)
        XCTAssertEqual(try admit(sample(pressure: .unavailable)).thermalPressure, .unavailable)
        XCTAssertThrowsError(try admit(changed { $0["pressure"] = "normalish" }))
    }

    func testHardwareOutcomeNeverClaimsPhysicalAutoAndNonRootCannotPersistIt() throws {
        let outcome = HardwareRecoveryOutcome(sessionID: UUID(), phase: "autoCodesObserved", reason: nil,
            events: [], failedSteps: [], elapsedSeconds: 4, powerNotificationsRegistered: false)
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(outcome)) as! [String: Any]
        XCTAssertEqual(json["physicalAutoVerified"] as? Bool, false)
        XCTAssertEqual(json["simulationOnly"] as? Bool, false)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertThrowsError(try FileSessionJournal(directory: directory).saveHardwareRecoveryOutcome(outcome))
    }

    func testChildRoleAndScopeAreCheckedBeforeAnyProbeOrDeviceOpen() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = try FileSessionJournal(directory: directory)
        try journal.saveSimulationDevice(.init())
        let authority = try ExperimentAuthority(directory: directory, domain: .simulation)
        let plan = CandidateExperimentPlan(binaries: .init(applicationSHA256: String(repeating: "a", count: 64),
                                                          helperSHA256: String(repeating: "b", count: 64)))
        let owner = UUID(), boot = UUID(), now = ExperimentMonotonicClock.now()
        let challenge = try authority.prepare(owner: owner, plan: plan, boot: boot, now: now)
        try authority.approveLocally(challengeID: challenge.id, planSHA256: plan.sha256(), boot: boot, now: now)
        let ledger = try authority.begin(owner: owner, challengeID: challenge.id, plan: plan, binaries: plan.binaries,
            boot: boot, now: now, observation: SimulatedStepDevice().observation(at: date), date: date)
        let scope = RecoveryScope(ledger: ledger)
        for (role, phase) in [(ExperimentChildRole.restore, RecoveryPhase.fixed), (.fixed, .restoring), (.reader, .restoring)] {
            XCTAssertThrowsError(try ScopedExperimentChild(authority: authority, scope: scope, role: role,
                phase: phase, input: -1, output: -1)) { XCTAssertEqual($0 as? NativeExperimentError, .invalidScope) }
        }
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(scope)) as! [String: Any]
        json["sessionID"] = UUID().uuidString
        let wrong = try JSONDecoder().decode(RecoveryScope.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertThrowsError(try ScopedExperimentChild(authority: authority, scope: wrong, role: .fixed,
            phase: .fixed, input: -1, output: -1)) { XCTAssertEqual($0 as? NativeExperimentError, .invalidScope) }
        try authority.closeFixed(sessionID: ledger.sessionID, now: now)
        XCTAssertThrowsError(try ScopedExperimentChild(authority: authority, scope: scope, role: .fixed,
            phase: .fixed, input: -1, output: -1)) { XCTAssertEqual($0 as? NativeExperimentError, .invalidScope) }
        XCTAssertTrue(try authority.state().ledger!.attempts.isEmpty)
    }
}
