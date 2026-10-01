import Darwin
import Foundation
import VentilatorCore

public enum ExperimentDomain: String, Codable, Sendable { case simulation, hardware }
public enum ExperimentStep: UInt32, Codable, CaseIterable, Sendable {
    case unlock = 0, manualZero, manualOne, targetZero, targetOne
    case autoZero, autoOne, clearTargetZero, clearTargetOne, releaseUnlock
    public var isFixed: Bool { rawValue < 5 }
}

public struct OwnerApprovalChallenge: Codable, Equatable {
    public let id: UUID
    public let connectionOwner: UUID
    public let planSHA256: String
    public let binaries: CandidateExperimentPlan.Binaries
    public let bootSession: UUID
    public let issuedAt: Double
    public let expiresAt: Double
}

public struct OwnerApproval: Codable, Equatable {
    public let domain: ExperimentDomain
    public let challenge: OwnerApprovalChallenge
    public let approvedAt: Double
}

public struct ApprovedExperimentLedger: Codable, Equatable {
    public let domain: ExperimentDomain
    public let sessionID: UUID
    public let approval: OwnerApproval
    public let startedAt: Double
    public let expiresAt: Double
    public var pendingRestoration: Bool
    public var autoCodesObserved: Bool
    public var fixedClosed: Bool
    public var restoreStartedAt: Double?
    public var restoreRequestedDate: Date?
    public var unlockReservedAt: Double?
    public var attempts: [ExperimentStep]
    public var lastClock: Double
}

public struct ExperimentAuthorityState: Codable {
    public var challenge: OwnerApprovalChallenge?
    public var approval: OwnerApproval?
    public var ledger: ApprovedExperimentLedger?
    public init() {}
}

public enum ExperimentAuthorityError: Error, Equatable {
    case hardwareRequiresRoot, localTerminalRequired, invalidClock, planMismatch, challengeMismatch
    case approvalMissing, approvalExpired, wrongConnection, experimentAlreadyConsumed, pendingChallenge
    case wrongSession, leaseExpired, fixedClosed, stepOrder, stepAlreadyAttempted, unsafeObservation
    case restoreNotStarted, restorationExpired, unverifiedRestoration
    case reservationConsumed, reservationScope
}

/// Non-Codable and constructible only after the authority's durable reservation transaction.
public final class ExperimentWriteReservation {
    public let ledger: ApprovedExperimentLedger
    public let step: ExperimentStep
    private let lock = NSLock()
    private var consumed = false
    fileprivate init(ledger: ApprovedExperimentLedger, step: ExperimentStep) { self.ledger = ledger; self.step = step }

    public func consume(domain: ExperimentDomain, sessionID: UUID) throws -> ExperimentStep {
        lock.lock(); defer { lock.unlock() }
        guard ledger.domain == domain, ledger.sessionID == sessionID else { throw ExperimentAuthorityError.reservationScope }
        guard !consumed else { throw ExperimentAuthorityError.reservationConsumed }
        consumed = true
        return step
    }
}

/// A local terminal issues consent; no XPC method issues it. Simulation receipts stay in a different file.
/// Root ownership is necessary for hardware state, but signing/readiness must also be checked by the helper.
public final class ExperimentAuthority {
    public static let approvalSeconds = 300.0
    private let journal: FileSessionJournal
    public let domain: ExperimentDomain

    public init(directory: URL, domain: ExperimentDomain) throws {
        if domain == .hardware && geteuid() != 0 { throw ExperimentAuthorityError.hardwareRequiresRoot }
        journal = try FileSessionJournal(directory: directory)
        self.domain = domain
    }

    public func state() throws -> ExperimentAuthorityState {
        let ownership = try journal.acquireAuthorityLock(domain: domain)
        defer { withExtendedLifetime(ownership) {} }
        return try journal.loadAuthorityState(domain: domain) ?? ExperimentAuthorityState()
    }

