import Foundation

#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI

public struct LivelineChart: UIViewRepresentable {
    public var points: [LivelinePoint]
    public var candles: [CandlePoint]
    public var liveCandle: CandlePoint?
    public var series: [LivelineSeries]
    public var hiddenSeriesIDs: Set<String>
    public var orderbook: LivelineOrderbook?
    public var value: Double
    public var config: LivelineConfig
    public var palette: LivelinePalette
    public var referenceLine: LivelineReferenceLine?
    public var loading: Bool
    public var paused: Bool
    public var lineMode: Bool
    public var lineData: [LivelinePoint]
    public var onHover: ((LivelinePoint?) -> Void)?

    public init(
        points: [LivelinePoint],
        candles: [CandlePoint] = [],
        liveCandle: CandlePoint? = nil,
        series: [LivelineSeries] = [],
        hiddenSeriesIDs: Set<String> = [],
        orderbook: LivelineOrderbook? = nil,
        value: Double,
        config: LivelineConfig = .init(),
        palette: LivelinePalette = .default,
        referenceLine: LivelineReferenceLine? = nil,
        loading: Bool = false,
        paused: Bool = false,
        lineMode: Bool = false,
        lineData: [LivelinePoint] = [],
        onHover: ((LivelinePoint?) -> Void)? = nil
    ) {
        self.points = points
        self.candles = candles
        self.liveCandle = liveCandle
        self.series = series
        self.hiddenSeriesIDs = hiddenSeriesIDs
        self.orderbook = orderbook
        self.value = value
        self.config = config
        self.palette = palette
        self.referenceLine = referenceLine
        self.loading = loading
        self.paused = paused
        self.lineMode = lineMode
        self.lineData = lineData
        self.onHover = onHover
    }

    public func makeUIView(context: Context) -> LivelineCanvasView {
        LivelineCanvasView(frame: .zero)
    }

    public func updateUIView(_ uiView: LivelineCanvasView, context: Context) {
        uiView.config = config
        uiView.palette = palette
        uiView.points = points
        uiView.candles = candles
        uiView.liveCandle = liveCandle
        uiView.series = series
        uiView.hiddenSeriesIDs = hiddenSeriesIDs
        uiView.orderbook = orderbook
        uiView.liveValue = value
        uiView.referenceLine = referenceLine
        uiView.isLoading = loading
        uiView.isPaused = paused
        uiView.lineMode = lineMode
        uiView.lineData = lineData
        uiView.onHover = onHover
    }
}
#endif
