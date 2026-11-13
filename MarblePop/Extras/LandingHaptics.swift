import Foundation
import QuartzCore
import GameKit
#if canImport(CoreHaptics)
import CoreHaptics
#endif

// Extra 2 (Features.landingHaptics): Core Haptics synced to the tray. The engine is untouched: after every update
// the game session hands its counters (marblesSorted, cupsFilled, combo, status) to LandingHaptics, and the
// engine's own cup-filled / win haptics are swapped for the richer ones below while this extra can play.

/// One haptic to play this frame.
enum LandingHapticCue: Equatable {
    /// A marble dropped into a cup; `level` = the live combo (0 when no combo chain is running), at most 6.
    case landing(level: Int)
    /// A cup filled up; `combo` = the engine's combo count for it (1 ... 6).
    case cupFilled(combo: Int)
    case win
}

/// Pure decision logic: turns one frame of engine counters into at most one cue.
/// Priority win > filled cup > landing. A landing keeps a 40 ms gap to the previous transient, so landings never
/// exceed 25 per second; a filled cup always plays (it is the event the player waits for).
struct LandingHapticPlanner {
    static let MIN_GAP: Double = 0.04
    /// GameEngine.completeCup's combo window (`time - lastCupTime < 1.5`).
    static let COMBO_WINDOW: Float = 1.5
    static let MAX_LEVEL = 6

    private var lastSorted: Int
    private var lastCups: Int
    private var cupsSeenByHaptic: Int
    private var won = false
    private var lastTransient = -Double.infinity
    private var lastCupTime: Float = -100

    init(sorted: Int = 0, cups: Int = 0) {
        lastSorted = sorted
        lastCups = cups
        cupsSeenByHaptic = cups
    }

    /// After `engine.update`: `now` = wall-clock seconds (the throttle is real time), `engineTime` = engine.time.
    mutating func step(now: Double, engineTime: Float, sorted: Int, cups: Int, combo: Int, won isWon: Bool) -> LandingHapticCue? {
        let landed = sorted > lastSorted
        let filled = cups > lastCups
        lastSorted = sorted
        lastCups = cups
        if filled { lastCupTime = engineTime }
        let newWin = isWon && !won
        won = isWon
        if newWin {
            lastTransient = now
            return .win
        }
        if filled {
            lastTransient = now
            return .cupFilled(combo: min(max(combo, 1), Self.MAX_LEVEL))
        }
        if landed && now - lastTransient >= Self.MIN_GAP {
            lastTransient = now
            let live = engineTime - lastCupTime < Self.COMBO_WINDOW ? combo : 0
            return .landing(level: min(max(live, 0), Self.MAX_LEVEL))
        }
        return nil
    }

    /// The engine's own `haptic(kind)` call as the session listener sees it: true for the two haptics this extra
    /// replaces, the LIGHT tap GameEngine.completeCup fires right after `cupsFilled += 1`, and the win SUCCESS.
    /// Other LIGHT taps (blocked block, machine landing, belt warning) and MEDIUM / HEAVY stay as on Android.
    mutating func replaces(_ kind: Haptic, cupsFilled: Int) -> Bool {
        switch kind {
        case .SUCCESS:
            return true
        case .LIGHT:
            let cup = cupsFilled != cupsSeenByHaptic
            cupsSeenByHaptic = cupsFilled
            return cup
        default:
            return false
        }
    }

    /// Landing transient: soft and round, firmer and crisper as the combo grows.
    static func landing(_ level: Int) -> (intensity: Float, sharpness: Float) {
        let k = Float(min(max(level, 0), MAX_LEVEL))
        return (0.32 + 0.07 * k, 0.28 + 0.06 * k)
    }

    /// Filled-cup tap: always firmer than any landing.
    static func cupFilled(_ combo: Int) -> (intensity: Float, sharpness: Float) {
        let k = Float(min(max(combo, 1), MAX_LEVEL) - 1)
        return (0.8 + 0.04 * k, 0.55 + 0.05 * k)
    }
}

/// Per game session: feeds the planner from the engine and plays its cues.
@MainActor
final class LandingHaptics {
    private let repo: GameRepository
    private var planner = LandingHapticPlanner()

    init(repo: GameRepository) { self.repo = repo }

    /// The extra plays when it is compiled in, Vibration is on and the phone has a Taptic Engine; otherwise the
    /// Android haptics stay exactly as they were.
    nonisolated static func isOn(flag: Bool, vibration: Bool, supported: Bool) -> Bool { flag && vibration && supported }

    var isOn: Bool {
        LandingHaptics.isOn(flag: Features.landingHaptics, vibration: repo.hapticsOn && Haptics.enabled,
                            supported: LandingHapticOutput.shared.supported)
    }

    func begin(_ engine: GameEngine) {
        planner = LandingHapticPlanner(sorted: engine.marblesSorted, cups: engine.cupsFilled)
        if isOn { LandingHapticOutput.shared.prepare() }
    }

    /// From the engine listener: true when the engine's own haptic is replaced by this extra (then skip it).
    func replaces(_ kind: Haptic, _ engine: GameEngine) -> Bool {
        let replaced = planner.replaces(kind, cupsFilled: engine.cupsFilled)
        return replaced && isOn
    }

