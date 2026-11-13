import Foundation
import GameKit
@testable import MarblePop

/// Helpers mirroring `Golden/source/GoldenDump.kt` line by line (same text format, same hash, same bot).
enum Golden {
    private final class Token {}

    /// Golden JSON from the test bundle (synchronized folder resources), falling back to the source tree.
    static func url(_ name: String) -> URL {
        let bundle = Bundle(for: Token.self)
        if let u = bundle.url(forResource: name, withExtension: "json") { return u }
        if let u = bundle.url(forResource: name, withExtension: "json", subdirectory: "Golden") { return u }
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Golden").appendingPathComponent(name + ".json")
    }

    static func text(_ name: String) -> String {
        let u = url(name)
        guard let s = try? String(contentsOf: u, encoding: .utf8) else { fatalError("missing golden file \(u.path)") }
        return s
    }

    /// Every level 1...5000, generated once per test run (shared by the golden and the solver tests).
    static let levels: [LevelSpec] = (1...LevelGenerator.MAX_LEVEL).map { LevelGenerator.generate($0) }

    // MARK: levels.json line format

    static func levelLine(_ s: LevelSpec) -> String {
        var b = "{\"n\":\(s.number),\"w\":\(s.width),\"h\":\(s.height),\"mask\":\""
        for m in s.mask { b += m ? "1" : "0" }
        b += "\",\"cells\":["
        for (i, c) in s.cells.enumerated() {
            if i > 0 { b += "," }
            if let c { b += "[\(c.id),\(c.color),\(c.kind.ordinal),\(c.param)]" } else { b += "null" }
        }
        b += "],\"tray\":["
        for (i, col) in s.tray.enumerated() {
            if i > 0 { b += "," }
            b += "["
            for (j, cup) in col.enumerated() {
                if j > 0 { b += "," }
                b += String(cup.color + (cup.hidden ? 100 : 0))
            }
            b += "]"
        }
        b += "],\"cap\":\(s.capacity),\"theme\":\(s.theme),\"colors\":\(s.colorCount),\"boss\":\(s.isBoss),\"plan\":["
        b += s.plan.map { String($0) }.joined(separator: ",")
        b += "],\"intro\":" + (s.introduces.map { "\"\($0.name)\"" } ?? "null") + "}"
        return b
    }

    // MARK: engine state hash (64-bit FNV-1a over 32-bit words)

    struct Hasher {
        var h: UInt64 = 0xcbf29ce484222325
        mutating func i(_ v: Int) { h = (h ^ UInt64(UInt32(truncatingIfNeeded: v))) &* 1099511628211 }
        mutating func f(_ v: Float) { i(Int(Int32(bitPattern: v.bitPattern))) }
        mutating func b(_ v: Bool) { i(v ? 1 : 0) }
        mutating func c(_ v: UInt32) { i(Int(Int32(bitPattern: v))) }
    }

    static func hashState(_ e: GameEngine) -> UInt64 {
        var x = Hasher()
        x.i(e.status.rawValue); x.i(e.failReason.rawValue); x.f(e.time); x.f(e.introT); x.b(e.inIntro)
        x.f(e.beltOffset); x.f(e.beltVel); x.i(e.beltCount); x.i(e.peakBelt); x.i(e.capacity); x.f(e.spacing)
        x.i(e.combo); x.i(e.maxCombo); x.i(e.comboCoins); x.i(e.cupsFilled); x.i(e.marblesSorted); x.i(e.boostersUsed)
        x.b(e.continued); x.f(e.shake); x.b(e.danger); x.f(e.dangerLevel); x.i(e.stars); x.i(e.coinReward()); x.b(e.isBusy)
        if let hint = e.hintTarget() { x.f(hint[0]); x.f(hint[1]) } else { x.i(-7) }
        let bd = e.board
        x.i(bd.pops); x.i(bd.moves); x.i(bd.cupsDone); x.i(bd.bombBonus)
        for c in bd.cells { if let c { x.i(c.id); x.b(c.cracked); x.b(c.revealed) } else { x.i(-1) } }
        for v in bd.exposed { x.b(v) }
        x.i(bd.openLocks.count); for v in bd.openLocks.sorted() { x.i(v) }
        x.i(bd.paintedBuckets.count); for v in bd.paintedBuckets.sorted() { x.i(v) }
        x.i(e.marbles.count)
        for m in e.marbles {
            x.i(m.state.rawValue); x.i(m.color); x.f(m.x); x.f(m.y); x.f(m.px); x.f(m.py); x.i(m.channel); x.i(m.slot)
            x.f(m.angle); x.f(m.t); x.f(m.dur); x.f(m.sx); x.f(m.sy); x.i(m.targetCol); x.i(m.targetDimple)
            x.f(m.prevX); x.f(m.squash); x.f(m.age); x.f(m.stuckT); x.i(m.wp?.count ?? -1); x.i(m.wpi); x.f(m.wait)
        }
        x.i(e.slots.count)
        for s in e.slots { x.i(s.map { s in e.marbles.firstIndex { $0 === s } ?? -1 } ?? -1) }
        for col in e.tray {
            x.i(col.cups.count)
            for c in col.cups {
                x.i(c.color); x.b(c.hidden); x.i(c.reserved); x.i(c.arrived); x.f(c.display); x.b(c.popping); x.f(c.popT)
                x.f(c.bounce); x.f(c.vel); x.f(c.reveal); x.b(c.revealing); x.f(c.shuffleT)
            }
        }
        for v in e.visuals {
            guard let v else { x.i(-1); continue }
            x.i(v.index); x.f(v.dropY); x.f(v.dropVel); x.f(v.delay); x.f(v.squash); x.f(v.shake); x.f(v.flash); x.f(v.reveal)
            x.f(v.crack); x.f(v.unlock); x.b(v.wasLocked); x.f(v.pulse); x.f(v.paint); x.f(v.open); x.b(v.wasOpen); x.f(v.wake)
        }
        x.i(e.exiting.count)
        for b in e.exiting { x.f(b.t); x.f(b.x); x.f(b.y); x.f(b.cell); x.i(b.state.id) }
        x.i(e.flying.count)
        for f in e.flying { x.f(f.t); x.f(f.x); x.f(f.y); x.f(f.rot); x.f(f.scale); x.f(f.mx); x.f(f.my); x.f(f.tx); x.f(f.ty); x.i(f.state.id) }
        x.i(e.texts.count)
        for t in e.texts { x.i(Kt.javaHash(t.text)); x.f(t.x); x.f(t.y); x.f(t.life); x.c(t.color); x.f(t.size) }
        let p = e.particles
        x.i(p.count)
        for k in 0..<p.count {
            x.f(p.x[k]); x.f(p.y[k]); x.f(p.vx[k]); x.f(p.vy[k]); x.f(p.life[k]); x.f(p.maxLife[k]); x.f(p.size[k])
            x.f(p.rot[k]); x.f(p.vrot[k]); x.f(p.grav[k]); x.c(p.color[k]); x.i(p.type[k])
        }
        return x.h
    }

