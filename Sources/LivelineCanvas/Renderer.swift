import Foundation

#if canImport(UIKit)
import UIKit
import CoreGraphics

struct RenderState {
    var displayValue: Double = 0
    var displayMin: Double = 0
    var displayMax: Double = 1
    var initialized = false

    /// 0 = running, 1 = fully paused; lerps between them so the chart
    /// decelerates into a pause instead of stopping dead.
    var pauseProgress: Double = 0
    /// Seconds the chart clock lags wall clock. Accumulates while paused,
    /// drains after resume so the chart smoothly catches up
    /// (PAUSE_CATCHUP_SPEED semantics from useLivelineEngine.ts).
    var timeDebt: TimeInterval = 0

    /// Grid interval hysteresis + per-label alpha smoothing
    /// (key = value * 1000 rounded).
    var gridInterval: Double = 0
    var gridLabels: [Int: Double] = [:]

    var momentum: LivelineMomentum = .flat
    var arrowUp: Double = 0
    var arrowDown: Double = 0

    var badgeWidth: Double = 0
    var badgeY: Double = 0
    var badgeColor: (r: Double, g: Double, b: Double) = (0, 0, 0)
    var badgeColorInitialized = false

    var seriesAlphas: [String: Double] = [:]
    var seriesValues: [String: Double] = [:]

    /// 0 → 1 after loading flips off; drives the loading→data reveal morph.
    var chartReveal: Double = 1

    var particles: [DegenParticle] = []
    var particleCooldown: Double = 0
    var burstCount = 0
    var shakeAmplitude: Double = 0

    var liveCandleTime: TimeInterval = -1
    var liveCandleAlpha: Double = 0
    var liveCandleSmooth: (open: Double, high: Double, low: Double, close: Double)?
    var closeLineSmooth: Double?

    var obLabels: [OrderbookLabel] = []
    var obSpawnTimer: Double = 0
    var obSpeed: Double = 0
    var obPrevBidTotal: Double = 0
    var obPrevAskTotal: Double = 0
    var obChurnRate: Double = 0

    /// Candle↔line morph: 0 = candles, 1 = line (LINE_MORPH_MS = 500, cosine).
    var lineModeProg: Double = 0
    var lineMorphTarget: Double = 0
    var lineMorphFrom: Double = 0
    var lineMorphStart: TimeInterval = -1
}

