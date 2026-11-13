import CoreGraphics
import CoreText
import SwiftUI
import GameKit

// Port of render/Sprites.kt: colour helpers, procedural painters and the bitmap sprite cache.

enum Col {
    static func lighten(_ c: Int, _ f: Float) -> Int {
        let r = AColor.red(c), g = AColor.green(c), b = AColor.blue(c)
        return AColor.argb(AColor.alpha(c), Int(Float(r) + Float(255 - r) * f), Int(Float(g) + Float(255 - g) * f), Int(Float(b) + Float(255 - b) * f))
    }

    static func darken(_ c: Int, _ f: Float) -> Int {
        let r = AColor.red(c), g = AColor.green(c), b = AColor.blue(c)
        return AColor.argb(AColor.alpha(c), Int(Float(r) * (1 - f)), Int(Float(g) * (1 - f)), Int(Float(b) * (1 - f)))
    }

    static func alpha(_ c: Int, _ a: Int) -> Int { (c & 0x00FFFFFF) | (max(0, min(255, a)) << 24) }

    static func mix(_ a: Int, _ b: Int, _ t: Float) -> Int {
        let u = 1 - t
        return AColor.argb(
            Int(Float(AColor.alpha(a)) * u + Float(AColor.alpha(b)) * t), Int(Float(AColor.red(a)) * u + Float(AColor.red(b)) * t),
            Int(Float(AColor.green(a)) * u + Float(AColor.green(b)) * t), Int(Float(AColor.blue(a)) * u + Float(AColor.blue(b)) * t)
        )
    }

    static let rainbow: [Int] = [0xFFFF4D5E, 0xFFFFD23F, 0xFF3CCB5A, 0xFF33C8F5, 0xFF9B5CFF, 0xFFFF7AC8, 0xFFFF4D5E]
}

/// Procedural painters. All coordinates are in the canvas' current units.
/// `ACanvas`/`CGContext` overloads draw immediately (Android semantics); `GraphicsContext` overloads (for SwiftUI
/// `Canvas`) draw a cached sprite rendered at the display scale, so they are cheap enough for every frame.
enum Painter {
    private static let p = Paint()
    private static var path = CGMutablePath()
    private static var rect = RectF()
    private static let tp = Paint()

    static func colorOf(_ id: Int) -> Int { id == MarbleColors.RAINBOW ? AColor.WHITE : argbInt(MarbleColors.argb[id]) }

    // ------------------------------------------------------------------ marbles

    static func marble(_ c: ACanvas, _ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ colorId: Int, _ skin: Int) {
        MachineArt.marble(c, cx, cy, r, colorId, skin)
    }

    /// Grid block: a glass candy crate. variant: 0 normal, 1 mystery, 2 gray, 3 rainbow
    static func block(_ c: ACanvas, _ x: CGFloat, _ y: CGFloat, _ s: CGFloat, _ colorId: Int, _ variant: Int, bumps: Bool = true, skin: Int = 0) {
        MachineArt.jelly(c, x, y, s, colorId, variant, bumps, skin)
    }

    /// Tray cup: a cylindrical puck with 3 sockets.
    static func cup(_ c: ACanvas, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ colorId: Int, _ hidden: Bool) {
        MachineArt.puck(c, x, y, w, h, colorId, hidden)
    }

    // ------------------------------------------------------------------ icons / overlays

    /// Centred candy text (Lilita One) with a round-joined outline.
    static func text(_ c: ACanvas, _ s: String, _ cx: CGFloat, _ cy: CGFloat, _ size: CGFloat, _ fill: Int, _ stroke: Int, _ strokeW: CGFloat? = nil) {
        let sw = strokeW ?? size * 0.14
        let font = GameFonts.ctLilita(size)
        let (glyphs, width) = TextPaths.line(s, font)
        let ascent = CTFontGetAscent(font), descent = CTFontGetDescent(font)
        // Android: y = cy - (descent + ascent) / 2 with a negative ascent
        let y = cy - (descent - ascent) / 2
        var t = CGAffineTransform(translationX: cx - width / 2, y: y)
        guard let outline = glyphs.copy(using: &t) else { return }
        tp.reset()
        if sw > 0 {
            tp.style = .STROKE; tp.strokeWidth = sw; tp.strokeJoin = .round; tp.color = stroke
            c.drawPath(outline, tp)
        }
        tp.style = .FILL; tp.color = fill
        c.drawPath(outline, tp)
    }

    static func badge(_ c: ACanvas, _ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ number: String, _ bg: Int) {
        p.reset()
        p.color = Col.darken(bg, 0.4); c.drawCircle(cx, cy + r * 0.12, r, p)
        p.shader = Shader.linear(0, cy - r, 0, cy + r, [Col.lighten(bg, 0.25), bg], nil)
        c.drawCircle(cx, cy, r, p); p.shader = nil
        p.style = .STROKE; p.strokeWidth = r * 0.14; p.color = AColor.WHITE; c.drawCircle(cx, cy, r * 0.93, p); p.style = .FILL
        text(c, number, cx, cy, r * 1.15, AColor.WHITE, Col.darken(bg, 0.5), r * 0.16)
    }

