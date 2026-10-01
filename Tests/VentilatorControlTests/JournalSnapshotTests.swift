import Darwin
import Foundation
import XCTest
@testable import VentilatorControl

final class JournalSnapshotTests: XCTestCase {
    func testOpenedAtomicSnapshotRemainsReadableAfterReplacementButCannotBeALock() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = try FileSessionJournal(directory: directory)
        let first = SessionRecord(id: UUID(), owner: UUID(), expiresAt: 10)
        try journal.save(first)
        let fd = open(directory.appendingPathComponent("session.json").path, O_RDONLY | O_NOFOLLOW)
        XCTAssertGreaterThanOrEqual(fd, 0); defer { close(fd) }
        let second = SessionRecord(id: UUID(), owner: UUID(), expiresAt: 20)
        try journal.save(second) // rename removes old inode's link while the read descriptor is retained.
        try FileSessionJournal.checkFile(fd, allowUnlinkedSnapshot: true)
        XCTAssertThrowsError(try FileSessionJournal.checkFile(fd, allowUnlinkedSnapshot: false))
        let data = try FileHandle(fileDescriptor: fd, closeOnDealloc: false).readToEnd()!
        XCTAssertEqual(try JSONDecoder().decode(SessionRecord.self, from: data).id, first.id)
        XCTAssertEqual(try journal.load()?.id, second.id)
    }

    func testLiveHardlinkAndPublicPermissionsStillRejectReadSnapshot() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = try FileSessionJournal(directory: directory)
        try journal.save(.init(id: UUID(), owner: UUID(), expiresAt: 10))
        let file = directory.appendingPathComponent("session.json"), alias = directory.appendingPathComponent("alias.json")
        try FileManager.default.linkItem(at: file, to: alias)
        XCTAssertThrowsError(try journal.load())
        try FileManager.default.removeItem(at: alias)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)
        XCTAssertThrowsError(try journal.load())
    }
}
