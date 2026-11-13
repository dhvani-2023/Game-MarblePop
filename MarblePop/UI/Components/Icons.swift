import SwiftUI

// Port of ui/components/Icons.kt: the 37 procedural game icons, drawn into a SwiftUI Canvas.

enum Ico: String, CaseIterable {
    case COIN, STAR, STAR_EMPTY, GEAR, SHOP, GIFT, PLAY, MARBLES, TROPHY, HAMMER, MAGNET, SLOTS, SHUFFLE, LOCK,
         MUSIC, SOUND, VIBRATE, BACK, CLOSE, DOC, SHIELD, CHEST, CALENDAR, WHEEL, PAUSE, RETRY, HOME, CHECK, PALETTE, USER, PLUS,
         CROWN, CHEVRON, FLAME, CUP, FLAG, SPARK
}

private let Outline = Color(argb: 0xFF2A1463)
private let GlyphShadow = Color(argb: 0x592A1463)

/// `GameIcon(icon, Modifier.size(..), tint)`: size it with `.frame(width:height:)`.
struct GameIcon: View {
    let icon: Ico
    var tint: Color?

    init(_ icon: Ico, tint: Color? = nil) {
        self.icon = icon
        self.tint = tint
    }

    var body: some View {
        Canvas { ctx, size in drawGameIcon(ctx, size, icon, tint) }
            .accessibilityHidden(true)
    }
}

