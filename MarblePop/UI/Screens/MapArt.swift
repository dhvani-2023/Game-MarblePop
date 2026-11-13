import SwiftUI
import GameKit

// Home map art: road tube, level discs and per-world scenery (port of MapArt.kt).
// Every function draws into a SwiftUI GraphicsContext whose origin is the row's top-left corner.

/// Horizontal position of level [n]'s node as a fraction of the width from the centre.
func nodeX(_ n: Int) -> CGFloat { CGFloat(Kt.sin(Float(n) * 0.85) * 0.2) }

/// Which side the scenery goes on (opposite the node): -1 left, +1 right.
func scenerySide(_ n: Int) -> Int { nodeX(n) > 0 ? -1 : 1 }

/// Unit-size four point sparkle (radius 1), drawn with translate + scale (Backgrounds.kt `SparklePath`).
let mapSparklePath: Path = {
    var p = Path()
    p.move(to: CGPoint(x: 0, y: -1))
    p.addQuadCurve(to: CGPoint(x: 1, y: 0), control: CGPoint(x: 0.14, y: -0.14))
    p.addQuadCurve(to: CGPoint(x: 0, y: 1), control: CGPoint(x: 0.14, y: 0.14))
    p.addQuadCurve(to: CGPoint(x: -1, y: 0), control: CGPoint(x: -0.14, y: 0.14))
    p.addQuadCurve(to: CGPoint(x: 0, y: -1), control: CGPoint(x: -0.14, y: -0.14))
    p.closeSubpath()
    return p
}()

/// Draws the unit sparkle at (x, y) with radius r.
func drawSparkle(_ ctx: GraphicsContext, _ x: CGFloat, _ y: CGFloat, _ r: CGFloat, _ color: Color) {
    var c = ctx
    c.translateBy(x: x, y: y)
    c.scaleBy(x: r, y: r)
    c.fill(mapSparklePath, with: .color(color))
}

/// Compose `drawArc(topLeft, size, startAngle, sweepAngle)` as a path (degrees, clockwise on screen).
func arcPath(_ rect: CGRect, _ startDeg: CGFloat, _ sweepDeg: CGFloat, useCenter: Bool = false) -> Path {
    var p = Path()
    let t = CGAffineTransform(translationX: rect.midX, y: rect.midY).scaledBy(x: rect.width / 2, y: rect.height / 2)
    if useCenter { p.move(to: CGPoint(x: rect.midX, y: rect.midY)) }
    p.addRelativeArc(center: .zero, radius: 1, startAngle: .degrees(Double(startDeg)), delta: .degrees(Double(sweepDeg)), transform: t)
    if useCenter { p.closeSubpath() }
    return p
}

private func ov(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> Path { Path(ellipseIn: CGRect(x: x, y: y, width: w, height: h)) }
private func circ(_ c: CGPoint, _ r: CGFloat) -> Path { Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)) }
private func rrect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> Path {
    Path(roundedRect: CGRect(x: x, y: y, width: w, height: h), cornerRadius: max(0, min(r, min(w, h) / 2)), style: .circular)
}
private func vgrad(_ colors: [Color], _ y0: CGFloat, _ y1: CGFloat) -> GraphicsContext.Shading {
    .linearGradient(Gradient(colors: colors), startPoint: CGPoint(x: 0, y: y0), endPoint: CGPoint(x: 0, y: y1))
}
private func hgrad(_ colors: [Color], _ x0: CGFloat, _ x1: CGFloat) -> GraphicsContext.Shading {
    .linearGradient(Gradient(colors: colors), startPoint: CGPoint(x: x0, y: 0), endPoint: CGPoint(x: x1, y: 0))
}
private func line(_ a: CGPoint, _ b: CGPoint) -> Path { var p = Path(); p.move(to: a); p.addLine(to: b); return p }