    public func prepare(owner: UUID, plan: CandidateExperimentPlan, boot: UUID, now: Double) throws -> OwnerApprovalChallenge {
        try checkClock(now)
        guard plan == CandidateExperimentPlan(binaries: plan.binaries), validHash(plan.binaries.applicationSHA256),
              validHash(plan.binaries.helperSHA256) else { throw ExperimentAuthorityError.planMismatch }
        return try transaction { state in
            guard state.ledger == nil else { throw ExperimentAuthorityError.experimentAlreadyConsumed }
            if let previous = state.challenge, now >= previous.issuedAt, now < previous.expiresAt {
                guard previous.connectionOwner == owner, previous.bootSession == boot,
                      previous.planSHA256 == (try plan.sha256()) else { throw ExperimentAuthorityError.pendingChallenge }
                return previous
            }
            let challenge = OwnerApprovalChallenge(id: UUID(), connectionOwner: owner, planSHA256: try plan.sha256(),
                                                    binaries: plan.binaries, bootSession: boot,
                                                    issuedAt: now, expiresAt: now + Self.approvalSeconds)
            state.challenge = challenge
            state.approval = nil
            return challenge
        }
    }

    public func approveLocally(challengeID: UUID, planSHA256: String, boot: UUID, now: Double) throws {
        try checkClock(now)
        if domain == .hardware && (geteuid() != 0 || isatty(STDIN_FILENO) != 1 || isatty(STDOUT_FILENO) != 1) {
            throw ExperimentAuthorityError.localTerminalRequired
        }
        try transaction { state in
            guard state.ledger == nil else { throw ExperimentAuthorityError.experimentAlreadyConsumed }
            guard let challenge = state.challenge, challenge.id == challengeID,
                  challenge.planSHA256 == planSHA256, challenge.bootSession == boot else {
                throw ExperimentAuthorityError.challengeMismatch
            }
            guard now >= challenge.issuedAt, now < challenge.expiresAt else { throw ExperimentAuthorityError.approvalExpired }
            state.approval = OwnerApproval(domain: domain, challenge: challenge, approvedAt: now)
        }
    }

    /// Consumes the approval durably before any step. A restart cannot start fixed again, even after success.
    public func begin(owner: UUID, challengeID: UUID, plan: CandidateExperimentPlan,
                      binaries: CandidateExperimentPlan.Binaries, boot: UUID, now: Double,
                      observation: ControlObservation, date: Date) throws -> ApprovedExperimentLedger {
        try checkClock(now)
        guard plan.matchesCandidate(binaries: binaries, observation: observation, now: date) else {
            throw ExperimentAuthorityError.planMismatch
        }
        return try transaction { state in
            guard state.ledger == nil else { throw ExperimentAuthorityError.experimentAlreadyConsumed }
            guard let approval = state.approval, approval.domain == domain else { throw ExperimentAuthorityError.approvalMissing }
            let challenge = approval.challenge
            guard challenge.id == challengeID, state.challenge == challenge, challenge.bootSession == boot,
                  challenge.planSHA256 == (try plan.sha256()), challenge.binaries == binaries else {
                throw ExperimentAuthorityError.challengeMismatch
            }
            guard challenge.connectionOwner == owner else { throw ExperimentAuthorityError.wrongConnection }
            guard now >= approval.approvedAt, now >= challenge.issuedAt, now < challenge.expiresAt else {
                throw ExperimentAuthorityError.approvalExpired
            }
            let ledger = ApprovedExperimentLedger(domain: domain, sessionID: UUID(), approval: approval,
                startedAt: now, expiresAt: now + plan.leaseSeconds, pendingRestoration: true, autoCodesObserved: false, fixedClosed: false,
                restoreStartedAt: nil, restoreRequestedDate: nil, unlockReservedAt: nil, attempts: [], lastClock: now)
            state.ledger = ledger
            return ledger
        }
    }