/// Compose `DrawScope.drawGameIcon(icon, tint)`: draws into the box (0, 0, size).
func drawGameIcon(_ ctx: GraphicsContext, _ size: CGSize, _ icon: Ico, _ tint: Color? = nil) {
    let d = ComposeDraw(ctx, size)
    let s = min(size.width, size.height)
    let c = CGPoint(x: size.width / 2, y: size.height / 2)
    let ow = s * 0.07
    func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
    func col(_ v: UInt32) -> GraphicsContext.Shading { .color(Color(argb: v)) }
    let white = GraphicsContext.Shading.color(.white)

    switch icon {
    case .COIN:
        d.circle(col(0xFFB86E00), s * 0.46, P(c.x, c.y + s * 0.04))
        d.circle(d.vGrad([Color(argb: 0xFFFFE680), Color(argb: 0xFFFFB800)], c.y - s * 0.45, c.y + s * 0.45), s * 0.44, c)
        d.circle(col(0xFFE09000), s * 0.31, c, stroke: s * 0.05)
        star(d, c, s * 0.2, Color(argb: 0xFFFFF4C2))
        d.circle(col(0xFF9A5600), s * 0.445, P(c.x, c.y + s * 0.01), stroke: s * 0.035)
        d.arc(.color(.white.opacity(0.55)), 200, 70, false, c.x - s * 0.36, c.y - s * 0.36, s * 0.72, s * 0.72,
              stroke: StrokeStyle(lineWidth: s * 0.05, lineCap: .round))
        d.circle(.color(.white.opacity(0.75)), s * 0.05, P(c.x - s * 0.2, c.y - s * 0.24))
    case .STAR, .STAR_EMPTY:
        let filled = icon == .STAR
        let p = starPath(P(c.x, c.y + s * 0.04), s * 0.48, s * 0.22)
        d.path(p, filled ? col(0xFFC77700) : col(0xFF3A2C78))
        let p2 = starPath(c, s * 0.48, s * 0.22)
        if filled { d.path(p2, d.vGrad([Color(argb: 0xFFFFEE88), Color(argb: 0xFFFFB000)], 0, size.height)) } else { d.path(p2, col(0xFF6A58B8)) }
        d.path(p2, filled ? col(0xFFB06000) : col(0xFF2E2266), stroke: StrokeStyle(lineWidth: ow * 0.7, lineJoin: .round))
        if filled { d.circle(.color(.white.opacity(0.8)), s * 0.05, P(c.x - s * 0.1, c.y - s * 0.14)) }
    case .GEAR:
        let fill = GraphicsContext.Shading.color(tint ?? .white)
        var p = Path()
        let teeth = 8
        for i in 0..<(teeth * 2) {
            let a = Double(i) * Double.pi / Double(teeth)
            let r = i % 2 == 0 ? s * 0.46 : s * 0.36
            let a1 = a - Double.pi / Double(teeth) * 0.45, a2 = a + Double.pi / Double(teeth) * 0.45
            let q1 = P(c.x + CGFloat(Float(cos(a1) * Double(r))), c.y + CGFloat(Float(sin(a1) * Double(r))))
            if i == 0 { p.move(to: q1) } else { p.addLine(to: q1) }
            p.addLine(to: P(c.x + CGFloat(Float(cos(a2) * Double(r))), c.y + CGFloat(Float(sin(a2) * Double(r)))))
        }
        p.closeSubpath()
        d.translated(0, s * 0.04).path(p, .color(Outline.opacity(0.5)))
        d.path(p, fill)
        d.path(p, .color(Outline), stroke: StrokeStyle(lineWidth: ow * 0.6, lineJoin: .round))
        d.circle(col(0xFF7B4DFF), s * 0.15, c)
        d.circle(.color(Outline), s * 0.15, c, stroke: ow * 0.6)
    case .SHOP:
        // stall with striped awning
        d.roundRect(col(0xFFE59A00), s * 0.16, s * 0.48, s * 0.68, s * 0.42, s * 0.06)
        d.roundRect(d.vGrad([Color(argb: 0xFFFFD35A), Color(argb: 0xFFFFB300)]), s * 0.16, s * 0.46, s * 0.68, s * 0.4, s * 0.06)
        d.roundRect(col(0xFF8A5200), s * 0.38, s * 0.6, s * 0.24, s * 0.26, s * 0.04)
        let stripes = 5
        let w = s * 0.84 / CGFloat(stripes)
        for i in 0..<stripes {
            let sc = i % 2 == 0 ? col(0xFFFF5FA2) : white
            d.roundRect(sc, s * 0.08 + CGFloat(i) * w, s * 0.14, w, s * 0.3, s * 0.06)
            d.circle(sc, w / 2, P(s * 0.08 + CGFloat(i) * w + w / 2, s * 0.44))
        }
        d.roundRect(.color(Outline), s * 0.08, s * 0.14, s * 0.84, s * 0.3, s * 0.06, stroke: ow * 0.6)
    case .GIFT:
        d.roundRect(col(0xFFC0306A), s * 0.14, s * 0.42, s * 0.72, s * 0.48, s * 0.08)
        d.roundRect(d.vGrad([Color(argb: 0xFFFF8AC0), Color(argb: 0xFFFF4D8D)]), s * 0.14, s * 0.4, s * 0.72, s * 0.46, s * 0.08)
        d.roundRect(d.vGrad([Color(argb: 0xFFFFA6D0), Color(argb: 0xFFFF5FA2)]), s * 0.08, s * 0.28, s * 0.84, s * 0.18, s * 0.06)
        d.rect(col(0xFFFFD23F), s * 0.43, s * 0.28, s * 0.14, s * 0.58)
        d.oval(col(0xFFFFD23F), s * 0.22, s * 0.1, s * 0.26, s * 0.2, stroke: s * 0.07)
        d.oval(col(0xFFFFD23F), s * 0.52, s * 0.1, s * 0.26, s * 0.2, stroke: s * 0.07)
    case .PLAY:
        var p = Path()
        p.move(to: P(s * 0.3, s * 0.18)); p.addLine(to: P(s * 0.82, s * 0.5)); p.addLine(to: P(s * 0.3, s * 0.82)); p.closeSubpath()
        d.translated(0, s * 0.04).path(p, .color(Outline.opacity(0.35)), stroke: StrokeStyle(lineWidth: s * 0.12, lineJoin: .round))
        d.path(p, .color(tint ?? .white), stroke: StrokeStyle(lineWidth: s * 0.12, lineJoin: .round))
        d.path(p, .color(tint ?? .white))
    case .MARBLES:
        ball(ctx, P(s * 0.34, s * 0.62), s * 0.22, 2)
        ball(ctx, P(s * 0.68, s * 0.64), s * 0.2, 6)
        ball(ctx, P(s * 0.52, s * 0.32), s * 0.21, 1)
    case .TROPHY:
        let gold = d.vGrad([Color(argb: 0xFFFFE680), Color(argb: 0xFFFFB000)])
        d.arc(col(0xFFE59A00), 90, 180, false, s * 0.08, s * 0.2, s * 0.3, s * 0.3, stroke: StrokeStyle(lineWidth: s * 0.07))
        d.arc(col(0xFFE59A00), -90, 180, false, s * 0.62, s * 0.2, s * 0.3, s * 0.3, stroke: StrokeStyle(lineWidth: s * 0.07))
        var cup = Path()
        cup.move(to: P(s * 0.22, s * 0.14)); cup.addLine(to: P(s * 0.78, s * 0.14))
        cup.addCurve(to: P(s * 0.5, s * 0.6), control1: P(s * 0.78, s * 0.5), control2: P(s * 0.62, s * 0.6))
        cup.addCurve(to: P(s * 0.22, s * 0.14), control1: P(s * 0.38, s * 0.6), control2: P(s * 0.22, s * 0.5)); cup.closeSubpath()
        d.path(cup, gold)
        d.path(cup, col(0xFFB06000), stroke: StrokeStyle(lineWidth: ow * 0.6))
        d.rect(col(0xFFE59A00), s * 0.44, s * 0.58, s * 0.12, s * 0.16)
        d.roundRect(col(0xFF8E5BFF), s * 0.26, s * 0.72, s * 0.48, s * 0.16, s * 0.04)
        star(d, P(s * 0.5, s * 0.32), s * 0.11, .white)
    case .HAMMER:
        let r = d.rotated(-35, c)
        r.roundRect(col(0xFF8A5200), s * 0.45, s * 0.36, s * 0.11, s * 0.56, s * 0.05)
        r.roundRect(r.hGrad([Color(argb: 0xFFD5A060), Color(argb: 0xFFA86A2A)]), s * 0.46, s * 0.36, s * 0.09, s * 0.54, s * 0.04)
        r.roundRect(col(0xFF3B3F52), s * 0.18, s * 0.12, s * 0.64, s * 0.28, s * 0.07)
        r.roundRect(r.vGrad([Color(argb: 0xFFE6EAF2), Color(argb: 0xFF8C93A8)]), s * 0.2, s * 0.13, s * 0.6, s * 0.24, s * 0.06)
    case .MAGNET:
        d.arc(col(0xFFB31E35), 0, 180, false, s * 0.16, s * 0.12, s * 0.68, s * 0.68, stroke: StrokeStyle(lineWidth: s * 0.22))
        d.arc(d.hGrad([Color(argb: 0xFFFF7A86), Color(argb: 0xFFFF2E4A)]), 0, 180, false, s * 0.16, s * 0.1, s * 0.68, s * 0.68,
              stroke: StrokeStyle(lineWidth: s * 0.18))
        d.rect(col(0xFFFF2E4A), s * 0.07, s * 0.2, s * 0.18, s * 0.24)
        d.rect(col(0xFFFF2E4A), s * 0.75, s * 0.2, s * 0.18, s * 0.24)
        d.rect(col(0xFFE6EAF2), s * 0.07, s * 0.08, s * 0.18, s * 0.14)
        d.rect(col(0xFFE6EAF2), s * 0.75, s * 0.08, s * 0.18, s * 0.14)
    case .SLOTS:
        d.roundRect(col(0xFF3B3557), s * 0.06, s * 0.32, s * 0.88, s * 0.38, s * 0.19)
        for i in 0..<4 { d.circle(i < 2 ? col(0xFF33C8F5) : col(0xFF6E6A86), s * 0.07, P(s * (0.22 + CGFloat(i) * 0.19), s * 0.51)) }
        d.circle(col(0xFF3CCB5A), s * 0.2, P(s * 0.74, s * 0.26))
        d.line(white, s * 0.74, s * 0.15, s * 0.74, s * 0.37, s * 0.07, cap: .round)
        d.line(white, s * 0.63, s * 0.26, s * 0.85, s * 0.26, s * 0.07, cap: .round)
    case .SHUFFLE:
        let sc = GraphicsContext.Shading.color(tint ?? Color(argb: 0xFF7B4DFF))
        var p1 = Path(); p1.move(to: P(s * 0.1, s * 0.3)); p1.addCurve(to: P(s * 0.82, s * 0.7), control1: P(s * 0.45, s * 0.3), control2: P(s * 0.45, s * 0.7))
        var p2 = Path(); p2.move(to: P(s * 0.1, s * 0.7)); p2.addCurve(to: P(s * 0.82, s * 0.3), control1: P(s * 0.45, s * 0.7), control2: P(s * 0.45, s * 0.3))
        d.path(p1, sc, stroke: StrokeStyle(lineWidth: s * 0.11, lineCap: .round))
        d.path(p2, sc, stroke: StrokeStyle(lineWidth: s * 0.11, lineCap: .round))
        for y in [0.3, 0.7] as [CGFloat] {
            var h = Path()
            h.move(to: P(s * 0.92, s * y)); h.addLine(to: P(s * 0.74, s * (y - 0.13))); h.addLine(to: P(s * 0.74, s * (y + 0.13))); h.closeSubpath()
            d.path(h, sc)
        }
    case .LOCK:
        d.arc(col(0xFF8A8FA8), 180, 180, false, s * 0.28, s * 0.12, s * 0.44, s * 0.5, stroke: StrokeStyle(lineWidth: s * 0.1))
        d.roundRect(col(0xFFB07000), s * 0.18, s * 0.4, s * 0.64, s * 0.5, s * 0.1)
        d.roundRect(d.vGrad([Color(argb: 0xFFFFD35A), Color(argb: 0xFFFFAA00)]), s * 0.18, s * 0.38, s * 0.64, s * 0.48, s * 0.1)
        d.circle(col(0xFF7A4A00), s * 0.07, P(s * 0.5, s * 0.58))
    case .MUSIC:
        let sc = GraphicsContext.Shading.color(tint ?? .white)
        d.circle(sc, s * 0.13, P(s * 0.3, s * 0.74)); d.circle(sc, s * 0.13, P(s * 0.72, s * 0.64))
        d.line(sc, s * 0.42, s * 0.74, s * 0.42, s * 0.2, s * 0.08)
        d.line(sc, s * 0.84, s * 0.64, s * 0.84, s * 0.12, s * 0.08)
        d.line(sc, s * 0.42, s * 0.22, s * 0.84, s * 0.12, s * 0.12)
    case .SOUND:
        let sc = GraphicsContext.Shading.color(tint ?? .white)
        var p = Path()
        p.move(to: P(s * 0.12, s * 0.38)); p.addLine(to: P(s * 0.3, s * 0.38)); p.addLine(to: P(s * 0.52, s * 0.18)); p.addLine(to: P(s * 0.52, s * 0.82))
        p.addLine(to: P(s * 0.3, s * 0.62)); p.addLine(to: P(s * 0.12, s * 0.62)); p.closeSubpath()
        d.path(p, sc)
        d.arc(sc, -45, 90, false, s * 0.42, s * 0.3, s * 0.32, s * 0.4, stroke: StrokeStyle(lineWidth: s * 0.07, lineCap: .round))
        d.arc(sc, -50, 100, false, s * 0.42, s * 0.16, s * 0.48, s * 0.68, stroke: StrokeStyle(lineWidth: s * 0.07, lineCap: .round))
    case .VIBRATE:
        let sc = GraphicsContext.Shading.color(tint ?? .white)
        d.roundRect(sc, s * 0.32, s * 0.12, s * 0.36, s * 0.76, s * 0.08, stroke: s * 0.08)
        d.line(sc, s * 0.42, s * 0.78, s * 0.58, s * 0.78, s * 0.06, cap: .round)
        for side in [-1, 1] as [CGFloat] {
            let x = s * 0.5 + side * s * 0.32
            d.line(sc, x, s * 0.32, x + side * s * 0.06, s * 0.42, s * 0.06, cap: .round)
            d.line(sc, x + side * s * 0.06, s * 0.42, x, s * 0.52, s * 0.06, cap: .round)
            d.line(sc, x, s * 0.52, x + side * s * 0.06, s * 0.62, s * 0.06, cap: .round)
        }
    case .BACK:
        glyph(d, s, tint) { g, sc in
            var p = Path(); p.move(to: P(s * 0.62, s * 0.18)); p.addLine(to: P(s * 0.3, s * 0.5)); p.addLine(to: P(s * 0.62, s * 0.82))
            g.path(p, sc, stroke: StrokeStyle(lineWidth: s * 0.16, lineCap: .round, lineJoin: .round))
        }
    case .CLOSE:
        glyph(d, s, tint) { g, sc in
            g.line(sc, s * 0.26, s * 0.26, s * 0.74, s * 0.74, s * 0.16, cap: .round)
            g.line(sc, s * 0.74, s * 0.26, s * 0.26, s * 0.74, s * 0.16, cap: .round)
        }
    case .DOC:
        d.roundRect(col(0xFFDCD3FF), s * 0.2, s * 0.12, s * 0.6, s * 0.78, s * 0.08)
        d.roundRect(white, s * 0.2, s * 0.08, s * 0.6, s * 0.76, s * 0.08)
        for i in 0..<4 {
            let y = s * (0.24 + CGFloat(i) * 0.14)
            d.line(col(0xFF9B87E8), s * 0.3, y, s * (i == 3 ? 0.55 : 0.7), y, s * 0.06, cap: .round)
        }
    case .SHIELD:
        var p = Path()
        p.move(to: P(s * 0.5, s * 0.08)); p.addLine(to: P(s * 0.84, s * 0.2))
        p.addCurve(to: P(s * 0.5, s * 0.92), control1: P(s * 0.84, s * 0.6), control2: P(s * 0.66, s * 0.8))
        p.addCurve(to: P(s * 0.16, s * 0.2), control1: P(s * 0.34, s * 0.8), control2: P(s * 0.16, s * 0.6)); p.closeSubpath()
        d.path(p, d.vGrad([Color(argb: 0xFF7BE88E), Color(argb: 0xFF1E9440)]))
        d.path(p, col(0xFF136B2E), stroke: StrokeStyle(lineWidth: ow * 0.6))
        var ck = Path(); ck.move(to: P(s * 0.33, s * 0.5)); ck.addLine(to: P(s * 0.46, s * 0.63)); ck.addLine(to: P(s * 0.68, s * 0.38))
        d.path(ck, white, stroke: StrokeStyle(lineWidth: s * 0.09, lineCap: .round, lineJoin: .round))
    case .CHEST:
        d.roundRect(col(0xFF6E3F18), s * 0.1, s * 0.36, s * 0.8, s * 0.54, s * 0.08)
        d.roundRect(d.vGrad([Color(argb: 0xFFE0A35C), Color(argb: 0xFFB0692A)]), s * 0.12, s * 0.4, s * 0.76, s * 0.46, s * 0.06)
        d.roundRect(d.vGrad([Color(argb: 0xFFF0B86E), Color(argb: 0xFFC07A36)]), s * 0.1, s * 0.14, s * 0.8, s * 0.28, s * 0.14)
        d.rect(col(0xFFFFC93C), s * 0.1, s * 0.38, s * 0.8, s * 0.07)
        d.roundRect(col(0xFFFFC93C), s * 0.42, s * 0.32, s * 0.16, s * 0.2, s * 0.04)
        d.circle(col(0xFF7A4A00), s * 0.03, P(s * 0.5, s * 0.42))
    case .CALENDAR:
        d.roundRect(col(0xFFC92A3C), s * 0.12, s * 0.18, s * 0.76, s * 0.72, s * 0.1)
        d.roundRect(white, s * 0.12, s * 0.32, s * 0.76, s * 0.56, s * 0.08)
        d.roundRect(d.vGrad([Color(argb: 0xFFFF7A86), Color(argb: 0xFFFF4D5E)]), s * 0.12, s * 0.16, s * 0.76, s * 0.2, s * 0.1)
        d.line(col(0xFF5B4A8E), s * 0.32, s * 0.08, s * 0.32, s * 0.24, s * 0.07, cap: .round)
        d.line(col(0xFF5B4A8E), s * 0.68, s * 0.08, s * 0.68, s * 0.24, s * 0.07, cap: .round)
        star(d, P(s * 0.5, s * 0.62), s * 0.16, Color(argb: 0xFFFFC93C))
    case .WHEEL:
        let cols: [UInt32] = [0xFFFF4D5E, 0xFFFFD23F, 0xFF3CCB5A, 0xFF33C8F5, 0xFF9B5CFF, 0xFFFF7AC8]
        for i in 0..<6 { d.arc(col(cols[i]), CGFloat(i) * 60, 60, true, s * 0.1, s * 0.1, s * 0.8, s * 0.8) }
        d.circle(white, s * 0.4, c, stroke: s * 0.06)
        d.circle(white, s * 0.1, c)
        var p = Path(); p.move(to: P(s * 0.5, s * 0.2)); p.addLine(to: P(s * 0.42, s * 0.02)); p.addLine(to: P(s * 0.58, s * 0.02)); p.closeSubpath()
        d.path(p, col(0xFF2B1A5E))
    case .PAUSE:
        glyph(d, s, tint) { g, sc in
            g.roundRect(sc, s * 0.26, s * 0.2, s * 0.16, s * 0.6, s * 0.06)
            g.roundRect(sc, s * 0.58, s * 0.2, s * 0.16, s * 0.6, s * 0.06)
        }
    case .RETRY:
        glyph(d, s, tint) { g, sc in
            g.arc(sc, 40, 290, false, s * 0.2, s * 0.2, s * 0.6, s * 0.6, stroke: StrokeStyle(lineWidth: s * 0.12, lineCap: .round))
            var p = Path(); p.move(to: P(s * 0.86, s * 0.38)); p.addLine(to: P(s * 0.62, s * 0.42)); p.addLine(to: P(s * 0.8, s * 0.18)); p.closeSubpath()
            g.path(p, sc)
        }
    case .HOME:
        glyph(d, s, tint) { g, sc in
            var p = Path()
            p.move(to: P(s * 0.5, s * 0.12)); p.addLine(to: P(s * 0.9, s * 0.48)); p.addLine(to: P(s * 0.78, s * 0.48)); p.addLine(to: P(s * 0.78, s * 0.86))
            p.addLine(to: P(s * 0.22, s * 0.86)); p.addLine(to: P(s * 0.22, s * 0.48)); p.addLine(to: P(s * 0.1, s * 0.48)); p.closeSubpath()
            g.path(p, sc, stroke: StrokeStyle(lineWidth: s * 0.04, lineJoin: .round))
            g.path(p, sc)
        }
        d.roundRect(col(0xFF7B4DFF), s * 0.42, s * 0.58, s * 0.16, s * 0.28, s * 0.04)
    case .CHECK:
        glyph(d, s, tint) { g, sc in
            var ck = Path(); ck.move(to: P(s * 0.2, s * 0.52)); ck.addLine(to: P(s * 0.42, s * 0.74)); ck.addLine(to: P(s * 0.8, s * 0.3))
            g.path(ck, sc, stroke: StrokeStyle(lineWidth: s * 0.16, lineCap: .round, lineJoin: .round))
        }
    case .PALETTE:
        d.circle(col(0xFFF5E6C8), s * 0.42, c)
        d.circle(col(0xFFB08A50), s * 0.42, c, stroke: s * 0.05)
        d.circle(col(0xFFFF4D5E), s * 0.08, P(s * 0.32, s * 0.32))
        d.circle(col(0xFF33C8F5), s * 0.08, P(s * 0.56, s * 0.24))
        d.circle(col(0xFF3CCB5A), s * 0.08, P(s * 0.74, s * 0.42))
        d.circle(col(0xFFFFD23F), s * 0.08, P(s * 0.28, s * 0.58))
        d.circle(col(0xFF9B5CFF), s * 0.1, P(s * 0.6, s * 0.68))
    case .USER:
        d.circle(.color(tint ?? .white), s * 0.2, P(s * 0.5, s * 0.34))
        d.arc(.color(tint ?? .white), 180, 180, true, s * 0.16, s * 0.56, s * 0.68, s * 0.6)
    case .PLUS:
        glyph(d, s, tint) { g, sc in
            g.line(sc, s * 0.5, s * 0.2, s * 0.5, s * 0.8, s * 0.18, cap: .round)
            g.line(sc, s * 0.2, s * 0.5, s * 0.8, s * 0.5, s * 0.18, cap: .round)
        }
    case .CROWN:
        var p = Path()
        p.move(to: P(s * 0.1, s * 0.34)); p.addLine(to: P(s * 0.31, s * 0.56)); p.addLine(to: P(s * 0.5, s * 0.2)); p.addLine(to: P(s * 0.69, s * 0.56))
        p.addLine(to: P(s * 0.9, s * 0.34)); p.addLine(to: P(s * 0.81, s * 0.82)); p.addLine(to: P(s * 0.19, s * 0.82)); p.closeSubpath()
        d.translated(0, s * 0.05).path(p, col(0xFFA85A00))
        d.path(p, d.vGrad([Color(argb: 0xFFFFF4B0), Color(argb: 0xFFFFC21A), Color(argb: 0xFFFF9E00)], s * 0.2, s * 0.82))
        d.rect(col(0x33A85A00), s * 0.19, s * 0.68, s * 0.62, s * 0.14)
        d.path(p, col(0xFF8A4A00), stroke: StrokeStyle(lineWidth: ow * 0.6, lineJoin: .round))
        d.circle(col(0xFFFF4D8D), s * 0.07, P(s * 0.5, s * 0.6))
        d.circle(col(0xFF33D6F5), s * 0.05, P(s * 0.31, s * 0.7))
        d.circle(col(0xFF33D6F5), s * 0.05, P(s * 0.69, s * 0.7))
        for pt in [P(s * 0.1, s * 0.34), P(s * 0.5, s * 0.2), P(s * 0.9, s * 0.34)] {
            d.circle(col(0xFF8A4A00), s * 0.075, pt); d.circle(col(0xFFFFF4B0), s * 0.05, pt)
        }
        d.circle(.color(.white.opacity(0.8)), s * 0.03, P(s * 0.46, s * 0.57))
    case .CHEVRON:
        glyph(d, s, tint ?? Outline) { g, sc in
            var p = Path(); p.move(to: P(s * 0.38, s * 0.2)); p.addLine(to: P(s * 0.68, s * 0.5)); p.addLine(to: P(s * 0.38, s * 0.8))
            g.path(p, sc, stroke: StrokeStyle(lineWidth: s * 0.15, lineCap: .round, lineJoin: .round))
        }
    case .FLAME:
        var outer = Path()
        outer.move(to: P(s * 0.5, s * 0.06))
        outer.addCurve(to: P(s * 0.84, s * 0.64), control1: P(s * 0.62, s * 0.3), control2: P(s * 0.86, s * 0.42))
        outer.addCurve(to: P(s * 0.5, s * 0.94), control1: P(s * 0.82, s * 0.84), control2: P(s * 0.66, s * 0.94))
        outer.addCurve(to: P(s * 0.17, s * 0.62), control1: P(s * 0.32, s * 0.94), control2: P(s * 0.16, s * 0.82))
        outer.addCurve(to: P(s * 0.34, s * 0.24), control1: P(s * 0.18, s * 0.46), control2: P(s * 0.3, s * 0.38))
        outer.addCurve(to: P(s * 0.44, s * 0.44), control1: P(s * 0.4, s * 0.34), control2: P(s * 0.42, s * 0.4))
        outer.addCurve(to: P(s * 0.5, s * 0.06), control1: P(s * 0.5, s * 0.32), control2: P(s * 0.52, s * 0.2)); outer.closeSubpath()
        d.path(outer, d.vGrad([Color(argb: 0xFFFFB24A), Color(argb: 0xFFFF5A3C), Color(argb: 0xFFE8273D)], s * 0.06, s * 0.94))
        d.path(outer, col(0xFF9A1A1A), stroke: StrokeStyle(lineWidth: ow * 0.55, lineJoin: .round))
        var inner = Path()
        inner.move(to: P(s * 0.5, s * 0.42))
        inner.addCurve(to: P(s * 0.66, s * 0.75), control1: P(s * 0.6, s * 0.56), control2: P(s * 0.68, s * 0.64))
        inner.addCurve(to: P(s * 0.5, s * 0.9), control1: P(s * 0.64, s * 0.86), control2: P(s * 0.56, s * 0.9))
        inner.addCurve(to: P(s * 0.34, s * 0.72), control1: P(s * 0.4, s * 0.9), control2: P(s * 0.33, s * 0.82))
        inner.addCurve(to: P(s * 0.5, s * 0.42), control1: P(s * 0.36, s * 0.6), control2: P(s * 0.46, s * 0.54)); inner.closeSubpath()
        d.path(inner, d.vGrad([Color(argb: 0xFFFFF6B0), Color(argb: 0xFFFFC93C)], s * 0.42, s * 0.9))
    case .CUP:
        var body = Path()
        body.move(to: P(s * 0.16, s * 0.36)); body.addLine(to: P(s * 0.84, s * 0.36)); body.addLine(to: P(s * 0.74, s * 0.88)); body.addLine(to: P(s * 0.26, s * 0.88)); body.closeSubpath()
        d.translated(0, s * 0.04).path(body, col(0xFF8A1E5A))
        d.path(body, d.hGrad([Color(argb: 0xFFFF8AC4), Color(argb: 0xFFFF4C97), Color(argb: 0xFFD12D78)], s * 0.16, s * 0.84))
        d.rect(.color(.white.opacity(0.35)), s * 0.27, s * 0.42, s * 0.07, s * 0.38)
        d.path(body, col(0xFF7E1546), stroke: StrokeStyle(lineWidth: ow * 0.6, lineJoin: .round))
        ball(ctx, P(s * 0.36, s * 0.3), s * 0.12, 1)
        ball(ctx, P(s * 0.62, s * 0.29), s * 0.12, 1)
        ball(ctx, P(s * 0.49, s * 0.16), s * 0.12, 1)
        d.roundRect(col(0xFFFFD0E8), s * 0.12, s * 0.34, s * 0.76, s * 0.08, s * 0.04)
        d.roundRect(col(0xFF7E1546), s * 0.12, s * 0.34, s * 0.76, s * 0.08, s * 0.04, stroke: ow * 0.45)
    case .FLAG:
        d.roundRect(col(0xFF6E5A8A), s * 0.2, s * 0.1, s * 0.07, s * 0.82, s * 0.035)
        d.roundRect(col(0xFFE6E0F5), s * 0.21, s * 0.1, s * 0.035, s * 0.8, s * 0.02)
        var flag = Path()
        flag.move(to: P(s * 0.27, s * 0.14))
        flag.addCurve(to: P(s * 0.86, s * 0.14), control1: P(s * 0.45, s * 0.08), control2: P(s * 0.6, s * 0.22))
        flag.addLine(to: P(s * 0.86, s * 0.5))
        flag.addCurve(to: P(s * 0.27, s * 0.5), control1: P(s * 0.6, s * 0.58), control2: P(s * 0.45, s * 0.44)); flag.closeSubpath()
        d.translated(0, s * 0.04).path(flag, col(0xFF1E9440))
        d.path(flag, d.vGrad([Color(argb: 0xFF9DF58A), Color(argb: 0xFF2FBF4F)], s * 0.1, s * 0.55))
        d.path(flag, col(0xFF0E5A26), stroke: StrokeStyle(lineWidth: ow * 0.5, lineJoin: .round))
        star(d, P(s * 0.56, s * 0.32), s * 0.1, .white)
        d.circle(col(0xFFFFC93C), s * 0.06, P(s * 0.235, s * 0.1))
    case .SPARK:
        var p = Path()
        p.move(to: P(c.x, c.y - s * 0.48))
        p.addQuadCurve(to: P(c.x + s * 0.48, c.y), control: P(c.x + s * 0.07, c.y - s * 0.07))
        p.addQuadCurve(to: P(c.x, c.y + s * 0.48), control: P(c.x + s * 0.07, c.y + s * 0.07))
        p.addQuadCurve(to: P(c.x - s * 0.48, c.y), control: P(c.x - s * 0.07, c.y + s * 0.07))
        p.addQuadCurve(to: P(c.x, c.y - s * 0.48), control: P(c.x - s * 0.07, c.y - s * 0.07)); p.closeSubpath()
        d.path(p, .color(tint ?? Color(argb: 0xFFFFF3B0)))
        d.circle(white, s * 0.08, c)
    }
}

