import XCTest
import CoreGraphics
import GameKit
@testable import MarblePop

/// iOS extras (Extras/): colour-blind symbols, landing haptics and the cup polish.
final class ExtrasTests: XCTestCase {

    // MARK: - flags & save key

    func testFeatureFlagsShipOn() {
        XCTAssertTrue(Features.colorBlindPatterns)
        XCTAssertTrue(Features.landingHaptics)
        XCTAssertTrue(Features.smoothPolish)
    }

    func testColorBlindSettingIsSavedInTheGameStore() {
        let suite = "MarblePopExtrasTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let prefs = Prefs(name: "marble_pop", defaults: defaults)
        let r = GameRepository(prefs: prefs)
        XCTAssertFalse(r.colorBlind, "default off")
        XCTAssertFalse(ColorBlind.active(r))
        r.setColorBlind(true)
        XCTAssertEqual(defaults.object(forKey: "marble_pop.color_blind") as? Bool, true)
        XCTAssertTrue(ColorBlind.active(r))
        XCTAssertTrue(GameRepository(prefs: prefs).colorBlind, "read back by a fresh repository")
        Features.colorBlindPatterns = false
        XCTAssertFalse(ColorBlind.active(r), "the flag switches the extra off")
        Features.colorBlindPatterns = true
        r.resetProgress()
        XCTAssertFalse(r.colorBlind)
        XCTAssertNil(defaults.object(forKey: "marble_pop.color_blind"))
    }

    // MARK: - colour-blind symbols

    func testEveryColourHasItsOwnSymbol() {
        let ids = Array(0..<MarbleColors.COUNT) + [MarbleColors.RAINBOW]
        let symbols = ids.compactMap { ColorBlindSymbol.of($0) }
        XCTAssertEqual(symbols.count, MarbleColors.COUNT + 1)
        XCTAssertEqual(Set(symbols).count, symbols.count)
        XCTAssertEqual(ColorBlindSymbol.allCases.count, MarbleColors.COUNT + 1)
        XCTAssertEqual(ColorBlindSymbol.of(0), .heart)
        XCTAssertEqual(ColorBlindSymbol.of(MarbleColors.RAINBOW), .arch)
        XCTAssertNil(ColorBlindSymbol.of(-1))
        XCTAssertNil(ColorBlindSymbol.of(MarbleColors.COUNT))
        XCTAssertNil(ColorBlindSymbol.of(MarbleColors.RAINBOW - 1))
        for s in ColorBlindSymbol.allCases {
            let b = s.unitPath.boundingBoxOfPath
            XCTAssertFalse(b.isEmpty, s.name)
            XCTAssertTrue(CGRect(x: -1.02, y: -1.02, width: 2.04, height: 2.04).contains(b), "\(s.name) leaves the unit box: \(b)")
        }
    }

    /// Rasterised at 24 px (about a marble on screen) every symbol covers a sensible area and differs from every
    /// other symbol in a large share of its pixels.
    func testSymbolsStayDistinctAtMarbleSize() {
        let n = 24
        let all = ColorBlindSymbol.allCases
        let masks = all.map { mask($0, n) }
        for (i, m) in masks.enumerated() {
            let cover = Double(m.filter { $0 }.count) / Double(n * n)
            XCTAssertGreaterThan(cover, 0.15, "\(all[i].name) is too thin")
            XCTAssertLessThan(cover, 0.75, "\(all[i].name) is too bulky")
        }
        for i in 0..<masks.count {
            for j in (i + 1)..<masks.count {
                let diff = zip(masks[i], masks[j]).filter { $0.0 != $0.1 }.count
                XCTAssertGreaterThan(Double(diff) / Double(n * n), 0.12, "\(all[i].name) and \(all[j].name) look alike")
            }
        }
        // the boolean path ops keep the holes
        XCTAssertFalse(masks[ColorBlindSymbol.ring.rawValue][(n / 2) * n + n / 2], "ring centre must be empty")
        XCTAssertFalse(masks[ColorBlindSymbol.moon.rawValue][7 * n + 18], "the crescent's bite must be empty")
        XCTAssertTrue(masks[ColorBlindSymbol.moon.rawValue][16 * n + 5])
    }

