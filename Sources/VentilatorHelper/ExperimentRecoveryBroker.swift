import Darwin
import CSystemPower
import Foundation
import VentilatorControl
import VentilatorCore
import VentilatorExperiment

private struct BrokerChildBootstrap: Codable {
    let scope: RecoveryScope
    let role: ExperimentChildRole
    let fault: ModelRecoveryCase
    let phase: RecoveryPhase
}
private struct BrokerChildRequest: Codable {
    let id: UUID
    let scope: RecoveryScope
    let step: ExperimentStep?
    let deadline: Double
}
private struct BrokerChildReply: Codable {
    let id: UUID?
    let scope: RecoveryScope
    let role: ExperimentChildRole
    let pid: Int32
    let error: String?
    let observation: BrokerObservation?
}
struct BrokerBootstrap: Codable {
    let sessionID: UUID
    let fault: ModelRecoveryCase
    let restarting: Bool
    let modelBootSession: UUID?
    init(sessionID: UUID, fault: ModelRecoveryCase, restarting: Bool = false, modelBootSession: UUID? = nil) {
        self.sessionID = sessionID; self.fault = fault; self.restarting = restarting; self.modelBootSession = modelBootSession
    }
}
enum BrokerOwnerCommand: String, Codable { case heartbeat, restore, sleep }
struct BrokerOwnerRequest: Codable { let scope: RecoveryScope; let command: BrokerOwnerCommand }
struct BrokerReady: Codable { let scope: RecoveryScope; let brokerPID: Int32; let writerPID: Int32; let readerPID: Int32; let restorerPID: Int32? }
struct BrokerProcessEvent: Codable {
    let scope: RecoveryScope; let role: ExperimentChildRole; let pid: Int32
    let fixedRPMObserved: Bool
    init(scope: RecoveryScope, role: ExperimentChildRole, pid: Int32, fixedRPMObserved: Bool = false) {
        self.scope = scope; self.role = role; self.pid = pid; self.fixedRPMObserved = fixedRPMObserved
    }
}

func privateExperimentChannel(domain: ExperimentDomain = .simulation) throws -> WorkerChannel {
    var input = stat(), output = stat()
    guard (domain == .hardware ? geteuid() == 0 : geteuid() != 0), fstat(STDIN_FILENO, &input) == 0, fstat(STDOUT_FILENO, &output) == 0,
          input.st_mode & S_IFMT == S_IFIFO, output.st_mode & S_IFMT == S_IFIFO else {
        throw CheckError.failed("Child requires inherited private pipes and the domain's exact UID class")
    }
    return try WorkerChannel(input: STDIN_FILENO, output: STDOUT_FILENO)
}

/// Private child entry points share the same broker protocol. Local approval does not start hardware.
func runApprovedModelChild(directory: URL) throws { try runExperimentChild(directory: directory, domain: .simulation) }
func runPreparedHardwareChild(directory: URL) throws {
    guard directory.standardizedFileURL == hardwareExperimentDirectory else { throw CheckError.failed("Fixed hardware directory required") }
    _ = try HardwareRecoveryIdentity.currentBoot()
    try runExperimentChild(directory: directory, domain: .hardware)
}

