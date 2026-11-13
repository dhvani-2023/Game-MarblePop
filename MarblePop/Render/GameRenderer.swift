import SwiftUI
import GameKit

/// "Candy Glass Machine" playground (see PLAYGROUND_GRAPHICS_PLAN.md), port of render/GameRenderer.kt: the world sky
/// with a candy skyline, a glass board set in a candy rim that flows into a hopper and pipe, a candy belt housing
/// with a dark track, rollers and a fill gauge, and a frosted tray cabinet with glass lanes.
/// Static art is baked into three layers (backdrop / board / base) at device scale so the scene can assemble with a
/// springy intro; everything moving is a cached sprite blit or a handful of cheap primitives.
///
/// iOS: `widthPx` / `heightPx` are the SwiftUI `Canvas` size in points; `scale` is points per world unit (the touch
/// mapping is `world = point / scale`). Draw every frame with `Canvas { ctx, _ in renderer.draw(ctx) }`.
final class GameRenderer {
    private let engine: GameEngine
    private let theme: GameTheme
    private let skin: Int
    let widthPx: CGFloat
    let heightPx: CGFloat

    private let l: GameLayout
    /// Points per world unit.
    let scale: CGFloat
    /// Device pixels per point used for baking.
    let displayScale: CGFloat
    /// Device pixels per world unit.
    let pxPerUnit: CGFloat
    let sprites: SpriteCache
    private let wDev: Int
    private let hDev: Int

    // ---------------- layout (world units)
    private let worldW: CGFloat, worldH: CGFloat, cx: CGFloat, marbleR: CGFloat, cell: CGFloat
    private let gridTop: CGFloat, gridBottom: CGFloat, gridLeft: CGFloat, gridRight: CGFloat
    private let funnelH: CGFloat, spoutTop: CGFloat, spoutHalf: CGFloat, gateFloor: CGFloat
    private let dishTop: CGFloat, dishLeft: CGFloat, dishRight: CGFloat
    private let beltR: CGFloat, beltCy: CGFloat, xl: CGFloat, xr: CGFloat
    private let colW: CGFloat, cupW: CGFloat, cupH: CGFloat, trayTop: CGFloat
    private let dimpleDx: [CGFloat], dimpleDy: CGFloat

    // ---------------- palette
    private let frame: Int
    private let frameDark: Int
    private let sky: [Int]
    private let silhouette: Int
    private let glassTop: Int
    private let glassMid: Int
    private let glassBottom: Int
    private let wellCol: Int
    private let trackTop: Int
    private let trackBottom: Int

    private let pad: CGFloat = 14
    private let rimW: CGFloat = 10
    private let boardTop: CGFloat
    private let boardLayerTop: CGFloat
    private let boardLayerBottom: CGFloat
    private let baseTop: CGFloat
    private let islandR: CGFloat
    private let hubR: CGFloat
    private let gx0: CGFloat
    private let gx1: CGFloat
    private let gh: CGFloat

    private var backdrop: Sprite?
    private var board: Sprite?
    private var base: Sprite?

    // per-frame shadings, created once
    private let vignette: GraphicsContext.Shading
    private let gaugeGreen: GraphicsContext.Shading
    private let gaugeYellow: GraphicsContext.Shading
    private let gaugeRed: GraphicsContext.Shading
    private let fogTop: CGFloat
    private let fogShading: GraphicsContext.Shading
    private let rivetDark = Painter.shading(0xFF0B0822)
    private let rivetLight = Painter.shading(0xFFB9C2EE)
    private let gaugeGloss = Painter.shading(0x8CFFFFFF)
    private var gaugeCount = -1
    private var gaugeLabel = ""
    private var gaugeSprite: TextSprite?

    /// Unit shard triangle for particles.
    private static let unitShard: Path = {
        var p = Path()
        p.move(to: CGPoint(x: 0, y: -1)); p.addLine(to: CGPoint(x: 0.6, y: 0.5)); p.addLine(to: CGPoint(x: -0.6, y: 0.5))
        p.closeSubpath()
        return p
    }()

    /// Twinkling sparkles in the sky: x, y, size, phase.
    private let sparkles: [CGFloat]

    convenience init(_ engine: GameEngine, _ theme: GameTheme, _ skin: Int, _ widthPx: CGFloat, _ heightPx: CGFloat) {
        self.init(engine: engine, theme: theme, skin: skin, widthPx: widthPx, heightPx: heightPx)
    }

    convenience init(_ engine: GameEngine, _ theme: GameTheme, _ skin: Int, _ widthPx: Int, _ heightPx: Int) {
        self.init(engine: engine, theme: theme, skin: skin, widthPx: CGFloat(widthPx), heightPx: CGFloat(heightPx))
    }

    convenience init(engine: GameEngine, theme: GameTheme, skin: Int, widthPx: Int, heightPx: Int) {
        self.init(engine: engine, theme: theme, skin: skin, widthPx: CGFloat(widthPx), heightPx: CGFloat(heightPx))
    }

