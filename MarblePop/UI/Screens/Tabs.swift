import SwiftUI
import GameKit

private let WhiteBody = TextStyle(fontFamily: Fredoka, fontWeight: .SemiBold, fontSize: 14, color: .white, lineHeight: 18)

struct TabHeader: View {
    let title: String
    @Environment(GameRepository.self) var repo

    var body: some View {
        ZStack {
            OutlinedText(title, fontSize: 36, brush: Grad.Snow, gloss: true, maxLines: 1)
                .frame(maxWidth: .infinity, alignment: .leading)
            ResourcePill(.COIN, String(repo.coins))
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(height: 56)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
    }
}

/// Scrolling tab body whose edges fade out under the header and above the dock.
struct TabBody<Content: View>: View {
    @ViewBuilder let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) { self.content = content }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                Color.clear.frame(height: 2)
                content()
                Color.clear.frame(height: 26)
            }
            .padding(.horizontal, 14)
        }
        .mask {
            VStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 14)
                Color.black
                LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).frame(height: 22)
            }
        }
    }
}

/// Springy "+1 Hammer" toast that floats up and fades.
private struct RewardToast: View {
    let message: String?
    let icon: Ico?
    let token: Int
    let onDone: () -> Void
    @State var a: CGFloat = 0
    @State var gen = 0

    var body: some View {
        ZStack {
            if let message {
                ToastBody(message: message, icon: icon, v: a)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .onChange(of: token) { _, _ in run() }
    }

    /// Compose: `remember(message) { Animatable(0f) }` + spring in, 700 ms hold, 380 ms float-out, then onDone.
    private func run() {
        guard message != nil else { return }
        gen += 1
        let my = gen
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) { a = 0 }
        DispatchQueue.main.async {
            withAnimation(.compose(dampingRatio: 0.5, stiffness: 500), completionCriteria: .logicallyComplete) { a = 1 } completion: {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.7) {
                    guard gen == my else { return }
                    withAnimation(CubicBezierEasing.FastOutSlowIn.tween(380), completionCriteria: .logicallyComplete) { a = 2 } completion: {
                        if gen == my { onDone() }
                    }
                }
            }
        }
    }
}

private struct ToastBody: View, Animatable {
    let message: String
    let icon: Ico?
    var v: CGFloat
    var animatableData: CGFloat {
        get { v }
        set { v = newValue }
    }

    var body: some View {
        let s = v <= 1 ? v : 1
        HStack(spacing: 0) {
            if let icon { GameIcon(icon).frame(width: 38, height: 38); Spacer().frame(width: 8) }
            OutlinedText(message, fontSize: 26, brush: Grad.Gold, maxLines: 1)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(Capsule().fill(LinearGradient(colors: [Color(argb: 0xF22A1463), Color(argb: 0xF2140A3C)], startPoint: .top, endPoint: .bottom)))
        .overlay(Capsule().strokeBorder(.white.opacity(0.35), lineWidth: 2))
        .scaleEffect(max(0.0001, s))
        .opacity(Double(v <= 1 ? min(max(v, 0), 1) : 2 - v))
        .offset(y: v > 1 ? -(v - 1) * 60 : 0)
    }
}

/// Gradient feature card background (gift hero, daily challenge, bundle) + its 3/3/3/6 padding.
private struct FeatureCard: ViewModifier {
    let top: Color
    let bottom: Color
    let rim: Color

    func body(content: Content) -> some View {
        content
            .padding(EdgeInsets(top: 3, leading: 3, bottom: 6, trailing: 3))
            .background {
                Canvas { ctx, canvasSize in
                    let size = CGSize(width: canvasSize.width, height: canvasSize.height - 6)
                    let r: CGFloat = 26
                    ctx.fill(Path(roundedRect: CGRect(x: 0, y: 6, width: size.width, height: size.height), cornerRadius: r), with: .color(Color(argb: 0x400D0530)))
                    ctx.fill(Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: r), with: .color(rim))
                    var inner = ctx
                    inner.translateBy(x: 3, y: 3)
                    let iw = size.width - 6
                    let ih = size.height - 9
                    let ir = Path(roundedRect: CGRect(x: 0, y: 0, width: iw, height: ih), cornerRadius: r - 3)
                    inner.fill(ir, with: .linearGradient(Gradient(colors: [top, bottom]), startPoint: .zero, endPoint: CGPoint(x: 0, y: ih)))
                    inner.fill(ir, with: .linearGradient(Gradient(colors: [.white.opacity(0.3), .clear]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height * 0.45)))
                    let rnd = KotlinRandom(intSeed: 5)
                    var dots = Path()
                    for _ in 0..<14 {
                        let x = CGFloat(rnd.nextFloat()) * size.width
                        let y = CGFloat(rnd.nextFloat()) * size.height
                        let rr = CGFloat(2 + rnd.nextFloat() * 4)
                        dots.addEllipse(in: CGRect(x: x - rr, y: y - rr, width: rr * 2, height: rr * 2))
                    }
                    inner.fill(dots, with: .color(.white.opacity(0.16)))
                }
                .padding(.bottom, -6)
            }
    }
}

private extension View {
    func featureCard(_ top: Color, _ bottom: Color, _ rim: Color) -> some View { modifier(FeatureCard(top: top, bottom: bottom, rim: rim)) }
}

// ============================================================ SHOP

private func boosterHalo(_ b: Booster) -> Color {
    switch b {
    case .HAMMER: return Color(argb: 0xFFFFC27A)
    case .MAGNET: return Color(argb: 0xFFFF9AB0)
    case .SLOTS: return Color(argb: 0xFF8FE3FF)
    case .SHUFFLE: return Color(argb: 0xFFC6A8FF)
    }
}

