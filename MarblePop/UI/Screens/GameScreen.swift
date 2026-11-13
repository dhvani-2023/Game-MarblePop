import SwiftUI
import UIKit
import GameKit

enum Overlay { case NONE, INTRO, PAUSE, WIN, FAIL, BUY }

let CONTINUE_PRICE = 150

private let PopupText = TextStyle(fontFamily: Fredoka, fontWeight: .SemiBold, fontSize: 17, color: GameColors.Ink, lineHeight: 23, textAlign: .Center)

/// Engine → host bridge (Kotlin's anonymous `GameListener`). Holds the session weakly: the engine owns its listener.
private final class SessionListener: GameListener {
    weak var session: GameSession?
    let snd: SoundManager

    init(_ snd: SoundManager) { self.snd = snd }

    func sound(_ sfx: Sfx, _ pitch: Float, _ volume: Float) { snd.play(sfx, pitch, volume) }
    func haptic(_ kind: Haptic) {
        // Extras (Features.landingHaptics): the filled-cup tap and the win pattern come from LandingHaptics
        if let s = session, MainActor.assumeIsolated({ s.engine.map { s.haptics.replaces(kind, $0) } ?? false }) { return }
        snd.haptic(kind)
    }
    func combo(_ count: Int) {
        guard let s = session else { return }
        MainActor.assumeIsolated {
            s.comboCount = count
            s.comboStamp += 1
        }
    }
    func statusChanged(_ status: GameStatus) {}
}

/// State of one GameScreen: the engine + renderer remembered by Kotlin's `remember(screen, wPx, hPx)`, the
/// overlay/booster/combo state and the display-synced frame loop (GameKit `GameLoop`, up to 120 Hz).
@MainActor
@Observable
final class GameSession {
    let route: GameRoute
    let spec: LevelSpec
    var overlay: Overlay
    var comboCount = 0
    var comboStamp = 0
    var hammerMode = false
    var buyBooster: Booster? = nil
    var toast: String? = nil
    var toastToken = 0
    var resultHandled = false
    var winStars = 0
    var winCoins = 0
    /// Latched when the WIN / FAIL popup first opens, so its content (and its intro animations) start with it.
    var winShown = false
    var failShown = false

    @ObservationIgnored private(set) var engine: GameEngine?
    @ObservationIgnored private(set) var renderer: GameRenderer?
    @ObservationIgnored private(set) var scale: CGFloat = 1       // points per world unit
    @ObservationIgnored private(set) var hudTop: CGFloat = 0       // statusTop + 136 (points)
    let loop = GameLoop()

    @ObservationIgnored private let repo: GameRepository
    @ObservationIgnored private let sound: SoundManager
    @ObservationIgnored private var listener: SessionListener?
    /// Extras (Features.landingHaptics): Core Haptics synced to marbles landing in the cups.
    let haptics: LandingHaptics

    init(route: GameRoute, repo: GameRepository, sound: SoundManager) {
        self.route = route
        self.repo = repo
        self.sound = sound
        spec = LevelGenerator.get(route.level)
        overlay = spec.introduces != nil ? .INTRO : .NONE
        haptics = LandingHaptics(repo: repo)
    }

    /// Builds engine, layout and renderer for the screen size (points) and starts the loop.
    func setup(width: CGFloat, height: CGFloat, statusTop: CGFloat, safeBottom: CGFloat, displayScale: CGFloat) {
        guard engine == nil, width > 0, height > 0 else { return }
        let s = width / 720
        scale = s
        hudTop = statusTop + 136
        let l = SessionListener(sound)
        listener = l
        let layout = GameLayout(Float(height / s), Float(hudTop / s), Float(8 + safeBottom / s), spec)
        let e = GameEngine(spec, layout, l)
        l.session = self
        engine = e
        haptics.begin(e)
        let theme = Themes.get(repo.themeForLevel(spec.number))
        renderer = GameRenderer(engine: e, theme: theme, skin: repo.skin, widthPx: width, heightPx: height, displayScale: displayScale,
                                symbols: ColorBlind.active(repo))
        loop.onTick = { [weak self] dt in self?.tick(dt) }
        loop.start()
    }

    func teardown() {
        loop.stop()
        loop.onTick = nil
        renderer?.release()
    }

    private func tick(_ dt: Double) {
        guard let engine else { return }
        if overlay != .PAUSE && overlay != .INTRO && overlay != .BUY {
            engine.update(Float(dt))
            haptics.afterUpdate(engine)
        }
        if !resultHandled && engine.status != .PLAYING { handleResult(engine) }
    }

