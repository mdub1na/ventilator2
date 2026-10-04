import Foundation
import XCTest
@testable import VentilatorInstallation

final class OwnerExperimentTerminalTests: XCTestCase {
    func testOnlyCompleteStartLineProducesChallengeForRPC() throws {
        let challenge = UUID()
        XCTAssertEqual(try OwnerExperimentTerminal.startChallenge(from: OwnerExperimentTerminal.startLine(challenge: challenge)), challenge)
        for input in [nil, "START", "APPROVE", "APPROVE \(challenge.uuidString)", "START \(challenge.uuidString) extra", "CANCEL", " START \(challenge.uuidString)"] {
            XCTAssertThrowsError(try OwnerExperimentTerminal.startChallenge(from: input)) {
                XCTAssertEqual($0 as? InstallationError, .invalidChallenge)
            }
        }
    }
}
