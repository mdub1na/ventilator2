import Foundation

/// Evidence checks for one proposed hardware experiment. This module does not write to SMC.
public enum ExperimentVerification {
    public static let proposedRPM = 2_500.0

    public enum PreflightFailure: String, Equatable, Sendable {
        case wrongMachine
        case smcUnavailable
        case unexpectedFans
        case unreadableFanState
        case unexpectedMode
        case fanAlreadyFast
        case thermalPressure
        case targetOutsideRange
        case staleReading
    }

    public enum ThermalPressure: Equatable, Sendable {
        case nominal
        case elevated
        case unavailable
    }

    /// This is a candidate for a dry-run, never an authorization to write.
    public static func preflight(
        _ snapshot: MonitorSnapshot,
        now: Date,
        thermalPressure: ThermalPressure
    ) -> PreflightFailure? {
        guard snapshot.modelIdentifier == "Mac15,7",
              snapshot.macOSVersion == "27.0.1",
              snapshot.macOSBuild == "26A434" else { return .wrongMachine }
        guard snapshot.smcAvailable else { return .smcUnavailable }
        guard thermalPressure == .nominal else { return .thermalPressure }
        guard now.timeIntervalSince(snapshot.sampledAt) >= 0,
              now.timeIntervalSince(snapshot.sampledAt) <= 3 else { return .staleReading }
        guard snapshot.fans.count == 2, snapshot.fans.map(\.index) == [0, 1] else {
            return .unexpectedFans
        }
        for fan in snapshot.fans {
            guard let actual = fan.actualRPM, let target = fan.targetRPM,
                  let minimum = fan.minimumRPM, let maximum = fan.maximumRPM,
                  actual.isFinite, target.isFinite, minimum.isFinite, maximum.isFinite,
                  actual >= 0, target >= 0, minimum > 0, maximum > minimum else {
                return .unreadableFanState
            }
            guard fan.modeCode == 3 else { return .unexpectedMode }
            guard actual <= 1_800, target <= 1_800 else { return .fanAlreadyFast }
            guard minimum <= proposedRPM, proposedRPM <= maximum else { return .targetOutsideRange }
        }
        return nil
    }

    /// Independent reads must show both modes, targets and an RPM rise.
    public static func fixedRPMConfirmed(
        baseline: MonitorSnapshot,
        observed: MonitorSnapshot
    ) -> Bool {
        guard sameHardware(baseline, observed),
              observed.sampledAt > baseline.sampledAt,
              baseline.fans.map(\.index) == [0, 1],
              observed.fans.map(\.index) == [0, 1] else { return false }
        for (before, after) in zip(baseline.fans, observed.fans) {
            guard before.index == after.index,
                  let baselineRPM = before.actualRPM, baselineRPM.isFinite,
                  let actual = after.actualRPM, actual.isFinite,
                  let target = after.targetRPM, target.isFinite,
                  after.modeCode == 1,
                  abs(target - proposedRPM) <= 100,
                  actual >= baselineRPM + 300,
                  abs(actual - proposedRPM) <= 500 else { return false }
        }
        return true
    }

    /// Sustained mode readings are one part of restoration evidence, not proof of thermal-manager control.
    public static func autoModeSustained(
        _ samples: [MonitorSnapshot],
        after restoreRequestedAt: Date
    ) -> Bool {
        guard samples.count >= 3 else { return false }
        let last = Array(samples.suffix(3))
        guard last[0].sampledAt > restoreRequestedAt,
              last[1].sampledAt.timeIntervalSince(last[0].sampledAt) >= 1,
              last[2].sampledAt.timeIntervalSince(last[1].sampledAt) >= 1 else { return false }
        for sample in last {
            guard sample.smcAvailable,
                  sample.fans.count == 2,
                  sample.fans.map(\.index) == [0, 1],
                  sample.fans.allSatisfy({ $0.modeCode == 3 || $0.modeCode == 0 }) else {
                return false
            }
        }
        return last.allSatisfy { sameHardware(last[0], $0) }
    }

    private static func sameHardware(_ first: MonitorSnapshot, _ second: MonitorSnapshot) -> Bool {
        first.modelIdentifier == second.modelIdentifier &&
            first.macOSVersion == second.macOSVersion &&
            first.macOSBuild == second.macOSBuild && second.smcAvailable
    }
}