    /// Unit path into an n × n mask, row 0 = top (y-down like the sprites).
    private func mask(_ s: ColorBlindSymbol, _ n: Int) -> [Bool] {
        let ctx = CGContext(data: nil, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n,
                            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        ctx.setFillColor(gray: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: n, height: n))
        ctx.translateBy(x: CGFloat(n) / 2, y: CGFloat(n) / 2)
        ctx.scaleBy(x: CGFloat(n) / 2, y: -CGFloat(n) / 2)
        ctx.addPath(s.unitPath)
        ctx.setFillColor(gray: 1, alpha: 1)
        ctx.fillPath()
        let data = ctx.data!.assumingMemoryBound(to: UInt8.self)
        return (0..<(n * n)).map { data[$0] > 127 }
    }

    private func bytes(_ s: Sprite) -> Data { s.cg.dataProvider!.data! as Data }

    func testSpriteCacheBakesSymbolsOnlyWhenAsked() {
        let cache = SpriteCache(3)
        XCTAssertFalse(cache.symbols, "off by default (menus, onboarding)")
        let marble = cache.marble(0, 0, 12), shadowed = cache.marbleShadowed(4, 0, 12)
        let cup = cache.cup(2, false, 100, 58), hidden = cache.cup(2, true, 100, 58)
        let block = cache.block(5, 0, 90), closed = cache.block(5, 0, 90, 0, false), rainbow = cache.block(5, 3, 90)
        let mystery = cache.block(5, 1, 90), grey = cache.block(5, 2, 90)
        let rainbowMarble = cache.marbleShadowed(MarbleColors.RAINBOW, 0, 12)
        cache.symbols = true
        XCTAssertNotEqual(bytes(cache.marble(0, 0, 12)), bytes(marble))
        XCTAssertNotEqual(bytes(cache.marbleShadowed(4, 0, 12)), bytes(shadowed))
        XCTAssertNotEqual(bytes(cache.marbleShadowed(MarbleColors.RAINBOW, 0, 12)), bytes(rainbowMarble))
        XCTAssertNotEqual(bytes(cache.cup(2, false, 100, 58)), bytes(cup))
        XCTAssertNotEqual(bytes(cache.block(5, 0, 90)), bytes(block))
        XCTAssertNotEqual(bytes(cache.block(5, 0, 90, 0, false)), bytes(closed))
        XCTAssertNotEqual(bytes(cache.block(5, 3, 90)), bytes(rainbow))
        // hidden cups, mystery and grey blocks keep their colour a secret
        XCTAssertEqual(bytes(cache.cup(2, true, 100, 58)), bytes(hidden))
        XCTAssertEqual(bytes(cache.block(5, 1, 90)), bytes(mystery))
        XCTAssertEqual(bytes(cache.block(5, 2, 90)), bytes(grey))
        // plain and symbol sprites live under their own keys
        cache.symbols = false
        XCTAssertTrue(cache.marble(0, 0, 12) === marble)
        XCTAssertTrue(cache.cup(2, false, 100, 58) === cup)
    }

    func testRendererBakesSymbolsWhenAsked() {
        let spec = LevelGenerator.get(3)
        let e = GameEngine(spec, GameLayout(1560, 210, 8, spec), Golden.Recorder())
        let r = GameRenderer(engine: e, theme: Themes.get(0), skin: 0, widthPx: 390, heightPx: 845, displayScale: 3, symbols: true)
        XCTAssertTrue(r.sprites.symbols)
        r.release()
    }

    // MARK: - landing haptics

    func testLandingTransientsAreThrottledTo25PerSecond() {
        for fps in [60.0, 120.0] {
            var p = LandingHapticPlanner()
            var times: [Double] = []
            var sorted = 0
            for f in 0..<Int(fps * 3) { // a marble lands on every frame for 3 s
                let now = Double(f) / fps
                sorted += 1
                if let cue = p.step(now: now, engineTime: Float(now), sorted: sorted, cups: 0, combo: 0, won: false) {
                    XCTAssertEqual(cue, .landing(level: 0))
                    times.append(now)
                }
            }
            for t in times {
                XCTAssertLessThanOrEqual(times.filter { $0 >= t && $0 < t + 1 }.count, 25, "\(fps) Hz")
            }
            XCTAssertGreaterThanOrEqual(times.count, 55, "still a steady patter at \(fps) Hz")
        }
    }

