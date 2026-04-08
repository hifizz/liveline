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

    public init(top: Double = 12, left: Double = 12, bottom: Double = 12, right: Double = 12) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }
}

public struct LivelineConfig: Sendable {
    public var mode: LivelineMode
    public var windowSeconds: TimeInterval
    public var lerpSpeed: Double
    public var showGrid: Bool
    public var showFill: Bool
    public var showCrosshair: Bool
    public var showValueLabel: Bool
    public var candleWidthSeconds: TimeInterval
    public var insets: LivelineInsets

    public init(
        mode: LivelineMode = .line,
        windowSeconds: TimeInterval = 300,
        lerpSpeed: Double = 0.18,
        showGrid: Bool = true,
        showFill: Bool = true,
        showCrosshair: Bool = true,
        showValueLabel: Bool = true,
        candleWidthSeconds: TimeInterval = 60,
        insets: LivelineInsets = LivelineInsets()
    ) {
        self.mode = mode
        self.windowSeconds = windowSeconds
        self.lerpSpeed = lerpSpeed
        self.showGrid = showGrid
        self.showFill = showFill
        self.showCrosshair = showCrosshair
        self.showValueLabel = showValueLabel
        self.candleWidthSeconds = candleWidthSeconds
        self.insets = insets
    }
}