/// Draws a flat glyph with a soft drop shadow underneath (for white icons on jelly buttons).
private func glyph(_ d: ComposeDraw, _ s: CGFloat, _ tint: Color?, _ draw: (ComposeDraw, GraphicsContext.Shading) -> Void) {
    draw(d.translated(0, s * 0.06), .color(GlyphShadow))
    draw(d, .color(tint ?? .white))
}

func starPath(_ c: CGPoint, _ outer: CGFloat, _ inner: CGFloat) -> Path {
    var p = Path()
    for i in 0..<10 {
        let r = i % 2 == 0 ? outer : inner
        let a = -Double.pi / 2 + Double(i) * Double.pi / 5
        let x = c.x + CGFloat(Float(cos(a) * Double(r))), y = c.y + CGFloat(Float(sin(a) * Double(r)))
        if i == 0 { p.move(to: CGPoint(x: x, y: y)) } else { p.addLine(to: CGPoint(x: x, y: y)) }
    }
    p.closeSubpath()
    return p
}

private func star(_ d: ComposeDraw, _ c: CGPoint, _ r: CGFloat, _ color: Color) {
    d.path(starPath(c, r, r * 0.45), .color(color))
}

/// Glossy marble drawn with the game's painter (cached sprite at the display scale).
func ball(_ ctx: GraphicsContext, _ c: CGPoint, _ r: CGFloat, _ colorId: Int, _ skin: Int = 0) {
    let rr = r * 0.95
    ctx.fill(Path(ellipseIn: CGRect(x: c.x + r * 0.1 - rr, y: c.y + r * 0.2 - rr, width: rr * 2, height: rr * 2)), with: .color(.black.opacity(0.25)))
    Painter.marble(ctx, c.x, c.y, r, colorId, skin)
}

