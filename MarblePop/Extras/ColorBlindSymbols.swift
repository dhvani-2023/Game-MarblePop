import CoreGraphics
import SwiftUI
import GameKit

// Extra 1 (Features.colorBlindPatterns): a distinct symbol per marble colour, baked into the game renderer's
// marble, cup and block sprites (SpriteCache.symbols), so every match reads without colour.

/// The player's colour-blind switch (Settings › Accessibility), saved in the game's "marble_pop" Prefs store.
enum ColorBlind {
    /// Prefs key (Android-style snake case like `haptics` or `free_gift_at`); default off.
    static let KEY = "color_blind"

    /// Symbols are baked when the extra is compiled in and the player switched it on.
    static func active(_ repo: GameRepository) -> Bool { Features.colorBlindPatterns && repo.colorBlind }
}

/// One symbol per marble colour id, in `MarbleColors` order, plus the rainbow wildcard. The shapes are chosen to
/// stay apart at marble size (about 6 pt): Red heart, Yellow star, Sky drop, Green clover, Purple diamond,
/// Orange triangle, Pink crescent, Blue bolt, White ring, Brown square, Forest cross, Charcoal plus,
/// and a rainbow arch for the rainbow wildcard.
enum ColorBlindSymbol: Int, CaseIterable {
    case heart, star, drop, clover, diamond, triangle, moon, bolt, ring, square, cross, plus, arch

    /// Symbol of a marble colour id (0 ..< MarbleColors.COUNT, or MarbleColors.RAINBOW); nil for anything else.
    static func of(_ colorId: Int) -> ColorBlindSymbol? {
        if colorId == MarbleColors.RAINBOW { return .arch }
        guard colorId >= 0 && colorId < MarbleColors.COUNT else { return nil }
        return ColorBlindSymbol(rawValue: colorId)
    }

    var name: String { ColorBlindSymbol.names[rawValue] }

    /// Outline in a [-1, 1] box (y-down), for the non-zero fill rule. Built once.
    var unitPath: CGPath { ColorBlindSymbol.paths[rawValue] }

    private static let names = ["heart", "star", "drop", "clover", "diamond", "triangle", "moon", "bolt", "ring",
                                "square", "cross", "plus", "arch"]
    private static let paths: [CGPath] = allCases.map { $0.build() }

