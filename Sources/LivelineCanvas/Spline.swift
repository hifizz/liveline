import Foundation

#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// One cubic bezier segment of a spline. The curve starts at the previous
/// segment's `end` (or the first input point) and ends at `end`.
struct SplineSegment: Equatable {
    let control1: CGPoint
    let control2: CGPoint
    let end: CGPoint
}

/// Fritsch-Carlson monotone cubic interpolation, ported from `src/math/spline.ts`.
/// Guarantees no overshoots — the curve never exceeds local min/max.
/// Platform-independent so it can be unit-tested off-device; callers build a
/// `CGPath`/`UIBezierPath` from the returned segments.
func monotoneSplineSegments(_ pts: [CGPoint]) -> [SplineSegment] {
    guard pts.count >= 2 else { return [] }
    if pts.count == 2 {
        return [SplineSegment(control1: pts[0], control2: pts[1], end: pts[1])]
    }

    let n = pts.count

    // 1. Secant slopes between consecutive points
    var h = [CGFloat](repeating: 0, count: n - 1)
    var delta = [CGFloat](repeating: 0, count: n - 1)
    for i in 0..<(n - 1) {
        h[i] = pts[i + 1].x - pts[i].x
        delta[i] = h[i] == 0 ? 0 : (pts[i + 1].y - pts[i].y) / h[i]
    }

    // 2. Initial tangent estimates — zero at sign changes for monotonicity
    var m = [CGFloat](repeating: 0, count: n)
    m[0] = delta[0]
    m[n - 1] = delta[n - 2]
    for i in 1..<(n - 1) {
        m[i] = delta[i - 1] * delta[i] <= 0 ? 0 : (delta[i - 1] + delta[i]) / 2
    }

    // 3. Fritsch-Carlson constraint: alpha^2 + beta^2 <= 9
    for i in 0..<(n - 1) {
        if delta[i] == 0 {
            m[i] = 0
            m[i + 1] = 0
        } else {
            let alpha = m[i] / delta[i]
            let beta = m[i + 1] / delta[i]
            let s2 = alpha * alpha + beta * beta
            if s2 > 9 {
                let s = 3 / s2.squareRoot()
                m[i] = s * alpha * delta[i]
                m[i + 1] = s * beta * delta[i]
            }
        }
    }

    // 4. Bezier control points from tangents
    var segments: [SplineSegment] = []
    segments.reserveCapacity(n - 1)
    for i in 0..<(n - 1) {
        let hi = h[i]
        segments.append(SplineSegment(
            control1: CGPoint(x: pts[i].x + hi / 3, y: pts[i].y + m[i] * hi / 3),
            control2: CGPoint(x: pts[i + 1].x - hi / 3, y: pts[i + 1].y - m[i + 1] * hi / 3),
            end: pts[i + 1]
        ))
    }
    return segments
}
