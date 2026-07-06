import Foundation

#if canImport(SwiftUI) && canImport(UIKit)
import SwiftUI

/// Time-horizon buttons with a sliding active indicator — SwiftUI equivalent
/// of the React window bar (`windows` / `windowStyle` / `onWindowChange`).
/// Bind `selection` to the value you pass as `config.windowSeconds`; the
/// chart animates the window change itself (750ms, log-interpolated).
public struct LivelineWindowBar: View {
    public enum Style {
        /// Subtle background, rounded corners (React `default`).
        case standard
        /// Fully rounded pill (React `rounded`).
        case rounded
        /// No chrome, text only (React `text`).
        case text
    }

    private let options: [LivelineWindowOption]
    @Binding private var selection: TimeInterval
    private let style: Style
    @Namespace private var indicator

    public init(options: [LivelineWindowOption], selection: Binding<TimeInterval>, style: Style = .standard) {
        self.options = options
        self._selection = selection
        self.style = style
    }

    public var body: some View {
        HStack(spacing: style == .text ? 4 : 2) {
            ForEach(options) { option in
                let isActive = option.seconds == selection
                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        selection = option.seconds
                    }
                } label: {
                    Text(option.label)
                        .font(.system(size: 11, weight: isActive ? .semibold : .regular, design: .monospaced))
                        .foregroundColor(isActive ? .primary : .secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Group {
                                if isActive && style != .text {
                                    RoundedRectangle(cornerRadius: style == .rounded ? 999 : 5)
                                        .fill(Color.primary.opacity(0.12))
                                        .matchedGeometryEffect(id: "window-indicator", in: indicator)
                                }
                            }
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(style == .text ? 0 : (style == .rounded ? 3 : 2))
        .background(
            Group {
                if style != .text {
                    RoundedRectangle(cornerRadius: style == .rounded ? 999 : 6)
                        .fill(Color.primary.opacity(0.05))
                }
            }
        )
    }
}

/// Line/candle mode toggle — SwiftUI equivalent of the built-in toggle the
/// React component renders when `onModeChange` is set. Bind `isLineMode` to
/// the value you pass as the chart's `lineMode`.
public struct LivelineModeToggle: View {
    @Binding private var isLineMode: Bool
    @Namespace private var indicator

    public init(isLineMode: Binding<Bool>) {
        self._isLineMode = isLineMode
    }

    public var body: some View {
        HStack(spacing: 2) {
            modeButton(line: true)
            modeButton(line: false)
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
    }

    private func modeButton(line: Bool) -> some View {
        let isActive = isLineMode == line
        return Button {
            withAnimation(.easeInOut(duration: 0.25)) {
                isLineMode = line
            }
        } label: {
            Group {
                if line { LineModeIcon() } else { CandleModeIcon() }
            }
            .frame(width: 22, height: 16)
            .opacity(isActive ? 1 : 0.45)
            .padding(.horizontal, 5)
            .padding(.vertical, 4)
            .background(
                Group {
                    if isActive {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(Color.primary.opacity(0.12))
                            .matchedGeometryEffect(id: "mode-indicator", in: indicator)
                    }
                }
            )
        }
        .buttonStyle(.plain)
    }
}

private struct LineModeIcon: View {
    var body: some View {
        Path { p in
            p.move(to: CGPoint(x: 1, y: 12))
            p.addCurve(to: CGPoint(x: 8, y: 6), control1: CGPoint(x: 4, y: 12), control2: CGPoint(x: 5, y: 6))
            p.addCurve(to: CGPoint(x: 14, y: 10), control1: CGPoint(x: 11, y: 6), control2: CGPoint(x: 12, y: 10))
            p.addCurve(to: CGPoint(x: 21, y: 3), control1: CGPoint(x: 17, y: 10), control2: CGPoint(x: 18, y: 3))
        }
        .stroke(Color.primary, style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round))
    }
}

private struct CandleModeIcon: View {
    var body: some View {
        ZStack {
            Path { p in
                p.move(to: CGPoint(x: 7, y: 1))
                p.addLine(to: CGPoint(x: 7, y: 15))
                p.move(to: CGPoint(x: 15, y: 1))
                p.addLine(to: CGPoint(x: 15, y: 15))
            }
            .stroke(Color.primary, lineWidth: 1.2)
            Path { p in
                p.addRoundedRect(in: CGRect(x: 4.5, y: 4, width: 5, height: 7), cornerSize: CGSize(width: 1, height: 1))
                p.addRoundedRect(in: CGRect(x: 12.5, y: 6, width: 5, height: 6), cornerSize: CGSize(width: 1, height: 1))
            }
            .fill(Color.primary)
        }
    }
}

/// Series visibility chips — SwiftUI equivalent of the React toggle chips in
/// multi-series mode. Bind `hidden` to the chart's `hiddenSeriesIDs`; the
/// last visible series can never be hidden, matching the web behavior.
public struct LivelineSeriesChips: View {
    private let series: [LivelineSeries]
    @Binding private var hidden: Set<String>
    private let compact: Bool

    public init(series: [LivelineSeries], hidden: Binding<Set<String>>, compact: Bool = false) {
        self.series = series
        self._hidden = hidden
        self.compact = compact
    }

    public var body: some View {
        HStack(spacing: 6) {
            ForEach(Array(series.enumerated()), id: \.element.id) { index, s in
                let isHidden = hidden.contains(s.id)
                Button {
                    toggle(s.id)
                } label: {
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color(uiColor: s.color ?? LivelinePalette.seriesColors[index % LivelinePalette.seriesColors.count]))
                            .frame(width: compact ? 8 : 6, height: compact ? 8 : 6)
                        if !compact {
                            Text(s.label ?? s.id)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, compact ? 5 : 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(Color.primary.opacity(0.05)))
                    .opacity(isHidden ? 0.4 : 1)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func toggle(_ id: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if hidden.contains(id) {
                hidden.remove(id)
            } else {
                let visibleCount = series.filter { !hidden.contains($0.id) }.count
                guard visibleCount > 1 else { return }
                hidden.insert(id)
            }
        }
    }
}
#endif
