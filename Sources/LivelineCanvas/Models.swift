import Foundation

public struct LivelinePoint: Sendable, Equatable {
    public let time: TimeInterval
    public let value: Double

    public init(time: TimeInterval, value: Double) {
        self.time = time
        self.value = value
    }
}

public struct CandlePoint: Sendable, Equatable {
    public let time: TimeInterval
    public let open: Double
    public let high: Double
    public let low: Double
    public let close: Double

    public init(time: TimeInterval, open: Double, high: Double, low: Double, close: Double) {
        self.time = time
        self.open = open
        self.high = high
        self.low = low
        self.close = close
    }
}

public enum LivelineMode: Sendable {
    case line
    case candle
}

public struct LivelineReferenceLine: Sendable, Equatable {
    public let value: Double

    public init(value: Double) {
        self.value = value
    }
}

public struct LivelineInsets: Sendable, Equatable {
    public var top: Double
    public var left: Double
    public var bottom: Double
    public var right: Double

    /// Defaults match the React component's padding: top 12, left 12,
    /// bottom 28 (time axis room), right 54 (grid label room).
    public init(top: Double = 12, left: Double = 12, bottom: Double = 28, right: Double = 54) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }
}

public struct LivelineConfig: Sendable {
    public var mode: LivelineMode
    public var windowSeconds: TimeInterval
    /// Fraction of the remaining distance covered per 60fps frame,
    /// same semantics and default as the React `lerpSpeed` prop.
    public var lerpSpeed: Double
    public var showGrid: Bool
    public var showFill: Bool
    public var showCrosshair: Bool
    public var showValueLabel: Bool
    /// Dashed horizontal line at the current value.
    public var showDashLine: Bool
    /// Live dot at the chart tip.
    public var showDot: Bool
    /// Expanding pulse ring on the live dot.
    public var pulse: Bool
    /// Tight Y-range so small moves fill the chart height.
    public var exaggerate: Bool
    public var lineWidth: Double
    public var candleWidthSeconds: TimeInterval
    public var insets: LivelineInsets
    /// Vertical offset for the crosshair tooltip text.
    public var tooltipY: Double
    public var emptyText: String
    public var formatValue: @Sendable (Double) -> String

    public init(
        mode: LivelineMode = .line,
        windowSeconds: TimeInterval = 300,
        lerpSpeed: Double = 0.08,
        showGrid: Bool = true,
        showFill: Bool = true,
        showCrosshair: Bool = true,
        showValueLabel: Bool = true,
        showDashLine: Bool = true,
        showDot: Bool = true,
        pulse: Bool = true,
        exaggerate: Bool = false,
        lineWidth: Double = 2,
        candleWidthSeconds: TimeInterval = 60,
        insets: LivelineInsets = LivelineInsets(),
        tooltipY: Double = 14,
        emptyText: String = "No data to display",
        formatValue: @escaping @Sendable (Double) -> String = { String(format: "%.2f", $0) }
    ) {
        self.mode = mode
        self.windowSeconds = windowSeconds
        self.lerpSpeed = lerpSpeed
        self.showGrid = showGrid
        self.showFill = showFill
        self.showCrosshair = showCrosshair
        self.showValueLabel = showValueLabel
        self.showDashLine = showDashLine
        self.showDot = showDot
        self.pulse = pulse
        self.exaggerate = exaggerate
        self.lineWidth = lineWidth
        self.candleWidthSeconds = candleWidthSeconds
        self.insets = insets
        self.tooltipY = tooltipY
        self.emptyText = emptyText
        self.formatValue = formatValue
    }
}
