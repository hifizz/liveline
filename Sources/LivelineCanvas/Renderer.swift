import Foundation

#if canImport(UIKit)
import UIKit
import CoreGraphics

struct RenderState {
    var displayValue: Double = 0
    var displayMin: Double = 0
    var displayMax: Double = 1
    var initialized = false
    /// Wall-clock time captured when `isPaused` flipped on; while set, the
    /// chart clock is frozen so scrolling stops. (The React engine also
    /// animates a smooth catch-up on resume; that part is not ported.)
    var pausedAt: TimeInterval?
}

struct RenderInput {
    let rect: CGRect
    let points: [LivelinePoint]
    let candles: [CandlePoint]
    let value: Double
    let config: LivelineConfig
    let palette: LivelinePalette
    let referenceLine: LivelineReferenceLine?
    let hoverX: CGFloat?
    let isPaused: Bool
    let isLoading: Bool
    let now: TimeInterval
}

enum LivelineRenderer {
    static func render(_ ctx: CGContext, input: RenderInput, state: inout RenderState, dt: Double) {
        let rect = input.rect
        let config = input.config
        let palette = input.palette

        ctx.setFillColor(palette.background.cgColor)
        ctx.fill(rect)

        let chartRect = rect.inset(by: UIEdgeInsets(
            top: CGFloat(config.insets.top),
            left: CGFloat(config.insets.left),
            bottom: CGFloat(config.insets.bottom),
            right: CGFloat(config.insets.right)
        ))
        guard chartRect.width > 0, chartRect.height > 0 else { return }

        guard !input.isLoading else {
            drawSquiggly(in: ctx, chartRect: chartRect, palette: palette, now: input.now)
            return
        }

        guard !(input.points.isEmpty && input.candles.isEmpty) else {
            drawEmpty(in: ctx, chartRect: chartRect, config: config, palette: palette, now: input.now)
            return
        }

        // Freeze the chart clock while paused so scrolling stops.
        if input.isPaused {
            if state.pausedAt == nil { state.pausedAt = input.now }
        } else {
            state.pausedAt = nil
        }
        let now = state.pausedAt ?? input.now

        let window = Swift.max(config.windowSeconds, 1)
        let visiblePoints = visibleSlice(input.points, leftTime: now - window)
        let visibleCandles = input.candles.filter { $0.time >= now - window - config.candleWidthSeconds }

        let range = valueRange(
            points: config.mode == .line ? visiblePoints : [],
            candles: config.mode == .candle ? visibleCandles : [],
            currentValue: input.value,
            reference: input.referenceLine,
            exaggerate: config.exaggerate
        )
        if !state.initialized {
            state.displayValue = input.value
            state.displayMin = range.min
            state.displayMax = range.max
            state.initialized = true
        } else if !input.isPaused {
            state.displayValue = lerp(state.displayValue, input.value, speed: config.lerpSpeed, dt: dt)
            state.displayMin = lerp(state.displayMin, range.min, speed: config.lerpSpeed + 0.07, dt: dt)
            state.displayMax = lerp(state.displayMax, range.max, speed: config.lerpSpeed + 0.07, dt: dt)
        }
        let minValue = state.displayMin
        let maxValue = state.displayMax

        if config.showGrid {
            drawGrid(in: ctx, chartRect: chartRect, minValue: minValue, maxValue: maxValue, config: config, palette: palette)
        }
        drawTimeAxis(in: ctx, chartRect: chartRect, now: now, window: window, palette: palette)

        if let reference = input.referenceLine {
            drawReferenceLine(in: ctx, chartRect: chartRect, minValue: minValue, maxValue: maxValue, value: reference.value, color: palette.reference)
        }

        switch config.mode {
        case .line:
            drawLine(in: ctx, chartRect: chartRect, points: visiblePoints, smoothValue: state.displayValue, now: now, window: window, minValue: minValue, maxValue: maxValue, config: config, palette: palette)
            if config.showDot, !visiblePoints.isEmpty {
                let tipY = yForValue(state.displayValue, minValue: minValue, maxValue: maxValue, chartRect: chartRect)
                // Clamp to the canvas (not the chart area) so the dot stays visible
                let dotY = clamp(tipY, rect.minY + 10, rect.maxY - 10)
                drawDot(in: ctx, at: CGPoint(x: chartRect.maxX, y: dotY), palette: palette, pulse: config.pulse, now: input.now)
            }
        case .candle:
            drawCandles(in: ctx, chartRect: chartRect, candles: visibleCandles, now: now, window: window, minValue: minValue, maxValue: maxValue, config: config, palette: palette)
        }

        if let hoverX = input.hoverX, config.showCrosshair {
            drawCrosshair(in: ctx, chartRect: chartRect, x: hoverX, points: input.points, now: now, window: window, minValue: minValue, maxValue: maxValue, config: config, palette: palette)
        }

        if config.showValueLabel {
            drawText(
                config.formatValue(state.displayValue),
                at: CGPoint(x: rect.maxX - 12, y: rect.minY + 8),
                anchorX: 1,
                font: .monospacedDigitSystemFont(ofSize: 12, weight: .medium),
                color: palette.text
            )
        }
    }

