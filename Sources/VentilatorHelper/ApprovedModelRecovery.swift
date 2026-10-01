import Darwin
import CSystemPower
import Foundation
import VentilatorControl
import VentilatorCore
import VentilatorExperiment

enum ModelRecoveryCase: String, Codable { case normal, hold, sleep, blockedFixed, blockedRestore, restoreFailure }
private enum ModelChildRole: String, Codable { case fixed, restore }
private struct ModelChildBootstrap: Codable {
    let scope: RecoveryScope
    let role: ModelChildRole
    let fault: ModelRecoveryCase
}
private struct ModelChildRequest: Codable {
    let id: UUID
    let scope: RecoveryScope
    let step: ExperimentStep?
}
private struct ModelChildReply: Codable {
    let id: UUID?
    let scope: RecoveryScope
    let role: ModelChildRole
    let pid: Int32
    let error: String?
}
private struct ModelBrokerBootstrap: Codable { let sessionID: UUID; let fault: ModelRecoveryCase }
private enum ModelOwnerCommand: String, Codable { case heartbeat, restore, sleep }
private struct ModelOwnerRequest: Codable { let scope: RecoveryScope; let command: ModelOwnerCommand }
private struct ModelBrokerReady: Codable { let scope: RecoveryScope; let brokerPID: Int32; let writerPID: Int32 }

private func privateChannel() throws -> WorkerChannel {
    var input = stat(), output = stat()
    guard geteuid() != 0, fstat(STDIN_FILENO, &input) == 0, fstat(STDOUT_FILENO, &output) == 0,
          input.st_mode & S_IFMT == S_IFIFO, output.st_mode & S_IFMT == S_IFIFO else {
        throw CheckError.failed("Approved model requires non-root inherited private pipes")
    }
    return try WorkerChannel(input: STDIN_FILENO, output: STDOUT_FILENO)
}

/// Each blocking simulated effect runs outside the broker. No native device is constructed here.
func runApprovedModelChild(directory: URL) throws {
    let channel = try privateChannel()
    guard let initial = try channel.readLine(waitSeconds: 2) else { throw CheckError.failed("Model child bootstrap timeout") }
    let bootstrap = try JSONDecoder().decode(ModelChildBootstrap.self, from: initial)
    let authority = try ExperimentAuthority(directory: directory, domain: .simulation)
    guard let ledger = try authority.state().ledger, bootstrap.scope.domain == .simulation,
          bootstrap.scope.matches(ledger), ledger.pendingRestoration,
          (bootstrap.role == .restore ? ledger.fixedClosed : (!ledger.fixedClosed && ledger.attempts.isEmpty)) else {
        throw CheckError.failed("Model child scope mismatch")
    }
    let device = try FileSimulatedStepDevice(directory: directory, sessionID: ledger.sessionID)
    if bootstrap.fault == .restoreFailure { device.failBeforeStep = .autoZero }
    let executor = try ApprovedStepExecutor(authority: authority, sessionID: ledger.sessionID, device: device)
    try channel.send(ModelChildReply(id: nil, scope: bootstrap.scope, role: bootstrap.role, pid: getpid(), error: nil))
    while true {
        guard let data = try channel.readLine(waitSeconds: 1) else { continue }
        let request = try JSONDecoder().decode(ModelChildRequest.self, from: data)
        guard request.scope == bootstrap.scope else { throw CheckError.failed("Model child request binding") }
        var errorCode: String?
        if let step = request.step {
            guard step.isFixed == (bootstrap.role == .fixed) else { throw CheckError.failed("Model child role violation") }
            do {
                let date = Date()
                let observation = try device.observation(at: date)
                try executor.perform(step, now: HelperClock.now(), date: date, observation: observation)
                if (bootstrap.fault == .blockedFixed && step == .unlock) ||
                    (bootstrap.fault == .blockedRestore && step == .autoZero) {
                    // The attempt and effect are already durable. A SIGKILL must precede any competing writer.
                    while true { Thread.sleep(forTimeInterval: 1) }
                }
            } catch { errorCode = String(describing: error) }
        }
        try channel.send(ModelChildReply(id: request.id, scope: bootstrap.scope, role: bootstrap.role,
                                        pid: getpid(), error: errorCode))
    }
}

private final class ModelChildClient {
    let process = Process()
    private let input = Pipe(), output = Pipe()
    let channel: WorkerChannel
    let bootstrap: ModelChildBootstrap