    /// The budget is consumed before I/O, including failed calls. There is no retry of an attempted step.
    public func reserve(step: ExperimentStep, sessionID: UUID, owner: UUID, boot: UUID, now: Double,
                        observation: ControlObservation, date: Date) throws -> ExperimentWriteReservation {
        try checkClock(now)
        let ledger = try transaction { state in
            guard var ledger = state.ledger, ledger.domain == domain, ledger.sessionID == sessionID,
                  ledger.approval.challenge.bootSession == boot else { throw ExperimentAuthorityError.wrongSession }
            guard now >= ledger.lastClock else { throw ExperimentAuthorityError.invalidClock }
            guard !ledger.attempts.contains(step) else { throw ExperimentAuthorityError.stepAlreadyAttempted }
            if step.isFixed {
                guard ledger.approval.challenge.connectionOwner == owner else { throw ExperimentAuthorityError.wrongConnection }
                guard !ledger.fixedClosed else { throw ExperimentAuthorityError.fixedClosed }
                guard now < ledger.expiresAt else { throw ExperimentAuthorityError.leaseExpired }
                guard ledger.attempts.filter(\.isFixed).count == Int(step.rawValue),
                      ledger.attempts.allSatisfy(\.isFixed) else { throw ExperimentAuthorityError.stepOrder }
                guard fixedObservationAllowed(step: step, ledger: ledger, observation: observation, date: date, now: now) else {
                    throw ExperimentAuthorityError.unsafeObservation
                }
            } else {
                guard let started = ledger.restoreStartedAt else { throw ExperimentAuthorityError.restoreNotStarted }
                guard now < started + 8, ledger.pendingRestoration else { throw ExperimentAuthorityError.restorationExpired }
                guard restoreObservationAllowed(step: step, observation: observation, date: date) else {
                    throw ExperimentAuthorityError.unsafeObservation
                }
            }
            ledger.attempts.append(step)
            if step == .unlock { ledger.unlockReservedAt = now }
            ledger.lastClock = now
            state.ledger = ledger
            return ledger
        }
        return ExperimentWriteReservation(ledger: ledger, step: step)
    }

    /// Revoke further reservations before stopping the writer. This alone does not prove quiescence.
    public func closeFixed(sessionID: UUID, now: Double) throws {
        try checkClock(now)
        try transaction { state in
            guard var ledger = state.ledger, ledger.sessionID == sessionID else { throw ExperimentAuthorityError.wrongSession }
            guard now >= ledger.lastClock else { throw ExperimentAuthorityError.invalidClock }
            ledger.fixedClosed = true; ledger.lastClock = now
            state.ledger = ledger
        }
    }

    public func closeFixedAndBeginRestoration(sessionID: UUID, now: Double, date: Date) throws -> ApprovedExperimentLedger {
        try checkClock(now)
        return try transaction { state in
            guard var ledger = state.ledger, ledger.sessionID == sessionID else { throw ExperimentAuthorityError.wrongSession }
            // A broken clock must not persist a restoration epoch before the consumed session.
            guard now >= ledger.lastClock else { throw ExperimentAuthorityError.invalidClock }
            ledger.fixedClosed = true
            if ledger.restoreStartedAt == nil { ledger.restoreStartedAt = now; ledger.restoreRequestedDate = date }
            ledger.lastClock = max(ledger.lastClock, now)
            state.ledger = ledger
            return ledger
        }
    }

    /// Marks only observed codes; the spent approval and audit budget are retained permanently.
    public func finishObservedRestoration(sessionID: UUID, samples: [ControlObservation], now: Double, date: Date) throws {
        try checkClock(now)
        try transaction { state in
            guard var ledger = state.ledger, ledger.sessionID == sessionID,
                  let started = ledger.restoreStartedAt, let requestedDate = ledger.restoreRequestedDate,
                  now >= ledger.lastClock, now < started + 8,
                  samples.count >= 3, samples.suffix(3).allSatisfy({ $0.testModeCode == 0 && activeProfile($0, date: date) }),
                  ExperimentVerification.autoModeSustained(samples.map(\.snapshot), after: requestedDate) else {
                throw ExperimentAuthorityError.unverifiedRestoration
            }
            ledger.fixedClosed = true
            ledger.autoCodesObserved = true
            // Mode codes are not physical proof. Hardware keeps the pending record for the owner-session result.
            if domain == .simulation { ledger.pendingRestoration = false }
            ledger.lastClock = now
            state.ledger = ledger
        }
    }

