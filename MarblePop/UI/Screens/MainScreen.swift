import SwiftUI
import GameKit

private let DockHeight: CGFloat = 82
private let NodeRowHeight: CGFloat = 118
/// Level map LazyColumn `contentPadding(top = 150.dp, bottom = 130.dp)`.
private let MapTopPad: CGFloat = 150
private let MapBottomPad: CGFloat = 130

/// Popup body text (Kotlin `PopupBody`: Fredoka SemiBold 17 sp / 23 sp line height, ink, centred).
struct PopupBodyText: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .textStyle(TextStyle(fontFamily: Fredoka, fontWeight: .SemiBold, fontSize: 17, color: GameColors.Ink, lineHeight: 23, textAlign: .Center))
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct MainScreen: View {
    let nav: Nav
    @Environment(GameRepository.self) private var repo
    @State var homeWorld = -1

    var body: some View {
        let world = homeWorld >= 0 ? homeWorld : LevelGenerator.themeFor(repo.level)
        ZStack(alignment: .bottom) {
            AnimatedSky(target: nav.tab == 2 ? world : -1)
                .ignoresSafeArea()
            AnimatedSwitcher(target: nav.tab, spec: { from, to in
                let dir: CGFloat = to > from ? 1 : -1
                return ContentTransformSpec(
                    enter: ScreenMotion(fade: Tween(duration: 200 + 40), slide: Tween(duration: 300 + 40, easing: .enter), slideFraction: dir / 3),
                    exit: ScreenMotion(fade: Tween(duration: 200 - 40), slide: Tween(duration: 300 + 40, easing: .enter), slideFraction: -dir / 3))
            }) { tab in
                Group {
                    switch tab {
                    case 0: ShopTab()
                    case 1: DailyTab(nav: nav)
                    case 2: HomeTab(nav: nav) { homeWorld = $0 }
                    case 3: CollectionTab()
                    default: ProfileTab()
                    }
                }
                .padding(.bottom, DockHeight)
            }
            BottomDock(selected: nav.tab) { nav.tab = $0 }
        }
    }
}

/// Sky that blends to a new palette over 700 ms (home worlds ↔ menu tabs). `target`: world index, -1 = menu.
private struct AnimatedSky: View {
    let target: Int
    @State var from: Int? = nil
    @State var to: Int? = nil
    @State var gen = 0

    var body: some View {
        SkyFade(from: palette(from ?? target), to: palette(to ?? target), animate: from != nil)
            .id(gen)
            .onChange(of: target) { old, new in
                from = to ?? old
                to = new
                gen += 1
            }
    }

    private func palette(_ i: Int) -> SkyPalette { i < 0 ? Skies.Menu : Skies.forWorld(i) }
}

private struct SkyFade: View {
    let from: SkyPalette
    let to: SkyPalette
    let animate: Bool
    @State var t: CGFloat = 0

    var body: some View {
        SkyBlend(from: from, to: to, t: animate ? t : 1)
            .onAppear { withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.7)) { t = 1 } }
    }
}

private struct SkyBlend: View, Animatable {
    let from: SkyPalette
    let to: SkyPalette
    var t: CGFloat
    var animatableData: CGFloat {
        get { t }
        set { t = newValue }
    }
    var body: some View {
        SkyBackground(t >= 1 ? to : from.lerpTo(to, Float(t)))
    }
}

// ============================================================ bottom dock

private struct TabDef { let icon: Ico; let label: String }
private let tabs = [TabDef(icon: .SHOP, label: "Shop"), TabDef(icon: .CALENDAR, label: "Daily"), TabDef(icon: .PLAY, label: "Play"),
                    TabDef(icon: .MARBLES, label: "Collection"), TabDef(icon: .TROPHY, label: "Profile")]
private let tabWeights: [CGFloat] = [1, 1, 1.25, 1, 1]

private struct BottomDock: View {
    let selected: Int
    let onSelect: (Int) -> Void
    @Environment(GameRepository.self) private var repo
    @Environment(SoundManager.self) private var sound

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let total = tabWeights.reduce(0, +)
            HStack(spacing: 0) {
                ForEach(0..<tabs.count, id: \.self) { i in
                    let sel = i == selected
                    let badge: Bool = {
                        switch i {
                        case 1: return repo.canSpin || repo.canClaimLogin || !repo.dailyChallengeDone
                        case 0: return nowMillis() >= repo.freeGiftAt
                        default: return false
                        }
                    }()
                    ZStack(alignment: .bottom) {
                        Color.clear
                        if i == 2 {
                            DockPlayButton(lift: sel ? 1 : 0)
                                .padding(.bottom, 18)
                        } else {
                            DockTabItem(def: tabs[i], selected: sel, badge: badge, lift: sel ? 1 : 0)
                                .padding(.bottom, 10)
                        }
                    }
                    .animation(Motion.bouncy(), value: sel)
                    .frame(width: w * tabWeights[i] / total, height: DockHeight + 18)
                    .contentShape(Rectangle())
                    .onTapGesture { if !sel { sound.play(.BUTTON); onSelect(i) } }
                }
            }
        }
        .frame(height: DockHeight + 18)
        .background(alignment: .top) {
            // body starts 18 pt below the row top; its 16 pt shadow sits just above it; it runs under the home indicator
            DockBody(pos: CGFloat(selected))
                .padding(.top, 2)
                .animation(.compose(dampingRatio: 0.72, stiffness: 480), value: selected)
                .ignoresSafeArea(edges: .bottom)
        }
    }
}

