import CSMCRead
import Darwin
import Foundation
import VentilatorControl
import VentilatorCore

public struct ExperimentMachine: Codable, Equatable, Sendable {
    public let model: String
    public let version: String
    public let build: String
    public init(model: String, version: String, build: String) { self.model = model; self.version = version; self.build = build }
    public static let legacyReadOnlyProfile = ExperimentMachine(model: "Mac15,7", version: "27.0.0", build: "26A428")
    public static let candidate = ExperimentMachine(model: "Mac15,7", version: "27.0.1", build: "26A434")
    /// Diagnostic reads only. This profile grants no hardware authority or candidate approval.
    public static let diagnosticProfile = ExperimentMachine(model: "Mac15,7", version: "27.0.1", build: "26A434")
    fileprivate var allowsDiagnosticRead: Bool { self == .legacyReadOnlyProfile || self == .diagnosticProfile }

    public static func current() -> ExperimentMachine {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        func string(_ name: String) -> String {
            var size = 0
            guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 1, size < 1024 else { return "unknown" }
            var bytes = [CChar](repeating: 0, count: size)
            guard sysctlbyname(name, &bytes, &size, nil, 0) == 0 else { return "unknown" }
            return bytes.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
        }
        return .init(model: string("hw.model"), version: "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
                     build: string("kern.osversion"))
    }
}

public enum ExperimentMonotonicClock {
    public static func now() -> Double {
        var timebase = mach_timebase_info_data_t()
        guard mach_timebase_info(&timebase) == KERN_SUCCESS, timebase.denom != 0 else { return .nan }
        return Double(mach_continuous_time()) * Double(timebase.numer) / Double(timebase.denom) / 1e9
    }
}

public enum ExperimentReadKey: String, CaseIterable, Sendable {
    case count = "FNum", testMode = "Ftst"
    case actualZero = "F0Ac", targetZero = "F0Tg", minimumZero = "F0Mn", maximumZero = "F0Mx", modeZero = "F0Md"
    case actualOne = "F1Ac", targetOne = "F1Tg", minimumOne = "F1Mn", maximumOne = "F1Mx", modeOne = "F1Md"
    var isByte: Bool { [.count, .testMode, .modeZero, .modeOne].contains(self) }
}

public struct ExperimentReadValue {
    public let type: UInt32
    public let bytes: [UInt8]
    public init(type: UInt32, bytes: [UInt8]) { self.type = type; self.bytes = bytes }
}

/// Read-only injection boundary. It cannot supply reservations, approval or any write operation.
public protocol ExperimentReadSource: AnyObject {
    func read(_ key: ExperimentReadKey) throws -> ExperimentReadValue
}

public enum ExperimentObservationError: Error, Equatable {
    case unsupportedMachine, connectionUnavailable, invalidClock, readDeadline, unexpectedFans
    case unavailableKey(ExperimentReadKey), metadata(ExperimentReadKey), invalidNumber(ExperimentReadKey)
}

public struct TimedExperimentObservation {
    public let observation: ControlObservation
    public let readSeconds: Double
    public init(observation: ControlObservation, readSeconds: Double) {
        self.observation = observation; self.readSeconds = readSeconds
    }
}

/// Opens a distinct read-only connection. A slow synchronous read is rejected when it returns;
/// this budget does not claim to interrupt IOKit. Future hardware use must keep reads off the broker loop.
public final class ReadOnlyExperimentObserver {
    private let source: ExperimentReadSource
    private let machine: () -> ExperimentMachine
    private let clock: () -> Double
    private let date: () -> Date
    private let pressure: () -> ExperimentVerification.ThermalPressure

    public init(source: ExperimentReadSource, machine: @escaping () -> ExperimentMachine,
                clock: @escaping () -> Double, date: @escaping () -> Date,
                pressure: @escaping () -> ExperimentVerification.ThermalPressure) {
        self.source = source; self.machine = machine; self.clock = clock; self.date = date; self.pressure = pressure
    }