    private func fixedObservationAllowed(step: ExperimentStep, ledger: ApprovedExperimentLedger,
                                         observation: ControlObservation, date: Date, now: Double) -> Bool {
        guard activeProfile(observation, date: date), observation.thermalPressure == .nominal else { return false }
        let fans = observation.snapshot.fans
        guard fans[0].minimumRPM == 1350, fans[0].maximumRPM == 5349,
              fans[1].minimumRPM == 1458, fans[1].maximumRPM == 5777 else { return false }
        if step == .unlock {
            return observation.testModeCode == 0 && ExperimentVerification.preflight(observation.snapshot, now: date, thermalPressure: observation.thermalPressure) == nil
        }
        guard observation.testModeCode == 1, let unlocked = ledger.unlockReservedAt, now - unlocked >= 3 else { return false }
        switch step {
        case .manualZero: return fans.map(\.modeCode) == [3, 3]
        case .manualOne: return fans.map(\.modeCode) == [1, 3]
        case .targetZero: return fans.map(\.modeCode) == [1, 1]
        case .targetOne: return fans.map(\.modeCode) == [1, 1] && fans[0].targetRPM == 2500
        default: return false
        }
    }

    private func restoreObservationAllowed(step: ExperimentStep, observation: ControlObservation, date: Date) -> Bool {
        guard activeProfile(observation, date: date) else { return false }
        let modes = observation.snapshot.fans.map(\.modeCode)
        let automatic: (UInt8?) -> Bool = { $0 == 0 || $0 == 3 }
        switch step {
        case .autoZero, .autoOne: return true
        case .clearTargetZero: return automatic(modes[0])
        case .clearTargetOne: return automatic(modes[1])
        case .releaseUnlock: return modes.allSatisfy(automatic)
        default: return false
        }
    }

    private func activeProfile(_ observation: ControlObservation, date: Date) -> Bool {
        let snapshot = observation.snapshot
        return snapshot.modelIdentifier == "Mac15,7" && snapshot.macOSVersion == "27.0.0" && snapshot.macOSBuild == "26A428" &&
            snapshot.smcAvailable && snapshot.fans.map(\.index) == [0, 1] &&
            date.timeIntervalSince(snapshot.sampledAt) >= 0 && date.timeIntervalSince(snapshot.sampledAt) <= 3 &&
            observation.testModeCode != nil && snapshot.fans.allSatisfy {
                guard let actual = $0.actualRPM, let target = $0.targetRPM, let low = $0.minimumRPM, let high = $0.maximumRPM,
                      $0.modeCode != nil else { return false }
                return actual.isFinite && target.isFinite && low.isFinite && high.isFinite && actual >= 0 && target >= 0 && low > 0 && high > low
            }
    }

    private func validHash(_ text: String) -> Bool {
        text.utf8.count == 64 && text.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
    private func checkClock(_ now: Double) throws {
        guard now.isFinite, now >= 0 else { throw ExperimentAuthorityError.invalidClock }
    }
    private func transaction<T>(_ action: (inout ExperimentAuthorityState) throws -> T) throws -> T {
        let ownership = try journal.acquireAuthorityLock(domain: domain)
        defer { withExtendedLifetime(ownership) {} }
        var state = try journal.loadAuthorityState(domain: domain) ?? ExperimentAuthorityState()
        let result = try action(&state)
        try journal.saveAuthorityState(state, domain: domain)
        return result
    }
}
