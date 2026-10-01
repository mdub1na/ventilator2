import Foundation
import XCTest
@testable import VentilatorControl

final class CandidateExperimentPlanTests: XCTestCase {
    private let binaries = CandidateExperimentPlan.Binaries(applicationSHA256: String(repeating: "a", count: 64),
                                                             helperSHA256: String(repeating: "b", count: 64))
    private let date = Date(timeIntervalSince1970: 1000)

    func testReviewBindsBinaryAndExactRangesWithoutGrantingApproval() throws {
        let plan = CandidateExperimentPlan(binaries: binaries)
        let transport = SimulatedFanTransport()
        XCTAssertTrue(plan.matchesCandidate(binaries: binaries, observation: try transport.read(at: date), now: date))
        XCTAssertFalse(plan.readyForOwnerApproval)
        let replaced = CandidateExperimentPlan.Binaries(applicationSHA256: binaries.applicationSHA256,
                                                       helperSHA256: String(repeating: "c", count: 64))
        XCTAssertFalse(plan.matchesCandidate(binaries: replaced, observation: try transport.read(at: date), now: date))
        transport.ranges[0].0 = 1400
        XCTAssertFalse(plan.matchesCandidate(binaries: binaries, observation: try transport.read(at: date), now: date))
    }

    func testChangedWriteOrLeaseOrReadinessIsRejectedAndChangesDigest() throws {
        let original = CandidateExperimentPlan(binaries: binaries)
        for field in ["write", "lease", "approval"] {
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: original.canonicalJSON()) as? [String: Any])
            switch field {
            case "lease": object["leaseSeconds"] = 60
            case "approval": object["readyForOwnerApproval"] = true
            default:
                var writes = try XCTUnwrap(object["fixedWrites"] as? [[String: Any]])
                writes[0]["key"] = "FS! "
                object["fixedWrites"] = writes
            }
            let changed = try JSONDecoder().decode(CandidateExperimentPlan.self, from: JSONSerialization.data(withJSONObject: object))
            XCTAssertNotEqual(try original.sha256(), try changed.sha256())
            XCTAssertFalse(changed.matchesCandidate(binaries: binaries, observation: try SimulatedFanTransport().read(at: date), now: date))
        }
    }

    func testCanonicalHashSurvivesSerializationOrderAndCandidateListsAllWrites() throws {
        let original = CandidateExperimentPlan(binaries: binaries)
        let decoded = try JSONDecoder().decode(CandidateExperimentPlan.self, from: JSONEncoder().encode(original))
        XCTAssertEqual(try original.sha256(), try decoded.sha256())
        XCTAssertEqual(original.fixedWrites.count, 5)
        XCTAssertEqual(original.restoreWrites.count, 5)
        XCTAssertTrue((original.fixedWrites + original.restoreWrites).allSatisfy { $0.maximumAttempts == 1 })
        let target = try XCTUnwrap(original.fixedWrites.first { $0.key == "F0Tg" })
        let bytes = stride(from: 0, to: target.payloadHex.count, by: 2).map { offset -> UInt8 in
            let start = target.payloadHex.index(target.payloadHex.startIndex, offsetBy: offset)
            let end = target.payloadHex.index(start, offsetBy: 2)
            return UInt8(target.payloadHex[start..<end], radix: 16)!
        }
        let bits = bytes.enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << ($1.offset * 8) }
        XCTAssertEqual(Float(bitPattern: bits), 2500)
    }
}
