import Foundation
import VentilatorControl

public enum ExperimentDeviceRole: String, Codable { case fixed, restoration }

/// A pure revocation/expiry check, not a capability or an authorization issuer.
public enum ExperimentWriteAdmission {
    public static func validate(reserved: ApprovedExperimentLedger, current: ApprovedExperimentLedger,
                                step: ExperimentStep, domain: ExperimentDomain, sessionID: UUID,
                                boot: UUID, now: Double, role: ExperimentDeviceRole? = nil) throws {
        guard reserved.domain == domain, current.domain == domain,
              current.sessionID == sessionID, reserved.sessionID == sessionID,
              current.approval == reserved.approval, current.approval.domain == domain,
              current.startedAt == reserved.startedAt, current.expiresAt == reserved.expiresAt,
              current.approval.challenge.bootSession == boot,
              current.attempts == reserved.attempts, current.attempts.last == step,
              current.pendingRestoration, !current.autoCodesObserved else { throw ExperimentAuthorityError.reservationScope }
        guard now.isFinite, now >= current.lastClock, current.lastClock >= reserved.lastClock else {
            throw ExperimentAuthorityError.invalidClock
        }
        if let role, step.isFixed != (role == .fixed) { throw ExperimentAuthorityError.reservationScope }
        if step.isFixed {
            guard !current.fixedClosed else { throw ExperimentAuthorityError.fixedClosed }
            guard now < current.expiresAt else { throw ExperimentAuthorityError.leaseExpired }
        } else {
            guard current.fixedClosed, let started = current.restoreStartedAt,
                  current.restoreRequestedDate != nil else { throw ExperimentAuthorityError.restoreNotStarted }
            guard now < started + 8 else { throw ExperimentAuthorityError.restorationExpired }
        }
    }
}