/// Dock body + sliding pink selection pill (fades out under the centre play button).
private struct DockBody: View, Animatable {
    var pos: CGFloat
    var animatableData: CGFloat {
        get { pos }
        set { pos = newValue }
    }

    var body: some View {
        Canvas { canvas, size in
            var ctx = canvas
            ctx.translateBy(x: 0, y: 16)
            let w = size.width
            let h = DockHeight
            let r: CGFloat = 26
            var body = Path()
            body.addRoundedRect(in: CGRect(x: 0, y: 0, width: w, height: size.height - 16 + r),
                                cornerRadii: RectangleCornerRadii(topLeading: r, bottomLeading: 0, bottomTrailing: 0, topTrailing: r))
            ctx.fill(Path(CGRect(x: 0, y: -16, width: w, height: 16)),
                     with: .linearGradient(Gradient(colors: [.clear, Color(argb: 0x40140A3C)]), startPoint: CGPoint(x: 0, y: -16), endPoint: .zero))
            ctx.fill(body, with: .linearGradient(Gradient(colors: [Color(argb: 0xFF6038E0), Color(argb: 0xFF2E1689)]),
                                                 startPoint: .zero, endPoint: CGPoint(x: 0, y: h)))
            ctx.stroke(body, with: .color(.white.opacity(0.3)), lineWidth: 1.5)
            let total = tabWeights.reduce(0, +)
            var centers = [CGFloat](repeating: 0, count: tabWeights.count)
            var widths = [CGFloat](repeating: 0, count: tabWeights.count)
            var acc: CGFloat = 0
            for i in tabWeights.indices { widths[i] = w * tabWeights[i] / total; centers[i] = acc + widths[i] / 2; acc += widths[i] }
            let pillH = h - 14
            let d: CGFloat = 4
            let pr: CGFloat = 20
            let pink = BtnColor.Pink
            let p = min(max(pos, 0), CGFloat(tabWeights.count - 1))
            let i0 = min(Int(p), tabWeights.count - 2)
            let f = p - CGFloat(i0)
            let cx = centers[i0] + (centers[i0 + 1] - centers[i0]) * f
            let pw = (widths[i0] + (widths[i0 + 1] - widths[i0]) * f) - 10
            let a = min(max(abs(p - 2) * 1.6, 0), 1)
            if a > 0.01 {
                let top: CGFloat = 7
                var c = ctx
                c.opacity = Double(a)
                c.fill(Path(roundedRect: CGRect(x: cx - pw / 2, y: top + d, width: pw, height: pillH - d), cornerRadius: pr), with: .color(pink.depth))
                c.fill(Path(roundedRect: CGRect(x: cx - pw / 2, y: top, width: pw, height: pillH - d), cornerRadius: pr),
                       with: .linearGradient(Gradient(colors: [pink.top, pink.bottom]), startPoint: CGPoint(x: 0, y: 7), endPoint: CGPoint(x: 0, y: 7 + pillH - d)))
                c.fill(Path(roundedRect: CGRect(x: cx - pw / 2 + pw * 0.08, y: top + 4, width: pw * 0.84, height: (pillH - d) * 0.3), cornerRadius: 8),
                       with: .color(.white.opacity(0.4)))
                c.stroke(Path(roundedRect: CGRect(x: cx - pw / 2, y: top, width: pw, height: pillH), cornerRadius: pr), with: .color(pink.outline), lineWidth: 1.8)
            }
        }
    }
}

private struct DockTabItem: View, Animatable {
    let def: TabDef
    let selected: Bool
    let badge: Bool
    var lift: CGFloat
    var animatableData: CGFloat {
        get { lift }
        set { lift = newValue }
    }

    var body: some View {
        let s = 0.88 + 0.2 * lift
        VStack(spacing: 0) {
            GameIcon(def.icon)
                .frame(width: 40, height: 40)
                .scaleEffect(s)
                .rotationEffect(.degrees(Double(sin(lift * .pi) * -8)))
                .overlay(alignment: .topTrailing) {
                    if badge { NotifyBadge(size: 15).offset(x: 4, y: -2) }
                }
            OutlinedText(def.label, fontSize: 12, color: selected ? .white : .white.opacity(0.78),
                         outline: selected ? BtnColor.Pink.outline : GameColors.Night, maxLines: 1)
        }
        .offset(y: -lift * 5)
    }
}

/// Raised gold marble button in the middle of the dock.
private struct DockPlayButton: View, Animatable {
    var lift: CGFloat
    var animatableData: CGFloat {
        get { lift }
        set { lift = newValue }
    }