    private func handleResult(_ engine: GameEngine) {
        resultHandled = true
        let won = engine.status == .WON
        repo.addStat(.MARBLES, Int64(engine.marblesSorted))
        repo.addStat(.CUPS, Int64(engine.cupsFilled))
        repo.addStat(.BLOCKS, Int64(engine.board.pops))
        repo.maxStat(.MAX_COMBO, Int64(engine.maxCombo))
        repo.addStat(.BOOSTERS, Int64(engine.boostersUsed))
        if won {
            winStars = engine.stars
            winCoins = engine.coinReward() * (route.daily ? 2 : 1)
            if route.daily { repo.markDailyWin() } else { repo.recordWin(spec.number, winStars) }
            repo.addStat(.LEVELS_WON, 1)
            if winStars == 3 { repo.addStat(.THREE_STARS, 1) }
            if spec.isBoss { repo.addStat(.BOSS_WINS, 1) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self else { return }
                self.sound.play(.WIN)
                self.winShown = true
                self.overlay = .WIN
            }
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
                guard let self else { return }
                self.sound.play(.FAIL)
                self.failShown = true
                self.overlay = .FAIL
            }
        }
    }

    /// Touch-down on the play field (Kotlin `awaitFirstDown`), in points.
    func touchDown(_ p: CGPoint) {
        guard let engine, overlay == .NONE else { return }
        let wx = Float(p.x / scale)
        let wy = Float(p.y / scale)
        if hammerMode {
            if engine.hammer(wx, wy) {
                repo.addBooster(.HAMMER, -1)
                hammerMode = false
            }
        } else {
            engine.tap(wx, wy)
        }
    }

    func showToast(_ t: String) {
        toast = t
        toastToken += 1
        let my = toastToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
            guard let self, self.toastToken == my else { return }
            self.toast = nil
        }
    }

    func useBooster(_ b: Booster) {
        guard let engine, engine.status == .PLAYING else { return }
        if repo.boosterCount(b) <= 0 { buyBooster = b; overlay = .BUY; return }
        switch b {
        case .HAMMER: hammerMode.toggle()
        case .MAGNET: if engine.magnet() { repo.addBooster(b, -1) } else { showToast("No marbles to pull yet") }
        case .SLOTS: engine.boosterSlots(); repo.addBooster(b, -1)
        case .SHUFFLE: if engine.boosterShuffle() { repo.addBooster(b, -1) } else { showToast("Nothing to shuffle") }
        }
    }

    func continueGame() {
        guard let engine else { return }
        if repo.spend(CONTINUE_PRICE) {
            engine.continueGame(); resultHandled = false; overlay = .NONE
        }
    }
}

struct GameScreen: View {
    let screen: GameRoute
    let nav: Nav
    @Environment(GameRepository.self) var repo
    @Environment(SoundManager.self) var sound
    @Environment(\.displayScale) var displayScale
    @State var session: GameSession? = nil

    init(screen: GameRoute, nav: Nav) {
        self.screen = screen
        self.nav = nav
    }

    var body: some View {
        let spec = LevelGenerator.get(screen.level)
        GeometryReader { geo in
            let statusTop = max(geo.safeAreaInsets.top, MPWindowInsets.current.top)
            ZStack(alignment: .topLeading) {
                themeColor(Themes.get(repo.themeForLevel(spec.number)).bgBottom)
                if let s = session {
                    GameContent(session: s, screen: screen, nav: nav, statusTop: statusTop)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .onAppear { ensureSession(geo) }
            .onChange(of: geo.size) { _, _ in ensureSession(geo) }
            .onDisappear { session?.teardown() }
        }
        .ignoresSafeArea()
    }

    /// Kotlin `remember(screen, wPx, hPx) { GameEngine(...) }`: built once the full-screen size is known.
    private func ensureSession(_ geo: GeometryProxy) {
        guard session == nil, geo.size.width > 0, geo.size.height > 0 else { return }
        let s = GameSession(route: screen, repo: repo, sound: sound)
        s.setup(width: geo.size.width, height: geo.size.height, statusTop: max(geo.safeAreaInsets.top, MPWindowInsets.current.top),
                safeBottom: max(geo.safeAreaInsets.bottom, MPWindowInsets.current.bottom), displayScale: displayScale)
        session = s
    }
}

private struct GameContent: View {
    let session: GameSession
    let screen: GameRoute
    let nav: Nav
    let statusTop: CGFloat
    @Environment(GameRepository.self) var repo
    @Environment(SoundManager.self) var sound

    var body: some View {
        let spec = session.spec
        ZStack(alignment: .top) {
            // ---------------- play field
            GameCanvas(session: session)

            // ---------------- tutorial hand
            if spec.number <= 2 && !screen.daily && session.overlay == .NONE {
                TutorialLayer(session: session)
            }

            // ---------------- HUD
            VStack(spacing: 0) {
                ZStack {
                    IconRoundButton(.PAUSE, size: 48, color: .Purple, iconScale: 0.5) { session.overlay = .PAUSE }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    LevelBadge(level: spec.number, daily: screen.daily, boss: spec.isBoss)
                        .offset(x: -14, y: 2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    CoinPill(value: Double(repo.coins))
                        .animation(CubicBezierEasing.FastOutSlowIn.tween(700), value: repo.coins)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .frame(height: 56)
                Spacer().frame(height: 8)
                BoosterTray {
                    ForEach(Booster.entries, id: \.self) { b in
                        BoosterButton(b: b, count: repo.boosterCount(b), active: session.hammerMode && b == .HAMMER) {
                            session.useBooster(b)
                        }
                    }
                }
            }
            .padding(.top, statusTop + 6)
            .padding(.horizontal, 12)

            if session.hammerMode {
                HStack(alignment: .center, spacing: 0) {
                    GameIcon(.HAMMER).frame(width: 28, height: 28)
                    Spacer().frame(width: 6)
                    OutlinedText("Tap a block to smash it!", fontSize: 18, shadow: false)
                    Spacer().frame(width: 10)
                    GameButton("Cancel", color: .Red, height: 40, fontSize: 16) { session.hammerMode = false }
                        .frame(width: 96)
                }
                .padding(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 6))
                .background(Capsule().fill(Color(argb: 0xCC1A0B4A)))
                .overlay(Capsule().strokeBorder(Color(argb: 0x59FFFFFF), lineWidth: 2))
                .padding(.top, session.hudTop + 6)
            }

            ComboBanner(count: session.comboCount, stamp: session.comboStamp)

            if let t = session.toast {
                Text(t)
                    .font(GameFonts.fredoka(18, .SemiBold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(argb: 0xE61A0B4A)))
                    .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color(argb: 0x59FFFFFF), lineWidth: 2))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
            }

            // ---------------- overlays (each animates in and out)
            Group {
                PopupHost(visible: session.overlay == .INTRO) {
                    if let f = spec.introduces { FeatureIntroContent(f: f) { session.overlay = .NONE } }
                }
                PopupHost(visible: session.overlay == .PAUSE, onDismiss: { session.overlay = .NONE }) {
                    PauseContent(
                        onResume: { session.overlay = .NONE },
                        onRestart: { nav.replace(.Game(screen.copy(nonce: screen.nonce + 1))) },
                        onHome: { nav.home() })
                }
                PopupHost(visible: session.overlay == .WIN) {
                    if session.winShown {
                        WinContent(level: spec.number, stars: session.winStars, coins: session.winCoins, daily: screen.daily,
                                   maxCombo: session.engine?.maxCombo ?? 0,
                                   onCollect: { mult in repo.addCoins(session.winCoins * mult) },
                                   onNext: {
                                       if screen.daily { nav.home() }
                                       else { nav.replace(.Game(GameRoute(level: min(spec.number + 1, LevelGenerator.MAX_LEVEL)))) }
                                   },
                                   onHome: { nav.home() })
                    }
                }
                PopupHost(visible: session.overlay == .FAIL) {
                    if session.failShown {
                        FailContent(reason: session.engine?.failReason ?? .JAM, coins: repo.coins,
                                    onContinue: { session.continueGame() },
                                    onRetry: { nav.replace(.Game(screen.copy(nonce: screen.nonce + 1))) },
                                    onHome: { nav.home() })
                    }
                }
                PopupHost(visible: session.overlay == .BUY, onDismiss: { session.overlay = .NONE }) {
                    if let b = session.buyBooster {
                        BuyBoosterContent(b: b, coins: repo.coins,
                                          onBuy: { if repo.spend(b.price) { repo.addBooster(b, 1); sound.play(.COIN); session.overlay = .NONE } },
                                          onClose: { session.overlay = .NONE })
                    }
                }
            }
        }
    }
}

/// HUD coin pill counting towards the balance (Kotlin `animateIntAsState(coins, tween(700))`).
private struct CoinPill: View, Animatable {
    var value: Double
    var animatableData: Double {
        get { value }
        set { value = newValue }
    }
    var body: some View { ResourcePill(.COIN, String(Int(value))) }
}

// MARK: - Play field host

/// The play field: the renderer draws into a SwiftUI Canvas re-rendered on every loop frame; touch-down
/// (Kotlin `awaitFirstDown`) goes to the engine.
private struct GameCanvas: View {
    let session: GameSession
    @State var touching = false

