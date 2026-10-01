import Darwin
import Foundation
import XCTest
@testable import VentilatorControl

final class LocalReviewFileTests: XCTestCase {
    private let binaries = CandidateExperimentPlan.Binaries(applicationSHA256: String(repeating: "a", count: 64), helperSHA256: String(repeating: "b", count: 64))
    private func fixture() throws -> (URL, URL, LocalApprovalReview) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = directory.appendingPathComponent("review.json")
        let review = try LocalApprovalReview(domain: .simulation, candidate: CandidateExperimentPlan(binaries: binaries),
            ownerInstructions: "Полный сеанс: " + String(repeating: "x", count: 10_000))
        try review.canonicalJSON().write(to: path)
        return (directory, path, review)
    }
    func testFullInstructionsImportOnlyExactCandidateDomainAndCanonicalDigest() throws {
        let (dir, file, review) = try fixture(); defer { try? FileManager.default.removeItem(at: dir) }
        let loaded = try LocalReviewFile.load(file, domain: .simulation, binaries: binaries, expectedSHA256: review.sha256())
        XCTAssertEqual(loaded.ownerInstructions, review.ownerInstructions)
        XCTAssertThrowsError(try LocalReviewFile.load(file, domain: .hardware, binaries: binaries, expectedSHA256: review.sha256()))
        XCTAssertThrowsError(try LocalReviewFile.load(file, domain: .simulation, binaries: binaries, expectedSHA256: String(repeating: "0", count: 64)))
        let other = CandidateExperimentPlan.Binaries(applicationSHA256: String(repeating: "c", count: 64), helperSHA256: binaries.helperSHA256)
        XCTAssertThrowsError(try LocalReviewFile.load(file, domain: .simulation, binaries: other, expectedSHA256: review.sha256()))
    }
    func testSymlinkHardLinkAndNonRegularSourceCannotBeStaged() throws {
        let (dir, file, review) = try fixture(); defer { try? FileManager.default.removeItem(at: dir) }
        let alias = dir.appendingPathComponent("alias.json")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: file)
        XCTAssertThrowsError(try LocalReviewFile.load(alias, domain: .simulation, binaries: binaries, expectedSHA256: review.sha256()))
        try FileManager.default.removeItem(at: alias)
        try FileManager.default.linkItem(at: file, to: alias)
        XCTAssertThrowsError(try LocalReviewFile.load(file, domain: .simulation, binaries: binaries, expectedSHA256: review.sha256()))
        let fifo = dir.appendingPathComponent("fifo")
        XCTAssertEqual(mkfifo(fifo.path, 0o600), 0)
        XCTAssertThrowsError(try LocalReviewFile.load(fifo, domain: .simulation, binaries: binaries, expectedSHA256: review.sha256()))
    }
    func testOversizedAndMalformedSourceRejectedBeforeProtectedImport() throws {
        let (dir, file, review) = try fixture(); defer { try? FileManager.default.removeItem(at: dir) }
        for data in [Data(repeating: 32, count: 16_385), Data("{}".utf8)] {
            try data.write(to: file)
            XCTAssertThrowsError(try LocalReviewFile.load(file, domain: .simulation, binaries: binaries, expectedSHA256: review.sha256()))
        }
    }
}
