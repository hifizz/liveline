import Foundation

#if canImport(UIKit)
import UIKit
import CoreGraphics

struct RenderState {
    var displayValue: Double = 0
    var displayMin: Double = 0
    var displayMax: Double = 1
    var initialized = false
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
        ctx.setFillColor(input.palette.background.cgColor)
        ctx.fill(rect)

        guard !input.isLoading else {
            drawLoading(in: ctx, rect: rect, palette: input.palette, t: input.now)
            return
        }

        let chartRect = rect.inset(by: UIEdgeInsets(
            top: CGFloat(input.config.insets.top),
            left: CGFloat(input.config.insets.left),
            bottom: CGFloat(input.config.insets.bottom),
            right: CGFloat(input.config.insets.right)
        ))

        if input.config.showGrid {
            drawGrid(in: ctx, rect: chartRect, color: input.palette.grid)
        }

        let range = valueRange(points: input.points, candles: input.candles, reference: input.referenceLine)
        if !state.initialized {
            state.displayValue = input.value
            state.displayMin = range.min
            state.displayMax = range.max
            state.initialized = true
        } else if !input.isPaused {
            state.displayValue = lerp(state.displayValue, input.value, speed: input.config.lerpSpeed, dt: dt)
            state.displayMin = lerp(state.displayMin, range.min, speed: input.config.lerpSpeed, dt: dt)
            state.displayMax = lerp(state.displayMax, range.max, speed: input.config.lerpSpeed, dt: dt)
        }

        if let reference = input.referenceLine {
            drawReferenceLine(in: ctx, chartRect: chartRect, min: state.displayMin, max: state.displayMax, value: reference.value, color: input.palette.reference)
        }

        let visiblePoints = input.points.filter { input.now - $0.time <= input.config.windowSeconds }
        let visibleCandles = input.candles.filter { input.now - $0.time <= input.config.windowSeconds }

        switch input.config.mode {
        case .line:
            drawLine(in: ctx, chartRect: chartRect, points: visiblePoints, min: state.displayMin, max: state.displayMax, color: input.palette.line, fill: input.config.showFill ? input.palette.fill : nil)
        case .candle:
            drawCandles(in: ctx, chartRect: chartRect, candles: visibleCandles, min: state.displayMin, max: state.displayMax, palette: input.palette, window: input.config.windowSeconds)
        }

        if let hoverX = input.hoverX, input.config.showCrosshair {
            drawCrosshair(in: ctx, chartRect: chartRect, x: hoverX, color: input.palette.crosshair)
        }