    var body: some View {
        // capture the frame tick inside the closure: SwiftUI only redraws a Canvas whose captures changed
        let tick = session.loop.frame
        let renderer = session.renderer
        Canvas { ctx, _ in
            _ = tick
            renderer?.draw(ctx)
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { v in
                    if !touching { touching = true; session.touchDown(v.startLocation) }
                }
                .onEnded { _ in touching = false }
        )
    }
}

// MARK: - Tutorial

/// Tutorial hand + hint for levels 1–2 (re-evaluated every frame like the Kotlin composable reading `frame`).
private struct TutorialLayer: View {
    let session: GameSession

    var body: some View {
        _ = session.loop.frame
        let engine = session.engine
        let pops = engine?.board.pops ?? 0
        return ZStack(alignment: .topLeading) {
            if let engine, pops < 3 {
                let target = engine.hintTarget()
                if let target, !engine.isBusy || pops == 0 {
                    HandPointer()
                        .frame(width: 90, height: 90)
                        .offset(x: CGFloat(target[0]) * session.scale - 3, y: CGFloat(target[1]) * session.scale - 3)
                }
                OutlinedText(pops == 0 ? "Tap a block to pop it!" : "Marbles sort into matching cups!", fontSize: 22, brush: Grad.Snow)
                    .idleBounce(amount: 0.04)
                    .frame(maxWidth: .infinity)
                    .padding(.top, session.hudTop + 8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}

private struct HandPointer: View {
    var body: some View {
        FrameClock { t in
            let k = loopPhase(t, 1100)
            let press = k < 0.5 ? k * 2 : (1 - k) * 2
            Canvas { canvas, size in
                var ctx = canvas
                ctx.translateBy(x: 40, y: 40)
                let s = size.width - 80
                if press > 0.7 {
                    let rr = s * 0.16 * (1 + (press - 0.7) * 3)
                    ctx.stroke(Path(ellipseIn: CGRect(x: s * 0.08 - rr, y: s * 0.08 - rr, width: rr * 2, height: rr * 2)),
                               with: .color(.white.opacity(Double((press - 0.7) * 2.5))), lineWidth: 4)
                }
                var c = ctx
                c.translateBy(x: s * 0.2, y: s * 0.2)
                c.rotate(by: .degrees(-28))
                c.translateBy(x: -s * 0.2, y: -s * 0.2)
                let finger = Path(roundedRect: CGRect(x: s * 0.02, y: s * 0.04, width: s * 0.22, height: s * 0.56), cornerRadius: s * 0.11)
                let palm = Path(roundedRect: CGRect(x: s * 0.02, y: s * 0.38, width: s * 0.58, height: s * 0.48), cornerRadius: s * 0.18)
                for p in [palm, finger] { c.fill(p, with: .color(Color(argb: 0x55000000))) }
                c.fill(palm, with: .color(.white))
                c.fill(finger, with: .color(.white))
                for i in 0..<3 {
                    c.fill(Path(roundedRect: CGRect(x: s * (0.26 + CGFloat(i) * 0.11), y: s * 0.36, width: s * 0.12, height: s * 0.2), cornerRadius: s * 0.06),
                           with: .color(Color(argb: 0xFFE8E2F7)))
                }
                c.stroke(palm, with: .color(GameColors.Ink), lineWidth: 3)
                c.stroke(finger, with: .color(GameColors.Ink), lineWidth: 3)
                let cuff = Path(roundedRect: CGRect(x: s * 0.04, y: s * 0.8, width: s * 0.54, height: s * 0.16), cornerRadius: s * 0.06)
                c.fill(cuff, with: .color(GameColors.Pink))
                c.stroke(cuff, with: .color(GameColors.Ink), lineWidth: 3)
            }
            .padding(-40)
            .offset(x: 10 * pxPt * (1 - press), y: 14 * pxPt * (1 - press))
        }
    }
}

// MARK: - HUD pieces

private struct LevelBadge: View {
    let level: Int
    let daily: Bool
    let boss: Bool

    var body: some View {
        VStack(spacing: 0) {
            Ribbon(daily ? "Daily" : "Level \(level)", boss && !daily ? .Red : .Purple, fontSize: 20, minWidth: 104, height: 44)
            if boss && !daily {
                HStack(alignment: .center, spacing: 0) {
                    GameIcon(.CROWN).frame(width: 22, height: 22)
                    Chip("SUPER HARD", .Red, fontSize: 11)
                }
                .offset(y: -10)
            }
        }
        .fixedSize()
    }
}

/// Glass tray holding the four booster buttons.
private struct BoosterTray<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        SpaceEvenly { content() }
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .background {
            Canvas { ctx, canvasSize in
                let size = CGSize(width: canvasSize.width, height: canvasSize.height - 3)
                let r: CGFloat = 24
                let rect = CGRect(origin: .zero, size: size)
                ctx.fill(Path(roundedRect: rect.offsetBy(dx: 0, dy: 3), cornerRadius: r), with: .color(Color(argb: 0x26140A3C)))
                ctx.fill(Path(roundedRect: rect, cornerRadius: r), with: .linearGradient(Gradient(colors: [Color(argb: 0x40FFFFFF), Color(argb: 0x14FFFFFF)]),
                                                                                        startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                ctx.stroke(Path(roundedRect: rect, cornerRadius: r), with: .color(.white.opacity(0.45)), lineWidth: 1.5)
                ctx.fill(Path(roundedRect: CGRect(x: size.width * 0.06, y: 3, width: size.width * 0.88, height: 3), cornerRadius: 2), with: .color(.white.opacity(0.3)))
            }
            .padding(.bottom, -3)
        }
    }
}

/// `Arrangement.SpaceEvenly` row: equal gaps before, between and after the children.
private struct SpaceEvenly: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let h = subviews.map { $0.sizeThatFits(.unspecified).height }.max() ?? 0
        return CGSize(width: proposal.width ?? subviews.reduce(0) { $0 + $1.sizeThatFits(.unspecified).width }, height: h)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let used = sizes.reduce(0) { $0 + $1.width }
        let gap = max(0, bounds.width - used) / CGFloat(subviews.count + 1)
        var x = bounds.minX + gap
        for (i, s) in subviews.enumerated() {
            s.place(at: CGPoint(x: x, y: bounds.midY), anchor: .leading, proposal: ProposedViewSize(sizes[i]))
            x += sizes[i].width + gap
        }
    }
}

private struct BoosterButton: View {
    let b: Booster
    let count: Int
    let active: Bool
    let onClick: () -> Void

    var body: some View {
        FrameClock(paused: !active) { t in
            let p = loopPhase(t, 900)
            ZStack {
                if active {
                    Canvas { ctx, size in
                        let c = CGPoint(x: size.width / 2, y: size.height / 2)
                        let r = 64 * (0.45 + 0.25 * p)
                        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                                 with: .color(Color(argb: 0xFFFFE680).opacity(Double(0.55 * (1 - p)))))
                    }
                    .frame(width: 100, height: 100)
                    .allowsHitTesting(false)
                }
                GameButton("", color: active ? .Yellow : .Blue, height: 56, icon: boosterIcon(b), corner: 18, iconSize: 38, onClick: onClick)
                    .frame(width: 56, height: 56)
                ZStack {
                    Circle().fill(count > 0
                                  ? LinearGradient(colors: [GameColors.GreenLight, GameColors.Green], startPoint: .top, endPoint: .bottom)
                                  : LinearGradient(colors: [Color(argb: 0xFFFFA8D4), GameColors.Pink], startPoint: .top, endPoint: .bottom))
                    Circle().strokeBorder(.white, lineWidth: 2)
                    if count > 0 {
                        OutlinedText(String(count), fontSize: 13, outline: GameColors.GreenDark, shadow: false)
                    } else {
                        GameIcon(.PLUS).frame(width: 13, height: 13)
                    }
                }
                .frame(width: 25, height: 25)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .allowsHitTesting(false)
            }
            .frame(width: 64, height: 64)
            .scaleEffect(active ? 1 + 0.07 * sin(p * 2 * .pi) : 1)
        }
        .frame(width: 64, height: 64)
    }
}

private struct ComboBanner: View {
    let count: Int
    let stamp: Int
    @State var v: CGFloat = 0
    @State var gen = 0

