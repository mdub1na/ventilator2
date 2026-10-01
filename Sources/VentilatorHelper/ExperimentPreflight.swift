import Darwin
import Foundation
import VentilatorControl
import VentilatorExperiment

private struct PreflightRequest: Codable {
    let nonce: UUID
    let domain: ExperimentDomain
    let deadline: Double
}
private struct PreflightReply: Codable {
    let nonce: UUID
    let domain: ExperimentDomain
    let pid: Int32
    let observation: BrokerObservation
}

/// A separate read-only process can be killed without consuming approval or blocking a broker timer.
func experimentPreflight(domain: ExperimentDomain) throws -> ControlObservation {
    let process = Process(), input = Pipe(), output = Pipe()
    let channel = try WorkerChannel(input: output.fileHandleForReading.fileDescriptor,
                                    output: input.fileHandleForWriting.fileDescriptor)
    let nonce = UUID(), date = Date(), deadline = HelperClock.now() + 2
    process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
    process.arguments = [domain == .hardware ? "--hardware-preflight-child" : "--model-preflight-child"]
    process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.standardError
    try process.run()
    try input.fileHandleForReading.close(); try output.fileHandleForWriting.close()
    defer {
        if process.isRunning { _ = Darwin.kill(process.processIdentifier, SIGKILL) }
        try? input.fileHandleForWriting.close(); try? output.fileHandleForReading.close()
    }
    try channel.send(PreflightRequest(nonce: nonce, domain: domain, deadline: deadline), deadline: deadline)
    guard let data = try channel.readLine(waitSeconds: max(0, deadline - HelperClock.now())) else {
        throw CheckError.failed("Preflight timeout; approval not consumed")
    }
    let response = try JSONDecoder().decode(PreflightReply.self, from: data)
    guard response.nonce == nonce, response.domain == domain, response.pid == process.processIdentifier else {
        throw CheckError.failed("Preflight binding")
    }
    while process.isRunning, HelperClock.now() < deadline { Thread.sleep(forTimeInterval: 0.01) }
    guard !process.isRunning, process.terminationStatus == 0 else { throw CheckError.failed("Preflight exit timeout") }
    return try response.observation.admitted(requestedAt: date, deadline: deadline, now: HelperClock.now(), date: Date())
}

func runPreflightChild(domain: ExperimentDomain) throws {
    let channel = try privateExperimentChannel(domain: domain)
    if domain == .hardware { _ = try HardwareRecoveryIdentity.currentBoot() }
    guard let data = try channel.readLine(waitSeconds: 0.5) else { throw CheckError.failed("Preflight bootstrap timeout") }
    let request = try JSONDecoder().decode(PreflightRequest.self, from: data)
    guard request.domain == domain, request.deadline.isFinite,
          HelperClock.now() < request.deadline, request.deadline <= HelperClock.now() + 2 else {
        throw CheckError.failed("Preflight deadline/domain")
    }
    let sample: TimedExperimentObservation
    if domain == .hardware { sample = try ReadOnlyExperimentObserver.native().sample() }
    else {
        let start = HelperClock.now()
        sample = .init(observation: SimulatedStepDevice().observation(at: Date()), readSeconds: HelperClock.now() - start)
    }
    try channel.send(PreflightReply(nonce: request.nonce, domain: domain, pid: getpid(), observation: .init(sample)), deadline: request.deadline)
}
