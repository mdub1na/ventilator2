import Darwin
import Foundation
import VentilatorControl
@testable import VentilatorExperiment
import XCTest

final class RecoveryProbeTests: XCTestCase {
    private func scope() throws -> (URL, ApprovedExperimentLedger, RecoveryScope) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let authority = try ExperimentAuthority(directory: directory, domain: .simulation)
        let plan = CandidateExperimentPlan(binaries: .init(applicationSHA256: String(repeating: "a", count: 64), helperSHA256: String(repeating: "b", count: 64)))
        let owner = UUID(), boot = UUID(), now = ExperimentMonotonicClock.now(), date = Date()
        let challenge = try authority.prepare(owner: owner, plan: plan, boot: boot, now: now)
        try authority.approveLocally(challengeID: challenge.id, planSHA256: plan.sha256(), boot: boot, now: now)
        let device = SimulatedStepDevice()
        let ledger = try authority.begin(owner: owner, challengeID: challenge.id, plan: plan, binaries: plan.binaries,
            boot: boot, now: now, observation: device.observation(at: date), date: date)
        return (directory, ledger, RecoveryScope(ledger: ledger))
    }

    private struct Pipes {
        let input: [Int32], output: [Int32]
        init() throws {
            var input: [Int32] = [0, 0], output: [Int32] = [0, 0]
            guard pipe(&input) == 0 else { throw RecoveryProbeError.invalidPipe }
            guard pipe(&output) == 0 else { close(input[0]); close(input[1]); throw RecoveryProbeError.invalidPipe }
            self.input = input; self.output = output
        }
        func closeAll() { for descriptor in input + output { close(descriptor) } }
    }

    // The peer runs only a private-pipe echo loop on a model scope. No hardware witness is constructed.
    private func peer(input: Int32, output: Int32, replyMode: String, count: Int = 1) -> XCTestExpectation {
        let completed = expectation(description: "Model recovery peer exited")
        Thread {
            defer { completed.fulfill() }
            for _ in 0..<count {
                var buffer = Data(), item = pollfd(fd: input, events: Int16(POLLIN), revents: 0)
                guard Darwin.poll(&item, 1, 1500) > 0 else { return }
                while buffer.last != 10 {
                    var byte: UInt8 = 0
                    guard Darwin.read(input, &byte, 1) == 1 else { return }
                    buffer.append(byte)
                    guard buffer.count < 1024 else { return }
                }
                guard let request = try? JSONDecoder().decode(RecoveryProbeRequest.self, from: buffer.dropLast()) else { return }
                if replyMode == "silent" { return }
                let reply = RecoveryProbeReply(id: replyMode == "wrongID" ? UUID() : request.id, scope: request.scope,
                    phase: replyMode == "stopping" ? .quiescing : .fixed,
                    deadline: request.deadline + (replyMode == "extend" ? 1 : 0))
                guard var data = try? JSONEncoder().encode(reply) else { return }
                if replyMode == "wrongScope" {
                    guard var object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                          var scope = object["scope"] as? [String: Any] else { return }
                    scope["domain"] = "hardware"; object["scope"] = scope
                    guard let altered = try? JSONSerialization.data(withJSONObject: object) else { return }
                    data = altered
                }
                if replyMode == "oversized" { data = Data(repeating: 65, count: 1100) }
                data.append(10)
                data.withUnsafeBytes { bytes in _ = Darwin.write(output, bytes.baseAddress, bytes.count) }
            }
        }.start()
        return completed
    }

    func testFreshBoundAcknowledgementOnEachProbeAndModelCannotArmHardware() throws {
        let (directory, ledger, scope) = try scope(); defer { try? FileManager.default.removeItem(at: directory) }
        let pipes = try Pipes(); defer { pipes.closeAll() }
        let completed = peer(input: pipes.output[0], output: pipes.input[1], replyMode: "valid", count: 2)
        let client = try RecoveryProbeClient(scope: scope, phase: .fixed, deadline: scope.expiresAt,
            input: pipes.input[0], output: pipes.output[1])
        try client.confirm(); try client.confirm()
        XCTAssertThrowsError(try ArmedHardwareRecovery(session: ledger, role: .fixed, probe: client)) {
            XCTAssertEqual($0 as? NativeExperimentError, .recoveryNotArmed)
        }
        wait(for: [completed], timeout: 2)
    }

    func testWrongReplyBindingDeadlineOrPhasePermanentlyInvalidatesProbe() throws {
        let (directory, _, scope) = try scope(); defer { try? FileManager.default.removeItem(at: directory) }
        for mode in ["wrongID", "wrongScope", "extend", "stopping", "oversized"] {
            let pipes = try Pipes(); defer { pipes.closeAll() }
            let completed = peer(input: pipes.output[0], output: pipes.input[1], replyMode: mode)
            let client = try RecoveryProbeClient(scope: scope, phase: .fixed, deadline: scope.expiresAt,
                input: pipes.input[0], output: pipes.output[1])
            XCTAssertThrowsError(try client.confirm())
            XCTAssertThrowsError(try client.confirm()) { XCTAssertEqual($0 as? RecoveryProbeError, .closed) }
            wait(for: [completed], timeout: 2)
        }
    }

    func testStoppedPeerTimesOutWithoutAWriteRetry() throws {
        let (directory, _, scope) = try scope(); defer { try? FileManager.default.removeItem(at: directory) }
        let pipes = try Pipes(); defer { pipes.closeAll() }
        let completed = peer(input: pipes.output[0], output: pipes.input[1], replyMode: "silent")
        let client = try RecoveryProbeClient(scope: scope, phase: .fixed, deadline: scope.expiresAt,
            input: pipes.input[0], output: pipes.output[1])
        let start = ExperimentMonotonicClock.now()
        XCTAssertThrowsError(try client.confirm()) { XCTAssertEqual($0 as? RecoveryProbeError, .timeout) }
        XCTAssertLessThan(ExperimentMonotonicClock.now() - start, 1)
        XCTAssertThrowsError(try client.confirm()) { XCTAssertEqual($0 as? RecoveryProbeError, .closed) }
        wait(for: [completed], timeout: 2)
    }

    func testClosedPipeDoesNotSendSIGPIPEToTheProcess() throws {
        let (directory, _, scope) = try scope(); defer { try? FileManager.default.removeItem(at: directory) }
        let pipes = try Pipes()
        let client = try RecoveryProbeClient(scope: scope, phase: .fixed, deadline: scope.expiresAt,
            input: pipes.input[0], output: pipes.output[1])
        close(pipes.output[0]); close(pipes.output[1]); close(pipes.input[0]); close(pipes.input[1])
        XCTAssertThrowsError(try client.confirm()) { XCTAssertEqual($0 as? RecoveryProbeError, .closed) }
    }

    func testRegularFileAndInvalidClockCannotBecomeARecoveryChannel() throws {
        let (directory, _, scope) = try scope(); defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("ordinary.json")
        try Data().write(to: file)
        let handle = try FileHandle(forReadingFrom: file); defer { try? handle.close() }
        let pipes = try Pipes(); defer { pipes.closeAll() }
        XCTAssertThrowsError(try RecoveryProbeClient(scope: scope, phase: .fixed, deadline: scope.expiresAt,
            input: handle.fileDescriptor, output: pipes.output[1]))
        XCTAssertThrowsError(try RecoveryProbeClient(scope: scope, phase: .fixed, deadline: scope.expiresAt,
            input: pipes.input[0], output: pipes.output[1], clock: { .nan }))
    }
}