struct ShopTab: View {
    @Environment(GameRepository.self) var repo
    @Environment(SoundManager.self) var sound
    @State var bought: (String, Ico?)? = nil
    @State var boughtToken = 0

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                TabHeader(title: "Shop")
                TabBody {
                    // hero: free coins
                    TimelineView(.periodic(from: .now, by: 1)) { tl in
                        let now = Int64(tl.date.timeIntervalSince1970 * 1000)
                        heroCard(now: now)
                    }
                    SectionTitle("Boosters", icon: .HAMMER)
                    ForEach(0..<2, id: \.self) { row in
                        WeightRow(weights: [1, 1], spacing: 12) {
                            ForEach(Booster.entries[(row * 2)..<(row * 2 + 2)], id: \.self) { b in
                                BoosterTile(b: b) { count, price in
                                    if repo.spend(price) { repo.addBooster(b, count); toast("+\(count) \(b.title)", boosterIcon(b)) }
                                }
                            }
                        }
                    }
                    megaBundle
                    Text("Coins are earned by playing: winning levels, combos, chests, daily rewards and the lucky spin.")
                        .textStyle(WhiteBody.copy(color: .white.opacity(0.85), textAlign: .Center))
                        .frame(maxWidth: .infinity)
                        .padding(8)
                }
            }
            RewardToast(message: bought?.0, icon: bought?.1, token: boughtToken) { bought = nil }
        }
    }

    private func toast(_ m: String, _ i: Ico?) { bought = (m, i); boughtToken += 1 }

    @ViewBuilder
    private func heroCard(now: Int64) -> some View {
        let ready = now >= repo.freeGiftAt
        HStack(alignment: .center, spacing: 0) {
            ZStack {
                if ready {
                    SunRays(color: Color(argb: 0xFFFFF3B0), alpha: 0.32, rays: 12, degPerSec: 20)
                        .frame(width: 170, height: 170)
                }
                GameIcon(.GIFT).frame(width: 80, height: 80).floaty(amplitude: 4, periodMs: 2200)
            }
            .frame(width: 96, height: 96)
            Spacer().frame(width: 8)
            VStack(alignment: .leading, spacing: 0) {
                OutlinedText("Free Coins", fontSize: 26, align: .Start, brush: Grad.Gold, gloss: true, maxLines: 1)
                Text("100 coins every 4 hours").textStyle(WhiteBody)
                Spacer().frame(height: 8)
                let left = max(repo.freeGiftAt - now, 0) / 1000
                GameButton(ready ? "Claim 100" : String(format: "%d:%02d:%02d", left / 3600, left / 60 % 60, left % 60),
                           color: ready ? .Green : .Gray, height: 48, fontSize: ready ? 21 : 18, enabled: ready,
                           icon: ready ? .COIN : nil, shine: ready) {
                    if repo.claimFreeGift(nowMillis()) { sound.play(.REWARD); toast("+100", .COIN) }
                }
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .featureCard(Color(argb: 0xFFFF7BBE), Color(argb: 0xFF7C4DFF), Color(argb: 0xFF4521C2))
    }

    private var megaBundle: some View {
        let affordable = repo.coins >= 1250
        return ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .center, spacing: 0) {
                    ZStack {
                        SunRays(color: .white, alpha: 0.3, rays: 12, degPerSec: 12).frame(width: 150, height: 150)
                        let icons: [Ico] = [.HAMMER, .MAGNET, .SLOTS, .SHUFFLE]
                        let spots: [(CGFloat, CGFloat)] = [(-20, -18), (20, -18), (-20, 20), (20, 20)]
                        ForEach(0..<4, id: \.self) { i in
                            GameIcon(icons[i])
                                .frame(width: 42, height: 42)
                                .rotationEffect(.degrees(i % 2 == 0 ? -12 : 12))
                                .offset(x: spots[i].0, y: spots[i].1)
                        }
                    }
                    .frame(width: 92, height: 92)
                    Spacer().frame(width: 10)
                    VStack(alignment: .leading, spacing: 0) {
                        OutlinedText("Mega Bundle", fontSize: 26, outline: Color(argb: 0xFF7A3A00), align: .Start, brush: Grad.Snow, gloss: true, maxLines: 1)
                        Text("3 of every booster · save 40%").textStyle(WhiteBody.copy(color: Color(argb: 0xFF5A2A00)))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Spacer().frame(height: 10)
                GameButton("1250", color: .Green, height: 52, fontSize: 23, enabled: affordable, icon: .COIN, sound: .COIN, shine: affordable) {
                    if repo.spend(1250) { Booster.entries.forEach { repo.addBooster($0, 3) }; toast("Mega Bundle!", .CHEST) }
                }
                .frame(maxWidth: .infinity)
            }
            .padding(14)
            .frame(maxWidth: .infinity)
            .featureCard(Color(argb: 0xFFFFE27A), Color(argb: 0xFFFF9F1C), Color(argb: 0xFFB45C00))
            Chip("BEST VALUE", .Red, fontSize: 14)
                .rotationEffect(.degrees(6))
                .offset(x: -14, y: -9)
        }
    }
}

private struct BoosterTile: View {
    let b: Booster
    let onBuy: (_ count: Int, _ price: Int) -> Void
    @Environment(GameRepository.self) var repo

    var body: some View {
        let coins = repo.coins
        let p3 = b.price * 5 / 2
        SectionCard(padding: 10) {
            ZStack(alignment: .topTrailing) {
                GameIcon(boosterIcon(b)).frame(width: 62, height: 62)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Chip("x\(repo.boosterCount(b))", .Purple, fontSize: 13).padding(6)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 86)
            .background(RadialGradient(colors: [boosterHalo(b), Color(argb: 0xFFF4EFFF)], center: .center, startRadius: 0, endRadius: 43))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            Spacer().frame(height: 6)
            Text(b.title).textStyle(CardTitleStyle.copy(fontSize: 19, textAlign: .Center)).lineLimit(1).frame(maxWidth: .infinity)
            Text(b.description + "\n").textStyle(CardBodyStyle.copy(fontSize: 12, lineHeight: 15, textAlign: .Center))
                .lineLimit(2, reservesSpace: true).frame(maxWidth: .infinity)
            Spacer().frame(height: 8)
            GameButton("\(b.price)", color: .Yellow, height: 44, fontSize: 19, enabled: coins >= b.price, icon: .COIN, sound: .COIN) { onBuy(1, b.price) }
                .frame(maxWidth: .infinity)
            Spacer().frame(height: 8)
            ZStack(alignment: .topTrailing) {
                GameButton("x3  \(p3)", color: .Pink, height: 42, fontSize: 17, enabled: coins >= p3, icon: .COIN, sound: .COIN) { onBuy(3, p3) }
                    .frame(maxWidth: .infinity)
                Chip("-17%", .Green, fontSize: 11).offset(x: 4, y: -10)
            }
        }
    }
}

// ============================================================ DAILY

private let wheelPrizes: [(String, Int)] = [
    ("50", 50), ("Hammer", -1), ("100", 100), ("Magnet", -2), ("25", 25), ("Slots", -3), ("250", 250), ("Shuffle", -4),
]
private let wheelColors: [(Color, Color)] = [
    (Color(argb: 0xFFFF5FA2), Color(argb: 0xFFD12D78)), (Color(argb: 0xFFFFD23F), Color(argb: 0xFFFF9F1C)),
    (Color(argb: 0xFF33D6F5), Color(argb: 0xFF1597C9)), (Color(argb: 0xFF8EF08A), Color(argb: 0xFF2FBF4F)),
    (Color(argb: 0xFFB394FF), Color(argb: 0xFF7B4DFF)), (Color(argb: 0xFFFFB86B), Color(argb: 0xFFFF7A1F)),
    (Color(argb: 0xFFFF8A8A), Color(argb: 0xFFE8273D)), (Color(argb: 0xFF7FE0F5), Color(argb: 0xFF2A8FD6)),
]
let spinEasing = ComposeEasing(0.15, 0.9, 0.3, 1)