    func testLandingsGetFirmerWithTheComboAndCupsAreFirmerStill() {
        var last: Float = 0
        for level in 0...LandingHapticPlanner.MAX_LEVEL {
            let v = LandingHapticPlanner.landing(level)
            XCTAssertGreaterThan(v.intensity, last)
            XCTAssertTrue((0...1).contains(v.intensity) && (0...1).contains(v.sharpness))
            last = v.intensity
        }
        XCTAssertLessThanOrEqual(LandingHapticPlanner.landing(0).intensity, 0.35, "soft")
        XCTAssertEqual(LandingHapticPlanner.landing(9).intensity, LandingHapticPlanner.landing(6).intensity)
        let cups = (1...6).map { LandingHapticPlanner.cupFilled($0) }
        XCTAssertEqual(cups.map(\.intensity), cups.map(\.intensity).sorted())
        XCTAssertLessThanOrEqual(cups.last!.intensity, 1)
        XCTAssertGreaterThan(cups.map(\.intensity).min()!, last, "every filled cup is firmer than any landing")
    }

    func testComboCountsOnlyWhileTheChainIsLive() {
        var p = LandingHapticPlanner()
        XCTAssertEqual(p.step(now: 0, engineTime: 10, sorted: 3, cups: 1, combo: 3, won: false), .cupFilled(combo: 3))
        XCTAssertEqual(p.step(now: 0.5, engineTime: 10.5, sorted: 4, cups: 1, combo: 3, won: false), .landing(level: 3))
        XCTAssertEqual(p.step(now: 2, engineTime: 12, sorted: 5, cups: 1, combo: 3, won: false), .landing(level: 0))
        XCTAssertEqual(p.step(now: 3, engineTime: 13, sorted: 6, cups: 2, combo: 9, won: false), .cupFilled(combo: 6))
    }

    func testCuePriorityAndGaps() {
        var p = LandingHapticPlanner()
        XCTAssertEqual(p.step(now: 0, engineTime: 0, sorted: 1, cups: 0, combo: 0, won: false), .landing(level: 0))
        // 10 ms later the third marble fills its cup: the cup tap always plays
        XCTAssertEqual(p.step(now: 0.01, engineTime: 0.01, sorted: 2, cups: 1, combo: 1, won: false), .cupFilled(combo: 1))
        // landings keep their gap after it
        XCTAssertNil(p.step(now: 0.03, engineTime: 0.03, sorted: 3, cups: 1, combo: 1, won: false))
        XCTAssertEqual(p.step(now: 0.06, engineTime: 0.06, sorted: 4, cups: 1, combo: 1, won: false), .landing(level: 1))
        XCTAssertNil(p.step(now: 0.2, engineTime: 0.2, sorted: 4, cups: 1, combo: 1, won: false), "nothing new")
        // the win beats everything and plays once
        XCTAssertEqual(p.step(now: 0.3, engineTime: 0.3, sorted: 5, cups: 2, combo: 2, won: true), .win)
        XCTAssertNil(p.step(now: 0.5, engineTime: 0.5, sorted: 5, cups: 2, combo: 2, won: true))
    }

    func testOnlyTheFilledCupAndWinHapticsAreReplaced() {
        var p = LandingHapticPlanner()
        XCTAssertFalse(p.replaces(.LIGHT, cupsFilled: 0), "blocked tap / machine landing / belt warning")
        XCTAssertTrue(p.replaces(.LIGHT, cupsFilled: 1), "GameEngine.completeCup")
        XCTAssertFalse(p.replaces(.LIGHT, cupsFilled: 1))
        XCTAssertFalse(p.replaces(.MEDIUM, cupsFilled: 2))
        XCTAssertTrue(p.replaces(.LIGHT, cupsFilled: 2))
        XCTAssertFalse(p.replaces(.HEAVY, cupsFilled: 2))
        XCTAssertTrue(p.replaces(.SUCCESS, cupsFilled: 2))
    }