// MARK: - Compose DrawScope-style helper

/// Thin wrapper giving `GraphicsContext` the Compose DrawScope calls used by the ported drawing code
/// (gradients default to the draw-scope size, like Compose brushes without start/end).
struct ComposeDraw {
    let ctx: GraphicsContext
    let size: CGSize

    init(_ ctx: GraphicsContext, _ size: CGSize) {
        self.ctx = ctx
        self.size = size
    }

    func vGrad(_ colors: [Color], _ y0: CGFloat = 0, _ y1: CGFloat? = nil) -> GraphicsContext.Shading {
        .linearGradient(Gradient(colors: colors), startPoint: CGPoint(x: 0, y: y0), endPoint: CGPoint(x: 0, y: y1 ?? size.height))
    }

    func vGrad(stops: [Gradient.Stop], _ y0: CGFloat = 0, _ y1: CGFloat? = nil) -> GraphicsContext.Shading {
        .linearGradient(Gradient(stops: stops), startPoint: CGPoint(x: 0, y: y0), endPoint: CGPoint(x: 0, y: y1 ?? size.height))
    }

    func hGrad(_ colors: [Color], _ x0: CGFloat = 0, _ x1: CGFloat? = nil) -> GraphicsContext.Shading {
        .linearGradient(Gradient(colors: colors), startPoint: CGPoint(x: x0, y: 0), endPoint: CGPoint(x: x1 ?? size.width, y: 0))
    }

