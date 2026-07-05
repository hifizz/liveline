import Foundation

#if canImport(UIKit)
import UIKit
import CoreGraphics

/// Multi-series rendering — port of drawMultiFrame in src/draw/index.ts.
/// Fill, badge, momentum and the dashed value line are disabled; each series
/// gets its own line, endpoint dot, optional label, and a visibility alpha
/// that fades at SERIES_TOGGLE_SPEED (0.10) when hidden/shown.
extension LivelineRenderer {

    static func seriesColor(_ series: LivelineSeries, index: Int) -> UIColor {
        series.color ?? LivelinePalette.seriesColors[index % LivelinePalette.seriesColors.count]
    }

    static func drawMultiSeries(in ctx: CGContext, chartRect: CGRect, series: [LivelineSeries], hidden: Set<String>, now: TimeInterval, animNow: TimeInterval, rightEdgeTime: TimeInterval, window: TimeInterval, minValue: Double, maxValue: Double, config: LivelineConfig, palette: LivelinePalette, state: inout RenderState, dt: Double) {
        for (index, s) in series.enumerated() {
            let targetAlpha = hidden.contains(s.id) ? 0.0 : 1.0
            var alpha = lerp(state.seriesAlphas[s.id] ?? targetAlpha, targetAlpha, speed: 0.10, dt: dt)
            if alpha < 0.005, targetAlpha == 0 { alpha = 0 }
            if alpha > 0.995, targetAlpha == 1 { alpha = 1 }
            state.seriesAlphas[s.id] = alpha

            guard !s.data.isEmpty else {
                state.seriesValues[s.id] = s.value
                continue
            }
            let smooth = lerp(state.seriesValues[s.id] ?? s.value, s.value, speed: config.lerpSpeed + 0.05, dt: dt)
            state.seriesValues[s.id] = smooth

            guard alpha > 0.01 else { continue }
            let color = seriesColor(s, index: index)

            let visible = visibleSlice(s.data, leftTime: rightEdgeTime - window)
            let pts = linePoints(visible, smoothValue: smooth, tipTime: now, rightEdgeTime: rightEdgeTime, window: window, minValue: minValue, maxValue: maxValue, chartRect: chartRect)
            guard pts.count >= 2 else { continue }

            ctx.saveGState()
            ctx.clip(to: chartRect.insetBy(dx: -1, dy: 0))
            strokeSpline(ctx, points: pts, color: color.withAlphaComponent(CGFloat(alpha)), lineWidth: CGFloat(config.lineWidth))
            ctx.restoreGState()

            // Endpoint dot: colored ring pulse + solid dot (drawMultiDot)
            let tip = pts[pts.count - 1]
            if config.showDot {
                drawMultiDot(in: ctx, at: tip, color: color, alpha: alpha, pulse: config.pulse, now: animNow)
            }

            if let label = s.label {
                drawText(
                    label,
                    at: CGPoint(x: tip.x + 9, y: tip.y - 5),
                    anchorX: 0,
                    font: .systemFont(ofSize: 10, weight: .semibold),
                    color: color.withAlphaComponent(CGFloat(alpha))
                )
            }
        }
    }

    /// Series endpoint dot: expanding colored ring (1.5s interval) + solid
    /// dot, no white outer, no shadow — port of drawMultiDot in src/draw/dot.ts.
    static func drawMultiDot(in ctx: CGContext, at point: CGPoint, color: UIColor, alpha: Double, pulse: Bool, now: TimeInterval) {
        if pulse {
            let t = now.truncatingRemainder(dividingBy: 1.5) / 0.9
            if t < 1 {
                let radius = CGFloat(9 + t * 10)
                ctx.saveGState()
                ctx.setStrokeColor(color.withAlphaComponent(CGFloat(0.3 * (1 - t) * alpha)).cgColor)
                ctx.setLineWidth(1.5)
                ctx.strokeEllipse(in: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
                ctx.restoreGState()
            }
        }
        ctx.setFillColor(color.withAlphaComponent(CGFloat(alpha)).cgColor)
        ctx.fillEllipse(in: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6))
    }

    /// Multi-series crosshair: one marker dot per visible series plus an
    /// inline "TIME · ●Label V · ..." tooltip (drawMultiCrosshair port).
    static func drawMultiCrosshair(in ctx: CGContext, chartRect: CGRect, x: CGFloat, series: [LivelineSeries], hidden: Set<String>, rightEdgeTime: TimeInterval, window: TimeInterval, minValue: Double, maxValue: Double, config: LivelineConfig, palette: LivelinePalette) {
        let clampedX = clamp(x, chartRect.minX, chartRect.maxX)

        ctx.saveGState()
        ctx.setStrokeColor(palette.crosshair.cgColor)
        ctx.setLineWidth(1)
        ctx.move(to: CGPoint(x: clampedX, y: chartRect.minY))
        ctx.addLine(to: CGPoint(x: clampedX, y: chartRect.maxY))
        ctx.strokePath()
        ctx.restoreGState()

        let hoverTime = (rightEdgeTime - window) + TimeInterval((clampedX - chartRect.minX) / Swift.max(chartRect.width, 1)) * window

        struct Segment {
            let color: UIColor
            let text: String
        }
        var segments: [Segment] = []
        for (index, s) in series.enumerated() where !hidden.contains(s.id) && !s.data.isEmpty {
            guard let value = interpolatedValue(s.data, at: hoverTime) else { continue }
            let color = seriesColor(s, index: index)

            let y = clamp(yForValue(value, minValue: minValue, maxValue: maxValue, chartRect: chartRect), chartRect.minY, chartRect.maxY)
            ctx.setFillColor(color.cgColor)
            ctx.fillEllipse(in: CGRect(x: clampedX - 3, y: y - 3, width: 6, height: 6))

            let label = s.label ?? s.id
            segments.append(Segment(color: color, text: "\(label) \(config.formatValue(value))"))
        }
        guard !segments.isEmpty else { return }

        // Layout: time first, then per-series bullet + text
        let font = UIFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        let timeText = timeString(hoverTime)
        let bulletR: CGFloat = 2.5
        let gap: CGFloat = 6

        var totalW = textSize(timeText, font: font).width
        for segment in segments {
            totalW += gap + bulletR * 2 + 3 + textSize(segment.text, font: font).width
        }

        var cursorX = clamp(clampedX - totalW / 2, chartRect.minX + 4, Swift.max(chartRect.minX + 4, chartRect.maxX - totalW - 4))
        let textY = chartRect.minY + CGFloat(config.tooltipY) - font.lineHeight / 2
        let centerY = textY + font.lineHeight / 2

        cursorX += drawText(timeText, at: CGPoint(x: cursorX, y: textY), anchorX: 0, font: font, color: palette.gridLabel).width
        for segment in segments {
            cursorX += gap
            ctx.setFillColor(segment.color.cgColor)
            ctx.fillEllipse(in: CGRect(x: cursorX, y: centerY - bulletR, width: bulletR * 2, height: bulletR * 2))
            cursorX += bulletR * 2 + 3
            cursorX += drawText(segment.text, at: CGPoint(x: cursorX, y: textY), anchorX: 0, font: font, color: palette.text).width
        }
    }
}
#endif
