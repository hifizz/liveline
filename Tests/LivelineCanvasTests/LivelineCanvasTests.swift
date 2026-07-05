import XCTest
@testable import LivelineCanvas

#if canImport(CoreGraphics)
import CoreGraphics
#endif

final class LivelineCanvasTests: XCTestCase {

    // MARK: - Lerp

    func testLerpMovesTowardTarget() {
        let result = lerp(100, 110, speed: 0.2, dt: 1.0 / 60)
        XCTAssertGreaterThan(result, 100)
        XCTAssertLessThan(result, 110)
    }

    func testLerpIsFrameRateIndependent() {
        // One 33ms step should land where two 16.67ms steps do
        let oneBigStep = lerp(0, 100, speed: 0.2, dt: 2 * 16.67 / 1000)
        var twoSmallSteps = lerp(0, 100, speed: 0.2, dt: 16.67 / 1000)
        twoSmallSteps = lerp(twoSmallSteps, 100, speed: 0.2, dt: 16.67 / 1000)
        XCTAssertEqual(oneBigStep, twoSmallSteps, accuracy: 0.001)
    }

    // MARK: - Value range

    func testValueRangeAddsPadding() {
        let points = [
            LivelinePoint(time: 1, value: 100),
            LivelinePoint(time: 2, value: 120)
        ]

        let range = valueRange(points: points, candles: [], reference: nil)
        XCTAssertLessThan(range.min, 100)
        XCTAssertGreaterThan(range.max, 120)
    }

    func testValueRangeFlatDataGetsMinimumSpan() {
        let points = [
            LivelinePoint(time: 1, value: 100),
            LivelinePoint(time: 2, value: 100)
        ]

        let range = valueRange(points: points, candles: [], reference: nil)
        XCTAssertEqual(range.max - range.min, 0.4, accuracy: 0.0001)
        XCTAssertEqual((range.max + range.min) / 2, 100, accuracy: 0.0001)
    }

    func testValueRangeExaggerateIsTighter() {
        let points = [
            LivelinePoint(time: 1, value: 100),
            LivelinePoint(time: 2, value: 120)
        ]

        let normal = valueRange(points: points, candles: [], reference: nil)
        let tight = valueRange(points: points, candles: [], reference: nil, exaggerate: true)
        XCTAssertLessThan(tight.max - tight.min, normal.max - normal.min)
    }

    func testValueRangeIncludesReferenceAndCurrentValue() {
        let points = [LivelinePoint(time: 1, value: 100)]

        let range = valueRange(
            points: points,
            candles: [],
            currentValue: 150,
            reference: LivelineReferenceLine(value: 50)
        )
        XCTAssertLessThanOrEqual(range.min, 50)
        XCTAssertGreaterThanOrEqual(range.max, 150)
    }

    // MARK: - Interpolation

    func testInterpolatedValueAtMidpoint() {
        let points = [
            LivelinePoint(time: 0, value: 10),
            LivelinePoint(time: 10, value: 20),
            LivelinePoint(time: 20, value: 40)
        ]

        XCTAssertEqual(interpolatedValue(points, at: 5)!, 15, accuracy: 0.0001)
        XCTAssertEqual(interpolatedValue(points, at: 15)!, 30, accuracy: 0.0001)
    }

    func testInterpolatedValueClampsToEndpoints() {
        let points = [
            LivelinePoint(time: 0, value: 10),
            LivelinePoint(time: 10, value: 20)
        ]

        XCTAssertEqual(interpolatedValue(points, at: -5), 10)
        XCTAssertEqual(interpolatedValue(points, at: 99), 20)
        XCTAssertNil(interpolatedValue([], at: 0))
    }

    // MARK: - Spline