    var body: some View {
        ZStack {
            if count >= 2 && stamp != 0 {
                let text: String = {
                    switch count { case 2: return "Nice!"; case 3: return "Great!"; case 4: return "Awesome!"; case 5: return "Amazing!"; default: return "Marble-ous!" }
                }()
                let brush: Brush = {
                    switch count { case 2: return Grad.Aqua; case 3: return Grad.Mint; case 4: return Grad.Gold; case 5: return Grad.Coral; default: return Grad.Pink }
                }()
                ZStack {
                    SunRays(color: Color(argb: 0xFFFFF3B0), alpha: 0.35, rays: 14, degPerSec: 60, radiusScale: 0.5)
                        .frame(width: 240, height: 240)
                    VStack(spacing: 0) {
                        OutlinedText(text, fontSize: 52, outline: GameColors.Night, brush: brush, gloss: true)
                            .fixedSize()
                        Chip("COMBO x\(count)", .Pink, fontSize: 18)
                    }
                }
                .modifier(PopFX(v: v, rotation: -6))
                .offset(y: -90)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
        .onChange(of: stamp) { _, _ in run() }
    }

    private func run() {
        guard count >= 2 else { return }
        gen += 1
        let my = gen
        var tr = Transaction()
        tr.disablesAnimations = true
        withTransaction(tr) { v = 0 }
        DispatchQueue.main.async {
            withAnimation(.compose(dampingRatio: 0.42, stiffness: 520), completionCriteria: .logicallyComplete) { v = 1 } completion: {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.56) {
                    guard gen == my else { return }
                    withAnimation(CubicBezierEasing.FastOutSlowIn.tween(240)) { v = 0 }
                }
            }
        }
    }
}

/// Soft halo + floor shadow behind a showcased item.
private struct Pedestal<Content: View>: View {
    var glow: Color = Color(argb: 0xFFFFE680)
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            Canvas { ctx, size in
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                let r = min(size.width, size.height) * 0.55
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)),
                         with: .radialGradient(Gradient(colors: [glow.opacity(0.55), glow.opacity(0)]), center: c, startRadius: 0, endRadius: r))
                ctx.fill(Path(ellipseIn: CGRect(x: size.width * 0.2, y: size.height * 0.84, width: size.width * 0.6, height: size.height * 0.12)),
                         with: .color(Color(argb: 0x332A1463)))
            }
            content()
        }
    }
}

