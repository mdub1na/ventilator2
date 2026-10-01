import Foundation
import VentilatorControl

public enum BrokerRestartError: Error, Equatable { case binding, alreadyObserved, deviceStillActive, originalDeadlineExpired }

/// Holds proof of device quiescence across ledger closure and monitor creation, without using a saved PID.
/// Release before spawning the sole Auto child; all future Fixed init/reservations see durable closure.
public final class BrokerRestartRecovery {
    public let ledger: ApprovedExperimentLedger
    public let remainingSteps: [ExperimentStep]
    public let ambiguousAutoSteps: [ExperimentStep]
    private var deviceLock: SessionJournalLock?

    public init(authority: ExperimentAuthority, sessionID: UUID, boot: UUID,
                binaries: CandidateExperimentPlan.Binaries, now: Double, date: Date) throws {
        guard let before = try authority.state().ledger, before.sessionID == sessionID,
              before.domain == authority.domain, before.approval.challenge.bootSession == boot,
              before.approval.challenge.binaries == binaries,
              before.approval.challenge.planSHA256 == (try CandidateExperimentPlan(binaries: binaries).sha256()) else {
            throw BrokerRestartError.binding
        }
        guard before.pendingRestoration, !before.autoCodesObserved else { throw BrokerRestartError.alreadyObserved }
        // Revoke an earlier reservation before waiting for any device connection to close.
        try authority.closeFixed(sessionID: sessionID, now: now)
        do { deviceLock = try FileSessionJournal(directory: authority.directory).acquireDeviceExecutionLock(domain: authority.domain) }
        catch { throw BrokerRestartError.deviceStillActive }
        let closed = try authority.closeFixedAndBeginRestoration(sessionID: sessionID, now: now, date: date)
        guard let started = closed.restoreStartedAt, now < started + 8 else { throw BrokerRestartError.originalDeadlineExpired }
        ledger = closed
        remainingSteps = ExperimentStep.allCases.filter { !$0.isFixed && !closed.attempts.contains($0) }
        ambiguousAutoSteps = closed.attempts.filter { !$0.isFixed && !(closed.successfulReturns ?? []).contains($0) }
    }

    public func releaseForAutoChild() { deviceLock = nil }
}
