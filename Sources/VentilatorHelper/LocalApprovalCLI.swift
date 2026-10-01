import Darwin
import Foundation
import VentilatorControl
import VentilatorExperiment

let hardwareExperimentDirectory = URL(fileURLWithPath: "/Library/Application Support/Ventilator/Experiment", isDirectory: true)

func ownerHardwareAudit() throws {
    let boot = try HardwareRecoveryIdentity.currentBoot()
    let journal = try FileSessionJournal(directory: hardwareExperimentDirectory)
    let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
    var result: [String: Any] = ["hardwareControlAvailable": false, "physicalAutoVerified": false, "readOnlyAudit": true,
        "currentBootSession": boot.uuidString]
    if let state = try journal.loadAuthorityState(domain: .hardware) {
        result["authority"] = try JSONSerialization.jsonObject(with: encoder.encode(state))
    }
    if let outcome = try journal.loadHardwareRecoveryOutcome() {
        result["outcome"] = try JSONSerialization.jsonObject(with: encoder.encode(outcome))
    }
    print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), as: UTF8.self))
}

/// Review import is separate from approval and begin. Hardware import requires the same root TTY identity.
func stageLocalReview(domain: ExperimentDomain, directory: URL, source: URL, reviewSHA256: String) throws {
    if domain == .hardware {
        _ = try LocalApprovalIssuer.hardware(directory: hardwareExperimentDirectory)
        guard directory == hardwareExperimentDirectory else { throw LocalApprovalError.reviewMismatch }
    } else {
        guard geteuid() != 0 else { throw ExperimentAuthorityError.hardwareRequiresRoot }
    }
    let review = try LocalReviewFile.load(source, domain: domain, binaries: bundledCandidatePlan().binaries, expectedSHA256: reviewSHA256)
    let journal = try FileSessionJournal(directory: directory)
    guard try journal.loadAuthorityState(domain: domain)?.ledger == nil else { throw ExperimentAuthorityError.experimentAlreadyConsumed }
    try journal.saveLocalReview(review.canonicalJSON(), domain: domain)
    print("Review staged: \(try review.sha256()). No approval, begin or device access.")
}

/// This command creates approval only. It never begins a ledger, launches a writer or calls native SMC.
func runLocalApproval(domain: ExperimentDomain, directory: URL, owner: UUID,
                      planSHA256: String, reviewSHA256: String) throws {
    guard isatty(STDIN_FILENO) == 1, isatty(STDOUT_FILENO) == 1 else { throw ExperimentAuthorityError.localTerminalRequired }
    let issuer: LocalApprovalIssuer
    if domain == .hardware { issuer = try .hardware(directory: directory) }
    else {
        guard geteuid() != 0 else { throw CheckError.failed("Model approval requires non-root") }
        let authority = try ExperimentAuthority(directory: directory, domain: .simulation)
        // Model boot is local to this test directory; it cannot become a hardware boot binding.
        let boot = try authority.state().challenge?.bootSession ?? UUID()
        issuer = try .simulation(authority: authority, binaries: bundledCandidatePlan().binaries, boot: boot)
    }
    let prompt = try issuer.prepare(owner: owner, planSHA256: planSHA256, reviewSHA256: reviewSHA256, now: HelperClock.now())
    print(domain == .hardware ? "HARDWARE LOCAL APPROVAL — no writes are executed by this command." : "SIMULATION LOCAL APPROVAL — cannot authorize hardware.")
    print(prompt.review.ownerInstructions)
    print(String(decoding: try prompt.review.candidate.canonicalJSON(), as: UTF8.self))
    print("Owner: \(owner.uuidString); challenge: \(prompt.challenge.id.uuidString); approval window: 300 seconds.")
    print("To approve exactly this plan and review, type:\n\(prompt.confirmation)")
    fflush(stdout)
    try issuer.confirm(prompt, response: readLine(strippingNewline: true), now: HelperClock.now())
    print("Approval saved for challenge \(prompt.challenge.id.uuidString). No experiment started; only this connection may consume the receipt.")
}