private struct FeatureIntroContent: View {
    let f: Feature
    let onOk: () -> Void
    @Environment(\.displayScale) var displayScale

    var body: some View {
        GamePanel("New!", ribbon: .Pink, rays: true) {
            Pedestal {
                Canvas { ctx, size in
                    let s = size.width
                    if f == .HIDDEN_CUP {
                        Painter.cup(ctx, s * 0.05, s * 0.3, s * 0.9, s * 0.42, 0, true)
                    } else {
                        let variant: Int = f == .MYSTERY ? 1 : (f == .RAINBOW ? 3 : 0)
                        Painter.block(ctx, 0, 0, s, 2, variant)
                        let ov: Int = {
                            switch f {
                            case .COUNTER: return SpriteCache.OV_CAGE
                            case .KEY: return SpriteCache.OV_KEY
                            case .CRATE: return SpriteCache.OV_CRATE
                            case .ICE: return SpriteCache.OV_ICE
                            case .ARROW: return SpriteCache.OV_ARROW
                            case .BOMB: return SpriteCache.OV_BOMB
                            case .PAINT: return SpriteCache.OV_BUCKET
                            case .SWITCH: return SpriteCache.OV_SWITCH
                            default: return -1
                            }
                        }()
                        if ov > 0 {
                            let sprite = SpriteCache.ui(displayScale).overlay(ov, s, ov == SpriteCache.OV_BUCKET ? 2 : 1)
                            ctx.draw(sprite.image, in: CGRect(x: 0, y: 0, width: s, height: s))
                        }
                        if f == .COUNTER { Painter.badge(ctx, s / 2, s * 0.45, s * 0.2, "3", 0xFF3D6BFF) }
                        if f == .CRATE { Painter.badge(ctx, s / 2, s * 0.44, s * 0.2, "4", 0xFFFF9F1C) }
                        if f == .BOMB { Painter.badge(ctx, s * 0.76, s * 0.24, s * 0.17, "8", 0xFF4A4E69) }
                        if f == .DOUBLE { Painter.badge(ctx, s * 0.78, s * 0.2, s * 0.17, "x2", 0xFF3CCB5A) }
                    }
                }
                .frame(width: 124, height: 124)
                .idleBounce(amount: 0.06)
            }
            .frame(width: 170, height: 170)
            OutlinedText(f.title, fontSize: 30, brush: Grad.Gold, gloss: true)
            Spacer().frame(height: 6)
            Text(f.description).textStyle(PopupText).fixedSize(horizontal: false, vertical: true)
            Spacer().frame(height: 18)
            GameButton("Got it!", color: .Green, shine: true) { onOk() }
                .frame(maxWidth: .infinity)
        }
    }
}

