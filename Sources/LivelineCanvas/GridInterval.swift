import Foundation

/// Pick a nice grid interval using TradingView's cycling divisor approach,
/// ported from `src/draw/grid.ts`. Hysteresis: once chosen, the interval
/// sticks until its pixel spacing falls outside [0.5×, 4×] of `minGap`.
func pickGridInterval(valueRange: Double, pxPerUnit: Double, minGap: Double, previous: Double) -> Double {
    guard valueRange > 0, pxPerUnit > 0 else { return 1 }

    if previous > 0 {
        let px = previous * pxPerUnit
        if px >= minGap * 0.5 && px <= minGap * 4 { return previous }
    }

    let divisorSets: [[Double]] = [[2, 2.5, 2], [2, 2, 2.5], [2.5, 2, 2]]
    var best = Double.infinity
    for divs in divisorSets {
        var span = pow(10, ceil(log10(valueRange)))
        var i = 0
        while span / divs[i % 3] * pxPerUnit >= minGap {
            span /= divs[i % 3]
            i += 1
        }
        if span < best { best = span }
    }
    return best.isFinite ? best : valueRange / 5
}

/// Float-safe divisibility check.
func isDivisible(_ value: Double, by interval: Double) -> Bool {
    guard interval != 0 else { return false }
    let ratio = value / interval
    return abs(ratio - ratio.rounded()) < 0.01
}