    var body: some View {
        let s = 0.94 + 0.08 * lift
        FrameClock(paused: lift <= 0.01) { t in
            let pulse = loopPhase(t, 1800)
            Canvas { ctx, size in
                let r: CGFloat = 35
                let c = CGPoint(x: size.width / 2, y: size.height / 2)
                func circle(_ cc: CGPoint, _ rr: CGFloat) -> Path { Path(ellipseIn: CGRect(x: cc.x - rr, y: cc.y - rr, width: rr * 2, height: rr * 2)) }
                if lift > 0.01 {
                    let p = pulse
                    ctx.stroke(circle(c, r * (1.02 + p * 0.35)), with: .color(.white.opacity(Double((1 - p) * 0.5 * lift))), lineWidth: 3 * (1 - p) + 1)
                }
                ctx.fill(circle(CGPoint(x: c.x, y: c.y + 5), r), with: .color(Color(argb: 0x40140A3C)))
                ctx.fill(circle(CGPoint(x: c.x, y: c.y + 3), r), with: .color(Color(argb: 0xFFB86A00)))
                ctx.fill(circle(c, r), with: .linearGradient(Gradient(colors: [Color(argb: 0xFFFFF0A0), Color(argb: 0xFFFFB21A)]),
                                                            startPoint: CGPoint(x: 0, y: c.y - r), endPoint: CGPoint(x: 0, y: c.y + r)))
                ctx.stroke(circle(c, r * 0.8), with: .color(.white.opacity(0.6)), lineWidth: 2)
                ctx.fill(Path(ellipseIn: CGRect(x: c.x - r * 0.55, y: c.y - r * 0.82, width: r * 1.1, height: r * 0.5)), with: .color(.white.opacity(0.55)))
                ctx.stroke(circle(CGPoint(x: c.x, y: c.y + 1.5), r), with: .color(Color(argb: 0xFF8A4A00)), lineWidth: 2.2)
            }
            .frame(width: 70 * 1.5, height: 70 * 1.5)
        }
        .frame(width: 70, height: 70)
        .overlay {
            GameIcon(.PLAY).frame(width: 34, height: 34).offset(x: 3)
        }
        .scaleEffect(s)
    }
}

// ============================================================ home / level map

private struct HomeTab: View {
    let nav: Nav
    let onWorld: (Int) -> Void
    @Environment(GameRepository.self) private var repo
    @Environment(SoundManager.self) private var sound
    @State var chestPopup = -1
    @State var shownChest = -1
    @State var giftPopup = false
    @State var lockedLevel = -1
    @State var shownLocked = -1
    @State var centerWorld = -1

