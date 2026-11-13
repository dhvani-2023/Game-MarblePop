import SwiftUI
import GameKit

/// Arguments of `Screen.Game` (Kotlin `data class Game(level, daily = false, nonce = 0)`).
struct GameRoute: Hashable {
    let level: Int
    var daily: Bool = false
    var nonce: Int = 0

    func copy(nonce: Int) -> GameRoute { GameRoute(level: level, daily: daily, nonce: nonce) }
}

enum Screen: Hashable {
    case Splash
    case Onboarding
    case Main
    case Game(GameRoute)
    case Settings
    case Legal(page: String)

    /// Kotlin `nav.screen::class`: one value per screen type.
    var kind: Int {
        switch self {
        case .Splash: return 0
        case .Onboarding: return 1
        case .Main: return 2
        case .Game: return 3
        case .Settings: return 4
        case .Legal: return 5
        }
    }

    var isGame: Bool { if case .Game = self { return true } else { return false } }
}

@MainActor
@Observable
final class Nav {
    var screen: Screen = .Splash
    var tab: Int = 2
    /// Direction of the last navigation, used to pick push vs. pop animations.
    private(set) var forward = true
    @ObservationIgnored private var stack: [Screen] = []

    func go(_ s: Screen) { forward = true; stack.append(screen); screen = s }
    func replace(_ s: Screen) { forward = true; screen = s }
    @discardableResult
    func back() -> Bool {
        guard let last = stack.popLast() else { return false }
        forward = false
        screen = last
        return true
    }
    func home() { forward = false; stack.removeAll(); screen = .Main }
}

// MARK: - Compose-style transitions

/// Compose `CubicBezierEasing` (x1, y1, x2, y2); `tween()` defaults to FastOutSlowIn.
struct ComposeEasing {
    let x1: Double, y1: Double, x2: Double, y2: Double

    init(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
        self.x1 = x1; self.y1 = y1; self.x2 = x2; self.y2 = y2
    }

    static let fastOutSlowIn = ComposeEasing(0.4, 0, 0.2, 1)
    static let linear = ComposeEasing(0, 0, 1, 1)
    /// Motion.EaseIn: decelerate, for entering elements.
    static let enter = ComposeEasing(0.05, 0.7, 0.1, 1)
    /// Motion.EaseOut: accelerate, for leaving elements.
    static let exit = ComposeEasing(0.3, 0, 0.8, 0.15)

    private func bez(_ t: Double, _ p1: Double, _ p2: Double) -> Double {
        let u = 1 - t
        return 3 * u * u * t * p1 + 3 * u * t * t * p2 + t * t * t
    }

    func callAsFunction(_ fraction: Double) -> Double {
        let x = min(1, max(0, fraction))
        if x <= 0 { return 0 }
        if x >= 1 { return 1 }
        if x1 == y1 && x2 == y2 { return x }
        // bisection on x(t) (monotonic for 0 <= x1, x2 <= 1)
        var lo = 0.0, hi = 1.0, t = x
        for _ in 0..<40 {
            let v = bez(t, x1, x2)
            if abs(v - x) < 1e-7 { break }
            if v < x { lo = t } else { hi = t }
            t = (lo + hi) / 2
        }
        return bez(t, y1, y2)
    }
}

/// Compose `tween(durationMillis, delayMillis, easing)`.
struct Tween {
    var duration: Double
    var delay: Double = 0
    var easing: ComposeEasing = .fastOutSlowIn

    /// Eased progress at `ms` milliseconds after the transition started.
    func value(_ ms: Double) -> Double {
        if duration <= 0 { return ms >= delay ? 1 : 0 }
        return easing((ms - delay) / duration)
    }
    var end: Double { delay + duration }
}

/// One side (enter or exit) of a Compose `ContentTransform`. Slide offsets are fractions of the width.
struct ScreenMotion {
    var fade: Tween? = nil
    var scale: Tween? = nil
    var scaleValue: CGFloat = 1     // initialScale (enter) / targetScale (exit)
    var slide: Tween? = nil
    var slideFraction: CGFloat = 0  // initial offset (enter) / target offset (exit), × width

