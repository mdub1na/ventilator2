import Foundation
import XCTest
@testable import VentilatorCore

final class ExperimentVerificationTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_000)

    func testPreflightRejectsChangedBuildAndMissingReadings() {
        XCTAssertNil(ExperimentVerification.preflight(snapshot(at: start), now: start,
                                                     thermalPressure: .nominal))
        XCTAssertEqual(
            ExperimentVerification.preflight(snapshot(at: start, build: "other"), now: start,
                                            thermalPressure: .nominal),
            .wrongMachine
        )
        XCTAssertEqual(
            ExperimentVerification.preflight(snapshot(at: start, actual: nil), now: start,
                                            thermalPressure: .nominal),
            .unreadableFanState
        )
        XCTAssertEqual(
            ExperimentVerification.preflight(snapshot(at: start), now: start.addingTimeInterval(4),
                                            thermalPressure: .nominal),
            .staleReading
        )
        XCTAssertEqual(
            ExperimentVerification.preflight(snapshot(at: start), now: start,
                                            thermalPressure: .elevated),
            .thermalPressure
        )
        XCTAssertEqual(
            ExperimentVerification.preflight(snapshot(at: start, target: 3_000), now: start,
                                            thermalPressure: .nominal),
            .fanAlreadyFast
        )
    }

    func testFixedRPMNeedsModeTargetAndActualMovement() {
        let baseline = snapshot(at: start)
        let manual = snapshot(at: start.addingTimeInterval(5), actual: 2_380,
                              target: 2_500, mode: 1)
        XCTAssertTrue(ExperimentVerification.fixedRPMConfirmed(baseline: baseline, observed: manual))
        XCTAssertFalse(ExperimentVerification.fixedRPMConfirmed(
            baseline: baseline,
            observed: snapshot(at: start.addingTimeInterval(5), actual: 0, target: 2_500, mode: 1)
        ))
        XCTAssertFalse(ExperimentVerification.fixedRPMConfirmed(
            baseline: baseline,
            observed: snapshot(at: start.addingTimeInterval(5), actual: 2_380, target: 2_500, mode: 3)
        ))
    }

    func testAutoRequiresThreeSeparatedReadsAfterRestore() {
        let restore = start.addingTimeInterval(20)
        let good = [21.0, 22.0, 23.0].map {
            snapshot(at: start.addingTimeInterval($0), actual: 0, target: 0, mode: 3)
        }
        XCTAssertTrue(ExperimentVerification.autoModeSustained(good, after: restore))
        XCTAssertFalse(ExperimentVerification.autoModeSustained(Array(good.prefix(2)), after: restore))
        XCTAssertFalse(ExperimentVerification.autoModeSustained(
            [good[0], snapshot(at: start.addingTimeInterval(21.5), mode: 3), good[2]],
            after: restore
        ))
        XCTAssertFalse(ExperimentVerification.autoModeSustained(
            [good[0], snapshot(at: start.addingTimeInterval(22), mode: 1), good[2]],
            after: restore
        ))
    }

    func testFixedConfirmationRejectsIncompleteBaseline() {
        let full = snapshot(at: start)
        let incomplete = MonitorSnapshot(
            modelIdentifier: full.modelIdentifier, macOSVersion: full.macOSVersion, macOSBuild: full.macOSBuild,
            sampledAt: full.sampledAt, fans: Array(full.fans.prefix(1)), temperatures: [], smcAvailable: true
        )
        XCTAssertFalse(ExperimentVerification.fixedRPMConfirmed(
            baseline: incomplete,
            observed: snapshot(at: start.addingTimeInterval(5), actual: 2380, target: 2500, mode: 1)
        ))
    }

    private func snapshot(
        at time: Date,
        build: String = "26A428",
        actual: Double? = 0,
        target: Double? = 0,
        mode: UInt8 = 3
    ) -> MonitorSnapshot {
        let ranges = [(1_350.0, 5_349.0), (1_458.0, 5_777.0)]
        let fans = ranges.enumerated().map { index, range in
            FanReading(index: index, actualRPM: actual, targetRPM: target,
                       minimumRPM: range.0, maximumRPM: range.1, modeCode: mode)
        }
        return MonitorSnapshot(modelIdentifier: "Mac15,7", macOSVersion: "27.0.0",
                               macOSBuild: build, sampledAt: time, fans: fans,
                               temperatures: [], smcAvailable: true)
    }
}