    var body: some View {
        let current = repo.level
        let avatar = repo.avatar
        let _ = repo.starsVersion
        let adLevels = repo.adUnlockedLevels
        let opened = repo.openedChests
        ZStack(alignment: .top) {
            GeometryReader { geo in
                let h = geo.size.height
                if h > 0 {
                    Group {
                    if #available(iOS 18.0, *) {
                        LevelMapScroll18(viewportH: h, startOffset: mapOffset(index: max(current - 3, 0), viewport: h),
                                         request: $scrollRequest, offsetFor: { mapOffset(index: $0, viewport: h) },
                                         onVisibleBottom: { updateWorld(visibleBottom: $0) }) {
                            levelRows(current: current, avatar: avatar, adLevels: adLevels, opened: opened)
                        }
                    } else {
                        ScrollViewReader { proxy in
                            ScrollView(.vertical, showsIndicators: false) {
                                levelRows(current: current, avatar: avatar, adLevels: adLevels, opened: opened)
                                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named("map")).minY } action: { minY in
                                        updateWorld(visibleBottom: -minY + h)
                                    }
                            }
                            .coordinateSpace(name: "map")
                            .ignoresSafeArea(edges: .top)
                            .defaultScrollAnchor(.bottom)
                            .onAppear { scroll(proxy, toIndex: max(current - 3, 0), viewport: h, animated: false) }
                            .onChange(of: scrollRequest) { _, req in
                                if let req { scroll(proxy, toIndex: req, viewport: h, animated: true); scrollRequest = nil }
                            }
                        }
                    }
                    }
                    .onAppear {
                        // Kotlin LaunchedEffect(centerWorld): the world of the initial map position is reported on entry
                        if centerWorld < 0 { updateWorld(visibleBottom: mapOffset(index: max(current - 3, 0), viewport: h) + h) }
                    }
                }
            }
            .ignoresSafeArea(edges: .top)

            // top bar over a soft scrim so the road slides under it
            LinearGradient(colors: [Color(argb: 0x80140A3C), Color(argb: 0x00140A3C)], startPoint: .top, endPoint: .bottom)
                .frame(height: 150)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)
            HStack(spacing: 0) {
                AvatarButton(avatar: avatar) { nav.tab = 4 }
                Spacer().frame(width: 4)
                ResourcePill(.STAR, String(repo.totalStars))
                Spacer(minLength: 0)
                ResourcePill(.COIN, String(repo.coins), onPlus: { nav.tab = 0 })
                Spacer().frame(width: 6)
                IconRoundButton(.GEAR, size: 46, color: .Purple, iconScale: 0.66) { nav.go(.Settings) }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            // side widgets
            HStack(alignment: .center, spacing: 0) {
                VStack(spacing: 10) {
                    SideWidget(icon: .WHEEL, label: "Spin", dot: repo.canSpin, phase: 0) { nav.tab = 1 }
                    SideWidget(icon: .CALENDAR, label: "Daily", dot: !repo.dailyChallengeDone, phase: 0.33) { nav.tab = 1 }
                    SideWidget(icon: .GIFT, label: "Gift", dot: nowMillis() >= repo.freeGiftAt, phase: 0.66) { giftPopup = true }
                }
                .padding(.leading, 10)
                Spacer(minLength: 0)
                VStack(spacing: 10) {
                    let nextChest = ((current - 1) / 10 + 1) * 10
                    SideWidget(icon: .CHEST, label: "Lv.\(nextChest)", dot: false, phase: 0.15) {
                        scrollRequest = max(nextChest - 3, 0)
                    }
                    SideWidget(icon: .PALETTE, label: "Themes", dot: false, phase: 0.5) { nav.tab = 3 }
                }
                .padding(.trailing, 10)
            }
            .frame(maxHeight: .infinity, alignment: .center)

            // play button
            VStack(spacing: 0) {
                let spec = LevelGenerator.get(current)
                if spec.isBoss {
                    Chip("BOSS LEVEL", .Red, fontSize: 15)
                        .idleBounce(amount: 0.08)
                    Spacer().frame(height: 4)
                }
                GameButton("Level \(current)", color: spec.isBoss ? .Red : .Green, height: 72, fontSize: 32, icon: .PLAY, shine: true) {
                    nav.go(.Game(GameRoute(level: current)))
                }
                .frame(width: 250)
                .idleBounce(amount: 0.035)
            }
            .padding(.bottom, 14)
            .frame(maxHeight: .infinity, alignment: .bottom)

            PopupHost(visible: chestPopup >= 0, onDismiss: nil) {
                if shownChest >= 0 { ChestPopupContent(index: shownChest) { chestPopup = -1 }.id(shownChest) }
            }
            if shownLocked > 0 {
                let locked = shownLocked
                WatchAdDialog(
                    visible: lockedLevel > 0,
                    title: "Level \(locked)",
                    message: "This level is locked. Watch a short ad to unlock it now!",
                    placement: .UNLOCK_LEVEL,
                    onUnlocked: { repo.unlockLevelByAd(locked); nav.go(.Game(GameRoute(level: locked))) },
                    onClose: { lockedLevel = -1 }
                ) {
                    ZStack { GameIcon(.LOCK).frame(width: 96, height: 96).idleBounce() }
                }
            }
            FreeGiftPopup(visible: giftPopup) { giftPopup = false }
        }
    }

    @State var scrollRequest: Int? = nil

    /// Compose `scrollToItem(index)` with reverseLayout: item `index`'s bottom edge sits on the bottom content padding.
    private func scroll(_ proxy: ScrollViewProxy, toIndex index: Int, viewport h: CGFloat, animated: Bool) {
        let level = index + 1
        guard h > NodeRowHeight + 130 else { proxy.scrollTo(level, anchor: .bottom); return }
        // item point a·rowH lands on viewport point a·H  ⇒  item bottom at H - 130
        let a = (h - 130 - NodeRowHeight) / (h - NodeRowHeight)
        let anchor = UnitPoint(x: 0.5, y: min(1, max(0, a)))
        if animated {
            withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.45)) { proxy.scrollTo(level, anchor: anchor) }
        } else {
            proxy.scrollTo(level, anchor: anchor)
        }
    }

    /// The 5000 level rows, top = level 5000 (Compose reverseLayout), with the LazyColumn content padding.
    @ViewBuilder
    private func levelRows(current: Int, avatar: Int, adLevels: Set<Int>, opened: Set<Int>) -> some View {
        LazyVStack(spacing: 0) {
            ForEach((1...LevelGenerator.MAX_LEVEL).reversed(), id: \.self) { n in
                let claimable = n % 10 == 0 && n < current && !opened.contains(n / 10)
                LevelNode(
                    n: n, current: current, stars: repo.starsFor(n),
                    chestClaimable: claimable,
                    chestOpened: n % 10 == 0 && opened.contains(n / 10),
                    adUnlocked: n > current && adLevels.contains(n),
                    avatar: avatar,
                    onChest: { shownChest = n / 10; chestPopup = n / 10 }
                ) {
                    if repo.isLevelPlayable(n) { nav.go(.Game(GameRoute(level: n))) }
                    else if Ads.rewarded.isAvailable { shownLocked = n; lockedLevel = n }
                    else { sound.play(.TAP, pitch: 0.7) }
                }
                .frame(height: NodeRowHeight)
                .zIndex(Double(n) + ((n == current || claimable) ? 100_000 : 0))
                .id(n)
            }
        }
        .padding(.top, MapTopPad)
        .padding(.bottom, MapBottomPad)
    }

    /// Content offset that puts item `index` (level index + 1) on the bottom content-padding edge — Compose
    /// `scrollToItem(index)` with reverseLayout.
    private func mapOffset(index: Int, viewport h: CGFloat) -> CGFloat {
        let level = index + 1
        let itemBottom = MapTopPad + CGFloat(LevelGenerator.MAX_LEVEL - level + 1) * NodeRowHeight
        let total = MapTopPad + CGFloat(LevelGenerator.MAX_LEVEL) * NodeRowHeight + MapBottomPad
        return min(max(itemBottom - (h - MapBottomPad), 0), max(total - h, 0))
    }

    /// `centerWorld = themeFor(firstVisibleItemIndex + 3)`; reverse layout: the first visible item sits on the
    /// bottom content-padding edge. `visibleBottom`: bottom of the viewport in content coordinates.
    private func updateWorld(visibleBottom: CGFloat) {
        let refY = visibleBottom - MapBottomPad - 0.5
        let fromTop = Int(((refY - MapTopPad) / NodeRowHeight).rounded(.down))
        let bottomLevel = min(max(LevelGenerator.MAX_LEVEL - fromTop, 1), LevelGenerator.MAX_LEVEL)
        let w = LevelGenerator.themeFor(min(max(bottomLevel + 2, 1), LevelGenerator.MAX_LEVEL))
        if w != centerWorld {
            centerWorld = w
            onWorld(w)
        }
    }
}

