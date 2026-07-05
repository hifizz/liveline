import Foundation

#if canImport(UIKit)
import UIKit
import CoreGraphics

/// Degen particles + shake (src/draw/particles.ts) and the Kalshi-style
/// orderbook label stream (src/draw/orderbook.ts).

struct DegenParticle {
    var x: Double
    var y: Double
    var vx: Double
    var vy: Double
    var life: Double // 1 → 0
    var size: Double
}

struct OrderbookLabel {
    var y: Double
    let text: String
    let green: Bool
    var life: Double
    let maxLife: Double
    let intensity: Double // bigger orders = brighter
}

extension LivelineRenderer {

    // MARK: - Particles

    private static var maxParticles: Int { 80 }
    private static var particleLifetime: Double { 1.0 }
    private static var particleCooldown: Double { 0.4 }
    private static var magnitudeThreshold: Double { 0.08 }
    private static var maxBursts: Int { 3 }

    /// Swing magnitude over the last 5 points, normalized by the visible
    /// range (useLivelineEngine.ts:1824).
    static func swingMagnitude(points: [LivelinePoint], span: Double) -> Double {
        guard span > 0, points.count >= 2 else { return 0 }
        let tail = points.suffix(5)
        guard let first = tail.first, let last = tail.last else { return 0 }
        return Swift.min(abs(last.value - first.value) / span, 1)
    }

    /// Spawn particles on large swings. Returns the burst intensity
    /// (0 = didn't fire) so the caller can scale the shake.
    static func spawnParticles(state: inout RenderState, momentum: LivelineMomentum, dot: CGPoint, swing: Double, dt: Double, options: LivelineDegenOptions) -> Double {
        state.particleCooldown = Swift.max(0, state.particleCooldown - dt)

        guard momentum != .flat else { return 0 }
        guard state.particleCooldown <= 0 else { return 0 }

        // Below threshold — calm period resets the burst limiter
        guard swing >= magnitudeThreshold else {
            state.burstCount = 0
            return 0
        }
        if momentum == .down && !options.downMomentum { return 0 }
        guard state.burstCount < maxBursts else { return 0 }

        state.particleCooldown = particleCooldown

        // First burst is biggest, subsequent taper — unless the swing is huge
        let mag = Swift.min(swing * 5, 1)
        let falloffs = [1.0, 0.6, 0.35]
        let burstFalloff = mag > 0.6 ? 1 : falloffs[Swift.min(state.burstCount, falloffs.count - 1)]
        state.burstCount += 1

        let count = Int(((12 + mag * 20) * options.scale * burstFalloff).rounded())
        let speedMultiplier = 1.0 + mag * 0.8
        let baseAngle = momentum == .up ? -Double.pi / 2 : Double.pi / 2

        for _ in 0..<count where state.particles.count < maxParticles {
            let angle = baseAngle + (Double.random(in: 0..<1) - 0.5) * Double.pi * 1.2
            let speed = (60 + Double.random(in: 0..<1) * 100) * speedMultiplier
            state.particles.append(DegenParticle(
                x: Double(dot.x) + (Double.random(in: 0..<1) - 0.5) * 24,
                y: Double(dot.y) + (Double.random(in: 0..<1) - 0.5) * 8,
                vx: cos(angle) * speed,
                vy: sin(angle) * speed,
                life: 1,
                size: (1 + Double.random(in: 0..<1) * 1.2) * options.scale * burstFalloff
            ))
        }
        return burstFalloff
    }

    static func drawParticles(in ctx: CGContext, state: inout RenderState, color: UIColor, dt: Double) {
        guard !state.particles.isEmpty else { return }

        // Drag is 0.95/frame at 60fps — normalize to the actual frame time
        let drag = pow(0.95, dt * 60)
        var alive: [DegenParticle] = []
        alive.reserveCapacity(state.particles.count)

        for var p in state.particles {
            p.life -= dt / particleLifetime
            guard p.life > 0 else { continue }
            p.x += p.vx * dt
            p.y += p.vy * dt
            p.vx *= drag
            p.vy *= drag

            let radius = CGFloat(p.size * (0.5 + p.life * 0.5))
            ctx.setFillColor(color.withAlphaComponent(CGFloat(p.life * 0.55)).cgColor)
            ctx.fillEllipse(in: CGRect(x: CGFloat(p.x) - radius, y: CGFloat(p.y) - radius, width: radius * 2, height: radius * 2))
            alive.append(p)
        }
        state.particles = alive
    }

    // MARK: - Orderbook

    private static var obGreen: (Double, Double, Double) { (34, 197, 94) }
    private static var obRed: (Double, Double, Double) { (239, 68, 68) }

