import Foundation
import XCTest
@testable import VentilatorControl

final class FileSessionJournalTests: XCTestCase {
    func testNewInstanceFindsPendingRecordAndOnlyClearsAfterRestoration() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = try FileSessionJournal(directory: directory)
        let transport = SimulatedFanTransport()
        let first = ControlSession(transport: transport, journal: journal)
        _ = try first.begin(owner: UUID(), now: 0, date: Date(timeIntervalSince1970: 1000))
        let reloaded = try FileSessionJournal(directory: directory)
        XCTAssertEqual(try reloaded.load(), try journal.load())
        let restarted = ControlSession(transport: transport, journal: reloaded)
        restarted.recover(now: 1, date: Date(timeIntervalSince1970: 1001))
        for instant in 2...4 { restarted.tick(now: Double(instant), date: Date(timeIntervalSince1970: 1000 + Double(instant))) }
        XCTAssertEqual(restarted.report.phase, .autoCodeObserved)
        XCTAssertNil(try journal.load())
    }

    func testSymlinkAndCorruptRecordAreRejected() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = try FileSessionJournal(directory: directory)
        let outside = directory.appendingPathComponent("other.json")
        try Data("invalid".utf8).write(to: outside)
        let record = directory.appendingPathComponent("session.json")
        try FileManager.default.createSymbolicLink(at: record, withDestinationURL: outside)
        XCTAssertThrowsError(try journal.load())
        try FileManager.default.removeItem(at: record)
        try Data("invalid".utf8).write(to: record)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: record.path)
        XCTAssertThrowsError(try journal.load())
    }

    func testWorkerLockExcludesAnotherOwnerAndIsReleasedOnClose() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try FileSessionJournal(directory: directory)
        let second = try FileSessionJournal(directory: directory)
        var lock: SessionJournalLock? = try first.acquireWorkerLock()
        XCTAssertNotNil(lock)
        XCTAssertThrowsError(try second.acquireWorkerLock())
        lock = nil
        let next = try second.acquireWorkerLock()
        withExtendedLifetime(next) {}
    }

    func testOutcomeCannotClaimHardwareControlAndRejectsSymlink() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = try FileSessionJournal(directory: directory)
        let outcome = SimulationWorkerOutcome(reply: HelperReply(control: ControlReport(phase: .autoCodeObserved)),
                                              effects: [.fixed2500, .auto], elapsedSeconds: 3,
                                              powerNotificationsRegistered: false)
        try journal.saveWorkerOutcome(outcome)
        XCTAssertEqual(try journal.loadWorkerOutcome()?.effects, [.fixed2500, .auto])
        let file = directory.appendingPathComponent("worker-result.json")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
        var reply = try XCTUnwrap(object["reply"] as? [String: Any])
        reply["hardwareControlAvailable"] = true
        object["reply"] = reply
        try JSONSerialization.data(withJSONObject: object).write(to: file)
        XCTAssertThrowsError(try journal.loadWorkerOutcome())
        try journal.clearWorkerOutcome()
        try FileManager.default.createSymbolicLink(at: file, withDestinationURL: directory.appendingPathComponent("session.json"))
        XCTAssertThrowsError(try journal.loadWorkerOutcome())
    }
}
