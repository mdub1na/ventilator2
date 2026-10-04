import Darwin
import Foundation
import Security
import VentilatorControl
import VentilatorExperiment
import VentilatorInstallation

enum HelperClock {
    static func now() -> Double {
        var timebase = mach_timebase_info_data_t()
        guard mach_timebase_info(&timebase) == KERN_SUCCESS, timebase.denom != 0 else { return .nan }
        // Includes sleep; a heartbeat never extends the original session deadline.
        return Double(mach_continuous_time()) * Double(timebase.numer) / Double(timebase.denom) / 1e9
    }
}

final class HelperCoordinator {
    private let queue = DispatchQueue(label: SignedBundleInspector.machService + ".session")
    private let directory: URL
    private var worker: SimulationWorkerClient?
    private let experiment: ExperimentSessionRuntime?
    private let machineSupported: Bool
    private var lastReply = HelperReply(control: ControlReport(phase: .idle))

    init(directory: URL, experiment: ExperimentSessionRuntime? = nil, machineSupported: Bool = true) throws {
        self.directory = directory
        self.experiment = experiment
        self.machineSupported = machineSupported
        try experiment?.recoverOnStartup()
        // A diagnostic listener must not create simulation storage just to look for a journal.
        var metadata = stat()
        if lstat(directory.path, &metadata) == 0 {
            let journal = try FileSessionJournal(directory: directory)
            if try journal.load() != nil {
                worker = try SimulationWorkerClient(directory: directory)
                lastReply = worker!.lastReply
            }
        } else if errno != ENOENT {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
    }

    func request(owner: UUID, command: String, sessionID: String?, reply: @escaping (Data) -> Void) {
        queue.async {
            do {
                var id: UUID?
                var action: WorkerCommand
                switch command {
                case "status": action = .status
                case "start": action = .start
                case "heartbeat", "restore":
                    guard let text = sessionID, text.utf8.count == 36, let identifier = UUID(uuidString: text) else {
                        throw ControlError.wrongOwnerOrSession
                    }
                    id = identifier
                    action = command == "heartbeat" ? .heartbeat : .restore
                default: throw ControlError.wrongOwnerOrSession
                }
                if self.worker == nil && action == .start {
                    guard try self.experiment?.status().phase ?? "idle" == "idle" else { throw ControlError.sessionAlreadyUsed }
                    self.worker = try SimulationWorkerClient(directory: self.directory)
                }
                if let worker = self.worker {
                    self.lastReply = try worker.request(command: action, owner: owner, sessionID: id)
                } else if action != .status { throw ControlError.wrongOwnerOrSession }
            } catch {
                // A worker communication failure closes its input and leaves recovery to its own clock.
                let previous = self.worker?.lastReply.control ?? self.lastReply.control
                let control = self.worker == nil ? previous : ControlReport(phase: .recoveryRequired,
                                                                           sessionID: previous.sessionID, reason: .transportFailure)
                self.lastReply = HelperReply(control: control,
                                             errorCode: String(describing: error))
            }
            reply((try? JSONEncoder().encode(self.lastReply)) ?? Data())
        }
    }

    func disconnected(owner: UUID) {
        queue.async {
            self.experiment?.disconnected(owner: owner)
            if let worker = self.worker {
                _ = try? worker.request(command: .disconnected, owner: owner)
            }
        }
    }

    func waitForSimulationWorkerExit() throws {
        try queue.sync { try worker?.waitForExit() }
    }

    func hardwarePreparation(owner: UUID, reply: @escaping (Data) -> Void) {
        queue.async {
            let preparation = try? HardwarePreparation(planSHA256: bundledCandidatePlan().sha256(),
                connectionOwner: owner, runtimePrepared: self.experiment != nil, machineSupported: self.machineSupported)
            let response = HelperReply(control: self.lastReply.control,
                errorCode: self.experiment == nil ? (self.machineSupported ? "hardwareRuntimeNotPrepared" : "unsupportedMachine") : nil,
                preparation: preparation)
            reply((try? JSONEncoder().encode(response)) ?? Data())
        }
    }

    func experimentRequest(owner: UUID, command: String, identifier: String? = nil, planSHA256: String? = nil,
                           reply: @escaping (Data) -> Void) {
        queue.async {
            var report: HardwareExperimentReport?, errorCode: String?
            do {
                guard let experiment = self.experiment else {
                    throw CheckError.failed(self.machineSupported ? "hardwareRuntimeNotPrepared" : "unsupportedMachine")
                }
                guard self.worker?.process.isRunning != true else { throw ControlError.sessionAlreadyUsed }
                if command == "status" { report = try experiment.status() }
                else {
                    guard let identifier, identifier.utf8.count == 36, let id = UUID(uuidString: identifier) else {
                        throw CheckError.failed("invalidApprovalRequest")
                    }
                    if command == "start" {
                        guard let planSHA256, planSHA256.utf8.count == 64,
                              planSHA256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
                            throw CheckError.failed("invalidApprovalRequest")
                        }
                        report = try experiment.start(owner: owner, challengeID: id, planSHA256: planSHA256)
                    } else {
                        report = try experiment.ownerRequest(owner: owner, sessionID: id, command: command == "heartbeat" ? .heartbeat : .restore)
                    }
                }
            } catch { errorCode = String(describing: error); report = try? self.experiment?.status() }
            let response = HelperReply(control: self.lastReply.control, errorCode: errorCode, hardwareExperiment: report)
            reply((try? JSONEncoder().encode(response)) ?? Data())
        }
    }

