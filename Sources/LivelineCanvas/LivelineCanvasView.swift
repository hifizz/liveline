import Foundation

#if canImport(UIKit)
import UIKit

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

        let link = CADisplayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
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

    @objc private func tick(_ sender: CADisplayLink) {
        setNeedsDisplay()
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
        guard !points.isEmpty else { return }
        let chartRect = bounds.inset(by: UIEdgeInsets(
            top: CGFloat(config.insets.top),
            left: CGFloat(config.insets.left),
            bottom: CGFloat(config.insets.bottom),
            right: CGFloat(config.insets.right)
        ))

        let ratio = clamp((x - chartRect.minX) / max(1, chartRect.width), 0, 1)
        guard let newest = points.last?.time else { return }
        let oldest = newest - config.windowSeconds
        let targetTime = oldest + TimeInterval(ratio) * config.windowSeconds

        let nearest = points.min { abs($0.time - targetTime) < abs($1.time - targetTime) }
        onHover?(nearest)
    }
}

#endif
