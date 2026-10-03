import Darwin
import Foundation
import VentilatorInstallation
import VentilatorControl
import VentilatorExperiment

enum ModelRecoveryCase: String, Codable { case normal, hold, sleep, delayedAutoZero, blockedFixed, blockedRestore, restoreFailure, blockedReader, readerFailure, blockedAutoReader, earlyAutoReaderFailure, stoppedAuthorityTransaction }

/// A harness proxy supplies heartbeat while the dedicated broker owns the experiment model.
func runApprovedModelParent(directory: URL, fault: ModelRecoveryCase) throws {
    guard geteuid() != 0 else { throw CheckError.failed("Recovery model must run without root") }
    let journal = try FileSessionJournal(directory: directory)
    guard try journal.loadSimulationDevice() == nil, try journal.loadAuthorityState(domain: .simulation)?.ledger == nil else {
        throw CheckError.failed("Model directory already used")
    }
    let authority = try ExperimentAuthority(directory: directory, domain: .simulation)
    let plan = try bundledCandidatePlan()
    let challenge: OwnerApprovalChallenge
    if let approval = try authority.state().approval {
        guard approval.domain == .simulation, approval.challenge.planSHA256 == (try plan.sha256()),
              approval.challenge.binaries == plan.binaries else { throw CheckError.failed("Local model approval binding") }
        challenge = approval.challenge
    } else {
        // Legacy fault harness only. A saved local receipt follows the same consuming begin path below.
        challenge = try authority.prepare(owner: UUID(), plan: plan, boot: UUID(), now: HelperClock.now())
        try authority.approveLocally(challengeID: challenge.id, planSHA256: plan.sha256(), boot: challenge.bootSession, now: HelperClock.now())
    }
    let baseline = SimulatedStepDevice(), date = Date()
    let ledger = try authority.begin(owner: challenge.connectionOwner, challengeID: challenge.id, plan: plan, binaries: plan.binaries,
        boot: challenge.bootSession, now: HelperClock.now(), observation: baseline.observation(at: date), date: date)
    try journal.saveSimulationDevice(SimulationDeviceState())
    let process = Process(), input = Pipe(), output = Pipe()
    let channel = try WorkerChannel(input: output.fileHandleForReading.fileDescriptor, output: input.fileHandleForWriting.fileDescriptor)
    process.executableURL = try CurrentExecutable.url()
    process.arguments = ["--approved-model-broker", directory.path]
    process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.standardError
    try process.run()
    try input.fileHandleForReading.close(); try output.fileHandleForWriting.close()
    defer { try? input.fileHandleForWriting.close(); try? output.fileHandleForReading.close() }
    try channel.send(BrokerBootstrap(sessionID: ledger.sessionID, fault: fault))
    guard let data = try channel.readLine(waitSeconds: 2) else { throw CheckError.failed("Recovery broker readiness timeout") }
    let ready = try JSONDecoder().decode(BrokerReady.self, from: data)
    guard ready.scope.matches(ledger), ready.brokerPID == process.processIdentifier else { throw CheckError.failed("Recovery broker readiness binding") }
    print(String(decoding: try JSONEncoder().encode(ready), as: UTF8.self)); fflush(stdout)
    var nextHeartbeat = HelperClock.now(), restoreSent = false
    while process.isRunning {
        let now = HelperClock.now()
        if let data = try? channel.readLine(waitSeconds: 0),
           let event = try? JSONDecoder().decode(BrokerProcessEvent.self, from: data), event.scope == ready.scope {
            print(String(decoding: try JSONEncoder().encode(event), as: UTF8.self)); fflush(stdout)
        }
        if !restoreSent, [.normal, .sleep, .delayedAutoZero].contains(fault), try journal.loadSimulationDevice()?.effects.contains(.targetOne) == true {
            try channel.send(BrokerOwnerRequest(scope: ready.scope, command: fault == .sleep ? .sleep : .restore)); restoreSent = true
        } else if now >= nextHeartbeat && !restoreSent {
            try? channel.send(BrokerOwnerRequest(scope: ready.scope, command: .heartbeat)); nextHeartbeat = now + 0.25
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
    }
    guard process.terminationStatus == 0, try journal.loadRecoveryOutcome() != nil else {
        throw CheckError.failed("Recovery broker failed")
    }
}
