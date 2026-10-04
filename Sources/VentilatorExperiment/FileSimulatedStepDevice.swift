import Foundation
import VentilatorControl
import VentilatorCore

/// The broker reads independently of writer/restorer processes; model changes are durable and serialized.
/// This file is explicitly a simulation boundary, never a hardware driver or hardware approval issuer.
public final class FileSimulatedStepDevice: ExperimentStepDevice {
    public let domain: ExperimentDomain = .simulation
    public var failBeforeStep: ExperimentStep?
    public var failBeforeSteps: Set<ExperimentStep> = []
    public var unlockEffectObserved = true
    private let journal: FileSessionJournal
    private let sessionID: UUID

    public init(directory: URL, sessionID: UUID) throws {
        journal = try FileSessionJournal(directory: directory)
        self.sessionID = sessionID
        guard try journal.loadSimulationDevice() != nil else { throw CocoaError(.fileReadNoSuchFile) }
    }

    public func write(_ reservation: ExperimentWriteReservation) throws {
        let step = try reservation.consume(domain: .simulation, sessionID: sessionID)
        if step == failBeforeStep || failBeforeSteps.contains(step) { throw SimulatedStepDevice.Fault.failedStep }
        let ownership = try journal.acquireSimulationDeviceLock()
        defer { withExtendedLifetime(ownership) {} }
        guard var state = try journal.loadSimulationDevice(), !state.effects.contains(step) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        switch step {
        case .unlock: if unlockEffectObserved { state.testMode = 1 }
        case .manualZero: state.modes[0] = 1
        case .manualOne: state.modes[1] = 1
        case .targetZero: state.targets[0] = 2500
        case .targetOne: state.targets[1] = 2500
        case .autoZero: state.modes[0] = 3
        case .autoOne: state.modes[1] = 3
        case .clearTargetZero: state.targets[0] = 0
        case .clearTargetOne: state.targets[1] = 0
        case .releaseUnlock: state.testMode = 0
        }
        state.effects.append(step)
        try journal.saveSimulationDevice(state)
    }

    public func observation(at date: Date) throws -> ControlObservation {
        guard let state = try journal.loadSimulationDevice() else { throw CocoaError(.fileReadNoSuchFile) }
        let ranges = [(1350.0, 5349.0), (1458.0, 5777.0)]
        let fans = (0..<2).map { index in
            FanReading(index: index, actualRPM: state.modes[index] == 1 && state.targets[index] == 2500 ? 2400 : 0,
                       targetRPM: state.targets[index], minimumRPM: ranges[index].0,
                       maximumRPM: ranges[index].1, modeCode: state.modes[index])
        }
        return ControlObservation(snapshot: MonitorSnapshot(modelIdentifier: "Mac15,7", macOSVersion: "27.0.1",
            macOSBuild: "26A434", sampledAt: date, fans: fans, temperatures: [], smcAvailable: true),
            thermalPressure: .nominal, testModeCode: state.testMode)
    }
}