    func installationStatus(nonce: String, reply: @escaping (Data) -> Void) {
        queue.async {
            do {
                guard nonce.utf8.count == 36, let nonce = UUID(uuidString: nonce), geteuid() == 0 else {
                    throw InstallationError.invalidChallenge
                }
                let proof = try SignedBundleInspector.requireCurrentProcess(role: .helper)
                let hardwareDirectory = URL(fileURLWithPath: "/Library/Application Support/Ventilator/Experiment", isDirectory: true)
                var pending = false
                if FileManager.default.fileExists(atPath: hardwareDirectory.path) {
                    pending = try FileSessionJournal(directory: hardwareDirectory).loadAuthorityState(domain: .hardware)?.ledger?.pendingRestoration ?? false
                }
                let response = HelperInstallationReply(nonce: nonce, processIdentifier: getpid(), effectiveUID: geteuid(),
                    teamIdentifier: proof.teamIdentifier, applicationCDHash: proof.applicationCDHash, helperCDHash: proof.helperCDHash,
                    applicationSHA256: proof.fingerprint.applicationSHA256, helperSHA256: proof.fingerprint.helperSHA256,
                    launchDaemonSHA256: proof.fingerprint.launchDaemonSHA256, pendingHardwareRestoration: pending,
                    simulationPhase: self.lastReply.control.phase.rawValue)
                reply(try JSONEncoder().encode(response))
            } catch { reply(Data()) } // No permissive fallback for an unreadable hardware journal or untrusted bundle.
        }
    }

    func rejectHardwareStart(challengeID: String, planSHA256: String, reply: @escaping (Data) -> Void) {
        queue.async {
            let valid = challengeID.utf8.count == 36 && UUID(uuidString: challengeID) != nil &&
                planSHA256.utf8.count == 64 && planSHA256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) })
            let response = HelperReply(control: self.lastReply.control, errorCode: valid ? "hardwareRuntimeNotPrepared" : "invalidApprovalRequest")
            reply((try? JSONEncoder().encode(response)) ?? Data())
        }
    }
}