    /// `symbols`: Extras (Features.colorBlindPatterns) colour-blind symbols baked into marble, cup and block sprites.
    init(engine: GameEngine, theme: GameTheme, skin: Int, widthPx: CGFloat, heightPx: CGFloat, displayScale: CGFloat = DisplayScale.value,
         symbols: Bool = false) {
        self.engine = engine
        self.theme = theme
        self.skin = skin
        self.widthPx = widthPx
        self.heightPx = heightPx
        let l = engine.layout
        self.l = l
        self.displayScale = displayScale
        worldW = CGFloat(l.worldW); worldH = CGFloat(l.worldH); cx = CGFloat(l.cx); marbleR = CGFloat(l.marbleR); cell = CGFloat(l.cell)
        gridTop = CGFloat(l.gridTop); gridBottom = CGFloat(l.gridBottom); gridLeft = CGFloat(l.gridLeft); gridRight = CGFloat(l.gridRight)
        funnelH = CGFloat(l.funnelH); spoutTop = CGFloat(l.spoutTop); spoutHalf = CGFloat(l.spoutHalf); gateFloor = CGFloat(l.gateFloor)
        dishTop = CGFloat(l.dishTop); dishLeft = CGFloat(l.dishLeft); dishRight = CGFloat(l.dishRight)
        beltR = CGFloat(l.beltR); beltCy = CGFloat(l.beltCy); xl = CGFloat(l.xl); xr = CGFloat(l.xr)
        colW = CGFloat(l.colW); cupW = CGFloat(l.cupW); cupH = CGFloat(l.cupH); trayTop = CGFloat(l.trayTop)
        dimpleDx = l.dimpleDx.map { CGFloat($0) }; dimpleDy = CGFloat(l.dimpleDy)

        scale = widthPx / worldW
        wDev = max(1, Int((widthPx * displayScale).rounded()))
        hDev = max(1, Int((heightPx * displayScale).rounded()))
        pxPerUnit = CGFloat(wDev) / worldW
        sprites = SpriteCache(pxPerUnit)
        sprites.symbols = symbols

        frame = theme.wall
        frameDark = theme.wallDark
        sky = theme.sky.count == 6 ? theme.sky
            : [theme.bgTop, Col.mix(theme.bgTop, theme.bgBottom, 0.5), theme.bgBottom, AColor.WHITE, AColor.WHITE, theme.wallDark]
        silhouette = sky[5]
        glassTop = Col.lighten(theme.wallLight, 0.9)
        glassMid = Col.lighten(theme.wallLight, 0.8)
        glassBottom = Col.lighten(theme.wallLight, 0.66)
        wellCol = Col.mix(glassMid, 0xFF5A5F8A, 0.13)
        trackTop = Col.darken(Col.mix(0xFF2A1F6B, frameDark, 0.15), 0.12)
        trackBottom = Col.darken(Col.mix(0xFF16113E, frameDark, 0.1), 0.05)

        boardTop = gridTop - pad
        boardLayerTop = boardTop - rimW - 8
        boardLayerBottom = gateFloor + 26
        baseTop = dishTop - 16
        islandR = beltR - marbleR - 7
        hubR = islandR * 0.95
        gx0 = xl + islandR * 1.15
        gx1 = xr - islandR * 1.15
        gh = islandR * 1.2

        vignette = .radialGradient(
            Gradient(stops: [.init(color: Color(argb: 0x00FFB04A), location: 0), .init(color: Color(argb: 0x00FFB04A), location: 0.68),
                             .init(color: Color(argb: 0xAAFF8A3D), location: 1)]),
            center: CGPoint(x: worldW / 2, y: worldH / 2), startRadius: 0, endRadius: worldH * 0.65)
        let g0 = beltCy - gh / 2, g1 = beltCy + gh / 2
        gaugeGreen = .linearGradient(Gradient(colors: [Color(argb: 0xFF8EF08A), Color(argb: 0xFF22A447)]),
                                     startPoint: CGPoint(x: 0, y: g0), endPoint: CGPoint(x: 0, y: g1))
        gaugeYellow = .linearGradient(Gradient(colors: [Color(argb: 0xFFFFE58A), Color(argb: 0xFFF0A000)]),
                                      startPoint: CGPoint(x: 0, y: g0), endPoint: CGPoint(x: 0, y: g1))
        gaugeRed = .linearGradient(Gradient(colors: [Color(argb: 0xFFFFA07A), Color(argb: 0xFFE8323F)]),
                                   startPoint: CGPoint(x: 0, y: g0), endPoint: CGPoint(x: 0, y: g1))
        fogTop = CGFloat(l.cupTop(0.95))
        fogShading = .linearGradient(
            Gradient(stops: [.init(color: Color(argbInt: Col.alpha(glassBottom, 0)), location: 0),
                             .init(color: Color(argbInt: Col.alpha(glassBottom, 70)), location: 0.55),
                             .init(color: Color(argbInt: Col.alpha(glassBottom, 175)), location: 1)]),
            startPoint: CGPoint(x: 0, y: fogTop), endPoint: CGPoint(x: 0, y: worldH))

        do {
            let rnd = KotlinRandom(intSeed: 11)
            let n = 7
            var a = [CGFloat](repeating: 0, count: n * 4)
            for i in 0..<n {
                let left = i % 2 == 0
                a[i * 4] = left ? 14 + CGFloat(rnd.nextFloat()) * 70 : worldW - 14 - CGFloat(rnd.nextFloat()) * 70
                a[i * 4 + 1] = gridTop + CGFloat(rnd.nextFloat()) * (dishTop - gridTop - 40)
                a[i * 4 + 2] = 5 + CGFloat(rnd.nextFloat()) * 6
                a[i * 4 + 3] = CGFloat(rnd.nextFloat()) * 6.28
            }
            sparkles = a
        }

        var colors = Set<Int>()
        for b in engine.spec.blocks { colors.insert(b.color) }
        for col in engine.spec.tray { for c in col { colors.insert(c.color) } }
        for c in colors {
            _ = sprites.marbleShadowed(c, skin, marbleR)
            _ = sprites.marble(c, skin, marbleR * 0.9)
            _ = sprites.block(c, 0, cell, skin, true); _ = sprites.block(c, 0, cell, skin, false)
            _ = sprites.cup(c, false, cupW, cupH)
        }
        _ = sprites.marbleShadowed(MarbleColors.RAINBOW, skin, marbleR)
        _ = sprites.socket(marbleR * 1.02)
        _ = sprites.hub(hubR, frame)
        backdrop = layer(0, worldH) { self.drawBackdrop($0) }
        board = layer(boardLayerTop, boardLayerBottom) { self.drawBoard($0) }
        base = layer(baseTop, worldH) { self.drawBase($0) }
    }

    private func layer(_ top: CGFloat, _ bottom: CGFloat, _ draw: (ACanvas) -> Void) -> Sprite {
        let h = min(max(Int((bottom - top) * pxPerUnit), 1), hDev)
        let ppu = pxPerUnit
        return Sprite(Bake.image(wDev, h) { c in
            c.scale(ppu, ppu)
            c.translate(0, -top)
            draw(c)
        })
    }

    func release() {
        sprites.clear()
        backdrop = nil; board = nil; base = nil
    }

    // ================================================================ static art

    private func drawBackdrop(_ c: ACanvas) {
        let w = worldW, h = worldH
        let p = Paint()
        p.shader = Shader.linear(0, 0, 0, h, [sky[0], sky[1], sky[2]], [0, 0.55, 1])
        c.drawRect(0, 0, w, h, p)
        p.shader = Shader.radial(w * 0.12, h * 0.2, w * 0.75, Col.alpha(sky[3], 120), Col.alpha(sky[3], 0))
        c.drawRect(0, 0, w, h, p)
        p.shader = Shader.radial(w * 0.95, h * 0.58, w * 0.62, Col.alpha(sky[4], 100), Col.alpha(sky[4], 0))
        c.drawRect(0, 0, w, h, p)
        p.shader = nil
        // soft bokeh
        let rnd = KotlinRandom(intSeed: 5)
        for _ in 0..<12 {
            let x = CGFloat(rnd.nextFloat()) * w; let y = CGFloat(rnd.nextFloat()) * h * 0.85; let r = 26 + CGFloat(rnd.nextFloat()) * 70
            p.shader = Shader.radial(x, y, r, Col.alpha(AColor.WHITE, 30 + rnd.nextInt(30)), 0x00FFFFFF)
            c.drawCircle(x, y, r, p)
        }
        p.shader = nil
        // candy factory skyline peeking above the tray cabinet
        let horizon = dishTop + 40
        skyline(c, horizon, 21, 110, 230, Col.alpha(Col.lighten(silhouette, 0.3), 95), false)
        skyline(c, horizon, 8, 60, 150, Col.alpha(silhouette, 165), true)
        // haze at the horizon
        p.shader = Shader.linear(0, horizon - 160, 0, horizon, Col.alpha(sky[2], 0), Col.alpha(Col.lighten(sky[2], 0.3), 120))
        c.drawRect(0, horizon - 160, w, horizon, p); p.shader = nil
        for _ in 0..<10 {
            Painter.star4(c, CGFloat(rnd.nextFloat()) * w, CGFloat(rnd.nextFloat()) * h * 0.7, 4 + CGFloat(rnd.nextFloat()) * 5, Col.alpha(AColor.WHITE, 110))
        }
    }

