import Darwin
import CSystemPower
import Foundation
import VentilatorControl
import VentilatorInstallation

@main
enum HelperMain {
    static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        do {
            if arguments.count == 4, arguments[0] == "--approve-local-hardware", let owner = UUID(uuidString: arguments[1]) {
                try runLocalApproval(domain: .hardware, directory: hardwareExperimentDirectory, owner: owner,
                    planSHA256: arguments[2], reviewSHA256: arguments[3])
                return
            }
            if arguments.count == 5, arguments[0] == "--approve-local-model", let owner = UUID(uuidString: arguments[2]) {
                try runLocalApproval(domain: .simulation, directory: URL(fileURLWithPath: arguments[1], isDirectory: true), owner: owner,
                    planSHA256: arguments[3], reviewSHA256: arguments[4])
                return
            }
            if arguments == ["--experiment-read-only"] {
                try experimentReadOnlyCheck()
                return
            }
            if arguments.count == 2, arguments[0] == "--approved-model-child" {
                try runApprovedModelChild(directory: URL(fileURLWithPath: arguments[1], isDirectory: true))
                return
            }
            if arguments.count == 2, arguments[0] == "--prepared-hardware-child" {
                try runPreparedHardwareChild(directory: URL(fileURLWithPath: arguments[1], isDirectory: true))
                return
            }
            if arguments.count == 2, arguments[0] == "--approved-model-broker" {
                try runApprovedModelBroker(directory: URL(fileURLWithPath: arguments[1], isDirectory: true))
                return
            }
            if arguments.count == 3, arguments[0] == "--approved-model-parent", let fault = ModelRecoveryCase(rawValue: arguments[2]) {
                try runApprovedModelParent(directory: URL(fileURLWithPath: arguments[1], isDirectory: true), fault: fault)
                return
            }
            if arguments == ["--candidate-plan"] {
                guard geteuid() != 0 else { throw CheckError.failed("Offline plan must run without root") }
                let plan = try bundledCandidatePlan()
                let object: [String: Any] = ["plan": try JSONSerialization.jsonObject(with: plan.canonicalJSON()),
                                           "planSHA256": try plan.sha256(), "hardwareWritesExecuted": 0,
                                           "blockers": HardwarePreparation(planSHA256: try plan.sha256()).blockers +
                                                        ["physicalRecoveryUnverified", "realSleepDeliveryUnverified"]]
                print(String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]), as: UTF8.self))
                return
            }
            if arguments == ["--experiment-protocol-check"] {
                guard geteuid() != 0 else { throw CheckError.failed("Protocol dry-run must run without root") }
                try experimentProtocolCheck()
                return
            }
            if arguments == ["--power-callback-check"] {
                guard geteuid() != 0 else { throw CheckError.failed("Simulation must run without root") }
                var events: [String] = []
                let observer = SystemPowerObserver { events.append("restore") }
                observer.handle(message: VentilatorCanSystemSleepMessage()) { events.append("ack") }
                observer.handle(message: VentilatorSystemWillSleepMessage()) { events.append("ack") }
                guard events == ["ack", "restore", "ack"] else { throw CheckError.failed("Power callback order") }
                print("Power notifications registered=\(observer.registered); injected sleep callback restores before acknowledgement. Actual sleep delivery not tested.")
                return
            }
            if arguments.count == 2, ["--simulation-worker", "--simulation-worker-restore-failure"].contains(arguments[0]) {
                guard geteuid() != 0 || (try? SignedBundleInspector.requireCurrentProcess(role: .helper)) != nil else { throw CheckError.failed("Untrusted installed root worker refused") }
                try runSimulationWorker(directory: URL(fileURLWithPath: arguments[1], isDirectory: true),
                                        restoreFailure: arguments[0].hasSuffix("restore-failure"))
                return
            }
            if arguments.count == 2, ["--worker-parent", "--worker-parent-restore-failure"].contains(arguments[0]) {
                guard geteuid() != 0 else { throw CheckError.failed("Simulation must run without root") }
                let worker = try SimulationWorkerClient(directory: URL(fileURLWithPath: arguments[1], isDirectory: true),
                                                        restoreFailure: arguments[0].hasSuffix("restore-failure"))
                let started = try worker.request(command: .start, owner: UUID())
                guard started.errorCode == nil, started.control.phase == .waitingForFixed else {
                    throw CheckError.failed("Independent worker did not arm")
                }
                let output: [String: Any] = ["workerPID": worker.process.processIdentifier,
                                            "reply": try JSONSerialization.jsonObject(with: JSONEncoder().encode(started))]
                print(String(decoding: try JSONSerialization.data(withJSONObject: output), as: UTF8.self))
                fflush(stdout)
                withExtendedLifetime(worker) { RunLoop.current.run() }
                return
            }
            if arguments == ["--loopback-check"] {
                guard geteuid() != 0 else { throw CheckError.failed("Simulation must run without root") }
                try loopbackCheck()
                return
            }
            if arguments.count == 2, ["--simulate-crash", "--recover-simulation"].contains(arguments[0]) {
                guard geteuid() != 0 else { throw CheckError.failed("Simulation must run without root") }
                let journal = try FileSessionJournal(directory: URL(fileURLWithPath: arguments[1], isDirectory: true))
                let ownership = try journal.acquireWorkerLock()
                defer { withExtendedLifetime(ownership) {} }
                let transport = SimulatedFanTransport()
                let session = ControlSession(transport: transport, journal: journal)
                if arguments[0] == "--simulate-crash" {
                    _ = try session.begin(owner: UUID(), now: HelperClock.now(), date: Date())
                    try emit(session.report)
                    fflush(stdout)
                    RunLoop.current.run() // Harness kills only this simulated process.
                } else {
                    let start = HelperClock.now(), date = Date()
                    session.recover(now: start, date: date)
                    for offset in 1...3 { session.tick(now: start + Double(offset), date: date.addingTimeInterval(Double(offset))) }
                    guard session.report.phase == .autoCodeObserved, transport.effects == [.auto], try journal.load() == nil else {
                        throw CheckError.failed("Restart restoration was not observed")
                    }
                    try emit(session.report)
                }
                return
            }
            guard arguments.isEmpty, geteuid() == 0 else {
                throw CheckError.failed("Daemon requires an Apple-issued helper signature and root; launchd registration is separate")
            }
            let proof = try SignedBundleInspector.requireCurrentProcess(role: .helper)
            let server = try HelperServer(acceptance: .signedApplication(proof: proof),
                                          directory: URL(fileURLWithPath: "/Library/Application Support/Ventilator/HelperSimulation", isDirectory: true))
            let listener = NSXPCListener(machServiceName: "dev.ventilator.helper")
            listener.delegate = server
            listener.resume()
            withExtendedLifetime(server) { RunLoop.current.run() }
        } catch {
            fputs("VentilatorHelper: \(error)\n", stderr)
            exit(78)
        }
    }

    private static func emit(_ report: ControlReport) throws {
        print(String(decoding: try JSONEncoder().encode(HelperReply(control: report)), as: UTF8.self))
    }
}

