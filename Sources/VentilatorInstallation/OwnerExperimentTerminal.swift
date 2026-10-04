import Foundation

/// Terminal A only parses the start line printed by the successful local issuer in Terminal B.
public enum OwnerExperimentTerminal {
    public static func startChallenge(from line: String?) throws -> UUID {
        guard let line, line.hasPrefix("START "),
              let challenge = UUID(uuidString: String(line.dropFirst(6))) else {
            throw InstallationError.invalidChallenge
        }
        return challenge
    }

    public static func startLine(challenge: UUID) -> String { "START \(challenge.uuidString)" }
}