private func runExperimentChild(directory: URL, domain: ExperimentDomain) throws {
    let channel = try privateExperimentChannel(domain: domain)
    guard let initial = try channel.readLine(waitSeconds: 0.5) else { throw CheckError.failed("Child bootstrap timeout") }
    let bootstrap = try JSONDecoder().decode(BrokerChildBootstrap.self, from: initial)
    guard bootstrap.scope.domain == domain, domain == .simulation || bootstrap.fault == .normal else {
        throw CheckError.failed("Child domain/fault binding")
    }
    let authority = try ExperimentAuthority(directory: directory, domain: domain)
    let child = try ScopedExperimentChild(authority: authority, scope: bootstrap.scope, role: bootstrap.role,
        phase: bootstrap.phase, input: STDIN_FILENO, output: STDOUT_FILENO)
    if bootstrap.fault == .stoppedAuthorityTransaction, bootstrap.role == .fixed {
        try authority.stopAfterTargetReturnForModelCheck()
    }
    if bootstrap.fault == .restoreFailure { try child.simulateFailure(before: .autoZero) }
    if bootstrap.fault == .blockedFixed && bootstrap.role == .fixed { try child.simulateBlock(afterEffect: .unlock) }
    if bootstrap.fault == .blockedRestore && bootstrap.role == .restore { try child.simulateBlock(afterEffect: .autoZero) }
    try channel.send(BrokerChildReply(id: nil, scope: bootstrap.scope, role: bootstrap.role, pid: getpid(), error: nil, observation: nil))
    while true {
        guard let data = try channel.readLine(waitSeconds: 0.25) else { continue }
        let request = try JSONDecoder().decode(BrokerChildRequest.self, from: data)
        guard request.scope == bootstrap.scope, request.deadline.isFinite, HelperClock.now() < request.deadline,
              (bootstrap.role == .reader ? request.step == nil : request.step.map { $0.isFixed == (bootstrap.role == .fixed) } ?? true) else {
            throw CheckError.failed("Child request binding")
        }
        var errorCode: String?, observation: BrokerObservation?
        do {
            if bootstrap.role == .reader {
                if domain == .simulation {
                    let effects = try FileSessionJournal(directory: directory).loadSimulationDevice()?.effects ?? []
                    if (bootstrap.phase == .fixed && bootstrap.fault == .blockedReader && effects.contains(.targetOne)) ||
                        (bootstrap.phase == .restoring && bootstrap.fault == .blockedAutoReader && effects.contains(.releaseUnlock)) {
                        while true { Thread.sleep(forTimeInterval: 1) }
                    }
                    if bootstrap.phase == .fixed && bootstrap.fault == .readerFailure && effects.contains(.targetOne) {
                        throw CheckError.failed("Injected reader failure")
                    }
                    if bootstrap.phase == .restoring && bootstrap.fault == .earlyAutoReaderFailure {
                        throw CheckError.failed("Injected early Auto reader failure")
                    }
                }
                observation = BrokerObservation(try child.sample())
            } else if let step = request.step {
                try child.perform(step)
                if bootstrap.fault == .delayedAutoZero && step == .autoZero {
                    // Model-only crash window after a durable successful return, before its IPC acknowledgement.
                    Thread.sleep(forTimeInterval: 0.2)
                }
            }
            guard HelperClock.now() < request.deadline else { throw CheckError.failed("Late child operation") }
        } catch { errorCode = String(describing: error) }
        try channel.send(BrokerChildReply(id: request.id, scope: bootstrap.scope, role: bootstrap.role,
                                        pid: getpid(), error: errorCode, observation: observation))
    }
}

private final class ExperimentChildClient {
    let process = Process()
    private let input = Pipe(), output = Pipe()
    let channel: WorkerChannel
    let bootstrap: BrokerChildBootstrap

    init(directory: URL, bootstrap: BrokerChildBootstrap, monitor: RecoveryMonitor, events: (String) -> Void) throws {
        self.bootstrap = bootstrap
        channel = try WorkerChannel(input: output.fileHandleForReading.fileDescriptor,
                                    output: input.fileHandleForWriting.fileDescriptor)
        process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        process.arguments = [bootstrap.scope.domain == .simulation ? "--approved-model-child" : "--prepared-hardware-child", directory.path]
        process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.standardError
        try process.run()
        try input.fileHandleForReading.close(); try output.fileHandleForWriting.close()
        do {
            let deadline = HelperClock.now() + CandidateExperimentPlan.operationSeconds
            try channel.send(bootstrap, deadline: deadline)
            var ready = false
            while !ready, HelperClock.now() < deadline {
                monitor.tick(now: HelperClock.now())
                guard monitor.phase == bootstrap.phase else { throw CheckError.failed("Child readiness phase") }
                guard let data = try channel.readLine(waitSeconds: 0.01) else { continue }
                if try serveProbe(data, monitor: monitor, events: events) { continue }
                let reply = try JSONDecoder().decode(BrokerChildReply.self, from: data)
                guard reply.id == nil, valid(reply), reply.error == nil, reply.observation == nil else {
                    throw CheckError.failed("Child readiness binding")
                }
                ready = true
            }
            guard ready else { throw CheckError.failed("Child readiness timeout") }
        } catch { killOwnedChild(); throw error }
    }

    deinit { try? input.fileHandleForWriting.close(); try? output.fileHandleForReading.close() }

    func valid(_ reply: BrokerChildReply) -> Bool {
        reply.scope == bootstrap.scope && reply.role == bootstrap.role && reply.pid == process.processIdentifier
    }