    public static func native() throws -> ReadOnlyExperimentObserver {
        guard ExperimentMachine.current().allowsDiagnosticRead else { throw ExperimentObservationError.unsupportedMachine }
        return try .init(source: NativeExperimentReadSource(), machine: ExperimentMachine.current,
                         clock: ExperimentMonotonicClock.now, date: Date.init, pressure: {
            switch ProcessInfo.processInfo.thermalState {
            case .nominal: return .nominal
            case .fair, .serious, .critical: return .elevated
            @unknown default: return .unavailable
            }
        })
    }

    public func sample() throws -> TimedExperimentObservation {
        let observedMachine = machine()
        guard observedMachine.allowsDiagnosticRead else { throw ExperimentObservationError.unsupportedMachine }
        let start = clock(), sampledAt = date()
        guard start.isFinite, start >= 0 else { throw ExperimentObservationError.invalidClock }
        var previous = start
        func checkTime() throws {
            let now = clock()
            guard now.isFinite, now >= previous else { throw ExperimentObservationError.invalidClock }
            previous = now
            guard now - start <= CandidateExperimentPlan.operationSeconds else { throw ExperimentObservationError.readDeadline }
        }
        func bytes(_ key: ExperimentReadKey) throws -> [UInt8] {
            try checkTime()
            let value = try source.read(key)
            try checkTime()
            let type = (key.isByte ? "ui8 " : "flt ").utf8.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            guard value.type == type, value.bytes.count == (key.isByte ? 1 : 4) else {
                throw ExperimentObservationError.metadata(key)
            }
            return value.bytes
        }
        func number(_ key: ExperimentReadKey) throws -> Double {
            let data = try bytes(key)
            let bits = UInt32(data[0]) | UInt32(data[1]) << 8 | UInt32(data[2]) << 16 | UInt32(data[3]) << 24
            let value = Double(Float(bitPattern: bits))
            guard value.isFinite, value >= 0 else { throw ExperimentObservationError.invalidNumber(key) }
            return value
        }
        guard try bytes(.count)[0] == 2 else { throw ExperimentObservationError.unexpectedFans }
        let testMode = try bytes(.testMode)[0]
        let groups: [[ExperimentReadKey]] = [[.actualZero, .targetZero, .minimumZero, .maximumZero, .modeZero],
                                            [.actualOne, .targetOne, .minimumOne, .maximumOne, .modeOne]]
        var fans: [FanReading] = []
        for (index, keys) in groups.enumerated() {
            fans.append(try FanReading(index: index, actualRPM: number(keys[0]), targetRPM: number(keys[1]),
                                       minimumRPM: number(keys[2]), maximumRPM: number(keys[3]), modeCode: bytes(keys[4])[0]))
        }
        let thermal = pressure()
        try checkTime()
        guard machine() == observedMachine else { throw ExperimentObservationError.unsupportedMachine }
        try checkTime() // Include the final identity check in the sample budget.
        let snapshot = MonitorSnapshot(modelIdentifier: observedMachine.model,
            macOSVersion: observedMachine.version, macOSBuild: observedMachine.build,
            sampledAt: sampledAt, fans: fans, temperatures: [], smcAvailable: true)
        return .init(observation: .init(snapshot: snapshot, thermalPressure: thermal, testModeCode: testMode),
                     readSeconds: previous - start)
    }
}

private final class NativeExperimentReadSource: ExperimentReadSource {
    private let connection: OpaquePointer
    init() throws {
        guard let connection = SMCReadOpen() else { throw ExperimentObservationError.connectionUnavailable }
        self.connection = connection
    }
    deinit { SMCReadClose(connection) }

    func read(_ key: ExperimentReadKey) throws -> ExperimentReadValue {
        var value = SMCReadValue()
        guard key.rawValue.withCString({ SMCReadKey(connection, $0, &value) }) == 0,
              value.size > 0, value.size <= 32 else { throw ExperimentObservationError.unavailableKey(key) }
        return withUnsafeBytes(of: value.bytes) { .init(type: value.type, bytes: Array($0.prefix(Int(value.size)))) }
    }
}