/// Glass-tube road from node [n] up to node n+1 (row height `size.height`, node at its centre).
/// Finished stretches are filled with gold.
func drawRoad(_ ctx: GraphicsContext, _ size: CGSize, _ n: Int, _ current: Int) {
    if n >= LevelGenerator.MAX_LEVEL || n < 1 { return }
    let w = size.width
    let h = size.height
    let x0 = w / 2 + nodeX(n) * w
    let x1 = w / 2 + nodeX(n + 1) * w
    let y0 = h / 2
    let y1 = y0 - h
    var path = Path()
    path.move(to: CGPoint(x: x0, y: y0))
    path.addCurve(to: CGPoint(x: x1, y: y1), control1: CGPoint(x: x0, y: y0 - h * 0.5), control2: CGPoint(x: x1, y: y1 + h * 0.5))
    ctx.stroke(path, with: .color(Color(argb: 0x33140A3C)), style: StrokeStyle(lineWidth: 30, lineCap: .round))
    ctx.stroke(path, with: .color(.white.opacity(0.26)), style: StrokeStyle(lineWidth: 25, lineCap: .round))
    if n < current {
        ctx.stroke(path, with: .color(Color(argb: 0xFFE59A00)), style: StrokeStyle(lineWidth: 15, lineCap: .round))
        ctx.stroke(path, with: .color(Color(argb: 0xFFFFCB3D)), style: StrokeStyle(lineWidth: 11, lineCap: .round))
        ctx.stroke(path, with: .color(Color(argb: 0xFFFFF3B8)), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [10, 9]))
    } else {
        ctx.stroke(path, with: .color(Color(argb: 0x4D140A3C)), style: StrokeStyle(lineWidth: 14, lineCap: .round))
        ctx.stroke(path, with: .color(.white.opacity(0.6)), style: StrokeStyle(lineWidth: 5, lineCap: .round, dash: [0.1, 15]))
    }
    var hl = ctx
    hl.translateBy(x: -7, y: 0)
    hl.stroke(path, with: .color(.white.opacity(0.3)), style: StrokeStyle(lineWidth: 2, lineCap: .round))
}

/// Disc colours per node state: top, bottom, depth, outline.
private let NodeDone = [Color(argb: 0xFFFFF0A0), Color(argb: 0xFFFFB300), Color(argb: 0xFFC47A00), Color(argb: 0xFF8A4A00)]
private let NodeCurrent = [Color(argb: 0xFFFFB8DC), Color(argb: 0xFFFF4C97), Color(argb: 0xFFC42A6E), Color(argb: 0xFF7E1546)]
private let NodeLocked = [Color(argb: 0xFFF4F1FB), Color(argb: 0xFFC9C1E0), Color(argb: 0xFF9D95B8), Color(argb: 0xFF5E5878)]
private let NodeAd = [Color(argb: 0xFFB5F3FF), Color(argb: 0xFF26ACF2), Color(argb: 0xFF1373BE), Color(argb: 0xFF0A4A80)]
private let NodeBoss = [Color(argb: 0xFFFFB0B0), Color(argb: 0xFFFF4D5E), Color(argb: 0xFFC0283A), Color(argb: 0xFF7D1222)]
/// Same colours with 28 % alpha for the inner shade (Compose `dark.copy(alpha = 0.28f)`).
private let NodeDarkShade: [[Color]] = [NodeDone, NodeCurrent, NodeLocked, NodeAd, NodeBoss].map { [Color.clear, $0[2].opacity(0.28)] }

/// state: 0 done, 1 current, 2 locked, 3 unlocked by an ad.
func nodeOutline(_ state: Int, _ boss: Bool) -> Color { nodeColors(state, boss)[3] }

private func nodeIndex(_ state: Int, _ boss: Bool) -> Int {
    if state == 2 { return 2 }
    if state == 3 { return 3 }
    if boss && state != 0 { return 4 }
    if state == 1 { return 1 }
    return 0
}

private func nodeColors(_ state: Int, _ boss: Bool) -> [Color] {
    [NodeDone, NodeCurrent, NodeLocked, NodeAd, NodeBoss][nodeIndex(state, boss)]
}

/// Glossy 3D level disc; `side` is the disc's diameter, origin its top-left corner.
func drawNodeDisc(_ ctx: GraphicsContext, _ side: CGFloat, _ state: Int, _ boss: Bool) {
    let cols = nodeColors(state, boss)
    let top = cols[0], bot = cols[1], dark = cols[2], outline = cols[3]
    let r = side / 2
    let c = CGPoint(x: r, y: r)
    let d = r * 0.14
    ctx.fill(ov(r * 0.12, r * 1.62, r * 1.76, r * 0.56), with: .color(Color(argb: 0x38140A3C)))
    ctx.fill(circ(CGPoint(x: c.x, y: c.y + d), r), with: .color(dark))
    ctx.fill(circ(c, r), with: vgrad([top, bot], 0, r * 2))
    ctx.fill(circ(c, r), with: .radialGradient(Gradient(colors: NodeDarkShade[nodeIndex(state, boss)]), center: c, startRadius: 0, endRadius: r))
    ctx.stroke(circ(c, r * 0.82), with: .color(.white.opacity(0.55)), lineWidth: 2.2)
    ctx.fill(ov(r * 0.42, r * 0.14, r * 1.16, r * 0.52), with: vgrad([.white.opacity(0.7), .white.opacity(0.05)], r * 0.14, r * 0.7))
    ctx.stroke(circ(CGPoint(x: c.x, y: c.y + d / 2), r), with: .color(outline), lineWidth: 2.2)
}

