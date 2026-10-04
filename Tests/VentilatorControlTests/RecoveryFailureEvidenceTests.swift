import Foundation
import XCTest
@testable import VentilatorControl

final class RecoveryFailureEvidenceTests: XCTestCase {
    func testFailureDetailsSurviveJournalWithoutBecomingIndependentAutoEvidence() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let failures = [
            RecoveryFailureEvidence(phase: "fixed", role: "fixed", step: .manualZero, error: "unsafeObservation",
                                    elapsedSeconds: 3.4, admissionSampleJSON: "{\"testMode\":0}"),
            RecoveryFailureEvidence(phase: "restoring", role: "restore", step: .autoZero, error: "failedStep", elapsedSeconds: 4.1)
        ]
        let journal = try FileSessionJournal(directory: directory)
        try journal.saveRecoveryOutcome(.init(sessionID: UUID(), phase: "recoveryRequired", reason: "restoreStepFailure",
            events: [], failedSteps: [.manualZero, .autoZero], elapsedSeconds: 6,
            powerNotificationsRegistered: false, failures: failures))
        let saved = try XCTUnwrap(journal.loadRecoveryOutcome())
        XCTAssertEqual(saved.reason, "restoreStepFailure")
        XCTAssertEqual(saved.failures?.map(\.error), ["unsafeObservation", "failedStep"])
        XCTAssertEqual(saved.failures?.first?.step, .manualZero)
        XCTAssertEqual(saved.failures?.first?.admissionSampleJSON, "{\"testMode\":0}")
        XCTAssertTrue(try XCTUnwrap(saved.observations).isEmpty)
    }

    func testLegacyHardwareOutcomeDecodesWithoutNewDiagnostics() throws {
        let outcome = HardwareRecoveryOutcome(sessionID: UUID(), phase: "recoveryRequired", reason: "restoreStepFailure",
            events: [], failedSteps: [.autoZero], elapsedSeconds: 6, powerNotificationsRegistered: true)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(outcome)) as? [String: Any])
        json.removeValue(forKey: "failures")
        let legacy = try JSONDecoder().decode(HardwareRecoveryOutcome.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(legacy.failures)
        XCTAssertFalse(legacy.physicalAutoVerified)
        XCTAssertEqual(legacy.failedSteps, [.autoZero])
    }

    func testDiagnosticLimitsKeepEarliestFailureAndUnknownTimeIsNotInvented() throws {
        let failures = (0..<20).map { index in
            RecoveryFailureEvidence(phase: "restoring", role: "restore", step: .autoZero,
                error: "\(index):" + String(repeating: "x", count: 1000), elapsedSeconds: .nan)
        }
        let outcome = HardwareRecoveryOutcome(sessionID: UUID(), phase: "recoveryRequired", reason: nil,
            events: [], failedSteps: [.autoZero], elapsedSeconds: 6, powerNotificationsRegistered: true, failures: failures)
        let decoded = try JSONDecoder().decode(HardwareRecoveryOutcome.self, from: JSONEncoder().encode(outcome))
        XCTAssertEqual(decoded.failures?.count, 16)
        XCTAssertTrue(try XCTUnwrap(decoded.failures?.first?.error).hasPrefix("0:"))
        XCTAssertEqual(decoded.failures?.first?.error.count, 512)
        XCTAssertNil(decoded.failures?.first?.elapsedSeconds)
        XCTAssertFalse(decoded.physicalAutoVerified)
    }
}