        if input.config.showValueLabel {
            drawValueLabel(in: ctx, rect: rect, value: state.displayValue, color: input.palette.text)
        }
    }

    private static func xForTime(_ t: TimeInterval, rightEdge: TimeInterval, window: TimeInterval, chartRect: CGRect) -> CGFloat {
        let ratio = CGFloat((t - (rightEdge - window)) / window)
        return chartRect.minX + ratio * chartRect.width
    }

    private static func yForValue(_ v: Double, min: Double, max: Double, chartRect: CGRect) -> CGFloat {
        let ratio = CGFloat((v - min) / (max - min))
        return chartRect.maxY - ratio * chartRect.height
    }

    private static func drawGrid(in ctx: CGContext, rect: CGRect, color: UIColor) {
        ctx.saveGState()
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(1)
        let rows = 4
        let cols = 4
        for i in 0...rows {
            let y = rect.minY + (CGFloat(i) / CGFloat(rows)) * rect.height
            ctx.move(to: CGPoint(x: rect.minX, y: y))
            ctx.addLine(to: CGPoint(x: rect.maxX, y: y))
        }
        for i in 0...cols {
            let x = rect.minX + (CGFloat(i) / CGFloat(cols)) * rect.width
            ctx.move(to: CGPoint(x: x, y: rect.minY))
            ctx.addLine(to: CGPoint(x: x, y: rect.maxY))
        }
        ctx.strokePath()
        ctx.restoreGState()
    }

    private static func drawLine(in ctx: CGContext, chartRect: CGRect, points: [LivelinePoint], min: Double, max: Double, color: UIColor, fill: UIColor?) {
        guard points.count >= 2, let last = points.last else { return }
        let rightEdge = last.time
        let window = points.last!.time - points.first!.time
        let effectiveWindow = max(window, 1)

        let path = UIBezierPath()
        for (index, p) in points.enumerated() {
            let x = xForTime(p.time, rightEdge: rightEdge, window: effectiveWindow, chartRect: chartRect)
            let y = yForValue(p.value, min: min, max: max, chartRect: chartRect)
            if index == 0 { path.move(to: CGPoint(x: x, y: y)) } else { path.addLine(to: CGPoint(x: x, y: y)) }
        }

        if let fill {
            let fillPath = path.copy() as! UIBezierPath
            fillPath.addLine(to: CGPoint(x: chartRect.maxX, y: chartRect.maxY))
            fillPath.addLine(to: CGPoint(x: chartRect.minX, y: chartRect.maxY))
            fillPath.close()
            ctx.setFillColor(fill.cgColor)
            ctx.addPath(fillPath.cgPath)
            ctx.fillPath()
        }

        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(2)
        ctx.addPath(path.cgPath)
        ctx.strokePath()
    }

    private static func drawCandles(in ctx: CGContext, chartRect: CGRect, candles: [CandlePoint], min: Double, max: Double, palette: LivelinePalette, window: TimeInterval) {
        guard candles.count > 0, let last = candles.last else { return }
        let rightEdge = last.time
        let candleWidth = max(3, chartRect.width / CGFloat(max(candles.count, 1)) * 0.7)

        for c in candles {
            let x = xForTime(c.time, rightEdge: rightEdge, window: window, chartRect: chartRect)
            let yOpen = yForValue(c.open, min: min, max: max, chartRect: chartRect)
            let yClose = yForValue(c.close, min: min, max: max, chartRect: chartRect)
            let yHigh = yForValue(c.high, min: min, max: max, chartRect: chartRect)
            let yLow = yForValue(c.low, min: min, max: max, chartRect: chartRect)

            let isUp = c.close >= c.open
            let color = isUp ? palette.upCandle : palette.downCandle

            ctx.setStrokeColor(color.cgColor)
            ctx.setLineWidth(1)
            ctx.move(to: CGPoint(x: x, y: yHigh))
            ctx.addLine(to: CGPoint(x: x, y: yLow))
            ctx.strokePath()

            let bodyTop = min(yOpen, yClose)
            let bodyBottom = max(yOpen, yClose)
            let bodyRect = CGRect(x: x - candleWidth / 2, y: bodyTop, width: candleWidth, height: max(1, bodyBottom - bodyTop))
            ctx.setFillColor(color.cgColor)
            ctx.fill(bodyRect)
        }
    }

    private static func drawCrosshair(in ctx: CGContext, chartRect: CGRect, x: CGFloat, color: UIColor) {
        let clampedX = clamp(x, chartRect.minX, chartRect.maxX)
        ctx.saveGState()
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(1)
        ctx.move(to: CGPoint(x: clampedX, y: chartRect.minY))
        ctx.addLine(to: CGPoint(x: clampedX, y: chartRect.maxY))
        ctx.strokePath()
        ctx.restoreGState()
    }

    private static func drawReferenceLine(in ctx: CGContext, chartRect: CGRect, min: Double, max: Double, value: Double, color: UIColor) {
        let y = yForValue(value, min: min, max: max, chartRect: chartRect)
        ctx.saveGState()
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineDash(phase: 0, lengths: [4, 4])
        ctx.move(to: CGPoint(x: chartRect.minX, y: y))
        ctx.addLine(to: CGPoint(x: chartRect.maxX, y: y))
        ctx.strokePath()
        ctx.restoreGState()
    }

    private static func drawValueLabel(in ctx: CGContext, rect: CGRect, value: Double, color: UIColor) {
        let text = String(format: "%.2f", value)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: color
        ]
        let attr = NSAttributedString(string: text, attributes: attrs)
        let size = attr.size()
        let textRect = CGRect(x: rect.maxX - size.width - 12, y: 8, width: size.width, height: size.height)
        attr.draw(in: textRect)
    }

    private static func drawLoading(in ctx: CGContext, rect: CGRect, palette: LivelinePalette, t: TimeInterval) {
        let shimmerWidth = rect.width * 0.25
        let x = ((CGFloat(t).truncatingRemainder(dividingBy: 1.5) / 1.5) * (rect.width + shimmerWidth)) - shimmerWidth
        let base = UIColor(white: 1, alpha: 0.08)
        let pulse = UIColor(white: 1, alpha: 0.14)

        ctx.setFillColor(base.cgColor)
        ctx.fill(rect)
        ctx.setFillColor(pulse.cgColor)
        ctx.fill(CGRect(x: x, y: 0, width: shimmerWidth, height: rect.height))

        drawValueLabel(in: ctx, rect: rect, value: 0, color: palette.text.withAlphaComponent(0.5))
    }
}
#endif