    private func skyline(_ c: ACanvas, _ horizon: CGFloat, _ seed: Int, _ minH: CGFloat, _ maxH: CGFloat, _ color: Int, _ windows: Bool) {
        let rnd = KotlinRandom(intSeed: seed)
        let sk = CGMutablePath()
        var lights: [RectF] = []
        var x: CGFloat = -20
        while x < worldW + 20 {
            let bw = 44 + CGFloat(rnd.nextFloat()) * 56
            let bh = minH + CGFloat(rnd.nextFloat()) * (maxH - minH)
            let top = horizon - bh
            switch rnd.nextInt(4) {
            case 0: // flat roof + chimney
                sk.addRectF(x, top, x + bw, horizon)
                sk.addRoundRect(RectF(x + bw * 0.62, top - bh * 0.28, x + bw * 0.82, top + 4), 4, 4)
            case 1: // dome
                sk.addRectF(x, top + bw * 0.3, x + bw, horizon)
                sk.addOval(RectF(x, top - bw * 0.2, x + bw, top + bw * 0.8))
            case 2: // lollipop tower
                sk.addRectF(x + bw * 0.1, top + bh * 0.35, x + bw * 0.9, horizon)
                sk.addRectF(x + bw * 0.44, top, x + bw * 0.56, top + bh * 0.4)
                sk.addCircle(x + bw / 2, top, bw * 0.3)
            default: // stepped roof
                sk.addRectF(x, top + bh * 0.2, x + bw, horizon)
                sk.addRoundRect(RectF(x + bw * 0.2, top, x + bw * 0.8, top + bh * 0.3), 6, 6)
            }
            if windows {
                let rows = min(Int((bh * 0.6) / 26), 4)
                for r in 0..<max(rows, 0) where rnd.nextFloat() < 0.6 {
                    let wx = x + bw * (0.25 + CGFloat(rnd.nextFloat()) * 0.4)
                    let wy = horizon - bh * 0.55 + CGFloat(r) * 26
                    lights.append(RectF(wx, wy, wx + 9, wy + 12))
                }
            }
            x += bw + 4 + CGFloat(rnd.nextFloat()) * 16
        }
        let p = Paint()
        p.color = color
        c.drawPath(sk, p)
        p.color = Col.alpha(sky[3], 110)
        for r in lights { c.drawRoundRect(r, 3, 3, p) }
    }

    /// Board outline: every active cell as a rounded rect (true circular corners), bridges between
    /// neighbouring cells so their rounded corners never leave notches, and the hopper + spout.
    private func boardShape(_ grow: CGFloat, _ radius: CGFloat) -> CGPath {
        let shape = CGMutablePath()
        let g = pad + grow
        for r in 0..<l.gridH {
            for col in 0..<l.gridW {
                if !l.active(col, r) { continue }
                let x = CGFloat(l.cellLeft(col)); let y = CGFloat(l.cellTop(Float(r)))
                shape.addRoundRect(RectF(x - g, y - g, x + cell + g, y + cell + g), radius, radius)
                if l.active(col + 1, r) { shape.addRectF(x + cell / 2, y - g, x + cell * 1.5, y + cell + g) }
                if l.active(col, r + 1) { shape.addRectF(x - g, y - cell / 2, x + cell + g, y + cell / 2) }
                if l.active(col + 1, r + 1) && l.active(col + 1, r) && l.active(col, r + 1) {
                    shape.addRectF(x + cell / 2, y - cell / 2, x + cell * 1.5, y + cell / 2)
                }
            }
        }
        let sl = cx - spoutHalf - 10 - grow; let sr = cx + spoutHalf + 10 + grow
        let bottom = gateFloor + 2 + grow * 0.4
        let left = gridLeft - g; let right = gridRight + g
        let hopper = CGMutablePath()
        hopper.moveTo(left, gridBottom - cell * 0.5)
        hopper.lineTo(right, gridBottom - cell * 0.5)
        hopper.lineTo(right, gridBottom)
        hopper.cubicTo(right, gridBottom + funnelH * 0.55, sr + 10, spoutTop - funnelH * 0.25, sr, spoutTop)
        hopper.lineTo(sr, bottom)
        hopper.lineTo(sl, bottom)
        hopper.lineTo(sl, spoutTop)
        hopper.cubicTo(sl - 10, spoutTop - funnelH * 0.25, left, gridBottom + funnelH * 0.55, left, gridBottom)
        hopper.close()
        shape.addPath(hopper)
        return shape.normalized(using: .winding)
    }

    /// Applies rounded corners for real (so the result also works as a clip).
    private func rounded(_ src: CGPath, _ radius: CGFloat) -> CGPath { PathFx.corner(src, radius) }