    init(directory: URL, bootstrap: ModelChildBootstrap) throws {
        self.bootstrap = bootstrap
        channel = try WorkerChannel(input: output.fileHandleForReading.fileDescriptor,
                                    output: input.fileHandleForWriting.fileDescriptor)
        process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        process.arguments = ["--approved-model-child", directory.path]
        process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.standardError
        try process.run()
        try input.fileHandleForReading.close(); try output.fileHandleForWriting.close()
        do {
            try channel.send(bootstrap)
            guard let data = try channel.readLine(waitSeconds: 2) else { throw CheckError.failed("Model child readiness timeout") }
            let ready = try JSONDecoder().decode(ModelChildReply.self, from: data)
            guard ready.id == nil, valid(ready), ready.error == nil else { throw CheckError.failed("Model child readiness binding") }
        } catch { killOwnedChild(); throw error }
    }

    deinit { try? input.fileHandleForWriting.close(); try? output.fileHandleForReading.close() }

    func valid(_ reply: ModelChildReply) -> Bool {
        reply.scope == bootstrap.scope && reply.role == bootstrap.role && reply.pid == process.processIdentifier
    }

    func killOwnedChild() {
        // Only Process instances created by this broker, never a PID supplied by XPC or a process-name match.
        if process.isRunning { _ = Darwin.kill(process.processIdentifier, SIGKILL) }
    }
}