    func testSplinePassesThroughInputPoints() {
        let pts = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 10, y: 5),
            CGPoint(x: 20, y: 3),
            CGPoint(x: 30, y: 8)
        ]

        let segments = monotoneSplineSegments(pts)
        XCTAssertEqual(segments.count, pts.count - 1)
        for (i, segment) in segments.enumerated() {
            XCTAssertEqual(segment.end, pts[i + 1])
        }
    }

    func testSplineDoesNotOvershootMonotoneData() {
        // Fritsch-Carlson guarantee: for monotone data, control points stay
        // within each segment's y-bounds, so the curve never overshoots
        let pts = [
            CGPoint(x: 0, y: 0),
            CGPoint(x: 10, y: 1),
            CGPoint(x: 20, y: 10),
            CGPoint(x: 30, y: 11),
            CGPoint(x: 40, y: 30)
        ]

        var start = pts[0]
        for (i, segment) in monotoneSplineSegments(pts).enumerated() {
            let lo = min(start.y, pts[i + 1].y) - 0.0001
            let hi = max(start.y, pts[i + 1].y) + 0.0001
            XCTAssertGreaterThanOrEqual(segment.control1.y, lo)
            XCTAssertLessThanOrEqual(segment.control1.y, hi)
            XCTAssertGreaterThanOrEqual(segment.control2.y, lo)
            XCTAssertLessThanOrEqual(segment.control2.y, hi)
            start = segment.end
        }
    }

    func testSplineTwoPointsIsStraightLine() {
        let pts = [CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 10)]
        let segments = monotoneSplineSegments(pts)
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments[0].end, pts[1])
    }

    // MARK: - Momentum

    private func momentumPoints(_ values: [Double]) -> [LivelinePoint] {
        values.enumerated().map { LivelinePoint(time: TimeInterval($0.offset), value: $0.element) }
    }

    func testMomentumDetectsUp() {
        let points = momentumPoints([100, 100, 101, 100, 99, 100, 101, 103, 106, 110])
        XCTAssertEqual(detectMomentum(points: points), .up)
    }

    func testMomentumDetectsDown() {
        let points = momentumPoints([110, 110, 109, 110, 111, 110, 108, 105, 102, 100])
        XCTAssertEqual(detectMomentum(points: points), .down)
    }

    func testMomentumFlatForSmallMoves() {
        let points = momentumPoints([100, 110, 100, 110, 100, 105, 105.1, 105, 105.1, 105])
        XCTAssertEqual(detectMomentum(points: points), .flat)
    }

    func testMomentumFlatWithTooFewPoints() {
        XCTAssertEqual(detectMomentum(points: momentumPoints([1, 2, 3])), .flat)
    }

    // MARK: - Grid interval

    func testGridIntervalGivesReasonableSpacing() {
        // 100-unit range over 300px → 3 px/unit; labels need >= 36px = 12 units
        let interval = pickGridInterval(valueRange: 100, pxPerUnit: 3, minGap: 36, previous: 0)
        XCTAssertGreaterThanOrEqual(interval * 3, 36)
        XCTAssertLessThanOrEqual(interval * 3, 36 * 2.5 + 0.001)
    }

    func testGridIntervalHysteresisKeepsPrevious() {
        // Previous interval still within [0.5×, 4×] of minGap → unchanged
        let interval = pickGridInterval(valueRange: 100, pxPerUnit: 3, minGap: 36, previous: 20)
        XCTAssertEqual(interval, 20)
    }

    func testGridIntervalRepicksWhenSpacingCollapses() {
        // Previous interval now renders at 6px (< 18px) → must repick
        let interval = pickGridInterval(valueRange: 1000, pxPerUnit: 0.3, minGap: 36, previous: 20)
        XCTAssertNotEqual(interval, 20)
        XCTAssertGreaterThanOrEqual(interval * 0.3, 36)
    }

    func testIsDivisible() {
        XCTAssertTrue(isDivisible(100, by: 25))
        XCTAssertTrue(isDivisible(0.3, by: 0.1))
        XCTAssertFalse(isDivisible(103, by: 25))
    }
}
