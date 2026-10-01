import Darwin
import Foundation
import VentilatorControl
import VentilatorExperiment

let hardwareExperimentDirectory = URL(fileURLWithPath: "/Library/Application Support/Ventilator/Experiment", isDirectory: true)

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
    print("Approval saved. No experiment started; public hardware start remains disabled.")
}