    // MARK: - Geometry

    /// Points inside the window plus one point just left of it, so the line
    /// enters from the chart edge instead of popping in.
    private static func visibleSlice(_ points: [LivelinePoint], leftTime: TimeInterval) -> [LivelinePoint] {
        guard let firstVisible = points.firstIndex(where: { $0.time >= leftTime }) else {
            // Everything is older than the window — keep the newest point so
            // the live tip still has an anchor.
            return points.suffix(1).map { $0 }
        }
        let start = firstVisible > 0 ? firstVisible - 1 : 0
        return Array(points[start...])
    }

    private static func xForTime(_ t: TimeInterval, now: TimeInterval, window: TimeInterval, chartRect: CGRect) -> CGFloat {
        let ratio = CGFloat((t - (now - window)) / window)
        return chartRect.minX + ratio * chartRect.width
    }

    private static func yForValue(_ v: Double, minValue: Double, maxValue: Double, chartRect: CGRect) -> CGFloat {
        let span = maxValue - minValue
        guard span > 0 else { return chartRect.midY }
        let ratio = CGFloat((v - minValue) / span)
        return chartRect.maxY - ratio * chartRect.height
    }

    // MARK: - Grid + axes

    private static func drawGrid(in ctx: CGContext, chartRect: CGRect, minValue: Double, maxValue: Double, config: LivelineConfig, palette: LivelinePalette) {
        let rows = 4
        ctx.saveGState()
        ctx.setStrokeColor(palette.grid.cgColor)
        ctx.setLineWidth(1)
        ctx.setLineDash(phase: 0, lengths: [1, 3])
        for i in 0...rows {
            let y = chartRect.minY + (CGFloat(i) / CGFloat(rows)) * chartRect.height
            ctx.move(to: CGPoint(x: chartRect.minX, y: y))
            ctx.addLine(to: CGPoint(x: chartRect.maxX, y: y))
        }
        ctx.strokePath()
        ctx.restoreGState()

        let font = UIFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        for i in 0...rows {
            let ratio = Double(i) / Double(rows)
            let value = maxValue - ratio * (maxValue - minValue)
            let y = chartRect.minY + CGFloat(ratio) * chartRect.height
            drawText(
                config.formatValue(value),
                at: CGPoint(x: chartRect.maxX + 8, y: y - font.lineHeight / 2),
                anchorX: 0,
                font: font,
                color: palette.gridLabel
            )
        }
    }

