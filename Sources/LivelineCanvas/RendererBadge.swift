import Foundation

#if canImport(UIKit)
import UIKit
import CoreGraphics

/// Badge pill + momentum arrows — ports of src/draw/badge.ts and the arrow
/// part of src/draw/dot.ts. The React badge is a DOM/SVG overlay; here it is
/// drawn straight into the canvas.
extension LivelineRenderer {

    // Badge geometry constants from src/draw/badge.ts
    private static var badgePadX: CGFloat { 10 }
    private static var badgeLineH: CGFloat { 16 }
    private static var badgePadY: CGFloat { 3 }
    private static var badgeTailLen: CGFloat { 5 }
    private static var badgeTailSpread: CGFloat { 2.5 }

    static func drawBadge(in ctx: CGContext, rect: CGRect, chartRect: CGRect, value: Double, valueY: CGFloat, momentum: LivelineMomentum, config: LivelineConfig, palette: LivelinePalette, state: inout RenderState, dt: Double) {
        // Hidden while pausing, like the web version
        let visibility = 1 - state.pauseProgress
        guard visibility > 0.02 else { return }

        let text = config.formatValue(value)
        let font = UIFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        let targetW = Double(textSize(text, font: font).width) + Double(badgePadX * 2)

        // Width lerps at 0.15, Y tracks the value at 0.35 (badge.ts constants)
        state.badgeWidth = state.badgeWidth == 0 ? targetW : lerp(state.badgeWidth, targetW, speed: 0.15, dt: dt)
        state.badgeY = state.badgeY == 0 ? Double(valueY) : lerp(state.badgeY, Double(valueY), speed: 0.35, dt: dt)

        // Momentum color: lerp toward green/red/accent at 0.12
        let targetColor: UIColor
        if config.momentum.isOff {
            targetColor = palette.line
        } else {
            switch momentum {
            case .up: targetColor = palette.upCandle
            case .down: targetColor = palette.downCandle
            case .flat: targetColor = palette.line
            }
        }
        var tr: CGFloat = 0, tg: CGFloat = 0, tb: CGFloat = 0, ta: CGFloat = 0
        _ = targetColor.getRed(&tr, green: &tg, blue: &tb, alpha: &ta)
        if !state.badgeColorInitialized {
            state.badgeColor = (Double(tr), Double(tg), Double(tb))
            state.badgeColorInitialized = true
        } else {
            state.badgeColor.r = lerp(state.badgeColor.r, Double(tr), speed: 0.12, dt: dt)
            state.badgeColor.g = lerp(state.badgeColor.g, Double(tg), speed: 0.12, dt: dt)
            state.badgeColor.b = lerp(state.badgeColor.b, Double(tb), speed: 0.12, dt: dt)
        }

        let fillColor: UIColor
        let textColor: UIColor
        switch config.badgeVariant {
        case .default:
            fillColor = UIColor(
                red: CGFloat(state.badgeColor.r),
                green: CGFloat(state.badgeColor.g),
                blue: CGFloat(state.badgeColor.b),
                alpha: CGFloat(visibility)
            )
            textColor = UIColor(white: 1, alpha: CGFloat(visibility))
        case .minimal:
            fillColor = palette.dotOuter.withAlphaComponent(CGFloat(visibility * 0.95))
            textColor = palette.text.withAlphaComponent(CGFloat(visibility))
        }

        let pillH = badgeLineH + badgePadY * 2
        let tailLen = config.badgeTail ? badgeTailLen : 0
        // Tail tip sits just right of the chart area, pointing at the dot
        let tipX = chartRect.maxX + 8
        let midY = clamp(CGFloat(state.badgeY), rect.minY + pillH / 2, rect.maxY - pillH / 2)
        let pillRect = CGRect(x: tipX + tailLen, y: midY - pillH / 2, width: CGFloat(state.badgeWidth), height: pillH)

        let path = CGMutablePath()
        addRoundedRect(pillRect, radius: pillH / 2, to: path)
        if config.badgeTail {
            path.move(to: CGPoint(x: pillRect.minX + 3, y: midY - 5))
            path.addQuadCurve(to: CGPoint(x: tipX, y: midY), control: CGPoint(x: tipX + 2, y: midY - badgeTailSpread))
            path.addQuadCurve(to: CGPoint(x: pillRect.minX + 3, y: midY + 5), control: CGPoint(x: tipX + 2, y: midY + badgeTailSpread))
            path.closeSubpath()
        }

        ctx.saveGState()
        if config.badgeVariant == .minimal {
            ctx.setShadow(offset: CGSize(width: 0, height: 1), blur: 4, color: UIColor.black.withAlphaComponent(0.3).cgColor)
        }
        ctx.setFillColor(fillColor.cgColor)
        ctx.addPath(path)
        ctx.fillPath()
        ctx.restoreGState()

        drawText(
            text,
            at: CGPoint(x: pillRect.midX, y: midY - font.lineHeight / 2),
            anchorX: 0.5,
            font: font,
            color: textColor
        )
    }