    private func build() -> CGPath {
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
        func poly(_ xy: [CGFloat]) -> CGPath {
            let q = CGMutablePath()
            q.move(to: pt(xy[0], xy[1]))
            var i = 2
            while i + 1 < xy.count { q.addLine(to: pt(xy[i], xy[i + 1])); i += 2 }
            q.closeSubpath()
            return q
        }
        func circle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) -> CGPath {
            CGPath(ellipseIn: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r), transform: nil)
        }
        switch self {
        case .heart:
            let p = CGMutablePath()
            p.move(to: pt(0, 0.88))
            p.addCurve(to: pt(-1, -0.25), control1: pt(-0.62, 0.4), control2: pt(-1, 0.13))
            p.addCurve(to: pt(0, -0.55), control1: pt(-1, -0.89), control2: pt(-0.28, -1.07))
            p.addCurve(to: pt(1, -0.25), control1: pt(0.28, -1.07), control2: pt(1, -0.89))
            p.addCurve(to: pt(0, 0.88), control1: pt(1, 0.13), control2: pt(0.62, 0.4))
            p.closeSubpath()
            return p
        case .star:
            var xy: [CGFloat] = []
            for i in 0..<10 {
                let a = -CGFloat.pi / 2 + CGFloat(i) * .pi / 5
                let r: CGFloat = i % 2 == 0 ? 1 : 0.46
                xy.append(cos(a) * r); xy.append(sin(a) * r + 0.08)
            }
            return poly(xy)
        case .drop:
            let p = CGMutablePath()
            p.move(to: pt(0, -1))
            p.addCurve(to: pt(0.76, 0.22), control1: pt(0.3, -0.58), control2: pt(0.76, -0.22))
            p.addCurve(to: pt(0, 0.98), control1: pt(0.76, 0.64), control2: pt(0.42, 0.98))
            p.addCurve(to: pt(-0.76, 0.22), control1: pt(-0.42, 0.98), control2: pt(-0.76, 0.64))
            p.addCurve(to: pt(0, -1), control1: pt(-0.76, -0.22), control2: pt(-0.3, -0.58))
            p.closeSubpath()
            return p
        case .clover:
            let stem = CGMutablePath()
            stem.move(to: pt(-0.1, 0))
            stem.addLine(to: pt(0.1, 0))
            stem.addQuadCurve(to: pt(0.36, 0.96), control: pt(0.12, 0.6))
            stem.addLine(to: pt(0.12, 0.98))
            stem.addQuadCurve(to: pt(-0.1, 0), control: pt(-0.12, 0.6))
            stem.closeSubpath()
            return circle(0, -0.5, 0.43)
                .union(circle(-0.52, 0.05, 0.43))
                .union(circle(0.52, 0.05, 0.43))
                .union(circle(0, -0.12, 0.3))
                .union(stem)
        case .diamond:
            return poly([0, -0.98, 0.92, 0, 0, 0.98, -0.92, 0])
        case .triangle:
            return poly([0, -0.95, 1, 0.8, -1, 0.8])
        case .moon:
            return circle(0, 0, 0.95).subtracting(circle(0.42, -0.28, 0.82))
        case .bolt:
            return poly([-0.2, -1, 0.55, -1, 0.12, -0.22, 0.62, -0.22, -0.36, 1, -0.06, 0.12, -0.56, 0.12])
        case .ring:
            return circle(0, 0, 0.92).subtracting(circle(0, 0, 0.48))
        case .square:
            return CGPath(roundedRect: CGRect(x: -0.8, y: -0.8, width: 1.6, height: 1.6), cornerWidth: 0.2, cornerHeight: 0.2, transform: nil)
        case .cross:
            // the plus below, longer arms, turned 45°
            let a: CGFloat = 0.24, l: CGFloat = 1.12
            let k = CGFloat(0.5).squareRoot()
            var xy: [CGFloat] = []
            let arms = ColorBlindSymbol.plusOutline(a, l)
            var i = 0
            while i < arms.count {
                let x = arms[i], y = arms[i + 1]
                xy.append((x - y) * k); xy.append((x + y) * k)
                i += 2
            }
            return poly(xy)
        case .plus:
            return poly(ColorBlindSymbol.plusOutline(0.25, 0.92))
        case .arch:
            // a thick rainbow band: the upper half of a ring standing on its two feet
            let p = CGMutablePath()
            let cy: CGFloat = 0.48
            p.move(to: pt(-0.98, cy))
            p.addArc(center: pt(0, cy), radius: 0.98, startAngle: .pi, endAngle: 0, clockwise: false)
            p.addLine(to: pt(0.5, cy))
            p.addArc(center: pt(0, cy), radius: 0.5, startAngle: 0, endAngle: .pi, clockwise: true)
            p.closeSubpath()
            return p
        }
    }

    /// Plus outline (x, y pairs) with arm half-width `a` and arm length `l`.
    private static func plusOutline(_ a: CGFloat, _ l: CGFloat) -> [CGFloat] {
        [a, -l, a, -a, l, -a, l, a, a, a, a, l, -a, l, -a, a, -l, a, -l, -a, -a, -a, -a, -l]
    }
}

/// Paints the symbols into baked sprites (ACanvas, main thread, like MachineArt): a soft drop shadow, the game's
/// dark outline purple and a white candy fill, so a symbol reads on every marble colour from White to Charcoal.
enum ColorBlindArt {
    private static let p = Paint()

    /// The game's outline ink (GameColors.Ink, icon outlines).
    static let INK = 0xFF2A1463
    private static let FILL_TOP = 0xFFFFFFFF
    private static let FILL_BOTTOM = 0xFFE2D8FF
    /// Outline and shadow offset as fractions of a symbol's half size.
    static let OUTLINE: CGFloat = 0.24
    static let SHADOW: CGFloat = 0.14
    /// Symbol half size on a marble, in marble radii.
    static let MARBLE_HALF: CGFloat = 0.5