/// One decorative prop per item on the open side, themed by world (seeded like Android: same prop per level).
func drawScenery(_ ctx: GraphicsContext, _ size: CGSize, _ n: Int, _ world: Int) {
    let rnd = KotlinRandom(intSeed: n &* 7919 &+ 13)
    if rnd.nextFloat() < 0.18 { return }
    let w = size.width
    let h = size.height
    let side = scenerySide(n)
    let cx: CGFloat = side < 0 ? w * CGFloat(0.1 + rnd.nextFloat() * 0.1) : w * CGFloat(0.8 + rnd.nextFloat() * 0.1)
    let by = h * CGFloat(0.62 + rnd.nextFloat() * 0.3)
    let s = CGFloat(54 + rnd.nextFloat() * 22)
    let kind = rnd.nextInt(3)
    let tint = rnd.nextInt(4)
    ctx.fill(ov(cx - s * 0.34, by - s * 0.05, s * 0.68, s * 0.12), with: .color(Color(argb: 0x2E140A3C)))
    switch Kt.mod(world, 5) {
    case 0:
        switch kind { case 0: lollipop(ctx, cx, by, s, tint); case 1: candyCane(ctx, cx, by, s); default: gumdrop(ctx, cx, by, s, tint) }
    case 1:
        switch kind { case 0: seaweed(ctx, cx, by, s); case 1: coral(ctx, cx, by, s, tint); default: shell(ctx, cx, by, s) }
    case 2:
        switch kind { case 0: planet(ctx, cx, by - s * 0.3, s, tint); case 1: moon(ctx, cx, by - s * 0.3, s); default: starCluster(ctx, cx, by - s * 0.3, s) }
    case 3:
        switch kind { case 0: crystals(ctx, cx, by, s, tint); case 1: palm(ctx, cx, by, s); default: cactus(ctx, cx, by, s, w) }
    default:
        switch kind { case 0: pine(ctx, cx, by, s); case 1: mushroom(ctx, cx, by, s); default: bush(ctx, cx, by, s) }
    }
    // a couple of tiny sparkles near the prop
    for _ in 0..<2 {
        let sx = cx + CGFloat(rnd.nextFloat() - 0.5) * s * 1.2
        let sy = by - s * CGFloat(0.4 + rnd.nextFloat() * 0.8)
        let sr = CGFloat(3 + rnd.nextFloat() * 4)
        drawSparkle(ctx, sx, sy, sr, .white.opacity(0.6))
    }
}

private let CandyTints = [Color(argb: 0xFFFF5FA2), Color(argb: 0xFF33D6F5), Color(argb: 0xFFFFC93C), Color(argb: 0xFF8EF08A)]
private let Ink = Color(argb: 0xFF2A1463)

private func outlinePath(_ ctx: GraphicsContext, _ p: Path, _ w: CGFloat = 2, _ c: Color = Ink.opacity(0.55)) {
    ctx.stroke(p, with: .color(c), style: StrokeStyle(lineWidth: w, lineJoin: .round))
}

// ---------------- Candy Lab

private func lollipop(_ ctx: GraphicsContext, _ cx: CGFloat, _ by: CGFloat, _ s: CGFloat, _ tint: Int) {
    ctx.fill(rrect(cx - s * 0.045, by - s * 0.62, s * 0.09, s * 0.62, s * 0.04), with: .color(Color(argb: 0xFFDCD3F2)))
    ctx.fill(rrect(cx - s * 0.03, by - s * 0.62, s * 0.035, s * 0.6, s * 0.02), with: .color(.white))
    let c = CGPoint(x: cx, y: by - s * 0.78)
    let r = s * 0.3
    let col = CandyTints[tint]
    ctx.fill(circ(c, r), with: .color(col))
    for i in 0..<3 {
        let rr = r * (0.82 - CGFloat(i) * 0.24)
        ctx.stroke(arcPath(CGRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2), CGFloat(i) * 120, 210),
                   with: .color(.white.opacity(0.9)), style: StrokeStyle(lineWidth: r * 0.15, lineCap: .round))
    }
    ctx.fill(ov(c.x - r * 0.6, c.y - r * 0.75, r * 0.7, r * 0.35), with: .color(.white.opacity(0.55)))
    ctx.stroke(circ(c, r), with: .color(Ink.opacity(0.55)), lineWidth: 2)
}

