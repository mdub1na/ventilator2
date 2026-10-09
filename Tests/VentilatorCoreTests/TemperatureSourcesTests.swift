import XCTest
@testable import VentilatorCore

final class TemperatureSourcesTests: XCTestCase {
    func testReadingDoesNotTransferToAnotherHardwareOrOSProfile() {
        for profile in [("Mac15,3", "27.0.0", "26A428"), ("Mac15,7", "26.0.0", "26A428"),
                        ("Mac15,7", "27.0.0", "26A999"), ("Mac15,7", "27.0.1", "26A434")] {
            let reading = TemperatureSources.nandReading(model: profile.0, version: profile.1, build: profile.2, rawCelsius: 30)
            XCTAssertNil(reading.celsius)
            XCTAssertFalse(reading.verified)
        }
    }

    func testUnavailableAndInvalidSamplesNeverBecomeAZeroReading() {
        for value: Double? in [nil, .nan, .infinity, -11, 126] {
            let reading = localReading(value)
            XCTAssertNil(reading.celsius)
            XCTAssertFalse(reading.verified)
        }
    }

    func testConfirmedNANDReadingPreservesZeroAndNamesTheChannel() {
        for value in [0.0, 30.0, 32.0] {
            let reading = localReading(value)
            XCTAssertEqual(reading.celsius, value)
            XCTAssertTrue(reading.verified)
            XCTAssertEqual(reading.label, "SSD (NAND CH0)")
        }
    }

    private func localReading(_ value: Double?) -> TemperatureReading {
        TemperatureSources.nandReading(model: "Mac15,7", version: "27.0.0", build: "26A428", rawCelsius: value)
    }
}