    func serveProbe(_ data: Data, monitor: RecoveryMonitor, events: (String) -> Void) throws -> Bool {
        guard let request = try? JSONDecoder().decode(RecoveryProbeRequest.self, from: data) else { return false }
        guard request.scope == bootstrap.scope, monitor.phase == bootstrap.phase else { throw CheckError.failed("Child probe binding") }
        try channel.send(monitor.reply(to: request, now: HelperClock.now()), deadline: request.deadline)
        events("\(bootstrap.role.rawValue)ProbeConfirmed")
        return true
    }

    func killOwnedChild() {
        // Only Process instances created by this broker, never a PID supplied by XPC or a process-name match.
        if process.isRunning { _ = Darwin.kill(process.processIdentifier, SIGKILL) }
    }
}

/// The production-shaped broker is exercised with simulation approval and file devices only.
func runApprovedModelBroker(directory: URL) throws { try runExperimentBroker(directory: directory, domain: .simulation) }

/// Inherited private pipes and installed root identity are required before touching hardware state.
func runPreparedHardwareBroker() throws {
    _ = try HardwareRecoveryIdentity.currentBoot()
    try runExperimentBroker(directory: hardwareExperimentDirectory, domain: .hardware)
}

private func runExperimentBroker(directory: URL, domain: ExperimentDomain) throws {
    let ownerChannel = try privateExperimentChannel(domain: domain)
    guard let data = try ownerChannel.readLine(waitSeconds: 2) else { throw CheckError.failed("Broker bootstrap timeout") }
    let bootstrap = try JSONDecoder().decode(BrokerBootstrap.self, from: data)
    let journal = try FileSessionJournal(directory: directory)
    let ownership = try journal.acquireRecoveryBrokerLock()
    defer { withExtendedLifetime(ownership) {} }
    let authority = try ExperimentAuthority(directory: directory, domain: domain)
    guard let ledger = try authority.state().ledger, ledger.sessionID == bootstrap.sessionID,
          domain == .simulation || bootstrap.fault == .normal else {
        throw CheckError.failed("Broker ledger binding")
    }
    var events: [String] = [], failedSteps: [ExperimentStep] = []
    var restart: BrokerRestartRecovery?
    let monitor: RecoveryMonitor
    if bootstrap.restarting {
        let boot: UUID
        if domain == .hardware {
            boot = try HardwareRecoveryIdentity.currentBoot()
        } else { boot = bootstrap.modelBootSession ?? ledger.approval.challenge.bootSession }
        let deadline = HelperClock.now() + CandidateExperimentPlan.writerQuiescenceSeconds
        repeat {
            do {
                restart = try BrokerRestartRecovery(authority: authority, sessionID: ledger.sessionID, boot: boot,
                    binaries: bundledCandidatePlan().binaries, now: HelperClock.now(), date: Date())
                break
            } catch BrokerRestartError.deviceStillActive {
                if HelperClock.now() >= deadline {
                    try persistBrokerOutcome(journal: journal, domain: domain, ledger: ledger, phase: .recoveryRequired,
                        reason: "deviceStillActive", events: ["restartFixedClosed", "deviceLockUnavailable"], failedSteps: [], registered: false)
                    return
                }
                RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            } catch {
                try persistBrokerOutcome(journal: journal, domain: domain, ledger: ledger, phase: .recoveryRequired,
                    reason: "restartRejected", events: [String(describing: error)], failedSteps: [], registered: false)
                return
            }
        } while true
        monitor = try RecoveryMonitor(restarting: restart!, now: HelperClock.now())
        events += ["restartFixedClosed", "deviceLockAcquired", "restorationStarted"]
        restart!.releaseForAutoChild()
    } else { monitor = try RecoveryMonitor(ledger: ledger, now: HelperClock.now()) }
    var reader: ExperimentChildClient?
    var retiredReaders: [ExperimentChildClient] = []
    var readerFailed = false
    let writer: ExperimentChildClient?
    var restorer: ExperimentChildClient?
    if bootstrap.restarting {
        writer = nil
        restorer = try ExperimentChildClient(directory: directory,
            bootstrap: .init(scope: monitor.scope, role: .restore, fault: bootstrap.fault, phase: .restoring),
            monitor: monitor, events: { events.append($0) })
        events.append("restorerReady")
    } else {
        writer = try ExperimentChildClient(directory: directory,
            bootstrap: .init(scope: monitor.scope, role: .fixed, fault: bootstrap.fault, phase: .fixed),
            monitor: monitor, events: { events.append($0) })
        events.append("writerReady")
    }
    defer { writer?.killOwnedChild(); restorer?.killOwnedChild(); reader?.killOwnedChild(); retiredReaders.forEach { $0.killOwnedChild() } }
    do {
        reader = try ExperimentChildClient(directory: directory,
            bootstrap: .init(scope: monitor.scope, role: .reader, fault: bootstrap.fault, phase: monitor.phase),
            monitor: monitor, events: { events.append($0) })
        events.append("readerReady")
    } catch {
        if !bootstrap.restarting { throw error }
        readerFailed = true; events.append("autoReaderSetupFailed")
    }
    var restoreSteps = restart?.remainingSteps ?? ExperimentStep.allCases.filter { !$0.isFixed }
    let ambiguousAuto = restart?.ambiguousAutoSteps ?? []
    var baseline: MonitorSnapshot?
    var restorationRequestedAt = restart?.ledger.restoreRequestedDate
    var readerRequest: (id: UUID, date: Date, deadline: Double)?
    var nextRead = HelperClock.now()
    var writerKillSent = false, ownerConnected = true, terminating = false, sleeping = false
    var nextFixed = 0, nextRestore = 0
    var unlockCompletedAt: Double?, nextProbe = HelperClock.now(), fixedObserved = false
    var pendingStep: ExperimentStep?
    var autoSamples: [ControlObservation] = []
    var sleepAcknowledgements: [() -> Void] = []
    let power = SystemPowerObserver(beforeSleep: { acknowledge in
        sleeping = true; sleepAcknowledgements.append(acknowledge)
    })
    guard domain != .hardware || bootstrap.restarting || power.registered else {
        throw CheckError.failed("System power observer unavailable; no Fixed writes started")
    }
    defer { sleepAcknowledgements.forEach { $0() } }
    signal(SIGTERM, SIG_IGN)
    let termination = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
    termination.setEventHandler { terminating = true }; termination.resume()
    defer { termination.cancel() }
    try ownerChannel.send(BrokerReady(scope: monitor.scope, brokerPID: getpid(), writerPID: writer?.process.processIdentifier ?? 0, readerPID: reader?.process.processIdentifier ?? 0, restorerPID: restorer?.process.processIdentifier))

    while [.fixed, .quiescing, .restoring].contains(monitor.phase) {
        var now = HelperClock.now()
        monitor.tick(now: now)
        if terminating { monitor.stop(reason: "systemShutdown", now: now) }
        if sleeping { monitor.stop(reason: "systemSleep", now: now) }
        if ownerConnected {
            do {
                if let data = try ownerChannel.readLine(waitSeconds: 0) {
                    let request = try JSONDecoder().decode(BrokerOwnerRequest.self, from: data)
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
        if monitor.phase == .fixed && writer?.process.isRunning == false { monitor.stop(reason: "writerExited", now: now) }
        if monitor.phase == .quiescing {
            if !writerKillSent {
                do {
                    try authority.revokeFixed(sessionID: ledger.sessionID, now: HelperClock.now())
                    events.append("fixedClosed")
                } catch { monitor.fail(reason: "journalClosureFailure") }
                events.append("writerStopRequested"); writer?.killOwnedChild(); writerKillSent = true
            }
            // A stop signal or a timeout is not enough: wait for this child's completed termination.
            if monitor.phase == .quiescing && writer?.process.isRunning == false {
                do {
                    now = HelperClock.now()
                    events.append("writerExited")
                    let closed = try authority.closeFixedAndBeginRestoration(sessionID: ledger.sessionID, now: now, date: Date())
                    try monitor.confirmWriterExited(now: HelperClock.now(), restorationStartedAt: closed.restoreStartedAt)
                    events.append("restorationStarted")
                    guard let requestedAt = closed.restoreRequestedDate else { throw CheckError.failed("Restoration timestamp missing") }
                    restorationRequestedAt = requestedAt
                    pendingStep = nil
                    reader?.killOwnedChild()
                    if let reader { retiredReaders.append(reader) }
                    readerRequest = nil; nextRead = HelperClock.now(); readerFailed = false
                    // Auto child reads independently of the broker's reader; reader failure cannot prevent its setup.
                    restorer = try ExperimentChildClient(directory: directory,
                        bootstrap: .init(scope: monitor.scope, role: .restore, fault: bootstrap.fault, phase: .restoring),
                        monitor: monitor, events: { events.append($0) })
                    events.append("restorerReady")
                    restoreSteps = ExperimentStep.allCases.filter { !$0.isFixed && !closed.attempts.contains($0) }
                    try? ownerChannel.send(BrokerProcessEvent(scope: monitor.scope, role: .restore, pid: restorer!.process.processIdentifier),
                        deadline: HelperClock.now() + 0.05)
                    do {
                        reader = try ExperimentChildClient(directory: directory,
                            bootstrap: .init(scope: monitor.scope, role: .reader, fault: bootstrap.fault, phase: .restoring),
                            monitor: monitor, events: { events.append($0) })
                    } catch { readerFailed = true; events.append("autoReaderSetupFailed") }
                } catch { monitor.fail(reason: "restorationSetupFailure") }
            }
        }

        if [.fixed, .restoring].contains(monitor.phase) {
            let child = monitor.phase == .fixed ? writer! : restorer!
            do {
                if let data = try child.channel.readLine(waitSeconds: 0) {
                    if try child.serveProbe(data, monitor: monitor, events: { events.append($0) }) { continue }
                    let reply = try JSONDecoder().decode(BrokerChildReply.self, from: data)
                    guard child.valid(reply), reply.observation == nil, let id = reply.id else { throw CheckError.failed("Broker child reply binding") }
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

        // No SMC or simulated-device reads run on this loop; only bounded private IPC is polled.
        now = HelperClock.now()
        if !readerFailed, [.fixed, .restoring].contains(monitor.phase) {
            do {
                guard let reader, reader.process.isRunning else { throw CheckError.failed("Reader exited") }
                if let pending = readerRequest, now >= pending.deadline { throw CheckError.failed("Reader timeout") }
                if let data = try reader.channel.readLine(waitSeconds: 0) {
                    guard let pending = readerRequest else { throw CheckError.failed("Unsolicited reader frame") }
                    let reply = try JSONDecoder().decode(BrokerChildReply.self, from: data)
                    guard reader.valid(reply), reply.id == pending.id, reply.error == nil, let value = reply.observation else {
                        throw CheckError.failed("Reader reply binding")
                    }
                    let receivedAt = Date()
                    let observation = try value.admitted(requestedAt: pending.date, deadline: pending.deadline,
                                                now: HelperClock.now(), date: receivedAt)
                    readerRequest = nil
                    if monitor.phase == .fixed {
                        if baseline == nil {
                            guard observation.testModeCode == 0,
                                  ExperimentVerification.preflight(observation.snapshot, now: receivedAt, thermalPressure: observation.thermalPressure) == nil else {
                                throw CheckError.failed("Broker preflight")
                            }
                            baseline = observation.snapshot
                        }
                        if observation.thermalPressure != .nominal { monitor.stop(reason: "thermalPressure", now: HelperClock.now()) }
                        if nextFixed == 5, ExperimentVerification.fixedRPMConfirmed(baseline: baseline!, observed: observation.snapshot) {
                            if !fixedObserved {
                                events.append("fixedRPMObserved")
                                try ownerChannel.send(BrokerProcessEvent(scope: monitor.scope, role: .reader,
                                    pid: reader.process.processIdentifier, fixedRPMObserved: true), deadline: HelperClock.now() + 0.05)
                            }
                            fixedObserved = true
                        } else if nextFixed == 5 && fixedObserved { monitor.stop(reason: "fixedNotObserved", now: HelperClock.now()) }
                    } else if nextRestore == restoreSteps.count, monitor.pendingOperation == nil,
                              observation.testModeCode == 0, observation.snapshot.fans.allSatisfy({ $0.modeCode == 0 || $0.modeCode == 3 }),
                              let requestedAt = restorationRequestedAt, observation.snapshot.sampledAt > requestedAt,
                              autoSamples.last.map({ observation.snapshot.sampledAt.timeIntervalSince($0.snapshot.sampledAt) >= 1 }) ?? true {
                        autoSamples.append(observation)
                    }
                }
                if readerRequest == nil && HelperClock.now() >= nextRead && [.fixed, .restoring].contains(monitor.phase) {
                    let id = UUID(), date = Date(), deadline = HelperClock.now() + CandidateExperimentPlan.operationSeconds
                    try reader.channel.send(BrokerChildRequest(id: id, scope: monitor.scope, step: nil, deadline: deadline), deadline: deadline)
                    readerRequest = (id, date, deadline); nextRead = HelperClock.now() + 0.1
                }
            } catch {
                if monitor.phase == .fixed {
                    monitor.stop(reason: readerRequest.map { HelperClock.now() >= $0.deadline } == true ? "readerTimeout" : "readerFailure", now: HelperClock.now())
                } else {
                    readerFailed = true; reader?.killOwnedChild(); events.append("autoReaderFailed")
                }
            }
        }
        now = HelperClock.now()
        if monitor.phase == .fixed {
            do {
                if !fixedObserved && now >= ledger.startedAt + 5 { monitor.stop(reason: "fixedNotObserved", now: now) }
                if baseline != nil, monitor.pendingOperation == nil, monitor.phase == .fixed {
                    let step: ExperimentStep?
                    if nextFixed == 0 { step = .unlock }
                    else if nextFixed < 5, let completed = unlockCompletedAt, now >= completed + 3 {
                        step = ExperimentStep(rawValue: UInt32(nextFixed))
                    } else { step = nil }
                    if step != nil || now >= nextProbe {
                        let id = UUID()
                        try monitor.beginOperation(id: id, now: now)
                        let deadline = min(now + CandidateExperimentPlan.operationSeconds, ledger.expiresAt)
                        try writer!.channel.send(BrokerChildRequest(id: id, scope: monitor.scope, step: step,
                            deadline: deadline), deadline: deadline)
                        pendingStep = step
                        if step != nil { nextFixed += 1 }
                        nextProbe = now + 0.25
                    }
                }
            } catch { monitor.stop(reason: "writerFailure", now: HelperClock.now()) }
        }

        if monitor.phase == .restoring {
            do {
                if monitor.pendingOperation == nil && nextRestore < restoreSteps.count {
                    let step = restoreSteps[nextRestore], id = UUID()
                    try monitor.beginOperation(id: id, now: HelperClock.now())
                    let deadline = min(HelperClock.now() + CandidateExperimentPlan.operationSeconds, monitor.restorationStartedAt! + 8)
                    try restorer!.channel.send(BrokerChildRequest(id: id, scope: monitor.scope, step: step,
                        deadline: deadline), deadline: deadline)
                    events.append("autoStep\(step.rawValue)Requested")
                    pendingStep = step; nextRestore += 1
                } else if monitor.pendingOperation == nil && nextRestore == restoreSteps.count {
                    let date = Date()
                    if failedSteps.contains(where: { !$0.isFixed }) { monitor.fail(reason: "restoreStepFailure"); continue }
                    if readerFailed { monitor.fail(reason: "restorationReaderFailure"); continue }
                    if !ambiguousAuto.isEmpty { monitor.fail(reason: "ambiguousAutoAttempt"); continue }
                    if autoSamples.count >= 3 {
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
    restorer?.killOwnedChild(); reader?.killOwnedChild(); retiredReaders.forEach { $0.killOwnedChild() }
    let exitDeadline = HelperClock.now() + 1
    while (restorer?.process.isRunning == true || reader?.process.isRunning == true || retiredReaders.contains(where: { $0.process.isRunning })), HelperClock.now() < exitDeadline {
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
    }
    if restorer?.process.isRunning == true { monitor.fail(reason: "restorerNotQuiescent") }
    if reader?.process.isRunning == true || retiredReaders.contains(where: { $0.process.isRunning }) { monitor.fail(reason: "readerNotQuiescent") }
    sleepAcknowledgements.forEach { $0() }; sleepAcknowledgements.removeAll()
    try persistBrokerOutcome(journal: journal, domain: domain, ledger: ledger, phase: monitor.phase,
        reason: monitor.reason, events: events, failedSteps: failedSteps, registered: power.registered)
    withExtendedLifetime(power) {}
}

private func persistBrokerOutcome(journal: FileSessionJournal, domain: ExperimentDomain, ledger: ApprovedExperimentLedger,
                                  phase: RecoveryPhase, reason: String?, events: [String], failedSteps: [ExperimentStep], registered: Bool) throws {
    let elapsed = max(0, HelperClock.now() - ledger.startedAt)
    if domain == .simulation {
        try journal.saveRecoveryOutcome(.init(sessionID: ledger.sessionID, phase: phase.rawValue,
            reason: reason, events: events, failedSteps: failedSteps, elapsedSeconds: elapsed, powerNotificationsRegistered: registered))
    } else {
        try journal.saveHardwareRecoveryOutcome(.init(sessionID: ledger.sessionID, phase: phase.rawValue,
            reason: reason, events: events, failedSteps: failedSteps, elapsedSeconds: elapsed, powerNotificationsRegistered: registered))
    }
}