private func candyCane(_ ctx: GraphicsContext, _ cx: CGFloat, _ by: CGFloat, _ s: CGFloat) {
    var p = Path()
    p.move(to: CGPoint(x: cx + s * 0.12, y: by))
    p.addLine(to: CGPoint(x: cx + s * 0.12, y: by - s * 0.7))
    p.addCurve(to: CGPoint(x: cx - s * 0.3, y: by - s * 0.74),
               control1: CGPoint(x: cx + s * 0.12, y: by - s * 1.02), control2: CGPoint(x: cx - s * 0.3, y: by - s * 1.02))
    ctx.stroke(p, with: .color(Ink.opacity(0.55)), style: StrokeStyle(lineWidth: s * 0.2, lineCap: .round))
    ctx.stroke(p, with: .color(.white), style: StrokeStyle(lineWidth: s * 0.16, lineCap: .round))
    ctx.stroke(p, with: .color(Color(argb: 0xFFFF4D5E)), style: StrokeStyle(lineWidth: s * 0.16, lineCap: .butt, dash: [s * 0.09, s * 0.09]))
    ctx.stroke(p, with: .color(.white.opacity(0.5)), style: StrokeStyle(lineWidth: s * 0.04, lineCap: .round))
}

/// Compose `Color.compositeOver` as used by the gumdrop (white 80 % over the tint).
private func whiteOver(_ col: Color, _ a: Double) -> Color {
    let r = col.resolve(in: EnvironmentValues())
    return Color(.sRGB, red: Double(a + Double(r.red) * (1 - a)), green: Double(a + Double(r.green) * (1 - a)), blue: Double(a + Double(r.blue) * (1 - a)), opacity: 1)
}
private let GumTops: [Color] = CandyTints.map { whiteOver($0, 0.8) }

private func gumdrop(_ ctx: GraphicsContext, _ cx: CGFloat, _ by: CGFloat, _ s: CGFloat, _ tint: Int) {
    let ti = (tint + 1) % 4
    let col = CandyTints[ti]
    var p = Path()
    p.move(to: CGPoint(x: cx - s * 0.36, y: by))
    p.addCurve(to: CGPoint(x: cx, y: by - s * 0.7), control1: CGPoint(x: cx - s * 0.4, y: by - s * 0.55), control2: CGPoint(x: cx - s * 0.18, y: by - s * 0.7))
    p.addCurve(to: CGPoint(x: cx + s * 0.36, y: by), control1: CGPoint(x: cx + s * 0.18, y: by - s * 0.7), control2: CGPoint(x: cx + s * 0.4, y: by - s * 0.55))
    p.closeSubpath()
    ctx.fill(p, with: vgrad([GumTops[ti], col], by - s * 0.7, by))
    for i in 0..<7 {
        let a = CGFloat(i) * 0.9
        ctx.fill(circ(CGPoint(x: cx + cos(a) * s * 0.2, y: by - s * 0.32 + sin(a * 1.7) * s * 0.16), s * 0.025), with: .color(.white.opacity(0.85)))
    }
    ctx.fill(ov(cx - s * 0.22, by - s * 0.6, s * 0.18, s * 0.12), with: .color(.white.opacity(0.6)))
    outlinePath(ctx, p)
}

// ---------------- Ocean

private func seaweed(_ ctx: GraphicsContext, _ cx: CGFloat, _ by: CGFloat, _ s: CGFloat) {
    let blades: [(CGFloat, CGFloat)] = [(-0.16, 0.95), (0, 1.15), (0.16, 0.8)]
    for (i, b) in blades.enumerated() {
        let (dx, hh) = b
        var p = Path()
        p.move(to: CGPoint(x: cx + dx * s, y: by))
        p.addCurve(to: CGPoint(x: cx + dx * s + s * 0.06, y: by - s * hh),
                   control1: CGPoint(x: cx + dx * s + s * 0.18, y: by - s * hh * 0.35),
                   control2: CGPoint(x: cx + dx * s - s * 0.18, y: by - s * hh * 0.65))
        ctx.stroke(p, with: .color(Color(argb: 0xFF0E6B4A)), style: StrokeStyle(lineWidth: s * 0.13, lineCap: .round))
        ctx.stroke(p, with: .color(i == 1 ? Color(argb: 0xFF3CCB7A) : Color(argb: 0xFF2FAE6A)), style: StrokeStyle(lineWidth: s * 0.09, lineCap: .round))
        ctx.stroke(p, with: .color(.white.opacity(0.3)), style: StrokeStyle(lineWidth: s * 0.025, lineCap: .round))
    }
    for k in 0..<3 {
        let kk = CGFloat(k)
        ctx.stroke(circ(CGPoint(x: cx + s * 0.28, y: by - s * (0.7 + kk * 0.22)), s * (0.035 + kk * 0.012)), with: .color(.white.opacity(0.6)), lineWidth: 1.5)
    }
}

