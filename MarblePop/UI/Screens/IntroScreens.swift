import SwiftUI
import GameKit

// ============================================================ SPLASH

/// Size of the iOS launch-screen mark (`LaunchMark`, 200 pt). The splash starts exactly like it and ends at the
/// Android composition size (288 dp logo × 0.8 ≈ the mark at 206 pt).
private let LaunchMarkSize: CGFloat = 200
private let LogoEndScale: CGFloat = 206 / 200

/// Starts identical to the launch screen (same purple, same mark, same size), then the sky fades in,
/// the logo glides up and the title pops in word by word while a glass tube loads.
struct SplashScreen: View {
    let onDone: () -> Void
    @Environment(SoundManager.self) var sound
    @State var words: [CGFloat] = [0, 0, 0]
    @State var started = false

    init(onDone: @escaping () -> Void) { self.onDone = onDone }

    var body: some View {
        FrameClock { t in
            let ms = t * 1000
            let intro = CGFloat(ComposeEasing.enter((ms - 120) / 720))
            let progress = CGFloat(ComposeEasing.fastOutSlowIn((ms - 200) / 2700))
            let tagline = CGFloat(ComposeEasing.fastOutSlowIn((ms - 1010) / 450))
            ZStack {
                Color(argb: 0xFF6A44F0).ignoresSafeArea()
                ZStack {
                    SkyBackground(Skies.Menu).ignoresSafeArea()
                    SunRays(alpha: 0.16, degPerSec: 9)
                        .frame(width: 620, height: 620)
                        .offset(y: -130)
                }
                .opacity(Double(intro))
                Image("LaunchMark")
                    .resizable()
                    .frame(width: LaunchMarkSize, height: LaunchMarkSize)
                    .scaleEffect(1 + (LogoEndScale - 1) * intro)
                    .offset(y: -intro * 130 + CGFloat(sin(t * 2.2)) * 4 * intro)
                VStack(spacing: 0) {
                    let spec: [(String, Brush, CGFloat)] = [("Marble", Grad.Gold, 54), ("Pop", Grad.Pink, 78), ("Factory", Grad.Aqua, 50)]
                    ForEach(0..<3, id: \.self) { i in
                        OutlinedText(spec[i].0, fontSize: spec[i].2, outline: GameColors.Night, brush: spec[i].1, gloss: true)
                            .fixedSize()
                            .modifier(WordPop(v: words[i], i: i))
                            .offset(y: CGFloat(-i * 12))
                    }
                    Text("Tap  ·  Pop  ·  Sort!")
                        .font(GameFonts.fredoka(18, .Bold))
                        .tracking(1)
                        .foregroundStyle(.white)
                        .opacity(Double(tagline))
                        .offset(y: -24 + (1 - tagline) * 10)
                }
                .offset(y: 64)
                VStack(spacing: 0) {
                    LoadingTube(progress: progress, t: t)
                }
                .opacity(Double(intro))
                .padding(.bottom, 64)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            }
        }
        .onAppear(perform: start)
    }

    private func start() {
        guard !started else { return }
        started = true
        for i in 0..<3 {
            withAnimation(.compose(dampingRatio: 0.45, stiffness: 380).delay(0.5 + 0.17 * Double(i))) { words[i] = 1 }
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 500_000_000)
            for i in 0..<3 {
                sound.play(.POP, 1 + Float(i) * 0.12, 0.7)
                try? await Task.sleep(nanoseconds: 170_000_000)
            }
            sound.play(.CUP_COMPLETE)
            try? await Task.sleep(nanoseconds: 1_650_000_000)
            onDone()
        }
    }
}

private struct WordPop: ViewModifier, Animatable {
    var v: CGFloat
    let i: Int
    var animatableData: CGFloat {
        get { v }
        set { v = newValue }
    }

    func body(content: Content) -> some View {
        content
            .scaleEffect(max(0.0001, v))
            .rotationEffect(.degrees(Double((i % 2 == 0 ? -4 : 4) * v + (1 - v) * 18)))
            .opacity(Double(min(1, max(0, v))))
    }
}

/// The loading glass tube with a marble rolling along its front, and the percentage label.
private struct LoadingTube: View {
    let progress: CGFloat
    let t: Double

