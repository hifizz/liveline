import Foundation

#if canImport(UIKit)
import UIKit

public struct LivelinePalette: Sendable {
    public var background: UIColor
    public var line: UIColor
    public var fill: UIColor
    public var grid: UIColor
    public var upCandle: UIColor
    public var downCandle: UIColor
    public var text: UIColor
    public var crosshair: UIColor
    public var reference: UIColor

    public init(
        background: UIColor = .black,
        line: UIColor = UIColor(red: 0.22, green: 0.72, blue: 0.95, alpha: 1),
        fill: UIColor = UIColor(red: 0.22, green: 0.72, blue: 0.95, alpha: 0.18),
        grid: UIColor = UIColor(white: 1, alpha: 0.08),
        upCandle: UIColor = UIColor(red: 0.23, green: 0.82, blue: 0.38, alpha: 1),
        downCandle: UIColor = UIColor(red: 0.95, green: 0.33, blue: 0.33, alpha: 1),
        text: UIColor = UIColor(white: 1, alpha: 0.92),
        crosshair: UIColor = UIColor(white: 1, alpha: 0.45),
        reference: UIColor = UIColor(white: 1, alpha: 0.35)
    ) {
        self.background = background
        self.line = line
        self.fill = fill
        self.grid = grid
        self.upCandle = upCandle
        self.downCandle = downCandle
        self.text = text
        self.crosshair = crosshair
        self.reference = reference
    }

    public static let `default` = LivelinePalette()
}
#else
public struct LivelinePalette: Sendable {
    public init() {}
    public static let `default` = LivelinePalette()
}
#endif