private func coral(_ ctx: GraphicsContext, _ cx: CGFloat, _ by: CGFloat, _ s: CGFloat, _ tint: Int) {
    let col = tint % 2 == 0 ? Color(argb: 0xFFFF7A9E) : Color(argb: 0xFFFF9F5A)
    let branches: [[CGFloat]] = [
        [0, 0, 0, -0.75], [0, -0.35, -0.28, -0.68], [0, -0.28, 0.26, -0.6],
        [-0.28, -0.68, -0.34, -0.88], [0.26, -0.6, 0.36, -0.8], [0, -0.75, 0.08, -0.95],
    ]
    for b in branches {
        ctx.stroke(line(CGPoint(x: cx + b[0] * s, y: by + b[1] * s), CGPoint(x: cx + b[2] * s, y: by + b[3] * s)),
                   with: .color(Ink.opacity(0.5)), style: StrokeStyle(lineWidth: s * 0.15, lineCap: .round))
    }
    for b in branches {
        ctx.stroke(line(CGPoint(x: cx + b[0] * s, y: by + b[1] * s), CGPoint(x: cx + b[2] * s, y: by + b[3] * s)),
                   with: .color(col), style: StrokeStyle(lineWidth: s * 0.11, lineCap: .round))
    }
    for b in branches {
        ctx.fill(circ(CGPoint(x: cx + b[2] * s - s * 0.02, y: by + b[3] * s - s * 0.02), s * 0.025), with: .color(.white.opacity(0.55)))
    }
}

private func shell(_ ctx: GraphicsContext, _ cx: CGFloat, _ by: CGFloat, _ s: CGFloat) {
    var p = Path()
    p.move(to: CGPoint(x: cx, y: by - s * 0.05))
    p.addLine(to: CGPoint(x: cx - s * 0.38, y: by - s * 0.42))
    p.addCurve(to: CGPoint(x: cx + s * 0.38, y: by - s * 0.42), control1: CGPoint(x: cx - s * 0.36, y: by - s * 0.78), control2: CGPoint(x: cx + s * 0.36, y: by - s * 0.78))
    p.closeSubpath()
    ctx.fill(p, with: vgrad([Color(argb: 0xFFFFE6D6), Color(argb: 0xFFFFB38A)], by - s * 0.72, by))
    for i in -3...3 {
        let fi = CGFloat(i)
        ctx.stroke(line(CGPoint(x: cx, y: by - s * 0.08), CGPoint(x: cx + fi * s * 0.1, y: by - s * (0.66 - abs(fi) * 0.04))),
                   with: .color(Color(argb: 0xFFE08A6A)), style: StrokeStyle(lineWidth: s * 0.025, lineCap: .round))
    }
    ctx.fill(rrect(cx - s * 0.12, by - s * 0.12, s * 0.24, s * 0.1, s * 0.04), with: .color(Color(argb: 0xFFFFC7A8)))
    outlinePath(ctx, p)
}

// ---------------- Space

private func planet(_ ctx: GraphicsContext, _ cx: CGFloat, _ cy: CGFloat, _ s: CGFloat, _ tint: Int) {
    let r = s * 0.3
    let cols: [(Color, Color)] = [
        (Color(argb: 0xFFFFB86B), Color(argb: 0xFFFF5F8F)), (Color(argb: 0xFF8FE3FF), Color(argb: 0xFF5A6BFF)),
        (Color(argb: 0xFFB9F07A), Color(argb: 0xFF2FAE8A)), (Color(argb: 0xFFFFE680), Color(argb: 0xFFFF9F1C)),
    ]
    let col = cols[tint]
    let ring = CGRect(x: cx - r * 1.75, y: cy - r * 0.45, width: r * 3.5, height: r * 0.9)
    var c = ctx
    c.translateBy(x: cx, y: cy)
    c.rotate(by: .degrees(-18))
    c.translateBy(x: -cx, y: -cy)
    c.stroke(arcPath(ring, 180, 180), with: .color(.white.opacity(0.75)), lineWidth: s * 0.05)
    c.fill(circ(CGPoint(x: cx, y: cy), r), with: vgrad([col.0, col.1], cy - r, cy + r))
    c.stroke(arcPath(CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r), 20, 140), with: .color(Color(argb: 0x33000000)), lineWidth: r * 0.3)
    c.stroke(circ(CGPoint(x: cx, y: cy), r), with: .color(Ink.opacity(0.5)), lineWidth: 1.8)
    c.stroke(arcPath(ring, 0, 180), with: .color(.white.opacity(0.9)), lineWidth: s * 0.05)
    c.fill(ov(cx - r * 0.6, cy - r * 0.75, r * 0.6, r * 0.3), with: .color(.white.opacity(0.5)))
}