    func testVibrationSettingFlagAndHardwareGateTheExtra() {
        XCTAssertTrue(LandingHaptics.isOn(flag: true, vibration: true, supported: true))
        XCTAssertFalse(LandingHaptics.isOn(flag: true, vibration: false, supported: true))
        XCTAssertFalse(LandingHaptics.isOn(flag: false, vibration: true, supported: true))
        XCTAssertFalse(LandingHaptics.isOn(flag: true, vibration: true, supported: false))
    }

    /// Engine listener that routes haptics through the planner like GameScreen's SessionListener.
    private final class Probe: GameListener {
        weak var engine: GameEngine?
        var planner = LandingHapticPlanner()
        var replacedCups = 0, replacedWins = 0, keptLights = 0
        func sound(_ sfx: Sfx, _ pitch: Float, _ volume: Float) {}
        func haptic(_ kind: Haptic) {
            guard let e = engine else { return }
            if planner.replaces(kind, cupsFilled: e.cupsFilled) {
                if kind == .SUCCESS { replacedWins += 1 } else { replacedCups += 1 }
            } else if kind == .LIGHT {
                keptLights += 1
            }
        }
        func combo(_ count: Int) {}
        func statusChanged(_ status: GameStatus) {}
    }

    /// Level 1 played by the golden-trace bot (trace L1_plan): one cue per filled cup and one win, the engine's
    /// own filled-cup and win haptics are exactly the ones replaced, landings stay ≤ 25/s, and every filled cup's
    /// shimmer has finished before the engine removes the cup.
    func testHapticsAndPolishFollowARealGame() {
        EngineRandom.source = KotlinRandom(11)
        let spec = LevelGenerator.generate(1)
        let layout = GameLayout(1560, 210, 8, spec)
        let probe = Probe()
        let e = GameEngine(spec, layout, probe)
        probe.engine = e
        var planIdx = 0
        var landings: [Double] = []
        var cupCues = 0, winCues = 0
        var maxPopT: Float = 0
        for f in 1...2400 {
            let dt: Float = f % 7 == 3 ? 0.05 : (f % 11 == 5 ? 0.004 : Float(1) / Float(60))
            e.update(dt)
            if let cue = probe.planner.step(now: Double(e.time), engineTime: e.time, sorted: e.marblesSorted, cups: e.cupsFilled,
                                            combo: e.combo, won: e.status == .WON) {
                switch cue {
                case .landing: landings.append(Double(e.time))
                case .cupFilled: cupCues += 1
                case .win: winCues += 1
                }
            }
            for col in e.tray { for cup in col.cups where cup.popping { maxPopT = max(maxPopT, cup.popT) } }
            if e.status == .PLAYING && !e.inIntro {
                if f % 20 == 0 {
                    while planIdx < spec.plan.count {
                        let i = e.board.locate(spec.plan[planIdx])
                        if i < 0 { planIdx += 1; continue }
                        if e.board.canTap(i) { Golden.tapCell(e, i); planIdx += 1 }
                        break
                    }
                }
                if f % 97 == 0 { e.tap(layout.cx, layout.gridTop + 1) }
                if f % 89 == 0 { e.tap(5, 5) }
            }
        }
        XCTAssertEqual(e.status, .WON)
        XCTAssertEqual(e.marblesSorted, 54, "same game as the golden trace L1_plan")
        XCTAssertEqual(winCues, 1)
        XCTAssertEqual(probe.replacedWins, 1)
        XCTAssertEqual(probe.replacedCups, e.cupsFilled, "exactly the completeCup taps are replaced")
        XCTAssertGreaterThan(cupCues, 0)
        XCTAssertLessThanOrEqual(cupCues, e.cupsFilled)
        XCTAssertGreaterThan(landings.count, 0)
        for t in landings { XCTAssertLessThanOrEqual(landings.filter { $0 >= t && $0 < t + 1 }.count, 25) }
        // a filled cup is drawn until popT reaches CupPolish.POP; the shimmer ends well before that
        XCTAssertGreaterThan(maxPopT, 0)
        XCTAssertLessThan(CGFloat(maxPopT), CupPolish.POP)
        XCTAssertGreaterThan(CGFloat(maxPopT), CupPolish.POP - 0.06)
        XCTAssertLessThan(CupPolish.SHIMMER_END * CupPolish.POP, CGFloat(maxPopT))
    }