/// Wheel rotation as a function of time (Compose `Animatable.animateTo(end, tween(4200, easing))`).
struct WheelSpin {
    var from: Double = 0
    var to: Double = 0
    var start: Date? = nil

    func value(at date: Date) -> Double {
        guard let start else { return to }
        let f = min(1, max(0, date.timeIntervalSince(start) / 4.2))
        return from + (to - from) * spinEasing(f)
    }
}

struct WheelPrize: Equatable {
    let label: String
    let v: Int
}

struct DailyTab: View {
    let nav: Nav
    @Environment(GameRepository.self) var repo
    @Environment(SoundManager.self) var sound
    @State var spin = WheelSpin()
    @State var spinning = false
    @State var prize: WheelPrize? = nil
    @State var shownPrize: WheelPrize? = nil
    @State var loginReward = 0
    @State var shownLogin = 0

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                TabHeader(title: "Daily")
                TabBody {
                    SectionCard {
                        CardHeader(title: "Lucky Spin", icon: .WHEEL)
                        Spacer().frame(height: 4)
                        LuckyWheel(spin: spin, spinning: spinning)
                            .aspectRatio(1, contentMode: .fit)
                            .padding(8)
                            .frame(maxWidth: .infinity)
                        let free = repo.canSpin
                        GameButton(free ? "SPIN FREE" : "SPIN  100", color: free ? .Green : .Yellow, enabled: !spinning && (free || repo.coins >= 100),
                                   icon: free ? nil : .COIN, shine: free && !spinning) { startSpin(free: free) }
                            .frame(maxWidth: .infinity)
                            .idleBounce(enabled: free && !spinning, amount: 0.035)
                    }
                    .frame(maxWidth: .infinity)
                    // daily challenge
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .center, spacing: 0) {
                            IconTile(.TROPHY, .Yellow, size: 64, iconScale: 0.7)
                            Spacer().frame(width: 12)
                            VStack(alignment: .leading, spacing: 0) {
                                OutlinedText("Daily Challenge", fontSize: 22, align: .Start, brush: Grad.Snow, maxLines: 1)
                                Text(repo.dailyChallengeDone ? "Completed! Come back tomorrow." : "A special hard puzzle every day.").textStyle(WhiteBody)
                                Spacer().frame(height: 4)
                                Chip("x2 COINS", .Yellow, fontSize: 13)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        Spacer().frame(height: 12)
                        GameButton(repo.dailyChallengeDone ? "Done" : "Play", color: .Green, height: 52, enabled: !repo.dailyChallengeDone,
                                   icon: repo.dailyChallengeDone ? .CHECK : .PLAY, shine: !repo.dailyChallengeDone) {
                            nav.go(.Game(GameRoute(level: repo.dailyLevel, daily: true)))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity)
                    .featureCard(Color(argb: 0xFF9B6BFF), Color(argb: 0xFF4F2BD6), Color(argb: 0xFF2E1689))
                    // login calendar
                    SectionCard {
                        CardHeader(title: "Daily Rewards", icon: .CALENDAR)
                        Spacer().frame(height: 10)
                        let idx = repo.loginIndex
                        let claimable = repo.canClaimLogin
                        ForEach(0..<2, id: \.self) { row in
                            let range = row == 0 ? Array(0..<4) : Array(4..<7)
                            WeightRow(weights: range.map { $0 == 6 ? 2.1 : 1 }, spacing: 8) {
                                ForEach(range, id: \.self) { d in
                                    DayTile(d: d, claimed: d < idx, today: claimable && d == idx)
                                }
                            }
                            Spacer().frame(height: 8)
                        }
                        GameButton(claimable ? "Claim Day \(idx + 1)" : "Come back tomorrow", color: .Green, height: 52,
                                   fontSize: claimable ? 23 : 18, enabled: claimable, shine: claimable) {
                            let r = repo.claimLogin()
                            shownLogin = r
                            loginReward = r
                            sound.play(.REWARD)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            PopupHost(visible: prize != nil, onDismiss: { prize = nil }) {
                if let p = shownPrize {
                    GamePanel("You won!", ribbon: .Yellow, rays: true) {
                        RewardTile(icon: p.v > 0 ? .COIN : boosterIcon(Booster.entries[-p.v - 1]), text: p.v > 0 ? "+\(p.label)" : "+1 \(p.label)")
                        Spacer().frame(height: 14)
                        GameButton("Collect", color: .Green, shine: true) { prize = nil }
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            PopupHost(visible: loginReward > 0, onDismiss: { loginReward = 0 }) {
                if shownLogin > 0 {
                    GamePanel("Daily Reward", ribbon: .Green, rays: true) {
                        RewardTile(icon: .COIN, text: "+\(shownLogin)")
                        Spacer().frame(height: 14)
                        GameButton("Great!", color: .Green, shine: true) { loginReward = 0 }
                            .frame(maxWidth: .infinity)
                    }
                }
            }
        }
    }

    private func startSpin(free: Bool) {
        if !free && !repo.spend(100) { return }
        if free { repo.markSpin() } else { repo.addStat(.SPINS, 1) }
        spinning = true
        let target = Int.random(in: 0..<wheelPrizes.count)
        let sweep = 360.0 / Double(wheelPrizes.count)
        let now = Date()
        let current = spin.value(at: now)
        let base = current - current.truncatingRemainder(dividingBy: 360)
        let end = base + 360 * 5 + (360 - Double(target) * sweep) + (Double(Float.random(in: 0..<1)) - 0.5) * sweep * 0.6
        spin = WheelSpin(from: current, to: end, start: now)
        let s = spin
        Task { @MainActor in
            var lastTick = s.value(at: Date())
            while spinning {
                let r = s.value(at: Date())
                if r - lastTick > sweep { lastTick = r; sound.play(.SPIN_TICK) }
                try? await Task.sleep(nanoseconds: 16_000_000)
            }
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 4_200_000_000)
            spinning = false
            spin = WheelSpin(from: end, to: end, start: nil)
            let p = wheelPrizes[target]
            grantPrize(repo, p.1)
            sound.play(.REWARD)
            shownPrize = WheelPrize(label: p.0, v: p.1)
            prize = shownPrize
        }
    }
}

private struct CardHeader: View {
    let title: String
    let icon: Ico

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            GameIcon(icon).frame(width: 30, height: 30)
            Spacer().frame(width: 8)
            Text(title).textStyle(CardTitleStyle.copy(fontSize: 25))
        }
        .frame(maxWidth: .infinity)
    }
}

/// Lucky wheel: the face (segments, icons, amounts) is baked into an image once and rotated each frame;
/// the gold rim has chasing bulbs and the gem pointer flicks as segments pass under it.
private struct LuckyWheel: View {
    let spin: WheelSpin
    let spinning: Bool
    @Environment(\.displayScale) var displayScale
    @State var face: Image? = nil
    @State var faceInner: CGFloat = 0

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let r = side / 2
            let inner = r * 0.86
            // idle: the bulbs only step 3×/s, so redraw at that rate; spinning: every frame
            FrameClock(minimumInterval: spinning ? nil : 1.0 / 30) { t in
                Canvas { ctx, size in
                    drawWheel(ctx, CGSize(width: size.width, height: size.height - 10), t: t, rotation: spin.value(at: Date()), r: r, inner: inner)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height + 10)
            .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            .onAppear { bake(inner) }
            .onChange(of: inner) { _, v in bake(v) }
        }
    }

    @MainActor
    private func bake(_ inner: CGFloat) {
        guard inner > 1, abs(inner - faceInner) > 0.5 else { return }
        faceInner = inner
        let renderer = ImageRenderer(content: WheelFace(inner: inner).frame(width: inner * 2, height: inner * 2))
        renderer.scale = displayScale
        if let cg = renderer.cgImage { face = Image(decorative: cg, scale: displayScale) }
    }

    private func drawWheel(_ ctx: GraphicsContext, _ size: CGSize, t: Double, rotation: Double, r: CGFloat, inner: CGFloat) {
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        func circle(_ cc: CGPoint, _ rr: CGFloat) -> Path { Path(ellipseIn: CGRect(x: cc.x - rr, y: cc.y - rr, width: rr * 2, height: rr * 2)) }
        let sweep = 360.0 / Double(wheelPrizes.count)
        ctx.fill(circle(CGPoint(x: c.x, y: c.y + 8), r), with: .color(Color(argb: 0x47140A3C)))
        ctx.fill(circle(c, r), with: .linearGradient(Gradient(colors: [Color(argb: 0xFFFFF0A0), Color(argb: 0xFFFFB21A), Color(argb: 0xFFC47A00)]),
                                                    startPoint: CGPoint(x: 0, y: c.y - r), endPoint: CGPoint(x: 0, y: c.y + r)))
        ctx.stroke(circle(c, r), with: .color(Color(argb: 0xFF8A4A00)), lineWidth: 2.5)
        // chasing bulbs
        let phase = Int(spinning ? t * 14 : t * 3)
        for i in 0..<16 {
            let a = CGFloat(i) * 2 * .pi / 16
            let p = CGPoint(x: c.x + cos(a) * r * 0.93, y: c.y + sin(a) * r * 0.93)
            let lit = (i + phase) % 2 == 0
            ctx.fill(circle(p, r * 0.042), with: .color(Color(argb: 0xFF8A4A00)))
            ctx.fill(circle(p, r * 0.034), with: .color(lit ? Color(argb: 0xFFFFFDE8) : Color(argb: 0xFFFFC94D)))
            if lit { ctx.fill(circle(p, r * 0.06), with: .color(Color(argb: 0x66FFFFFF))) }
        }
        if let face {
            var fc = ctx
            fc.translateBy(x: c.x, y: c.y)
            fc.rotate(by: .degrees(rotation))
            fc.draw(face, in: CGRect(x: -inner, y: -inner, width: inner * 2, height: inner * 2))
        }
        ctx.stroke(circle(c, inner), with: .color(Color(argb: 0xFF8A4A00)), lineWidth: 3)
        // hub
        ctx.fill(circle(CGPoint(x: c.x, y: c.y + 3), r * 0.19), with: .color(Color(argb: 0xFFB86A00)))
        ctx.fill(circle(c, r * 0.18), with: .linearGradient(Gradient(colors: [Color(argb: 0xFFFFF6C8), Color(argb: 0xFFFFB21A)]),
                                                           startPoint: CGPoint(x: 0, y: c.y - r * 0.18), endPoint: CGPoint(x: 0, y: c.y + r * 0.18)))
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.1, y: c.y - r * 0.14, width: r * 0.2, height: r * 0.09)), with: .color(.white.opacity(0.6)))
        ctx.stroke(circle(c, r * 0.18), with: .color(Color(argb: 0xFF8A4A00)), lineWidth: 2)
        // gem pointer: flicks back when a segment edge passes
        let f = ((rotation.truncatingRemainder(dividingBy: sweep)) + sweep).truncatingRemainder(dividingBy: sweep) / sweep
        let kick = spinning ? min(max(1 - f * 3, 0), 1) * 22 : 0
        var pointer = Path()
        pointer.move(to: CGPoint(x: c.x, y: c.y - r * 0.74))
        pointer.addLine(to: CGPoint(x: c.x - r * 0.11, y: c.y - r * 1.0))
        pointer.addQuadCurve(to: CGPoint(x: c.x + r * 0.11, y: c.y - r * 1.0), control: CGPoint(x: c.x, y: c.y - r * 1.1))
        pointer.closeSubpath()
        var pc = ctx
        pc.translateBy(x: c.x, y: c.y - r)
        pc.rotate(by: .degrees(-kick))
        pc.translateBy(x: -c.x, y: -(c.y - r))
        pc.fill(pointer, with: .color(Color(argb: 0x55140A3C)))
        pc.fill(pointer, with: .linearGradient(Gradient(colors: [Color(argb: 0xFFFF8A9A), Color(argb: 0xFFE8273D)]),
                                               startPoint: CGPoint(x: 0, y: c.y - r * 1.08), endPoint: CGPoint(x: 0, y: c.y - r * 0.74)))
        pc.stroke(pointer, with: .color(Color(argb: 0xFF7D1222)), style: StrokeStyle(lineWidth: 2.2, lineJoin: .round))
        pc.fill(circle(CGPoint(x: c.x - r * 0.03, y: c.y - r * 0.97), r * 0.025), with: .color(.white.opacity(0.7)))
    }
}

