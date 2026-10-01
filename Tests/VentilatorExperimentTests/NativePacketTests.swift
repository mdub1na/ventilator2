import CSMCExperiment
import Darwin
import Foundation
import VentilatorControl
import VentilatorExperiment
import XCTest

final class NativePacketTests: XCTestCase {
    func testNativePacketsMatchEveryReviewedWriteExactly() throws {
        let plan = CandidateExperimentPlan(binaries: .init(applicationSHA256: String(repeating: "a", count: 64),
                                                          helperSHA256: String(repeating: "b", count: 64)))
        let writes = plan.fixedWrites + plan.restoreWrites
        for (index, write) in writes.enumerated() {
            var description = SMCExperimentStep(), request = SMCExperimentRequest()
            XCTAssertEqual(SMCExperimentDescribeStep(UInt32(index), &description), 0)
            let key = withUnsafeBytes(of: description.key) { String(decoding: $0.prefix(4), as: UTF8.self) }
            XCTAssertEqual(key, write.key)
            XCTAssertEqual(description.type, write.dataType.utf8.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) })
            XCTAssertEqual(SMCExperimentBuildRequest(UInt32(index), description.type, description.size, &request), 0)
            let bytes = withUnsafeBytes(of: request.bytes) { Array($0) }
            XCTAssertEqual(bytes.count, 80)
            XCTAssertEqual(bytes[42], 6)
            XCTAssertEqual(bytes[48..<48 + Int(description.size)].map { String(format: "%02x", $0) }.joined(), write.payloadHex)
            XCTAssertTrue(bytes[(48 + Int(description.size))...].allSatisfy { $0 == 0 })
        }
    }

    func testUnknownStepAndWrongMetadataCannotProduceWritePacket() {
        var description = SMCExperimentStep(), request = SMCExperimentRequest()
        XCTAssertNotEqual(SMCExperimentDescribeStep(10, &description), 0)
        XCTAssertNotEqual(SMCExperimentBuildRequest(UInt32.max, 0, 0, &request), 0)
        _ = SMCExperimentDescribeStep(3, &description)
        XCTAssertNotEqual(SMCExperimentBuildRequest(3, 0x66706532, 2, &request), 0) // Intel fpe2 is not accepted.
        XCTAssertNotEqual(SMCExperimentBuildRequest(3, description.type, 8, &request), 0)
        XCTAssertTrue(withUnsafeBytes(of: request.bytes) { $0.allSatisfy { $0 == 0 } })
    }

    func testKernelSMCAndShortRepliesAreDistinctFailures() {
        var reply = SMCExperimentRequest(), result = SMCExperimentResult()
        XCTAssertNotEqual(SMCExperimentValidateReply(-1, 80, &reply, &result), 0)
        XCTAssertEqual(result.kernelStatus, -1)
        XCTAssertNotEqual(SMCExperimentValidateReply(0, 79, &reply, &result), 0)
        withUnsafeMutableBytes(of: &reply.bytes) { $0[40] = 0x82 }
        XCTAssertNotEqual(SMCExperimentValidateReply(0, 80, &reply, &result), 0)
        XCTAssertEqual(result.smcResult, 0x82)
        withUnsafeMutableBytes(of: &reply.bytes) { $0[40] = 0 }
        XCTAssertEqual(SMCExperimentValidateReply(0, 80, &reply, &result), 0)
        withUnsafeMutableBytes(of: &reply.bytes) { $0[41] = 1 }
        XCTAssertNotEqual(SMCExperimentValidateReply(0, 80, &reply, &result), 0)
        XCTAssertEqual(result.smcStatus, 1)
    }

    func testNativeOpenRefusesNonRootBeforeIOKitAndSimulationReceiptsNeverOpenHardware() throws {
        guard geteuid() != 0 else { throw XCTSkip("The non-root gate must be tested by a non-root user") }
        XCTAssertNil(SMCExperimentOpen(1, 0))
        XCTAssertEqual(SMCExperimentOpenPolicyAllows(501, 1, 100, 110, 0), 0)
        XCTAssertEqual(SMCExperimentOpenPolicyAllows(0, 1, 100, 110, 0), 1)
        XCTAssertEqual(SMCExperimentOpenPolicyAllows(0, 0, 100, 110, 0), 0)
        XCTAssertEqual(SMCExperimentOpenPolicyAllows(0, 1, 100, 111, 0), 0)
        XCTAssertEqual(SMCExperimentOpenPolicyAllows(0, 1, 100, 109, 1), 0)
        XCTAssertEqual(SMCExperimentOpenPolicyAllows(0, 1, 100, .nan, 0), 0)
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let authority = try ExperimentAuthority(directory: folder, domain: .simulation)
        XCTAssertThrowsError(try NativeExperimentDevice(authority: authority, sessionID: UUID(), restorationOnly: false)) {
            XCTAssertEqual($0 as? NativeExperimentError, .simulationCannotOpenHardware)
        }
        XCTAssertThrowsError(try ExperimentAuthority(directory: folder, domain: .hardware)) {
            XCTAssertEqual($0 as? ExperimentAuthorityError, .hardwareRequiresRoot)
        }
    }
}