    // MARK: - cup polish

    func testCupSpringIsGentleAndEndsWithTheEngineTimer() {
        XCTAssertEqual(CupPolish.bounce(0, 1).squash, 0)
        XCTAssertEqual(CupPolish.bounce(1, 1).squash, 0)
        let impact = CupPolish.bounce(0.8, 1) // 50 ms after the landing
        XCTAssertGreaterThan(impact.squash, 0.02)
        XCTAssertGreaterThan(impact.dip, 0)
        let rebound = CupPolish.bounce(0.4, 1) // 150 ms: a softer stretch back
        XCTAssertLessThan(rebound.squash, 0)
        XCTAssertLessThan(abs(rebound.squash), impact.squash)
        XCTAssertLessThan(CupPolish.bounce(0.8, 1).squash, CupPolish.bounce(0.8, 2).squash)
        XCTAssertLessThan(CupPolish.bounce(0.8, 2).squash, CupPolish.bounce(0.8, 3).squash, "biggest when the cup fills")
        for k in 0...200 {
            for n in 1...3 { XCTAssertLessThanOrEqual(abs(CupPolish.bounce(Float(k) / 200, n).squash), 0.08) }
        }
        XCTAssertLessThan(abs(CupPolish.bounce(0.02, 3).squash), 0.002, "fades out before the timer ends")
    }

    func testFlyAwayAndShimmerStayInsideThePop() {
        XCTAssertEqual(CupPolish.lift(0), 0)
        XCTAssertEqual(CupPolish.lift(1), 1)
        XCTAssertEqual(CupPolish.fade(0), 1)
        XCTAssertEqual(CupPolish.fade(1), 0)
        var lift: CGFloat = -1, fade: CGFloat = 2
        for k in 0...50 {
            let t = CGFloat(k) / 50
            XCTAssertGreaterThanOrEqual(CupPolish.lift(t), lift)
            XCTAssertLessThanOrEqual(CupPolish.fade(t), fade)
            lift = CupPolish.lift(t)
            fade = CupPolish.fade(t)
        }
        XCTAssertLessThan(CupPolish.lift(0.3), 0.3, "holds still while the shimmer passes")
        XCTAssertNil(CupPolish.shimmerPhase(0))
        XCTAssertEqual(CupPolish.shimmerPhase(CupPolish.SHIMMER_END / 2)!, 0.5, accuracy: 1e-9)
        XCTAssertNil(CupPolish.shimmerPhase(CupPolish.SHIMMER_END))
        XCTAssertNil(CupPolish.shimmerPhase(1))
        XCTAssertLessThan(CupPolish.SHIMMER_END, 1)
        XCTAssertGreaterThan(CupPolish.fade(CupPolish.SHIMMER_END), 0.6, "the cup is still solid while it shimmers")
    }

    /// The extras never reach into the simulation: a golden-trace bot run gives identical engine states with every
    /// extra switched off.
    func testExtrasDoNotChangeTheSimulation() {
        let on = Golden.runTrace(level: 40, seed: 16, frames: 900, policy: 0, tapEvery: 12, boosters: true)
        Features.colorBlindPatterns = false
        Features.landingHaptics = false
        Features.smoothPolish = false
        defer {
            Features.colorBlindPatterns = true
            Features.landingHaptics = true
            Features.smoothPolish = true
        }
        let off = Golden.runTrace(level: 40, seed: 16, frames: 900, policy: 0, tapEvery: 12, boosters: true)
        XCTAssertEqual(on.hashes, off.hashes)
        XCTAssertEqual(on.events, off.events)
    }
}