    /// After every `engine.update`.
    func afterUpdate(_ engine: GameEngine) {
        let cue = planner.step(now: CACurrentMediaTime(), engineTime: engine.time, sorted: engine.marblesSorted,
                               cups: engine.cupsFilled, combo: engine.combo, won: engine.status == .WON)
        if let cue, isOn { LandingHapticOutput.shared.play(cue) }
    }
}

/// Core Haptics output. Every cue has a pre-built player (7 landing levels, 6 cup levels, the win pattern), so a
/// landing costs one `start` call and no allocation. The engine shuts itself down when idle (menus) and is
/// restarted on demand; players are rebuilt after a server reset.
@MainActor
final class LandingHapticOutput {
    static let shared = LandingHapticOutput()

    let supported: Bool
    #if canImport(CoreHaptics)
    private var engine: CHHapticEngine?
    private var landing: [CHHapticPatternPlayer?] = []
    private var cup: [CHHapticPatternPlayer?] = []
    private var win: CHHapticPatternPlayer?
    #endif
    private var running = false

    private init() {
        #if canImport(CoreHaptics)
        supported = CHHapticEngine.capabilitiesForHardware().supportsHaptics
        #else
        supported = false
        #endif
    }

    /// Creates the engine and its players and starts it in the background (call before the first cue).
    func prepare() {
        #if canImport(CoreHaptics)
        guard supported else { return }
        if engine == nil { makeEngine() }
        guard let engine, !running else { return }
        running = true
        engine.start { error in
            if error != nil { Task { @MainActor in LandingHapticOutput.shared.running = false } }
        }
        #endif
    }

    func play(_ cue: LandingHapticCue) {
        #if canImport(CoreHaptics)
        guard supported else { return }
        if engine == nil || !running { startNow() }
        let player: CHHapticPatternPlayer?
        switch cue {
        case .landing(let level): player = landing.indices.contains(level) ? landing[level] : nil
        case .cupFilled(let combo): player = cup.indices.contains(combo - 1) ? cup[combo - 1] : nil
        case .win: player = win
        }
        guard let player else { return }
        do {
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            // stopped behind our back (background, audio interruption): restart once and retry
            running = false
            startNow()
            try? player.start(atTime: CHHapticTimeImmediate)
        }
        #endif
    }

    #if canImport(CoreHaptics)
    private func startNow() {
        if engine == nil { makeEngine() }
        guard let engine else { return }
        do {
            try engine.start()
            running = true
        } catch {
            running = false
        }
    }

    private func makeEngine() {
        guard let e = try? CHHapticEngine() else { return }
        e.playsHapticsOnly = true
        e.isAutoShutdownEnabled = true
        e.stoppedHandler = { _ in
            Task { @MainActor in LandingHapticOutput.shared.running = false }
        }
        e.resetHandler = {
            Task { @MainActor in
                let out = LandingHapticOutput.shared
                out.running = false
                out.makePlayers()
                out.startNow()
            }
        }
        engine = e
        makePlayers()
    }

    private func makePlayers() {
        guard let engine else { return }
        landing = (0...LandingHapticPlanner.MAX_LEVEL).map { level in
            let v = LandingHapticPlanner.landing(level)
            return LandingHapticOutput.player(engine, [LandingHapticOutput.transient(0, v.intensity, v.sharpness)])
        }
        cup = (1...LandingHapticPlanner.MAX_LEVEL).map { combo in
            let v = LandingHapticPlanner.cupFilled(combo)
            return LandingHapticOutput.player(engine, [LandingHapticOutput.transient(0, v.intensity, v.sharpness)])
        }
        win = LandingHapticOutput.winPlayer(engine)
    }

    private static func transient(_ t: TimeInterval, _ intensity: Float, _ sharpness: Float) -> CHHapticEvent {
        CHHapticEvent(eventType: .hapticTransient, parameters: [
            CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
            CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
        ], relativeTime: t)
    }

    private static func player(_ engine: CHHapticEngine, _ events: [CHHapticEvent]) -> CHHapticPatternPlayer? {
        guard let pattern = try? CHHapticPattern(events: events, parameters: []) else { return nil }
        return try? engine.makePlayer(with: pattern)
    }

    /// Win: three rising taps ("ta-da-DA") over a short swell that fades out.
    private static func winPlayer(_ engine: CHHapticEngine) -> CHHapticPatternPlayer? {
        let events = [
            transient(0, 0.55, 0.45),
            transient(0.1, 0.75, 0.55),
            transient(0.22, 1, 0.7),
            CHHapticEvent(eventType: .hapticContinuous, parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.6),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.25),
            ], relativeTime: 0.22, duration: 0.42),
        ]
        let fade = CHHapticParameterCurve(parameterID: .hapticIntensityControl, controlPoints: [
            CHHapticParameterCurve.ControlPoint(relativeTime: 0, value: 1),
            CHHapticParameterCurve.ControlPoint(relativeTime: 0.24, value: 1),
            CHHapticParameterCurve.ControlPoint(relativeTime: 0.64, value: 0),
        ], relativeTime: 0)
        guard let pattern = try? CHHapticPattern(events: events, parameterCurves: [fade]) else { return nil }
        return try? engine.makePlayer(with: pattern)
    }
    #endif
}
