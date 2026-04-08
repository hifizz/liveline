import Foundation

#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI

public struct LivelineChart: UIViewRepresentable {
    public var points: [LivelinePoint]
    public var candles: [CandlePoint]
    public var value: Double
    public var config: LivelineConfig
    public var palette: LivelinePalette
    public var referenceLine: LivelineReferenceLine?
    public var loading: Bool
    public var paused: Bool

    public init(
        points: [LivelinePoint],
        candles: [CandlePoint] = [],
        value: Double,
        config: LivelineConfig = .init(),
        palette: LivelinePalette = .default,
        referenceLine: LivelineReferenceLine? = nil,
        loading: Bool = false,
        paused: Bool = false
    ) {
        self.points = points
        self.candles = candles
        self.value = value
        self.config = config
        self.palette = palette
        self.referenceLine = referenceLine
        self.loading = loading
        self.paused = paused
    }

    public func makeUIView(context: Context) -> LivelineCanvasView {
        LivelineCanvasView(frame: .zero)
    }

    public func updateUIView(_ uiView: LivelineCanvasView, context: Context) {
        uiView.config = config
        uiView.palette = palette
        uiView.points = points
        uiView.candles = candles
        uiView.liveValue = value
        uiView.referenceLine = referenceLine
        uiView.isLoading = loading
        uiView.isPaused = paused
    }
}
#endif