private func moon(_ ctx: GraphicsContext, _ cx: CGFloat, _ cy: CGFloat, _ s: CGFloat) {
    let r = s * 0.3
    let c = CGPoint(x: cx, y: cy)
    ctx.fill(circ(c, r * 1.35), with: .color(Color(argb: 0x40FFFFFF)))
    ctx.fill(circ(c, r), with: vgrad([Color(argb: 0xFFFFFBEA), Color(argb: 0xFFE0D8F5)], cy - r, cy + r))
    ctx.fill(circ(CGPoint(x: cx - r * 0.3, y: cy - r * 0.2), r * 0.22), with: .color(Color(argb: 0xFFCFC6EA)))
    ctx.fill(circ(CGPoint(x: cx + r * 0.35, y: cy + r * 0.25), r * 0.14), with: .color(Color(argb: 0xFFCFC6EA)))
    ctx.fill(circ(CGPoint(x: cx + r * 0.1, y: cy - r * 0.5), r * 0.1), with: .color(Color(argb: 0xFFCFC6EA)))
    ctx.stroke(circ(c, r), with: .color(Ink.opacity(0.4)), lineWidth: 1.5)
}

private func starCluster(_ ctx: GraphicsContext, _ cx: CGFloat, _ cy: CGFloat, _ s: CGFloat) {
    let pts: [(CGFloat, CGFloat, CGFloat)] = [(0, 0, 0.22), (-0.3, 0.25, 0.12), (0.28, -0.22, 0.1), (0.22, 0.3, 0.08)]
    for (dx, dy, r) in pts { drawSparkle(ctx, cx + dx * s, cy + dy * s, r * s, Color(argb: 0xFFFFF3B0)) }
    ctx.fill(circ(CGPoint(x: cx - s * 0.12, y: cy - s * 0.3), s * 0.03), with: .color(.white.opacity(0.8)))
    ctx.fill(circ(CGPoint(x: cx + s * 0.35, y: cy + s * 0.05), s * 0.025), with: .color(.white.opacity(0.8)))
}

// ---------------- Sunset

private func crystals(_ ctx: GraphicsContext, _ cx: CGFloat, _ by: CGFloat, _ s: CGFloat, _ tint: Int) {
    let cols: [(Color, Color)] = [
        (Color(argb: 0xFFFF8AD8), Color(argb: 0xFFB04FE0)), (Color(argb: 0xFF8FE3FF), Color(argb: 0xFF5A6BFF)),
        (Color(argb: 0xFFFFD36E), Color(argb: 0xFFFF7A59)), (Color(argb: 0xFFC6A8FF), Color(argb: 0xFF7A3FE0)),
    ]
    let col = cols[tint]
    let gems: [(CGFloat, CGFloat, CGFloat)] = [(0, 0.95, 0.17), (-0.22, 0.62, 0.13), (0.22, 0.7, 0.14)]
    for (dx, hh, ww) in gems {
        let x = cx + dx * s
        var p = Path()
        p.move(to: CGPoint(x: x - ww * s, y: by))
        p.addLine(to: CGPoint(x: x - ww * s, y: by - hh * s * 0.72))
        p.addLine(to: CGPoint(x: x, y: by - hh * s))
        p.addLine(to: CGPoint(x: x + ww * s, y: by - hh * s * 0.72))
        p.addLine(to: CGPoint(x: x + ww * s, y: by))
        p.closeSubpath()
        ctx.fill(p, with: hgrad([col.0, col.1], x - ww * s, x + ww * s))
        var f = Path()
        f.move(to: CGPoint(x: x, y: by - hh * s))
        f.addLine(to: CGPoint(x: x, y: by))
        f.addLine(to: CGPoint(x: x - ww * s, y: by))
        f.addLine(to: CGPoint(x: x - ww * s, y: by - hh * s * 0.72))
        f.closeSubpath()
        ctx.fill(f, with: .color(.white.opacity(0.25)))
        outlinePath(ctx, p)
    }
}