/// Exact approved steps, private IPC, independent observation and quiescence are tested on the file model.
/// Hardware transport and local hardware approval are deliberately not routed through these CLI modes.
func runApprovedModelBroker(directory: URL) throws {
    let ownerChannel = try privateChannel()
    guard let data = try ownerChannel.readLine(waitSeconds: 2) else { throw CheckError.failed("Broker bootstrap timeout") }
    let bootstrap = try JSONDecoder().decode(ModelBrokerBootstrap.self, from: data)
    let journal = try FileSessionJournal(directory: directory)
    let ownership = try journal.acquireRecoveryBrokerLock()
    defer { withExtendedLifetime(ownership) {} }
    let authority = try ExperimentAuthority(directory: directory, domain: .simulation)
    guard let ledger = try authority.state().ledger, ledger.sessionID == bootstrap.sessionID else {
        throw CheckError.failed("Broker ledger binding")
    }
    let monitor = try RecoveryMonitor(ledger: ledger, now: HelperClock.now())
    let device = try FileSimulatedStepDevice(directory: directory, sessionID: ledger.sessionID)
    let baseline = try device.observation(at: Date()).snapshot
    let writer = try ModelChildClient(directory: directory, bootstrap: .init(scope: monitor.scope, role: .fixed, fault: bootstrap.fault))
    var restorer: ModelChildClient?
    defer { writer.killOwnedChild(); restorer?.killOwnedChild() }
    var events = ["writerReady"], failedSteps: [ExperimentStep] = []
    var writerKillSent = false, ownerConnected = true, terminating = false, sleeping = false
    var nextFixed = 0, nextRestore = 0
    var unlockCompletedAt: Double?, nextProbe = HelperClock.now(), fixedObserved = false
    var pendingStep: ExperimentStep?
    var autoSamples: [ControlObservation] = []
    var sleepAcknowledgements: [() -> Void] = []
    let power = SystemPowerObserver(beforeSleep: { acknowledge in
        sleeping = true; sleepAcknowledgements.append(acknowledge)
    })
    defer { sleepAcknowledgements.forEach { $0() } }
    signal(SIGTERM, SIG_IGN)
    let termination = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
    termination.setEventHandler { terminating = true }; termination.resume()
    defer { termination.cancel() }
    try ownerChannel.send(ModelBrokerReady(scope: monitor.scope, brokerPID: getpid(), writerPID: writer.process.processIdentifier))

    while [.fixed, .quiescing, .restoring].contains(monitor.phase) {
        var now = HelperClock.now()
        monitor.tick(now: now)
        if terminating { monitor.stop(reason: "systemShutdown", now: now) }
        if sleeping { monitor.stop(reason: "systemSleep", now: now) }
        if ownerConnected {
            do {
                if let data = try ownerChannel.readLine(waitSeconds: 0) {
                    let request = try JSONDecoder().decode(ModelOwnerRequest.self, from: data)
                    guard request.scope == monitor.scope else { throw CheckError.failed("Broker owner binding") }
                    if request.command == .restore { monitor.stop(reason: "explicitAuto", now: HelperClock.now()) }
                    else if request.command == .sleep {
                        power.handle(message: VentilatorSystemWillSleepMessage()) { events.append("sleepAcknowledged") }
                    }
                    else if monitor.phase == .fixed { try monitor.heartbeat(scope: request.scope, now: HelperClock.now()) }
                }
            } catch { ownerConnected = false; monitor.stop(reason: "helperExited", now: HelperClock.now()) }
        }
        now = HelperClock.now()
        if monitor.phase == .fixed && !writer.process.isRunning { monitor.stop(reason: "writerExited", now: now) }
        if monitor.phase == .quiescing {
            if !writerKillSent {
                do {
                    try authority.closeFixed(sessionID: ledger.sessionID, now: HelperClock.now())
                    events.append("fixedClosed")
                } catch { monitor.fail(reason: "journalClosureFailure") }
                events.append("writerStopRequested"); writer.killOwnedChild(); writerKillSent = true
            }
            // A stop signal or a timeout is not enough: wait for this child's completed termination.
            if monitor.phase == .quiescing && !writer.process.isRunning {
                do {
                    now = HelperClock.now()
                    events.append("writerExited")
                    let closed = try authority.closeFixedAndBeginRestoration(sessionID: ledger.sessionID, now: now, date: Date())
                    try monitor.confirmWriterExited(now: HelperClock.now(), restorationStartedAt: closed.restoreStartedAt)
                    events.append("restorationStarted")
                    pendingStep = nil
                    restorer = try ModelChildClient(directory: directory, bootstrap: .init(scope: monitor.scope, role: .restore, fault: bootstrap.fault))
                    events.append("restorerReady")
                } catch { monitor.fail(reason: "restorationSetupFailure") }
            }
        }

        if [.fixed, .restoring].contains(monitor.phase) {
            let child = monitor.phase == .fixed ? writer : restorer!
            do {
                if let data = try child.channel.readLine(waitSeconds: 0) {
                    let reply = try JSONDecoder().decode(ModelChildReply.self, from: data)
                    guard child.valid(reply), let id = reply.id else { throw CheckError.failed("Broker child reply binding") }
                    try monitor.acknowledge(id: id, scope: reply.scope, now: HelperClock.now())
                    if let step = pendingStep {
                        if reply.error != nil {
                            failedSteps.append(step)
                            if step.isFixed { monitor.stop(reason: "writerFailure", now: HelperClock.now()) }
                        } else if step == .unlock { unlockCompletedAt = HelperClock.now() }
                    }
                    pendingStep = nil
                }
            } catch {
                if monitor.phase == .fixed { monitor.stop(reason: "writerChannelFailure", now: HelperClock.now()) }
                else { monitor.fail(reason: "restorerChannelFailure") }
            }
            if monitor.phase == .restoring && !child.process.isRunning { monitor.fail(reason: "restorerExited") }
        }

        now = HelperClock.now()
        if monitor.phase == .fixed {
            do {
                let observation = try device.observation(at: Date())
                if nextFixed == 5 && ExperimentVerification.fixedRPMConfirmed(baseline: baseline, observed: observation.snapshot) {
                    if !fixedObserved { events.append("fixedRPMObserved") }
                    fixedObserved = true
                } else if fixedObserved || now >= ledger.startedAt + 5 {
                    monitor.stop(reason: "fixedNotObserved", now: now)
                }
                if monitor.pendingOperation == nil && monitor.phase == .fixed {
                    let step: ExperimentStep?
                    if nextFixed == 0 { step = .unlock }
                    else if nextFixed < 5, let completed = unlockCompletedAt, now >= completed + 3 {
                        step = ExperimentStep(rawValue: UInt32(nextFixed))
                    } else { step = nil }
                    if step != nil || now >= nextProbe {
                        let id = UUID()
                        try monitor.beginOperation(id: id, now: now)
                        try writer.channel.send(ModelChildRequest(id: id, scope: monitor.scope, step: step))
                        pendingStep = step
                        if step != nil { nextFixed += 1 }
                        nextProbe = now + 0.25
                    }
                }
            } catch { monitor.stop(reason: "writerFailure", now: HelperClock.now()) }
        }

        if monitor.phase == .restoring {
            do {
                if monitor.pendingOperation == nil && nextRestore < 5 {
                    let step = ExperimentStep(rawValue: UInt32(5 + nextRestore))!, id = UUID()
                    try monitor.beginOperation(id: id, now: HelperClock.now())
                    try restorer!.channel.send(ModelChildRequest(id: id, scope: monitor.scope, step: step))
                    events.append("autoStep\(step.rawValue)Requested")
                    pendingStep = step; nextRestore += 1
                } else if monitor.pendingOperation == nil && nextRestore == 5 {
                    let date = Date(), observation = try device.observation(at: date)
                    if autoSamples.last.map({ date.timeIntervalSince($0.snapshot.sampledAt) >= 1 }) ?? true {
                        autoSamples.append(observation)
                    }
                    if autoSamples.count >= 3 {
                        guard !failedSteps.contains(where: { !$0.isFixed }) else { monitor.fail(reason: "restoreStepFailure"); continue }
                        // The final acknowledgement is received; close the sole Auto child before clearing the model marker.
                        restorer!.killOwnedChild()
                        let exitDeadline = min(HelperClock.now() + 1, monitor.restorationStartedAt! + 8)
                        while restorer!.process.isRunning, HelperClock.now() < exitDeadline {
                            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
                        }
                        guard !restorer!.process.isRunning else { throw CheckError.failed("Auto child did not exit") }
                        events.append("restorerExited")
                        try authority.finishObservedRestoration(sessionID: ledger.sessionID, samples: autoSamples, now: HelperClock.now(), date: date)
                        try monitor.observeAutoCodes(now: HelperClock.now())
                        events.append("autoCodesObserved")
                    }
                }
            } catch { monitor.fail(reason: "restorationVerificationFailure") }
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
    }
    // End the scoped Auto child too, then persist the result. Never retry an attempted step.
    restorer?.killOwnedChild()
    let exitDeadline = HelperClock.now() + 1
    while restorer?.process.isRunning == true, HelperClock.now() < exitDeadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
    }
    if restorer?.process.isRunning == true { monitor.fail(reason: "restorerNotQuiescent") }
    sleepAcknowledgements.forEach { $0() }; sleepAcknowledgements.removeAll()
    try journal.saveRecoveryOutcome(.init(sessionID: ledger.sessionID, phase: monitor.phase.rawValue,
        reason: monitor.reason, events: events, failedSteps: failedSteps, elapsedSeconds: HelperClock.now() - ledger.startedAt,
        powerNotificationsRegistered: power.registered))
    withExtendedLifetime(power) {}
}

