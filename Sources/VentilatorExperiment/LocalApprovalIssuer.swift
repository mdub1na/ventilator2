import Darwin
import Foundation
import ServiceManagement
import VentilatorControl

public enum LocalApprovalError: Error, Equatable {
    case reviewMissing, reviewMismatch, invalidInstructions, declined, installationNotEnabled
}

/// Full owner-session instructions and the exact candidate are reviewed together. This does not
/// enable public hardware start; the candidate readiness flag remains false until installed gates pass.
public struct LocalApprovalReview: Codable {
    public let domain: ExperimentDomain
    public let candidate: CandidateExperimentPlan
    public let ownerInstructions: String

    public init(domain: ExperimentDomain, candidate: CandidateExperimentPlan, ownerInstructions: String) throws {
        self.domain = domain; self.candidate = candidate; self.ownerInstructions = ownerInstructions
        try validate(domain: domain, binaries: candidate.binaries)
    }
    public func canonicalJSON() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
    public func sha256() throws -> String { CandidateExperimentPlan.digest(try canonicalJSON()) }
    internal func validate(domain: ExperimentDomain, binaries: CandidateExperimentPlan.Binaries) throws {
        guard self.domain == domain, candidate == CandidateExperimentPlan(binaries: binaries) else { throw LocalApprovalError.reviewMismatch }
        guard !ownerInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              ownerInstructions.utf8.count <= 8192,
              ownerInstructions.unicodeScalars.allSatisfy({ $0.value == 10 || $0.value == 9 || !CharacterSet.controlCharacters.contains($0) }) else {
            throw LocalApprovalError.invalidInstructions
        }
    }
}

public struct LocalApprovalPrompt {
    public let challenge: OwnerApprovalChallenge
    public let review: LocalApprovalReview
    public var confirmation: String {
        "APPROVE \(challenge.id.uuidString) \(challenge.planSHA256) \(challenge.ownerReviewSHA256!)"
    }
}

/// No XPC issuer. Hardware construction/confirmation recheck root TTY, signatures, exact profile,
/// installed registration, binaries and boot. Only the non-root simulation factory has injected identity.
public final class LocalApprovalIssuer {
    private struct Identity { let binaries: CandidateExperimentPlan.Binaries; let boot: UUID }
    private let authority: ExperimentAuthority
    private let journal: FileSessionJournal
    private let identity: () throws -> Identity

    private init(authority: ExperimentAuthority, identity: @escaping () throws -> Identity) throws {
        self.authority = authority; self.identity = identity
        journal = try FileSessionJournal(directory: authority.directory)
    }
    public static func simulation(authority: ExperimentAuthority, binaries: CandidateExperimentPlan.Binaries,
                                  boot: UUID) throws -> LocalApprovalIssuer {
        guard authority.domain == .simulation, geteuid() != 0 else { throw NativeExperimentError.simulationCannotOpenHardware }
        return try .init(authority: authority, identity: { .init(binaries: binaries, boot: boot) })
    }
    public static func hardware(directory: URL) throws -> LocalApprovalIssuer {
        _ = try hardwareIdentity()
        return try .init(authority: ExperimentAuthority(directory: directory, domain: .hardware), identity: hardwareIdentity)
    }
    private static func hardwareIdentity() throws -> Identity {
        guard geteuid() == 0, isatty(STDIN_FILENO) == 1, isatty(STDOUT_FILENO) == 1 else {
            throw ExperimentAuthorityError.localTerminalRequired
        }
        guard trustedHelperAndApplication(), ExperimentMachine.current() == .candidate else { throw NativeExperimentError.untrustedSignature }
        guard SMAppService.daemon(plistName: "dev.ventilator.helper.plist").status == .enabled else {
            throw LocalApprovalError.installationNotEnabled
        }
        guard let boot = currentBootSession() else { throw NativeExperimentError.wrongBootSession }
        let helper = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        let application = helper.deletingLastPathComponent().appendingPathComponent("Ventilator")
        let binaries = CandidateExperimentPlan.Binaries(applicationSHA256: CandidateExperimentPlan.digest(try Data(contentsOf: application)),
            helperSHA256: CandidateExperimentPlan.digest(try Data(contentsOf: helper)))
        return .init(binaries: binaries, boot: boot)
    }
    private func review(expectedSHA256: String, current: Identity) throws -> LocalApprovalReview {
        guard let data = try journal.loadLocalReview(domain: authority.domain) else { throw LocalApprovalError.reviewMissing }
        let review = try JSONDecoder().decode(LocalApprovalReview.self, from: data)
        try review.validate(domain: authority.domain, binaries: current.binaries)
        guard try review.sha256() == expectedSHA256 else { throw LocalApprovalError.reviewMismatch }
        return review
    }
    public func prepare(owner: UUID, planSHA256: String, reviewSHA256: String, now: Double) throws -> LocalApprovalPrompt {
        let current = try identity(), review = try review(expectedSHA256: reviewSHA256, current: current)
        guard try review.candidate.sha256() == planSHA256 else { throw LocalApprovalError.reviewMismatch }
        let challenge = try authority.prepare(owner: owner, plan: review.candidate, boot: current.boot, now: now,
            ownerReviewSHA256: reviewSHA256)
        return .init(challenge: challenge, review: review)
    }
    public func confirm(_ prompt: LocalApprovalPrompt, response: String?, now: Double) throws {
        guard response == prompt.confirmation else { throw LocalApprovalError.declined }
        let current = try identity()
        guard current.boot == prompt.challenge.bootSession, current.binaries == prompt.challenge.binaries,
              let reviewSHA = prompt.challenge.ownerReviewSHA256 else { throw LocalApprovalError.reviewMismatch }
        _ = try review(expectedSHA256: reviewSHA, current: current)
        try authority.approveLocally(challengeID: prompt.challenge.id, planSHA256: prompt.challenge.planSHA256,
            boot: current.boot, now: now, ownerReviewSHA256: reviewSHA)
    }
}
