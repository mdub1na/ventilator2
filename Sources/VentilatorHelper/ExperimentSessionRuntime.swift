import Darwin
import Foundation
import VentilatorInstallation
import ServiceManagement
import VentilatorControl
import VentilatorExperiment

/// The daemon proxies only scoped owner requests. A broker has its own clock and inherited pipes.
final class ExperimentSessionRuntime {
    let authority: ExperimentAuthority
    private let journal: FileSessionJournal
    private let identity: () throws -> UUID
    private var broker: ExperimentBrokerClient?

    private init(directory: URL, domain: ExperimentDomain, identity: @escaping () throws -> UUID) throws {
        self.identity = identity
        authority = try ExperimentAuthority(directory: directory, domain: domain)
        journal = try FileSessionJournal(directory: directory)
    }
    static func hardware() throws -> ExperimentSessionRuntime {
        _ = try hardwareIdentity()
        return try .init(directory: hardwareExperimentDirectory, domain: .hardware, identity: hardwareIdentity)
    }
    /// Unsupported profiles keep diagnostic XPC available without initializing hardware authority or recovery.
    static func hardwareIfSupported(machine: ExperimentMachine = .current()) throws -> ExperimentSessionRuntime? {
        guard machine == .candidate else { return nil }
        return try hardware()
    }
    private static func hardwareIdentity() throws -> UUID {
        let boot = try HardwareRecoveryIdentity.currentBoot()
        guard SMAppService.daemon(plistName: SignedBundleInspector.plistName).status == .enabled else {
            throw LocalApprovalError.installationNotEnabled
        }
        return boot
    }
    static func simulation(directory: URL, boot: UUID) throws -> ExperimentSessionRuntime {
        guard geteuid() != 0 else { throw CheckError.failed("Runtime model requires non-root") }
        return try .init(directory: directory, domain: .simulation, identity: { boot })
    }

    /// Called before accepting connections. Never resumes Fixed or repeats consumed steps.
    func recoverOnStartup() throws {
        let boot = try identity()
        guard let ledger = try journal.loadAuthorityState(domain: authority.domain)?.ledger,
              ledger.pendingRestoration, !ledger.autoCodesObserved else { return }
        guard ledger.approval.challenge.bootSession == boot, ledger.approval.challenge.binaries == (try bundledCandidatePlan().binaries) else {
            throw CheckError.failed("Startup recovery boot/binary mismatch; pending retained")
        }
        // A surviving broker owns this lock. Its private owner pipe will already close on daemon exit.
        // No new process is signalled and no PID is loaded from disk.
        let lockAvailable: Bool = {
            guard let ownership = try? journal.acquireRecoveryBrokerLock() else { return false }
            defer { withExtendedLifetime(ownership) {} }
            return true
        }()
        guard lockAvailable else { return }
        // Release the transient check before the new broker acquires its lifetime lock.
        try startRecoveryAfterLockCheck(ledger: ledger, boot: boot)
    }

    private func startRecoveryAfterLockCheck(ledger: ApprovedExperimentLedger, boot: UUID) throws {
        broker = try ExperimentBrokerClient(directory: authority.directory, ledger: ledger, restarting: true, boot: boot)
    }

    func start(owner: UUID, challengeID: UUID, planSHA256: String) throws -> HardwareExperimentReport {
        guard broker == nil else { throw ExperimentAuthorityError.experimentAlreadyConsumed }
        let boot = try identity(), plan = try bundledCandidatePlan(), state = try authority.state()
        guard state.ledger == nil else { throw ExperimentAuthorityError.experimentAlreadyConsumed }
        guard let approval = state.approval, approval.challenge.id == challengeID,
              approval.challenge.connectionOwner == owner, approval.challenge.planSHA256 == planSHA256,
              planSHA256 == (try plan.sha256()), let reviewSHA = approval.challenge.ownerReviewSHA256,
              let data = try journal.loadLocalReview(domain: authority.domain) else { throw ExperimentAuthorityError.approvalMissing }
        let review = try JSONDecoder().decode(LocalApprovalReview.self, from: data)
        guard review.domain == authority.domain, review.candidate == plan, try review.sha256() == reviewSHA else {
            throw LocalApprovalError.reviewMismatch
        }
        let observation = try experimentPreflight(domain: authority.domain)
        guard try identity() == boot else { throw NativeExperimentError.wrongBootSession }
        if authority.domain == .simulation { try journal.saveSimulationDevice(SimulationDeviceState()) }
        let ledger = try authority.begin(owner: owner, challengeID: challengeID, plan: plan, binaries: plan.binaries,
            boot: boot, now: HelperClock.now(), observation: observation, date: Date())
        // A failure from this point keeps the consumed pending ledger; it cannot authorize a second Fixed run.
        broker = try ExperimentBrokerClient(directory: authority.directory, ledger: ledger, restarting: false, boot: boot)
        return try status()
    }