    static func key(_ c: ACanvas, _ cx: CGFloat, _ cy: CGFloat, _ s: CGFloat) {
        let gold = 0xFFFFC93C, dark = 0xFFB07000
        p.reset()
        p.style = .STROKE; p.strokeCap = .round
        p.strokeWidth = s * 0.2; p.color = dark
        c.drawCircle(cx - s * 0.22, cy, s * 0.2, p)
        c.drawLine(cx, cy, cx + s * 0.45, cy, p)
        c.drawLine(cx + s * 0.3, cy, cx + s * 0.3, cy + s * 0.18, p)
        c.drawLine(cx + s * 0.44, cy, cx + s * 0.44, cy + s * 0.14, p)
        p.strokeWidth = s * 0.12; p.color = gold
        c.drawCircle(cx - s * 0.22, cy, s * 0.2, p)
        c.drawLine(cx, cy, cx + s * 0.45, cy, p)
        c.drawLine(cx + s * 0.3, cy, cx + s * 0.3, cy + s * 0.18, p)
        c.drawLine(cx + s * 0.44, cy, cx + s * 0.44, cy + s * 0.14, p)
        p.style = .FILL; p.color = 0xCCFFFFFF
        c.drawCircle(cx - s * 0.3, cy - s * 0.08, s * 0.04, p)
    }

    static func padlock(_ c: ACanvas, _ cx: CGFloat, _ cy: CGFloat, _ s: CGFloat) {
        p.reset()
        p.style = .STROKE; p.strokeWidth = s * 0.13; p.color = 0xFF6B6F80
        rect.set(cx - s * 0.22, cy - s * 0.42, cx + s * 0.22, cy + s * 0.05)
        c.drawArc(rect, 180, 180, false, p)
        p.style = .FILL
        rect.set(cx - s * 0.34, cy - s * 0.15, cx + s * 0.34, cy + s * 0.36)
        p.shader = Shader.linear(0, rect.top, 0, rect.bottom, 0xFFFFD35A, 0xFFE59A00)
        c.drawRoundRect(rect, s * 0.08, s * 0.08, p); p.shader = nil
        p.color = 0xFF7A4A00
        c.drawCircle(cx, cy + s * 0.06, s * 0.07, p)
        rect.set(cx - s * 0.03, cy + s * 0.06, cx + s * 0.03, cy + s * 0.22); c.drawRect(rect, p)
    }

    static func chains(_ c: ACanvas, _ x: CGFloat, _ y: CGFloat, _ s: CGFloat) {
        p.reset(); p.style = .STROKE
        for diag in 0...1 {
            c.save()
            c.rotate(diag == 0 ? 45 : -45, x + s / 2, y + s / 2)
            let n = 5
            for i in 0..<n {
                let lx = x - s * 0.1 + CGFloat(i) * s * 0.3
                rect.set(lx, y + s / 2 - s * 0.08, lx + s * 0.26, y + s / 2 + s * 0.08)
                p.strokeWidth = s * 0.06; p.color = 0xFF4A4E5E; c.drawRoundRect(rect, s * 0.08, s * 0.08, p)
                p.strokeWidth = s * 0.035; p.color = 0xFFC9CEDB; c.drawRoundRect(rect, s * 0.08, s * 0.08, p)
            }
            c.restore()
        }
        p.style = .FILL
    }

    static func cage(_ c: ACanvas, _ x: CGFloat, _ y: CGFloat, _ s: CGFloat) {
        p.reset()
        p.color = 0x553A3F55
        rect.set(x + s * 0.05, y + s * 0.05, x + s * 0.95, y + s * 0.88); c.drawRoundRect(rect, s * 0.18, s * 0.18, p)
        p.style = .STROKE; p.strokeCap = .round
        for i in 1...4 {
            let bx = x + s * (0.05 + 0.18 * CGFloat(i))
            p.strokeWidth = s * 0.06; p.color = 0xFF3B3F52; c.drawLine(bx, y + s * 0.08, bx, y + s * 0.85, p)
            p.strokeWidth = s * 0.03; p.color = 0xFFD7DBE6; c.drawLine(bx - s * 0.008, y + s * 0.1, bx - s * 0.008, y + s * 0.83, p)
        }
        p.style = .FILL
    }