    var body: some View {
        let p = progress
        VStack(spacing: 0) {
            ZStack {
                ProgressTube(Float(p), height: 30, fill: .Pink)
                    .frame(width: 250, height: 30)
                Canvas { ctx, size in
                    let w = max(size.width * p, size.height)
                    ball(ctx, CGPoint(x: w - size.height / 2, y: size.height / 2), size.height * 0.4, Kt.toInt(Float(t) * 2.5) % 7)
                }
                .frame(width: 250, height: 30)
            }
            Spacer().frame(height: 10)
            Text("Loading \(Kt.toInt(Float(p) * 100))%")
                .font(GameFonts.fredoka(15, .Bold))
                .foregroundStyle(.white.opacity(0.9))
        }
    }
}

// ============================================================ ONBOARDING (no skip)

private struct OnbPage {
    let title: String
    let text: String
}

private let pages = [
    OnbPage(title: "Tap to Pop!", text: "Tap a block with a clear path to the bottom. It bursts into a shower of shiny marbles!"),
    OnbPage(title: "Ride the Belt", text: "Marbles pour through the funnel onto the conveyor belt and loop around the track."),
    OnbPage(title: "Sort the Cups", text: "Each marble drops into a cup of the same colour. Fill a cup with 3 to clear it!"),
    OnbPage(title: "Don't Jam the Belt!", text: "The belt has limited slots. Plan your taps, chain combos and use boosters when things get busy."),
]
private let pageColors = [6, 2, 1, 3]

struct OnboardingScreen: View {
    let onFinish: () -> Void
    @Environment(SoundManager.self) var sound
    @State var page: Int? = 0
    @State var origin = Date()

    init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }

    var body: some View {
        let current = page ?? 0
        ZStack {
            SkyBackground(Skies.Menu).ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer().frame(height: 14)
                HStack(alignment: .center, spacing: 0) {
                    OutlinedText("How to play", fontSize: 22, brush: Grad.Snow)
                    Spacer().frame(width: 10)
                    OutlinedText("\(current + 1) / \(pages.count)", fontSize: 15, shadow: false)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color(argb: 0x66140A3C)))
                }
                Spacer().frame(height: 10)
                GeometryReader { geo in
                    let pageW = geo.size.width
                    ScrollView(.horizontal, showsIndicators: false) {
                        LazyHStack(spacing: 0) {
                            ForEach(0..<pages.count, id: \.self) { p in
                                OnbPageView(p: p, origin: origin, pageW: pageW)
                                    .frame(width: pageW, height: geo.size.height)
                                    .id(p)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollTargetBehavior(.paging)
                    .scrollPosition(id: $page, anchor: .center)
                }
                // marble progress dots
                HStack(alignment: .center, spacing: 8) {
                    ForEach(0..<pages.count, id: \.self) { i in
                        OnbDot(sel: i <= current ? 1 : 0, cur: i == current ? 1 : 0, color: pageColors[i])
                            .frame(width: 30, height: 30)
                            .animation(Motion.bouncy(), value: current)
                    }
                }
                Spacer().frame(height: 16)
                let last = current == pages.count - 1
                GameButton(last ? "Let's Play!" : "Next", color: last ? .Green : .Yellow, height: 68, fontSize: 30, icon: last ? .PLAY : nil, shine: last) {
                    if last { onFinish() } else {
                        withAnimation(Motion.EaseIn.tween(Motion.EMPHASIZED)) { page = current + 1 }
                    }
                }
                .frame(maxWidth: .infinity)
                .idleBounce(enabled: last)
                .padding(.horizontal, 22)
                Spacer().frame(height: 22)
            }
        }
        .onChange(of: current) { _, new in if new > 0 { sound.play(.WHOOSH, 1.2, 0.5) } }
    }
}

/// Compose `(pager.currentPage - p) + currentPageOffsetFraction` from a horizontally centred element's frame in the pager.
private func onbOffset(_ proxy: GeometryProxy, _ pageW: CGFloat) -> CGFloat {
    let f = proxy.frame(in: .scrollView)
    return pageW > 0 ? -(f.minX - (pageW - f.width) / 2) / pageW : 0
}