    // MARK: deterministic bot

    final class Recorder: GameListener {
        var frame = 0
        var events: [String] = []
        func sound(_ sfx: Sfx, _ pitch: Float, _ volume: Float) {
            events.append("\(frame) S \(sfx.name) \(Int32(bitPattern: pitch.bitPattern)) \(Int32(bitPattern: volume.bitPattern))")
        }
        func haptic(_ kind: Haptic) { events.append("\(frame) H \(kind)") }
        func combo(_ count: Int) { events.append("\(frame) C \(count)") }
        func statusChanged(_ status: GameStatus) { events.append("\(frame) T \(status)") }
    }

    struct TraceResult {
        var hashes: [String] = []
        var events: [String] = []
        var finalStatus = ""
        var marblesSorted = 0
    }

    static func tapCell(_ e: GameEngine, _ i: Int) {
        let c = i % e.spec.width, r = i / e.spec.width
        e.tap(e.layout.cellCenterX(c), e.layout.cellCenterY(Float(r)))
    }

    static func runTrace(level: Int, seed: Int64, frames: Int, policy: Int, tapEvery: Int, boosters: Bool,
                         probe: ((GameEngine) -> Void)? = nil) -> TraceResult {
        EngineRandom.source = KotlinRandom(seed)
        let spec = LevelGenerator.generate(level)
        let layout = GameLayout(1560, 210, 8, spec)
        let rec = Recorder()
        let e = GameEngine(spec, layout, rec)
        var planIdx = 0
        var continues = 0
        var out = TraceResult()
        for f in 1...frames {
            rec.frame = f
            let dt: Float = f % 7 == 3 ? 0.05 : (f % 11 == 5 ? 0.004 : Float(1) / Float(60))
            e.update(dt)
            if e.status == .FAILED && continues < 2 && f % 30 == 0 { e.continueGame(); continues += 1; rec.events.append("\(f) K \(e.failReason)") }
            if e.status == .PLAYING && !e.inIntro {
                if f % tapEvery == 0 {
                    if policy == 0 {
                        while planIdx < spec.plan.count {
                            let i = e.board.locate(spec.plan[planIdx])
                            if i < 0 { planIdx += 1; continue }
                            if e.board.canTap(i) { tapCell(e, i); planIdx += 1 }
                            break
                        }
                    } else {
                        var pick = -1
                        let n = e.board.cells.count
                        for k in 0..<n {
                            let i = policy == 2 ? n - 1 - k : k
                            if !e.board.canTap(i) { continue }
                            if policy == 3 && e.board.cells[i]!.spec.kind == .BOMB { continue }
                            pick = i; break
                        }
                        if pick < 0 { for i in 0..<n where e.board.cells[i] != nil { pick = i; break } }
                        if pick >= 0 { tapCell(e, pick) }
                    }
                }
                if boosters {
                    switch f {
                    case 150, 330:
                        var done = false
                        for k in stride(from: e.visuals.count - 1, through: 0, by: -1) {
                            guard let v = e.visuals[k] else { continue }
                            done = e.hammer(layout.cellCenterX(v.col), layout.cellCenterY(Float(v.row))); break
                        }
                        rec.events.append("\(f) B hammer \(done)")
                    case 200:
                        e.boosterSlots(); rec.events.append("\(f) B slots")
                    case 260, 520:
                        rec.events.append("\(f) B magnet \(e.magnet())")
                    case 280, 600:
                        rec.events.append("\(f) B shuffle \(e.boosterShuffle())")
                    default:
                        break
                    }
                }
                if f % 97 == 0 { e.tap(layout.cx, layout.gridTop + 1) }
                if f % 89 == 0 { e.tap(5, 5) }
            }
            out.hashes.append(String(hashState(e), radix: 16))
            probe?(e)
        }
        out.events = rec.events
        out.finalStatus = "\(e.status)"
        out.marblesSorted = e.marblesSorted
        return out
    }
}