private struct PauseContent: View {
    let onResume: () -> Void
    let onRestart: () -> Void
    let onHome: () -> Void
    @Environment(GameRepository.self) var repo
    @Environment(SoundManager.self) var sound

    var body: some View {
        GamePanel("Paused", onClose: onResume) {
            VStack(spacing: 0) {
                ToggleRow(icon: .MUSIC, label: "Music", value: repo.musicOn, color: .Pink) { repo.setMusic($0); sound.onMusicSettingChanged() }
                ToggleRow(icon: .SOUND, label: "Sound", value: repo.sfxOn, color: .Blue) { repo.setSfx($0) }
                ToggleRow(icon: .VIBRATE, label: "Vibration", value: repo.hapticsOn, color: .Purple) { repo.setHaptics($0) }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(argb: 0x0F4521C2)))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Color(argb: 0x1F4521C2), lineWidth: 1.5))
            Spacer().frame(height: 16)
            GameButton("Resume", color: .Green, icon: .PLAY, shine: true) { onResume() }
                .frame(maxWidth: .infinity)
            Spacer().frame(height: 10)
            WeightRow(weights: [1, 1], spacing: 10) {
                GameButton("Restart", color: .Yellow, height: 54, fontSize: 20, icon: .RETRY) { onRestart() }
                GameButton("Home", color: .Blue, height: 54, fontSize: 20, icon: .HOME) { onHome() }
            }
        }
    }
}

struct ToggleRow: View {
    let icon: Ico
    let label: String
    let value: Bool
    var color: BtnColor = .Purple
    let onChange: (Bool) -> Void

    init(icon: Ico, label: String, value: Bool, color: BtnColor = .Purple, onChange: @escaping (Bool) -> Void) {
        self.icon = icon
        self.label = label
        self.value = value
        self.color = color
        self.onChange = onChange
    }

    var body: some View {
        HStack(alignment: .center, spacing: 0) {
            IconTile(icon, color, size: 44, iconScale: 0.6)
            Spacer().frame(width: 12)
            Text(label).textStyle(TextStyle(fontFamily: LilitaOne, fontSize: 21, color: GameColors.Ink)).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            GameToggle(value, onChange: onChange)
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity)
    }
}

private struct WinContent: View {
    let level: Int
    let stars: Int
    let coins: Int
    let daily: Bool
    let maxCombo: Int
    let onCollect: (Int) -> Void
    let onNext: () -> Void
    let onHome: () -> Void
    @Environment(SoundManager.self) var sound
    @State var starAnims: [CGFloat] = [0, 0, 0]
    @State var collected = false
    @State var shownCoins = 0
    @State var started = false
    @State var origin = Date()
    @State var countDone = false

    var body: some View {
        ZStack {
            GamePanel(daily ? "Daily Done!" : "Level \(level)", ribbon: .Green, rays: true) {
                OutlinedText("COMPLETE!", fontSize: 36, outline: GameColors.Night, brush: Grad.Gold, gloss: true)
                Spacer().frame(height: 6)
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(0..<3, id: \.self) { i in
                        WinStar(v: starAnims[i])
                            .frame(width: i == 1 ? 82 : 64, height: i == 1 ? 82 : 64)
                            .offset(y: i == 1 ? -12 : 0)
                    }
                }
                if maxCombo >= 3 {
                    Spacer().frame(height: 4)
                    HStack(alignment: .center, spacing: 0) {
                        GameIcon(.FLAME).frame(width: 20, height: 20)
                        Spacer().frame(width: 4)
                        Text("Best combo x\(maxCombo)").textStyle(PopupText.copy(fontSize: 15, color: GameColors.InkSoft))
                    }
                }
                Spacer().frame(height: 10)
                HStack(alignment: .center, spacing: 0) {
                    GameIcon(.COIN).frame(width: 40, height: 40)
                    Spacer().frame(width: 6)
                    FrameClock(paused: collected || countDone, origin: origin) { t in
                        // coinCount: tween(900) after 250 ms
                        let shown = collected ? Double(shownCoins) : Double(coins) * ComposeEasing.fastOutSlowIn((t * 1000 - 250) / 900)
                        OutlinedText("+\(Int(shown))", fontSize: 34, brush: Grad.Gold, gloss: true)
                    }
                    .fixedSize()
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 2)
                .background(Capsule().fill(Color(argb: 0x144521C2)))
                Spacer().frame(height: 12)
                if !collected {
                    FrameClock(origin: origin) { t in
                        // needle: infiniteRepeatable(tween(1300, Linear), Reverse)
                        let cyc = (t * 1000).truncatingRemainder(dividingBy: 2600) / 1300
                        let needle = CGFloat(cyc <= 1 ? cyc : 2 - cyc)
                        CollectSection(needle: needle, coins: coins, onCollect: { mult in
                            collected = true
                            shownCoins = coins * mult
                            onCollect(mult)
                            sound.play(.REWARD)
                        }, onClaimOne: {
                            if !collected { collected = true; shownCoins = coins; onCollect(1); sound.play(.COIN) }
                        })
                    }
                } else {
                    GameButton(daily ? "Home" : "Next Level", color: .Green, icon: .PLAY, shine: true) { onNext() }
                        .frame(maxWidth: .infinity)
                        .idleBounce(amount: 0.035)
                    Spacer().frame(height: 10)
                    if !daily {
                        GameButton("Home", color: .Blue, height: 50, fontSize: 20, icon: .HOME) { onHome() }
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            ConfettiBurst(count: 80).allowsHitTesting(false)
        }
        .onAppear(perform: start)
    }

    private func start() {
        guard !started else { return }
        started = true
        shownCoins = coins
        origin = Date()
        for i in 0..<stars {
            withAnimation(.compose(dampingRatio: 0.4, stiffness: 600).delay(0.35 + 0.26 * Double(i))) { starAnims[i] = 1 }
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_250_000_000)
            countDone = true
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            for i in 0..<stars {
                sound.play(.STAR, 1 + Float(i) * 0.15)
                try? await Task.sleep(nanoseconds: 260_000_000)
            }
        }
    }
}

private let winSegments = [2, 3, 5, 3, 2]

/// Lucky multiplier bar, the live "Collect xN" button and the "Claim x1" link (re-drawn with the needle).
private struct CollectSection: View {
    let needle: CGFloat
    let coins: Int
    let onCollect: (Int) -> Void
    let onClaimOne: () -> Void

