import Foundation
import VentilatorControl

/// A private pipe handshake binds a child to the consumed ledger. It does not grant write authority.
public struct RecoveryScope: Codable, Equatable {
    public let domain: ExperimentDomain
    public let sessionID: UUID
    public let planSHA256: String
    public let bootSession: UUID
    public let owner: UUID
    public let expiresAt: Double
    public let nonce: UUID

    public init(ledger: ApprovedExperimentLedger) {
        domain = ledger.domain; sessionID = ledger.sessionID
        planSHA256 = ledger.approval.challenge.planSHA256
        bootSession = ledger.approval.challenge.bootSession
        owner = ledger.approval.challenge.connectionOwner
        expiresAt = ledger.expiresAt; nonce = UUID()
    }

    public func matches(_ ledger: ApprovedExperimentLedger) -> Bool {
        domain == ledger.domain && sessionID == ledger.sessionID &&
            planSHA256 == ledger.approval.challenge.planSHA256 &&
            bootSession == ledger.approval.challenge.bootSession &&
            owner == ledger.approval.challenge.connectionOwner && expiresAt == ledger.expiresAt
    }
}

public enum RecoveryPhase: String, Codable { case fixed, quiescing, restoring, autoCodesObserved, recoveryRequired }
public enum RecoveryFailure: Error { case binding, clock, phase }

/// Serialized by a dedicated broker, independent of the helper and of blocking device calls.
/// Auto is allowed only after the exact writer child has exited. SIGKILL alone is not that proof.
public final class RecoveryMonitor {
    public static let operationSeconds = CandidateExperimentPlan.operationSeconds
    public static let quiescenceSeconds = CandidateExperimentPlan.writerQuiescenceSeconds
    public let scope: RecoveryScope
    public private(set) var phase: RecoveryPhase = .fixed
    public private(set) var reason: String?
    public private(set) var restorationStartedAt: Double?
    public private(set) var pendingOperation: UUID?
    private var operationDeadline: Double?
    private var heartbeatDeadline: Double
    private var quiescenceDeadline: Double?
    private var lastClock: Double

    public init(ledger: ApprovedExperimentLedger, now: Double) throws {
        guard ledger.pendingRestoration, !ledger.fixedClosed, ledger.attempts.isEmpty,
              now.isFinite, now >= ledger.startedAt, now < ledger.expiresAt else { throw RecoveryFailure.phase }
        scope = RecoveryScope(ledger: ledger)
        heartbeatDeadline = min(now + 2, ledger.expiresAt)
        lastClock = now
    }

    /// A new nonce revokes old broker replies; no Fixed phase and no fresh eight-second budget.
    public init(restarting recovery: BrokerRestartRecovery, now: Double) throws {
        let ledger = recovery.ledger
        guard ledger.fixedClosed, ledger.pendingRestoration, !ledger.autoCodesObserved,
              let started = ledger.restoreStartedAt, now.isFinite, now >= ledger.lastClock,
              now < started + 8 else { throw RecoveryFailure.phase }
        scope = RecoveryScope(ledger: ledger); heartbeatDeadline = ledger.expiresAt; lastClock = now
        phase = .restoring; reason = "brokerRestart"; restorationStartedAt = started
    }

    public func heartbeat(scope received: RecoveryScope, now: Double) throws {
        guard received == scope else { throw RecoveryFailure.binding }
        tick(now: now)
        guard phase == .fixed else { throw RecoveryFailure.phase }
        heartbeatDeadline = min(now + 2, scope.expiresAt)
    }

    /// A writer probe checks current broker state without renewing the owner's heartbeat or operation budget.
    public func reply(to request: RecoveryProbeRequest, now: Double) throws -> RecoveryProbeReply {
        guard request.scope == scope else { throw RecoveryProbeError.binding }
        tick(now: now)
        guard [.fixed, .restoring].contains(phase) else { throw RecoveryProbeError.wrongPhase }
        let sessionDeadline = phase == .fixed ? scope.expiresAt : restorationStartedAt! + 8
        guard request.deadline.isFinite, request.deadline > now,
              request.deadline <= min(sessionDeadline, now + CandidateExperimentPlan.operationSeconds) else {
            throw RecoveryProbeError.expired
        }
        return .init(id: request.id, scope: scope, phase: phase, deadline: request.deadline)
    }

    public func beginOperation(id: UUID, now: Double) throws {
        tick(now: now)
        guard [.fixed, .restoring].contains(phase), pendingOperation == nil else { throw RecoveryFailure.phase }
        pendingOperation = id
        operationDeadline = now + Self.operationSeconds
    }

    public func acknowledge(id: UUID, scope received: RecoveryScope, now: Double) throws {
        guard received == scope, pendingOperation == id else { throw RecoveryFailure.binding }
        tick(now: now) // A late acknowledgement cannot revive the writer or renew an Auto budget.
        guard [.fixed, .restoring].contains(phase) else { throw RecoveryFailure.phase }
        pendingOperation = nil; operationDeadline = nil
    }

    public func stop(reason: String, now: Double) {
        guard phase == .fixed else { return }
        let epoch = now.isFinite && now >= lastClock ? now : lastClock
        lastClock = epoch
        self.reason = reason
        phase = .quiescing
        quiescenceDeadline = epoch + Self.quiescenceSeconds
        pendingOperation = nil; operationDeadline = nil
    }

    public func confirmWriterExited(now: Double, restorationStartedAt existingEpoch: Double? = nil) throws {
        tick(now: now)
        guard phase == .quiescing else { throw RecoveryFailure.phase }
        let epoch = existingEpoch ?? now
        guard epoch.isFinite, epoch >= scope.expiresAt - 10, epoch <= now, now < epoch + 8 else {
            fail(reason: "restorationExpired"); throw RecoveryFailure.clock
        }
        phase = .restoring
        restorationStartedAt = epoch
        pendingOperation = nil; operationDeadline = nil
    }

    public func observeAutoCodes(now: Double) throws {
        tick(now: now)
        guard phase == .restoring, pendingOperation == nil else { throw RecoveryFailure.phase }
        phase = .autoCodesObserved
    }

    public func fail(reason: String) {
        guard phase != .autoCodesObserved else { return }
        self.reason = reason; phase = .recoveryRequired
    }

    public func tick(now: Double) {
        guard [.fixed, .quiescing, .restoring].contains(phase) else { return }
        guard now.isFinite, now >= lastClock else {
            if phase == .fixed { stop(reason: "clockFailure", now: lastClock) }
            else { fail(reason: "clockFailure") }
            return
        }
        lastClock = now
        switch phase {
        case .fixed:
            if now >= scope.expiresAt { stop(reason: "leaseExpired", now: now) }
            else if now >= heartbeatDeadline { stop(reason: "heartbeatLost", now: now) }
            else if operationDeadline.map({ now >= $0 }) ?? false { stop(reason: "writerTimeout", now: now) }
        case .quiescing:
            if now >= quiescenceDeadline! { fail(reason: "writerNotQuiescent") }
        case .restoring:
            if now >= restorationStartedAt! + 8 { fail(reason: "restorationExpired") }
            else if operationDeadline.map({ now >= $0 }) ?? false { fail(reason: "restorerTimeout") }
        default: break
        }
    }
}
