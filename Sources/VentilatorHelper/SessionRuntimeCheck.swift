import Foundation
import VentilatorControl
import VentilatorExperiment

/// Real anonymous XPC routes into the same session proxy, with immutable simulation authority.
func sessionRuntimeCheck() throws {
    for machine in [ExperimentMachine(model: "Mac15,7", version: "27.0.1", build: "26A434"),
                    ExperimentMachine(model: "Mac15,7", version: "27.0.0", build: "other"),
                    ExperimentMachine(model: "unknown", version: "27.0.0", build: "26A428")] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ventilator-unsupported-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let server = try HelperServer(acceptance: .anonymousUnsupportedMachineModel(machine: machine), directory: directory)
        guard !FileManager.default.fileExists(atPath: directory.path) else { throw CheckError.failed("Diagnostic startup created simulation storage") }
        let listener = NSXPCListener.anonymous(); listener.delegate = server; listener.resume()
        defer { listener.invalidate() }
        let client = NSXPCConnection(listenerEndpoint: listener.endpoint)
        client.remoteObjectInterface = NSXPCInterface(with: VentilatorHelperProtocol.self); client.resume()
        defer { client.invalidate() }
        let status = try rpc(client) { $0.status(reply: $1) }
        guard status.errorCode == nil, status.control.phase == .idle, !status.hardwareControlAvailable else {
            throw CheckError.failed("Unsupported profile lost diagnostic XPC")
        }
        let preparation = try rpc(client) { $0.prepareHardwareExperiment(reply: $1) }
        guard preparation.errorCode == "unsupportedMachine", let prepared = preparation.preparation,
              !prepared.runtimePrepared, !prepared.readyForOwnerApproval, prepared.blockers.contains("unsupportedMachine") else {
            throw CheckError.failed("Unsupported profile prepared hardware")
        }
        let start = try rpc(client) { $0.startApprovedHardwareExperiment(UUID().uuidString, planSHA256: prepared.planSHA256, reply: $1) }
        guard start.errorCode?.contains("unsupportedMachine") == true,
              !FileManager.default.fileExists(atPath: directory.path) else {
            throw CheckError.failed("Unsupported start initialized authority")
        }
        let installation = try rpcData(client) { $0.installationStatus(UUID().uuidString, reply: $1) }
        guard installation.isEmpty else { throw CheckError.failed("Anonymous non-root model claimed installation proof") }
        guard !FileManager.default.fileExists(atPath: directory.path) else { throw CheckError.failed("Diagnostic requests created a journal") }
        print("Unsupported hardware XPC model: \(machine.model)/\(machine.version)/\(machine.build); diagnostic idle, explicit blocker and start denial; no authority or device.")
        withExtendedLifetime(server) {}
    }
    for disconnect in [false, true] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ventilator-runtime-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let boot = UUID(), authority = try ExperimentAuthority(directory: directory, domain: .simulation)
        let journal = try FileSessionJournal(directory: directory)
        let server = try HelperServer(acceptance: .anonymousExperimentModel(boot: boot), directory: directory)
        let listener = NSXPCListener.anonymous(); listener.delegate = server; listener.resume()
        defer { listener.invalidate() }
        func connection() -> NSXPCConnection {
            let result = NSXPCConnection(listenerEndpoint: listener.endpoint)
            result.remoteObjectInterface = NSXPCInterface(with: VentilatorHelperProtocol.self); result.resume()
            return result
        }
        let client = connection(), stranger = connection()
        defer { client.invalidate(); stranger.invalidate() }
        let preparation = try rpc(client) { $0.prepareHardwareExperiment(reply: $1) }
        guard let prepared = preparation.preparation, prepared.runtimePrepared, let owner = prepared.connectionOwner,
              !prepared.readyForOwnerApproval else { throw CheckError.failed("Runtime preparation binding") }
        let missing = try rpc(client) { $0.startApprovedHardwareExperiment(UUID().uuidString, planSHA256: prepared.planSHA256, reply: $1) }
        guard missing.errorCode != nil, try authority.state().ledger == nil else { throw CheckError.failed("Missing approval started broker") }
        let plan = try bundledCandidatePlan()
        let review = try LocalApprovalReview(domain: .simulation, candidate: plan, ownerInstructions: "Model only: exact XPC owner, isolated preflight, single Fixed and Auto, pending on errors.")
        try journal.saveLocalReview(review.canonicalJSON(), domain: .simulation)
        let issuer = try LocalApprovalIssuer.simulation(authority: authority, binaries: plan.binaries, boot: boot)
        let prompt = try issuer.prepare(owner: owner, planSHA256: prepared.planSHA256, reviewSHA256: review.sha256(), now: HelperClock.now())
        try issuer.confirm(prompt, response: prompt.confirmation, now: HelperClock.now())
        let wrongOwner = try rpc(stranger) { $0.startApprovedHardwareExperiment(prompt.challenge.id.uuidString, planSHA256: prepared.planSHA256, reply: $1) }
        guard wrongOwner.errorCode != nil, try authority.state().ledger == nil else { throw CheckError.failed("Wrong owner consumed approval") }
        let started = try rpc(client) { $0.startApprovedHardwareExperiment(prompt.challenge.id.uuidString, planSHA256: prepared.planSHA256, reply: $1) }
        guard started.errorCode == nil, let report = started.hardwareExperiment, report.domain == "simulation",
              let session = report.sessionID, report.pending, !report.physicalAutoVerified, !started.hardwareControlAvailable else {
            throw CheckError.failed("Runtime did not begin simulation only")
        }
        let denied = try rpc(stranger) { $0.restoreHardwareExperiment(session.uuidString, reply: $1) }
        guard denied.errorCode != nil else { throw CheckError.failed("Wrong owner restored session") }
        if disconnect { client.invalidate() }
        else {
            let deadline = HelperClock.now() + 5
            var observed = false
            while !observed, HelperClock.now() < deadline {
                let heartbeat = try rpc(client) { $0.heartbeatHardwareExperiment(session.uuidString, reply: $1) }
                guard heartbeat.errorCode == nil else {
                    throw CheckError.failed("Runtime heartbeat failed: \(heartbeat.errorCode!); phase=\(heartbeat.hardwareExperiment?.phase ?? "missing"); attempts=\(try journal.loadAuthorityState(domain: .simulation)?.ledger?.attempts ?? [])")
                }
                observed = heartbeat.hardwareExperiment?.fixedRPMObserved == true
                RunLoop.current.run(until: Date().addingTimeInterval(0.1))
            }
            guard observed, try journal.loadSimulationDevice()?.effects.contains(.targetOne) == true else {
                let outcome = try journal.loadRecoveryOutcome()
                throw CheckError.failed("Runtime independent Fixed observation missing; attempts=\(try authority.state().ledger!.attempts); reason=\(outcome?.reason ?? "pending"); events=\(outcome?.events ?? [])")
            }
            _ = try rpc(client) { $0.restoreHardwareExperiment(session.uuidString, reply: $1) }
        }
        let deadline = HelperClock.now() + 5
        var final: HardwareExperimentReport?
        while HelperClock.now() < deadline {
            final = try rpc(stranger) { $0.hardwareExperimentStatus(reply: $1) }.hardwareExperiment
            if final?.phase == "autoCodesObserved" { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        guard let final, final.sessionID == session, final.domain == "simulation", final.phase == "autoCodesObserved",
              !final.pending, !final.physicalAutoVerified else { throw CheckError.failed("Runtime Auto result missing") }
        let ledger = try authority.state().ledger!
        let replay = try rpc(stranger) { $0.startApprovedHardwareExperiment(prompt.challenge.id.uuidString, planSHA256: prepared.planSHA256, reply: $1) }
        guard replay.errorCode != nil, try authority.state().ledger!.attempts == ledger.attempts,
              Set(ledger.attempts).count == ledger.attempts.count else { throw CheckError.failed("Runtime replay changed spent ledger") }
        if !disconnect {
            let evidenceDeadline = HelperClock.now() + 1
            while try journal.loadRecoveryOutcome() == nil, HelperClock.now() < evidenceDeadline {
                RunLoop.current.run(until: Date().addingTimeInterval(0.02))
            }
            guard let samples = try journal.loadRecoveryOutcome()?.observations,
                  samples.map(\.stage) == ["baseline", "fixed", "auto1", "auto2", "auto3"] else {
                throw CheckError.failed("Independent owner evidence not persisted")
            }
            let fixed = try JSONDecoder().decode(BrokerObservation.self, from: Data(samples[1].sampleJSON.utf8))
            guard fixed.fans.allSatisfy({ $0.actual == 2400 && $0.target == 2500 && $0.mode == 1 }), fixed.testMode == 1 else {
                throw CheckError.failed("Owner evidence lacks independent actual/target/mode values")
            }
        }
        print("Runtime XPC model: \(disconnect ? "connection invalidation" : "explicit Auto") passed; missing/wrong-owner approval, heartbeat, restore, status and replay; no hardware authority.")
        withExtendedLifetime(server) {}
    }
    for killBroker in [false, true] {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ventilator-runtime-restart-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let boot = UUID(), owner = UUID(), plan = try bundledCandidatePlan()
        let runtime = try ExperimentSessionRuntime.simulation(directory: directory, boot: boot)
        let journal = try FileSessionJournal(directory: directory)
        let review = try LocalApprovalReview(domain: .simulation, candidate: plan, ownerInstructions: "Model startup recovery; surviving broker or only remaining Auto after broker death.")
        try journal.saveLocalReview(review.canonicalJSON(), domain: .simulation)
        let issuer = try LocalApprovalIssuer.simulation(authority: runtime.authority, binaries: plan.binaries, boot: boot)
        let prompt = try issuer.prepare(owner: owner, planSHA256: plan.sha256(), reviewSHA256: review.sha256(), now: HelperClock.now())
        try issuer.confirm(prompt, response: prompt.confirmation, now: HelperClock.now())
        let started = try runtime.start(owner: owner, challengeID: prompt.challenge.id, planSHA256: plan.sha256())
        guard let session = started.sessionID else { throw CheckError.failed("Startup model session missing") }
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        let original = try journal.loadAuthorityState(domain: .simulation)!.ledger!
        if killBroker { try runtime.killModelBrokerForCheck() }
        else { runtime.disconnected(owner: owner) }
        let recovered = try ExperimentSessionRuntime.simulation(directory: directory, boot: boot)
        try recovered.recoverOnStartup()
        let deadline = HelperClock.now() + 5
        var report = try recovered.status()
        while report.phase != "autoCodesObserved", HelperClock.now() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05)); report = try recovered.status()
        }
        let final = try journal.loadAuthorityState(domain: .simulation)!.ledger!
        guard report.sessionID == session, report.phase == "autoCodesObserved", !report.pending,
              final.approval.challenge.id == prompt.challenge.id,
              final.attempts.filter(\.isFixed) == original.attempts.filter(\.isFixed),
              Set(final.attempts).count == final.attempts.count else { throw CheckError.failed("Startup recovery repeated Fixed/Auto") }
        print("Runtime startup model: \(killBroker ? "broker killed, remaining Auto only" : "surviving broker lifetime lock") passed; same receipt, no repeated Fixed/Auto.")
        withExtendedLifetime(runtime) {}
    }
}