    /// Draws `symbol` centred at (cx, cy) with half size `half` (canvas units).
    static func draw(_ c: ACanvas, _ symbol: ColorBlindSymbol, _ cx: CGFloat, _ cy: CGFloat, _ half: CGFloat, _ alpha: Int = 255) {
        guard half > 0 else { return }
        var t = CGAffineTransform(a: half, b: 0, c: 0, d: half, tx: cx, ty: cy)
        guard let path = symbol.unitPath.copy(using: &t) else { return }
        let ow = half * OUTLINE
        p.reset()
        p.strokeJoin = .round
        p.strokeCap = .round
        p.strokeWidth = ow * 2
        // soft drop shadow
        p.color = Col.alpha(INK, alpha * 80 / 255)
        c.save()
        c.translate(0, half * SHADOW)
        p.style = .FILL; c.drawPath(path, p)
        p.style = .STROKE; c.drawPath(path, p)
        c.restore()
        // outline
        p.color = Col.alpha(INK, alpha)
        c.drawPath(path, p)
        // candy fill (the paint alpha scales the opaque gradient)
        p.style = .FILL
        p.color = Col.alpha(AColor.WHITE, alpha)
        p.shader = Shader.linear(0, cy - half, 0, cy + half, FILL_TOP, FILL_BOTTOM)
        c.drawPath(path, p)
        p.shader = nil
    }

    /// On a marble of radius `r` centred at (cx, cy).
    static func onMarble(_ c: ACanvas, _ colorId: Int, _ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) {
        guard let s = ColorBlindSymbol.of(colorId) else { return }
        draw(c, s, cx, cy + r * 0.02, r * MARBLE_HALF)
    }

    /// On the front face of a cup (MachineArt.puck) drawn in the box (x, y, w, h), below the lip with the sockets.
    /// Callers skip hidden cups: their colour is still a secret.
    static func onCup(_ c: ACanvas, _ colorId: Int, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) {
        guard let s = ColorBlindSymbol.of(colorId) else { return }
        draw(c, s, x + w / 2, y + h * 0.69, h * 0.19)
    }

    /// On a board block of side `s` (MachineArt.jelly at the origin), over the bottom-left marble of its window:
    /// the one spot that no block overlay (key, arrow, bomb, bucket, switch, cage badge, x2 badge) covers.
    /// Mystery (1) and grey (2) blocks hide their colour, so they get none; rainbow blocks (3) show the rainbow arch.
    static func onBlock(_ c: ACanvas, _ colorId: Int, _ variant: Int, _ s: CGFloat, _ open: Bool) {
        let symbol: ColorBlindSymbol?
        switch variant {
        case 1, 2: symbol = nil
        case 3: symbol = .arch
        default: symbol = ColorBlindSymbol.of(colorId)
        }
        guard let symbol else { return }
        // MachineArt.jelly: face = box inset by pad (bottom also by depth); window = face inset by (0.125 s, 0.115 s)
        let pad = s * 0.05
        let depth = open ? s * 0.1 : s * 0.05
        let left = pad + s * 0.125, top = pad + s * 0.115
        let right = s - pad - s * 0.125, bottom = s - pad - depth - s * 0.115
        let stepX = (right - left) / 3, stepY = (bottom - top) / 3
        draw(c, symbol, left + stepX * 0.5, top + stepY * 2.5 - s * 0.008, s * 0.115, open ? 255 : 225)
    }

    // ---- SwiftUI (Settings preview)

    private static var images: [Int: Image] = [:]

    /// The symbol alone as an image of `side` points (the symbol's half size is 0.36 side), baked once per size.
    static func image(_ symbol: ColorBlindSymbol, side: CGFloat, displayScale: CGFloat) -> Image {
        let scale = displayScale >= 1 ? displayScale : DisplayScale.value
        let px = max(8, Int((side * scale).rounded(.up)))
        let k = symbol.rawValue * 100_000 + px
        if let img = images[k] { return img }
        let cg = Bake.image(px, px) { c in
            let s = CGFloat(px)
            draw(c, symbol, s / 2, s / 2 - s * 0.03, s * 0.36)
        }
        let img = Image(decorative: cg, scale: scale).interpolation(.high).antialiased(true)
        images[k] = img
        return img
    }
}
