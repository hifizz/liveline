import Foundation

/// Frame-rate-independent exponential lerp, ported from `src/math/lerp.ts`.
/// `speed` is the fraction of the remaining distance covered per 16.67ms
/// (60fps) frame, so behavior matches at any display refresh rate.
@inlinable
func lerp(_ current: Double, _ target: Double, speed: Double, dt: Double) -> Double {
    let clamped = Swift.max(0, Swift.min(1, speed))
    let factor = 1 - pow(1 - clamped, dt * 1000 / 16.67)
    return current + (target - current) * factor
}

@inlinable
func clamp<T: Comparable>(_ value: T, _ lo: T, _ hi: T) -> T {
    Swift.min(Swift.max(value, lo), hi)
}

/// Visible Y range from data + live value + reference line, ported from
/// `src/math/range.ts` — 12% margin, or a centered minimum range when the
/// data is flat; `exaggerate` tightens both so small moves fill the chart.
func valueRange(
    points: [LivelinePoint],
    candles: [CandlePoint],
    currentValue: Double? = nil,
    reference: LivelineReferenceLine? = nil,
    exaggerate: Bool = false
) -> (min: Double, max: Double) {
    var targetMin = Double.infinity
    var targetMax = -Double.infinity

    for p in points {
        targetMin = Swift.min(targetMin, p.value)
        targetMax = Swift.max(targetMax, p.value)
    }
    for c in candles {
        targetMin = Swift.min(targetMin, c.low)
        targetMax = Swift.max(targetMax, c.high)
    }
    if let currentValue {
        targetMin = Swift.min(targetMin, currentValue)
        targetMax = Swift.max(targetMax, currentValue)
    }
    if let reference {
        targetMin = Swift.min(targetMin, reference.value)
        targetMax = Swift.max(targetMax, reference.value)
    }

    guard targetMin.isFinite, targetMax.isFinite else { return (0, 1) }

    let rawRange = targetMax - targetMin
    let marginFactor = exaggerate ? 0.01 : 0.12
    var minRange = rawRange * (exaggerate ? 0.02 : 0.1)
    if minRange == 0 { minRange = exaggerate ? 0.04 : 0.4 }

    if rawRange < minRange {
        let mid = (targetMin + targetMax) / 2
        return (mid - minRange / 2, mid + minRange / 2)
    }
    let margin = rawRange * marginFactor
    return (targetMin - margin, targetMax + margin)
}

/// Value at `time` by binary search + linear interpolation between the two
/// neighboring points, ported from `src/math/interpolate.ts`. Assumes
/// `points` is sorted by time ascending.
func interpolatedValue(_ points: [LivelinePoint], at time: TimeInterval) -> Double? {
    guard let first = points.first, let last = points.last else { return nil }
    if time <= first.time { return first.value }
    if time >= last.time { return last.value }

    var lo = 0
    var hi = points.count - 1
    while hi - lo > 1 {
        let mid = (lo + hi) / 2
        if points[mid].time <= time { lo = mid } else { hi = mid }
    }

    let a = points[lo]
    let b = points[hi]
    let span = b.time - a.time
    guard span > 0 else { return a.value }
    let t = (time - a.time) / span
    return a.value + (b.value - a.value) * t
}