    func ownerRequest(owner: UUID, sessionID: UUID, command: BrokerOwnerCommand) throws -> HardwareExperimentReport {
        guard let ledger = try journal.loadAuthorityState(domain: authority.domain)?.ledger, ledger.sessionID == sessionID,
              ledger.approval.challenge.connectionOwner == owner else { throw ExperimentAuthorityError.wrongConnection }
        guard let broker else { throw CheckError.failed("Broker unavailable; pending retained") }
        try broker.send(command)
        return try status()
    }
    func disconnected(owner: UUID) {
        guard let ledger = try? journal.loadAuthorityState(domain: authority.domain)?.ledger,
              ledger.approval.challenge.connectionOwner == owner else { return }
        broker?.closeOwnerPipe() // Independent broker initiates restoration on EOF; no signals to its devices.
    }
    /// Fault harness only, immutable simulation domain and a Process created by this runtime.
    func killModelBrokerForCheck() throws {
        guard authority.domain == .simulation, geteuid() != 0, let broker else { throw NativeExperimentError.invalidScope }
        if broker.process.isRunning { _ = Darwin.kill(broker.process.processIdentifier, SIGKILL) }
        let deadline = HelperClock.now() + 1
        while broker.process.isRunning, HelperClock.now() < deadline { Thread.sleep(forTimeInterval: 0.01) }
        guard !broker.process.isRunning else { throw CheckError.failed("Model broker did not exit") }
    }
    func status() throws -> HardwareExperimentReport {
        try broker?.poll()
        // Atomic protected-file snapshots need no authority transaction lock. Diagnostic polling
        // must not contend with a writer's nonblocking reservation/admission lock.
        guard let ledger = try journal.loadAuthorityState(domain: authority.domain)?.ledger else {
            return .init(domain: authority.domain.rawValue, sessionID: nil, phase: "idle", pending: false, fixedRPMObserved: false)
        }
        let phase: String
        var fixedObserved = broker?.fixedRPMObserved ?? false
        if broker?.process.isRunning != true {
            if authority.domain == .simulation, let outcome = try journal.loadRecoveryOutcome(), outcome.sessionID == ledger.sessionID {
                phase = outcome.phase; fixedObserved = outcome.events.contains("fixedRPMObserved")
            } else if authority.domain == .hardware, let outcome = try journal.loadHardwareRecoveryOutcome(), outcome.sessionID == ledger.sessionID {
                phase = outcome.phase; fixedObserved = outcome.events.contains("fixedRPMObserved")
            } else { phase = "recoveryRequired" }
        } else if ledger.autoCodesObserved { phase = "autoCodesObserved" }
        else if broker?.process.isRunning == true { phase = ledger.fixedClosed ? "restoring" : "fixed" }
        else { phase = "recoveryRequired" }
        return .init(domain: authority.domain.rawValue, sessionID: ledger.sessionID, phase: phase,
            pending: ledger.pendingRestoration, fixedRPMObserved: fixedObserved)
    }
}

private final class ExperimentBrokerClient {
    let process = Process()
    private let input = Pipe(), output = Pipe()
    private let channel: WorkerChannel
    private let ready: BrokerReady
    private var closed = false
    private(set) var fixedRPMObserved = false
    init(directory: URL, ledger: ApprovedExperimentLedger, restarting: Bool, boot: UUID) throws {
        channel = try WorkerChannel(input: output.fileHandleForReading.fileDescriptor, output: input.fileHandleForWriting.fileDescriptor)
        process.executableURL = try CurrentExecutable.url()
        process.arguments = ledger.domain == .hardware ? ["--hardware-broker"] : ["--approved-model-broker", directory.path]
        process.standardInput = input; process.standardOutput = output; process.standardError = FileHandle.standardError
        try process.run()
        try input.fileHandleForReading.close(); try output.fileHandleForWriting.close()
        do {
            try channel.send(BrokerBootstrap(sessionID: ledger.sessionID, fault: .normal, restarting: restarting, modelBootSession: boot))
            guard let data = try channel.readLine(waitSeconds: 2) else { throw CheckError.failed("Broker readiness timeout") }
            let received = try JSONDecoder().decode(BrokerReady.self, from: data)
            guard received.scope.matches(ledger), received.brokerPID == process.processIdentifier,
                  restarting ? received.writerPID == 0 : received.writerPID > 0 else { throw CheckError.failed("Broker readiness binding") }
            ready = received
        } catch {
            try? input.fileHandleForWriting.close() // Restoration is requested through EOF; never kill the broker here.
            throw error
        }
    }
    deinit { closeOwnerPipe(); try? output.fileHandleForReading.close() }
    func closeOwnerPipe() { if !closed { closed = true; try? input.fileHandleForWriting.close() } }
    func send(_ command: BrokerOwnerCommand) throws {
        guard !closed, process.isRunning else { throw CheckError.failed("Broker closed") }
        try poll()
        try channel.send(BrokerOwnerRequest(scope: ready.scope, command: command), deadline: HelperClock.now() + 0.1)
    }
    func poll() throws {
        guard !closed, process.isRunning else { return }
        // Drain trusted process events to keep the bounded output pipe writable. They are never used as kill targets.
        do {
            while let data = try channel.readLine(waitSeconds: 0) {
                let event = try JSONDecoder().decode(BrokerProcessEvent.self, from: data)
                guard event.scope == ready.scope else { throw CheckError.failed("Broker event binding") }
                if event.fixedRPMObserved {
                    guard event.role == .reader, event.pid == ready.readerPID else { throw CheckError.failed("Fixed observation peer") }
                    fixedRPMObserved = true
                }
            }
        } catch {
            closeOwnerPipe() // A broken/malformed owner channel always requests restoration.
            throw error
        }
    }
}