    private static func niceTimeInterval(_ windowSecs: TimeInterval) -> TimeInterval {
        switch windowSecs {
        case ...15: return 2
        case ...30: return 5
        case ...60: return 10
        case ...120: return 15
        case ...300: return 30
        case ...600: return 60
        case ...1800: return 300
        case ...3600: return 600
        case ...14400: return 1800
        case ...43200: return 3600
        case ...86400: return 7200
        case ...604800: return 86400
        default: return 604800
        }
    }

    private static func drawTimeAxis(in ctx: CGContext, chartRect: CGRect, now: TimeInterval, window: TimeInterval, palette: LivelinePalette) {
        ctx.saveGState()
        ctx.setStrokeColor(palette.grid.cgColor)
        ctx.setLineWidth(1)
        ctx.move(to: CGPoint(x: chartRect.minX, y: chartRect.maxY))
        ctx.addLine(to: CGPoint(x: chartRect.maxX, y: chartRect.maxY))
        ctx.strokePath()

        var interval = niceTimeInterval(window)
        while chartRect.width * CGFloat(interval / window) < 60 { interval *= 2 }

        let font = UIFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        var t = ((now - window) / interval).rounded(.up) * interval
        ctx.setStrokeColor(palette.timeLabel.cgColor)
        while t <= now {
            let x = xForTime(t, now: now, window: window, chartRect: chartRect)
            ctx.move(to: CGPoint(x: x, y: chartRect.maxY))
            ctx.addLine(to: CGPoint(x: x, y: chartRect.maxY + 5))
            ctx.strokePath()
            drawText(
                timeString(t),
                at: CGPoint(x: x, y: chartRect.maxY + 8),
                anchorX: 0.5,
                font: font,
                color: palette.timeLabel
            )
            t += interval
        }
        ctx.restoreGState()
    }

    // MARK: - Line mode