private final class ConnectionEndpoint: NSObject, VentilatorHelperProtocol {
    private let owner = UUID() // Server-generated and never supplied by the client.
    private let coordinator: HelperCoordinator
    func status(reply: @escaping (Data) -> Void) { coordinator.request(owner: owner, command: "status", sessionID: nil, reply: reply) }
    func installationStatus(_ nonce: String, reply: @escaping (Data) -> Void) { coordinator.installationStatus(nonce: nonce, reply: reply) }
    func startSimulation(reply: @escaping (Data) -> Void) { coordinator.request(owner: owner, command: "start", sessionID: nil, reply: reply) }
    func heartbeat(_ sessionID: String, reply: @escaping (Data) -> Void) { coordinator.request(owner: owner, command: "heartbeat", sessionID: sessionID, reply: reply) }
    func restoreSimulation(_ sessionID: String, reply: @escaping (Data) -> Void) { coordinator.request(owner: owner, command: "restore", sessionID: sessionID, reply: reply) }
    private let experimental: Bool
    init(_ coordinator: HelperCoordinator, experimental: Bool) { self.coordinator = coordinator; self.experimental = experimental }
    func prepareHardwareExperiment(reply: @escaping (Data) -> Void) { coordinator.hardwarePreparation(owner: owner, reply: reply) }
    func startApprovedHardwareExperiment(_ challengeID: String, planSHA256: String, reply: @escaping (Data) -> Void) {
        if experimental { coordinator.experimentRequest(owner: owner, command: "start", identifier: challengeID, planSHA256: planSHA256, reply: reply) }
        else { coordinator.rejectHardwareStart(challengeID: challengeID, planSHA256: planSHA256, reply: reply) }
    }
    func heartbeatHardwareExperiment(_ sessionID: String, reply: @escaping (Data) -> Void) { coordinator.experimentRequest(owner: owner, command: "heartbeat", identifier: sessionID, reply: reply) }
    func restoreHardwareExperiment(_ sessionID: String, reply: @escaping (Data) -> Void) { coordinator.experimentRequest(owner: owner, command: "restore", identifier: sessionID, reply: reply) }
    func hardwareExperimentStatus(reply: @escaping (Data) -> Void) { coordinator.experimentRequest(owner: owner, command: "status", reply: reply) }
    func disconnected() { coordinator.disconnected(owner: owner) }
}

func bundledCandidatePlan() throws -> CandidateExperimentPlan {
    let helper = try CurrentExecutable.url()
    let application = helper.deletingLastPathComponent().appendingPathComponent("Ventilator")
    return CandidateExperimentPlan(binaries: .init(
        applicationSHA256: CandidateExperimentPlan.digest(try Data(contentsOf: application)),
        helperSHA256: CandidateExperimentPlan.digest(try Data(contentsOf: helper))))
}

final class HelperServer: NSObject, NSXPCListenerDelegate {
    enum Acceptance {
        case anonymousSimulation, anonymousExperimentModel(boot: UUID), signedApplication(proof: SignedBundleProof)
        case anonymousUnsupportedMachineModel(machine: ExperimentMachine)
    }
    private let acceptance: Acceptance
    private let coordinator: HelperCoordinator
    init(acceptance: Acceptance, directory: URL) throws {
        self.acceptance = acceptance
        let experiment: ExperimentSessionRuntime?
        let machineSupported: Bool
        switch acceptance {
        case .anonymousSimulation: experiment = nil; machineSupported = true
        case .anonymousExperimentModel(let boot): experiment = try .simulation(directory: directory, boot: boot); machineSupported = true
        case .signedApplication:
            let machine = ExperimentMachine.current()
            experiment = try .hardwareIfSupported(machine: machine)
            machineSupported = machine == .candidate
        case .anonymousUnsupportedMachineModel(let machine):
            guard machine != .candidate else { throw CheckError.failed("Unsupported model cannot initialize hardware") }
            experiment = try .hardwareIfSupported(machine: machine)
            machineSupported = false
        }
        self.coordinator = try HelperCoordinator(directory: directory, experiment: experiment, machineSupported: machineSupported)
    }

    func waitForSimulationWorkerExit() throws { try coordinator.waitForSimulationWorkerExit() }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        if case .signedApplication(let proof) = acceptance {
            guard let requirement = try? SignedBundleInspector.requirement(role: .application, proof: proof) else { return false }
            connection.setCodeSigningRequirement(requirement)
        }
        let experimental: Bool
        if case .anonymousSimulation = acceptance { experimental = false } else { experimental = true }
        let endpoint = ConnectionEndpoint(coordinator, experimental: experimental)
        connection.exportedInterface = NSXPCInterface(with: VentilatorHelperProtocol.self)
        connection.exportedObject = endpoint
        connection.invalidationHandler = { endpoint.disconnected() }
        connection.interruptionHandler = { endpoint.disconnected() }
        connection.resume()
        return true
    }
}