    static func drawOrderbook(in ctx: CGContext, chartRect: CGRect, orderbook: LivelineOrderbook, swing: Double, palette: LivelinePalette, state: inout RenderState, dt: Double) {
        guard !orderbook.bids.isEmpty || !orderbook.asks.isEmpty else { return }

        var maxSize = 0.0
        var bidTotal = 0.0
        var askTotal = 0.0
        for level in orderbook.bids { bidTotal += level.size; maxSize = Swift.max(maxSize, level.size) }
        for level in orderbook.asks { askTotal += level.size; maxSize = Swift.max(maxSize, level.size) }
        guard maxSize > 0 else { return }

        // Orderbook churn: normalized change in total size since last frame,
        // smoothed with fast attack / slow decay
        let prevTotal = state.obPrevBidTotal + state.obPrevAskTotal
        var churnSignal = 0.0
        if prevTotal > 0 {
            let delta = abs(bidTotal - state.obPrevBidTotal) + abs(askTotal - state.obPrevAskTotal)
            churnSignal = Swift.min(delta / prevTotal, 1)
        }
        state.obPrevBidTotal = bidTotal
        state.obPrevAskTotal = askTotal
        let churnLerp = churnSignal > state.obChurnRate ? 0.3 : 0.05
        state.obChurnRate += (churnSignal - state.obChurnRate) * churnLerp

        // Speed from whichever is stronger: price momentum or book churn
        let activity = Swift.max(Swift.min(swing * 5, 1), state.obChurnRate)
        let targetSpeed = 60 + activity * 100
        state.obSpeed = lerp(state.obSpeed == 0 ? 60 : state.obSpeed, targetSpeed, speed: 0.05, dt: dt)

        let labelX = chartRect.minX + 8
        let bottomY = Double(chartRect.maxY) - 6
        let topY = Double(chartRect.minY)

        // Spawn at the bottom every 40ms, keeping a 22px gap
        state.obSpawnTimer += dt * 1000
        while state.obSpawnTimer >= 40, state.obLabels.count < 50 {
            state.obSpawnTimer -= 40
            if state.obLabels.contains(where: { abs($0.y - bottomY) < 22 }) { break }

            var levels: [(size: Double, green: Bool)] = []
            for level in orderbook.bids { levels.append((level.size, true)) }
            for level in orderbook.asks { levels.append((level.size, false)) }
            let totalWeight = levels.reduce(0) { $0 + $1.size }
            var r = Double.random(in: 0..<1) * totalWeight
            var picked = levels[0]
            for level in levels {
                r -= level.size
                if r <= 0 { picked = level; break }
            }

            state.obLabels.append(OrderbookLabel(
                y: bottomY,
                text: "+ \(formatOrderSize(picked.size))",
                green: picked.green,
                life: 6,
                maxLife: 6,
                intensity: 0.5 + (picked.size / maxSize) * 0.5
            ))
        }

        // Rise + decelerate toward the top, expire by life or position
        let span = bottomY - topY
        var alive: [OrderbookLabel] = []
        alive.reserveCapacity(state.obLabels.count)
        for var label in state.obLabels {
            label.life -= dt
            guard label.life > 0 else { continue }
            let yProgress = span > 0 ? (label.y - topY) / span : 1
            label.y -= state.obSpeed * (0.7 + 0.3 * yProgress) * dt
            guard label.y >= topY - 14 else { continue }
            alive.append(label)
        }
        state.obLabels = alive

        var bgR: CGFloat = 0, bgG: CGFloat = 0, bgB: CGFloat = 0, bgA: CGFloat = 0
        _ = palette.background.getRed(&bgR, green: &bgG, blue: &bgB, alpha: &bgA)
        let bg = (Double(bgR) * 255, Double(bgG) * 255, Double(bgB) * 255)

        let font = UIFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        let chartH = Double(chartRect.height)
        for label in state.obLabels {
            let lifeRatio = label.life / label.maxLife
            let fadeIn = Swift.min((1 - lifeRatio) * 10, 1)
            let yRatio = chartH > 0 ? (label.y - topY) / chartH : 1
            let fadeOut = yRatio < 0.45 ? yRatio / 0.45 : 1
            let strength = label.intensity * fadeIn * fadeOut
            guard strength > 0.01 else { continue }

            let base = label.green ? obGreen : obRed
            let mixed = UIColor(
                red: CGFloat((base.0 + (bg.0 - base.0) * (1 - strength)) / 255),
                green: CGFloat((base.1 + (bg.1 - base.1) * (1 - strength)) / 255),
                blue: CGFloat((base.2 + (bg.2 - base.2) * (1 - strength)) / 255),
                alpha: 1
            )
            drawText(
                label.text,
                at: CGPoint(x: labelX, y: CGFloat(label.y) - font.lineHeight / 2),
                anchorX: 0,
                font: font,
                color: mixed
            )
        }
    }

    static func formatOrderSize(_ size: Double) -> String {
        if size >= 10 { return "$\(Int(size.rounded()))" }
        if size >= 1 { return String(format: "$%.1f", size) }
        return String(format: "$%.2f", size)
    }
}
#endif