    static func crate(_ c: ACanvas, _ x: CGFloat, _ y: CGFloat, _ s: CGFloat) {
        p.reset()
        let pad = s * 0.05
        p.color = 0xFF7A4A22; rect.set(x + pad, y + pad + s * 0.07, x + s - pad, y + s - pad); c.drawRoundRect(rect, s * 0.12, s * 0.12, p)
        rect.set(x + pad, y + pad, x + s - pad, y + s - pad - s * 0.07)
        p.shader = Shader.linear(0, rect.top, 0, rect.bottom, 0xFFE0A35C, 0xFFC07A36)
        c.drawRoundRect(rect, s * 0.12, s * 0.12, p); p.shader = nil
        p.color = 0xFF8F5526
        for k in 1...2 {
            let ly = rect.top + rect.height() * CGFloat(k) / 3
            c.drawRect(rect.left + s * 0.06, ly - s * 0.012, rect.right - s * 0.06, ly + s * 0.012, p)
        }
        p.style = .STROKE; p.strokeWidth = s * 0.09; p.color = 0xFFA8692F
        c.drawLine(rect.left + s * 0.12, rect.top + s * 0.12, rect.right - s * 0.12, rect.bottom - s * 0.12, p)
        p.strokeWidth = s * 0.05; p.color = 0xFF6E3F18
        var inset = RectF(rect); inset.inset(s * 0.06, s * 0.06); c.drawRoundRect(inset, s * 0.08, s * 0.08, p)
        p.style = .FILL
        p.color = 0xFF55606E
        for (nx, ny) in [(0.18, 0.18), (0.82, 0.18), (0.18, 0.75), (0.82, 0.75)] as [(CGFloat, CGFloat)] {
            c.drawCircle(x + s * nx, y + s * ny, s * 0.035, p)
        }
    }

    static func ice(_ c: ACanvas, _ x: CGFloat, _ y: CGFloat, _ s: CGFloat, _ cracked: Bool) {
        p.reset()
        rect.set(x + s * 0.03, y + s * 0.03, x + s * 0.97, y + s * 0.9)
        p.shader = Shader.linear(rect.left, rect.top, rect.right, rect.bottom, [0xCCEAFBFF, 0x99B6E8FF, 0xBBE2F7FF], nil)
        c.drawRoundRect(rect, s * 0.2, s * 0.2, p); p.shader = nil
        p.style = .STROKE; p.strokeWidth = s * 0.03; p.color = 0xEEFFFFFF
        c.drawRoundRect(rect, s * 0.2, s * 0.2, p)
        p.strokeWidth = s * 0.05; p.strokeCap = .round; p.color = 0xBBFFFFFF
        c.drawLine(x + s * 0.2, y + s * 0.25, x + s * 0.4, y + s * 0.15, p)
        c.drawLine(x + s * 0.18, y + s * 0.38, x + s * 0.28, y + s * 0.33, p)
        if cracked {
            p.strokeWidth = s * 0.025; p.color = 0xFF7FB6D6
            path = CGMutablePath()
            path.moveTo(x + s * 0.5, y + s * 0.45); path.lineTo(x + s * 0.3, y + s * 0.6); path.lineTo(x + s * 0.2, y + s * 0.85)
            path.moveTo(x + s * 0.5, y + s * 0.45); path.lineTo(x + s * 0.72, y + s * 0.3); path.lineTo(x + s * 0.9, y + s * 0.25)
            path.moveTo(x + s * 0.5, y + s * 0.45); path.lineTo(x + s * 0.62, y + s * 0.7); path.lineTo(x + s * 0.8, y + s * 0.8)
            path.moveTo(x + s * 0.5, y + s * 0.45); path.lineTo(x + s * 0.42, y + s * 0.15)
            c.drawPath(path, p)
        }
        p.style = .FILL
    }

    static func arrowIcon(_ c: ACanvas, _ cx: CGFloat, _ cy: CGFloat, _ s: CGFloat, _ dir: Int) {
        p.reset()
        p.color = 0x55000000; c.drawCircle(cx, cy + s * 0.04, s * 0.36, p)
        p.color = AColor.WHITE; c.drawCircle(cx, cy, s * 0.34, p)
        c.save()
        c.rotate(dir == 0 ? 180 : (dir == 1 ? 0 : -90), cx, cy)
        path = CGMutablePath()
        path.moveTo(cx + s * 0.22, cy); path.lineTo(cx, cy - s * 0.2); path.lineTo(cx, cy - s * 0.08)
        path.lineTo(cx - s * 0.2, cy - s * 0.08); path.lineTo(cx - s * 0.2, cy + s * 0.08); path.lineTo(cx, cy + s * 0.08)
        path.lineTo(cx, cy + s * 0.2); path.close()
        p.color = 0xFF4B25B8; c.drawPath(path, p)
        c.restore()
    }

