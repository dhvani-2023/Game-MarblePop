import SwiftUI
import GameKit

// Port of ui/components/Backgrounds.kt: layered skies, soft bokeh, sun rays and the confetti burst.

/// Kotlin `rememberTime()`: seconds since this view appeared, ticking every frame (TimelineView-driven).
/// Read the value inside a Canvas so only drawing updates.
struct TimeTicker<Content: View>: View {
    var paused: Bool
    let content: (Float) -> Content
    @State private var start = Date()

    init(paused: Bool = false, @ViewBuilder content: @escaping (Float) -> Content) {
        self.paused = paused
        self.content = content
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: nil, paused: paused)) { tl in
            content(Float(tl.date.timeIntervalSince(start)))
        }
    }
}

/// A pre-baked soft white dot used for bokeh and glows (one bitmap, drawn with alpha + scale).
enum SoftDot {
    static let image: Image = {
        let n = 64
        let cg = Bake.image(n, n) { c in
            let p = Paint()
            p.shader = Shader.radial(CGFloat(n) / 2, CGFloat(n) / 2, CGFloat(n) / 2, [0xF2FFFFFF, 0x6BFFFFFF, 0x00FFFFFF], [0, 0.38, 1])
            c.drawCircle(CGFloat(n) / 2, CGFloat(n) / 2, CGFloat(n) / 2, p)
        }
        return Image(decorative: cg, scale: 1).interpolation(.high)
    }()
}

/// Unit-size four point sparkle (radius 1), drawn with translate + scale.
let SparklePath: Path = {
    var p = Path()
    p.move(to: CGPoint(x: 0, y: -1))
    p.addQuadCurve(to: CGPoint(x: 1, y: 0), control: CGPoint(x: 0.14, y: -0.14))
    p.addQuadCurve(to: CGPoint(x: 0, y: 1), control: CGPoint(x: 0.14, y: 0.14))
    p.addQuadCurve(to: CGPoint(x: -1, y: 0), control: CGPoint(x: -0.14, y: 0.14))
    p.addQuadCurve(to: CGPoint(x: 0, y: -1), control: CGPoint(x: -0.14, y: -0.14))
    p.closeSubpath()
    return p
}()

/// Layered sky: gradient + two coloured glows + optional candy-factory skyline (static)
/// and a light animated layer of soft bokeh and twinkles. Fills its container, including the safe areas.
struct SkyBackground: View {
    var palette: SkyPalette
    var skyline: Bool
    var particles: Bool
    var seed: Int

    init(_ palette: SkyPalette = Skies.Menu, skyline: Bool = true, particles: Bool = true, seed: Int = 7) {
        self.palette = palette
        self.skyline = skyline
        self.particles = particles
        self.seed = seed
    }