private struct OnbPageView: View {
    let p: Int
    let origin: Date
    let pageW: CGFloat

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                FrameClock(origin: origin) { t in
                    Canvas { ctx, size in
                        switch p {
                        case 0: demoTap(ctx, size, CGFloat(t))
                        case 1: demoBelt(ctx, size, CGFloat(t), 12, false)
                        case 2: demoSort(ctx, size, CGFloat(t))
                        default: demoBelt(ctx, size, CGFloat(t), 0, true)
                        }
                    }
                }
                if p == 3 {
                    HStack(spacing: 10) {
                        let icons: [Ico] = [.HAMMER, .MAGNET, .SLOTS, .SHUFFLE]
                        ForEach(0..<4, id: \.self) { i in
                            IconTile(icons[i], .Blue, size: 54, iconScale: 0.66)
                                .floaty(amplitude: 3, periodMs: 2200, phase: Float(i) * 0.25)
                        }
                    }
                    .padding(.bottom, 18)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                }
            }
            .background(LinearGradient(colors: [Color(argb: 0xFFFBF9FF), Color(argb: 0xFFE6DDFF)], startPoint: .top, endPoint: .bottom))
            .clipShape(RoundedRectangle(cornerRadius: 33, style: .continuous))
            .padding(5)
            .background(RoundedRectangle(cornerRadius: 38, style: .continuous)
                .fill(LinearGradient(colors: [.white, Color(argb: 0xFFD9CCFF)], startPoint: .top, endPoint: .bottom)))
            .background(RoundedRectangle(cornerRadius: 38, style: .continuous).fill(Color(argb: 0x4D0D0530)).offset(y: 12))
            .aspectRatio(0.95, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .visualEffect { content, proxy in
                let o = onbOffset(proxy, pageW)
                return content
                    .offset(x: o * proxy.size.width * 0.32)
                    .scaleEffect(1 - min(1, abs(o)) * 0.1)
                    .rotationEffect(.degrees(Double(o * -4)))
            }
            Spacer().frame(height: 24)
            VStack(spacing: 0) {
                OutlinedText(pages[p].title, fontSize: 38, outline: GameColors.Night, brush: Grad.Gold, gloss: true)
                Spacer().frame(height: 8)
                Text(pages[p].text)
                    .textStyle(TextStyle(fontFamily: Fredoka, fontWeight: .SemiBold, fontSize: 18, color: .white, lineHeight: 25, textAlign: .Center))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .visualEffect { content, proxy in
                let o = onbOffset(proxy, pageW)
                return content
                    .offset(x: o * proxy.size.width * 0.12)
                    .opacity(Double(1 - min(1, abs(o)) * 0.7))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
    }
}

private struct OnbDot: View, Animatable {
    var sel: CGFloat
    var cur: CGFloat
    let color: Int
    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { AnimatablePair(sel, cur) }
        set { sel = newValue.first; cur = newValue.second }
    }

    var body: some View {
        Canvas { ctx, size in
            let rIdle = size.width * 0.18
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            ctx.fill(Path(ellipseIn: CGRect(x: c.x - rIdle, y: c.y - rIdle, width: rIdle * 2, height: rIdle * 2)), with: .color(.white.opacity(0.35)))
            let r = rIdle + (size.width * 0.27 - rIdle) * sel + size.width * 0.12 * cur
            if sel > 0.02 { ball(ctx, c, r * min(max(sel, 0), 1), color) }
        }
    }
}