    static func bomb(_ c: ACanvas, _ cx: CGFloat, _ cy: CGFloat, _ s: CGFloat, _ fuse: CGFloat) {
        p.reset()
        p.shader = Shader.radial(cx - s * 0.12, cy - s * 0.1, s * 0.5, [0xFF6B6F85, 0xFF2A2C3A], nil)
        c.drawCircle(cx, cy + s * 0.05, s * 0.3, p); p.shader = nil
        p.color = 0xFF3A3D4F; c.drawRect(cx + s * 0.08, cy - s * 0.3, cx + s * 0.22, cy - s * 0.18, p)
        p.style = .STROKE; p.strokeWidth = s * 0.04; p.color = 0xFFC8A060; p.strokeCap = .round
        c.drawLine(cx + s * 0.15, cy - s * 0.3, cx + s * 0.25, cy - s * 0.42, p)
        p.style = .FILL
        p.color = 0xFFFFD23F; c.drawCircle(cx + s * 0.27, cy - s * 0.44, s * (0.06 + 0.03 * fuse), p)
        p.color = 0xFFFF6A1A; c.drawCircle(cx + s * 0.27, cy - s * 0.44, s * 0.035, p)
        p.color = 0x99FFFFFF; c.drawCircle(cx - s * 0.12, cy - s * 0.06, s * 0.07, p)
    }

    static func bucket(_ c: ACanvas, _ cx: CGFloat, _ cy: CGFloat, _ s: CGFloat, _ color: Int) {
        p.reset()
        path = CGMutablePath()
        path.moveTo(cx - s * 0.26, cy - s * 0.18); path.lineTo(cx + s * 0.26, cy - s * 0.18)
        path.lineTo(cx + s * 0.2, cy + s * 0.3); path.lineTo(cx - s * 0.2, cy + s * 0.3); path.close()
        p.color = 0xFFE9ECF5; c.drawPath(path, p)
        p.style = .STROKE; p.strokeWidth = s * 0.04; p.color = 0xFF6B6F85; c.drawPath(path, p)
        rect.set(cx - s * 0.26, cy - s * 0.42, cx + s * 0.26, cy + s * 0.06); c.drawArc(rect, 180, 180, false, p)
        p.style = .FILL
        p.color = color
        rect.set(cx - s * 0.26, cy - s * 0.25, cx + s * 0.26, cy - s * 0.1); c.drawOval(rect, p)
        c.drawCircle(cx + s * 0.16, cy - s * 0.02, s * 0.06, p)
        c.drawCircle(cx + s * 0.18, cy + s * 0.1, s * 0.045, p)
    }

    static func switchIcon(_ c: ACanvas, _ cx: CGFloat, _ cy: CGFloat, _ s: CGFloat) {
        p.reset()
        p.color = 0x55000000; c.drawCircle(cx, cy + s * 0.04, s * 0.36, p)
        p.color = AColor.WHITE; c.drawCircle(cx, cy, s * 0.34, p)
        p.style = .STROKE; p.strokeWidth = s * 0.07; p.color = 0xFF4B25B8; p.strokeCap = .round
        rect.set(cx - s * 0.2, cy - s * 0.2, cx + s * 0.2, cy + s * 0.2)
        c.drawArc(rect, 200, 120, false, p); c.drawArc(rect, 20, 120, false, p)
        p.style = .FILL
        for k in 0...1 {
            let a = (k == 0 ? 320.0 : 140.0) * Double.pi / 180
            let ax = cx + CGFloat(Float(cos(a))) * s * 0.2, ay = cy + CGFloat(Float(sin(a))) * s * 0.2
            c.drawCircle(ax, ay, s * 0.06, p)
        }
    }

    static func star4(_ c: ACanvas, _ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ color: Int) {
        path = CGMutablePath()
        path.moveTo(cx, cy - r)
        path.quadTo(cx, cy, cx + r, cy); path.quadTo(cx, cy, cx, cy + r)
        path.quadTo(cx, cy, cx - r, cy); path.quadTo(cx, cy, cx, cy - r)
        p.reset(); p.color = color
        c.drawPath(path, p)
    }

    // ------------------------------------------------------------------ CGContext entry points (y-down contexts)

    static func marble(_ cg: CGContext, _ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ colorId: Int, _ skin: Int) {
        marble(ACanvas(cg), cx, cy, r, colorId, skin)
    }
    static func block(_ cg: CGContext, _ x: CGFloat, _ y: CGFloat, _ s: CGFloat, _ colorId: Int, _ variant: Int, bumps: Bool = true, skin: Int = 0) {
        block(ACanvas(cg), x, y, s, colorId, variant, bumps: bumps, skin: skin)
    }
    static func cup(_ cg: CGContext, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ colorId: Int, _ hidden: Bool) {
        cup(ACanvas(cg), x, y, w, h, colorId, hidden)
    }
    static func text(_ cg: CGContext, _ s: String, _ cx: CGFloat, _ cy: CGFloat, _ size: CGFloat, _ fill: Int, _ stroke: Int, _ strokeW: CGFloat? = nil) {
        text(ACanvas(cg), s, cx, cy, size, fill, stroke, strokeW)
    }
    static func star4(_ cg: CGContext, _ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ color: Int) {
        star4(ACanvas(cg), cx, cy, r, color)
    }

    // ------------------------------------------------------------------ SwiftUI GraphicsContext entry points (cached sprites)

