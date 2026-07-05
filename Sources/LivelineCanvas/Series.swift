import Foundation

#if canImport(UIKit)
import UIKit

/// One line in multi-series mode. When a `LivelineCanvasView`'s `series` is
/// non-empty it overrides `points`/`liveValue`, and badge/momentum/fill are
/// disabled — same semantics as the React `series` prop.
public struct LivelineSeries: Sendable {
    public let id: String
    public var data: [LivelinePoint]
    public var value: Double
    /// Defaults to `LivelinePalette.seriesColors[index % 8]` when nil.
    public var color: UIColor?
    public var label: String?

    public init(id: String, data: [LivelinePoint], value: Double, color: UIColor? = nil, label: String? = nil) {
        self.id = id
        self.data = data
        self.value = value
        self.color = color
        self.label = label
    }
}
#endif
