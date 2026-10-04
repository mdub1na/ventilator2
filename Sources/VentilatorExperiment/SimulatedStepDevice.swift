import Foundation
import VentilatorControl
import VentilatorCore

/// Exercises the exact step sequence and partial failures. Never opens an IOKit connection.
public final class SimulatedStepDevice: ExperimentStepDevice {
    public enum Fault: Error { case failedStep }
    public let domain: ExperimentDomain = .simulation
    public var failAfterStep: ExperimentStep?
    public var pressure: ExperimentVerification.ThermalPressure = .nominal
    public var ranges = [(1350.0, 5349.0), (1458.0, 5777.0)]
    public private(set) var effects: [ExperimentStep] = []
    private var modes: [UInt8] = [3, 3]
    private var targets: [Double] = [0, 0]
    private var testMode: UInt8 = 0

    public init() {}

    public func write(_ reservation: ExperimentWriteReservation) throws {
        let step = try reservation.consume(domain: .simulation, sessionID: reservation.ledger.sessionID)
        effects.append(step)
        switch step {
        case .unlock: testMode = 1
        case .manualZero: modes[0] = 1
        case .manualOne: modes[1] = 1
        case .targetZero: targets[0] = 2500
        case .targetOne: targets[1] = 2500
        case .autoZero: modes[0] = 3
        case .autoOne: modes[1] = 3
        case .clearTargetZero: targets[0] = 0
        case .clearTargetOne: targets[1] = 0
        case .releaseUnlock: testMode = 0
        }
        if step == failAfterStep { throw Fault.failedStep }
    }

    public func observation(at date: Date) -> ControlObservation {
        let fans = (0..<2).map { index in
            FanReading(index: index, actualRPM: modes[index] == 1 && targets[index] == 2500 ? 2400 : 0,
                       targetRPM: targets[index], minimumRPM: ranges[index].0, maximumRPM: ranges[index].1,
                       modeCode: modes[index])
        }
        return ControlObservation(snapshot: MonitorSnapshot(modelIdentifier: "Mac15,7", macOSVersion: "27.0.1",
            macOSBuild: "26A434", sampledAt: date, fans: fans, temperatures: [], smcAvailable: true),
            thermalPressure: pressure, testModeCode: testMode)
    }
}
