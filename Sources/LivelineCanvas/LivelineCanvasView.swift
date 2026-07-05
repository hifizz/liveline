import Foundation

#if canImport(UIKit)
import UIKit

/// CADisplayLink retains its target — pointing it at the view directly would
/// keep the view alive forever (deinit never runs, the link never stops).
/// This weak proxy breaks the cycle.
private final class DisplayLinkProxy: NSObject {
    weak var view: LivelineCanvasView?

    init(view: LivelineCanvasView) {
        self.view = view
    }

    @objc func tick(_ link: CADisplayLink) {
        view?.displayLinkFired()
    }
}

public final class LivelineCanvasView: UIView {
    public var config: LivelineConfig {
        didSet { setNeedsDisplay() }
    }

    public var palette: LivelinePalette {
        didSet { setNeedsDisplay() }
    }

    public var points: [LivelinePoint] = [] {
        didSet { setNeedsDisplay() }
    }

    public var candles: [CandlePoint] = [] {
        didSet { setNeedsDisplay() }
    }

    /// Current in-progress candle, updated every tick (React `liveCandle`).
    public var liveCandle: CandlePoint? {
        didSet { setNeedsDisplay() }
    }

    /// Bid/ask depth stream for the rising orderbook labels.
    public var orderbook: LivelineOrderbook? {
        didSet { setNeedsDisplay() }
    }

    /// Multi-series mode: when non-empty, overrides `points`/`liveValue`
    /// and disables badge/momentum/fill, like the React `series` prop.
    public var series: [LivelineSeries] = [] {
        didSet { setNeedsDisplay() }
    }

    /// Series IDs currently hidden (they fade out smoothly). Toggle from
    /// your own chips UI and the Y-range re-adjusts, as on the web.
    public var hiddenSeriesIDs: Set<String> = [] {
        didSet { setNeedsDisplay() }
    }

    public var liveValue: Double = 0 {
        didSet { setNeedsDisplay() }
    }

    public var referenceLine: LivelineReferenceLine? {
        didSet { setNeedsDisplay() }
    }

    public var isPaused: Bool = false {
        didSet { setNeedsDisplay() }
    }

    public var isLoading: Bool = false {
        didSet { setNeedsDisplay() }
    }

    public var onHover: ((LivelinePoint?) -> Void)?

    private var displayLink: CADisplayLink?
    private var hoverX: CGFloat?
    private var state = RenderState()
    private var lastTimestamp: CFTimeInterval?

    public override init(frame: CGRect) {
        self.config = LivelineConfig()
        self.palette = .default
        super.init(frame: frame)
        commonInit()
    }

    public required init?(coder: NSCoder) {
        self.config = LivelineConfig()
        self.palette = .default
        super.init(coder: coder)
        commonInit()
    }

    deinit {
        displayLink?.invalidate()
    }

    private func commonInit() {
        isOpaque = true
        contentMode = .redraw

        let pan = UIPanGestureRecognizer(target: self, action: #selector(onPan(_:)))
        pan.maximumNumberOfTouches = 1
        addGestureRecognizer(pan)

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(onLongPress(_:)))
        longPress.minimumPressDuration = 0.2
        addGestureRecognizer(longPress)

        let link = CADisplayLink(target: DisplayLinkProxy(view: self), selector: #selector(DisplayLinkProxy.tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    /// Stop the render loop while detached from a window — the equivalent of
    /// the web version pausing requestAnimationFrame on a hidden tab.
    public override func didMoveToWindow() {
        super.didMoveToWindow()
        displayLink?.isPaused = window == nil
        if window != nil {
            lastTimestamp = nil
            setNeedsDisplay()
        }
    }

    fileprivate func displayLinkFired() {
        setNeedsDisplay()
    }

    public override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        let now = Date().timeIntervalSince1970
        let dt: Double
        if let lastTimestamp {
            dt = min(1 / 20, now - lastTimestamp)
        } else {
            dt = 1 / 60
        }
        lastTimestamp = now

        LivelineRenderer.render(
            ctx,
            input: RenderInput(
                rect: bounds,
                points: points,
                candles: candles,
                liveCandle: liveCandle,
                series: series,
                hiddenSeriesIDs: hiddenSeriesIDs,
                orderbook: orderbook,
                value: liveValue,
                config: config,
                palette: palette,
                referenceLine: referenceLine,
                hoverX: hoverX,
                isPaused: isPaused,
                isLoading: isLoading,
                now: now
            ),
            state: &state,
            dt: dt
        )
    }

    @objc private func onPan(_ gesture: UIPanGestureRecognizer) {
        let point = gesture.location(in: self)
        hoverX = point.x
        emitHover(atX: point.x)
        if gesture.state == .ended || gesture.state == .cancelled {
            hoverX = nil
            onHover?(nil)
        }
        setNeedsDisplay()
    }

    @objc private func onLongPress(_ gesture: UILongPressGestureRecognizer) {
        let point = gesture.location(in: self)
        switch gesture.state {
        case .began, .changed:
            hoverX = point.x
            emitHover(atX: point.x)
        case .ended, .cancelled, .failed:
            hoverX = nil
            onHover?(nil)
        default:
            break
        }
        setNeedsDisplay()
    }

    private func emitHover(atX x: CGFloat) {
        let hoverData = series.isEmpty ? points : (series.first(where: { !hiddenSeriesIDs.contains($0.id) })?.data ?? [])
        guard !hoverData.isEmpty else { return }
        let chartRect = bounds.inset(by: UIEdgeInsets(
            top: CGFloat(config.insets.top),
            left: CGFloat(config.insets.left),
            bottom: CGFloat(config.insets.bottom),
            right: CGFloat(config.insets.right)
        ))
        guard chartRect.width > 0 else { return }

        // Same time mapping as the renderer: chart clock (wall clock minus
        // pause debt) plus the small right-edge buffer.
        let isMulti = !series.isEmpty
        let showBadge = config.showBadge && config.mode == .line && !isMulti
        let buffer = showBadge ? 0.05 : 0.015
        let now = Date().timeIntervalSince1970 - state.timeDebt
        let rightEdgeTime = now + config.windowSeconds * buffer
        let ratio = clamp((x - chartRect.minX) / chartRect.width, 0, 1)
        let targetTime = (rightEdgeTime - config.windowSeconds) + TimeInterval(ratio) * config.windowSeconds

        let nearest = hoverData.min { abs($0.time - targetTime) < abs($1.time - targetTime) }
        onHover?(nearest)
    }
}

#endif