    private static func drawLine(in ctx: CGContext, chartRect: CGRect, points: [LivelinePoint], smoothValue: Double, now: TimeInterval, window: TimeInterval, minValue: Double, maxValue: Double, config: LivelineConfig, palette: LivelinePalette) {
        guard !points.isEmpty else { return }
        let clampY: (CGFloat) -> CGFloat = { clamp($0, chartRect.minY, chartRect.maxY) }

        // Historical points keep their data values; the LAST data point takes
        // the interpolated value so big jumps animate instead of snapping,
        // then the live tip is appended at the right edge (matches
        // src/draw/line.ts).
        var pts: [CGPoint] = []
        pts.reserveCapacity(points.count + 1)
        for (index, p) in points.enumerated() {
            let x = xForTime(p.time, now: now, window: window, chartRect: chartRect)
            let v = index == points.count - 1 ? smoothValue : p.value
            pts.append(CGPoint(x: x, y: clampY(yForValue(v, minValue: minValue, maxValue: maxValue, chartRect: chartRect))))
        }
        let tipY = clampY(yForValue(smoothValue, minValue: minValue, maxValue: maxValue, chartRect: chartRect))
        pts.append(CGPoint(x: chartRect.maxX, y: tipY))
        guard pts.count >= 2 else { return }

        let linePath = CGMutablePath()
        linePath.move(to: pts[0])
        for segment in monotoneSplineSegments(pts) {
            linePath.addCurve(to: segment.end, control1: segment.control1, control2: segment.control2)
        }

        ctx.saveGState()
        ctx.clip(to: chartRect.insetBy(dx: -1, dy: 0))

        if config.showFill {
            let fillPath = linePath.mutableCopy()!
            fillPath.addLine(to: CGPoint(x: pts[pts.count - 1].x, y: chartRect.maxY))
            fillPath.addLine(to: CGPoint(x: pts[0].x, y: chartRect.maxY))
            fillPath.closeSubpath()

            ctx.saveGState()
            ctx.addPath(fillPath)
            ctx.clip()
            var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
            var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
            _ = palette.fillTop.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
            _ = palette.fillBottom.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
            let components: [CGFloat] = [r1, g1, b1, a1, r2, g2, b2, a2]
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colorComponents: components, locations: [0, 1], count: 2) {
                ctx.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0, y: chartRect.minY),
                    end: CGPoint(x: 0, y: chartRect.maxY),
                    options: []
                )
            }
            ctx.restoreGState()
        }

        ctx.setStrokeColor(palette.line.cgColor)
        ctx.setLineWidth(CGFloat(config.lineWidth))
        ctx.setLineJoin(.round)
        ctx.setLineCap(.round)
        ctx.addPath(linePath)
        ctx.strokePath()
        ctx.restoreGState()

        if config.showDashLine {
            ctx.saveGState()
            ctx.setStrokeColor(palette.dashLine.cgColor)
            ctx.setLineWidth(1)
            ctx.setLineDash(phase: 0, lengths: [4, 4])
            ctx.move(to: CGPoint(x: chartRect.minX, y: tipY))
            ctx.addLine(to: CGPoint(x: chartRect.maxX, y: tipY))
            ctx.strokePath()
            ctx.restoreGState()
        }
    }

    /// Live dot: expanding accent pulse ring (1.5s interval, 0.9s duration),
    /// outer circle with shadow, colored inner dot — port of src/draw/dot.ts.
    private static func drawDot(in ctx: CGContext, at point: CGPoint, palette: LivelinePalette, pulse: Bool, now: TimeInterval) {
        if pulse {
            let t = now.truncatingRemainder(dividingBy: 1.5) / 0.9
            if t < 1 {
                let radius = CGFloat(9 + t * 12)
                ctx.saveGState()
                ctx.setStrokeColor(palette.line.withAlphaComponent(CGFloat(0.35 * (1 - t))).cgColor)
                ctx.setLineWidth(1.5)
                ctx.strokeEllipse(in: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
                ctx.restoreGState()
            }
        }

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: 1), blur: 6, color: UIColor.black.withAlphaComponent(0.4).cgColor)
        ctx.setFillColor(palette.dotOuter.cgColor)
        ctx.fillEllipse(in: CGRect(x: point.x - 6.5, y: point.y - 6.5, width: 13, height: 13))
        ctx.restoreGState()

        ctx.setFillColor(palette.line.cgColor)
        ctx.fillEllipse(in: CGRect(x: point.x - 3.5, y: point.y - 3.5, width: 7, height: 7))
    }

    // MARK: - Candle mode

    private static func drawCandles(in ctx: CGContext, chartRect: CGRect, candles: [CandlePoint], now: TimeInterval, window: TimeInterval, minValue: Double, maxValue: Double, config: LivelineConfig, palette: LivelinePalette) {
        guard !candles.isEmpty else { return }
        let pxPerSecond = chartRect.width / CGFloat(window)
        let bodyWidth = Swift.max(1, pxPerSecond * CGFloat(config.candleWidthSeconds) * 0.7)
        let wickWidth = clamp(bodyWidth * 0.15, 0.8, 2)

        ctx.saveGState()
        ctx.clip(to: chartRect.insetBy(dx: -1, dy: 0))
        for c in candles {
            // Candle time is the bucket's open time — center the body on it
            let x = xForTime(c.time + config.candleWidthSeconds / 2, now: now, window: window, chartRect: chartRect)
            let yOpen = yForValue(c.open, minValue: minValue, maxValue: maxValue, chartRect: chartRect)
            let yClose = yForValue(c.close, minValue: minValue, maxValue: maxValue, chartRect: chartRect)
            let yHigh = yForValue(c.high, minValue: minValue, maxValue: maxValue, chartRect: chartRect)
            let yLow = yForValue(c.low, minValue: minValue, maxValue: maxValue, chartRect: chartRect)

            let isUp = c.close >= c.open
            let color = isUp ? palette.upCandle : palette.downCandle

            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(wickWidth)
            ctx.move(to: CGPoint(x: x, y: yHigh))
            ctx.addLine(to: CGPoint(x: x, y: yLow))
            ctx.strokePath()

            let bodyTop = Swift.min(yOpen, yClose)
            let bodyBottom = Swift.max(yOpen, yClose)
            let bodyRect = CGRect(
                x: x - bodyWidth / 2,
                y: bodyTop,
                width: bodyWidth,
                height: Swift.max(1, bodyBottom - bodyTop)
            )
            ctx.setFillColor(color.cgColor)
            ctx.fill(bodyRect)
        }
        ctx.restoreGState()

        // Dashed close-price line at the latest close (candle-colored)
        if config.showDashLine, let last = candles.last {
            let y = clamp(
                yForValue(last.close, minValue: minValue, maxValue: maxValue, chartRect: chartRect),
                chartRect.minY, chartRect.maxY
            )
            let color = last.close >= last.open ? palette.upCandle : palette.downCandle
            ctx.saveGState()
            ctx.setStrokeColor(color.withAlphaComponent(0.4).cgColor)
            ctx.setLineWidth(1)
            ctx.setLineDash(phase: 0, lengths: [4, 4])
            ctx.move(to: CGPoint(x: chartRect.minX, y: y))
            ctx.addLine(to: CGPoint(x: chartRect.maxX, y: y))
            ctx.strokePath()
            ctx.restoreGState()
        }
    }

    // MARK: - Overlays

    private static func drawCrosshair(in ctx: CGContext, chartRect: CGRect, x: CGFloat, points: [LivelinePoint], now: TimeInterval, window: TimeInterval, minValue: Double, maxValue: Double, config: LivelineConfig, palette: LivelinePalette) {
        let clampedX = clamp(x, chartRect.minX, chartRect.maxX)

        ctx.saveGState()
        ctx.setStrokeColor(palette.crosshair.cgColor)
        ctx.setLineWidth(1)
        ctx.move(to: CGPoint(x: clampedX, y: chartRect.minY))
        ctx.addLine(to: CGPoint(x: clampedX, y: chartRect.maxY))
        ctx.strokePath()
        ctx.restoreGState()

        guard !points.isEmpty else { return }
        let hoverTime = (now - window) + TimeInterval((clampedX - chartRect.minX) / Swift.max(chartRect.width, 1)) * window
        guard let value = interpolatedValue(points, at: hoverTime) else { return }

        // Marker dot on the line at the hovered value
        let y = clamp(yForValue(value, minValue: minValue, maxValue: maxValue, chartRect: chartRect), chartRect.minY, chartRect.maxY)
        ctx.setFillColor(palette.line.cgColor)
        ctx.fillEllipse(in: CGRect(x: clampedX - 4, y: y - 4, width: 8, height: 8))

        // "VALUE · TIME" inline tooltip near the top, clamped into the chart
        let font = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        let text = "\(config.formatValue(value))  ·  \(timeString(hoverTime))"
        let size = textSize(text, font: font)
        let textX = clamp(clampedX - size.width / 2, chartRect.minX + 4, chartRect.maxX - size.width - 4)
        drawText(
            text,
            at: CGPoint(x: textX, y: chartRect.minY + CGFloat(config.tooltipY) - size.height / 2),
            anchorX: 0,
            font: font,
            color: palette.text
        )
    }

    private static func drawReferenceLine(in ctx: CGContext, chartRect: CGRect, minValue: Double, maxValue: Double, value: Double, color: UIColor) {
        let y = yForValue(value, minValue: minValue, maxValue: maxValue, chartRect: chartRect)
        guard y >= chartRect.minY - 10, y <= chartRect.maxY + 10 else { return }
        ctx.saveGState()
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(1)
        ctx.setLineDash(phase: 0, lengths: [4, 4])
        ctx.move(to: CGPoint(x: chartRect.minX, y: y))
        ctx.addLine(to: CGPoint(x: chartRect.maxX, y: y))
        ctx.strokePath()
        ctx.restoreGState()
    }

    // MARK: - Loading / empty

    /// Breathing squiggly line, same shape constants as src/draw/loadingShape.ts.
    private static func drawSquiggly(in ctx: CGContext, chartRect: CGRect, palette: LivelinePalette, now: TimeInterval, alphaScale: Double = 1) {
        // Keep the sine arguments small for precision — the shape repeats anyway
        let ms = now.truncatingRemainder(dividingBy: 86_400) * 1000
        let scroll = ms * 0.001
        let breath = 0.22 + 0.08 * sin(ms / 1200 * .pi)
        let amplitude = Double(chartRect.height) * 0.07
        let centerY = Double(chartRect.midY)

        let samples = 32
        var pts: [CGPoint] = []
        pts.reserveCapacity(samples + 1)
        for i in 0...samples {
            let t = Double(i) / Double(samples)
            let y = centerY + amplitude * (
                sin(t * 9.4 + scroll) * 0.55 +
                sin(t * 15.7 + scroll * 1.3) * 0.3 +
                sin(t * 4.2 + scroll * 0.7) * 0.15
            )
            pts.append(CGPoint(x: chartRect.minX + CGFloat(t) * chartRect.width, y: CGFloat(y)))
        }

        let path = CGMutablePath()
        path.move(to: pts[0])
        for segment in monotoneSplineSegments(pts) {
            path.addCurve(to: segment.end, control1: segment.control1, control2: segment.control2)
        }

        ctx.saveGState()
        ctx.setStrokeColor(palette.gridLabel.withAlphaComponent(CGFloat(breath * alphaScale)).cgColor)
        ctx.setLineWidth(2)
        ctx.setLineJoin(.round)
        ctx.setLineCap(.round)
        ctx.addPath(path)
        ctx.strokePath()
        ctx.restoreGState()
    }

    private static func drawEmpty(in ctx: CGContext, chartRect: CGRect, config: LivelineConfig, palette: LivelinePalette, now: TimeInterval) {
        drawSquiggly(in: ctx, chartRect: chartRect, palette: palette, now: now)

        let font = UIFont.systemFont(ofSize: 12, weight: .regular)
        let size = textSize(config.emptyText, font: font)
        // Background-colored gap behind the text, standing in for the
        // destination-out gradient the web version uses
        let gap = CGRect(
            x: chartRect.midX - size.width / 2 - 12,
            y: chartRect.midY - size.height / 2 - 6,
            width: size.width + 24,
            height: size.height + 12
        )
        ctx.setFillColor(palette.background.cgColor)
        ctx.fill(gap)
        drawText(
            config.emptyText,
            at: CGPoint(x: chartRect.midX - size.width / 2, y: chartRect.midY - size.height / 2),
            anchorX: 0,
            font: font,
            color: palette.gridLabel.withAlphaComponent(0.35)
        )
    }

    // MARK: - Text helpers

    private static func timeString(_ t: TimeInterval) -> String {
        let comps = Calendar.current.dateComponents(
            [.hour, .minute, .second],
            from: Date(timeIntervalSince1970: t)
        )
        return String(format: "%02d:%02d:%02d", comps.hour ?? 0, comps.minute ?? 0, comps.second ?? 0)
    }

    private static func textSize(_ string: String, font: UIFont) -> CGSize {
        (string as NSString).size(withAttributes: [.font: font])
    }

    @discardableResult
    private static func drawText(_ string: String, at point: CGPoint, anchorX: CGFloat, font: UIFont, color: UIColor) -> CGSize {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = (string as NSString).size(withAttributes: attributes)
        let origin = CGPoint(x: point.x - size.width * anchorX, y: point.y)
        (string as NSString).draw(at: origin, withAttributes: attributes)
        return size
    }
}
#endif
