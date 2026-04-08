import XCTest
@testable import LivelineCanvas

final class LivelineCanvasTests: XCTestCase {
    func testLerpMovesTowardTarget() {
        let result = lerp(100, 110, speed: 0.2, dt: 1.0 / 60)
        XCTAssertGreaterThan(result, 100)
        XCTAssertLessThan(result, 110)
    }

    func testValueRangeAddsPadding() {
        let points = [
            LivelinePoint(time: 1, value: 100),
            LivelinePoint(time: 2, value: 120)
        ]

        let range = valueRange(points: points, candles: [], reference: nil)
        XCTAssertLessThan(range.min, 100)
        XCTAssertGreaterThan(range.max, 120)
    }
}
