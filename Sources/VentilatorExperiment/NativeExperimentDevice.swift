import CSMCExperiment
import CryptoKit
import Darwin
import Foundation
import Security
import VentilatorControl
import VentilatorInstallation

public enum NativeExperimentError: Error, Equatable {
    case simulationCannotOpenHardware, rootRequired, untrustedSignature, wrongBinary, invalidScope, openFailed
    case recoveryNotArmed, wrongBootSession
    case writeRejected(step: ExperimentStep, status: Int32, kernel: Int32, smcResult: UInt8, smcStatus: UInt8)
}

/// Prepared child factory. Public XPC start remains closed until installed validation and the owner
/// session are ready. The GUI does not link this module.
public final class NativeExperimentDevice: ExperimentStepDevice {
    public let domain: ExperimentDomain = .hardware
    private let connection: OpaquePointer
    private let sessionID: UUID
    private let authority: ExperimentAuthority
    private let role: ExperimentDeviceRole
    private let recovery: ArmedHardwareRecovery
    private let executionLock: SessionJournalLock

    public init(authority: ExperimentAuthority, sessionID: UUID, restorationOnly: Bool,
                recovery: ArmedHardwareRecovery? = nil) throws {
        guard authority.domain == .hardware else {
            throw NativeExperimentError.simulationCannotOpenHardware
        }
        guard geteuid() == 0 else { throw NativeExperimentError.rootRequired }
        let executionLock = try FileSessionJournal(directory: authority.directory).acquireDeviceExecutionLock(domain: .hardware)
        guard let session = try authority.state().ledger, session.sessionID == sessionID,
              session.domain == .hardware, session.approval.domain == .hardware,
              session.approval.challenge.ownerReviewSHA256 != nil else { throw NativeExperimentError.invalidScope }
        guard currentBootSession() == session.approval.challenge.bootSession else { throw NativeExperimentError.wrongBootSession }
        guard let recovery else { throw NativeExperimentError.recoveryNotArmed }
        guard trustedHelperAndApplication() else { throw NativeExperimentError.untrustedSignature }
        let helper = try CurrentExecutable.url()
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
        self.executionLock = executionLock
    }

    deinit { withExtendedLifetime(executionLock) { SMCExperimentClose(connection) } }

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
        if step.isFixed, try authority.fixedRevoked(sessionID: sessionID) { throw ExperimentAuthorityError.fixedClosed }
        var result = SMCExperimentResult()
        let status = SMCExperimentWriteStep(connection, step.rawValue, &result)
        guard status == 0 else {
            throw NativeExperimentError.writeRejected(step: step, status: status,
                kernel: result.kernelStatus, smcResult: result.smcResult, smcStatus: result.smcStatus)
        }
    }
}

/// The scoped hardware child may issue this witness only from a live broker probe and consumed hardware
/// ledger. It has no public initializer and cannot be decoded from XPC. Simulation never issues it.
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

internal func currentBootSession() -> UUID? {
    var bytes = [CChar](repeating: 0, count: 64)
    var size = bytes.count
    guard sysctlbyname("kern.bootsessionuuid", &bytes, &size, nil, 0) == 0 else { return nil }
    return bytes.withUnsafeBufferPointer { UUID(uuidString: String(cString: $0.baseAddress!)) }
}

public enum HardwareRecoveryIdentity {
    /// Read-only identity validation. Restart recovery never accepts a boot UUID from IPC or a saved PID.
    public static func currentBoot() throws -> UUID {
        guard geteuid() == 0, ExperimentMachine.current() == .candidate, trustedHelperAndApplication() else {
            throw NativeExperimentError.untrustedSignature
        }
        guard let boot = currentBootSession() else { throw NativeExperimentError.wrongBootSession }
        return boot
    }
}

internal func trustedHelperAndApplication() -> Bool {
    (try? SignedBundleInspector.requireCurrentProcess(role: .helper)) != nil
}
