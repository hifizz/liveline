import Foundation

#if canImport(UIKit)
import UIKit

public enum LivelineTheme: Sendable {
    case dark
    case light
}

public struct LivelinePalette: Sendable {
    public var background: UIColor
    public var line: UIColor
    /// Top of the gradient fill under the curve.
    public var fillTop: UIColor
    /// Bottom of the gradient fill (normally transparent).
    public var fillBottom: UIColor
    public var grid: UIColor
    public var gridLabel: UIColor
    public var timeLabel: UIColor
    /// Dashed current-value line.
    public var dashLine: UIColor
    public var upCandle: UIColor
    public var downCandle: UIColor
    public var text: UIColor
    public var crosshair: UIColor
    public var reference: UIColor
    /// Outer circle of the live dot.
    public var dotOuter: UIColor

    public init(
        background: UIColor = UIColor(red: 10 / 255, green: 10 / 255, blue: 10 / 255, alpha: 1),
        line: UIColor = UIColor(red: 0.23, green: 0.51, blue: 0.96, alpha: 1),
        fillTop: UIColor = UIColor(red: 0.23, green: 0.51, blue: 0.96, alpha: 0.12),
        fillBottom: UIColor = UIColor(red: 0.23, green: 0.51, blue: 0.96, alpha: 0),
        grid: UIColor = UIColor(white: 1, alpha: 0.06),
        gridLabel: UIColor = UIColor(white: 1, alpha: 0.4),
        timeLabel: UIColor = UIColor(white: 1, alpha: 0.35),
        dashLine: UIColor = UIColor(red: 0.23, green: 0.51, blue: 0.96, alpha: 0.4),
        upCandle: UIColor = UIColor(red: 0.13, green: 0.77, blue: 0.37, alpha: 1),
        downCandle: UIColor = UIColor(red: 0.94, green: 0.27, blue: 0.27, alpha: 1),
        text: UIColor = UIColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1),
        crosshair: UIColor = UIColor(white: 1, alpha: 0.2),
        reference: UIColor = UIColor(white: 1, alpha: 0.15),
        dotOuter: UIColor = UIColor(red: 40 / 255, green: 40 / 255, blue: 40 / 255, alpha: 0.95)
    ) {
        self.background = background
        self.line = line
        self.fillTop = fillTop
        self.fillBottom = fillBottom
        self.grid = grid
        self.gridLabel = gridLabel
        self.timeLabel = timeLabel
        self.dashLine = dashLine
        self.upCandle = upCandle
        self.downCandle = downCandle
        self.text = text
        self.crosshair = crosshair
        self.reference = reference
        self.dotOuter = dotOuter
    }

    public static let `default` = LivelinePalette()

    /// Derive a full palette from one accent color + theme, mirroring
    /// `resolveTheme` in `src/theme.ts`. Candle/momentum colors stay
    /// semantic green/red regardless of accent.
    public static func derive(accent: UIColor, theme: LivelineTheme = .dark) -> LivelinePalette {
        let dark = theme == .dark
        let mono: (CGFloat, CGFloat) -> UIColor = { white, alpha in
            UIColor(white: dark ? white : 1 - white, alpha: alpha)
        }
        return LivelinePalette(
            background: dark
                ? UIColor(red: 10 / 255, green: 10 / 255, blue: 10 / 255, alpha: 1)
                : .white,
            line: accent,
            fillTop: accent.withAlphaComponent(dark ? 0.12 : 0.08),
            fillBottom: accent.withAlphaComponent(0),
            grid: mono(1, 0.06),
            gridLabel: mono(1, dark ? 0.4 : 0.35),
            timeLabel: mono(1, dark ? 0.35 : 0.3),
            dashLine: accent.withAlphaComponent(0.4),
            upCandle: UIColor(red: 0.13, green: 0.77, blue: 0.37, alpha: 1),
            downCandle: UIColor(red: 0.94, green: 0.27, blue: 0.27, alpha: 1),
            text: dark
                ? UIColor(red: 0.9, green: 0.9, blue: 0.9, alpha: 1)
                : UIColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1),
            crosshair: mono(1, dark ? 0.2 : 0.12),
            reference: mono(1, dark ? 0.15 : 0.12),
            dotOuter: dark
                ? UIColor(red: 40 / 255, green: 40 / 255, blue: 40 / 255, alpha: 0.95)
                : UIColor(white: 1, alpha: 0.95)
        )
    }
}
#else
public struct LivelinePalette: Sendable {
    public init() {}
    public static let `default` = LivelinePalette()
}
#endif