    func translated(_ dx: CGFloat, _ dy: CGFloat) -> ComposeDraw {
        var c = ctx
        c.translateBy(x: dx, y: dy)
        return ComposeDraw(c, size)
    }

    func rotated(_ degrees: CGFloat, _ pivot: CGPoint) -> ComposeDraw {
        var c = ctx
        c.translateBy(x: pivot.x, y: pivot.y)
        c.rotate(by: .degrees(Double(degrees)))
        c.translateBy(x: -pivot.x, y: -pivot.y)
        return ComposeDraw(c, size)
    }

    func clipped(_ path: Path) -> ComposeDraw {
        var c = ctx
        c.clip(to: path)
        return ComposeDraw(c, size)
    }

    func path(_ p: Path, _ s: GraphicsContext.Shading, stroke: StrokeStyle? = nil) {
        if let stroke {
            var st = stroke
            if st.miterLimit == 10 { st.miterLimit = 4 }
            ctx.stroke(p, with: s, style: st)
        } else {
            ctx.fill(p, with: s)
        }
    }

    func circle(_ s: GraphicsContext.Shading, _ r: CGFloat, _ c: CGPoint, stroke: CGFloat? = nil) {
        let p = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
        path(p, s, stroke: stroke.map { StrokeStyle(lineWidth: $0) })
    }