    /// Unit four-point star (radius 1) with the same quad construction as `star4`.
    static let unitStar4: Path = {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: -1))
        p.addQuadCurve(to: CGPoint(x: 1, y: 0), control: .zero); p.addQuadCurve(to: CGPoint(x: 0, y: 1), control: .zero)
        p.addQuadCurve(to: CGPoint(x: -1, y: 0), control: .zero); p.addQuadCurve(to: CGPoint(x: 0, y: -1), control: .zero)
        p.closeSubpath()
        return p
    }()

    /// Shading for an ARGB int (no Color allocation).
    @inline(__always) static func shading(_ argb: Int) -> GraphicsContext.Shading {
        .color(.sRGB, red: Double(AColor.red(argb)) / 255, green: Double(AColor.green(argb)) / 255,
               blue: Double(AColor.blue(argb)) / 255, opacity: Double(AColor.alpha(argb)) / 255)
    }

    static func star4(_ ctx: GraphicsContext, _ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ color: Int) {
        if r <= 0 { return }
        var c = ctx
        c.translateBy(x: cx, y: cy)
        c.scaleBy(x: r, y: r)
        c.fill(unitStar4, with: shading(color))
    }

    static func marble(_ ctx: GraphicsContext, _ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ colorId: Int, _ skin: Int) {
        let cache = SpriteCache.ui(ctx.environment.displayScale)
        let q = SpriteCache.quantize(r * 2, cache.pxPerUnit * 1.6) / 2
        ctx.draw(cache.marble(colorId, skin, q).image, in: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r))
    }

    static func block(_ ctx: GraphicsContext, _ x: CGFloat, _ y: CGFloat, _ s: CGFloat, _ colorId: Int, _ variant: Int, bumps: Bool = true, skin: Int = 0) {
        let cache = SpriteCache.ui(ctx.environment.displayScale)
        let q = SpriteCache.quantize(s, cache.pxPerUnit)
        ctx.draw(cache.block(colorId, variant, q, skin, bumps).image, in: CGRect(x: x, y: y, width: s, height: s))
    }

    static func cup(_ ctx: GraphicsContext, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ colorId: Int, _ hidden: Bool) {
        let cache = SpriteCache.ui(ctx.environment.displayScale)
        let k = SpriteCache.quantize(w, cache.pxPerUnit) / max(w, 0.0001)
        ctx.draw(cache.cup(colorId, hidden, w * k, h * k).image, in: CGRect(x: x, y: y, width: w, height: h))
    }

    static func text(_ ctx: GraphicsContext, _ s: String, _ cx: CGFloat, _ cy: CGFloat, _ size: CGFloat, _ fill: Int, _ stroke: Int, _ strokeW: CGFloat? = nil) {
        let cache = SpriteCache.ui(ctx.environment.displayScale)
        let q = SpriteCache.quantize(size, cache.pxPerUnit)
        let k = size / q
        cache.text(s, q, fill, stroke, (strokeW ?? size * 0.14) / k).draw(ctx, cx, cy, k)
    }

    static func badge(_ ctx: GraphicsContext, _ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ number: String, _ bg: Int) {
        let cache = SpriteCache.ui(ctx.environment.displayScale)
        let q = SpriteCache.quantize(r * 2, cache.pxPerUnit) / 2
        let b = cache.badge(number, bg, q)
        ctx.draw(b.image, in: CGRect(x: cx - r * SpriteCache.BADGE_BOX, y: cy - r * SpriteCache.BADGE_BOX,
                                     width: 2 * r * SpriteCache.BADGE_BOX, height: 2 * r * SpriteCache.BADGE_BOX))
    }

    static func bomb(_ ctx: GraphicsContext, _ cx: CGFloat, _ cy: CGFloat, _ s: CGFloat, _ fuse: CGFloat) {
        let cache = SpriteCache.ui(ctx.environment.displayScale)
        let q = SpriteCache.quantize(s, cache.pxPerUnit)
        ctx.draw(cache.bombIcon(q, fuse).image, in: CGRect(x: cx - s / 2, y: cy - s / 2, width: s, height: s))
    }
}

// MARK: - Sprites

/// A baked bitmap: the CGImage plus a ready SwiftUI `Image` for `GraphicsContext.draw(_:in:)`.
final class Sprite {
    let cg: CGImage
    let image: Image
    var width: Int { cg.width }
    var height: Int { cg.height }

    init(_ cg: CGImage) {
        self.cg = cg
        self.image = Image(decorative: cg, scale: 1).interpolation(.high).antialiased(true)
    }
}

/// A baked line of candy text; anchor and size in the cache's units.
struct TextSprite {
    let sprite: Sprite
    let anchorX: CGFloat, anchorY: CGFloat
    let width: CGFloat, height: CGFloat

    /// Draws the text centred at (cx, cy), scaled by k.
    func draw(_ ctx: GraphicsContext, _ cx: CGFloat, _ cy: CGFloat, _ k: CGFloat = 1) {
        ctx.draw(sprite.image, in: CGRect(x: cx - anchorX * k, y: cy - anchorY * k, width: width * k, height: height * k))
    }
}

