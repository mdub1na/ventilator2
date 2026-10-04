import Foundation
import VentilatorCore
import VentilatorExperiment
import XCTest

final class ReadOnlyExperimentObserverTests: XCTestCase {
    private final class Source: ExperimentReadSource {
        var values: [ExperimentReadKey: ExperimentReadValue] = [:]
        var requested: [ExperimentReadKey] = []
        var afterRead: () -> Void = {}
        init() {
            for key in ExperimentReadKey.allCases {
                switch key {
                case .count: values[key] = Self.byte(2)
                case .testMode: values[key] = Self.byte(0)
                case .modeZero, .modeOne: values[key] = Self.byte(3)
                case .minimumZero: values[key] = Self.number(1350)
                case .maximumZero: values[key] = Self.number(5349)
                case .minimumOne: values[key] = Self.number(1458)
                case .maximumOne: values[key] = Self.number(5777)
                default: values[key] = Self.number(0)
                }
            }
        }
        func read(_ key: ExperimentReadKey) throws -> ExperimentReadValue {
            requested.append(key); afterRead()
            guard let value = values[key] else { throw ExperimentObservationError.unavailableKey(key) }
            return value
        }
        static func byte(_ value: UInt8) -> ExperimentReadValue { .init(type: 0x75693820, bytes: [value]) }
        static func number(_ value: Float) -> ExperimentReadValue {
            let bits = value.bitPattern
            return .init(type: 0x666c7420, bytes: (0..<4).map { UInt8(truncatingIfNeeded: bits >> ($0 * 8)) })
        }
    }
    private final class Context {
        var now = 100.0
        var date = Date(timeIntervalSince1970: 1000)
        var machine = ExperimentMachine.candidate
        var pressure = ExperimentVerification.ThermalPressure.nominal
    }
    private func observer(_ source: Source, _ context: Context) -> ReadOnlyExperimentObserver {
        .init(source: source, machine: { context.machine }, clock: { context.now }, date: { context.date }, pressure: { context.pressure })
    }

    func testExactTypesZeroRPMAndTimestampAtReadStart() throws {
        let source = Source(), context = Context(), start = context.date
        source.afterRead = { context.now += 0.01; context.date = context.date.addingTimeInterval(0.01) }
        let result = try observer(source, context).sample()
        XCTAssertEqual(result.observation.snapshot.sampledAt, start)
        XCTAssertEqual(result.observation.snapshot.fans.map(\.actualRPM), [0, 0])
        XCTAssertEqual(result.observation.snapshot.fans.map(\.modeCode), [3, 3])
        XCTAssertEqual(result.observation.testModeCode, 0)
        XCTAssertEqual(result.readSeconds, 0.12, accuracy: 0.0001)
        XCTAssertEqual(Set(source.requested), Set(ExperimentReadKey.allCases))
        XCTAssertNil(ExperimentVerification.preflight(result.observation.snapshot, now: context.date, thermalPressure: .nominal))
    }

    func testUnsupportedOrChangedProfileCannotProduceAnObservation() throws {
        let source = Source(), context = Context()
        context.machine = .init(model: "Mac15,7", version: "26.0.0", build: "25A")
        XCTAssertThrowsError(try observer(source, context).sample())
        XCTAssertTrue(source.requested.isEmpty)
        context.machine = .candidate
        source.afterRead = { context.machine = .init(model: "Mac15,7", version: "27.0.0", build: "different") }
        XCTAssertThrowsError(try observer(source, context).sample()) {
            XCTAssertEqual($0 as? ExperimentObservationError, .unsupportedMachine)
        }
    }

    func testLegacyReadOnlyProfileCannotPassCurrentCandidatePreflight() throws {
        let source = Source(), context = Context()
        context.machine = .legacyReadOnlyProfile
        let observation = try observer(source, context).sample().observation
        XCTAssertEqual(observation.snapshot.modelIdentifier, "Mac15,7")
        XCTAssertEqual(observation.snapshot.macOSVersion, "27.0.0")
        XCTAssertEqual(observation.snapshot.macOSBuild, "26A428")
        XCTAssertEqual(observation.snapshot.fans.map(\.modeCode), [3, 3])
        XCTAssertEqual(ExperimentVerification.preflight(observation.snapshot, now: context.date, thermalPressure: .nominal), .wrongMachine)
        source.afterRead = { context.machine = .candidate }
        XCTAssertThrowsError(try observer(source, context).sample()) {
            XCTAssertEqual($0 as? ExperimentObservationError, .unsupportedMachine)
        }
    }