/// Page 1: only bottom-row blocks are open; tapping one pops it, its marbles stream out and the block above wakes up.
private func demoTap(_ ctx: GraphicsContext, _ size: CGSize, _ t: CGFloat) {
    let w = size.width
    let h = size.height
    let cell = w * 0.2
    let gx = w / 2 - cell * 1.5
    let gy = h * 0.1
    let boardW = cell * 3
    let boardH = cell * 3
    let cycle: CGFloat = 3.8
    let k = t.truncatingRemainder(dividingBy: cycle)
    let colors = [[2, 6, 1], [0, 3, 4], [5, 2, 7]] // [row from bottom][col]
    let popAt: CGFloat = 1.0
    let popped = k >= popAt && k < cycle - 0.25
    let wake = min(max((k - 1.35) / 0.4, 0), 1)
    let fadeAll: CGFloat = k > cycle - 0.25 ? (cycle - k) / 0.25 : 1
    let P = pxPt

    // board + exit chute
    let ex = gx + cell * 1.5
    var chute = Path()
    chute.move(to: CGPoint(x: gx - 14 * P, y: gy + boardH + 10 * P))
    chute.addLine(to: CGPoint(x: gx + boardW + 14 * P, y: gy + boardH + 10 * P))
    chute.addLine(to: CGPoint(x: ex + cell * 0.34, y: h * 0.84))
    chute.addLine(to: CGPoint(x: ex - cell * 0.34, y: h * 0.84))
    chute.closeSubpath()
    ctx.fill(chute, with: .color(Color(argb: 0xFFEDE6FF)))
    ctx.stroke(chute, with: .color(Color(argb: 0xFFB7A7EA)), lineWidth: 4 * P)
    ctx.fill(Path(roundedRect: CGRect(x: gx - 14 * P, y: gy - 14 * P, width: boardW + 28 * P, height: boardH + 28 * P), cornerRadius: 28 * P), with: .color(Color(argb: 0xFF8E6EF2)))
    ctx.fill(Path(roundedRect: CGRect(x: gx - 5 * P, y: gy - 5 * P, width: boardW + 10 * P, height: boardH + 10 * P), cornerRadius: 20 * P), with: .color(Color(argb: 0xFFF6F2FF)))
    // exit arrows under each column (the bottom row is the exit)
    for col in 0..<3 {
        let ax = gx + cell * (CGFloat(col) + 0.5)
        let ay = gy + boardH + 22 * P
        let bob = sin(t * 5 + CGFloat(col)) * 3 * P
        var arr = Path()
        arr.move(to: CGPoint(x: ax - 10 * P, y: ay + bob))
        arr.addLine(to: CGPoint(x: ax, y: ay + 10 * P + bob))
        arr.addLine(to: CGPoint(x: ax + 10 * P, y: ay + bob))
        ctx.stroke(arr, with: .color(Color(argb: 0xFF8E6EF2).opacity(0.55)), style: StrokeStyle(lineWidth: 5 * P, lineCap: .round))
    }

    for row in 0..<3 {
        for col in 0..<3 {
            if row == 0 && col == 1 && popped { continue }
            let x = gx + CGFloat(col) * cell
            let y = gy + CGFloat(2 - row) * cell
            let open = row == 0 || (row == 1 && col == 1 && wake >= 0.5 && popped)
            var s = cell * 0.96
            if row == 0 && col == 1 && k >= 0.78 && k <= popAt { s *= 0.9 }
            if row == 1 && col == 1 && popped && wake >= 0.01 && wake <= 0.99 { s *= 1 + 0.14 * sin(wake * .pi) }
            Painter.block(ctx, x + (cell - s) / 2, y + (cell - s) / 2, s, colors[row][col], 0, bumps: open)
        }
    }

    if popped {
        let tt = k - popAt
        let y0 = gy + 2.5 * cell
        if tt < 0.4 {
            let p = tt / 0.4
            let rr0 = cell * 0.3 + p * cell * 0.6
            ctx.stroke(Path(ellipseIn: CGRect(x: ex - rr0, y: y0 - rr0, width: rr0 * 2, height: rr0 * 2)), with: .color(.white.opacity(Double(1 - p))), lineWidth: (8 * (1 - p) + 1) * P)
            for sIdx in 0..<6 {
                let a = CGFloat(sIdx) * .pi / 3
                let rr = cell * (0.3 + p * 0.7)
                Painter.star4(ctx, ex + cos(a) * rr, y0 + sin(a) * rr, (12 * (1 - p) + 3) * P, AColor.argb(Int((1 - p) * 255), 255, 220, 90))
            }
        }
        for m in 0..<9 {
            let lt = tt - CGFloat(m) * 0.08
            if lt < 0 { continue }
            let y = y0 + lt * lt * h * 1.6 + lt * cell
            if y > h * 0.86 { continue }
            let spread = 1 - min(max((y - y0) / (h * 0.86 - y0), 0), 1)
            let x = ex + sin(CGFloat(m) * 1.7) * cell * 0.28 * spread
            ball(ctx, CGPoint(x: x, y: y), cell * 0.13, colors[0][1])
        }
    }
    // "open" sparkle on the block that just woke up
    if popped && wake > 0.3 {
        let a = min(max(1 - abs(wake - 0.65) * 2.5, 0), 1) * fadeAll
        let cx = ex
        let cy = gy + 1.5 * cell
        drawSparkle(ctx, cx + cell * 0.38, cy - cell * 0.38, 14 * P, Color(argb: 0xFFFFE680).opacity(Double(a)))
    }

    // hand
    let hx = ex + cell * 0.1
    let hy = gy + 2.6 * cell
    let approach = min(1, k / 0.65)
    let press: CGFloat = (k >= 0.65 && k <= 1.0) ? 1 : 0
    if k < 1.5 {
        let leave = min(max((k - 1.1) / 0.4, 0), 1)
        let px = hx + (1 - approach) * w * 0.3 + leave * w * 0.25
        let py = hy + (1 - approach) * h * 0.2 + press * 8 * P + leave * h * 0.12
        let alpha = Double(1 - leave)
        let rr = cell * 0.22
        ctx.fill(Path(ellipseIn: CGRect(x: px - rr, y: py - rr, width: rr * 2, height: rr * 2)), with: .color(.white.opacity(alpha)))
        ctx.fill(Path(roundedRect: CGRect(x: px - cell * 0.1, y: py, width: cell * 0.38, height: cell * 0.5), cornerRadius: cell * 0.15), with: .color(.white.opacity(alpha)))
        ctx.stroke(Path(ellipseIn: CGRect(x: px - rr, y: py - rr, width: rr * 2, height: rr * 2)), with: .color(GameColors.Ink.opacity(alpha)), lineWidth: 4 * P)
        if press > 0 {
            let r2 = cell * 0.42
            ctx.stroke(Path(ellipseIn: CGRect(x: px - r2, y: py - 6 * P - r2, width: r2 * 2, height: r2 * 2)), with: .color(.white.opacity(0.7)), lineWidth: 5 * P)
        }
    }
}

