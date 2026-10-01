import Foundation
import XCTest
@testable import VentilatorControl

final class ControlSessionTests: XCTestCase {
    private let owner = UUID()
    private func date(_ seconds: Double) -> Date { Date(timeIntervalSince1970: 1000 + seconds) }

    private func setup() -> (ControlSession, SimulatedFanTransport, MemorySessionJournal) {
        let transport = SimulatedFanTransport()
        let journal = MemorySessionJournal()
        return (ControlSession(transport: transport, journal: journal), transport, journal)
    }

    func testHeartbeatCannotExtendLeaseOrStartAnotherSession() throws {
        let (session, transport, journal) = setup()
        let id = try XCTUnwrap(session.begin(owner: owner, now: 0, date: date(0)).sessionID)
        for instant in 1...9 { _ = try session.heartbeat(owner: owner, sessionID: id, now: Double(instant), date: date(Double(instant))) }
        XCTAssertEqual(session.report.phase, .fixedObserved)
        session.tick(now: 10, date: date(10))
        XCTAssertEqual(session.report.reason, .leaseExpired)
        XCTAssertThrowsError(try session.heartbeat(owner: owner, sessionID: id, now: 10, date: date(10)))
        XCTAssertNotNil(journal.record)
        finishRestore(session, from: 10)
        XCTAssertEqual(session.report.phase, .autoCodeObserved)
        XCTAssertNil(journal.record)
        XCTAssertThrowsError(try session.begin(owner: owner, now: 14, date: date(14)))
        XCTAssertEqual(transport.effects, [.fixed2500, .auto])
    }

    func testLostHeartbeatAndWrongOwnerCannotKeepFixedModeAlive() throws {
        let (session, transport, _) = setup()
        let id = try XCTUnwrap(session.begin(owner: owner, now: 0, date: date(0)).sessionID)
        XCTAssertThrowsError(try session.heartbeat(owner: UUID(), sessionID: id, now: 1, date: date(1)))
        session.tick(now: 2, date: date(2))
        XCTAssertEqual(session.report.reason, .heartbeatLost)
        XCTAssertEqual(transport.effects, [.fixed2500, .auto])
    }

    func testInitialJournalFailurePreventsFixedChange() {
        let (session, transport, journal) = setup()
        journal.failSave = true
        XCTAssertThrowsError(try session.begin(owner: owner, now: 0, date: date(0)))
        XCTAssertTrue(transport.effects.isEmpty)
    }

    func testChangeFailureRequestsRestoreAndKeepsMarkerUntilThreeReads() throws {
        let (session, transport, journal) = setup()
        transport.fault = .partialFixedFailure
        _ = try session.begin(owner: owner, now: 0, date: date(0))
        XCTAssertEqual(transport.effects, [.fixed2500, .auto])
        XCTAssertEqual(session.report.phase, .restoring)
        session.tick(now: 1, date: date(1))
        session.tick(now: 2, date: date(2))
        XCTAssertNotNil(journal.record)
        session.tick(now: 3, date: date(3))
        XCTAssertEqual(session.report.phase, .autoCodeObserved)
        XCTAssertNil(journal.record)
    }

    func testRestoreFailureKeepsMarkerAndDoesNotRetrySilently() throws {
        let (session, transport, journal) = setup()
        let id = try XCTUnwrap(session.begin(owner: owner, now: 0, date: date(0)).sessionID)
        transport.fault = .restoreFailure
        _ = try session.restore(owner: owner, sessionID: id, now: 1, date: date(1))
        session.tick(now: 2, date: date(2))
        XCTAssertEqual(session.report.phase, .recoveryRequired)
        XCTAssertNotNil(journal.record)
        XCTAssertEqual(transport.effects, [.fixed2500, .auto])
    }

    func testRestartRestoresInsteadOfResumingFixedMode() throws {
        let (_, transport, journal) = setup()
        let first = ControlSession(transport: transport, journal: journal)
        _ = try first.begin(owner: owner, now: 0, date: date(0))
        let restarted = ControlSession(transport: transport, journal: journal)
        restarted.recover(now: 1, date: date(1))
        XCTAssertEqual(restarted.report.reason, .processRestart)
        XCTAssertEqual(transport.effects, [.fixed2500, .auto])
        finishRestore(restarted, from: 1)
        XCTAssertNil(journal.record)
        XCTAssertThrowsError(try restarted.begin(owner: UUID(), now: 6, date: date(6)))
    }

    func testDisconnectSleepSensorLossPressureAndProfileChangeRequestRestore() throws {
        for cause in [StopReason.clientDisconnected, .systemSleep, .sensorUnavailable, .thermalPressure, .profileChanged, .clockFailure] {
            let (session, transport, journal) = setup()
            _ = try session.begin(owner: owner, now: 1, date: date(1))
            switch cause {
            case .clientDisconnected: session.disconnected(owner: owner, now: 2, date: date(2))
            case .systemSleep: session.willSleep(now: 2, date: date(2))
            case .sensorUnavailable: transport.fault = .unavailable; session.tick(now: 2, date: date(2))
            case .thermalPressure: transport.thermalPressure = .elevated; session.tick(now: 2, date: date(2))
            case .profileChanged: transport.build = "other"; session.tick(now: 2, date: date(2))
            case .clockFailure: session.tick(now: 0, date: date(2))
            default: XCTFail("Unexpected test cause")
            }
            XCTAssertEqual(session.report.reason, cause)
            XCTAssertEqual(transport.effects, [.fixed2500, .auto])
            XCTAssertNotNil(journal.record)
        }
    }

    func testNoRPMMovementFailsVerificationInsteadOfClaimingFixedMode() throws {
        let (session, transport, _) = setup()
        transport.fixedRPMMoves = false
        let id = try XCTUnwrap(session.begin(owner: owner, now: 0, date: date(0)).sessionID)
        for instant in 1...4 { _ = try session.heartbeat(owner: owner, sessionID: id, now: Double(instant), date: date(Double(instant))) }
        session.tick(now: 5, date: date(5))
        XCTAssertEqual(session.report.reason, .fixedNotObserved)
        XCTAssertEqual(transport.effects, [.fixed2500, .auto])
    }

    func testFailedMarkerRemovalDoesNotDeclareRestorationCompleted() throws {
        let (session, _, journal) = setup()
        let id = try XCTUnwrap(session.begin(owner: owner, now: 0, date: date(0)).sessionID)
        _ = try session.restore(owner: owner, sessionID: id, now: 1, date: date(1))
        journal.failClear = true
        finishRestore(session, from: 1)
        XCTAssertEqual(session.report.phase, .recoveryRequired)
        XCTAssertEqual(session.report.reason, .journalFailure)
        XCTAssertNotNil(journal.record)
    }

    func testChangedRangeStopsEvenWhenTargetRemainsInsideIt() throws {
        let (session, transport, journal) = setup()
        _ = try session.begin(owner: owner, now: 0, date: date(0))
        transport.ranges[1].1 = 5000
        session.tick(now: 1, date: date(1))
        XCTAssertEqual(session.report.reason, .rangeChanged)
        XCTAssertEqual(transport.effects, [.fixed2500, .auto])
        XCTAssertNotNil(journal.record)
    }

    private func finishRestore(_ session: ControlSession, from start: Double) {
        for offset in 1...3 { session.tick(now: start + Double(offset), date: date(start + Double(offset))) }
    }
}
