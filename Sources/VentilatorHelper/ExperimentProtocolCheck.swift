import CSMCExperiment
import Foundation
import VentilatorControl
import VentilatorExperiment

/// The only device instantiated here is SimulatedStepDevice; native packet builders are pure.
func experimentProtocolCheck() throws {
    let plan = try bundledCandidatePlan()
    for (index, write) in (plan.fixedWrites + plan.restoreWrites).enumerated() {
        var description = SMCExperimentStep(), packet = SMCExperimentRequest()
        guard SMCExperimentDescribeStep(UInt32(index), &description) == 0,
              SMCExperimentBuildRequest(UInt32(index), description.type, description.size, &packet) == 0 else {
            throw CheckError.failed("Native packet description")
        }
        let key = withUnsafeBytes(of: description.key) { String(decoding: $0.prefix(4), as: UTF8.self) }
        let payload = withUnsafeBytes(of: description.payload) { $0.prefix(Int(description.size)).map { String(format: "%02x", $0) }.joined() }
        guard key == write.key, payload == write.payloadHex else { throw CheckError.failed("Packet drifted from review plan") }
    }
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ventilator-authority-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let authority = try ExperimentAuthority(directory: directory, domain: .simulation)
    let owner = UUID(), boot = UUID(), device = SimulatedStepDevice()
    let date: (Double) -> Date = { Date(timeIntervalSince1970: 1000 + $0) }
    let challenge = try authority.prepare(owner: owner, plan: plan, boot: boot, now: 0)
    try authority.approveLocally(challengeID: challenge.id, planSHA256: plan.sha256(), boot: boot, now: 1)
    let session = try authority.begin(owner: owner, challengeID: challenge.id, plan: plan, binaries: plan.binaries,
        boot: boot, now: 2, observation: device.observation(at: date(2)), date: date(2))
    let executor = try ApprovedStepExecutor(authority: authority, sessionID: session.sessionID, device: device)
    for (step, now) in [(ExperimentStep.unlock, 2.0), (.manualZero, 5), (.manualOne, 5.1), (.targetZero, 5.2), (.targetOne, 5.3)] {
        try executor.perform(step, now: now, date: date(now), observation: device.observation(at: date(now)))
    }
    _ = try authority.closeFixedAndBeginRestoration(sessionID: session.sessionID, now: 6, date: date(6))
    for step in ExperimentStep.allCases.filter({ !$0.isFixed }) {
        try executor.perform(step, now: 6, date: date(6), observation: device.observation(at: date(6)))
    }
    try authority.finishObservedRestoration(sessionID: session.sessionID, samples: (7...9).map { device.observation(at: date(Double($0))) }, now: 9, date: date(9))
    guard device.effects == ExperimentStep.allCases, try authority.state().ledger?.pendingRestoration == false else {
        throw CheckError.failed("Approved simulation steps did not finish")
    }
    do {
        _ = try ExperimentAuthority(directory: directory, domain: .simulation).begin(owner: owner, challengeID: challenge.id,
            plan: plan, binaries: plan.binaries, boot: boot, now: 10, observation: device.observation(at: date(10)), date: date(10))
        throw CheckError.failed("Approval replay was accepted")
    } catch ExperimentAuthorityError.experimentAlreadyConsumed {}
    print("Experiment protocol: ten native packet descriptions match plan; simulated approval/steps/Auto-code reads passed; persisted approval replay refused. No native open/write called.")
}
