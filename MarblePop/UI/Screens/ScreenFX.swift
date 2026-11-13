import SwiftUI
import GameKit

// Small helpers shared by the screen ports (Compose idioms that have no direct SwiftUI twin).

/// Compose `rememberInfiniteTransition` / `rememberTime()`: redraws every display frame while not paused
/// and hands the content the seconds elapsed since it first appeared.
struct FrameClock<Content: View>: View {
    var paused: Bool = false
    /// Shared time origin (several clocks in step); nil = when this view first appeared.
    var origin: Date? = nil
    /// Redraw at most this often (seconds); nil = every display frame.
    var minimumInterval: Double? = nil
    @ViewBuilder let content: (Double) -> Content
    @State var start = Date()

    init(paused: Bool = false, origin: Date? = nil, minimumInterval: Double? = nil, @ViewBuilder content: @escaping (Double) -> Content) {
        self.paused = paused
        self.origin = origin
        self.minimumInterval = minimumInterval
        self.content = content
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: minimumInterval, paused: paused)) { tl in
            content(max(0, tl.date.timeIntervalSince(origin ?? start)))
        }
    }
}

/// Phase in [0, 1) of an `infiniteRepeatable(tween(periodMs, LinearEasing))` animation.
@inline(__always)
func loopPhase(_ seconds: Double, _ periodMs: Double) -> CGFloat {
    let p = (seconds * 1000).truncatingRemainder(dividingBy: periodMs) / periodMs
    return CGFloat(p)
}

/// Spring "pop": scale = v, alpha = v clamped to [0, 1] (Compose `graphicsLayer { scaleX = v; alpha = v.coerceIn(0f, 1f) }`).
struct PopFX: ViewModifier, Animatable {
    var v: CGFloat
    var rotation: Double = 0
    var animatableData: CGFloat {
        get { v }
        set { v = newValue }
    }

    func body(content: Content) -> some View {
        content
            .scaleEffect(max(0.0001, v))
            .rotationEffect(.degrees(rotation))
            .opacity(Double(min(1, max(0, v))))
    }
}

/// Seconds → Kotlin `System.currentTimeMillis()`.
@inline(__always)
func nowMillis() -> Int64 { Days.nowMillis() }

/// Raw Android pixel constants in the screen code (Canvas `CornerRadius(16f)`, `Stroke(4f)`…) were tuned on the
/// 2.0-density reference device: 1 px = 0.5 pt.
let pxPt: CGFloat = 0.5

/// Compose `Row` whose children use `Modifier.weight(w)`: fixed widths from the weights, top aligned.
struct WeightRow: Layout {
    var weights: [CGFloat]
    var spacing: CGFloat = 0

    private func unit(_ width: CGFloat, _ n: Int) -> CGFloat {
        let total = weights.prefix(n).reduce(0, +)
        return total > 0 ? max(0, width - spacing * CGFloat(max(0, n - 1))) / total : 0
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let w = proposal.width ?? 0
        let u = unit(w, subviews.count)
        var h: CGFloat = 0
        for (i, s) in subviews.enumerated() {
            h = max(h, s.sizeThatFits(ProposedViewSize(width: u * weights[min(i, weights.count - 1)], height: nil)).height)
        }
        return CGSize(width: w, height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let u = unit(bounds.width, subviews.count)
        var x = bounds.minX
        for (i, s) in subviews.enumerated() {
            let cw = u * weights[min(i, weights.count - 1)]
            s.place(at: CGPoint(x: x, y: bounds.minY), anchor: .topLeading, proposal: ProposedViewSize(width: cw, height: nil))
            x += cw + spacing
        }
    }
}