    var end: Double { max(fade?.end ?? 0, scale?.end ?? 0, slide?.end ?? 0) }
}

struct ContentTransformSpec {
    var enter: ScreenMotion
    var exit: ScreenMotion
    /// Kotlin `targetContentZIndex`: true = the incoming content draws above the outgoing one.
    var incomingOnTop: Bool = true

    var total: Double { max(enter.end, exit.end) }
}

struct SwitchEntry<Key: Hashable>: Identifiable {
    let id: Int
    let key: Key
}

/// Compose `AnimatedContent`: keeps the outgoing content alive while both animate with tween clocks,
/// then drops it. Every change of `target` creates fresh content (Compose `contentKey`).
struct AnimatedSwitcher<Key: Hashable, Content: View>: View {
    let target: Key
    let spec: (_ from: Key, _ to: Key) -> ContentTransformSpec
    @ViewBuilder let content: (Key) -> Content

    @State var entries: [SwitchEntry<Key>] = []
    @State var outgoingId: Int? = nil
    @State var active: ContentTransformSpec? = nil
    @State var start: Date = .distantPast
    @State var counter = 0

    init(target: Key, spec: @escaping (_ from: Key, _ to: Key) -> ContentTransformSpec, @ViewBuilder content: @escaping (Key) -> Content) {
        self.target = target
        self.spec = spec
        self.content = content
        // first content is present from the very first frame (no blank frame after the launch screen)
        _entries = State(initialValue: [SwitchEntry(id: 1, key: target)])
        _counter = State(initialValue: 1)
    }

    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: nil, paused: active == nil)) { tl in
                let ms = active == nil ? 0 : max(0, tl.date.timeIntervalSince(start) * 1000)
                ZStack {
                    ForEach(entries) { e in
                        let incoming = e.id != outgoingId
                        content(e.key)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .modifier(SwitchFX(motion: active.map { incoming ? $0.enter : $0.exit },
                                               incoming: incoming, ms: ms, width: geo.size.width))
                            .zIndex(zIndex(incoming))
                            .allowsHitTesting(incoming)
                    }
                }
            }
        }
        .onChange(of: target) { _, new in switchTo(new) }
    }

    private func zIndex(_ incoming: Bool) -> Double {
        guard let a = active else { return 0 }
        return (incoming == a.incomingOnTop) ? 1 : 0
    }

    private func switchTo(_ new: Key) {
        guard let cur = entries.last(where: { $0.id != outgoingId }) ?? entries.last else {
            counter += 1; entries = [SwitchEntry(id: counter, key: new)]; return
        }
        let s = spec(cur.key, new)
        counter += 1
        let entry = SwitchEntry(id: counter, key: new)
        entries = [cur, entry]
        outgoingId = cur.id
        active = s
        start = Date()
        let myId = counter
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64((s.total + 20) * 1_000_000))
            guard counter == myId else { return }
            entries = entries.filter { $0.id == myId }
            outgoingId = nil
            active = nil
        }
    }
}

private struct SwitchFX: ViewModifier {
    let motion: ScreenMotion?
    let incoming: Bool
    let ms: Double
    let width: CGFloat

    func body(content: Content) -> some View {
        var alpha = 1.0
        var scale: CGFloat = 1
        var dx: CGFloat = 0
        if let m = motion {
            if let f = m.fade { let e = f.value(ms); alpha = incoming ? e : 1 - e }
            if let s = m.scale {
                let e = CGFloat(s.value(ms))
                scale = incoming ? m.scaleValue + (1 - m.scaleValue) * e : 1 + (m.scaleValue - 1) * e
            }
            if let s = m.slide {
                let e = CGFloat(s.value(ms))
                dx = incoming ? m.slideFraction * width * (1 - e) : m.slideFraction * width * e
            }
        }
        return content
            .scaleEffect(scale)
            .offset(x: dx)
            .opacity(alpha)
    }
}

// MARK: - App root