    static func roundRectPath(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> Path {
        let rect = CGRect(x: x, y: y, width: w, height: h).standardized
        let (rx, ry) = ACanvas.clampRadii(rect, r, r)
        if rx <= 0 { return Path(rect) }
        return Path(roundedRect: rect, cornerSize: CGSize(width: rx, height: ry), style: .circular)
    }

    func roundRect(_ s: GraphicsContext.Shading, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat, stroke: CGFloat? = nil) {
        path(ComposeDraw.roundRectPath(x, y, w, h, r), s, stroke: stroke.map { StrokeStyle(lineWidth: $0) })
    }

    func rect(_ s: GraphicsContext.Shading, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) {
        ctx.fill(Path(CGRect(x: x, y: y, width: w, height: h)), with: s)
    }

    func oval(_ s: GraphicsContext.Shading, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, stroke: CGFloat? = nil) {
        path(Path(ellipseIn: CGRect(x: x, y: y, width: w, height: h)), s, stroke: stroke.map { StrokeStyle(lineWidth: $0) })
    }

    /// Compose drawArc: degrees, 0 = 3 o'clock, positive = clockwise; topLeft + size of the oval.
    func arc(_ s: GraphicsContext.Shading, _ startAngle: CGFloat, _ sweep: CGFloat, _ useCenter: Bool,
             _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, stroke: StrokeStyle? = nil) {
        let cg = CGMutablePath()
        let t = CGAffineTransform(translationX: x + w / 2, y: y + h / 2).scaledBy(x: w / 2, y: h / 2)
        let a0 = startAngle * .pi / 180, a1 = (startAngle + sweep) * .pi / 180
        if useCenter {
            cg.move(to: CGPoint(x: x + w / 2, y: y + h / 2))
            cg.addLine(to: CGPoint(x: cos(a0), y: sin(a0)), transform: t)
        } else {
            cg.move(to: CGPoint(x: cos(a0), y: sin(a0)), transform: t)
        }
        cg.addArc(center: .zero, radius: 1, startAngle: a0, endAngle: a1, clockwise: sweep < 0, transform: t)
        if useCenter { cg.closeSubpath() }
        path(Path(cg), s, stroke: stroke)
    }

    func line(_ s: GraphicsContext.Shading, _ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat, _ width: CGFloat, cap: CGLineCap = .butt) {
        var p = Path()
        p.move(to: CGPoint(x: x0, y: y0)); p.addLine(to: CGPoint(x: x1, y: y1))
        ctx.stroke(p, with: s, style: StrokeStyle(lineWidth: width, lineCap: cap))
    }
}

/// Canvas that may draw outside its layout box by `bleed` on every side (Compose draw modifiers are not clipped).
/// The closure receives the layout size, with the origin at the layout box's top-left.
/// `key` must change whenever the drawing changes for any reason other than size: it is captured directly by the
/// Canvas closure, because SwiftUI only redraws a Canvas when the closure's own captures change.
struct BleedCanvas: View {
    var bleed: CGFloat = 8
    var key: Int = 0
    let draw: (GraphicsContext, CGSize) -> Void

    init(bleed: CGFloat = 8, key: Int = 0, _ draw: @escaping (GraphicsContext, CGSize) -> Void) {
        self.bleed = bleed
        self.key = key
        self.draw = draw
    }

    var body: some View {
        let bleed = self.bleed, key = self.key, draw = self.draw
        return Canvas { ctx, size in
            _ = key
            var c = ctx
            c.translateBy(x: bleed, y: bleed)
            draw(c, CGSize(width: max(0, size.width - 2 * bleed), height: max(0, size.height - 2 * bleed)))
        }
        .padding(-bleed)
        .allowsHitTesting(false)
    }
}
