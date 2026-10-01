import Foundation

public enum LocalApprovalError: Error, Equatable {
    case reviewMissing, reviewMismatch, invalidInstructions, declined, installationNotEnabled
}

/// Full owner-session instructions and the exact candidate are reviewed together. This does not
/// changes product readiness; native admission still requires local approval and installed gates.
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
    public func validate(domain: ExperimentDomain, binaries: CandidateExperimentPlan.Binaries) throws {
        guard self.domain == domain, candidate == CandidateExperimentPlan(binaries: binaries) else { throw LocalApprovalError.reviewMismatch }
        guard !ownerInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              ownerInstructions.utf8.count <= 12_288,
              ownerInstructions.unicodeScalars.allSatisfy({ $0.value == 10 || $0.value == 9 || !CharacterSet.controlCharacters.contains($0) }) else {
            throw LocalApprovalError.invalidInstructions
        }
    }
}