    private static func addRoundedRect(_ rect: CGRect, radius: CGFloat, to path: CGMutablePath) {
        let r = Swift.min(radius, Swift.min(rect.width, rect.height) / 2)
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.maxY), radius: r)
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.maxY), radius: r)
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY), tangent2End: CGPoint(x: rect.minX, y: rect.minY), radius: r)
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY), tangent2End: CGPoint(x: rect.maxX, y: rect.minY), radius: r)
        path.closeSubpath()
    }

    /// Momentum chevrons next to the dot — directional cascade, old direction
    /// fades out fully before the new one fades in (src/draw/dot.ts drawArrows).
    static func drawArrows(in ctx: CGContext, at dot: CGPoint, momentum: LivelineMomentum, palette: LivelinePalette, state: inout RenderState, dt: Double, now: TimeInterval) {
        let upTarget = momentum == .up ? 1.0 : 0.0
        let downTarget = momentum == .down ? 1.0 : 0.0
        let canFadeInUp = state.arrowDown < 0.02
        let canFadeInDown = state.arrowUp < 0.02

        state.arrowUp = lerp(state.arrowUp, canFadeInUp ? upTarget : 0, speed: upTarget > state.arrowUp ? 0.08 : 0.04, dt: dt)
        state.arrowDown = lerp(state.arrowDown, canFadeInDown ? downTarget : 0, speed: downTarget > state.arrowDown ? 0.08 : 0.04, dt: dt)
        if state.arrowUp < 0.01 { state.arrowUp = 0 }
        if state.arrowDown < 0.01 { state.arrowDown = 0 }
        if state.arrowUp > 0.99 { state.arrowUp = 1 }
        if state.arrowDown > 0.99 { state.arrowDown = 1 }

        let ms = now.truncatingRemainder(dividingBy: 86_400) * 1000
        let cycle = ms.truncatingRemainder(dividingBy: 1400) / 1400

        func chevrons(dir: CGFloat, opacity: Double) {
            guard opacity >= 0.01 else { return }
            let baseX = dot.x + 19

            ctx.saveGState()
            ctx.setLineWidth(2.5)
            ctx.setLineJoin(.round)
            ctx.setLineCap(.round)

            for i in 0..<2 {
                // Stagger: arrow 0 brightens at t=0, arrow 1 at t=0.2; both
                // stay visible at min 0.3 while the cascade brightens them
                let start = Double(i) * 0.2
                let dur = 0.35
                let localT = cycle - start
                let wave = (localT >= 0 && localT < dur) ? sin((localT / dur) * .pi) : 0
                let pulse = 0.3 + 0.7 * wave

                ctx.setStrokeColor(palette.gridLabel.withAlphaComponent(CGFloat(opacity * pulse)).cgColor)
                let nudge: CGFloat = dir == -1 ? -3 : 3
                let cy = dot.y + dir * (CGFloat(i) * 8 - 4) + nudge
                ctx.move(to: CGPoint(x: baseX - 5, y: cy - dir * 3.5))
                ctx.addLine(to: CGPoint(x: baseX, y: cy))
                ctx.addLine(to: CGPoint(x: baseX + 5, y: cy - dir * 3.5))
                ctx.strokePath()
            }
            ctx.restoreGState()
        }

        chevrons(dir: -1, opacity: state.arrowUp)
        chevrons(dir: 1, opacity: state.arrowDown)
    }
}
#endif