/// Bitmap cache so frame rendering is just blits. `pxPerUnit` = device pixels per drawing unit.
final class SpriteCache {
    let pxPerUnit: CGFloat
    /// Extras (Features.colorBlindPatterns): bake the colour-blind symbol into marble, cup and block sprites
    /// (own sprite keys, so plain and symbol sprites never mix). Set by the game renderer.
    var symbols = false
    private var map: [Int64: Sprite] = [:]
    private var texts: [TextKey: TextSprite] = [:]

    private struct TextKey: Hashable {
        let s: String
        let size: Int, fill: Int, stroke: Int, strokeW: Int
    }

    init(_ pxPerUnit: CGFloat) { self.pxPerUnit = pxPerUnit }

    private func key(_ type: Int, _ a: Int, _ b: Int, _ size: Int) -> Int64 {
        (Int64(type) << 48) | ((Int64(a) & 0xFFF) << 32) | ((Int64(b) & 0xFFFF) << 16) | (Int64(size) & 0xFFFF)
    }

    private func make(_ w: Int, _ h: Int, _ draw: (ACanvas) -> Void) -> Sprite {
        Sprite(Bake.image(max(1, w), max(1, h), draw))
    }

    @inline(__always) private func getOrPut(_ k: Int64, _ build: () -> Sprite) -> Sprite {
        if let s = map[k] { return s }
        let s = build()
        map[k] = s
        return s
    }

    private let SS: CGFloat = 1.6 // supersampling for crisp marbles

    func marble(_ colorId: Int, _ skin: Int, _ radiusUnits: CGFloat) -> Sprite {
        let px = max(Int(radiusUnits * 2 * pxPerUnit * SS), 8)
        let sym = symbols
        return getOrPut(key(sym ? 31 : 1, colorId, skin, px)) {
            make(px, px) {
                MachineArt.marble($0, CGFloat(px) / 2, CGFloat(px) / 2, CGFloat(px) / 2 - 0.5, colorId, skin)
                if sym { ColorBlindArt.onMarble($0, colorId, CGFloat(px) / 2, CGFloat(px) / 2, CGFloat(px) / 2 - 0.5) }
            }
        }
    }

    func marbleBody(_ colorId: Int, _ skin: Int, _ radiusUnits: CGFloat) -> Sprite {
        let px = max(Int(radiusUnits * 2 * pxPerUnit * SS), 8)
        return getOrPut(key(4, colorId, skin, px)) {
            make(px, px) { MachineArt.marbleBody($0, CGFloat(px) / 2, CGFloat(px) / 2, CGFloat(px) / 2 - 0.5, colorId, skin) }
        }
    }

    func marbleGloss(_ colorId: Int, _ skin: Int, _ radiusUnits: CGFloat) -> Sprite {
        let px = max(Int(radiusUnits * 2 * pxPerUnit * SS), 8)
        return getOrPut(key(5, colorId, skin, px)) {
            make(px, px) { MachineArt.marbleGloss($0, CGFloat(px) / 2, CGFloat(px) / 2, CGFloat(px) / 2 - 0.5, colorId, skin) }
        }
    }

    /// Soft shadow sprite; drawn at 2x the marble radius footprint.
    func shadow(_ radiusUnits: CGFloat) -> Sprite {
        let px = max(Int(radiusUnits * 3 * pxPerUnit), 8)
        return getOrPut(key(6, 0, 0, px)) {
            make(px, px) { MachineArt.shadow($0, CGFloat(px) / 2, CGFloat(px) / 2, CGFloat(px) * 0.36, CGFloat(px) * 0.24, 150) }
        }
    }

    func block(_ colorId: Int, _ variant: Int, _ sizeUnits: CGFloat, _ skin: Int = 0, _ open: Bool = true) -> Sprite {
        let px = max(Int(sizeUnits * pxPerUnit), 8)
        let sym = symbols
        return getOrPut(key(sym ? 32 : 2, colorId + variant * 100 + (open ? 1000 : 0), skin, px)) {
            make(px, px) {
                MachineArt.jelly($0, 0, 0, CGFloat(px), colorId, variant, open, skin)
                if sym { ColorBlindArt.onBlock($0, colorId, variant, CGFloat(px), open) }
            }
        }
    }

    /// Marble with its soft contact shadow baked in; draw into a box of ±1.35 r around the centre.
    func marbleShadowed(_ colorId: Int, _ skin: Int, _ radiusUnits: CGFloat) -> Sprite {
        let px = max(Int(radiusUnits * 2.7 * pxPerUnit * SS), 8)
        let sym = symbols
        return getOrPut(key(sym ? 39 : 9, colorId, skin, px)) {
            make(px, px) { c in
                let r = CGFloat(px) / 2.7
                MachineArt.shadow(c, CGFloat(px) / 2 + r * 0.12, CGFloat(px) / 2 + r * 0.55, r * 0.85, r * 0.42, 120)
                MachineArt.marble(c, CGFloat(px) / 2, CGFloat(px) / 2, r - 0.5, colorId, skin)
                if sym { ColorBlindArt.onMarble(c, colorId, CGFloat(px) / 2, CGFloat(px) / 2, r - 0.5) }
            }
        }
    }