    func testWrongTypeOrSizeDoesNotUseAnIntelFallback() throws {
        let source = Source(), context = Context()
        source.values[.actualZero] = .init(type: 0x66706532, bytes: [0, 0])
        XCTAssertThrowsError(try observer(source, context).sample()) {
            XCTAssertEqual($0 as? ExperimentObservationError, .metadata(.actualZero))
        }
        source.values[.actualZero] = Source.number(0)
        source.values[.modeZero] = .init(type: 0x75693820, bytes: [3, 0])
        XCTAssertThrowsError(try observer(source, context).sample()) {
            XCTAssertEqual($0 as? ExperimentObservationError, .metadata(.modeZero))
        }
    }

    func testNaNAndNegativeRPMCannotBecomeZeroOrFreshData() throws {
        let source = Source(), context = Context()
        for value: Float in [.nan, .infinity, -1] {
            source.values[.actualZero] = Source.number(value)
            XCTAssertThrowsError(try observer(source, context).sample()) {
                XCTAssertEqual($0 as? ExperimentObservationError, .invalidNumber(.actualZero))
            }
        }
    }

    func testSlowReadBackwardClockAndUnavailableClockRejectWholeSample() throws {
        let source = Source(), context = Context()
        source.afterRead = { context.now += 0.5001 }
        XCTAssertThrowsError(try observer(source, context).sample()) {
            XCTAssertEqual($0 as? ExperimentObservationError, .readDeadline)
        }
        XCTAssertEqual(source.requested, [.count])
        source.afterRead = { context.now -= 1 }
        XCTAssertThrowsError(try observer(source, context).sample()) {
            XCTAssertEqual($0 as? ExperimentObservationError, .invalidClock)
        }
        source.afterRead = { context.now = .nan }
        XCTAssertThrowsError(try observer(source, context).sample()) {
            XCTAssertEqual($0 as? ExperimentObservationError, .invalidClock)
        }
    }

    func testFanCountAndUnavailableKeyCannotPassWithPartialData() throws {
        let source = Source(), context = Context()
        source.values[.count] = Source.byte(1)
        XCTAssertThrowsError(try observer(source, context).sample()) {
            XCTAssertEqual($0 as? ExperimentObservationError, .unexpectedFans)
        }
        source.values[.count] = Source.byte(2); source.values[.modeOne] = nil
        XCTAssertThrowsError(try observer(source, context).sample()) {
            XCTAssertEqual($0 as? ExperimentObservationError, .unavailableKey(.modeOne))
        }
    }

    func testThermalPressureRemainsAnExplicitPreflightFailure() throws {
        let source = Source(), context = Context()
        for pressure in [ExperimentVerification.ThermalPressure.elevated, .unavailable] {
            context.pressure = pressure
            let result = try observer(source, context).sample()
            XCTAssertEqual(result.observation.thermalPressure, pressure)
            XCTAssertEqual(ExperimentVerification.preflight(result.observation.snapshot, now: context.date,
                thermalPressure: result.observation.thermalPressure), .thermalPressure)
        }
    }

    func testSlowFinalIdentityCheckAlsoConsumesTheReadBudget() throws {
        let source = Source(), context = Context()
        var identityReads = 0
        let reader = ReadOnlyExperimentObserver(source: source, machine: {
            identityReads += 1
            if identityReads == 2 { context.now += 0.51 }
            return .candidate
        }, clock: { context.now }, date: { context.date }, pressure: { .nominal })
        XCTAssertThrowsError(try reader.sample()) { XCTAssertEqual($0 as? ExperimentObservationError, .readDeadline) }
        XCTAssertEqual(source.requested.count, 12)
    }
}
