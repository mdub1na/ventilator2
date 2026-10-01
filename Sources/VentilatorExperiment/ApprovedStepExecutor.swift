import Foundation
import VentilatorControl

public protocol ExperimentStepDevice: AnyObject {
    var domain: ExperimentDomain { get }
    func write(_ reservation: ExperimentWriteReservation) throws
}

/// All callers are serialized by the owning worker. A reservation is fsynced before device I/O.
public final class ApprovedStepExecutor {
    private let authority: ExperimentAuthority
    private let session: ApprovedExperimentLedger
    private let device: ExperimentStepDevice

    public init(authority: ExperimentAuthority, sessionID: UUID, device: ExperimentStepDevice) throws {
        guard let session = try authority.state().ledger, session.sessionID == sessionID else { throw ExperimentAuthorityError.wrongSession }
        guard authority.domain == session.domain, device.domain == session.domain,
              session.pendingRestoration else { throw ExperimentAuthorityError.wrongSession }
        self.authority = authority
        self.session = session
        self.device = device
    }

    public func perform(_ step: ExperimentStep, now: Double, date: Date, observation: ControlObservation) throws {
        do {
            let reservation = try authority.reserve(step: step, sessionID: session.sessionID,
                owner: session.approval.challenge.connectionOwner, boot: session.approval.challenge.bootSession,
                now: now, observation: observation, date: date)
            guard let current = try authority.state().ledger else { throw ExperimentAuthorityError.wrongSession }
            try ExperimentWriteAdmission.validate(reserved: reservation.ledger, current: current, step: step,
                domain: device.domain, sessionID: session.sessionID, boot: session.approval.challenge.bootSession, now: now)
            try device.write(reservation)
            try authority.recordSuccessfulReturn(step: step, sessionID: session.sessionID)
        } catch {
            // A failed call may already have changed hardware. Keep the marker and close fixed.
            _ = try? authority.closeFixedAndBeginRestoration(sessionID: session.sessionID, now: now, date: date)
            throw error
        }
    }
}