/// iOS 18 map scroller: exact content offsets through `ScrollPosition`, live offset through `onScrollGeometryChange`.
@available(iOS 18.0, *)
private struct LevelMapScroll18<Rows: View>: View {
    let viewportH: CGFloat
    @Binding var request: Int?
    let offsetFor: (Int) -> CGFloat
    let onVisibleBottom: (CGFloat) -> Void
    @ViewBuilder let rows: () -> Rows
    @State var pos: ScrollPosition

    init(viewportH: CGFloat, startOffset: CGFloat, request: Binding<Int?>, offsetFor: @escaping (Int) -> CGFloat,
         onVisibleBottom: @escaping (CGFloat) -> Void, @ViewBuilder rows: @escaping () -> Rows) {
        self.viewportH = viewportH
        _request = request
        self.offsetFor = offsetFor
        self.onVisibleBottom = onVisibleBottom
        self.rows = rows
        _pos = State(initialValue: ScrollPosition(y: startOffset))
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            rows()
        }
        .scrollPosition($pos)
        .ignoresSafeArea(edges: .top)
        .onScrollGeometryChange(for: CGFloat.self) { $0.visibleRect.maxY } action: { _, bottom in
            onVisibleBottom(bottom)
        }
        .onChange(of: request) { _, req in
            guard let req else { return }
            withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.45)) { pos.scrollTo(y: offsetFor(req)) }
            request = nil
        }
    }
}

private struct AvatarButton: View {
    let avatar: Int
    let onClick: () -> Void