/// A harness proxy supplies heartbeat while the dedicated broker owns the experiment model.
func runApprovedModelParent(directory: URL, fault: ModelRecoveryCase) throws {
    guard geteuid() != 0 else { throw CheckError.failed("Recovery model must run without root") }
    let journal = try FileSessionJournal(directory: directory)
    guard try journal.loadSimulationDevice() == nil, try journal.loadAuthorityState(domain: .simulation) == nil else {
        throw CheckError.failed("Model directory already used")
    }
    try journal.saveSimulationDevice(SimulationDeviceState())
    let authority = try ExperimentAuthority(directory: directory, domain: .simulation)
    let plan = try bundledCandidatePlan(), owner = UUID(), boot = UUID()
    let challenge = try authority.prepare(owner: owner, plan: plan, boot: boot, now: HelperClock.now())
    try authority.approveLocally(challengeID: challenge.id, planSHA256: plan.sha256(), boot: boot, now: HelperClock.now())
    let baseline = SimulatedStepDevice(), date = Date()
    let ledger = try authority.begin(owner: owner, challengeID: challenge.id, plan: plan, binaries: plan.binaries,
        boot: boot, now: HelperClock.now(), observation: baseline.observation(at: date), date: date)
    let process = Process(), input = Pipe(), output = Pipe()
    let channel = try WorkerChannel(input: output.fileHandleForReading.fileDescriptor, output: input.fileHandleForWriting.fileDescriptor)
    process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
    process.arguments = ["--approved-model-broker", directory.path]
    process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.standardError
    try process.run()
    try input.fileHandleForReading.close(); try output.fileHandleForWriting.close()
    defer { try? input.fileHandleForWriting.close(); try? output.fileHandleForReading.close() }
    try channel.send(ModelBrokerBootstrap(sessionID: ledger.sessionID, fault: fault))
    guard let data = try channel.readLine(waitSeconds: 2) else { throw CheckError.failed("Recovery broker readiness timeout") }
    let ready = try JSONDecoder().decode(ModelBrokerReady.self, from: data)
    guard ready.scope.matches(ledger), ready.brokerPID == process.processIdentifier else { throw CheckError.failed("Recovery broker readiness binding") }
    print(String(decoding: try JSONEncoder().encode(ready), as: UTF8.self)); fflush(stdout)
    var nextHeartbeat = HelperClock.now(), restoreSent = false
    while process.isRunning {
        let now = HelperClock.now()
        if !restoreSent, [.normal, .sleep].contains(fault), try journal.loadSimulationDevice()?.effects.contains(.targetOne) == true {
            try channel.send(ModelOwnerRequest(scope: ready.scope, command: fault == .sleep ? .sleep : .restore)); restoreSent = true
        } else if now >= nextHeartbeat && !restoreSent {
            try? channel.send(ModelOwnerRequest(scope: ready.scope, command: .heartbeat)); nextHeartbeat = now + 0.25
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
    }
    guard process.terminationStatus == 0, try journal.loadRecoveryOutcome() != nil else {
        throw CheckError.failed("Recovery broker failed")
    }
}
