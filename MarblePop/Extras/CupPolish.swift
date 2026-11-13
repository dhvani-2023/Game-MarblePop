import SwiftUI
import GameKit

// Extra 3 (Features.smoothPolish): render-only cup polish for GameRenderer.drawCups. The engine keeps its own
// timers (a cup's `bounce` runs 1 → 0 at 4/s after every landing, a filled cup pops for 0.42 s and is then
// removed), so gameplay timing is unchanged; only how those timers are drawn changes.

enum CupPolish {
    /// GameEngine.updateCups removes a popping cup once `popT` reaches 0.42 s.
    static let POP: CGFloat = 0.42
    /// The shimmer has swept across the cup by this fraction of the pop, while the cup is still nearly solid.
    static let SHIMMER_END: CGFloat = 0.6
    /// Landing spring: 5 Hz under an envelope that ends with the engine's 0.25 s bounce timer (one squash, then a
    /// softer rebound).
    static let OMEGA: CGFloat = 2 * .pi * 5
    /// Squash amplitude for the 1st, 2nd and 3rd (filling) marble.
    static let AMP: [CGFloat] = [0.05, 0.06, 0.075]
    /// World units the cup dips per unit of squash.
    static let DIP: CGFloat = 70

    /// Drawn while the flag is on and Reduce Motion is off (Canvas draws on the main thread).
    static var active: Bool {
        guard Features.smoothPolish else { return false }
        guard Thread.isMainThread else { return true }
        return !MainActor.assumeIsolated { Motion.reduce }
    }

    /// Squash (+ squashed, − stretched; scale x by 1 + s and y by 1 − s around the cup's foot) and dip (world
    /// units, + = down) of a cup whose landing timer is `bounce`: τ = (1 − bounce) / 4 is the time since the
    /// marble landed. Bigger as the cup fills.
    static func bounce(_ bounce: Float, _ arrived: Int) -> (squash: CGFloat, dip: CGFloat) {
        let b = CGFloat(min(max(bounce, 0), 1))
        if b <= 0 || b >= 1 { return (0, 0) }
        let tau = (1 - b) / 4
        let amp = AMP[min(max(arrived, 1), 3) - 1]
        let s = amp * sin(tau * OMEGA) * b * b.squareRoot()
        return (s, s * DIP)
    }

    /// Rise of a filled cup (fraction of its 55-unit flight) at `t` = popT / 0.42: eased in, so the cup stays put
    /// while the shimmer passes and then flies off.
    static func lift(_ t: CGFloat) -> CGFloat {
        let u = min(max(t, 0), 1)
        return u * u
    }

    /// Opacity of a filled cup at `t`: solid for longer, gone exactly when the engine removes it.
    static func fade(_ t: CGFloat) -> CGFloat {
        let u = min(max(t, 0), 1)
        return 1 - u * u
    }

    /// Shimmer progress 0 → 1 at pop fraction `t`, nil outside the sweep.
    static func shimmerPhase(_ t: CGFloat) -> CGFloat? {
        guard t > 0 && t < SHIMMER_END else { return nil }
        return t / SHIMMER_END
    }

    /// A diagonal glint sweeping left → right across a filled cup (and its marbles), clipped to the cup's
    /// silhouette and added on top. `c` is the cup's already transformed context, (x, y, w, h) its sprite box,
    /// `t` = popT / 0.42.
    static func shimmer(_ c: GraphicsContext, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ t: CGFloat) {
        guard let p = shimmerPhase(t) else { return }
        let art = CupPolishArt.get(w, h)
        var g = c
        g.translateBy(x: x, y: y)
        g.clip(to: art.silhouette)
        g.blendMode = .plusLighter
        g.opacity *= Double(sin(p * .pi))
        let e = p * p * (3 - 2 * p)
        g.translateBy(x: -0.25 * w + 1.5 * w * e, y: h / 2)
        g.rotate(by: .degrees(22))
        g.fill(art.band, with: art.shading)
    }
}

/// Cached paths and shading for one cup size (the cup size is fixed per level).
private final class CupPolishArt {
    let w: CGFloat
    let h: CGFloat
    /// MachineArt.puck's outline at the origin: top lip oval + body + bottom oval.
    let silhouette: Path
    let band: Path
    let shading: GraphicsContext.Shading

    private static var last: CupPolishArt?

    static func get(_ w: CGFloat, _ h: CGFloat) -> CupPolishArt {
        if let a = last, a.w == w, a.h == h { return a }
        let a = CupPolishArt(w, h)
        last = a
        return a
    }

    private init(_ w: CGFloat, _ h: CGFloat) {
        self.w = w
        self.h = h
        let eh = h * 0.4
        let lip = CGPath(ellipseIn: CGRect(x: 0, y: 0, width: w, height: eh), transform: nil)
        let body = CGPath(rect: CGRect(x: 0, y: eh / 2, width: w, height: h - eh), transform: nil)
        let foot = CGPath(ellipseIn: CGRect(x: 0, y: h - eh, width: w, height: eh), transform: nil)
        silhouette = Path(lip.union(body).union(foot))
        let bw = w * 0.34
        band = Path(CGRect(x: -bw / 2, y: -h * 1.2, width: bw, height: h * 2.4))
        shading = .linearGradient(
            Gradient(stops: [
                .init(color: .white.opacity(0), location: 0),
                .init(color: .white.opacity(0.28), location: 0.32),
                .init(color: .white.opacity(0.9), location: 0.5),
                .init(color: .white.opacity(0.28), location: 0.68),
                .init(color: .white.opacity(0), location: 1),
            ]),
            startPoint: CGPoint(x: -bw / 2, y: 0), endPoint: CGPoint(x: bw / 2, y: 0))
    }
}