struct RenderInput {
    let rect: CGRect
    let points: [LivelinePoint]
    let candles: [CandlePoint]
    let liveCandle: CandlePoint?
    let series: [LivelineSeries]
    let hiddenSeriesIDs: Set<String>
    let orderbook: LivelineOrderbook?
    let value: Double
    let config: LivelineConfig
    let palette: LivelinePalette
    let referenceLine: LivelineReferenceLine?
    let hoverX: CGFloat?
    let isPaused: Bool
    let isLoading: Bool
    let now: TimeInterval
    /// Effective visible window — differs from config.windowSeconds while a
    /// window-change transition is animating.
    let window: TimeInterval
    /// Candle mode: morph candles into a line display (React `lineMode`).
    let lineMode: Bool
    /// Tick-level data for line-mode density (React `lineData`).
    let lineData: [LivelinePoint]
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
            // Next data frame morphs out of this squiggly
            state.chartReveal = 0
            drawSquiggly(in: ctx, chartRect: chartRect, palette: palette, now: input.now)
            return
        }

        let isMulti = !input.series.isEmpty
        let hasData = isMulti
            ? input.series.contains { !$0.data.isEmpty }
            : !(input.points.isEmpty && input.candles.isEmpty)
        guard hasData else {
            drawEmpty(in: ctx, chartRect: chartRect, config: config, palette: palette, now: input.now)
            return
        }

        // --- Loading→data reveal (CHART_REVEAL_SPEED_FWD = 0.09) ---
        if state.chartReveal < 1 {
            state.chartReveal = lerp(state.chartReveal, 1, speed: 0.09, dt: dt)
            if state.chartReveal > 0.995 { state.chartReveal = 1 }
        }
        let reveal = state.chartReveal

        // --- Degen shake: random translate, exponential decay ---
        var shakeApplied = false
        if state.shakeAmplitude > 0.2, reveal > 0.9 {
            ctx.saveGState()
            ctx.translateBy(
                x: CGFloat(Double.random(in: -1...1) * state.shakeAmplitude),
                y: CGFloat(Double.random(in: -1...1) * state.shakeAmplitude)
            )
            shakeApplied = true
        }
        state.shakeAmplitude *= exp(-0.002 * dt * 1000)
        if state.shakeAmplitude < 0.2 { state.shakeAmplitude = 0 }
        defer { if shakeApplied { ctx.restoreGState() } }

        // --- Pause: decelerate into a frozen clock, catch up on resume ---
        state.pauseProgress = lerp(state.pauseProgress, input.isPaused ? 1 : 0, speed: 0.12, dt: dt)
        if state.pauseProgress > 0.001 {
            state.timeDebt += dt * state.pauseProgress
        }
        if !input.isPaused, state.timeDebt > 0 {
            let speed = state.timeDebt > 10 ? 0.22 : 0.08
            state.timeDebt = lerp(state.timeDebt, 0, speed: speed, dt: dt)
            if state.timeDebt < 0.01 { state.timeDebt = 0 }
        }
        let now = input.now - state.timeDebt
        let pausedDt = dt * (1 - state.pauseProgress)

        // --- Candle↔line morph progress (timed 500ms cosine ease) ---
        let lineTarget = input.lineMode ? 1.0 : 0.0
        if state.lineMorphTarget != lineTarget {
            state.lineMorphTarget = lineTarget
            state.lineMorphFrom = state.lineModeProg
            state.lineMorphStart = input.now
        }
        if state.lineModeProg != lineTarget {
            let progress = state.lineMorphStart < 0 ? 1 : clamp((input.now - state.lineMorphStart) / 0.5, 0, 1)
            let eased = 0.5 - 0.5 * cos(progress * .pi)
            state.lineModeProg = state.lineMorphFrom + (lineTarget - state.lineMorphFrom) * eased
        }
        let lineProg = config.mode == .candle ? state.lineModeProg : 0

        let window = Swift.max(input.window, 1)
        // Small time buffer past "now" keeps the live dot inside the chart;
        // wider when the badge needs room (WINDOW_BUFFER semantics).
        let showBadge = config.showBadge && config.mode == .line && !isMulti
        let buffer = showBadge ? 0.05 : 0.015
        let rightEdgeTime = now + window * buffer
        let leftTime = rightEdgeTime - window

        // --- Momentum ---
        let momentum: LivelineMomentum
        switch config.momentum {
        case .off:
            momentum = .flat
        case .fixed(let m):
            momentum = m
        case .auto:
            momentum = (isMulti || config.mode == .candle) ? .flat : detectMomentum(points: input.points)
        }
        state.momentum = momentum

        // --- Y range + display lerps ---
        let visiblePoints = isMulti ? [] : visibleSlice(input.points, leftTime: leftTime)
        let visibleCandles = input.candles.filter { $0.time >= leftTime - config.candleWidthSeconds }

        // Line the candles morph into: tick-level data when provided,
        // otherwise the candle closes
        let morphLinePoints: [LivelinePoint]
        if config.mode == .candle, lineProg > 0.001 {
            if !input.lineData.isEmpty {
                morphLinePoints = visibleSlice(input.lineData, leftTime: leftTime)
            } else {
                var closes = visibleCandles.map { LivelinePoint(time: $0.time + config.candleWidthSeconds / 2, value: $0.close) }
                if let live = input.liveCandle {
                    closes.append(LivelinePoint(time: live.time + config.candleWidthSeconds / 2, value: live.close))
                }
                morphLinePoints = closes
            }
        } else {
            morphLinePoints = []
        }

        let range: (min: Double, max: Double)
        if isMulti {
            var uMin = Double.infinity
            var uMax = -Double.infinity
            for s in input.series where !input.hiddenSeriesIDs.contains(s.id) && !s.data.isEmpty {
                let visible = visibleSlice(s.data, leftTime: leftTime)
                let r = valueRange(
                    points: visible,
                    candles: [],
                    currentValue: s.value,
                    reference: input.referenceLine,
                    exaggerate: config.exaggerate
                )
                uMin = Swift.min(uMin, r.min)
                uMax = Swift.max(uMax, r.max)
            }
            range = uMin.isFinite ? (uMin, uMax) : (0, 1)
        } else {
            let rangeCandles = input.liveCandle.map { visibleCandles + [$0] } ?? visibleCandles
            let baseRange = valueRange(
                points: config.mode == .line ? visiblePoints : [],
                candles: config.mode == .candle ? rangeCandles : [],
                currentValue: input.value,
                reference: input.referenceLine,
                exaggerate: config.exaggerate
            )
            if config.mode == .candle, lineProg > 0.001, !morphLinePoints.isEmpty {
                // Blend candle OHLC range into the line range during the morph
                let lineRange = valueRange(
                    points: morphLinePoints,
                    candles: [],
                    currentValue: input.value,
                    reference: input.referenceLine,
                    exaggerate: config.exaggerate
                )
                range = (
                    baseRange.min + (lineRange.min - baseRange.min) * lineProg,
                    baseRange.max + (lineRange.max - baseRange.max) * lineProg
                )
            } else {
                range = baseRange
            }
        }

        if !state.initialized {
            state.displayValue = input.value
            state.displayMin = range.min
            state.displayMax = range.max
            state.initialized = true
        } else {
            // Adaptive speed: small ticks track fast, big jumps glide
            // (ADAPTIVE_SPEED_BOOST = 0.2, VALUE_SNAP_THRESHOLD = 0.001)
            let span = state.displayMax - state.displayMin
            let gapRatio = span > 0 ? clamp(abs(input.value - state.displayValue) / span, 0, 1) : 0
            let adaptive = config.lerpSpeed + (1 - gapRatio) * 0.2
            state.displayValue = lerp(state.displayValue, input.value, speed: adaptive, dt: pausedDt)
            if span > 0, abs(input.value - state.displayValue) < span * 0.001, state.pauseProgress < 0.5 {
                state.displayValue = input.value
            }
            state.displayMin = lerp(state.displayMin, range.min, speed: config.lerpSpeed + 0.07, dt: pausedDt)
            state.displayMax = lerp(state.displayMax, range.max, speed: config.lerpSpeed + 0.07, dt: pausedDt)
        }
        let minValue = state.displayMin
        let maxValue = state.displayMax

        if config.showGrid {
            drawGrid(in: ctx, chartRect: chartRect, minValue: minValue, maxValue: maxValue, config: config, palette: palette, state: &state, dt: dt)
        }
        drawTimeAxis(in: ctx, chartRect: chartRect, rightEdgeTime: rightEdgeTime, window: window, palette: palette)

        if let reference = input.referenceLine {
            drawReferenceLine(in: ctx, chartRect: chartRect, minValue: minValue, maxValue: maxValue, value: reference.value, color: palette.reference)
        }

        if isMulti {
            drawMultiSeries(
                in: ctx, chartRect: chartRect, series: input.series, hidden: input.hiddenSeriesIDs,
                now: now, animNow: input.now, rightEdgeTime: rightEdgeTime, window: window,
                minValue: minValue, maxValue: maxValue, config: config, palette: palette,
                state: &state, dt: pausedDt
            )
        } else {
            switch config.mode {
            case .line:
                drawLine(in: ctx, chartRect: chartRect, points: visiblePoints, smoothValue: state.displayValue, tipTime: now, rightEdgeTime: rightEdgeTime, window: window, minValue: minValue, maxValue: maxValue, config: config, palette: palette, reveal: reveal, animNow: input.now)
                if !visiblePoints.isEmpty, reveal > 0.5 {
                    let tipX = xForTime(now, rightEdgeTime: rightEdgeTime, window: window, chartRect: chartRect)
                    let tipY = yForValue(state.displayValue, minValue: minValue, maxValue: maxValue, chartRect: chartRect)
                    let dot = CGPoint(x: tipX, y: clamp(tipY, rect.minY + 10, rect.maxY - 10))
                    if config.showDot {
                        let glow: UIColor? = config.momentum.isOff ? nil : glowColor(for: momentum, palette: palette)
                        drawDot(in: ctx, at: dot, palette: palette, pulse: config.pulse, glow: glow, now: input.now)
                    }
                    if !config.momentum.isOff {
                        drawArrows(in: ctx, at: dot, momentum: momentum, palette: palette, state: &state, dt: dt, now: input.now)
                    }
                    if showBadge {
                        drawBadge(in: ctx, rect: rect, chartRect: chartRect, value: state.displayValue, valueY: tipY, momentum: momentum, config: config, palette: palette, state: &state, dt: dt)
                    }
                    if let degen = config.degen {
                        let swing = swingMagnitude(points: visiblePoints, span: maxValue - minValue)
                        let intensity = spawnParticles(state: &state, momentum: momentum, dot: dot, swing: swing, dt: dt, options: degen)
                        if intensity > 0 {
                            state.shakeAmplitude = (3 + swing * 4) * intensity
                        }
                        drawParticles(in: ctx, state: &state, color: palette.line, dt: dt)
                    }
                }
            case .candle:
                if lineProg < 0.999 {
                    drawCandles(in: ctx, chartRect: chartRect, candles: visibleCandles, liveCandle: input.liveCandle, rightEdgeTime: rightEdgeTime, window: window, minValue: minValue, maxValue: maxValue, config: config, palette: palette, state: &state, dt: pausedDt, animNow: input.now, collapse: lineProg, alphaScale: 1 - lineProg)
                }
                if lineProg > 0.001, !morphLinePoints.isEmpty {
                    drawLine(in: ctx, chartRect: chartRect, points: morphLinePoints, smoothValue: state.displayValue, tipTime: now, rightEdgeTime: rightEdgeTime, window: window, minValue: minValue, maxValue: maxValue, config: config, palette: palette, reveal: reveal, animNow: input.now, alphaScale: lineProg)
                    if lineProg > 0.5, config.showDot, reveal > 0.5 {
                        let tipX = xForTime(now, rightEdgeTime: rightEdgeTime, window: window, chartRect: chartRect)
                        let tipY = yForValue(state.displayValue, minValue: minValue, maxValue: maxValue, chartRect: chartRect)
                        let dot = CGPoint(x: tipX, y: clamp(tipY, rect.minY + 10, rect.maxY - 10))
                        drawDot(in: ctx, at: dot, palette: palette, pulse: config.pulse, glow: nil, now: input.now)
                    }
                }
            }
        }

        // Left-edge fade so the line dissolves into the chart edge
        drawEdgeFade(in: ctx, chartRect: chartRect, background: palette.background)

        if let orderbook = input.orderbook {
            let swingPoints = isMulti ? (input.series.first?.data ?? []) : input.points
            let swing = swingMagnitude(points: swingPoints, span: maxValue - minValue)
            drawOrderbook(in: ctx, chartRect: chartRect, orderbook: orderbook, swing: swing, palette: palette, state: &state, dt: dt)
        }

        if let hoverX = input.hoverX, config.showCrosshair {
            if isMulti {
                drawMultiCrosshair(in: ctx, chartRect: chartRect, x: hoverX, series: input.series, hidden: input.hiddenSeriesIDs, rightEdgeTime: rightEdgeTime, window: window, minValue: minValue, maxValue: maxValue, config: config, palette: palette)
            } else {
                // In candle mode the value tooltip only makes sense once the
                // morph line carries the values
                let crosshairPoints: [LivelinePoint]
                if config.mode == .candle {
                    crosshairPoints = lineProg > 0.5 ? (input.lineData.isEmpty ? morphLinePoints : input.lineData) : []
                } else {
                    crosshairPoints = input.points
                }
                drawCrosshair(in: ctx, chartRect: chartRect, x: hoverX, points: crosshairPoints, rightEdgeTime: rightEdgeTime, window: window, minValue: minValue, maxValue: maxValue, config: config, palette: palette)
            }
        }

        if config.showValueLabel {
            var color = palette.text
            if config.valueMomentumColor {
                if momentum == .up { color = palette.upCandle }
                if momentum == .down { color = palette.downCandle }
            }
            drawText(
                config.formatValue(state.displayValue),
                at: CGPoint(x: rect.maxX - 12, y: rect.minY + 8),
                anchorX: 1,
                font: .monospacedDigitSystemFont(ofSize: 14, weight: .medium),
                color: color
            )
        }
    }

    // MARK: - Geometry

    /// Points inside the window plus one point just left of it, so the line
    /// enters from the chart edge instead of popping in.
    static func visibleSlice(_ points: [LivelinePoint], leftTime: TimeInterval) -> [LivelinePoint] {
        guard let firstVisible = points.firstIndex(where: { $0.time >= leftTime }) else {
            // Everything is older than the window — keep the newest point so
            // the live tip still has an anchor.
            return points.suffix(1).map { $0 }
        }
        let start = firstVisible > 0 ? firstVisible - 1 : 0
        return Array(points[start...])
    }

    static func xForTime(_ t: TimeInterval, rightEdgeTime: TimeInterval, window: TimeInterval, chartRect: CGRect) -> CGFloat {
        let ratio = CGFloat((t - (rightEdgeTime - window)) / window)
        return chartRect.minX + ratio * chartRect.width
    }

    static func yForValue(_ v: Double, minValue: Double, maxValue: Double, chartRect: CGRect) -> CGFloat {
        let span = maxValue - minValue
        guard span > 0 else { return chartRect.midY }
        let ratio = CGFloat((v - minValue) / span)
        return chartRect.maxY - ratio * chartRect.height
    }

    // MARK: - Grid + axes

    /// TradingView-style value grid with interval hysteresis and per-label
    /// fade in/out, ported from `src/draw/grid.ts`.
    static func drawGrid(in ctx: CGContext, chartRect: CGRect, minValue: Double, maxValue: Double, config: LivelineConfig, palette: LivelinePalette, state: inout RenderState, dt: Double) {
        let valRange = maxValue - minValue
        guard valRange > 0 else { return }
        let pxPerUnit = Double(chartRect.height) / valRange

        let coarse = pickGridInterval(valueRange: valRange, pxPerUnit: pxPerUnit, minGap: 36, previous: state.gridInterval)
        state.gridInterval = coarse
        let fine = coarse / 2
        let finePx = fine * pxPerUnit
        let fineTarget = finePx < 40 ? 0 : finePx >= 60 ? 1 : (finePx - 40) / 20

        let fadeZone = 32.0
        func edgeAlpha(_ y: CGFloat) -> Double {
            let fromEdge = Double(Swift.min(y - chartRect.minY, chartRect.maxY - y))
            if fromEdge >= fadeZone { return 1 }
            if fromEdge <= 0 { return 0 }
            return fromEdge / fadeZone
        }

        // Phase 1: target alpha for every label position currently in range
        var targets: [Int: Double] = [:]
        var val = (minValue / fine).rounded(.up) * fine
        var guardCount = 0
        while val <= maxValue, guardCount < 512 {
            guardCount += 1
            let y = yForValue(val, minValue: minValue, maxValue: maxValue, chartRect: chartRect)
            if y >= chartRect.minY - 2, y <= chartRect.maxY + 2 {
                let isCoarse = isDivisible(val, by: coarse)
                targets[Int((val * 1000).rounded())] = (isCoarse ? 1 : fineTarget) * edgeAlpha(y)
            }
            val += fine
        }

        // Phase 2: smooth all tracked label alphas (FADE_IN 0.18 / FADE_OUT 0.12)
        for (key, alpha) in state.gridLabels {
            let target = targets[key] ?? 0
            let speed = target >= alpha ? 0.18 : 0.12
            var next = lerp(alpha, target, speed: speed, dt: dt)
            if abs(next - target) < 0.02 { next = target }
            if next < 0.01, target == 0 {
                state.gridLabels.removeValue(forKey: key)
            } else {
                state.gridLabels[key] = next
            }
        }
        for (key, target) in targets where state.gridLabels[key] == nil {
            state.gridLabels[key] = target * 0.18
        }

        // Phase 3: draw
        let font = UIFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        for (key, alpha) in state.gridLabels {
            guard alpha >= 0.02 else { continue }
            let v = Double(key) / 1000
            let y = yForValue(v, minValue: minValue, maxValue: maxValue, chartRect: chartRect)
            guard y >= chartRect.minY - 10, y <= chartRect.maxY + 10 else { continue }

            ctx.saveGState()
            ctx.setStrokeColor(palette.grid.withAlphaComponent(CGFloat(alpha) * gridLineAlpha(palette)).cgColor)
            ctx.setLineWidth(1)
            ctx.setLineDash(phase: 0, lengths: [1, 3])
            ctx.move(to: CGPoint(x: chartRect.minX, y: y))
            ctx.addLine(to: CGPoint(x: chartRect.maxX, y: y))
            ctx.strokePath()
            ctx.restoreGState()

            drawText(
                config.formatValue(v),
                at: CGPoint(x: chartRect.maxX + 8, y: y - font.lineHeight / 2),
                anchorX: 0,
                font: font,
                color: palette.gridLabel.withAlphaComponent(CGFloat(alpha) * labelBaseAlpha(palette))
            )
        }
    }

    /// The palette's grid/label colors already carry their own alpha; scaling
    /// with the fade alpha needs the base value so fades multiply correctly.
    private static func gridLineAlpha(_ palette: LivelinePalette) -> CGFloat {
        var a: CGFloat = 1
        palette.grid.getRed(nil, green: nil, blue: nil, alpha: &a)
        return a
    }

    private static func labelBaseAlpha(_ palette: LivelinePalette) -> CGFloat {
        var a: CGFloat = 1
        palette.gridLabel.getRed(nil, green: nil, blue: nil, alpha: &a)
        return a
    }

    static func niceTimeInterval(_ windowSecs: TimeInterval) -> TimeInterval {
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

    static func drawTimeAxis(in ctx: CGContext, chartRect: CGRect, rightEdgeTime: TimeInterval, window: TimeInterval, palette: LivelinePalette) {
        ctx.saveGState()
        ctx.setStrokeColor(palette.grid.cgColor)
        ctx.setLineWidth(1)
        ctx.move(to: CGPoint(x: chartRect.minX, y: chartRect.maxY))
        ctx.addLine(to: CGPoint(x: chartRect.maxX, y: chartRect.maxY))
        ctx.strokePath()

        var interval = niceTimeInterval(window)
        while chartRect.width * CGFloat(interval / window) < 60 { interval *= 2 }

        let font = UIFont.monospacedDigitSystemFont(ofSize: 10, weight: .regular)
        var t = ((rightEdgeTime - window) / interval).rounded(.up) * interval
        ctx.setStrokeColor(palette.timeLabel.cgColor)
        while t <= rightEdgeTime {
            let x = xForTime(t, rightEdgeTime: rightEdgeTime, window: window, chartRect: chartRect)
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

    static func linePoints(_ points: [LivelinePoint], smoothValue: Double, tipTime: TimeInterval, rightEdgeTime: TimeInterval, window: TimeInterval, minValue: Double, maxValue: Double, chartRect: CGRect) -> [CGPoint] {
        guard !points.isEmpty else { return [] }
        let clampY: (CGFloat) -> CGFloat = { clamp($0, chartRect.minY, chartRect.maxY) }

        // Historical points keep their data values; the LAST data point takes
        // the interpolated value so big jumps animate instead of snapping,
        // then the live tip is appended at tipTime (src/draw/line.ts).
        var pts: [CGPoint] = []
        pts.reserveCapacity(points.count + 1)
        for (index, p) in points.enumerated() {
            let x = xForTime(p.time, rightEdgeTime: rightEdgeTime, window: window, chartRect: chartRect)
            let v = index == points.count - 1 ? smoothValue : p.value
            pts.append(CGPoint(x: x, y: clampY(yForValue(v, minValue: minValue, maxValue: maxValue, chartRect: chartRect))))
        }
        let tipX = xForTime(tipTime, rightEdgeTime: rightEdgeTime, window: window, chartRect: chartRect)
        pts.append(CGPoint(x: tipX, y: clampY(yForValue(smoothValue, minValue: minValue, maxValue: maxValue, chartRect: chartRect))))
        return pts
    }

    static func strokeSpline(_ ctx: CGContext, points: [CGPoint], color: UIColor, lineWidth: CGFloat) {
        guard points.count >= 2 else { return }
        let path = CGMutablePath()
        path.move(to: points[0])
        for segment in monotoneSplineSegments(points) {
            path.addCurve(to: segment.end, control1: segment.control1, control2: segment.control2)
        }
        ctx.setStrokeColor(color.cgColor)
        ctx.setLineWidth(lineWidth)
        ctx.setLineJoin(.round)
        ctx.setLineCap(.round)
        ctx.addPath(path)
        ctx.strokePath()
    }

    static func drawLine(in ctx: CGContext, chartRect: CGRect, points: [LivelinePoint], smoothValue: Double, tipTime: TimeInterval, rightEdgeTime: TimeInterval, window: TimeInterval, minValue: Double, maxValue: Double, config: LivelineConfig, palette: LivelinePalette, reveal: Double = 1, animNow: TimeInterval = 0, alphaScale: Double = 1) {
        var pts = linePoints(points, smoothValue: smoothValue, tipTime: tipTime, rightEdgeTime: rightEdgeTime, window: window, minValue: minValue, maxValue: maxValue, chartRect: chartRect)
        guard pts.count >= 2 else { return }

        let ms = animNow.truncatingRemainder(dividingBy: 86_400) * 1000
        var lineAlpha = alphaScale
        var fillAlpha = alphaScale
        var strokeColor = palette.line

        if reveal < 1 {
            // Morph out of the loading squiggly, center-out: the middle of
            // the chart resolves first, edges last (src/draw/line.ts)
            let centerY = Double(chartRect.midY)
            let amplitude = Double(chartRect.height) * 0.07
            let scroll = ms * 0.001
            for i in pts.indices {
                let t = clamp(Double((pts[i].x - chartRect.minX) / Swift.max(chartRect.width, 1)), 0, 1)
                let centerDist = abs(t - 0.5) * 2
                let localReveal = clamp((reveal - centerDist * 0.4) / 0.6, 0, 1)
                let baseY = loadingY(t: t, centerY: centerY, amplitude: amplitude, scroll: scroll)
                pts[i].y = CGFloat(baseY + (Double(pts[i].y) - baseY) * localReveal)
            }
            // Tip X extends to the full width at reveal=0, matching the squiggly
            let tip = pts[pts.count - 1]
            pts[pts.count - 1].x = tip.x + (chartRect.maxX - tip.x) * CGFloat(1 - reveal)

            // Line shares the loading breath at reveal=0, ramps to full;
            // color blends grey → accent by reveal ≈ 0.3
            let breath = 0.22 + 0.08 * sin(ms / 1200 * .pi)
            lineAlpha = (breath + (1 - breath) * reveal) * alphaScale
            fillAlpha = reveal * alphaScale
            strokeColor = blendColor(palette.gridLabel, palette.line, t: Swift.min(1, reveal * 3))
        }

        ctx.saveGState()
        ctx.clip(to: chartRect.insetBy(dx: -1, dy: 0))

        if config.showFill, fillAlpha > 0.01 {
            let fillPath = CGMutablePath()
            fillPath.move(to: pts[0])
            for segment in monotoneSplineSegments(pts) {
                fillPath.addCurve(to: segment.end, control1: segment.control1, control2: segment.control2)
            }
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
            let components: [CGFloat] = [
                r1, g1, b1, a1 * CGFloat(fillAlpha),
                r2, g2, b2, a2 * CGFloat(fillAlpha)
            ]
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

        strokeSpline(ctx, points: pts, color: scaledAlpha(strokeColor, lineAlpha), lineWidth: CGFloat(config.lineWidth))
        ctx.restoreGState()

        if config.showDashLine {
            let realY = clamp(
                yForValue(smoothValue, minValue: minValue, maxValue: maxValue, chartRect: chartRect),
                chartRect.minY, chartRect.maxY
            )
            // During reveal the dash line unfolds from the vertical center
            let y = reveal < 1 ? chartRect.midY + (realY - chartRect.midY) * CGFloat(reveal) : realY
            ctx.saveGState()
            ctx.setStrokeColor(scaledAlpha(palette.dashLine, reveal * alphaScale).cgColor)
            ctx.setLineWidth(1)
            ctx.setLineDash(phase: 0, lengths: [4, 4])
            ctx.move(to: CGPoint(x: chartRect.minX, y: y))
            ctx.addLine(to: CGPoint(x: chartRect.maxX, y: y))
            ctx.strokePath()
            ctx.restoreGState()
        }
    }

    /// Fade the line/fill into the left chart edge over 40px — stands in for
    /// the destination-out gradient the web version uses (FADE_EDGE_WIDTH).
    static func drawEdgeFade(in ctx: CGContext, chartRect: CGRect, background: UIColor) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        _ = background.getRed(&r, green: &g, blue: &b, alpha: &a)
        let components: [CGFloat] = [r, g, b, 1, r, g, b, 0]
        guard let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colorComponents: components, locations: [0, 1], count: 2) else { return }
        ctx.saveGState()
        ctx.clip(to: CGRect(x: chartRect.minX, y: chartRect.minY, width: 40, height: chartRect.height))
        ctx.drawLinearGradient(
            gradient,
            start: CGPoint(x: chartRect.minX, y: 0),
            end: CGPoint(x: chartRect.minX + 40, y: 0),
            options: []
        )
        ctx.restoreGState()
    }

    // MARK: - Color helpers

    static func blendColor(_ a: UIColor, _ b: UIColor, t: Double) -> UIColor {
        let tt = CGFloat(clamp(t, 0, 1))
        var r1: CGFloat = 0, g1: CGFloat = 0, b1: CGFloat = 0, a1: CGFloat = 0
        var r2: CGFloat = 0, g2: CGFloat = 0, b2: CGFloat = 0, a2: CGFloat = 0
        _ = a.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        _ = b.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(
            red: r1 + (r2 - r1) * tt,
            green: g1 + (g2 - g1) * tt,
            blue: b1 + (b2 - b1) * tt,
            alpha: a1 + (a2 - a1) * tt
        )
    }

    /// Multiply a color's existing alpha by `factor` (withAlphaComponent
    /// would replace it and lose palette alphas like gridLabel's 0.4).
    static func scaledAlpha(_ color: UIColor, _ factor: Double) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        _ = color.getRed(&r, green: &g, blue: &b, alpha: &a)
        return UIColor(red: r, green: g, blue: b, alpha: a * CGFloat(clamp(factor, 0, 1)))
    }

    static func glowColor(for momentum: LivelineMomentum, palette: LivelinePalette) -> UIColor {
        switch momentum {
        case .up: return palette.upCandle.withAlphaComponent(0.5)
        case .down: return palette.downCandle.withAlphaComponent(0.5)
        case .flat: return palette.line.withAlphaComponent(0.35)
        }
    }

    /// Live dot: expanding accent pulse ring (1.5s interval, 0.9s duration),
    /// outer circle with shadow, colored inner dot — port of src/draw/dot.ts.
    /// `glow` adds a momentum-colored halo behind the dot.
    static func drawDot(in ctx: CGContext, at point: CGPoint, palette: LivelinePalette, pulse: Bool, glow: UIColor?, now: TimeInterval) {
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
        if let glow {
            ctx.setShadow(offset: .zero, blur: 14, color: glow.cgColor)
        } else {
            ctx.setShadow(offset: CGSize(width: 0, height: 1), blur: 6, color: UIColor.black.withAlphaComponent(0.4).cgColor)
        }
        ctx.setFillColor(palette.dotOuter.cgColor)
        ctx.fillEllipse(in: CGRect(x: point.x - 6.5, y: point.y - 6.5, width: 13, height: 13))
        ctx.restoreGState()

        ctx.setFillColor(palette.line.cgColor)
        ctx.fillEllipse(in: CGRect(x: point.x - 3.5, y: point.y - 3.5, width: 7, height: 7))
    }

    // MARK: - Candle mode

    static func drawCandles(in ctx: CGContext, chartRect: CGRect, candles: [CandlePoint], liveCandle: CandlePoint?, rightEdgeTime: TimeInterval, window: TimeInterval, minValue: Double, maxValue: Double, config: LivelineConfig, palette: LivelinePalette, state: inout RenderState, dt: Double, animNow: TimeInterval, collapse: Double = 0, alphaScale: Double = 1) {
        guard !candles.isEmpty || liveCandle != nil else { return }
        let pxPerSecond = chartRect.width / CGFloat(window)
        let bodyWidth = Swift.max(1, pxPerSecond * CGFloat(config.candleWidthSeconds) * 0.7)
        let wickWidth = clamp(bodyWidth * 0.15, 0.8, 2)

        // During the line morph, OHLC collapses toward the close price
        func collapsed(_ c: CandlePoint) -> CandlePoint {
            guard collapse > 0 else { return c }
            let k = 1 - collapse
            return CandlePoint(
                time: c.time,
                open: c.close + (c.open - c.close) * k,
                high: c.close + (c.high - c.close) * k,
                low: c.close + (c.low - c.close) * k,
                close: c.close
            )
        }

        func drawCandle(_ c: CandlePoint, at time: TimeInterval, alpha: Double) {
            let x = xForTime(time + config.candleWidthSeconds / 2, rightEdgeTime: rightEdgeTime, window: window, chartRect: chartRect)
            let yOpen = yForValue(c.open, minValue: minValue, maxValue: maxValue, chartRect: chartRect)
            let yClose = yForValue(c.close, minValue: minValue, maxValue: maxValue, chartRect: chartRect)
            let yHigh = yForValue(c.high, minValue: minValue, maxValue: maxValue, chartRect: chartRect)
            let yLow = yForValue(c.low, minValue: minValue, maxValue: maxValue, chartRect: chartRect)

            let isUp = c.close >= c.open
            let color = (isUp ? palette.upCandle : palette.downCandle).withAlphaComponent(CGFloat(alpha))

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

        ctx.saveGState()
        ctx.clip(to: chartRect.insetBy(dx: -1, dy: 0))
        // Candle time is the bucket's open time — bodies are centered on it
        for c in candles {
            drawCandle(collapsed(c), at: c.time, alpha: alphaScale)
        }

        // Live candle: birth fade-in, lerped OHLC, pulsing glow
        var closeSource: CandlePoint? = candles.last
        if let live = liveCandle {
            if state.liveCandleTime != live.time {
                state.liveCandleTime = live.time
                state.liveCandleAlpha = 0
                state.liveCandleSmooth = (live.open, live.high, live.low, live.close)
            }
            state.liveCandleAlpha = lerp(state.liveCandleAlpha, 1, speed: 0.12, dt: dt)
            var smooth = state.liveCandleSmooth ?? (live.open, live.high, live.low, live.close)
            smooth.open = lerp(smooth.open, live.open, speed: 0.25, dt: dt)
            smooth.high = lerp(smooth.high, live.high, speed: 0.25, dt: dt)
            smooth.low = lerp(smooth.low, live.low, speed: 0.25, dt: dt)
            smooth.close = lerp(smooth.close, live.close, speed: 0.25, dt: dt)
            state.liveCandleSmooth = smooth

            let display = CandlePoint(time: live.time, open: smooth.open, high: smooth.high, low: smooth.low, close: smooth.close)
            let ms = animNow.truncatingRemainder(dividingBy: 86_400) * 1000
            let glowAlpha = (0.12 + sin(ms * 0.004) * 0.08) * alphaScale
            let glowBase = display.close >= display.open ? palette.upCandle : palette.downCandle

            ctx.saveGState()
            ctx.setShadow(offset: .zero, blur: 8, color: glowBase.withAlphaComponent(CGFloat(Swift.max(0, glowAlpha))).cgColor)
            drawCandle(collapsed(display), at: live.time, alpha: state.liveCandleAlpha * alphaScale)
            ctx.restoreGState()

            closeSource = display
        }
        ctx.restoreGState()

        // Dashed close-price line, smoothed so it never jumps on candle birth
        if config.showDashLine, let source = closeSource {
            let smoothClose = lerp(state.closeLineSmooth ?? source.close, source.close, speed: 0.25, dt: dt)
            state.closeLineSmooth = smoothClose
            let y = clamp(
                yForValue(smoothClose, minValue: minValue, maxValue: maxValue, chartRect: chartRect),
                chartRect.minY, chartRect.maxY
            )
            let color = source.close >= source.open ? palette.upCandle : palette.downCandle
            ctx.saveGState()
            ctx.setStrokeColor(color.withAlphaComponent(CGFloat(0.4 * alphaScale)).cgColor)
            ctx.setLineWidth(1)
            ctx.setLineDash(phase: 0, lengths: [4, 4])
            ctx.move(to: CGPoint(x: chartRect.minX, y: y))
            ctx.addLine(to: CGPoint(x: chartRect.maxX, y: y))
            ctx.strokePath()
            ctx.restoreGState()
        }
    }

    // MARK: - Overlays

    static func drawCrosshair(in ctx: CGContext, chartRect: CGRect, x: CGFloat, points: [LivelinePoint], rightEdgeTime: TimeInterval, window: TimeInterval, minValue: Double, maxValue: Double, config: LivelineConfig, palette: LivelinePalette) {
        let clampedX = clamp(x, chartRect.minX, chartRect.maxX)

        ctx.saveGState()
        ctx.setStrokeColor(palette.crosshair.cgColor)
        ctx.setLineWidth(1)
        ctx.move(to: CGPoint(x: clampedX, y: chartRect.minY))
        ctx.addLine(to: CGPoint(x: clampedX, y: chartRect.maxY))
        ctx.strokePath()
        ctx.restoreGState()

        guard !points.isEmpty else { return }
        let hoverTime = (rightEdgeTime - window) + TimeInterval((clampedX - chartRect.minX) / Swift.max(chartRect.width, 1)) * window
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

    static func drawReferenceLine(in ctx: CGContext, chartRect: CGRect, minValue: Double, maxValue: Double, value: Double, color: UIColor) {
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

    /// Squiggly Y position shared by the loading line and the reveal morph —
    /// same shape constants as src/draw/loadingShape.ts.
    static func loadingY(t: Double, centerY: Double, amplitude: Double, scroll: Double) -> Double {
        centerY + amplitude * (
            sin(t * 9.4 + scroll) * 0.55 +
            sin(t * 15.7 + scroll * 1.3) * 0.3 +
            sin(t * 4.2 + scroll * 0.7) * 0.15
        )
    }

    /// Breathing squiggly loading line.
    static func drawSquiggly(in ctx: CGContext, chartRect: CGRect, palette: LivelinePalette, now: TimeInterval, alphaScale: Double = 1) {
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
            let y = loadingY(t: t, centerY: centerY, amplitude: amplitude, scroll: scroll)
            pts.append(CGPoint(x: chartRect.minX + CGFloat(t) * chartRect.width, y: CGFloat(y)))
        }

        strokeSpline(ctx, points: pts, color: palette.gridLabel.withAlphaComponent(CGFloat(breath * alphaScale)), lineWidth: 2)
    }

    static func drawEmpty(in ctx: CGContext, chartRect: CGRect, config: LivelineConfig, palette: LivelinePalette, now: TimeInterval) {
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

    static func timeString(_ t: TimeInterval) -> String {
        let comps = Calendar.current.dateComponents(
            [.hour, .minute, .second],
            from: Date(timeIntervalSince1970: t)
        )
        return String(format: "%02d:%02d:%02d", comps.hour ?? 0, comps.minute ?? 0, comps.second ?? 0)
    }

    static func textSize(_ string: String, font: UIFont) -> CGSize {
        (string as NSString).size(withAttributes: [.font: font])
    }

    @discardableResult
    static func drawText(_ string: String, at point: CGPoint, anchorX: CGFloat, font: UIFont, color: UIColor) -> CGSize {
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = (string as NSString).size(withAttributes: attributes)
        let origin = CGPoint(x: point.x - size.width * anchorX, y: point.y)
        (string as NSString).draw(at: origin, withAttributes: attributes)
        return size
    }
}
#endif