    var body: some View {
        let mult = winSegments[min(max(Int(needle * CGFloat(winSegments.count)), 0), winSegments.count - 1)]
        VStack(spacing: 0) {
            MultiplierBar(segments: winSegments, needle: needle)
            Spacer().frame(height: 14)
            GameButton("Collect x\(mult)", color: .Yellow, icon: .COIN, sound: .COIN, shine: true) { onCollect(mult) }
                .frame(maxWidth: .infinity)
                .idleBounce(amount: 0.035)
            Spacer().frame(height: 8)
            Text("Claim x1")
                .textStyle(PopupText.copy(fontSize: 16, color: GameColors.InkSoft))
                .padding(4)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { _ in onClaimOne() })
        }
    }
}

private struct WinStar: View, Animatable {
    var v: CGFloat
    var animatableData: CGFloat {
        get { v }
        set { v = newValue }
    }

    var body: some View {
        ZStack {
            GameIcon(.STAR_EMPTY)
            GameIcon(.STAR)
                .scaleEffect(max(0.0001, v))
                .rotationEffect(.degrees(Double((1 - v) * 90)))
                .opacity(Double(min(1, max(0, v))))
            // sparkle burst as the star lands
            Canvas { ctx, size in
                if v <= 0.05 { return }
                let p = min(max(v, 0), 1.2) / 1.2
                if p >= 0.98 { return }
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                for k in 0..<6 {
                    let ang = CGFloat(k) * .pi / 3 + 0.3
                    let rr = min(size.width, size.height) * (0.18 + 0.3 * p)
                    let sr = 7 * (1 - p) + 2
                    drawSparkle(ctx, c.x + cos(ang) * rr, c.y + sin(ang) * rr, sr, Color(argb: 0xFFFFF3B0).opacity(Double(1 - p)))
                }
            }
            .frame(width: 130, height: 130)
            .allowsHitTesting(false)
        }
    }
}

private struct MultiplierBar: View {
    let segments: [Int]
    let needle: CGFloat

    var body: some View {
        let cols: [BtnColor] = [.Blue, .Green, .Pink, .Green, .Blue]
        ZStack {
            HStack(spacing: 0) {
                ForEach(segments.indices, id: \.self) { i in
                    let c = cols[i]
                    let shape = UnevenRoundedRectangle(cornerRadii: RectangleCornerRadii(
                        topLeading: i == 0 ? 13 : 0, bottomLeading: i == 0 ? 13 : 0,
                        bottomTrailing: i == segments.count - 1 ? 13 : 0, topTrailing: i == segments.count - 1 ? 13 : 0), style: .circular)
                    ZStack {
                        shape.fill(LinearGradient(colors: [c.top, c.bottom], startPoint: .top, endPoint: .bottom))
                        GeometryReader { g in
                            Rectangle().fill(.white.opacity(0.3)).frame(width: g.size.width, height: g.size.height * 0.28).offset(y: 2)
                        }
                        OutlinedText("x\(segments[i])", fontSize: 19, outline: c.outline)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if i < segments.count - 1 {
                        Rectangle().fill(Color(argb: 0x664521C2)).frame(width: 2)
                    }
                }
            }
            .padding(3)
            .background {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .circular).fill(Color(argb: 0xFF331589)).offset(y: 3)
                    RoundedRectangle(cornerRadius: 16, style: .circular).fill(Color(argb: 0xFF4521C2))
                }
            }
            .padding(.top, 6)
            Canvas { ctx, size in
                let x = size.width * min(max(needle, 0), 1)
                var p = Path()
                p.move(to: CGPoint(x: x, y: size.height * 0.36))
                p.addLine(to: CGPoint(x: x - 10, y: 0))
                p.addLine(to: CGPoint(x: x + 10, y: 0))
                p.closeSubpath()
                ctx.fill(Path(roundedRect: CGRect(x: x - 1, y: 4, width: 4, height: size.height - 4), cornerRadius: 2), with: .color(Color(argb: 0x552A1463)))
                ctx.fill(Path(roundedRect: CGRect(x: x - 2, y: 2, width: 4, height: size.height - 4), cornerRadius: 2), with: .color(.white))
                ctx.fill(p, with: .color(.white))
                ctx.stroke(p, with: .color(GameColors.Ink), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
            }
            .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 50)
    }
}

