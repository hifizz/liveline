import XCTest
@testable import LivelineCanvasTests

fileprivate extension LivelineCanvasTests {
    @available(*, deprecated, message: "Not actually deprecated. Marked as deprecated to allow inclusion of deprecated tests (which test deprecated functionality) without warnings")
    static nonisolated(unsafe) let __allTests__LivelineCanvasTests = [
        ("testInterpolatedValueAtMidpoint", testInterpolatedValueAtMidpoint),
        ("testInterpolatedValueClampsToEndpoints", testInterpolatedValueClampsToEndpoints),
        ("testLerpIsFrameRateIndependent", testLerpIsFrameRateIndependent),
        ("testLerpMovesTowardTarget", testLerpMovesTowardTarget),
        ("testSplineDoesNotOvershootMonotoneData", testSplineDoesNotOvershootMonotoneData),
        ("testSplinePassesThroughInputPoints", testSplinePassesThroughInputPoints),
        ("testSplineTwoPointsIsStraightLine", testSplineTwoPointsIsStraightLine),
        ("testValueRangeAddsPadding", testValueRangeAddsPadding),
        ("testValueRangeExaggerateIsTighter", testValueRangeExaggerateIsTighter),
        ("testValueRangeFlatDataGetsMinimumSpan", testValueRangeFlatDataGetsMinimumSpan),
        ("testValueRangeIncludesReferenceAndCurrentValue", testValueRangeIncludesReferenceAndCurrentValue)
    ]
}
@available(*, deprecated, message: "Not actually deprecated. Marked as deprecated to allow inclusion of deprecated tests (which test deprecated functionality) without warnings")
func __LivelineCanvasTests__allTests() -> [XCTestCaseEntry] {
    return [
        testCase(LivelineCanvasTests.__allTests__LivelineCanvasTests)
    ]
}