    func cup(_ colorId: Int, _ hidden: Bool, _ wUnits: CGFloat, _ hUnits: CGFloat) -> Sprite {
        let w = Int(wUnits * pxPerUnit), h = Int(hUnits * pxPerUnit)
        let sym = symbols
        return getOrPut(key(sym ? 33 : 3, colorId, hidden ? 1 : 0, w * 7 + h)) {
            make(w, h) {
                MachineArt.puck($0, 0, 0, CGFloat(w), CGFloat(h), colorId, hidden)
                if sym && !hidden { ColorBlindArt.onCup($0, colorId, 0, 0, CGFloat(w), CGFloat(h)) }
            }
        }
    }

    func gear(_ radiusUnits: CGFloat, _ tint: Int) -> Sprite {
        let px = max(Int(radiusUnits * 2 * pxPerUnit * 1.2), 8)
        return getOrPut(key(7, 0, tint & 0xFFFF, px)) {
            make(px, px) { MachineArt.gear($0, CGFloat(px) / 2, CGFloat(px) / 2, CGFloat(px) / 2 * 0.92, 12, tint) }
        }
    }

    func cradle(_ lenUnits: CGFloat, _ widUnits: CGFloat) -> Sprite {
        let w = max(Int(lenUnits * pxPerUnit * 1.4), 4), h = max(Int(widUnits * pxPerUnit * 1.4), 4)
        return getOrPut(key(8, w, h, 0)) {
            make(w, h) { MachineArt.cradle($0, CGFloat(w) / 2, CGFloat(h) / 2, CGFloat(w) - 1, CGFloat(h) - 1) }
        }
    }

    /// Belt socket; draw into a box of ±r around the slot centre.
    func socket(_ radiusUnits: CGFloat) -> Sprite {
        let px = max(Int(radiusUnits * 2 * pxPerUnit * SS), 8)
        return getOrPut(key(20, 0, 0, px)) {
            make(px, px) { MachineArt.socket($0, CGFloat(px) / 2, CGFloat(px) / 2, CGFloat(px) / 2 - 0.5) }
        }
    }

    /// Roller hub; draw into a box of ±r around its centre and rotate the canvas.
    func hub(_ radiusUnits: CGFloat, _ tint: Int) -> Sprite {
        let px = max(Int(radiusUnits * 2 * pxPerUnit * SS), 8)
        return getOrPut(key(21, 0, tint & 0xFFFF, px)) {
            make(px, px) { MachineArt.hub($0, CGFloat(px) / 2, CGFloat(px) / 2, CGFloat(px) / 2 - 0.5, tint) }
        }
    }

    /// Overlay sprite: type ids 10..
    func overlay(_ type: Int, _ sizeUnits: CGFloat, _ arg: Int = 0) -> Sprite {
        let px = max(Int(sizeUnits * pxPerUnit), 8)
        return getOrPut(key(type, arg, 0, px)) {
            make(px, px) { c in
                let s = CGFloat(px)
                switch type {
                case SpriteCache.OV_CHAINS: Painter.chains(c, 0, 0, s); Painter.padlock(c, s / 2, s / 2, s * 0.42)
                case SpriteCache.OV_CAGE: Painter.cage(c, 0, 0, s)
                case SpriteCache.OV_CRATE: Painter.crate(c, 0, 0, s)
                case SpriteCache.OV_ICE: Painter.ice(c, 0, 0, s, false)
                case SpriteCache.OV_ICE_CRACKED: Painter.ice(c, 0, 0, s, true)
                case SpriteCache.OV_KEY: Painter.key(c, s / 2, s * 0.44, s * 0.6)
                case SpriteCache.OV_ARROW: Painter.arrowIcon(c, s / 2, s * 0.45, s * 0.7, arg)
                case SpriteCache.OV_BOMB: Painter.bomb(c, s / 2, s * 0.48, s * 0.9, 1)
                case SpriteCache.OV_BUCKET: Painter.bucket(c, s / 2, s * 0.46, s * 0.75, Painter.colorOf(arg))
                case SpriteCache.OV_SWITCH: Painter.switchIcon(c, s / 2, s * 0.45, s * 0.7)
                default: break
                }
            }
        }
    }

    // ---- iOS additions: the Kotlin renderer draws these live each frame; here they are baked once and blitted.

    /// `Painter.badge` sprite; draw into a box of ±BADGE_BOX·r around the centre.
    func badge(_ number: String, _ bg: Int, _ rUnits: CGFloat) -> Sprite {
        let rpx = rUnits * pxPerUnit
        let px = max(Int((rpx * 2 * SpriteCache.BADGE_BOX).rounded(.up)), 8)
        let k = TextKey(s: "badge:" + number, size: Int((rpx * 16).rounded()), fill: bg, stroke: 0, strokeW: 0)
        if let t = texts[k] { return t.sprite }
        let sprite = make(px, px) { c in
            Painter.badge(c, CGFloat(px) / 2, CGFloat(px) / 2, CGFloat(px) / 2 / SpriteCache.BADGE_BOX, number, bg)
        }
        texts[k] = TextSprite(sprite: sprite, anchorX: 0, anchorY: 0, width: 0, height: 0)
        return sprite
    }

