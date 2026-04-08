import Foundation

@inlinable
func lerp(_ current: Double, _ target: Double, speed: Double, dt: Double) -> Double {
    let s = max(0, min(1, speed * dt * 60))
    return current + (target - current) * s
}

@inlinable
func clamp<T: Comparable>(_ value: T, _ lo: T, _ hi: T) -> T {
    min(max(value, lo), hi)
}

func valueRange(points: [LivelinePoint], candles: [CandlePoint], reference: LivelineReferenceLine?) -> (min: Double, max: Double) {
    var minV = Double.greatestFiniteMagnitude
    var maxV = -Double.greatestFiniteMagnitude

    for p in points {
        minV = min(minV, p.value)
        maxV = max(maxV, p.value)
    }

    for c in candles {
        minV = min(minV, c.low)
        maxV = max(maxV, c.high)
    }

    if let reference {
        minV = min(minV, reference.value)
        maxV = max(maxV, reference.value)
    }

    if !minV.isFinite || !maxV.isFinite {
        return (0, 1)
    }

    if abs(maxV - minV) < .ulpOfOne {
        let epsilon = max(0.0001, abs(minV) * 0.01)
        return (minV - epsilon, maxV + epsilon)
    }

    let pad = (maxV - minV) * 0.05
    return (minV - pad, maxV + pad)
}
