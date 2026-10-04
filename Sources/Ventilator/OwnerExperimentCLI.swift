import Darwin
import Foundation
import VentilatorControl
import VentilatorInstallation

/// Explicit Terminal command only. The GUI never constructs this session or starts hardware.
func runOwnerExperimentCommand(_ arguments: [String]) -> Bool {
    guard let command = arguments.first, ["--run-owner-experiment", "--owner-experiment-status", "--qualify-owner-signature"].contains(command) else { return false }
    var startRequested = false
    do {
        if command == "--qualify-owner-signature" {
            guard arguments.count == 3 else { throw InstallationError.invalidChallenge }
            let proof = try CertificateQualification.qualify(bundle: URL(fileURLWithPath: arguments[1]), certificateSHA1: arguments[2])
            try printOwnerJSON(["certificateSHA1": arguments[2], "teamIdentifier": proof.teamIdentifier,
                "fingerprint": ["applicationSHA256": proof.fingerprint.applicationSHA256, "helperSHA256": proof.fingerprint.helperSHA256,
                    "launchDaemonSHA256": proof.fingerprint.launchDaemonSHA256],
                "positiveRevocation": true, "notarizationClaimed": false])
            return true
        }
        guard command == "--run-owner-experiment" ? arguments.count == 2 : arguments.count == 1 else { throw InstallationError.invalidChallenge }
        let proof = try SignedBundleInspector.requireCurrentProcess(role: .application)
        let client = try InstalledHelperSession(proof: proof)
        defer { client.close() }
        if command == "--owner-experiment-status" { try printOwnerReply(client.status()); return true }
        guard isatty(STDIN_FILENO) == 1, isatty(STDOUT_FILENO) == 1, isDigest(arguments[1]),
              !client.installation.pendingHardwareRestoration else { throw InstallationError.invalidChallenge }
        let candidate = CandidateExperimentPlan(binaries: .init(applicationSHA256: proof.fingerprint.applicationSHA256,
            helperSHA256: proof.fingerprint.helperSHA256)), planSHA = try candidate.sha256()
        let prepared = try client.prepare()
        guard prepared.errorCode == nil, let p = prepared.preparation, p.runtimePrepared,
              p.planSHA256 == planSHA, let owner = p.connectionOwner else { throw InstallationError.invalidReply }
        print("ТЕРМИНАЛ A — запуск пока не запрашивался. Оставьте это окно открытым.")
        print("1. Откройте второе окно Terminal (B). Скопируйте туда всю следующую команду:")
        print("sudo /Applications/Ventilator.app/Contents/MacOS/VentilatorHelper --approve-local-hardware \(owner.uuidString) \(planSHA) \(arguments[1])")
        print("2. В B прочитайте план и скопируйте полную строку APPROVE с UUID и двумя хешами. Одного слова APPROVE недостаточно.")
        print("3. Только после «Approval saved» в B скопируйте оттуда полную строку START с UUID в это окно A.")
        print("ТЕРМИНАЛ A — ожидаю START <challenge UUID>. APPROVE вводится только в B; CANCEL отменяет.")
        fflush(stdout)
        let challenge = try OwnerExperimentTerminal.startChallenge(from: readLine())
        let started = InstalledHelperClient.clock()
        startRequested = true // A failed/late RPC can already have consumed the receipt; never claim otherwise.
        let initial = try client.start(challenge: challenge, planSHA256: planSHA)
        guard initial.errorCode == nil, let first = initial.hardwareExperiment, let session = first.sessionID else {
            try printOwnerReply(initial); throw InstallationError.invalidReply
        }
        try printOwnerReply(initial)
        var restoreSent = false
        while InstalledHelperClient.clock() < started + 25 {
            let reply = restoreSent ? try client.status() : try client.heartbeat(session: session)
            guard reply.errorCode == nil, let report = reply.hardwareExperiment, report.sessionID == session else {
                try printOwnerReply(reply); throw InstallationError.invalidReply
            }
            if report.phase == "autoCodesObserved" {
                try printOwnerReply(reply)
                print("Auto codes observed. Hardware pending is retained; physical recovery and product readiness remain unverified.")
                return true
            }
            if report.phase == "recoveryRequired" { try printOwnerReply(reply); throw InstallationError.pendingRecovery }
            if report.fixedRPMObserved && !restoreSent {
                restoreSent = true
                try printOwnerReply(client.restore(session: session))
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        throw InstallationError.deadline
    } catch {
        let detail: String
        if command == "--run-owner-experiment" {
            detail = startRequested ?
                "Connection closed; if a broker started, it retains its independent Auto duty. Do not retry Fixed or erase pending. Follow the owner-session stop plan." :
                "Аппаратный запуск не запрашивался. Terminal A принимает полную START <challenge UUID> после одобрения в B. Сеанс закрыт; ничего не повторяйте, сообщите разработчику."
        } else {
            detail = "No experiment was started by this diagnostic command. Follow the owner-session stop plan."
        }
        fputs("Owner experiment: \(error). \(detail)\n", stderr)
        exit(78)
    }
    return true
}

private func isDigest(_ value: String) -> Bool {
    value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
}
private func printOwnerJSON(_ object: [String: Any]) throws {
    print(String(decoding: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]), as: UTF8.self))
}
private func printOwnerReply(_ reply: HelperReply) throws {
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
    print(String(decoding: try encoder.encode(reply), as: UTF8.self)); fflush(stdout)
}