private func palm(_ ctx: GraphicsContext, _ cx: CGFloat, _ by: CGFloat, _ s: CGFloat) {
    var trunk = Path()
    trunk.move(to: CGPoint(x: cx, y: by))
    trunk.addCurve(to: CGPoint(x: cx + s * 0.06, y: by - s * 0.95), control1: CGPoint(x: cx + s * 0.05, y: by - s * 0.4), control2: CGPoint(x: cx + s * 0.12, y: by - s * 0.7))
    ctx.stroke(trunk, with: .color(Color(argb: 0xFF6B3A2E)), style: StrokeStyle(lineWidth: s * 0.12, lineCap: .round))
    ctx.stroke(trunk, with: .color(Color(argb: 0xFFB0704A)), style: StrokeStyle(lineWidth: s * 0.08, lineCap: .round, dash: [s * 0.07, s * 0.03]))
    let top = CGPoint(x: cx + s * 0.06, y: by - s * 0.95)
    for i in 0..<5 {
        let a = (-160 + CGFloat(i) * 35) * .pi / 180
        let end = CGPoint(x: top.x + cos(a) * s * 0.42, y: top.y + sin(a) * s * 0.42 + s * 0.18)
        var leaf = Path()
        leaf.move(to: top)
        leaf.addQuadCurve(to: end, control: CGPoint(x: top.x + cos(a) * s * 0.3, y: top.y + sin(a) * s * 0.3 - s * 0.08))
        ctx.stroke(leaf, with: .color(Color(argb: 0xFF145E3A)), style: StrokeStyle(lineWidth: s * 0.11, lineCap: .round))
        ctx.stroke(leaf, with: .color(Color(argb: 0xFF3CB46A)), style: StrokeStyle(lineWidth: s * 0.075, lineCap: .round))
    }
    ctx.fill(circ(CGPoint(x: top.x - s * 0.04, y: top.y + s * 0.04), s * 0.05), with: .color(Color(argb: 0xFF7A4A2E)))
}

/// `width`: the row width (Compose's default horizontalGradient spans the whole draw area).
private func cactus(_ ctx: GraphicsContext, _ cx: CGFloat, _ by: CGFloat, _ s: CGFloat, _ width: CGFloat) {
    let g = hgrad([Color(argb: 0xFF5ED38A), Color(argb: 0xFF239A5C)], 0, width)
    ctx.fill(rrect(cx - s * 0.13, by - s * 0.82, s * 0.26, s * 0.82, s * 0.13), with: .color(Ink.opacity(0.5)))
    ctx.fill(rrect(cx - s * 0.11, by - s * 0.8, s * 0.22, s * 0.8, s * 0.11), with: g)
    var armL = Path()
    armL.move(to: CGPoint(x: cx - s * 0.1, y: by - s * 0.38)); armL.addLine(to: CGPoint(x: cx - s * 0.28, y: by - s * 0.38)); armL.addLine(to: CGPoint(x: cx - s * 0.28, y: by - s * 0.62))
    var armR = Path()
    armR.move(to: CGPoint(x: cx + s * 0.1, y: by - s * 0.48)); armR.addLine(to: CGPoint(x: cx + s * 0.26, y: by - s * 0.48)); armR.addLine(to: CGPoint(x: cx + s * 0.26, y: by - s * 0.7))
    for a in [armL, armR] {
        ctx.stroke(a, with: .color(Ink.opacity(0.5)), style: StrokeStyle(lineWidth: s * 0.15, lineCap: .round, lineJoin: .round))
        ctx.stroke(a, with: .color(Color(argb: 0xFF3CB46A)), style: StrokeStyle(lineWidth: s * 0.11, lineCap: .round, lineJoin: .round))
    }
    ctx.stroke(line(CGPoint(x: cx - s * 0.04, y: by - s * 0.72), CGPoint(x: cx - s * 0.04, y: by - s * 0.12)), with: .color(.white.opacity(0.4)), style: StrokeStyle(lineWidth: s * 0.03, lineCap: .round))
    ctx.fill(circ(CGPoint(x: cx, y: by - s * 0.82), s * 0.07), with: .color(Color(argb: 0xFFFF5FA2)))
    ctx.fill(circ(CGPoint(x: cx, y: by - s * 0.82), s * 0.03), with: .color(Color(argb: 0xFFFFC93C)))
}