    private func drawBoard(_ c: ACanvas) {
        // concave steps of the staircase are softened by the corner effect; convex corners are true arcs
        let outer = rounded(boardShape(rimW, 22 + rimW), 14)
        let inner = rounded(boardShape(0, 22), 22)
        let bx0 = gridLeft - pad; let bx1 = gridRight + pad
        let p = Paint()
        var path = CGMutablePath()
        var dst = RectF()
        // drop shadow + depth side
        p.color = Col.alpha(silhouette, 120); p.blurRadius = 14
        c.save(); c.translate(0, 16); c.drawPath(outer, p); c.restore()
        p.blurRadius = 0
        p.color = frameDark
        c.save(); c.translate(0, 9); c.drawPath(outer, p); c.restore()
        // candy rim
        p.shader = Shader.linear(0, boardTop - rimW, 0, gateFloor, [Col.lighten(frame, 0.32), frame, Col.darken(frame, 0.08)], [0, 0.4, 1])
        c.drawPath(outer, p); p.shader = nil
        p.style = .STROKE
        c.save(); c.clipPath(outer)
        p.strokeWidth = 4; p.color = 0x99FFFFFF
        c.save(); c.translate(0, 3); c.drawPath(outer, p); c.restore()
        c.restore()
        p.strokeWidth = 2.5; p.color = Col.alpha(Col.darken(frameDark, 0.3), 150); c.drawPath(outer, p)
        p.style = .FILL
        // glass interior
        p.shader = Shader.linear(0, boardTop, 0, gateFloor, [glassTop, glassMid, glassBottom], [0, 0.55, 1])
        c.drawPath(inner, p); p.shader = nil
        c.save(); c.clipPath(inner)
        // diagonal glass streaks
        let bh = gateFloor - boardTop
        for (k, a) in [(0.12, 40), (0.3, 26), (0.68, 22)] as [(CGFloat, Int)] {
            let sx = bx0 + (bx1 - bx0) * k
            path = CGMutablePath()
            path.moveTo(sx, gateFloor); path.lineTo(sx + 34, gateFloor)
            path.lineTo(sx + 34 + bh * 0.45, boardTop); path.lineTo(sx + bh * 0.45, boardTop); path.close()
            p.color = Col.alpha(AColor.WHITE, a); c.drawPath(path, p)
        }
        // hopper deepens toward the spout
        p.shader = Shader.radial(cx, spoutTop, funnelH + 60, Col.alpha(frame, 64), Col.alpha(frame, 0))
        c.drawRect(bx0 - rimW, gridBottom, bx1 + rimW, gateFloor + 10, p); p.shader = nil
        // dotted guide lanes from each exit into the spout
        p.style = .STROKE
        p.color = Col.alpha(AColor.WHITE, 170)
        let dotPaint = Paint()
        dotPaint.color = p.color
        for col in 0..<l.gridW {
            if !l.active(col, 0) { continue }
            let x = CGFloat(l.cellCenterX(col))
            let dots = PathFx.dotsAlongQuad(CGPoint(x: x, y: gridBottom + 28), CGPoint(x: x, y: spoutTop - funnelH * 0.3),
                                            CGPoint(x: cx, y: spoutTop - 4), advance: 13, radius: 2.6)
            c.drawPath(dots, dotPaint)
        }
        // inner shadow (glass sits inside the rim)
        p.strokeWidth = 22; p.color = Col.alpha(frame, 85); p.blurRadius = 9
        c.save(); c.translate(0, 7); c.drawPath(inner, p); c.restore()
        p.blurRadius = 0
        c.restore()
        p.strokeWidth = 2; p.color = Col.alpha(frameDark, 90); c.drawPath(inner, p)
        // exit chevrons
        p.strokeWidth = 4.5; p.strokeCap = .round; p.strokeJoin = .round
        for col in 0..<l.gridW {
            if !l.active(col, 0) { continue }
            let x = CGFloat(l.cellCenterX(col)); let y = gridBottom + 10
            path = CGMutablePath(); path.moveTo(x - 9, y - 3); path.lineTo(x, y + 4); path.lineTo(x + 9, y - 3)
            p.color = Col.alpha(frameDark, 60); c.save(); c.translate(0, 2); c.drawPath(path, p); c.restore()
            p.color = AColor.WHITE; c.drawPath(path, p)
        }
        p.style = .FILL; p.strokeCap = .butt
        // recessed cell wells
        for r in 0..<l.gridH {
            for col in 0..<l.gridW {
                if !l.active(col, r) { continue }
                let x = CGFloat(l.cellLeft(col)); let y = CGFloat(l.cellTop(Float(r)))
                let rr = cell * 0.23
                dst.set(x + cell * 0.065, y + cell * 0.065, x + cell * 0.935, y + cell * 0.935)
                p.color = 0xCCFFFFFF; dst.offset(0, 2.5); c.drawRoundRect(dst, rr, rr, p); dst.offset(0, -2.5)
                p.color = wellCol; c.drawRoundRect(dst, rr, rr, p)
                c.save(); path = CGMutablePath(); path.addRoundRect(dst, rr, rr); c.clipPath(path)
                p.shader = Shader.linear(0, dst.top, 0, dst.top + cell * 0.3, Col.alpha(Col.darken(frameDark, 0.2), 70), Col.alpha(frameDark, 0))
                c.drawRect(dst, p); p.shader = nil
                c.restore()
            }
        }
        // glass pipe with candy collars
        let sl = cx - spoutHalf - 3; let sr = cx + spoutHalf + 3
        dst.set(sl, spoutTop - 10, sr, gateFloor + 4)
        p.shader = Shader.linear(sl, 0, sr, 0, [Col.alpha(frameDark, 110), Col.alpha(AColor.WHITE, 220), Col.alpha(AColor.WHITE, 150), Col.alpha(frameDark, 120)],
                                 [0, 0.3, 0.6, 1])
        c.drawRect(dst, p); p.shader = nil
        collar(c, p, spoutTop - 8, sl - 8, sr + 8)
        collar(c, p, gateFloor - 6, sl - 6, sr + 6)
    }

    private func collar(_ c: ACanvas, _ p: Paint, _ cy: CGFloat, _ x0: CGFloat, _ x1: CGFloat) {
        var dst = RectF(x0, cy - 7, x1, cy + 7)
        p.color = frameDark; dst.offset(0, 3); c.drawRoundRect(dst, 6, 6, p); dst.offset(0, -3)
        p.shader = Shader.linear(0, dst.top, 0, dst.bottom, Col.lighten(frame, 0.45), Col.darken(frame, 0.1))
        c.drawRoundRect(dst, 6, 6, p); p.shader = nil
        p.color = 0xB3FFFFFF; c.drawRoundRect(dst.left + 5, dst.top + 2.5, dst.right - 5, dst.top + 5, 2, 2, p)
    }

    private func stadium(_ radius: CGFloat) -> CGPath {
        let s = CGMutablePath()
        s.addRoundRect(RectF(xl - radius, beltCy - radius, xr + radius, beltCy + radius), radius, radius)
        return s
    }

