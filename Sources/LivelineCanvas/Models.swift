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
    /// bottom 28 (time axis room), right 80 (badge room; use 54 when the
    /// badge is off, 12 when the grid is off too).
    public init(top: Double = 12, left: Double = 12, bottom: Double = 28, right: Double = 80) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }
}

/// Burst particles + chart shake on momentum swings (React `degen` prop).
public struct LivelineDegenOptions: Sendable, Equatable {
    /// Particle count/size multiplier.
    public var scale: Double
    /// Also fire on downward swings (off by default, like the web).
    public var downMomentum: Bool

    public init(scale: Double = 1, downMomentum: Bool = false) {
        self.scale = scale
        self.downMomentum = downMomentum
    }
}

public struct LivelineOrderbookLevel: Sendable, Equatable {
    public let price: Double
    public let size: Double

    public init(price: Double, size: Double) {
        self.price = price
        self.size = size
    }
}

/// Bid/ask depth stream for the rising orderbook labels.
public struct LivelineOrderbook: Sendable, Equatable {
    public var bids: [LivelineOrderbookLevel]
    public var asks: [LivelineOrderbookLevel]

    public init(bids: [LivelineOrderbookLevel], asks: [LivelineOrderbookLevel]) {
        self.bids = bids
        self.asks = asks
    }
}

/// One time-horizon button for `LivelineWindowBar`.
public struct LivelineWindowOption: Sendable, Equatable, Identifiable {
    public let label: String
    public let seconds: TimeInterval

    public var id: TimeInterval { seconds }

    public init(label: String, seconds: TimeInterval) {
        self.label = label
        self.seconds = seconds
    }
}

public enum LivelineBadgeVariant: Sendable {
    /// Accent/momentum-colored pill with white text.
    case `default`
    /// Neutral background pill with theme text color.
    case minimal
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
    /// Large live value in the top-right corner (React `showValue`).
    public var showValueLabel: Bool
    /// Color the value label green/red by momentum.
    public var valueMomentumColor: Bool
    /// Dashed horizontal line at the current value.
    public var showDashLine: Bool
    /// Live dot at the chart tip.
    public var showDot: Bool
    /// Expanding pulse ring on the live dot.
    public var pulse: Bool
    /// Value pill tracking the chart tip (line mode, single series only).
    public var showBadge: Bool
    public var badgeVariant: LivelineBadgeVariant
    /// Pointed tail on the badge pill.
    public var badgeTail: Bool
    /// Momentum styling: dot glow, chevron arrows, badge color.
    public var momentum: LivelineMomentumMode
    /// Burst particles + chart shake on momentum swings.
    public var degen: LivelineDegenOptions?
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
        showValueLabel: Bool = false,
        valueMomentumColor: Bool = false,
        showDashLine: Bool = true,
        showDot: Bool = true,
        pulse: Bool = true,
        showBadge: Bool = true,
        badgeVariant: LivelineBadgeVariant = .default,
        badgeTail: Bool = true,
        momentum: LivelineMomentumMode = .auto,
        degen: LivelineDegenOptions? = nil,
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
        self.valueMomentumColor = valueMomentumColor
        self.showDashLine = showDashLine
        self.showDot = showDot
        self.pulse = pulse
        self.showBadge = showBadge
        self.badgeVariant = badgeVariant
        self.badgeTail = badgeTail
        self.momentum = momentum
        self.degen = degen
        self.exaggerate = exaggerate
        self.lineWidth = lineWidth
        self.candleWidthSeconds = candleWidthSeconds
        self.insets = insets
        self.tooltipY = tooltipY
        self.emptyText = emptyText
        self.formatValue = formatValue
    }
}
