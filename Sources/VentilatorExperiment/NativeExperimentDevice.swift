import CSMCExperiment
import CryptoKit
import Darwin
import Foundation
import Security
import VentilatorControl

public enum NativeExperimentError: Error, Equatable {
    case simulationCannotOpenHardware, rootRequired, untrustedSignature, wrongBinary, invalidScope, openFailed
    case recoveryNotArmed, wrongBootSession
    case writeRejected(step: ExperimentStep, status: Int32, kernel: Int32, smcResult: UInt8, smcStatus: UInt8)
}

/// This factory is not connected to an XPC/CLI start command. Runtime recovery arming is still required
/// before wiring it to a hardware experiment. The GUI does not link this module.
public final class NativeExperimentDevice: ExperimentStepDevice {
    public let domain: ExperimentDomain = .hardware
    private let connection: OpaquePointer
    private let sessionID: UUID
    private let authority: ExperimentAuthority
    private let role: ExperimentDeviceRole
    private let recovery: ArmedHardwareRecovery

    public init(authority: ExperimentAuthority, sessionID: UUID, restorationOnly: Bool,
                recovery: ArmedHardwareRecovery? = nil) throws {
        guard authority.domain == .hardware else {
            throw NativeExperimentError.simulationCannotOpenHardware
        }
        guard geteuid() == 0 else { throw NativeExperimentError.rootRequired }
        guard let session = try authority.state().ledger, session.sessionID == sessionID,
              session.domain == .hardware, session.approval.domain == .hardware else { throw NativeExperimentError.invalidScope }
        guard currentBootSession() == session.approval.challenge.bootSession else { throw NativeExperimentError.wrongBootSession }
        guard let recovery else { throw NativeExperimentError.recoveryNotArmed }
        guard trustedHelperAndApplication() else { throw NativeExperimentError.untrustedSignature }
        let helper = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        let application = helper.deletingLastPathComponent().appendingPathComponent("Ventilator")
        let binaries = CandidateExperimentPlan.Binaries(applicationSHA256: CandidateExperimentPlan.digest(try Data(contentsOf: application)),
                                                       helperSHA256: CandidateExperimentPlan.digest(try Data(contentsOf: helper)))
        let plan = CandidateExperimentPlan(binaries: binaries)
        guard session.approval.challenge.binaries == binaries,
              session.approval.challenge.planSHA256 == (try plan.sha256()) else { throw NativeExperimentError.wrongBinary }
        let deadline: Double
        if restorationOnly {
            guard session.fixedClosed, session.pendingRestoration, let started = session.restoreStartedAt else {
                throw NativeExperimentError.invalidScope
            }
            deadline = started + plan.restorationDeadlineSeconds
        } else {
            guard !session.fixedClosed, session.pendingRestoration, session.attempts.isEmpty,
                  session.expiresAt == session.startedAt + plan.leaseSeconds else { throw NativeExperimentError.invalidScope }
            deadline = session.expiresAt
        }
        try recovery.confirm(session: session, role: restorationOnly ? .restoration : .fixed)
        guard let connection = SMCExperimentOpen(deadline, restorationOnly ? 1 : 0) else { throw NativeExperimentError.openFailed }
        self.connection = connection
        self.sessionID = sessionID
        self.authority = authority
        self.role = restorationOnly ? .restoration : .fixed
        self.recovery = recovery
    }

    deinit { SMCExperimentClose(connection) }

    public func write(_ reservation: ExperimentWriteReservation) throws {
        guard let beforeProbe = try authority.state().ledger else { throw NativeExperimentError.invalidScope }
        try recovery.confirm(session: beforeProbe, role: role)
        guard let current = try authority.state().ledger, let boot = currentBootSession() else {
            throw NativeExperimentError.invalidScope
        }
        guard recovery.sessionID == sessionID, recovery.planSHA256 == current.approval.challenge.planSHA256 else {
            throw NativeExperimentError.recoveryNotArmed
        }
        try ExperimentWriteAdmission.validate(reserved: reservation.ledger, current: current, step: reservation.step,
            domain: .hardware, sessionID: sessionID, boot: boot, now: ExperimentMonotonicClock.now(), role: role)
        let step = try reservation.consume(domain: .hardware, sessionID: sessionID)
        var result = SMCExperimentResult()
        let status = SMCExperimentWriteStep(connection, step.rawValue, &result)
        guard status == 0 else {
            throw NativeExperimentError.writeRejected(step: step, status: status,
                kernel: result.kernelStatus, smcResult: result.smcResult, smcStatus: result.smcStatus)
        }
    }
}

/// Only the future recovery broker in this module may issue a live witness. It has no public initializer
/// and cannot be decoded from an XPC payload. No hardware witness is issued by the current simulation worker.
public final class ArmedHardwareRecovery {
    private let probe: RecoveryProbeClient
    var sessionID: UUID { probe.scope.sessionID }
    var planSHA256: String { probe.scope.planSHA256 }

    internal init(session: ApprovedExperimentLedger, role: ExperimentDeviceRole, probe: RecoveryProbeClient) throws {
        self.probe = probe
        try confirm(session: session, role: role)
    }

    internal func confirm(session: ApprovedExperimentLedger, role: ExperimentDeviceRole) throws {
        guard geteuid() == 0, session.domain == .hardware, probe.scope.domain == .hardware,
              probe.scope.matches(session), probe.phase == (role == .fixed ? .fixed : .restoring),
              probe.deadline == (role == .fixed ? session.expiresAt : session.restoreStartedAt.map { $0 + 8 }),
              session.pendingRestoration, !session.autoCodesObserved,
              (role == .fixed ? !session.fixedClosed : session.fixedClosed) else { throw NativeExperimentError.recoveryNotArmed }
        do { try probe.confirm() } catch { throw NativeExperimentError.recoveryNotArmed }
    }
}

private func currentBootSession() -> UUID? {
    var bytes = [CChar](repeating: 0, count: 64)
    var size = bytes.count
    guard sysctlbyname("kern.bootsessionuuid", &bytes, &size, nil, 0) == 0 else { return nil }
    return bytes.withUnsafeBufferPointer { UUID(uuidString: String(cString: $0.baseAddress!)) }
}

private func trustedHelperAndApplication() -> Bool {
    var code: SecCode?, helperRequirement: SecRequirement?
    guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
          SecRequirementCreateWithString("anchor apple generic and identifier \"dev.ventilator.helper\"" as CFString, [], &helperRequirement) == errSecSuccess,
          let helperRequirement, SecCodeCheckValidity(code, [], helperRequirement) == errSecSuccess else { return false }
    var staticCode: SecStaticCode?, information: CFDictionary?
    guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
          SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &information) == errSecSuccess,
          let values = information as? [String: Any], let team = values[kSecCodeInfoTeamIdentifier as String] as? String,
          team.utf8.count == 10, team.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) }) else { return false }
    let helper = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
    let app = helper.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    var application: SecStaticCode?, requirement: SecRequirement?
    guard SecStaticCodeCreateWithPath(app as CFURL, [], &application) == errSecSuccess, let application,
          SecRequirementCreateWithString("anchor apple generic and identifier \"dev.ventilator.macos\" and certificate leaf[subject.OU] = \"\(team)\"" as CFString, [], &requirement) == errSecSuccess,
          let requirement else { return false }
    return SecStaticCodeCheckValidity(application, [], requirement) == errSecSuccess
}