    private func drawBase(_ c: ACanvas) {
        let p = Paint()
        var dst = RectF()
        // ---- tray cabinet
        let dish = RectF(dishLeft, dishTop, dishRight, worldH + 60)
        p.color = Col.alpha(silhouette, 110); p.blurRadius = 14
        dst.set(dish); dst.offset(0, -4); c.drawRoundRect(dst, 46, 46, p); p.blurRadius = 0
        p.color = frameDark; dst.set(dish); dst.offset(0, 7); c.drawRoundRect(dst, 46, 46, p)
        p.shader = Shader.linear(0, dish.top, 0, dish.top + 240, Col.lighten(frame, 0.32), frame)
        c.drawRoundRect(dish, 46, 46, p); p.shader = nil
        p.style = .STROKE; p.strokeWidth = 4; p.color = 0x99FFFFFF
        dst.set(dish); dst.inset(3, 3); dst.offset(0, 1.5)
        c.save(); c.clipRect(dish.left, dish.top, dish.right, dish.top + 60); c.drawRoundRect(dst, 43, 43, p); c.restore()
        p.strokeWidth = 2.5; p.color = Col.alpha(Col.darken(frameDark, 0.3), 150); c.drawRoundRect(dish, 46, 46, p)
        p.style = .FILL
        var inn = RectF(dish); inn.inset(rimW, rimW)
        p.shader = Shader.linear(0, inn.top, 0, worldH, [glassTop, glassMid, glassBottom], [0, 0.3, 1])
        c.drawRoundRect(inn, 36, 36, p); p.shader = nil
        c.save()
        let innPath = CGMutablePath(); innPath.addRoundRect(inn, 36, 36); c.clipPath(innPath)
        // glass lanes
        for col in 0..<l.trayCols {
            let ccx = CGFloat(l.colCenter(col))
            dst.set(ccx - colW / 2 + 5, trayTop - 10, ccx + colW / 2 - 5, worldH + 40)
            p.color = Col.alpha(frameDark, 26); c.drawRoundRect(dst, 22, 22, p)
            p.shader = Shader.linear(dst.left, 0, dst.left + 16, 0, Col.alpha(frameDark, 50), Col.alpha(frameDark, 0))
            c.drawRoundRect(dst, 22, 22, p); p.shader = nil
            p.color = 0x99FFFFFF; c.drawRect(dst.right - 4, dst.top + 20, dst.right - 2, dst.bottom, p)
        }
        p.style = .STROKE; p.strokeWidth = 20; p.color = Col.alpha(frame, 80); p.blurRadius = 8
        c.save(); c.translate(0, 6); c.drawRoundRect(inn, 36, 36, p); c.restore()
        p.blurRadius = 0; p.style = .FILL
        c.restore()
        // ---- belt housing
        let r = marbleR
        let hR = beltR + r + 13
        let tR = beltR + r + 6
        p.color = Col.alpha(frameDark, 90); p.blurRadius = 7
        c.save(); c.translate(0, 7); c.drawPath(stadium(hR), p); c.restore(); p.blurRadius = 0
        p.color = frameDark
        c.save(); c.translate(0, 5); c.drawPath(stadium(hR), p); c.restore()
        p.shader = Shader.linear(0, beltCy - hR, 0, beltCy + hR, [Col.lighten(frame, 0.38), frame, Col.darken(frame, 0.12)], [0, 0.45, 1])
        c.drawPath(stadium(hR), p)
        p.style = .STROKE; p.strokeWidth = 3
        p.shader = Shader.linear(0, beltCy - hR, 0, beltCy, 0xCCFFFFFF, 0x00FFFFFF)
        c.drawPath(stadium(hR - 2.5), p); p.shader = nil
        p.strokeWidth = 2; p.color = Col.alpha(Col.darken(frameDark, 0.3), 150); c.drawPath(stadium(hR), p)
        p.style = .FILL
        // track
        p.shader = Shader.linear(0, beltCy - tR, 0, beltCy + tR, trackTop, trackBottom)
        c.drawPath(stadium(tR), p); p.shader = nil
        c.save(); c.clipPath(stadium(tR))
        p.style = .STROKE; p.strokeWidth = 10; p.color = 0x99000000; p.blurRadius = 5
        c.save(); c.translate(0, 4); c.drawPath(stadium(tR), p); c.restore()
        p.blurRadius = 0; p.style = .FILL
        c.restore()
        p.style = .STROKE; p.strokeWidth = 1.5; p.color = 0x40FFFFFF
        c.save(); c.translate(0, 1.2); c.drawPath(stadium(tR), p); c.restore()
        p.style = .FILL
        // island
        p.color = 0x66000000; c.save(); c.translate(0, 2.5); c.drawPath(stadium(islandR), p); c.restore()
        p.shader = Shader.linear(0, beltCy - islandR, 0, beltCy + islandR, AColor.WHITE, Col.lighten(theme.wallLight, 0.35))
        c.drawPath(stadium(islandR), p); p.shader = nil
        // gauge recess
        dst.set(gx0, beltCy - gh / 2, gx1, beltCy + gh / 2)
        p.color = 0xCCFFFFFF; dst.offset(0, 1.5); c.drawRoundRect(dst, gh / 2, gh / 2, p); dst.offset(0, -1.5)
        p.shader = Shader.linear(0, dst.top, 0, dst.bottom, Col.mix(trackTop, frameDark, 0.3), Col.mix(trackBottom, frameDark, 0.4))
        c.drawRoundRect(dst, gh / 2, gh / 2, p); p.shader = nil
    }

    // ================================================================ frame

    private func easeOutBack(_ t: CGFloat) -> CGFloat {
        let c1: CGFloat = 1.70158; let c3 = c1 + 1
        let x = t - 1
        return 1 + c3 * x * x * x + c1 * x * x
    }

    @inline(__always) private func opacity(_ a255: CGFloat) -> Double {
        Double(min(max(Int(a255), 0), 255)) / 255
    }

