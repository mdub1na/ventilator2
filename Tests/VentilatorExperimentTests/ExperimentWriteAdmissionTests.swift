import Foundation
import VentilatorControl
import VentilatorExperiment
import XCTest

final class ExperimentWriteAdmissionTests: XCTestCase {
    private func fixture() throws -> (URL, ExperimentAuthority, ExperimentWriteReservation) {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let authority = try ExperimentAuthority(directory: folder, domain: .simulation)
        let plan = CandidateExperimentPlan(binaries: .init(applicationSHA256: String(repeating: "a", count: 64), helperSHA256: String(repeating: "b", count: 64)))
        let owner = UUID(), boot = UUID(), device = SimulatedStepDevice(), date = Date()
        let challenge = try authority.prepare(owner: owner, plan: plan, boot: boot, now: 0)
        try authority.approveLocally(challengeID: challenge.id, planSHA256: plan.sha256(), boot: boot, now: 1)
        let ledger = try authority.begin(owner: owner, challengeID: challenge.id, plan: plan, binaries: plan.binaries,
            boot: boot, now: 2, observation: device.observation(at: date), date: date)
        return (folder, authority, try authority.reserve(step: .unlock, sessionID: ledger.sessionID,
            owner: owner, boot: boot, now: 2, observation: device.observation(at: date), date: date))
    }
    private func validate(_ reservation: ExperimentWriteReservation, _ current: ApprovedExperimentLedger,
                          now: Double = 2, role: ExperimentDeviceRole? = nil) throws {
        try ExperimentWriteAdmission.validate(reserved: reservation.ledger, current: current, step: reservation.step,
            domain: .simulation, sessionID: reservation.ledger.sessionID,
            boot: reservation.ledger.approval.challenge.bootSession, now: now, role: role)
    }

    func testPreviouslyReservedFixedStepIsRevokedByDurableClosure() throws {
        let (folder, authority, reservation) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        try validate(reservation, XCTUnwrap(authority.state().ledger), role: .fixed)
        try authority.closeFixed(sessionID: reservation.ledger.sessionID, now: 2.1)
        XCTAssertThrowsError(try validate(reservation, XCTUnwrap(authority.state().ledger), now: 2.2)) {
            XCTAssertEqual($0 as? ExperimentAuthorityError, .fixedClosed)
        }
        XCTAssertEqual(try authority.state().ledger?.attempts, [.unlock])
    }

    func testExpiredOrBackwardWriteIsRejectedImmediatelyBeforeIO() throws {
        let (folder, authority, reservation) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let current = try XCTUnwrap(authority.state().ledger)
        XCTAssertThrowsError(try validate(reservation, current, now: 12)) {
            XCTAssertEqual($0 as? ExperimentAuthorityError, .leaseExpired)
        }
        for now in [Double.nan, 1.9] {
            XCTAssertThrowsError(try validate(reservation, current, now: now)) {
                XCTAssertEqual($0 as? ExperimentAuthorityError, .invalidClock)
            }
        }
    }

    func testAnotherSessionBootDomainOrRoleCannotUseReservation() throws {
        let (folder, authority, reservation) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let current = try XCTUnwrap(authority.state().ledger)
        XCTAssertThrowsError(try validate(reservation, current, role: .restoration))
        for (domain, id, boot) in [(ExperimentDomain.hardware, current.sessionID, current.approval.challenge.bootSession),
                                   (.simulation, UUID(), current.approval.challenge.bootSession),
                                   (.simulation, current.sessionID, UUID())] {
            XCTAssertThrowsError(try ExperimentWriteAdmission.validate(reserved: reservation.ledger, current: current,
                step: reservation.step, domain: domain, sessionID: id, boot: boot, now: 2))
        }
    }

    func testSupersededReservationAndCompletedStateCannotPermitIO() throws {
        let (folder, authority, reservation) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        var current = try XCTUnwrap(authority.state().ledger)
        current.attempts.append(.manualZero)
        XCTAssertThrowsError(try validate(reservation, current))
        current = reservation.ledger; current.autoCodesObserved = true
        XCTAssertThrowsError(try validate(reservation, current))
        current = reservation.ledger; current.pendingRestoration = false
        XCTAssertThrowsError(try validate(reservation, current))
    }

    func testRestorationUsesOriginalDeadlineAndCannotUseFixedDevice() throws {
        let (folder, authority, fixed) = try fixture()
        defer { try? FileManager.default.removeItem(at: folder) }
        let date = Date(), ledger = fixed.ledger, device = SimulatedStepDevice()
        _ = try authority.closeFixedAndBeginRestoration(sessionID: ledger.sessionID, now: 3, date: date)
        let auto = try authority.reserve(step: .autoZero, sessionID: ledger.sessionID,
            owner: ledger.approval.challenge.connectionOwner, boot: ledger.approval.challenge.bootSession,
            now: 3, observation: device.observation(at: date), date: date)
        let current = try XCTUnwrap(authority.state().ledger)
        try validate(auto, current, now: 3.1, role: .restoration)
        XCTAssertThrowsError(try validate(auto, current, now: 3.1, role: .fixed))
        XCTAssertThrowsError(try validate(auto, current, now: 11)) {
            XCTAssertEqual($0 as? ExperimentAuthorityError, .restorationExpired)
        }
    }
}