enum CheckError: Error { case failed(String) }

private final class ReplyBox {
    private let lock = NSLock()
    private var result: Result<Data, Error>?
    func set(_ result: Result<Data, Error>) { lock.lock(); defer { lock.unlock() }; if self.result == nil { self.result = result } }
    func get() -> Result<Data, Error>? { lock.lock(); defer { lock.unlock() }; return result }
}

private func rpc(_ connection: NSXPCConnection, send: (VentilatorHelperProtocol, @escaping (Data) -> Void) -> Void) throws -> HelperReply {
    try JSONDecoder().decode(HelperReply.self, from: rpcData(connection, send: send))
}

private func rpcData(_ connection: NSXPCConnection, send: (VentilatorHelperProtocol, @escaping (Data) -> Void) -> Void) throws -> Data {
    let box = ReplyBox()
    guard let proxy = connection.remoteObjectProxyWithErrorHandler({ box.set(.failure($0)) }) as? VentilatorHelperProtocol else {
        throw CheckError.failed("XPC proxy type")
    }
    send(proxy) { box.set(.success($0)) }
    let deadline = Date().addingTimeInterval(4)
    while box.get() == nil, Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.02)) }
    guard let result = box.get() else { throw CheckError.failed("XPC reply timeout") }
    return try result.get()
}