    @inline(__always) private func circle(_ x: CGFloat, _ y: CGFloat, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: x - r, y: y - r, width: 2 * r, height: 2 * r))
    }

    /// Draws one frame into a SwiftUI Canvas context (points).
    func draw(_ ctx: GraphicsContext) {
        let it = CGFloat(engine.introT)
        let dur = CGFloat(GameEngine.INTRO_MACHINE)
        let tm = min(max(it / dur, 0), 1)
        let boardScale: CGFloat = tm < 1 ? 0.6 + 0.4 * easeOutBack(tm) : 1
        let boardAlpha = min(tm * 3, 1)
        let tb = min(max((it - 0.08) / dur, 0), 1)
        let offB: CGFloat = tb < 1 ? (1 - easeOutBack(tb)) * (worldH - baseTop + 60) : 0
        let pivotY = (gridTop + gridBottom) / 2
        let ds = displayScale

        if let b = backdrop {
            ctx.draw(b.image, in: CGRect(x: 0, y: 0, width: CGFloat(b.width) / ds, height: CGFloat(b.height) / ds))
        }
        drawSparkles(ctx)
        if let b = base {
            ctx.draw(b.image, in: CGRect(x: 0, y: (baseTop + offB) * scale, width: CGFloat(b.width) / ds, height: CGFloat(b.height) / ds))
        }
        if let b = board {
            var c = ctx
            if boardScale != 1 { c.scaleAround(boardScale, boardScale, cx * scale, pivotY * scale) }
            c.opacity = opacity(255 * boardAlpha)
            c.draw(b.image, in: CGRect(x: 0, y: boardLayerTop * scale, width: CGFloat(b.width) / ds, height: CGFloat(b.height) / ds))
        }

        var w = ctx
        w.scaleBy(x: scale, y: scale)
        if engine.shake > 0 {
            let s = CGFloat(engine.shake)
            w.translateBy(x: (CGFloat(Float.random(in: 0..<1)) - 0.5) * s, y: (CGFloat(Float.random(in: 0..<1)) - 0.5) * s)
        }
        var bw = w
        if boardScale != 1 { bw.scaleAround(boardScale, boardScale, cx, pivotY) }
        drawBlocks(bw)
        drawExiting(bw)
        var bl = w
        bl.translateBy(x: 0, y: offB)
        drawBelt(bl)
        drawCups(bl)
        drawLooseMarbles(w)
        drawFlying(w)
        drawParticles(w)
        drawTexts(w)
        if engine.dangerLevel > 0.02 {
            let a = CGFloat(engine.dangerLevel) * (0.6 + 0.4 * sin(CGFloat(engine.time) * 5))
            var v = ctx
            v.scaleBy(x: scale, y: scale)
            v.opacity = opacity(a * 100)
            v.fill(Path(CGRect(x: 0, y: 0, width: worldW, height: worldH)), with: vignette)
        }
    }

    private func marbleAt(_ c: GraphicsContext, _ x: CGFloat, _ y: CGFloat, _ color: Int, _ squash: CGFloat = 0) {
        let r = marbleR
        let bmp = sprites.marbleShadowed(color, skin, r)
        let rect = CGRect(x: x - r * 1.35, y: y - r * 1.35, width: r * 2.7, height: r * 2.7)
        if squash > 0 {
            var cc = c
            cc.scaleAround(1 + squash * 0.22, 1 - squash * 0.22, x, y + r)
            cc.draw(bmp.image, in: rect)
        } else {
            c.draw(bmp.image, in: rect)
        }
    }

    private func drawSparkles(_ ctx: GraphicsContext) {
        var c = ctx
        c.scaleBy(x: scale, y: scale)
        let t = CGFloat(engine.time)
        for i in 0..<(sparkles.count / 4) {
            let k = (sin(t * 1.6 + sparkles[i * 4 + 3]) + 1) * 0.5
            if k < 0.15 { continue }
            Painter.star4(c, sparkles[i * 4], sparkles[i * 4 + 1], sparkles[i * 4 + 2] * (0.5 + 0.5 * k), Col.alpha(AColor.WHITE, Int(k * 200)))
        }
    }

    private func drawBelt(_ c: GraphicsContext) {
        let r = marbleR
        let sr = r * 1.02
        let sock = sprites.socket(sr)
        let cap = engine.capacity
        for i in 0..<cap {
            let pt = l.beltPoint(engine.slotS(i))
            c.draw(sock.image, in: CGRect(x: CGFloat(pt.x) - sr, y: CGFloat(pt.y) - sr, width: sr * 2, height: sr * 2))
        }
        // rivets between sockets show the belt running even when it is empty
        if cap > 1 {
            let half = (engine.slotS(1) - engine.slotS(0)) / 2
            for i in 0..<cap {
                let pt = l.beltPoint(engine.slotS(i) + half)
                let x = CGFloat(pt.x), y = CGFloat(pt.y)
                c.fill(circle(x, y + 0.8, 2.8), with: rivetDark)
                c.fill(circle(x, y, 2.3), with: rivetLight)
            }
        }
        for i in 0..<engine.slots.count {
            guard let m = engine.slots[i] else { continue }
            if m.state == .BELT { marbleAt(c, CGFloat(m.x), CGFloat(m.y), m.color, CGFloat(m.squash)) }
        }
        // rollers
        let hub = sprites.hub(hubR, frame)
        let deg = CGFloat(engine.beltOffset) / beltR * (180 / CGFloat.pi)
        for k in 0..<2 {
            let hx = k == 0 ? xl : xr
            var cc = c
            cc.rotateAround(deg, hx, beltCy)
            cc.draw(hub.image, in: CGRect(x: hx - hubR, y: beltCy - hubR, width: hubR * 2, height: hubR * 2))
        }
        // fill gauge
        let ratio = min(max(CGFloat(engine.beltCount) / CGFloat(cap), 0), 1)
        if ratio > 0 {
            let inset: CGFloat = 2.5
            let w = (gx1 - gx0 - inset * 2) * ratio
            let fh = gh - inset * 2
            let left = gx0 + inset, top = beltCy - fh / 2
            let right = gx0 + inset + max(w, fh)
            var cc = c
            if ratio >= 0.78 { cc.opacity = opacity(200 + 55 * sin(CGFloat(engine.time) * 9)) }
            cc.fill(Path(roundedRect: CGRect(x: left, y: top, width: right - left, height: fh), cornerSize: CGSize(width: fh / 2, height: fh / 2), style: .circular),
                    with: ratio >= 0.78 ? gaugeRed : (ratio >= 0.55 ? gaugeYellow : gaugeGreen))
            let hl0 = left + fh * 0.4
            let hl1 = max(right - fh * 0.4, hl0)
            c.fill(Path(roundedRect: CGRect(x: hl0, y: top + fh * 0.16, width: hl1 - hl0, height: fh * 0.2), cornerSize: CGSize(width: fh * 0.1, height: fh * 0.1), style: .circular),
                   with: gaugeGloss)
        }
        if engine.beltCount != gaugeCount || gaugeSprite == nil {
            gaugeCount = engine.beltCount
            gaugeLabel = "\(gaugeCount) / \(cap)"
            gaugeSprite = sprites.text(gaugeLabel, gh * 0.95, AColor.WHITE, 0xFF22124F, gh * 0.2)
        }
        gaugeSprite?.draw(c, cx, beltCy + 0.5)
    }

    private func variantOf(_ v: BlockVisual) -> Int {
        let k = v.state.spec.kind
        if k == .RAINBOW { return 3 }
        if k == .MYSTERY && v.reveal < 0.5 { return 1 }
        if k == .GRAY && v.paint < 0.5 { return 2 }
        return 0
    }

    private func drawBlocks(_ c: GraphicsContext) {
        for v in engine.visuals {
            guard let v else { continue }
            drawBlock(c, v, CGFloat(l.cellLeft(v.col)), CGFloat(l.cellTop(Float(v.row) + v.dropY)), cell)
        }
    }

    private func drawBlock(_ c0: GraphicsContext, _ v: BlockVisual, _ x0: CGFloat, _ y: CGFloat, _ s: CGFloat) {
        let spec = v.state.spec
        let time = CGFloat(engine.time)
        let x = x0 + (v.shake > 0 ? sin(time * 70) * CGFloat(v.shake) * s * 0.07 : 0)
        var c = c0
        let wakeBump = sin(CGFloat(v.wake) * .pi) * 0.1
        let sy = 1 - CGFloat(v.squash) * 0.22 + CGFloat(v.crack) * 0.05 + wakeBump
        let sx = 1 + CGFloat(v.squash) * 0.12 + wakeBump
        var flipX: CGFloat = 1
        if spec.kind == .MYSTERY && v.reveal >= 0.001 && v.reveal <= 0.999 { flipX = abs(cos(CGFloat(v.reveal) * .pi)) }
        c.scaleAround(sx * max(flipX, 0.05), sy, x + s / 2, y + s * 0.9)
        let variant = variantOf(v)
        let dst = CGRect(x: x, y: y, width: s, height: s)
        if v.open < 0.99 { c.draw(sprites.block(spec.color, variant, s, skin, false).image, in: dst) }
        if v.open > 0.01 {
            var cc = c
            cc.opacity = opacity(255 * CGFloat(v.open))
            cc.draw(sprites.block(spec.color, variant, s, skin, true).image, in: dst)
        }
        if spec.kind == .GRAY && v.paint >= 0.01 && v.paint <= 0.99 {
            var cc = c
            cc.opacity = opacity(255 * CGFloat(v.paint))
            cc.draw(sprites.block(spec.color, 0, s, skin, v.open > 0.5).image, in: dst)
        }
        let locked = engine.board.isLocked(v.state)
        switch spec.kind {
        case .KEY:
            overlay(c, SpriteCache.OV_KEY, x, y, s)
        case .CHAINED:
            if locked { overlay(c, SpriteCache.OV_CHAINS, x, y, s) } else if v.unlock > 0 { overlayFade(c, SpriteCache.OV_CHAINS, x, y, s, CGFloat(v.unlock)) }
        case .COUNTER:
            if locked {
                overlay(c, SpriteCache.OV_CAGE, x, y, s)
                badge(c, x + s / 2, y + s * 0.47, s * 0.2, engine.board.counterRemaining(v.state), 0xFF3D6BFF)
            } else if v.unlock > 0 { overlayFade(c, SpriteCache.OV_CAGE, x, y, s, CGFloat(v.unlock)) }
        case .CRATE:
            if locked {
                overlay(c, SpriteCache.OV_CRATE, x, y, s)
                badge(c, x + s / 2, y + s * 0.44, s * 0.2, engine.board.counterRemaining(v.state), 0xFFFF9F1C)
            } else if v.unlock > 0 { overlayFade(c, SpriteCache.OV_CRATE, x, y, s, CGFloat(v.unlock)) }
        case .ICE:
            overlay(c, v.state.cracked ? SpriteCache.OV_ICE_CRACKED : SpriteCache.OV_ICE, x, y, s)
        case .ARROW:
            overlay(c, SpriteCache.OV_ARROW, x, y, s, spec.param)
        case .DOUBLE:
            badge(c, x + s * 0.8, y + s * 0.2, s * 0.16, SpriteCache.BADGE_X2, 0xFF3CCB5A)
        case .BOMB:
            let rem = engine.board.counterRemaining(v.state)
            let pulse: CGFloat = rem <= 3 ? 1 + 0.08 * sin(time * 12) : 1
            var cc = c
            cc.scaleAround(pulse, pulse, x + s / 2, y + s / 2)
            overlay(cc, SpriteCache.OV_BOMB, x, y, s)
            badge(c, x + s * 0.78, y + s * 0.24, s * 0.16, rem, rem <= 3 ? 0xFFFF4D5E : 0xFF4A4E69)
        case .PAINT:
            overlay(c, SpriteCache.OV_BUCKET, x, y, s, spec.color)
        case .SWITCH:
            overlay(c, SpriteCache.OV_SWITCH, x, y, s)
        default:
            break
        }
        if v.pulse > 0 {
            c.fill(Path(roundedRect: CGRect(x: x + s * 0.06, y: y + s * 0.06, width: s * 0.88, height: s * 0.84), cornerSize: CGSize(width: s * 0.22, height: s * 0.22), style: .circular),
                   with: Painter.shading(Col.alpha(0xFFFF3040, Int(v.pulse * 100))))
        }
        if v.flash > 0 || v.wake > 0 {
            c.fill(Path(roundedRect: CGRect(x: x + s * 0.06, y: y + s * 0.06, width: s * 0.88, height: s * 0.84), cornerSize: CGSize(width: s * 0.22, height: s * 0.22), style: .circular),
                   with: Painter.shading(Col.alpha(AColor.WHITE, Int(max(v.flash, v.wake * 0.6) * 170))))
        }
    }

    /// `Painter.badge` as a cached sprite (the number is only formatted when the sprite is first built).
    private func badge(_ c: GraphicsContext, _ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ number: Int, _ bg: Int) {
        let rect = CGRect(x: cx - r * SpriteCache.BADGE_BOX, y: cy - r * SpriteCache.BADGE_BOX,
                          width: 2 * r * SpriteCache.BADGE_BOX, height: 2 * r * SpriteCache.BADGE_BOX)
        c.draw(sprites.badge(number, bg, r).image, in: rect)
    }

    private func drawExiting(_ c0: GraphicsContext) {
        for e in engine.exiting {
            let t = CGFloat(e.t)
            let ec = CGFloat(e.cell), ex = CGFloat(e.x), ey = CGFloat(e.y)
            let sc = 1 + 0.18 * sin(t * .pi) - 0.5 * t * t
            var c = c0
            c.scaleAround(sc, sc, ex + ec / 2, ey + ec / 2)
            c.opacity = opacity((1 - t) * 255)
            let variant = e.state.spec.kind == .RAINBOW ? 3 : 0
            c.draw(sprites.block(e.state.spec.color, variant, ec, skin, true).image, in: CGRect(x: ex, y: ey, width: ec, height: ec))
        }
    }

    private func overlay(_ c: GraphicsContext, _ type: Int, _ x: CGFloat, _ y: CGFloat, _ s: CGFloat, _ arg: Int = 0) {
        c.draw(sprites.overlay(type, s, arg).image, in: CGRect(x: x, y: y, width: s, height: s))
    }

    private func overlayFade(_ c0: GraphicsContext, _ type: Int, _ x: CGFloat, _ y: CGFloat, _ s: CGFloat, _ t: CGFloat) {
        let k = 1 + (1 - t) * 0.5
        let half = s * k / 2
        var c = c0
        c.opacity = Double(Int(255 * t)) / 255
        c.draw(sprites.overlay(type, s).image,
               in: CGRect(x: x + s / 2 - half, y: y + s / 2 - half - (1 - t) * s * 0.3, width: half * 2, height: half * 2))
    }

    private func drawCups(_ c0: GraphicsContext) {
        let w = cupW, h = cupH
        let mr = marbleR * 0.9
        let polish = CupPolish.active // Extras (Features.smoothPolish): landing spring, eased fly-away, shimmer
        for (ci, col) in engine.tray.enumerated() {
            let ccx = CGFloat(l.colCenter(ci))
            var last = col.cups.count - 1
            while last > 0 && CGFloat(l.cupTop(col.cups[last].display)) > worldH + 10 { last -= 1 }
            if last < 0 { continue }
            for idx in stride(from: last, through: 0, by: -1) {
                let cup = col.cups[idx]
                var y = CGFloat(l.cupTop(cup.display))
                var c = c0
                var scale: CGFloat = 1
                if cup.popping {
                    let t = CGFloat(cup.popT) / 0.42
                    scale = 1 + 0.3 * sin(t * .pi * 0.5)
                    y -= (polish ? CupPolish.lift(t) : t) * 55
                    c.opacity = opacity((polish ? CupPolish.fade(t) : 1 - t) * 255)
                }
                let hump = sin(CGFloat(cup.bounce) * .pi)
                let bounce = polish ? CupPolish.bounce(cup.bounce, cup.arrived) : (squash: hump * 0.04, dip: hump * 4)
                y += bounce.dip
                let sh: CGFloat = cup.shuffleT > 0 ? 1 + sin(CGFloat(cup.shuffleT) * .pi) * 0.12 : 1
                var flip: CGFloat = 1
                if cup.revealing { flip = max(abs(cos(CGFloat(cup.reveal) * .pi)), 0.05) }
                c.scaleAround(scale * sh * flip * (1 + bounce.squash), scale * sh * (1 - bounce.squash), ccx, y + h)
                let hiddenNow = cup.hidden && cup.reveal < 0.5
                c.draw(sprites.cup(cup.color, hiddenNow, w, h).image, in: CGRect(x: ccx - w / 2, y: y, width: w, height: h))
                if !hiddenNow {
                    let n = min(cup.arrived, 3)
                    if n > 0 {
                        let ms = sprites.marble(cup.color, skin, mr)
                        for k in 0..<n {
                            let mx = ccx + dimpleDx[k]; let my = y + dimpleDy
                            c.draw(ms.image, in: CGRect(x: mx - mr, y: my - mr, width: mr * 2, height: mr * 2))
                        }
                    }
                }
                if polish && cup.popping { CupPolish.shimmer(c, ccx - w / 2, y, w, h, CGFloat(cup.popT) / 0.42) }
            }
        }
        // queue fog: rows behind the active one fade into the frosted cabinet
        c0.fill(Path(CGRect(x: dishLeft + rimW, y: fogTop, width: dishRight - rimW - (dishLeft + rimW), height: worldH + 2 - fogTop)), with: fogShading)
    }

    private func drawLooseMarbles(_ c: GraphicsContext) {
        for m in engine.marbles {
            if m.state == .BELT { continue }
            marbleAt(c, CGFloat(m.x), CGFloat(m.y), m.color)
        }
    }

    private func drawFlying(_ c0: GraphicsContext) {
        for f in engine.flying {
            let s = CGFloat(f.cell * f.scale)
            let fx = CGFloat(f.x), fy = CGFloat(f.y)
            var c = c0
            c.rotateAround(CGFloat(f.rot), fx + s / 2, fy + s / 2)
            let variant = f.state.spec.kind == .RAINBOW ? 3 : 0
            c.draw(sprites.block(f.state.spec.color, variant, CGFloat(f.cell), skin, true).image, in: CGRect(x: fx, y: fy, width: s, height: s))
        }
    }

    private func drawParticles(_ c: GraphicsContext) {
        let ps = engine.particles
        for i in 0..<ps.count {
            let t = ps.life[i] / ps.maxLife[i]
            let a = Int(255 * min(max(t, 0), 1))
            let x = CGFloat(ps.x[i]), y = CGFloat(ps.y[i]), size = CGFloat(ps.size[i]), tt = CGFloat(t)
            let color = argbInt(ps.color[i])
            switch ps.type[i] {
            case Particles.DOT:
                c.fill(circle(x, y, size * (0.4 + 0.6 * tt)), with: Painter.shading(Col.alpha(color, a)))
            case Particles.STAR:
                Painter.star4(c, x, y, size * (0.5 + 0.5 * tt), Col.alpha(color, a))
            case Particles.CONFETTI:
                let rot = CGFloat(ps.rot[i])
                var cc = c
                cc.rotateAround(rot, x, y)
                let w = size; let hh = w * 0.55 * abs(cos(rot * 0.05))
                cc.fill(Path(CGRect(x: x - w / 2, y: y - hh / 2, width: w, height: hh)),
                        with: Painter.shading(Col.alpha(color, Int(255 * min(t * 2, 1)))))
            case Particles.RING:
                c.stroke(circle(x, y, max(size * (1.1 - tt) * 0.9, 0)), with: Painter.shading(Col.alpha(color, Int(Float(a) * 0.9))),
                         lineWidth: 7 * tt + 1)
            case Particles.SHARD:
                var cc = c
                cc.rotateAround(CGFloat(ps.rot[i]), x, y)
                cc.translateBy(x: x, y: y)
                cc.scaleBy(x: size, y: size)
                cc.fill(GameRenderer.unitShard, with: Painter.shading(Col.alpha(color, a)))
            case Particles.SMOKE:
                c.fill(circle(x, y, max(size * (1.6 - tt), 0)), with: Painter.shading(Col.alpha(color, Int(Float(a) * 0.5))))
            default:
                break
            }
        }
    }

    private func drawTexts(_ c: GraphicsContext) {
        for t in engine.texts {
            let k = CGFloat(t.life / t.maxLife)
            let sc = k < 0.15 ? 0.5 + k / 0.15 * 0.6 : 1.1 - (k - 0.15) * 0.1
            let alpha = k > 0.7 ? (1 - (k - 0.7) / 0.3) : 1
            let size = CGFloat(t.size)
            let ts = sprites.text(t.text, size * 1.1, argbInt(t.color), 0xFF3A1C8A, size * 1.1 * 0.18)
            var cc = c
            cc.opacity = opacity(alpha * 255)
            ts.draw(cc, CGFloat(t.x), CGFloat(t.y), sc / 1.1)
        }
    }
}

fileprivate extension GraphicsContext {
    /// Android `canvas.scale(sx, sy, px, py)`.
    mutating func scaleAround(_ sx: CGFloat, _ sy: CGFloat, _ px: CGFloat, _ py: CGFloat) {
        translateBy(x: px, y: py); scaleBy(x: sx, y: sy); translateBy(x: -px, y: -py)
    }

    /// Android `canvas.rotate(degrees, px, py)`.
    mutating func rotateAround(_ degrees: CGFloat, _ px: CGFloat, _ py: CGFloat) {
        translateBy(x: px, y: py); rotate(by: .degrees(Double(degrees))); translateBy(x: -px, y: -py)
    }
}
