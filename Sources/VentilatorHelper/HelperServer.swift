import Darwin
import Foundation
import Security
import VentilatorControl

enum HelperClock {
    static func now() -> Double {
        var timebase = mach_timebase_info_data_t()
        guard mach_timebase_info(&timebase) == KERN_SUCCESS, timebase.denom != 0 else { return .nan }
        // Includes sleep; a heartbeat never extends the original session deadline.
        return Double(mach_continuous_time()) * Double(timebase.numer) / Double(timebase.denom) / 1e9
    }
}

final class HelperCoordinator {
    private let queue = DispatchQueue(label: "dev.ventilator.helper.session")
    private let directory: URL
    private var worker: SimulationWorkerClient?
    private var lastReply = HelperReply(control: ControlReport(phase: .idle))

    init(directory: URL) throws {
        self.directory = directory
        let journal = try FileSessionJournal(directory: directory)
        if try journal.load() != nil {
            worker = try SimulationWorkerClient(directory: directory)
            lastReply = worker!.lastReply
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
            if let worker = self.worker {
                _ = try? worker.request(command: .disconnected, owner: owner)
            }
        }
    }

    func waitForSimulationWorkerExit() throws {
        try queue.sync { try worker?.waitForExit() }
    }

    func hardwarePreparation(reply: @escaping (Data) -> Void) {
        queue.async {
            let preparation = try? HardwarePreparation(planSHA256: bundledCandidatePlan().sha256())
            let response = HelperReply(control: self.lastReply.control, errorCode: "hardwareRuntimeNotPrepared", preparation: preparation)
            reply((try? JSONEncoder().encode(response)) ?? Data())
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
    init(_ coordinator: HelperCoordinator) { self.coordinator = coordinator }
    func status(reply: @escaping (Data) -> Void) { coordinator.request(owner: owner, command: "status", sessionID: nil, reply: reply) }
    func startSimulation(reply: @escaping (Data) -> Void) { coordinator.request(owner: owner, command: "start", sessionID: nil, reply: reply) }
    func heartbeat(_ sessionID: String, reply: @escaping (Data) -> Void) { coordinator.request(owner: owner, command: "heartbeat", sessionID: sessionID, reply: reply) }
    func restoreSimulation(_ sessionID: String, reply: @escaping (Data) -> Void) { coordinator.request(owner: owner, command: "restore", sessionID: sessionID, reply: reply) }
    func prepareHardwareExperiment(reply: @escaping (Data) -> Void) { coordinator.hardwarePreparation(reply: reply) }
    func startApprovedHardwareExperiment(_ challengeID: String, planSHA256: String, reply: @escaping (Data) -> Void) {
        coordinator.rejectHardwareStart(challengeID: challengeID, planSHA256: planSHA256, reply: reply)
    }
    func disconnected() { coordinator.disconnected(owner: owner) }
}

func bundledCandidatePlan() throws -> CandidateExperimentPlan {
    let helper = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
    let application = helper.deletingLastPathComponent().appendingPathComponent("Ventilator")
    return CandidateExperimentPlan(binaries: .init(
        applicationSHA256: CandidateExperimentPlan.digest(try Data(contentsOf: application)),
        helperSHA256: CandidateExperimentPlan.digest(try Data(contentsOf: helper))))
}

final class HelperServer: NSObject, NSXPCListenerDelegate {
    enum Acceptance { case anonymousSimulation, signedApplication(team: String) }
    private let acceptance: Acceptance
    private let coordinator: HelperCoordinator
    init(acceptance: Acceptance, directory: URL) throws {
        self.acceptance = acceptance
        self.coordinator = try HelperCoordinator(directory: directory)
    }

    func waitForSimulationWorkerExit() throws { try coordinator.waitForSimulationWorkerExit() }

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        if case .signedApplication(let team) = acceptance {
            // Team is validated as ten ASCII letters/digits by appleTeamIdentifier().
            connection.setCodeSigningRequirement("anchor apple generic and identifier \"dev.ventilator.macos\" and certificate leaf[subject.OU] = \"\(team)\"")
        }
        let endpoint = ConnectionEndpoint(coordinator)
        connection.exportedInterface = NSXPCInterface(with: VentilatorHelperProtocol.self)
        connection.exportedObject = endpoint
        connection.invalidationHandler = { endpoint.disconnected() }
        connection.interruptionHandler = { endpoint.disconnected() }
        connection.resume()
        return true
    }
}

func appleTeamIdentifier() -> String? {
    var code: SecCode?
    guard SecCodeCopySelf([], &code) == errSecSuccess, let code else { return nil }
    var requirement: SecRequirement?
    guard SecRequirementCreateWithString("anchor apple generic and identifier \"dev.ventilator.helper\"" as CFString, [], &requirement) == errSecSuccess,
          let requirement, SecCodeCheckValidity(code, [], requirement) == errSecSuccess else { return nil }
    var information: CFDictionary?
    var staticCode: SecStaticCode?
    guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
          SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
          let values = information as? [String: Any],
          let team = values[kSecCodeInfoTeamIdentifier as String] as? String,
          team.utf8.count == 10,
          team.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) }) else { return nil }
    return team
}
