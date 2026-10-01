import XCTest
@testable import VentilatorCore

final class FanReadingTests: XCTestCase {
    func testZeroRPMIsARealEmptyGauge() {
        let fan = FanReading(index: 0, actualRPM: 0, targetRPM: 0,
                             minimumRPM: 1350, maximumRPM: 5349, modeCode: 3)
        XCTAssertEqual(fan.relativeLevel, 0)
    }

    func testUnavailableRPMDoesNotBecomeZero() {
        let fan = FanReading(index: 0, actualRPM: nil, targetRPM: nil,
                             minimumRPM: 1350, maximumRPM: 5349, modeCode: nil)
        XCTAssertNil(fan.relativeLevel)
    }

    func testEachFanUsesItsOwnRange() {
        let left = FanReading(index: 0, actualRPM: 3000, targetRPM: nil,
                              minimumRPM: 1350, maximumRPM: 5349, modeCode: 3)
        let right = FanReading(index: 1, actualRPM: 3000, targetRPM: nil,
                               minimumRPM: 1458, maximumRPM: 5777, modeCode: 3)
        XCTAssertEqual(left.relativeLevel, 3)
        XCTAssertEqual(right.relativeLevel, 2)
    }
}