    var body: some View {
        let palette = self.palette, skyline = self.skyline
        ZStack {
            Canvas { ctx, size in
                let w = size.width, h = size.height
                let full = Path(CGRect(origin: .zero, size: size))
                ctx.fill(full, with: .linearGradient(
                    Gradient(stops: [.init(color: palette.top, location: 0), .init(color: palette.mid, location: 0.55),
                                     .init(color: palette.bottom, location: 1)]),
                    startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
                let c1 = CGPoint(x: w * 0.1, y: h * 0.18)
                let c2 = CGPoint(x: w * 0.98, y: h * 0.6)
                ctx.fill(Path(ellipseIn: CGRect(x: c1.x - w * 0.9, y: c1.y - w * 0.9, width: w * 1.8, height: w * 1.8)),
                         with: .radialGradient(Gradient(colors: [palette.glowA.opacity(0.55), palette.glowA.opacity(0)]),
                                               center: c1, startRadius: 0, endRadius: w * 0.9))
                ctx.fill(Path(ellipseIn: CGRect(x: c2.x - w * 0.85, y: c2.y - w * 0.85, width: w * 1.7, height: w * 1.7)),
                         with: .radialGradient(Gradient(colors: [palette.glowB.opacity(0.42), palette.glowB.opacity(0)]),
                                               center: c2, startRadius: 0, endRadius: w * 0.85))
                if skyline {
                    ctx.fill(skylinePath(w, h, far: true), with: .color(palette.silhouette.opacity(0.22)))
                    ctx.fill(Path(CGRect(x: 0, y: h * 0.72, width: w, height: h * 0.28)),
                             with: .linearGradient(Gradient(colors: [.clear, palette.bottom.opacity(0.55)]),
                                                   startPoint: CGPoint(x: 0, y: h * 0.72), endPoint: CGPoint(x: 0, y: h)))
                    ctx.fill(skylinePath(w, h, far: false), with: .color(palette.silhouette.opacity(0.38)))
                }
            }
            if particles { SkyParticles(seed: seed) }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// Old name kept for screens that just want the default menu sky.
struct MenuBackground: View {
    var body: some View { SkyBackground(Skies.Menu) }
}

private struct SkyParticles: View {
    let seed: Int
    var count: Int = 14
    private let parts: [[CGFloat]]

    init(seed: Int, count: Int = 14) {
        self.seed = seed
        self.count = count
        let r = KotlinRandom(intSeed: seed)
        var ps: [[CGFloat]] = []
        for _ in 0..<count {
            let x = CGFloat(r.nextFloat()), y = CGFloat(r.nextFloat())   // x, y start
            let radius = 10 + CGFloat(r.nextFloat()) * 26                  // radius dp
            let laps = CGFloat(1 + r.nextInt(3))                           // laps per minute (keeps the loop seamless)
            let sway = CGFloat(r.nextFloat()) * 6.28                       // sway phase
            let alpha = 0.10 + CGFloat(r.nextFloat()) * 0.20               // alpha
            ps.append([x, y, radius, laps, sway, alpha])
        }
        parts = ps
    }

    var body: some View {
        let parts = self.parts
        TimeTicker(paused: Motion.reduce) { tf in
            Canvas { ctx, size in
                let t = CGFloat(tf)
                let w = size.width, h = size.height
                for p in parts {
                    let period = 60 / p[3]
                    let y = ((p[1] - t / period).truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1)
                    let r = p[2]
                    let x = p[0] * w + sin(t * 0.45 + p[4]) * 14
                    let cy = y * (h + 2 * r) - r
                    var c = ctx
                    c.opacity = Double(p[5])
                    c.draw(SoftDot.image, in: CGRect(x: x - r, y: cy - r, width: 2 * r, height: 2 * r))
                }
                for i in 0..<9 {
                    let fi = CGFloat(i)
                    let a = 0.5 + 0.5 * sin(t * 2.1 + fi * 1.9)
                    let sx = (fi * 0.37 + 0.11).truncatingRemainder(dividingBy: 1) * w
                    let sy = (fi * 0.61 + 0.07).truncatingRemainder(dividingBy: 1) * h * 0.82
                    let s = 4 + 4 * a
                    var c = ctx
                    c.translateBy(x: sx, y: sy)
                    c.scaleBy(x: s, y: s)
                    c.fill(SparklePath, with: .color(.white.opacity(Double(0.2 + 0.55 * a))))
                }
            }
        }
    }
}

/// Candy-factory silhouettes: domed towers, chimneys, tanks and pipes.
private func skylinePath(_ w: CGFloat, _ h: CGFloat, far: Bool) -> Path {
    var p = Path()
    let u = w / 360
    let rnd = KotlinRandom(intSeed: far ? 11 : 29)
    let baseH = h * (far ? 0.13 : 0.075)
    var x = -12 * u
    func rr(_ l: CGFloat, _ t: CGFloat, _ r: CGFloat, _ b: CGFloat, _ cr: CGFloat) {
        p.addPath(ComposeDraw.roundRectPath(l, t, r - l, b - t, cr))
    }
    while x < w + 12 * u {
        let kind = rnd.nextInt(4)
        let bw = (far ? 38 : 46) * u * (0.75 + CGFloat(rnd.nextFloat()) * 0.6)
        let bh = baseH * (0.6 + CGFloat(rnd.nextFloat()) * 0.8)
        let top = h - bh
        switch kind {
        case 0: // domed tower
            rr(x, top, x + bw, h + 4, bw * 0.12)
            p.addEllipse(in: CGRect(x: x - bw * 0.06, y: top - bw * 0.5, width: bw * 1.12, height: bw))
        case 1: // chimney pair with round caps
            let cw = bw * 0.32
            p.addRect(CGRect(x: x, y: top - bh * 0.4, width: cw, height: h + 4 - (top - bh * 0.4)))
            p.addEllipse(in: CGRect(x: x - cw * 0.25, y: top - bh * 0.4 - cw * 0.5, width: cw * 1.5, height: cw))
            p.addRect(CGRect(x: x + cw * 1.6, y: top, width: cw * 0.9, height: h + 4 - top))
            rr(x - cw * 0.2, top + bh * 0.35, x + bw, h + 4, cw * 0.3)
        case 2: // big tank
            let r = bw * 0.62
            p.addEllipse(in: CGRect(x: x, y: h - bh * 0.9 - r, width: 2 * r, height: 2 * r))
            p.addRect(CGRect(x: x + r * 0.3, y: h - bh * 0.9, width: r * 1.4, height: h + 4 - (h - bh * 0.9)))
        default: // pipe bridge
            rr(x, top + bh * 0.45, x + bw * 1.3, top + bh * 0.62, bh * 0.1)
            p.addRect(CGRect(x: x + bw * 0.1, y: top + bh * 0.5, width: bw * 0.18, height: h + 4 - (top + bh * 0.5)))
            p.addRect(CGRect(x: x + bw * 1.0, y: top + bh * 0.5, width: bw * 0.18, height: h + 4 - (top + bh * 0.5)))
        }
        x += bw * (0.85 + CGFloat(rnd.nextFloat()) * 0.5)
    }
    return p
}

/// Slowly rotating sunburst with a soft centre glow. Centred in its frame; the rays reach
/// `max(width, height) · radiusScale` (outside the frame, like Compose).
struct SunRays: View {
    var color: Color
    var alpha: Float
    var rays: Int
    var degPerSec: Float
    var radiusScale: Float
    @State private var angle: Double = 0

    init(color: Color = .white, alpha: Float = 0.2, rays: Int = 16, degPerSec: Float = 14, radiusScale: Float = 0.75) {
        self.color = color
        self.alpha = alpha
        self.rays = rays
        self.degPerSec = degPerSec
        self.radiusScale = radiusScale
    }

    var body: some View {
        let color = self.color, alpha = Double(self.alpha), rays = max(self.rays, 1)
        GeometryReader { geo in
            let r = max(geo.size.width, geo.size.height) * CGFloat(radiusScale)
            ZStack {
                Canvas { ctx, size in
                    let c = CGPoint(x: size.width / 2, y: size.height / 2)
                    let step = 2 * CGFloat.pi / CGFloat(rays)
                    var path = Path()
                    for i in 0..<rays {
                        let a0 = CGFloat(i) * step - step * 0.23
                        let a1 = CGFloat(i) * step + step * 0.23
                        path.move(to: c)
                        path.addLine(to: CGPoint(x: c.x + cos(a0) * r, y: c.y + sin(a0) * r))
                        path.addLine(to: CGPoint(x: c.x + cos(a1) * r, y: c.y + sin(a1) * r))
                        path.closeSubpath()
                    }
                    ctx.fill(path, with: .radialGradient(Gradient(colors: [color.opacity(alpha), color.opacity(0)]),
                                                         center: c, startRadius: 0, endRadius: r))
                }
                .frame(width: r * 2, height: r * 2)
                .rotationEffect(.degrees(angle))
                Canvas { ctx, size in
                    let c = CGPoint(x: size.width / 2, y: size.height / 2)
                    let gr = r * 0.42
                    ctx.fill(Path(ellipseIn: CGRect(x: c.x - gr, y: c.y - gr, width: gr * 2, height: gr * 2)),
                             with: .radialGradient(Gradient(colors: [color.opacity(min(alpha * 1.8, 1)), color.opacity(0)]),
                                                   center: c, startRadius: 0, endRadius: gr))
                }
                .frame(width: r * 2, height: r * 2)
            }
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
        .allowsHitTesting(false)
        .onAppear {
            guard !Motion.reduce, degPerSec != 0 else { return }
            DispatchQueue.main.async {
                withAnimation(.linear(duration: 360 / Double(abs(degPerSec))).repeatForever(autoreverses: false)) {
                    angle = degPerSec > 0 ? 360 : -360
                }
            }
        }
    }
}

private let ConfettiColors: [Color] = [
    Color(argb: 0xFFFF5FA2), Color(argb: 0xFFFFC93C), Color(argb: 0xFF33D6F5), Color(argb: 0xFF8EF08A),
    Color(argb: 0xFF9775FF), Color(argb: 0xFFFF9F1C), .white,
]

/// One-shot confetti burst from the top-centre of its bounds (pieces may fly outside them). Drag keeps it floaty.
struct ConfettiBurst: View {
    var count: Int
    var seed: Int
    private let parts: [[Float]]
    @State private var done = false

    init(count: Int = 70, seed: Int = 3) {
        self.count = count
        self.seed = seed
        let r = KotlinRandom(intSeed: seed)
        var ps: [[Float]] = []
        for _ in 0..<count {
            let a = Float(-Double.pi / 2 + Double(r.nextFloat() - 0.5) * Double.pi * Double(Float(1.1)))
            let v = 380 + r.nextFloat() * 560
            let vx = Float(Foundation.cos(Double(a))) * v, vy = Float(Foundation.sin(Double(a))) * v // launch velocity dp/s
            let rot = r.nextFloat() * 360, spin = (r.nextFloat() - 0.5) * 720                       // rotation, spin
            let colour = Float(r.nextInt(ConfettiColors.count))
            let size = 6 + r.nextFloat() * 6                                                         // size dp
            let delay = r.nextFloat() * 0.3                                                          // launch delay
            let shape = Float(r.nextInt(3))                                                          // shape
            let flutter = r.nextFloat() * 6.28                                                       // flutter phase
            ps.append([vx, vy, rot, spin, colour, size, delay, shape, flutter])
        }
        parts = ps
    }

    var body: some View {
        let parts = self.parts
        TimeTicker(paused: done) { now in
            Canvas { ctx, size in
                let ox = size.width / 2
                let oy = size.height * 0.12
                let k: CGFloat = 2.4          // air drag (1/s)
                let g: CGFloat = 520          // gravity dp/s²; terminal fall speed g/k ≈ 215 dp/s
                for p in parts {
                    let tt = CGFloat(now - p[6])
                    if tt <= 0 || tt > 3.6 { continue }
                    let e = 1 - exp(-k * tt)
                    let x = ox + (CGFloat(p[0]) / k * e + sin(tt * 5 + CGFloat(p[8])) * 8)
                    let y = oy + (g / k * tt + (CGFloat(p[1]) - g / k) / k * e)
                    let alpha = tt > 2.8 ? (3.6 - tt) / 0.8 : 1
                    let col = GraphicsContext.Shading.color(ConfettiColors[Int(p[4])].opacity(Double(alpha)))
                    let s = CGFloat(p[5])
                    let rot = CGFloat(p[2]) + CGFloat(p[3]) * tt
                    let flip = cos(rot * 0.035)
                    var c = ctx
                    c.translateBy(x: x, y: y)
                    c.rotate(by: .degrees(Double(rot)))
                    c.translateBy(x: -x, y: -y)
                    switch Int(p[7]) {
                    case 0:
                        c.fill(Path(CGRect(x: x - s / 2, y: y - s * 0.3, width: s, height: s * 0.6 * min(max(flip, 0.15), 1))), with: col)
                    case 1:
                        c.fill(Path(ellipseIn: CGRect(x: x - s * 0.42, y: y - s * 0.42, width: s * 0.84, height: s * 0.84)), with: col)
                    default:
                        c.fill(ComposeDraw.roundRectPath(x - s * 0.2, y - s * 0.6, s * 0.4, s * 1.2 * min(max(flip, 0.2), 1), s * 0.2), with: col)
                    }
                }
            }
        }
        .allowsHitTesting(false)
        .task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            done = true
        }
    }
}