    /// `Painter.badge` sprite keyed by number (no string work on a cache hit); `BADGE_X2` draws "x2".
    func badge(_ number: Int, _ bg: Int, _ rUnits: CGFloat) -> Sprite {
        let rpx = rUnits * pxPerUnit
        let px = max(Int((rpx * 2 * SpriteCache.BADGE_BOX).rounded(.up)), 8)
        return getOrPut(key(23, number & 0xFFF, bg & 0xFFFF, px)) {
            let label = number == SpriteCache.BADGE_X2 ? "x2" : String(number)
            return make(px, px) { c in
                Painter.badge(c, CGFloat(px) / 2, CGFloat(px) / 2, CGFloat(px) / 2 / SpriteCache.BADGE_BOX, label, bg)
            }
        }
    }

    /// Badge label sentinel for "x2".
    static let BADGE_X2 = -2

    /// `Painter.bomb` sprite (fuse quantised to 1/8) in a box of side s.
    func bombIcon(_ sizeUnits: CGFloat, _ fuse: CGFloat) -> Sprite {
        let px = max(Int(sizeUnits * pxPerUnit), 8)
        let f = Int((min(max(fuse, 0), 1) * 8).rounded())
        return getOrPut(key(22, f, 0, px)) {
            make(px, px) { c in
                let s = CGFloat(px)
                Painter.bomb(c, s / 2, s / 2, s, CGFloat(f) / 8)
            }
        }
    }

    /// `Painter.text` sprite: centred candy text of the given size (all in units).
    func text(_ s: String, _ sizeUnits: CGFloat, _ fill: Int, _ stroke: Int, _ strokeUnits: CGFloat) -> TextSprite {
        let k = TextKey(s: s, size: Int((sizeUnits * 64).rounded()), fill: fill, stroke: stroke, strokeW: Int((strokeUnits * 64).rounded()))
        if let t = texts[k] { return t }
        if texts.count > 400 { texts.removeAll() }
        let size = sizeUnits * pxPerUnit
        let sw = strokeUnits * pxPerUnit
        let font = GameFonts.ctLilita(size)
        let (glyphs, width) = TextPaths.line(s, font)
        let ascent = CTFontGetAscent(font), descent = CTFontGetDescent(font)
        let baseline = -(descent - ascent) / 2
        var box = glyphs.boundingBoxOfPath
        if box.isNull || box.isEmpty { box = CGRect(x: 0, y: -ascent, width: max(width, 1), height: ascent + descent) }
        box = box.offsetBy(dx: -width / 2, dy: baseline).insetBy(dx: -(sw / 2 + 2), dy: -(sw / 2 + 2))
        let w = Int(box.width.rounded(.up)), h = Int(box.height.rounded(.up))
        let ax = -box.minX, ay = -box.minY
        let sprite = make(w, h) { c in Painter.text(c, s, ax, ay, size, fill, stroke, sw) }
        let t = TextSprite(sprite: sprite, anchorX: ax / pxPerUnit, anchorY: ay / pxPerUnit,
                           width: CGFloat(w) / pxPerUnit, height: CGFloat(h) / pxPerUnit)
        texts[k] = t
        return t
    }

    func clear() { map.removeAll(); texts.removeAll() }

    static let OV_CHAINS = 10, OV_CAGE = 11, OV_CRATE = 12, OV_ICE = 13, OV_ICE_CRACKED = 14
    static let OV_KEY = 15, OV_ARROW = 16, OV_BOMB = 17, OV_BUCKET = 18, OV_SWITCH = 19

    /// Half-size of a badge sprite box in badge radii.
    static let BADGE_BOX: CGFloat = 1.5

    // ---- shared cache for SwiftUI screens (units = points)

    private static var uiCache: SpriteCache?

    /// Cache whose unit is one point at the given display scale (used by the `GraphicsContext` painters and `ball`).
    static func ui(_ displayScale: CGFloat) -> SpriteCache {
        let s = displayScale >= 1 ? displayScale : DisplayScale.value
        if let c = uiCache, c.pxPerUnit == s {
            if c.map.count > 600 { c.map.removeAll() }
            return c
        }
        let c = SpriteCache(s)
        uiCache = c
        return c
    }

    /// Rounds a size up to a multiple of 4 device pixels so animated sizes reuse a handful of sprites.
    static func quantize(_ units: CGFloat, _ pxPerUnit: CGFloat) -> CGFloat {
        let px = max(4, (units * pxPerUnit / 4).rounded(.up) * 4)
        return px / pxPerUnit
    }
}