/// The baked wheel face: segments, dividers, prize icons and amounts, inner vignette.
private struct WheelFace: View {
    let inner: CGFloat

    var body: some View {
        let sweep = 360.0 / CGFloat(wheelPrizes.count)
        ZStack {
            Canvas { ctx, size in
                let fc = CGPoint(x: inner, y: inner)
                let rect = CGRect(x: 0, y: 0, width: inner * 2, height: inner * 2)
                for i in wheelPrizes.indices {
                    let (a, b) = wheelColors[i]
                    let start = -90 + CGFloat(i) * sweep - sweep / 2
                    ctx.fill(arcPath(rect, start, sweep, useCenter: true),
                             with: .radialGradient(Gradient(colors: [a, b]), center: fc, startRadius: 0, endRadius: inner))
                    ctx.fill(arcPath(rect, start, sweep / 2, useCenter: true), with: .color(.white.opacity(0.16)))
                }
                for i in wheelPrizes.indices {
                    let ang = (-90 + CGFloat(i) * sweep - sweep / 2) * .pi / 180
                    var p = Path()
                    p.move(to: fc)
                    p.addLine(to: CGPoint(x: fc.x + cos(ang) * inner, y: fc.y + sin(ang) * inner))
                    ctx.stroke(p, with: .color(.white.opacity(0.85)), lineWidth: 3)
                }
            }
            ForEach(wheelPrizes.indices, id: \.self) { i in
                let v = wheelPrizes[i].1
                let s = inner * (v > 0 ? 0.24 : 0.3)
                let iy = inner * (v > 0 ? 0.74 : 0.66)
                ZStack {
                    GameIcon(v > 0 ? .COIN : boosterIcon(Booster.entries[-v - 1]))
                        .frame(width: s, height: s)
                        .position(x: inner, y: inner - iy)
                    if v > 0 {
                        OutlinedText(wheelPrizes[i].0, fontSize: inner * 0.17, outlineWidth: inner * 0.17 * 0.14, shadow: false, maxLines: 1)
                            .fixedSize()
                            .position(x: inner, y: inner - inner * 0.44)
                    }
                }
                .frame(width: inner * 2, height: inner * 2)
                .rotationEffect(.degrees(Double(CGFloat(i) * sweep)))
            }
            Canvas { ctx, size in
                let fc = CGPoint(x: inner, y: inner)
                ctx.fill(Path(ellipseIn: CGRect(x: 0, y: 0, width: inner * 2, height: inner * 2)),
                         with: .radialGradient(Gradient(colors: [.clear, Color(argb: 0x40000000)]), center: fc, startRadius: 0, endRadius: inner))
            }
        }
        .frame(width: inner * 2, height: inner * 2)
    }
}

