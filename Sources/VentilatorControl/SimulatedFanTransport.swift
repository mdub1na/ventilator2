import Foundation
import VentilatorCore

public enum SimulatedEffect: String, Codable { case fixed2500, auto }

public final class SimulatedFanTransport: ExperimentTransport {
    public enum Fault: Error { case unavailable, partialFixedFailure, restoreFailure }
    public var fault: Fault?
    public var thermalPressure: ExperimentVerification.ThermalPressure = .nominal
    public var build = "26A434"
    public var fixedRPMMoves = true
    public var ranges = [(1350.0, 5349.0), (1458.0, 5777.0)]
    public private(set) var effects: [SimulatedEffect] = []
    private var manual = false

    public init() {}

    public func read(at date: Date) throws -> ControlObservation {
        if fault == .unavailable { throw Fault.unavailable }
        let fans = ranges.enumerated().map { index, range in
            FanReading(index: index, actualRPM: manual && fixedRPMMoves ? 2400 : 0,
                       targetRPM: manual ? 2500 : 0, minimumRPM: range.0, maximumRPM: range.1,
                       modeCode: manual ? 1 : 3)
        }
        return ControlObservation(snapshot: MonitorSnapshot(
            modelIdentifier: "Mac15,7", macOSVersion: "27.0.1", macOSBuild: build,
            sampledAt: date, fans: fans, temperatures: [], smcAvailable: true
        ), thermalPressure: thermalPressure, testModeCode: manual ? 1 : 0)
    }

    public func simulateFixed2500RPM() throws {
        effects.append(.fixed2500)
        manual = true
        if fault == .partialFixedFailure { throw Fault.partialFixedFailure }
    }

    public func simulateAuto() throws {
        effects.append(.auto)
        if fault == .restoreFailure { throw Fault.restoreFailure }
        manual = false
    }
}

public final class MemorySessionJournal: SessionJournal {
    public var record: SessionRecord?
    public var failSave = false
    public var failClear = false
    public init() {}
    public func load() throws -> SessionRecord? { record }
    public func save(_ record: SessionRecord) throws {
        if failSave { throw CocoaError(.fileWriteUnknown) }
        self.record = record
    }
    public func clear() throws {
        if failClear { throw CocoaError(.fileWriteUnknown) }
        record = nil
    }
}