private struct FailContent: View {
    let reason: FailReason
    let coins: Int
    let onContinue: () -> Void
    let onRetry: () -> Void
    let onHome: () -> Void

    var body: some View {
        let (title, text): (String, String) = {
            switch reason {
            case .JAM: return ("Belt Jammed!", "The belt is full. Continue with 10 extra slots?")
            case .BOMB: return ("Boom!", "A bomb went off. Continue with 6 more moves?")
            case .NO_MOVES: return ("Stuck!", "No moves left. Continue with a tray shuffle and extra slots?")
            }
        }()
        GamePanel(title, ribbon: .Red, onClose: onHome) {
            Pedestal(glow: Color(argb: 0xFFFF9AA3)) {
                FrameClock { t in
                    let k = loopPhase(t, 1400)
                    Canvas { ctx, size in
                        let jitter = k < 0.3 ? sin(k / 0.3 * 8 * .pi) * 3 : 0
                        if reason == .BOMB {
                            Painter.bomb(ctx, size.width / 2 + jitter, size.height * 0.55, size.height * 0.75, 0)
                        } else {
                            // a jammed belt crammed with marbles
                            let top = size.height * 0.3
                            ctx.fill(Path(roundedRect: CGRect(x: jitter, y: top, width: size.width, height: size.height * 0.5), cornerRadius: size.height * 0.25),
                                     with: .color(Color(argb: 0xFF1E1750)))
                            ctx.fill(Path(roundedRect: CGRect(x: jitter + 4, y: top + 4, width: size.width - 8, height: size.height * 0.5 - 8), cornerRadius: size.height * 0.2),
                                     with: .color(Color(argb: 0xFF3B2F86)))
                            let cols = [0, 1, 2, 3, 4, 6, 7, 5, 1]
                            for i in 0..<9 {
                                ball(ctx, CGPoint(x: jitter + size.width * (0.09 + CGFloat(i) * 0.103), y: top + size.height * 0.25), size.height * 0.11, cols[i])
                            }
                            // warning sign
                            let wx = size.width / 2
                            var tri = Path()
                            tri.move(to: CGPoint(x: wx, y: 0))
                            tri.addLine(to: CGPoint(x: wx + size.height * 0.24, y: size.height * 0.4))
                            tri.addLine(to: CGPoint(x: wx - size.height * 0.24, y: size.height * 0.4))
                            tri.closeSubpath()
                            ctx.fill(tri, with: .color(Color(argb: 0xFFFFC93C)))
                            ctx.stroke(tri, with: .color(Color(argb: 0xFF8A4A00)), style: StrokeStyle(lineWidth: 2.5, lineJoin: .round))
                            var bar = Path()
                            bar.move(to: CGPoint(x: wx, y: size.height * 0.12))
                            bar.addLine(to: CGPoint(x: wx, y: size.height * 0.27))
                            ctx.stroke(bar, with: .color(Color(argb: 0xFF2A1463)), lineWidth: 3)
                            ctx.fill(Path(ellipseIn: CGRect(x: wx - 2, y: size.height * 0.33 - 2, width: 4, height: 4)), with: .color(Color(argb: 0xFF2A1463)))
                        }
                    }
                }
                .frame(width: 180, height: 96)
            }
            .frame(width: 200, height: 110)
            Text(text).textStyle(PopupText).fixedSize(horizontal: false, vertical: true)
            Spacer().frame(height: 16)
            GameButton("Continue  \(CONTINUE_PRICE)", color: .Yellow, enabled: coins >= CONTINUE_PRICE, icon: .COIN, shine: coins >= CONTINUE_PRICE) { onContinue() }
                .frame(maxWidth: .infinity)
            Spacer().frame(height: 10)
            GameButton("Try Again", color: .Green, icon: .RETRY) { onRetry() }
                .frame(maxWidth: .infinity)
        }
    }
}

private struct BuyBoosterContent: View {
    let b: Booster
    let coins: Int
    let onBuy: () -> Void
    let onClose: () -> Void

    var body: some View {
        GamePanel(b.title, ribbon: .Blue, onClose: onClose, rays: true) {
            Pedestal(glow: Color(argb: 0xFF9BE9FF)) {
                GameIcon(boosterIcon(b)).frame(width: 100, height: 100).idleBounce(amount: 0.06)
            }
            .frame(width: 150, height: 150)
            Text(b.description).textStyle(PopupText).fixedSize(horizontal: false, vertical: true)
            Spacer().frame(height: 16)
            GameButton("Buy  \(b.price)", color: .Green, enabled: coins >= b.price, icon: .COIN, shine: coins >= b.price) { onBuy() }
                .frame(maxWidth: .infinity)
            Spacer().frame(height: 6)
            Text(coins < b.price ? "Not enough coins" : "You have \(coins) coins")
                .textStyle(PopupText.copy(fontSize: 15, color: coins < b.price ? GameColors.Red : GameColors.InkSoft))
        }
    }
}


/// Key-window safe-area insets: the game view ignores the safe area (full-bleed), so its own insets read 0.
@MainActor
enum MPWindowInsets {
    static var current: UIEdgeInsets {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let window = scenes.flatMap(\.windows).first(where: \.isKeyWindow) ?? scenes.first?.windows.first
        return window?.safeAreaInsets ?? .zero
    }
}