// ---------------- Forest

private func pine(_ ctx: GraphicsContext, _ cx: CGFloat, _ by: CGFloat, _ s: CGFloat) {
    ctx.fill(rrect(cx - s * 0.06, by - s * 0.2, s * 0.12, s * 0.2, s * 0.03), with: .color(Color(argb: 0xFF6B3A2E)))
    let tiers: [(CGFloat, CGFloat, Color)] = [(0.18, 0.4, Color(argb: 0xFF1E7A4C)), (0.42, 0.33, Color(argb: 0xFF2A9A5C)), (0.64, 0.25, Color(argb: 0xFF3CB46A))]
    for (y, hw, col) in tiers {
        let base = by - s * y
        var p = Path()
        p.move(to: CGPoint(x: cx - s * hw, y: base)); p.addLine(to: CGPoint(x: cx, y: base - s * 0.42)); p.addLine(to: CGPoint(x: cx + s * hw, y: base)); p.closeSubpath()
        ctx.fill(p, with: .color(col))
        var f = Path()
        f.move(to: CGPoint(x: cx, y: base - s * 0.42)); f.addLine(to: CGPoint(x: cx - s * hw, y: base)); f.addLine(to: CGPoint(x: cx - s * hw * 0.4, y: base)); f.closeSubpath()
        ctx.fill(f, with: .color(.white.opacity(0.18)))
        outlinePath(ctx, p, 1.8)
    }
}

private func mushroom(_ ctx: GraphicsContext, _ cx: CGFloat, _ by: CGFloat, _ s: CGFloat) {
    ctx.fill(rrect(cx - s * 0.1, by - s * 0.42, s * 0.2, s * 0.42, s * 0.08), with: .color(Color(argb: 0xFFF6EBDD)))
    ctx.stroke(rrect(cx - s * 0.1, by - s * 0.42, s * 0.2, s * 0.42, s * 0.08), with: .color(Ink.opacity(0.4)), lineWidth: 1.6)
    var cap = Path()
    cap.move(to: CGPoint(x: cx - s * 0.4, y: by - s * 0.38))
    cap.addCurve(to: CGPoint(x: cx + s * 0.4, y: by - s * 0.38), control1: CGPoint(x: cx - s * 0.4, y: by - s * 0.88), control2: CGPoint(x: cx + s * 0.4, y: by - s * 0.88))
    cap.closeSubpath()
    ctx.fill(cap, with: vgrad([Color(argb: 0xFFFF7A7A), Color(argb: 0xFFE8273D)], by - s * 0.8, by - s * 0.38))
    ctx.fill(circ(CGPoint(x: cx - s * 0.16, y: by - s * 0.58), s * 0.06), with: .color(.white))
    ctx.fill(circ(CGPoint(x: cx + s * 0.14, y: by - s * 0.66), s * 0.045), with: .color(.white))
    ctx.fill(circ(CGPoint(x: cx + s * 0.24, y: by - s * 0.47), s * 0.04), with: .color(.white))
    ctx.fill(circ(CGPoint(x: cx - s * 0.02, y: by - s * 0.74), s * 0.035), with: .color(.white))
    outlinePath(ctx, cap)
}

private func bush(_ ctx: GraphicsContext, _ cx: CGFloat, _ by: CGFloat, _ s: CGFloat) {
    let blobs: [(CGFloat, CGFloat, CGFloat)] = [(-0.2, -0.24, 0.24), (0.2, -0.24, 0.24), (0, -0.4, 0.28)]
    for (dx, dy, r) in blobs { ctx.fill(circ(CGPoint(x: cx + dx * s, y: by + dy * s), r * s + 1.5), with: .color(Ink.opacity(0.45))) }
    for (dx, dy, r) in blobs {
        ctx.fill(circ(CGPoint(x: cx + dx * s, y: by + dy * s), r * s), with: vgrad([Color(argb: 0xFF7BE07F), Color(argb: 0xFF2A9A5C)], by + (dy - r) * s, by + (dy + r) * s))
    }
    for k in 0..<4 {
        let kk = CGFloat(k)
        ctx.fill(circ(CGPoint(x: cx + (kk - 1.5) * s * 0.14, y: by - s * (0.3 + CGFloat(k % 2) * 0.16)), s * 0.045), with: .color(Color(argb: 0xFFFF4D6D)))
    }
    ctx.fill(ov(cx - s * 0.16, by - s * 0.62, s * 0.22, s * 0.1), with: .color(.white.opacity(0.35)))
}