private func loopbackCheck() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ventilator-xpc-\(UUID().uuidString)", isDirectory: true)
    // Directory cleanup follows worker exit, rather than racing a still-running restorer.
    defer { try? FileManager.default.removeItem(at: directory) }
    let listener = NSXPCListener.anonymous()
    let server = try HelperServer(acceptance: .anonymousSimulation, directory: directory)
    listener.delegate = server
    listener.resume()
    defer { listener.invalidate() }
    let client = NSXPCConnection(listenerEndpoint: listener.endpoint)
    client.remoteObjectInterface = NSXPCInterface(with: VentilatorHelperProtocol.self)
    client.resume()
    defer { client.invalidate() }
    let initial = try rpc(client) { $0.status(reply: $1) }
    guard initial.protocolVersion == 1, !initial.hardwareControlAvailable, initial.control.phase == .idle else {
        throw CheckError.failed("Unexpected initial helper status")
    }
    let installationDenied = try rpcData(client) { $0.installationStatus(UUID().uuidString, reply: $1) }
    guard installationDenied.isEmpty else {
        throw CheckError.failed("Anonymous simulation claimed an installed root helper")
    }
    let preparation = try rpc(client) { $0.prepareHardwareExperiment(reply: $1) }
    guard let prepared = preparation.preparation, !prepared.readyForOwnerApproval else { throw CheckError.failed("Hardware readiness was granted") }
    let hardwareDenied = try rpc(client) { $0.startApprovedHardwareExperiment(UUID().uuidString, planSHA256: prepared.planSHA256, reply: $1) }
    guard hardwareDenied.errorCode == "hardwareRuntimeNotPrepared", hardwareDenied.control.phase == .idle else {
        throw CheckError.failed("An XPC digest authorized a hardware experiment")
    }
    let malformedApproval = try rpc(client) { $0.startApprovedHardwareExperiment("invalid", planSHA256: "invalid", reply: $1) }
    guard malformedApproval.errorCode == "invalidApprovalRequest" else { throw CheckError.failed("Malformed approval request accepted") }
    let started = try rpc(client) { $0.startSimulation(reply: $1) }
    guard started.errorCode == nil, let id = started.control.sessionID else { throw CheckError.failed("Simulation start rejected") }
    let stranger = NSXPCConnection(listenerEndpoint: listener.endpoint)
    stranger.remoteObjectInterface = NSXPCInterface(with: VentilatorHelperProtocol.self)
    stranger.resume()
    defer { stranger.invalidate() }
    let denied = try rpc(stranger) { $0.restoreSimulation(id.uuidString, reply: $1) }
    guard denied.errorCode != nil else { throw CheckError.failed("Another connection controlled the session") }
    let invalid = try rpc(client) { $0.heartbeat("not-a-session", reply: $1) }
    guard invalid.errorCode != nil else { throw CheckError.failed("Malformed session accepted") }
    _ = try rpc(client) { $0.heartbeat(id.uuidString, reply: $1) }
    _ = try rpc(client) { $0.restoreSimulation(id.uuidString, reply: $1) }
    let deadline = Date().addingTimeInterval(4)
    var restored = false
    while Date() < deadline {
        let response = try rpc(client) { $0.status(reply: $1) }
        if response.control.phase == .autoCodeObserved { restored = true; break }
        RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    guard restored else { throw CheckError.failed("Three separated Auto-code reads missing") }
    try server.waitForSimulationWorkerExit()
    print("XPC loopback: status, empty installation refusal, hardware preparation/refusal, malformed approval, simulation start, owner binding, heartbeat and restore passed; hardwareControlAvailable=false")
    withExtendedLifetime(server) {}
}