    var body: some View {
        Canvas { ctx, canvasSize in
            let size = CGSize(width: canvasSize.width, height: canvasSize.height - 3)
            let r = min(size.width, size.height) / 2
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            func circle(_ cc: CGPoint, _ rr: CGFloat) -> Path { Path(ellipseIn: CGRect(x: cc.x - rr, y: cc.y - rr, width: rr * 2, height: rr * 2)) }
            ctx.fill(circle(CGPoint(x: c.x, y: c.y + 3), r), with: .color(Color(argb: 0x40140A3C)))
            ctx.fill(circle(c, r), with: .linearGradient(Gradient(colors: [Color(argb: 0xFFFFF0A0), Color(argb: 0xFFFFA81A)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            ctx.fill(circle(c, r - 4), with: .linearGradient(Gradient(colors: [Color(argb: 0xFF9775FF), Color(argb: 0xFF4521C2)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            ball(ctx, c, r * 0.62, avatar, 6)
            ctx.stroke(circle(c, r), with: .color(Color(argb: 0xFF8A4A00)), lineWidth: 1.8)
        }
        .padding(.bottom, -3)
        .frame(width: 46, height: 46)
        .contentShape(Rectangle())
        .onTapGesture(perform: onClick)
    }
}

private struct SideWidget: View {
    let icon: Ico
    let label: String
    let dot: Bool
    let phase: Float
    let onClick: () -> Void
    @Environment(SoundManager.self) private var sound

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Canvas { ctx, canvasSize in
                    let size = CGSize(width: canvasSize.width, height: canvasSize.height - 4)
                    let r = min(size.width, size.height) / 2
                    let c = CGPoint(x: r, y: r)
                    func circle(_ cc: CGPoint, _ rr: CGFloat) -> Path { Path(ellipseIn: CGRect(x: cc.x - rr, y: cc.y - rr, width: rr * 2, height: rr * 2)) }
                    ctx.fill(circle(CGPoint(x: c.x, y: c.y + 4), r), with: .color(Color(argb: 0x47140A3C)))
                    ctx.fill(circle(c, r), with: .linearGradient(Gradient(colors: [.white, Color(argb: 0xFFC9B8FF)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                    ctx.fill(circle(c, r - 3), with: .linearGradient(Gradient(colors: [.white, Color(argb: 0xFFE3D8FF)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                    ctx.fill(circle(CGPoint(x: c.x, y: c.y + r * 0.35), r - 3), with: .color(Color(argb: 0x1F4521C2)))
                    ctx.fill(Path(ellipseIn: CGRect(x: r * 0.42, y: r * 0.15, width: r * 1.16, height: r * 0.6)),
                             with: .linearGradient(Gradient(colors: [.white.opacity(0.9), .white.opacity(0)]), startPoint: CGPoint(x: 0, y: r * 0.15), endPoint: CGPoint(x: 0, y: r * 0.8)))
                    ctx.stroke(circle(c, r), with: .color(GameColors.Purple800), lineWidth: 2.5)
                }
                .padding(.bottom, -4)
                FrameClock(paused: !dot) { t in
                    let k = loopPhase(t, 1600)
                    GameIcon(icon)
                        .frame(width: 40, height: 40)
                        .rotationEffect(.degrees(dot && k < 0.35 ? Double(sin(k / 0.35 * 4 * .pi) * 10) : 0))
                }
            }
            .frame(width: 58, height: 58)
            .overlay(alignment: .topTrailing) {
                if dot { NotifyBadge().offset(x: 2, y: -1) }
            }
            OutlinedText(label, fontSize: 12, shadow: false, maxLines: 1)
                .padding(.horizontal, 8)
                .padding(.vertical, 1)
                .background(Capsule().fill(Color(argb: 0xCC1A0B4A)))
                .offset(y: -7)
        }
        .floaty(amplitude: 3, periodMs: 2800, phase: phase)
        .contentShape(Rectangle())
        .onTapGesture { sound.play(.BUTTON); onClick() }
    }
}

private struct LevelNode: View {
    let n: Int
    let current: Int
    let stars: Int
    let chestClaimable: Bool
    let chestOpened: Bool
    let adUnlocked: Bool
    let avatar: Int
    let onChest: () -> Void
    let onClick: () -> Void

    var body: some View {
        // 0 done, 1 current, 2 locked, 3 unlocked early by an ad
        let state = n < current ? 0 : (n == current ? 1 : (adUnlocked ? 3 : 2))
        let boss = LevelGenerator.isBoss(n)
        let world = LevelGenerator.themeFor(n)
        let worldStart = (n - 1) % 25 == 0
        let hasChest = n % 10 == 0
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let x = w * nodeX(n)
            let size: CGFloat = state == 1 ? 84 : (boss ? 74 : 64)
            let side = CGFloat(scenerySide(n))
            let ext: CGFloat = 40
            ZStack {
                Canvas { ctx, sz in
                    let row = CGSize(width: w, height: h)
                    var road = ctx
                    road.translateBy(x: 0, y: ext)
                    road.clip(to: Path(CGRect(origin: .zero, size: row)))
                    if n > 1 {
                        var prev = road
                        prev.translateBy(x: 0, y: h)
                        drawRoad(prev, row, n - 1, current)
                    }
                    drawRoad(road, row, n, current)
                    if !worldStart && !hasChest {
                        var sc = ctx
                        sc.translateBy(x: 0, y: ext)
                        drawScenery(sc, row, n, world)
                    }
                }
                .frame(width: w, height: h + ext)
                .offset(y: -ext / 2)
                .allowsHitTesting(false)

                if worldStart {
                    WorldSign(n: n, world: world).offset(x: w * 0.3 * side)
                }
                if hasChest {
                    ChestSpot(claimable: chestClaimable, opened: chestOpened, reached: n < current, onClick: onChest)
                        .offset(x: x + 92 * side)
                }
                if state == 1 {
                    FrameClock { t in
                        let p = loopPhase(t, 1600)
                        ZStack {
                            CurrentNodeFx(t: p, size: size)
                            NodeBody(n: n, state: state, boss: boss, size: size, onClick: onClick)
                                .scaleEffect(1 + 0.05 * sin(p * 2 * .pi))
                            PlayerPin(t: p, avatar: avatar).offset(y: -size / 2 - 19)
                        }
                        .offset(x: x)
                    }
                } else {
                    NodeBody(n: n, state: state, boss: boss, size: size, onClick: onClick).offset(x: x)
                }
                if boss && state != 0 {
                    GameIcon(.CROWN).frame(width: size * 0.5, height: size * 0.5).offset(x: x, y: -size * 0.62).allowsHitTesting(false)
                }
                if state == 0 {
                    StarRow(stars, size: 19).offset(x: x, y: size * 0.58).allowsHitTesting(false)
                }
            }
            .frame(width: w, height: h)
        }
    }
}

private struct NodeBody: View {
    let n: Int
    let state: Int
    let boss: Bool
    let size: CGFloat
    let onClick: () -> Void

    var body: some View {
        ZStack {
            if state == 2 {
                GameIcon(.LOCK).frame(width: size * 0.46, height: size * 0.46).offset(y: -2)
            } else {
                OutlinedText(String(n), fontSize: n >= 1000 ? 19 : (state == 1 ? 30 : 24), outline: nodeOutline(state, boss), maxLines: 1)
                    .offset(y: -2)
            }
        }
        .frame(width: size, height: size)
        .background(alignment: .top) {
            Canvas { ctx, _ in drawNodeDisc(ctx, size, state, boss) }
                .frame(width: size, height: size * 1.2)
                .allowsHitTesting(false)
        }
        .contentShape(Circle())
        .onTapGesture(perform: onClick)
    }
}

/// Ping rings + glow around the current node.
private struct CurrentNodeFx: View {
    let t: CGFloat
    let size: CGFloat

    var body: some View {
        Canvas { ctx, sz in
            let r = size / 2
            let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
            func circle(_ rr: CGFloat) -> Path { Path(ellipseIn: CGRect(x: c.x - rr, y: c.y - rr, width: rr * 2, height: rr * 2)) }
            ctx.fill(circle(r * 1.9), with: .radialGradient(Gradient(colors: [Color(argb: 0x80FF9AD5), Color(argb: 0x00FF9AD5)]), center: c, startRadius: 0, endRadius: r * 1.9))
            for k in 0..<2 {
                let p = (t + CGFloat(k) * 0.5).truncatingRemainder(dividingBy: 1)
                ctx.stroke(circle(r * (1.05 + p * 0.75)), with: .color(.white.opacity(Double((1 - p) * 0.7))), lineWidth: 3 * (1 - p) + 1)
            }
        }
        .frame(width: size * 2.4, height: size * 2.4)
        .allowsHitTesting(false)
    }
}

/// The player's avatar in a map pin, bobbing on top of the current node.
private struct PlayerPin: View {
    let t: CGFloat
    let avatar: Int

    var body: some View {
        Canvas { ctx, size in
            let r = size.width / 2
            var pin = Path(ellipseIn: CGRect(x: 0, y: 0, width: r * 2, height: r * 2))
            pin.move(to: CGPoint(x: r * 0.45, y: r * 1.6))
            pin.addLine(to: CGPoint(x: r, y: size.height))
            pin.addLine(to: CGPoint(x: r * 1.55, y: r * 1.6))
            pin.closeSubpath()
            ctx.fill(pin, with: .color(Color(argb: 0x40140A3C)))
            ctx.fill(pin, with: .color(.white))
            ctx.stroke(pin, with: .color(GameColors.Ink), lineWidth: 2)
            ball(ctx, CGPoint(x: r, y: r), r * 0.7, avatar, 6)
        }
        .frame(width: 40, height: 50)
        .offset(y: sin(t * 2 * .pi) * 4)
        .allowsHitTesting(false)
    }
}

private struct WorldSign: View {
    let n: Int
    let world: Int

    var body: some View {
        let color: BtnColor = {
            switch Kt.mod(world, 5) { case 0: return .Purple; case 1: return .Blue; case 2: return .Purple; case 3: return .Orange; default: return .Green }
        }()
        let raw = Themes.get(world).name
        let name = raw == "Lava" ? "Sunset" : raw
        VStack(spacing: 0) {
            Chip("WORLD \((n - 1) / 25 + 1)", color, fontSize: 13)
            Spacer().frame(height: 3)
            OutlinedText(name, fontSize: 20, brush: Grad.Snow, maxLines: 1)
        }
        .fixedSize()
        .allowsHitTesting(false)
    }
}

private struct ChestSpot: View {
    let claimable: Bool
    let opened: Bool
    let reached: Bool
    let onClick: () -> Void

    var body: some View {
        ZStack {
            if claimable {
                SunRays(color: Color(argb: 0xFFFFF3B0), alpha: 0.35, rays: 12, degPerSec: 30)
                    .frame(width: 130, height: 130)
                    .allowsHitTesting(false)
            }
            Canvas { ctx, size in
                ctx.fill(Path(ellipseIn: CGRect(x: size.width * 0.12, y: size.height * 0.72, width: size.width * 0.76, height: size.height * 0.2)),
                         with: .color(Color(argb: 0x40140A3C)))
            }
            FrameClock(paused: !claimable) { t in
                let k = loopPhase(t, 1400)
                GameIcon(.CHEST)
                    .frame(width: 54, height: 54)
                    .rotationEffect(.degrees(claimable && k < 0.4 ? Double(sin(k / 0.4 * 6 * .pi) * 8) : 0))
                    .scaleEffect(claimable ? 1 + 0.06 * sin(k * 2 * .pi) : 1)
                    .opacity(claimable ? 1 : (opened ? 0.45 : (reached ? 0.75 : 0.92)))
            }
            if opened {
                GameIcon(.CHECK, tint: GameColors.Green)
                    .frame(width: 24, height: 24)
                    .frame(width: 70, height: 70, alignment: .bottomTrailing)
            }
        }
        .frame(width: 70, height: 70)
        .contentShape(Rectangle())
        .onTapGesture { if claimable { onClick() } }
    }
}

private struct ChestPopupContent: View {
    let index: Int
    let onClose: () -> Void
    @Environment(GameRepository.self) private var repo
    @Environment(SoundManager.self) private var sound
    @State var opened = false

    var body: some View {
        let coins = 100 + index * 10
        let booster = Booster.entries[index % Booster.entries.count]
        ZStack {
            GamePanel(opened ? "Rewards!" : "Treasure", ribbon: .Yellow, rays: true) {
                if !opened {
                    FrameClock { t in
                        let k = loopPhase(t, 900)
                        GameIcon(.CHEST)
                            .frame(width: 150, height: 150)
                            .rotationEffect(.degrees(k < 0.45 ? Double(sin(k / 0.45 * 6 * .pi) * 7) : 0))
                    }
                    .frame(width: 150, height: 150)
                    Spacer().frame(height: 4)
                    PopupBodyText("You reached a treasure chest!")
                    Spacer().frame(height: 14)
                    GameButton("Open", color: .Green, shine: true) {
                        repo.openChest(index); repo.addCoins(coins); repo.addBooster(booster, 1)
                        sound.play(.REWARD); opened = true
                    }
                    .frame(maxWidth: .infinity)
                    .idleBounce()
                } else {
                    HStack(alignment: .center, spacing: 18) {
                        RewardTile(icon: .COIN, text: "+\(coins)", index: 0)
                        RewardTile(icon: boosterIcon(booster), text: "+1", index: 1)
                    }
                    Spacer().frame(height: 16)
                    GameButton("Awesome!", color: .Green) { onClose() }
                        .frame(maxWidth: .infinity)
                }
            }
            if opened { ConfettiBurst().allowsHitTesting(false) }
        }
    }
}

/// Reward tile that pops in (staggered by [index]).
struct RewardTile: View {
    let icon: Ico
    let text: String
    var index: Int = 0
    @State var a: CGFloat = 0

    init(icon: Ico, text: String, index: Int = 0) {
        self.icon = icon
        self.text = text
        self.index = index
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Canvas { ctx, canvasSize in
                    let size = CGSize(width: canvasSize.width, height: canvasSize.height - 4)
                    let r: CGFloat = 24
                    let rect = CGRect(origin: .zero, size: size)
                    ctx.fill(Path(roundedRect: rect.offsetBy(dx: 0, dy: 4), cornerRadius: r), with: .color(Color(argb: 0xFFB9A3FF)))
                    ctx.fill(Path(roundedRect: rect, cornerRadius: r), with: .linearGradient(Gradient(colors: [Color(argb: 0xFFFFFFFF), Color(argb: 0xFFE6DCFF)]),
                                                                                           startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
                    let c = CGPoint(x: size.width / 2, y: size.height / 2)
                    ctx.fill(Path(roundedRect: rect, cornerRadius: r), with: .radialGradient(Gradient(colors: [Color(argb: 0x66FFE680), Color(argb: 0x00FFE680)]),
                                                                                           center: c, startRadius: 0, endRadius: min(size.width, size.height) * 0.6))
                    ctx.stroke(Path(roundedRect: rect, cornerRadius: r), with: .color(GameColors.Purple800), lineWidth: 2.5)
                }
                .padding(.bottom, -4)
                GameIcon(icon).frame(width: 62, height: 62).idleBounce()
            }
            .frame(width: 92, height: 92)
            OutlinedText(text, fontSize: 26, brush: Grad.Gold, gloss: true)
        }
        .modifier(PopFX(v: a))
        .onAppear {
            withAnimation(.compose(dampingRatio: 0.45, stiffness: 420).delay(0.09 * Double(index))) { a = 1 }
        }
    }
}

func boosterIcon(_ b: Booster) -> Ico {
    switch b {
    case .HAMMER: return .HAMMER
    case .MAGNET: return .MAGNET
    case .SLOTS: return .SLOTS
    case .SHUFFLE: return .SHUFFLE
    }
}

struct FreeGiftPopup: View {
    let visible: Bool
    let onClose: () -> Void
    @Environment(GameRepository.self) private var repo
    @Environment(SoundManager.self) private var sound
    @State var now: Int64 = nowMillis()

    init(visible: Bool, onClose: @escaping () -> Void) {
        self.visible = visible
        self.onClose = onClose
    }

    var body: some View {
        PopupHost(visible: visible, onDismiss: onClose) {
            let ready = now >= repo.freeGiftAt
            GamePanel("Free Gift", ribbon: .Pink, onClose: onClose, rays: ready) {
                GameIcon(.GIFT).frame(width: 120, height: 120).idleBounce(enabled: ready, amount: 0.08)
                Spacer().frame(height: 8)
                if ready {
                    PopupBodyText("A gift of 100 coins is waiting for you!")
                    Spacer().frame(height: 14)
                    GameButton("Claim 100", color: .Green, icon: .COIN, shine: true) {
                        if repo.claimFreeGift(nowMillis()) { sound.play(.REWARD) }
                        onClose()
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    let mins = max((repo.freeGiftAt - now) / 60000, 1)
                    PopupBodyText("Next gift in \(mins / 60)h \(mins % 60)m")
                    Spacer().frame(height: 14)
                    GameButton("OK", color: .Purple) { onClose() }
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .onChange(of: visible) { _, v in if v { now = nowMillis() } }
    }
}

struct MarbleCluster: View {
    var skin: Int = 0
    init(skin: Int = 0) { self.skin = skin }

    var body: some View {
        Canvas { ctx, size in
            let r = min(size.width, size.height) * 0.22
            ball(ctx, CGPoint(x: size.width * 0.3, y: size.height * 0.62), r, 2, skin)
            ball(ctx, CGPoint(x: size.width * 0.7, y: size.height * 0.64), r * 0.95, 6, skin)
            ball(ctx, CGPoint(x: size.width * 0.5, y: size.height * 0.32), r, 1, skin)
        }
    }
}