private func demoBelt(_ ctx: GraphicsContext, _ size: CGSize, _ t: CGFloat, _ fixedCount: Int, _ danger: Bool) {
    let w = size.width
    let h = size.height
    let P = pxPt
    let cy = h * 0.42
    let r = h * 0.12
    let left = w * 0.18
    let right = w * 0.82
    let straight = right - left
    let len = 2 * straight + 2 * .pi * r
    ctx.fill(Path(roundedRect: CGRect(x: left - r - 26 * P, y: cy - r - 26 * P, width: straight + 2 * r + 52 * P, height: 2 * r + 52 * P), cornerRadius: r + 26 * P), with: .color(Color(argb: 0xFFC6B9EE)))
    ctx.fill(Path(roundedRect: CGRect(x: left - r - 16 * P, y: cy - r - 16 * P, width: straight + 2 * r + 32 * P, height: 2 * r + 32 * P), cornerRadius: r + 16 * P), with: .color(Color(argb: 0xFF3B2F86)))
    ctx.fill(Path(roundedRect: CGRect(x: left - r + 18 * P, y: cy - r + 18 * P, width: straight + 2 * r - 36 * P, height: 2 * r - 36 * P), cornerRadius: max(0, r - 18 * P)), with: .color(.white))
    let slots = 30
    let count = danger ? Int(min((t.truncatingRemainder(dividingBy: 5)) / 4, 1) * CGFloat(slots)) : fixedCount
    let off = t * 90 * P
    func pt(_ s0: CGFloat) -> CGPoint {
        var s = s0.truncatingRemainder(dividingBy: len)
        if s < 0 { s += len }
        let half = straight / 2
        let arc = .pi * r
        if s < half { return CGPoint(x: w / 2 + s, y: cy - r) }
        if s < half + arc { let a = (s - half) / r; return CGPoint(x: right + r * sin(a), y: cy - r * cos(a)) }
        if s < half + arc + straight { return CGPoint(x: right - (s - half - arc), y: cy + r) }
        if s < half + 2 * arc + straight { let a = (s - half - arc - straight) / r; return CGPoint(x: left - r * sin(a), y: cy + r * cos(a)) }
        return CGPoint(x: left + (s - half - 2 * arc - straight), y: cy - r)
    }
    for i in 0..<slots {
        let p = pt(CGFloat(i) * len / CGFloat(slots) + off)
        let rr = r * 0.2
        ctx.fill(Path(ellipseIn: CGRect(x: p.x - rr, y: p.y - rr, width: rr * 2, height: rr * 2)), with: .color(Color(argb: 0xFF1E1750)))
    }
    let beltCols = [0, 1, 2, 3, 4, 6]
    for i in 0..<min(count, slots) { ball(ctx, pt(CGFloat(i) * len / CGFloat(slots) + off), r * 0.21, beltCols[i % 6]) }
    if !danger {
        var funnel = Path()
        funnel.move(to: CGPoint(x: w * 0.3, y: h * 0.02))
        funnel.addLine(to: CGPoint(x: w * 0.7, y: h * 0.02))
        funnel.addLine(to: CGPoint(x: w / 2 + 20 * P, y: cy - r - 30 * P))
        funnel.addLine(to: CGPoint(x: w / 2 - 20 * P, y: cy - r - 30 * P))
        funnel.closeSubpath()
        ctx.fill(funnel, with: .color(Color(argb: 0xFFEDE6FF)))
        ctx.stroke(funnel, with: .color(Color(argb: 0xFFB7A7EA)), lineWidth: 4 * P)
        let fall = (t * 1.6).truncatingRemainder(dividingBy: 1)
        ball(ctx, CGPoint(x: w / 2, y: h * 0.08 + fall * (cy - r - h * 0.1)), r * 0.21, 2)
        for k in 0..<3 {
            let cx = w * (0.3 + CGFloat(k) * 0.2)
            Painter.cup(ctx, cx - w * 0.08, h * 0.7, w * 0.16, h * 0.09, k * 2, false)
        }
    } else {
        let ratio = CGFloat(count) / CGFloat(slots)
        let col: Int = ratio > 0.78 ? 0xFFFF4D5E : 0xFF6A5ACD
        Painter.text(ctx, "\(count)/\(slots)", w / 2, cy, r * 0.7, col, 0xFFFFFFFF, 6 * P)
        if ratio > 0.78 {
            let a = 0.5 + 0.5 * sin(t * 10)
            ctx.stroke(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 36 * P), with: .color(Color(argb: 0xFFFF2E4A).opacity(Double(0.35 * a))), lineWidth: 26 * P)
            Painter.text(ctx, "Almost full!", w / 2, h * 0.68, h * 0.07, 0xFFFF4D5E, 0xFFFFFFFF, 8 * P)
        }
    }
}

