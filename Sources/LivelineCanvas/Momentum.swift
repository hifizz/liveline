import Foundation

public enum LivelineMomentum: Sendable, Equatable {
    case up
    case down
    case flat
}

/// How the chart decides the current momentum (dot glow, arrows, badge color).
public enum LivelineMomentumMode: Sendable, Equatable {
    /// No momentum styling at all.
    case off
    /// Detect from recent data (default).
    case auto
    /// Force a fixed direction.
    case fixed(LivelineMomentum)

    var isOff: Bool { self == .off }
}

/// Port of `src/math/momentum.ts`: range over the last `lookback` points sets
/// the scale, velocity over the last 5 points sets the direction. Threshold
/// is 12% of the recent range.
func detectMomentum(points: [LivelinePoint], lookback: Int = 20) -> LivelineMomentum {
    guard points.count >= 5 else { return .flat }

    let recent = Array(points.suffix(lookback))
    var lo = Double.infinity
    var hi = -Double.infinity
    for p in recent {
        lo = Swift.min(lo, p.value)
        hi = Swift.max(hi, p.value)
    }
    let range = hi - lo
    guard range > 0 else { return .flat }

    let tail = Array(recent.suffix(5))
    let delta = tail[tail.count - 1].value - tail[0].value
    let threshold = range * 0.12

    if delta > threshold { return .up }
    if delta < -threshold { return .down }
    return .flat
}