/// Screen-to-screen motion (UI_GRAPHICS_PLAN.md §4).
private func screenTransition(_ from: Screen, _ to: Screen, _ forward: Bool) -> ContentTransformSpec {
    let easeIn = ComposeEasing.enter
    let easeOut = ComposeEasing.exit
    var t: ContentTransformSpec
    if case .Splash = from {
        t = ContentTransformSpec(
            enter: ScreenMotion(fade: Tween(duration: 420, easing: easeIn), scale: Tween(duration: 520, easing: easeIn), scaleValue: 1.06),
            exit: ScreenMotion(fade: Tween(duration: 320)))
    } else if from.isGame && to.isGame {
        t = ContentTransformSpec(
            enter: ScreenMotion(fade: Tween(duration: 260, delay: 60)),
            exit: ScreenMotion(fade: Tween(duration: 200)))
    } else if to.isGame {
        t = ContentTransformSpec(
            enter: ScreenMotion(fade: Tween(duration: 300, delay: 80), scale: Tween(duration: 420, easing: easeIn), scaleValue: 0.9),
            exit: ScreenMotion(fade: Tween(duration: 240), scale: Tween(duration: 380, easing: easeOut), scaleValue: 1.1))
    } else if from.isGame {
        t = ContentTransformSpec(
            enter: ScreenMotion(fade: Tween(duration: 300, delay: 60), scale: Tween(duration: 420, easing: easeIn), scaleValue: 1.1),
            exit: ScreenMotion(fade: Tween(duration: 240), scale: Tween(duration: 360, easing: easeOut), scaleValue: 0.9))
    } else if forward {
        t = ContentTransformSpec(
            enter: ScreenMotion(fade: Tween(duration: 200), slide: Tween(duration: 420, easing: easeIn), slideFraction: 1),
            exit: ScreenMotion(fade: Tween(duration: 300), slide: Tween(duration: 420, easing: easeIn), slideFraction: -0.25))
    } else {
        t = ContentTransformSpec(
            enter: ScreenMotion(fade: Tween(duration: 300), slide: Tween(duration: 420, easing: easeIn), slideFraction: -0.25),
            exit: ScreenMotion(fade: Tween(duration: 300), slide: Tween(duration: 300, easing: easeOut), slideFraction: 1))
    }
    // the popped screen slides away on top of the one revealed underneath it
    if case .Splash = from { t.incomingOnTop = true } else { t.incomingOnTop = forward }
    return t
}

/// Port of `MarbleApp`: navigator, screen transitions and music per screen type.
struct MarbleApp: View {
    let repo: GameRepository
    let sound: SoundManager
    @State var nav = Nav()

    var body: some View {
        let nav = self.nav
        ZStack {
            Color(argb: 0xFF2A1463).ignoresSafeArea()
            // Each screen lays out inside the safe area and extends its own backdrop under the bars.
            AnimatedSwitcher(target: nav.screen, spec: { from, to in screenTransition(from, to, nav.forward) }) { s in
                screenView(s)
            }
            // debug-only fake rewarded ad on Android; renders nothing on iOS (no fake ads)
            DebugAdOverlay()
        }
        .environment(repo)
        .environment(sound)
        .onChange(of: nav.screen.kind, initial: true) { _, _ in
            switch nav.screen {
            case .Game: sound.playMusic(.GAME)
            case .Splash: break
            default: sound.playMusic(.HOME)
            }
        }
    }

    @ViewBuilder
    private func screenView(_ s: Screen) -> some View {
        switch s {
        case .Splash:
            SplashScreen { nav.replace(repo.onboardingDone ? .Main : .Onboarding) }
        case .Onboarding:
            OnboardingScreen { repo.finishOnboarding(); nav.replace(.Main) }
        case .Main:
            MainScreen(nav: nav)
        case .Game(let route):
            GameScreen(screen: route, nav: nav)
        case .Settings:
            SettingsScreen(nav: nav)
        case .Legal(let page):
            LegalScreen(page: page) { nav.back() }
        }
    }
}