private func demoSort(_ ctx: GraphicsContext, _ size: CGSize, _ t: CGFloat) {
    let w = size.width
    let h = size.height
    let P = pxPt
    let cupW = w * 0.24
    let cupH = h * 0.13
    let cupY = h * 0.6
    let cycle: CGFloat = 3
    let k = t.truncatingRemainder(dividingBy: cycle)
    let colors = [2, 6, 1]
    let target = 1
    for i in 0..<3 {
        let cx = w * (0.22 + CGFloat(i) * 0.28)
        var y = cupY
        var s: CGFloat = 1
        if i == target && k > 2.1 { let p = (k - 2.1) / 0.6; s = 1 + 0.3 * sin(min(1, p) * .pi / 2); y -= p * 40 * P }
        if i == target && k > 2.7 { continue }
        var sc = ctx
        sc.translateBy(x: cx, y: y + cupH / 2)
        sc.scaleBy(x: s, y: s)
        sc.translateBy(x: -cx, y: -(y + cupH / 2))
        Painter.cup(sc, cx - cupW / 2, y, cupW, cupH, colors[i], false)
        Painter.cup(ctx, cx - cupW / 2, cupY + cupH * 1.15, cupW, cupH, colors[(i + 1) % 3], false)
        if i == target {
            let landed = min(max(Int((k - 0.3) / 0.6), 0), 3)
            if k <= 2.7 {
                for m in 0..<landed {
                    ball(ctx, CGPoint(x: cx + CGFloat(m - 1) * cupW * 0.28, y: y + cupH * 0.3 - 4 * P), cupH * 0.2, colors[i])
                }
            }
            let falling = ((k - 0.3).truncatingRemainder(dividingBy: 0.6)) / 0.6
            let idx = Int((k - 0.3) / 0.6)
            if k > 0.3 && idx < 3 {
                let tx = cx + CGFloat(idx - 1) * cupW * 0.28
                ball(ctx, CGPoint(x: tx, y: h * 0.15 + falling * falling * (y - h * 0.15)), cupH * 0.2, colors[i])
            }
            if k >= 2.1 && k <= 2.9 {
                let p = (k - 2.1) / 0.8
                for sIdx in 0..<8 {
                    let a = CGFloat(sIdx) * .pi / 4
                    let rr = p * w * 0.22
                    Painter.star4(ctx, cx + cos(a) * rr, y + cupH / 2 + sin(a) * rr, (14 * (1 - p) + 4) * P, AColor.argb(Int((1 - p) * 255), 255, 210, 63))
                }
            }
        }
    }
    Painter.text(ctx, "3 = clear!", w / 2, h * 0.92, h * 0.07, 0xFF7B4DFF, 0xFFFFFFFF, 8 * P)
}