private struct DayTile: View {
    let d: Int
    let claimed: Bool
    let today: Bool

    var body: some View {
        ZStack {
            FrameClock(paused: !today) { t in
                Canvas { ctx, size in
                    let r: CGFloat = 18
                    let fill: [Color] = today ? [Color(argb: 0xFFFFF2A8), Color(argb: 0xFFFFC21A)]
                        : (claimed ? [Color(argb: 0xFFE2D8FF), Color(argb: 0xFFC9B8FF)] : [.white, Color(argb: 0xFFEDE6FF)])
                    let rim = today ? Color(argb: 0xFFC47A00) : Color(argb: 0xFF9F87F0)
                    var c = ctx
                    c.translateBy(x: 4, y: 4)
                    let w = size.width - 8
                    let h = size.height - 8
                    if today {
                        let k = 0.5 + 0.5 * sin(loopPhase(t, 1200) * 2 * .pi)
                        c.fill(Path(roundedRect: CGRect(x: -4, y: -4, width: w + 8, height: h + 8), cornerRadius: r + 4),
                               with: .color(Color(argb: 0xFFFFE680).opacity(Double(0.35 + 0.4 * k))))
                    }
                    c.fill(Path(roundedRect: CGRect(x: 0, y: 3, width: w, height: h), cornerRadius: r), with: .color(rim))
                    c.fill(Path(roundedRect: CGRect(x: 0, y: 0, width: w, height: h - 1), cornerRadius: r),
                           with: .linearGradient(Gradient(colors: fill), startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
                    c.fill(Path(roundedRect: CGRect(x: w * 0.1, y: 4, width: w * 0.8, height: 8), cornerRadius: 4), with: .color(.white.opacity(0.5)))
                    c.stroke(Path(roundedRect: CGRect(x: 0, y: 0, width: w, height: h), cornerRadius: r), with: .color(rim), lineWidth: 2)
                }
            }
            .padding(-4)
            VStack(spacing: 0) {
                Text("Day \(d + 1)").textStyle(TextStyle(fontFamily: LilitaOne, fontSize: 14, color: GameColors.Ink))
                GameIcon(d == 6 ? .CHEST : .COIN).frame(width: d == 6 ? 42 : 32, height: d == 6 ? 42 : 32)
                Text(String(GameRepository.LOGIN_REWARDS[d])).textStyle(TextStyle(fontFamily: LilitaOne, fontSize: 15, color: GameColors.Ink))
            }
            .opacity(claimed ? 0.55 : 1)
            if claimed {
                ZStack {
                    Circle().fill(LinearGradient(colors: [GameColors.GreenLight, GameColors.Green], startPoint: .top, endPoint: .bottom))
                    Circle().strokeBorder(.white, lineWidth: 2.5)
                    GameIcon(.CHECK).frame(width: 24, height: 24)
                }
                .frame(width: 38, height: 38)
                .rotationEffect(.degrees(-12))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 94)
    }
}

private func grantPrize(_ repo: GameRepository, _ v: Int) {
    if v > 0 { repo.addCoins(v) } else { repo.addBooster(Booster.entries[-v - 1], 1) }
}

// ============================================================ COLLECTION

private enum Rarity {
    case COMMON, RARE, EPIC, LEGENDARY

    var label: String {
        switch self { case .COMMON: return "COMMON"; case .RARE: return "RARE"; case .EPIC: return "EPIC"; case .LEGENDARY: return "LEGENDARY" }
    }
    var color: BtnColor {
        switch self { case .COMMON: return .Gray; case .RARE: return .Blue; case .EPIC: return .Purple; case .LEGENDARY: return .Orange }
    }
    var glow: Color {
        switch self {
        case .COMMON: return Color(argb: 0xFFE6E3EF)
        case .RARE: return Color(argb: 0xFFBDEFFF)
        case .EPIC: return Color(argb: 0xFFDCCBFF)
        case .LEGENDARY: return Color(argb: 0xFFFFE0A8)
        }
    }
}

private func rarityOf(_ price: Int) -> Rarity {
    if price == 0 { return .COMMON }
    if price <= 900 { return .RARE }
    if price <= 1500 { return .EPIC }
    return .LEGENDARY
}

private func themeDisplayName(_ name: String) -> String { name == "Lava" ? "Sunset" : name }

struct CollectionTab: View {
    @Environment(GameRepository.self) var repo
    @Environment(SoundManager.self) var sound
    @State var page = 0
    @State var lockedSkin = -1
    @State var shownSkin = -1
    @State var lockedTheme = -1
    @State var shownTheme = -1

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                TabHeader(title: "Collection")
                SegmentedSwitch(["Marbles", "Themes"], page) { page = $0 }
                    .padding(.horizontal, 14)
                    .frame(maxWidth: .infinity)
                Spacer().frame(height: 10)
                AnimatedSwitcher(target: page, spec: { from, to in
                    let dir: CGFloat = to > from ? 1 : -1
                    return ContentTransformSpec(
                        enter: ScreenMotion(fade: Tween(duration: 200), slide: Tween(duration: 300, easing: .enter), slideFraction: dir / 3),
                        exit: ScreenMotion(fade: Tween(duration: 120), slide: Tween(duration: 300, easing: .enter), slideFraction: -dir / 3))
                }) { pg in
                    TabBody {
                        if pg == 0 { skinsPage } else { themesPage }
                    }
                }
            }
            if shownSkin >= 0 {
                let i = shownSkin
                WatchAdDialog(
                    visible: lockedSkin >= 0,
                    title: Catalog.skins[i].name, message: "Unlock the \(Catalog.skins[i].name) marbles!", placement: .UNLOCK_SKIN,
                    onUnlocked: { repo.grantSkin(i); repo.selectSkin(i) },
                    onClose: { lockedSkin = -1 },
                    coinPrice: Catalog.skins[i].price, coins: repo.coins,
                    onBuy: { if repo.buySkin(i) { repo.selectSkin(i); sound.play(.REWARD) }; lockedSkin = -1 }
                ) { SkinPreview(skin: i) }
            }
            if shownTheme >= 0 {
                let i = shownTheme
                let name = themeDisplayName(Catalog.themes[i].name)
                WatchAdDialog(
                    visible: lockedTheme >= 0,
                    title: name, message: "Unlock the \(name) playground theme!", placement: .UNLOCK_THEME,
                    onUnlocked: { repo.grantTheme(i); repo.selectTheme(i) },
                    onClose: { lockedTheme = -1 },
                    coinPrice: Catalog.themes[i].price, coins: repo.coins,
                    onBuy: { if repo.buyTheme(i) { repo.selectTheme(i); sound.play(.REWARD) }; lockedTheme = -1 }
                ) {
                    ThemePreview(t: Themes.get(i))
                        .frame(width: 150, height: 110)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
            }
        }
    }

    @ViewBuilder
    private var skinsPage: some View {
        let skins = Catalog.skins
        ForEach(0..<((skins.count + 1) / 2), id: \.self) { row in
            WeightRow(weights: [1, 1], spacing: 12) {
                ForEach((row * 2)..<min(row * 2 + 2, skins.count), id: \.self) { i in
                    let owned = repo.ownedSkins.contains(i)
                    let selected = repo.skin == i
                    SkinTile(i: i, name: skins[i].name, price: skins[i].price, owned: owned, selected: selected) {
                        if owned { repo.selectSkin(i); sound.play(.BUTTON) } else { shownSkin = i; lockedSkin = i }
                    }
                }
                if row * 2 + 1 >= skins.count { Color.clear.frame(height: 1) }
            }
        }
    }

    @ViewBuilder
    private var themesPage: some View {
        ThemeCard(name: "Auto Rotate", subtitle: "A new world every 25 levels", owned: true, selected: repo.theme == -1, price: 0,
                  onAction: { repo.selectTheme(-1) }) {
            HStack(spacing: 6) {
                ForEach(Themes.all.indices, id: \.self) { k in
                    let t = Themes.all[k]
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(LinearGradient(colors: [themeColor(t.bgTop), themeColor(t.bgBottom)], startPoint: .top, endPoint: .bottom))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(10)
        }
        ForEach(Catalog.themes.indices, id: \.self) { i in
            let info = Catalog.themes[i]
            let owned = repo.ownedThemes.contains(i)
            ThemeCard(name: themeDisplayName(info.name), subtitle: "Playground theme", owned: owned, selected: repo.theme == i, price: info.price,
                      onAction: { if owned { repo.selectTheme(i) } else { shownTheme = i; lockedTheme = i } }) {
                ThemePreview(t: Themes.get(i))
            }
        }
    }
}

private struct SkinTile: View {
    let i: Int
    let name: String
    let price: Int
    let owned: Bool
    let selected: Bool
    let onAction: () -> Void

    var body: some View {
        let rarity = rarityOf(price)
        SectionCard(padding: 10) {
            ZStack {
                Canvas { ctx, size in
                    let r: CGFloat = 18
                    let rect = CGRect(origin: .zero, size: size)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: r),
                             with: .radialGradient(Gradient(colors: [.white, rarity.glow, rarity.glow.opacity(0.6)]),
                                                   center: CGPoint(x: size.width / 2, y: size.height * 0.45), startRadius: 0, endRadius: max(size.width, size.height) * 0.7))
                    ctx.stroke(Path(roundedRect: rect.insetBy(dx: selected ? 1.75 : 0.75, dy: selected ? 1.75 : 0.75), cornerRadius: r),
                               with: .color(selected ? GameColors.Green : Color(argb: 0x332A1463)), lineWidth: selected ? 3.5 : 1.5)
                }
                SkinPreview(skin: i)
                    .padding(6)
                    .floaty(amplitude: 3, periodMs: 2600, phase: Float(i) * 0.17)
                    .opacity(owned ? 1 : 0.85)
                Chip(rarity.label, rarity.color, fontSize: 10)
                    .padding(6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                if selected {
                    CheckBadge(size: 28, icon: 18)
                        .padding(6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
                if !owned {
                    GameIcon(.LOCK).frame(width: 28, height: 28)
                        .padding(6)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 124)
            Spacer().frame(height: 8)
            Text(name).textStyle(CardTitleStyle.copy(fontSize: 19, textAlign: .Center)).lineLimit(1).frame(maxWidth: .infinity)
            Spacer().frame(height: 6)
            Group {
                if selected {
                    GameButton("Selected", color: .Gray, height: 44, fontSize: 18, enabled: false) {}
                } else if owned {
                    GameButton("Use", color: .Green, height: 44, fontSize: 18) { onAction() }
                } else {
                    GameButton("Unlock", color: .Yellow, height: 44, fontSize: 18, icon: .LOCK) { onAction() }
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

/// Green round check badge with a white border.
private struct CheckBadge: View {
    let size: CGFloat
    let icon: CGFloat
    var border: CGFloat = 2

    var body: some View {
        ZStack {
            Circle().fill(LinearGradient(colors: [GameColors.GreenLight, GameColors.Green], startPoint: .top, endPoint: .bottom))
            Circle().strokeBorder(.white, lineWidth: border)
            GameIcon(.CHECK).frame(width: icon, height: icon)
        }
        .frame(width: size, height: size)
    }
}

private struct ThemeCard<Preview: View>: View {
    let name: String
    let subtitle: String
    let owned: Bool
    let selected: Bool
    let price: Int
    let onAction: () -> Void
    @ViewBuilder let preview: () -> Preview

    var body: some View {
        SectionCard(padding: 10) {
            ZStack {
                preview()
                if selected {
                    CheckBadge(size: 30, icon: 20)
                        .padding(8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                }
                if !owned {
                    Chip(rarityOf(price).label, rarityOf(price).color, fontSize: 11)
                        .padding(8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                if selected { RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(GameColors.Green, lineWidth: 3.5) }
            }
            Spacer().frame(height: 8)
            HStack(alignment: .center, spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(name).textStyle(CardTitleStyle.copy(fontSize: 20)).lineLimit(1)
                    Text(subtitle).textStyle(CardBodyStyle.copy(fontSize: 12)).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer().frame(width: 8)
                Group {
                    if selected {
                        GameButton("Selected", color: .Gray, height: 44, fontSize: 17, enabled: false) {}
                    } else if owned {
                        GameButton("Use", color: .Green, height: 44, fontSize: 18) { onAction() }
                    } else {
                        GameButton("Unlock", color: .Yellow, height: 44, fontSize: 18, icon: .LOCK) { onAction() }
                    }
                }
                .frame(width: 126)
            }
        }
    }
}

private struct SkinPreview: View {
    let skin: Int

    var body: some View {
        Canvas { ctx, size in
            let r = min(size.width, size.height) * 0.21
            ball(ctx, CGPoint(x: size.width * 0.32, y: size.height * 0.64), r, 0, skin)
            ball(ctx, CGPoint(x: size.width * 0.68, y: size.height * 0.64), r, 2, skin)
            ball(ctx, CGPoint(x: size.width * 0.5, y: size.height * 0.31), r, 1, skin)
        }
    }
}

/// GameTheme colours are ARGB ints.
func themeColor(_ v: Int) -> Color { Color(argb: UInt32(truncatingIfNeeded: v)) }

private struct ThemePreview: View {
    let t: GameTheme

    var body: some View {
        Canvas { ctx, size in
            let w = size.width
            let h = size.height
            ctx.fill(Path(CGRect(origin: .zero, size: size)),
                     with: .linearGradient(Gradient(colors: [themeColor(t.bgTop), themeColor(t.bgBottom)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
            for k in 0..<6 {
                let rr = h * (0.05 + CGFloat(k % 3) * 0.03)
                let c = CGPoint(x: w * (0.1 + CGFloat(k) * 0.17), y: h * (0.15 + CGFloat(k % 2) * 0.6))
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2)), with: .color(.white.opacity(0.12)))
            }
            ctx.fill(Path(roundedRect: CGRect(x: w * 0.06, y: h * 0.08, width: w * 0.5, height: h * 0.84), cornerRadius: 16 * pxPt), with: .color(themeColor(t.wallDark)))
            ctx.fill(Path(roundedRect: CGRect(x: w * 0.07, y: h * 0.1, width: w * 0.48, height: h * 0.8), cornerRadius: 14 * pxPt), with: .color(themeColor(t.wall)))
            ctx.fill(Path(roundedRect: CGRect(x: w * 0.1, y: h * 0.16, width: w * 0.42, height: h * 0.6), cornerRadius: 12 * pxPt), with: .color(themeColor(t.interior)))
            let bs = h * 0.24
            for k in 0..<3 { Painter.block(ctx, w * 0.115 + CGFloat(k) * bs * 1.0, h * 0.46, bs, k + 1, 0) }
            for k in 0..<3 { Painter.block(ctx, w * 0.115 + CGFloat(k) * bs * 1.0, h * 0.46 - bs, bs, k + 4, 0, bumps: false) }
            ctx.fill(Path(roundedRect: CGRect(x: w * 0.6, y: h * 0.2, width: w * 0.36, height: h * 0.6), cornerRadius: 20 * pxPt), with: .color(themeColor(t.dishDark)))
            ctx.fill(Path(roundedRect: CGRect(x: w * 0.61, y: h * 0.22, width: w * 0.34, height: h * 0.56), cornerRadius: 18 * pxPt), with: .color(themeColor(t.dish)))
            ctx.fill(Path(roundedRect: CGRect(x: w * 0.635, y: h * 0.3, width: w * 0.29, height: h * 0.15), cornerRadius: 40 * pxPt), with: .color(Color(argb: 0xFF3B2F86)))
            for k in 0..<4 { ball(ctx, CGPoint(x: w * 0.67 + CGFloat(k) * w * 0.075, y: h * 0.375), h * 0.05, k + 2) }
            for k in 0..<3 { Painter.cup(ctx, w * 0.635 + CGFloat(k) * w * 0.1, h * 0.55, w * 0.085, h * 0.1, k * 2, false) }
        }
    }
}

// ============================================================ PROFILE & ACHIEVEMENTS

struct Achievement {
    let id: Int
    let title: String
    let stat: Stat
    let target: Int64
    let reward: Int
}

let achievements: [Achievement] = {
    var id = 0
    func a(_ title: String, _ stat: Stat, _ target: Int64, _ reward: Int) -> Achievement {
        defer { id += 1 }
        return Achievement(id: id, title: title, stat: stat, target: target, reward: reward)
    }
    return [
        a("First Steps", .LEVELS_WON, 5, 50), a("Getting Rolling", .LEVELS_WON, 25, 100), a("Marble Pro", .LEVELS_WON, 100, 250),
        a("Factory Boss", .LEVELS_WON, 250, 400), a("Unstoppable", .LEVELS_WON, 500, 600), a("Legend", .LEVELS_WON, 1000, 1000),
        a("Grand Master", .LEVELS_WON, 2500, 2000), a("The Whole Factory", .LEVELS_WON, 5000, 5000),
        a("Shining Star", .THREE_STARS, 10, 80), a("Star Collector", .THREE_STARS, 50, 200), a("Galaxy of Stars", .THREE_STARS, 200, 500), a("Perfectionist", .THREE_STARS, 1000, 1500),
        a("Marble Mover", .MARBLES, 500, 60), a("Marble Hauler", .MARBLES, 5000, 200), a("Marble Mountain", .MARBLES, 50000, 800), a("Marble Ocean", .MARBLES, 250000, 2000),
        a("Cup Filler", .CUPS, 100, 60), a("Cup Champion", .CUPS, 1000, 250), a("Cup Factory", .CUPS, 10000, 1000),
        a("Combo Starter", .MAX_COMBO, 5, 100), a("Combo King", .MAX_COMBO, 10, 300), a("Combo Legend", .MAX_COMBO, 20, 800),
        a("Power Up", .BOOSTERS, 5, 60), a("Booster Fan", .BOOSTERS, 50, 300),
        a("Lucky Week", .SPINS, 7, 120), a("Wheel Whiz", .SPINS, 30, 400),
        a("Daily Player", .DAILY_WINS, 5, 150), a("Daily Devotee", .DAILY_WINS, 30, 600),
        a("Treasure Hunter", .CHESTS, 5, 100), a("Treasure Hoarder", .CHESTS, 50, 700),
        a("Boss Breaker", .BOSS_WINS, 5, 300), a("Boss Crusher", .BOSS_WINS, 50, 1500),
        a("Big Saver", .COINS_EARNED, 5000, 250), a("Coin Tycoon", .COINS_EARNED, 50000, 1000),
    ]
}()

struct ProfileTab: View {
    @Environment(GameRepository.self) var repo
    @Environment(SoundManager.self) var sound

    var body: some View {
        VStack(spacing: 0) {
            TabHeader(title: "Profile")
            TabBody {
                playerCard
                let stats: [(Ico, String, Int64)] = [
                    (.FLAG, "Levels", repo.stat(.LEVELS_WON)), (.STAR, "3-Star", repo.stat(.THREE_STARS)),
                    (.MARBLES, "Marbles", repo.stat(.MARBLES)), (.CUP, "Cups", repo.stat(.CUPS)),
                    (.FLAME, "Best Combo", repo.stat(.MAX_COMBO)), (.CROWN, "Bosses", repo.stat(.BOSS_WINS)),
                ]
                ForEach(0..<2, id: \.self) { row in
                    WeightRow(weights: [1, 1, 1], spacing: 10) {
                        ForEach((row * 3)..<(row * 3 + 3), id: \.self) { k in
                            StatTile(icon: stats[k].0, label: stats[k].1, v: stats[k].2)
                        }
                    }
                }
                let claimed = repo.claimedAchievements
                SectionTitle("Achievements", icon: .TROPHY) {
                    Chip("\(claimed.count) / \(achievements.count)", .Yellow, fontSize: 14)
                }
                // stable sort: claimable first, then in progress, then claimed
                let sorted = achievements.enumerated().map { (i, a) -> (Int, Int, Achievement) in
                    let done = repo.stat(a.stat) >= a.target
                    let cl = claimed.contains(a.id)
                    return (done && !cl ? 0 : (!done ? 1 : 2), i, a)
                }.sorted { ($0.0, $0.1) < ($1.0, $1.1) }.map { $0.2 }
                ForEach(sorted, id: \.id) { a in AchievementRow(a: a) }
            }
        }
    }

    private var playerCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: 0) {
                ZStack {
                    Canvas { ctx, canvasSize in
                        let size = CGSize(width: canvasSize.width, height: canvasSize.height - 4)
                        let r = min(size.width, size.height) / 2
                        let c = CGPoint(x: size.width / 2, y: size.height / 2)
                        func circle(_ cc: CGPoint, _ rr: CGFloat) -> Path { Path(ellipseIn: CGRect(x: cc.x - rr, y: cc.y - rr, width: rr * 2, height: rr * 2)) }
                        ctx.fill(circle(CGPoint(x: c.x, y: c.y + 4), r), with: .color(Color(argb: 0x40140A3C)))
                        ctx.fill(circle(c, r), with: .linearGradient(Gradient(colors: [Color(argb: 0xFFFFF0A0), Color(argb: 0xFFFFA81A)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                        ctx.fill(circle(c, r - 6), with: .linearGradient(Gradient(colors: [Color(argb: 0xFFB9A3FF), Color(argb: 0xFF4521C2)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                        ctx.stroke(circle(c, r), with: .color(Color(argb: 0xFF8A4A00)), lineWidth: 2)
                    }
                    .padding(.bottom, -4)
                    let avatar = repo.avatar
                    Canvas { ctx, size in
                        ball(ctx, CGPoint(x: size.width / 2, y: size.height / 2), size.width * 0.44, avatar, 6)
                    }
                    .frame(width: 64, height: 64)
                    Chip("Lv \(repo.level)", .Pink, fontSize: 13)
                        .offset(y: 8)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                }
                .frame(width: 92, height: 92)
                .contentShape(Rectangle())
                .onTapGesture { repo.setAvatar((repo.avatar + 1) % 9); sound.play(.BUTTON) }
                Spacer().frame(width: 14)
                VStack(alignment: .leading, spacing: 0) {
                    OutlinedText(repo.playerName, fontSize: 24, align: .Start, brush: Grad.Snow, maxLines: 1)
                    Spacer().frame(height: 4)
                    HStack(alignment: .center, spacing: 0) {
                        GameIcon(.STAR).frame(width: 24, height: 24)
                        Spacer().frame(width: 4)
                        OutlinedText("\(repo.totalStars) stars", fontSize: 17, shadow: false)
                    }
                    Text("Tap the avatar to change it").textStyle(WhiteBody.copy(fontSize: 12, color: .white.opacity(0.85)))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .featureCard(Color(argb: 0xFFFF8AC4), Color(argb: 0xFF6A3FF0), Color(argb: 0xFF3A1CA8))
    }
}

private struct StatTile: View {
    let icon: Ico
    let label: String
    let v: Int64

    var body: some View {
        SectionCard(padding: 8) {
            VStack(spacing: 0) {
                GameIcon(icon).frame(width: 34, height: 34)
                Text(compact(v)).textStyle(CardTitleStyle.copy(fontSize: 22, color: GameColors.Purple700))
                Text(label).textStyle(CardBodyStyle.copy(fontSize: 12)).lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

private struct AchievementRow: View {
    let a: Achievement
    @Environment(GameRepository.self) var repo

    var body: some View {
        let progress = repo.stat(a.stat)
        let done = progress >= a.target
        let claimed = repo.claimedAchievements.contains(a.id)
        let medal: (Ico, BtnColor) = a.reward >= 1000 ? (.CROWN, .Orange) : (a.reward >= 300 ? (.TROPHY, .Pink) : (.STAR, .Purple))
        SectionCard(padding: 12) {
            HStack(alignment: .center, spacing: 0) {
                IconTile(medal.0, claimed || done ? medal.1 : .Gray, size: 50, iconScale: 0.66)
                Spacer().frame(width: 10)
                VStack(alignment: .leading, spacing: 0) {
                    Text(a.title).textStyle(CardTitleStyle.copy(fontSize: 18)).lineLimit(1)
                    Text("\(statLabel(a.stat)) \(compact(a.target))").textStyle(CardBodyStyle.copy(fontSize: 12)).lineLimit(1)
                    Spacer().frame(height: 5)
                    ProgressTube(min(max(Float(progress) / Float(a.target), 0), 1), height: 16, fill: done ? .Green : .Blue,
                                 label: "\(compact(min(progress, a.target))) / \(compact(a.target))")
                        .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Spacer().frame(width: 10)
                if claimed {
                    CheckBadge(size: 44, icon: 26, border: 2.5)
                } else {
                    GameButton(String(a.reward), color: done ? .Green : .Gray, height: 44, fontSize: 17, enabled: done, icon: .COIN, sound: .REWARD, shine: done) {
                        repo.claimAchievement(a.id, a.reward)
                    }
                    .frame(width: 98)
                }
            }
        }
        .opacity(claimed ? 0.8 : 1)
    }
}

private func statLabel(_ s: Stat) -> String {
    switch s {
    case .LEVELS_WON: return "Win levels:"
    case .THREE_STARS: return "3-star levels:"
    case .MARBLES: return "Sort marbles:"
    case .CUPS: return "Fill cups:"
    case .BLOCKS: return "Pop blocks:"
    case .MAX_COMBO: return "Reach combo:"
    case .BOOSTERS: return "Use boosters:"
    case .SPINS: return "Lucky spins:"
    case .DAILY_WINS: return "Daily challenges:"
    case .COINS_EARNED: return "Earn coins:"
    case .CHESTS: return "Open chests:"
    case .BOSS_WINS: return "Beat boss levels:"
    }
}

func compact(_ v: Int64) -> String {
    if v >= 1_000_000 { return String(format: "%.1fM", Double(Float(v) / 1_000_000)) }
    if v >= 10_000 { return String(format: "%.1fK", Double(Float(v) / 1000)) }
    return String(v)
}
