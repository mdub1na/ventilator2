import Foundation
import XCTest
import VentilatorControl
@testable import VentilatorExperiment

final class LocalApprovalIssuerTests: XCTestCase {
    let binaries = CandidateExperimentPlan.Binaries(applicationSHA256: String(repeating: "a", count: 64), helperSHA256: String(repeating: "b", count: 64))

    private func fixture() throws -> (URL, ExperimentAuthority, LocalApprovalIssuer, LocalApprovalReview) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let authority = try ExperimentAuthority(directory: directory, domain: .simulation)
        let review = try LocalApprovalReview(domain: .simulation, candidate: CandidateExperimentPlan(binaries: binaries),
            ownerInstructions: "Model session: one 2500 RPM Fixed; Auto before exit. No hardware, root or real sleep.")
        try FileSessionJournal(directory: directory).saveLocalReview(review.canonicalJSON(), domain: .simulation)
        return (directory, authority, try .simulation(authority: authority, binaries: binaries, boot: UUID()), review)
    }

    func testExactReviewAndConfirmationPersistSingleApprovalWithoutStarting() throws {
        let (directory, authority, issuer, review) = try fixture(); defer { try? FileManager.default.removeItem(at: directory) }
        let prompt = try issuer.prepare(owner: UUID(), planSHA256: review.candidate.sha256(), reviewSHA256: review.sha256(), now: 10)
        try issuer.confirm(prompt, response: prompt.confirmation, now: 11)
        let saved = try authority.state()
        XCTAssertEqual(saved.approval?.challenge.ownerReviewSHA256, try review.sha256())
        XCTAssertNil(saved.ledger)
        XCTAssertEqual(saved.approval?.approvedAt, 11)
        XCTAssertThrowsError(try issuer.confirm(prompt, response: prompt.confirmation, now: 12)) {
            XCTAssertEqual($0 as? ExperimentAuthorityError, .approvalAlreadyIssued)
        }
    }

    func testDeclineEOFAndPartialConsentNeverApprove() throws {
        let (directory, authority, issuer, review) = try fixture(); defer { try? FileManager.default.removeItem(at: directory) }
        let prompt = try issuer.prepare(owner: UUID(), planSHA256: review.candidate.sha256(), reviewSHA256: review.sha256(), now: 10)
        for response in [nil, "", "yes", "APPROVE", "START", "START \(prompt.challenge.id.uuidString)", " " + prompt.confirmation] {
            XCTAssertThrowsError(try issuer.confirm(prompt, response: response, now: 11))
            XCTAssertNil(try authority.state().approval)
            XCTAssertNil(try authority.state().ledger)
        }
    }

    func testReviewChangedAfterDisplayOrWrongDigestCannotApprove() throws {
        let (directory, authority, issuer, review) = try fixture(); defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertThrowsError(try issuer.prepare(owner: UUID(), planSHA256: review.candidate.sha256(), reviewSHA256: String(repeating: "f", count: 64), now: 10))
        XCTAssertNil(try authority.state().challenge)
        let prompt = try issuer.prepare(owner: UUID(), planSHA256: review.candidate.sha256(), reviewSHA256: review.sha256(), now: 10)
        let changed = try LocalApprovalReview(domain: .simulation, candidate: review.candidate, ownerInstructions: "Different owner actions")
        try FileSessionJournal(directory: directory).saveLocalReview(changed.canonicalJSON(), domain: .simulation)
        XCTAssertThrowsError(try issuer.confirm(prompt, response: prompt.confirmation, now: 11))
        XCTAssertNil(try authority.state().approval)
    }

    func testChangedBinaryDomainOrExpiredChallengeAreRejected() throws {
        let (directory, authority, issuer, review) = try fixture(); defer { try? FileManager.default.removeItem(at: directory) }
        let prompt = try issuer.prepare(owner: UUID(), planSHA256: review.candidate.sha256(), reviewSHA256: review.sha256(), now: 10)
        XCTAssertThrowsError(try issuer.confirm(prompt, response: prompt.confirmation, now: 310))
        let wrong = try LocalApprovalReview(domain: .hardware, candidate: review.candidate, ownerInstructions: "Hardware review")
        try FileSessionJournal(directory: directory).saveLocalReview(wrong.canonicalJSON(), domain: .simulation)
        XCTAssertThrowsError(try issuer.prepare(owner: UUID(), planSHA256: review.candidate.sha256(), reviewSHA256: wrong.sha256(), now: 311))
        let other = try LocalApprovalIssuer.simulation(authority: authority,
            binaries: .init(applicationSHA256: binaries.applicationSHA256, helperSHA256: String(repeating: "c", count: 64)), boot: UUID())
        XCTAssertThrowsError(try other.confirm(prompt, response: prompt.confirmation, now: 11))
        XCTAssertNil(try authority.state().approval)
    }

    func testSymlinkOversizedOrUnsafeInstructionsCannotBeReviewed() throws {
        let (directory, authority, issuer, review) = try fixture(); defer { try? FileManager.default.removeItem(at: directory) }
        for instructions in [" ", String(repeating: "x", count: 12_289), "\u{1b}[2J"] {
            XCTAssertThrowsError(try LocalApprovalReview(domain: .simulation, candidate: review.candidate, ownerInstructions: instructions))
        }
        let path = directory.appendingPathComponent("local-review-simulation.json")
        try FileManager.default.removeItem(at: path)
        try FileManager.default.createSymbolicLink(at: path, withDestinationURL: directory.appendingPathComponent("authority-simulation.json"))
        XCTAssertThrowsError(try issuer.prepare(owner: UUID(), planSHA256: review.candidate.sha256(), reviewSHA256: review.sha256(), now: 10))
        XCTAssertNil(try authority.state().approval)
        try FileManager.default.removeItem(at: path)
        try Data(repeating: 32, count: 16_385).write(to: path)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path.path)
        XCTAssertThrowsError(try issuer.prepare(owner: UUID(), planSHA256: review.candidate.sha256(), reviewSHA256: review.sha256(), now: 10))
        XCTAssertNil(try authority.state().approval)
    }

    func testNonRootCannotConstructHardwareIssuerOrWriteHardwareReview() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        XCTAssertThrowsError(try LocalApprovalIssuer.hardware(directory: directory))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        XCTAssertThrowsError(try FileSessionJournal(directory: directory).saveLocalReview(Data(), domain: .hardware))
    }
}
