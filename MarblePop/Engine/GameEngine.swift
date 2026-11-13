import Foundation
import GameKit

enum GameStatus: Int { case PLAYING, WON, FAILED }
enum FailReason: Int { case JAM, BOMB, NO_MOVES }
enum Haptic: Int { case LIGHT, MEDIUM, HEAVY, SUCCESS }

/// Engine → host events (Kotlin `GameListener`). Kotlin's `sound(sfx, pitch = 1f, volume = 1f)` defaults are the
/// `sound(_:)` / `sound(_:_:)` helpers below; conformers implement all four requirements.
/// The engine keeps a strong reference to its listener (like Kotlin), so don't make the listener own the engine.
protocol GameListener {
    func sound(_ sfx: Sfx, _ pitch: Float, _ volume: Float)
    func haptic(_ kind: Haptic)
    func combo(_ count: Int)
    func statusChanged(_ status: GameStatus)
}

extension GameListener {
    func sound(_ sfx: Sfx) { sound(sfx, 1, 1) }
    func sound(_ sfx: Sfx, _ pitch: Float) { sound(sfx, pitch, 1) }
}

private let PI_F = Float(Double.pi)

/// Real-time game simulation.
/// Board rules (which blocks are open) live in `Board`; this class animates everything:
/// marbles streaming out of the board along their path, the hopper physics, the belt and the cups.
final class GameEngine {
    let spec: LevelSpec
    let layout: GameLayout
    private let listener: GameListener
    let board: Board
    private(set) var status = GameStatus.PLAYING
    private(set) var failReason = FailReason.JAM
    private(set) var time: Float = 0

    // ---- board visuals (fixed cells, index = row * width + col)
    private(set) var visuals: [BlockVisual?]
    var exiting: [ExitingBlock] = []
    var flying: [FlyingBlock] = []

    private(set) var introT: Float = 0
    let introDone: Float
    var inIntro: Bool { introT < introDone }

    // ---- marbles
    var marbles: [Marble] = []
    private var physicsList: [Marble] = []

    // ---- belt
    private(set) var capacity: Int
    private(set) var slots: [Marble?]
    private(set) var spacing: Float
    private(set) var beltOffset: Float = 0
    private(set) var beltVel: Float = 0
    private var beltDir: Float = 1
    let beltSpeed: Float = 175
    private(set) var beltCount = 0
    private(set) var peakBelt = 0

    // ---- tray
    let tray: [TrayColumn]

    // ---- fx
    let particles = Particles()
    var texts: [FloatingText] = []
    private(set) var shake: Float = 0
    private(set) var danger = false
    private(set) var dangerLevel: Float = 0

    // ---- stats
    private(set) var combo = 0
    private(set) var maxCombo = 0
    private(set) var comboCoins = 0
    private(set) var cupsFilled = 0
    private(set) var marblesSorted = 0
    var boostersUsed = 0
    private(set) var continued = false
    private var lastCupTime: Float = -10
    private var lastDropTime: Float = 0
    private var lastClack: Float = 0
    private var pendingEnd: Float = -1
    private var pendingStatus = GameStatus.PLAYING
    private var gridTmp = [Int](repeating: 0, count: MarbleColors.COUNT)

    private let segs: [Float]
    /// How many loose marbles the hopper holds before streams wait in the board.
    private let hopperCap: Int

    var lapTime: Float { layout.beltLength / beltSpeed }
    var isBusy: Bool { !marbles.isEmpty || !flying.isEmpty }

    convenience init(spec: LevelSpec, layout: GameLayout, listener: GameListener) {
        self.init(spec, layout, listener)
    }

    init(_ spec: LevelSpec, _ layout: GameLayout, _ listener: GameListener) {
        self.spec = spec
        self.layout = layout
        self.listener = listener
        let board = Board(spec)
        self.board = board
        visuals = (0..<(spec.width * spec.height)).map { i -> BlockVisual? in
            guard let st = board.cells[i] else { return nil }
            let c = i % spec.width, r = i / spec.width
            let v = BlockVisual(st, i, c, r)
            v.dropY = Float(spec.height) + 1.5 - Float(r) * 0.4
            v.delay = GameEngine.INTRO_MACHINE + Float(r) * 0.08 + Float(c) * 0.05
            v.wasLocked = board.isLocked(st)
            v.wasOpen = board.hasExit(i)
            v.open = v.wasOpen ? 1 : 0
            return v
        }
        introDone = GameEngine.INTRO_MACHINE + Float(spec.height - 1) * 0.08 + Float(spec.width - 1) * 0.05 + 0.5
        capacity = spec.capacity
        slots = [Marble?](repeating: nil, count: spec.capacity)
        spacing = layout.beltLength / Float(spec.capacity)
        tray = spec.tray.map { col in
            let tc = TrayColumn()
            for (i, c) in col.enumerated() {
                let cup = Cup(c.color, c.hidden)
                cup.display = Float(i) + 5
                tc.cups.append(cup)
            }
            return tc
        }
        let l = layout
        let sl = l.cx - l.spoutHalf
        let sr = l.cx + l.spoutHalf
        segs = [
            l.gridLeft - 2, l.gridBottom, sl, l.spoutTop,
            sl, l.spoutTop, sl, l.gateFloor,
            sl, l.gateFloor, sr, l.gateFloor,
            sr, l.gateFloor, sr, l.spoutTop,
            sr, l.spoutTop, l.gridRight + 2, l.gridBottom,
        ]
        let area = (l.gridRight - l.gridLeft + l.spoutHalf * 2) * 0.5 * l.funnelH + l.spoutHalf * 2 * (l.gateFloor - l.spoutTop)
        hopperCap = Kt.toInt(area / (4 * l.marbleR * l.marbleR) * 0.72).coerceIn(14, 60)
    }

    // ============================================================ input

    func cellAt(_ wx: Float, _ wy: Float) -> Int {
        let c = Kt.toInt(Kt.floor((wx - layout.gridLeft) / layout.cell))
        let r = Kt.toInt(Kt.floor((layout.gridBottom - wy) / layout.cell))
        if c < 0 || c >= spec.width || r < 0 || r >= spec.height { return -1 }
        return r * spec.width + c
    }

    func tap(_ wx: Float, _ wy: Float) {
        if status != .PLAYING || pendingEnd >= 0 || inIntro { return }
        let i = cellAt(wx, wy)
        if i < 0 { return }
        guard let v = visuals[i] else { return }
        if !board.canTap(i) {
            v.shake = 1
            if board.isLocked(v.state) { v.pulse = 1 }
            listener.sound(.TAP, 0.7, 0.6)
            listener.haptic(.LIGHT)
            return
        }
        listener.sound(.TAP, 1 + EngineRandom.nextFloat() * 0.1)
        let path = board.exposed[i] ? board.pathOut(i) : nil
        switch board.tap(i) {
        case .CRACK:
            v.crack = 1; v.squash = 0.5
            particles.burst(layout.cellCenterX(v.col), layout.cellCenterY(Float(v.row)), 14, 260, 0xFFE6F8FF, Particles.SHARD, 7, 0.6, 900)
            listener.sound(.ICE)
            listener.haptic(.MEDIUM)
        case .POP:
            pop(v, path)
        case .NONE:
            break
        }
        afterMove()
    }

    private func afterMove() {
        if board.bombExpired() {
            for case let v? in visuals where v.state.spec.kind == .BOMB && board.counterRemaining(v.state) == 0 {
                let x = layout.cellCenterX(v.col), y = layout.cellCenterY(Float(v.row))
                particles.burst(x, y, 40, 520, 0xFFFF7A1A, Particles.DOT, 14, 0.8, 300)
                particles.burst(x, y, 18, 220, 0xFF5A5A6E, Particles.SMOKE, 26, 1.1, -60)
                particles.emit(x, y, 0, 0, 0.5, layout.cell * 2.2, 0xFFFFD23F, Particles.RING)
            }
            shake = 20
            listener.sound(.EXPLODE)
            listener.haptic(.HEAVY)
            endWith(.FAILED, .BOMB, 0.9)
        }
        refreshBlockStates()
    }

    /// Removes a block: marbles stream out along `path`, or the block flies to the hopper when there's no path.
    private func pop(_ v: BlockVisual, _ path: [Int]?) {
        visuals[v.index] = nil
        let l = layout
        let cell = l.cell
        let left = l.cellLeft(v.col)
        let top = l.cellTop(Float(v.row))
        let st = v.state
        if let path {
            streamOut(st, v.col, v.row, path)
            exiting.append(ExitingBlock(st, left, top, cell))
        } else {
            let f = FlyingBlock(st, left, top, cell)
            if st.spec.kind == .ARROW && st.spec.param == 0 {
                f.mx = l.gridLeft - cell * 1.1; f.my = top
            } else if st.spec.kind == .ARROW && st.spec.param == 1 {
                f.mx = l.gridRight + cell * 0.1; f.my = top
            } else {
                f.mx = left; f.my = Kt.min(top, l.gridTop) - cell * 0.9
            }
            f.tx = l.cx - cell / 2; f.ty = l.gridBottom + 6
            flying.append(f)
            listener.sound(.WHOOSH)
        }
        listener.haptic(.MEDIUM)
    }

    private func streamOut(_ st: BlockState, _ col: Int, _ row: Int, _ path: [Int]) {
        let l = layout
        let cell = l.cell
        let bspec = st.spec
        let n = bspec.marbleCount
        let color = bspec.marbleColor
        let left = l.cellLeft(col), top = l.cellTop(Float(row))
        let exit = path[path.count - 1]
        let exitCol = exit % spec.width
        for k in 0..<n {
            let gx = k % 3, gy = (k / 3) % 3
            let ox = Float(gx - 1) * cell * 0.22
            let oy = Float(gy - 1) * cell * 0.22
            let m = Marble(color)
            m.state = .PATH
            m.x = left + cell * 0.5 + Float(gx - 1) * cell * 0.28
            m.y = top + cell * 0.5 + Float(gy - 1) * cell * 0.28
            var pts = [Float]()
            pts.reserveCapacity(path.count * 2 + 2)
            for j in 1..<max(1, path.count) {
                let pc = path[j] % spec.width, pr = path[j] / spec.width
                pts.append(l.cellCenterX(pc) + ox); pts.append(l.cellCenterY(Float(pr)) + oy)
            }
            pts.append(l.cellCenterX(exitCol) + ox); pts.append(l.gridBottom + 6 + oy * 0.5)
            m.wp = pts
            m.wpi = 0
            m.wait = Float(k) * 0.022 + Float(k / 9) * 0.12
            marbles.append(m)
        }
        let cx = left + cell / 2, cy = top + cell / 2
        let argb: UInt32 = color == MarbleColors.RAINBOW ? 0xFFFFFFFF : MarbleColors.argb[color]
        particles.emit(cx, cy, 0, 0, 0.35, cell * 1.15, argb, Particles.RING)
        particles.burst(cx, cy, 10, 260, argb, Particles.DOT, 8, 0.45, 300)
        particles.burst(cx, cy, 5, 170, 0xFFFFFFFF, Particles.STAR, 11, 0.45)
        shake = Kt.max(shake, 3)
        listener.sound(.POP, 0.95 + EngineRandom.nextFloat() * 0.12)
        if bspec.kind == .SWITCH {
            beltDir = -beltDir
            texts.append(FloatingText("REVERSE!", l.cx, l.beltCy, 0xFFFFFFFF, 30))
        }
    }

    /// Burst at the hopper mouth (flying blocks and hammered blocks without a path).
    private func burstAtMouth(_ st: BlockState) {
        let l = layout
        let n = st.spec.marbleCount
        for k in 0..<n {
            let m = Marble(st.spec.marbleColor)
            m.x = l.cx + Float((k % 5) - 2) * l.marbleR * 2.1
            m.y = l.gridBottom + 4 - Float(k / 5) * l.marbleR * 2
            m.px = m.x; m.py = m.y - 1
            marbles.append(m)
        }
        let argb: UInt32 = st.spec.marbleColor == MarbleColors.RAINBOW ? 0xFFFFFFFF : MarbleColors.argb[st.spec.marbleColor]
        particles.emit(l.cx, l.gridBottom, 0, 0, 0.4, l.cell * 1.3, argb, Particles.RING)
        particles.burst(l.cx, l.gridBottom, 14, 300, argb, Particles.DOT, 9, 0.5, 400)
        listener.sound(.POP)
        if st.spec.kind == .SWITCH { beltDir = -beltDir }
    }

    // ============================================================ boosters

    @discardableResult
    func hammer(_ wx: Float, _ wy: Float) -> Bool {
        if status != .PLAYING || inIntro { return false }
        let i = cellAt(wx, wy)
        if i < 0 { return false }
        guard let v = visuals[i] else { return false }
        let path = board.exposed[i] ? board.pathOut(i) : nil
        board.tap(i, force: true)
        shake = 10
        listener.sound(.EXPLODE, 1.4, 0.7)
        particles.burst(layout.cellCenterX(v.col), layout.cellCenterY(Float(v.row)), 18, 300, 0xFFFFFFFF, Particles.STAR, 12, 0.6)
        if let path {
            streamOut(v.state, v.col, v.row, path)
            visuals[i] = nil
            exiting.append(ExitingBlock(v.state, layout.cellLeft(v.col), layout.cellTop(Float(v.row)), layout.cell))
        } else {
            pop(v, nil)
        }
        boostersUsed += 1
        afterMove()
        return true
    }

    @discardableResult
    func magnet() -> Bool {
        if status != .PLAYING { return false }
        var counts = [Int](repeating: 0, count: MarbleColors.COUNT)
        for case let m? in slots where m.state == .BELT && m.color != MarbleColors.RAINBOW { counts[m.color] += 1 }
        var best = -1, bestScore = 0
        for k in 0..<counts.count {
            if counts[k] == 0 { continue }
            var room = 0
            for col in tray { for cup in col.cups where cup.color == k && !cup.popping { room += 3 - cup.reserved } }
            let score = min(room, counts[k])
            if score > bestScore { bestScore = score; best = k }
        }
        if best < 0 { return false }
        var moved = 0
        for i in 0..<slots.count {
            guard let m = slots[i] else { continue }
            if m.state != .BELT || m.color != best { continue }
            var placed = false
            for (ci, col) in tray.enumerated() {
                for cup in col.cups {
                    if cup.color == best && !cup.popping && cup.reserved < 3 {
                        cup.reserved += 1
                        startDrop(m, ci, cup, 0.5 + Float(moved) * 0.03)
                        cup.reveal = 1; cup.hidden = false
                        placed = true; break
                    }
                }
                if placed { break }
            }
            if placed { moved += 1 }
        }
        if moved > 0 {
            boostersUsed += 1
            listener.sound(.REWARD, 1.2, 0.8)
            texts.append(FloatingText("MAGNET!", layout.cx, layout.beltCy - 20, 0xFFFFFFFF, 32))
        }
        return moved > 0
    }

    func addSlots(_ n: Int) {
        let old = slots
        let oldSpacing = spacing
        capacity += n
        spacing = layout.beltLength / Float(capacity)
        slots = [Marble?](repeating: nil, count: capacity)
        for i in 0..<old.count {
            guard let m = old[i] else { continue }
            let s = Float(i) * oldSpacing
            var idx = Kt.roundToInt(s / spacing) % capacity
            while slots[idx] != nil { idx = (idx + 1) % capacity }
            slots[idx] = m
            m.slot = idx
        }
        beltCount = countSlots()
        texts.append(FloatingText("+\(n) SLOTS", layout.cx, layout.beltCy, 0xFFFFFFFF, 30))
        listener.sound(.REWARD)
    }

    func boosterSlots() { addSlots(6); boostersUsed += 1 }

    @discardableResult
    func shuffleTray() -> Bool {
        var cups: [Cup] = []
        for col in tray { for cup in col.cups where cup.reserved == 0 && !cup.popping { cups.append(cup) } }
        if cups.count < 2 { return false }
        let colors = cups.map { $0.color }.kotlinShuffled(EngineRandom.source)
        for (i, cup) in cups.enumerated() {
            cup.color = colors[i]
            cup.hidden = false; cup.reveal = 1
            cup.shuffleT = 1
        }
        listener.sound(.WHOOSH, 1.2)
        return true
    }

    @discardableResult
    func boosterShuffle() -> Bool {
        let ok = shuffleTray()
        if ok { boostersUsed += 1 }
        return ok
    }

    func continueGame() {
        if status != .FAILED { return }
        continued = true
        switch failReason {
        case .BOMB: board.bombBonus += 6
        case .JAM: addSlots(10)
        case .NO_MOVES: shuffleTray(); addSlots(6)
        }
        lastDropTime = time
        pendingEnd = -1
        status = .PLAYING
        listener.statusChanged(status)
    }

    // ============================================================ update

    func update(_ dtIn: Float) {
        let dt = dtIn.coerceIn(0, Float(1) / Float(30))
        time += dt
        if introT < 10 {
            let before = introT
            introT += dt
            if before == 0 { listener.sound(.WHOOSH, 0.8, 0.7) }
            if before < GameEngine.INTRO_MACHINE && introT >= GameEngine.INTRO_MACHINE { shake = 5; listener.haptic(.LIGHT) }
        }
        updateBlocks(dt)
        updateFlying(dt)
        updatePaths(dt)
        physics(dt)
        updateBelt(dt)
        updateDropping(dt)
        updateCups(dt)
        particles.update(dt)
        var i = 0
        while i < texts.count {
            let t = texts[i]
            t.life += dt; t.y -= 50 * dt
            if t.life > t.maxLife { texts.remove(at: i) } else { i += 1 }
        }
        i = 0
        while i < exiting.count {
            let e = exiting[i]
            e.t += dt / 0.22
            if e.t >= 1 { exiting.remove(at: i) } else { i += 1 }
        }
        shake = (shake - dt * 40).coerceAtLeast(0)
        dangerLevel += ((danger ? 1 : 0) - dangerLevel) * Kt.min(1, dt * 4)
        checkEnd(dt)
    }

    private func updateBlocks(_ dt: Float) {
        for case let v? in visuals {
            if v.delay > 0 { v.delay -= dt; continue }
            if v.dropY > 0 || v.dropVel != 0 {
                v.dropVel += 34 * dt
                v.dropY -= v.dropVel * dt
                if v.dropY <= 0 {
                    if v.dropVel > 2 { v.squash = Kt.min(0.3, v.dropVel * 0.03); listener.sound(.CLACK, 0.6 + 0.08 * Float(v.row), 0.35) }
                    v.dropY = 0; v.dropVel = 0
                }
            }
            let target: Float = board.hasExit(v.index) ? 1 : 0
            v.open += (target - v.open) * Kt.min(1, dt * 9)
            v.squash = (v.squash - dt * 2.4).coerceAtLeast(0)
            v.shake = (v.shake - dt * 3).coerceAtLeast(0)
            v.pulse = (v.pulse - dt * 2).coerceAtLeast(0)
            v.unlock = (v.unlock - dt * 1.6).coerceAtLeast(0)
            v.crack = (v.crack - dt * 3).coerceAtLeast(0)
            v.wake = (v.wake - dt * 2.8).coerceAtLeast(0)
            if v.state.revealed && v.reveal < 1 { v.reveal = (v.reveal + dt * 3).coerceAtMost(1) }
            let painted = v.state.spec.kind == .GRAY && board.paintedBuckets.contains(v.state.spec.param)
            if painted && v.paint < 1 { v.paint = (v.paint + dt * 2.5).coerceAtMost(1) }
            v.flash = (v.flash - dt * 3).coerceAtLeast(0)
        }
    }

    private func refreshBlockStates() {
        var woke = false
        for case let v? in visuals {
            let locked = board.isLocked(v.state)
            if v.wasLocked && !locked {
                v.unlock = 1; v.flash = 1
                particles.burst(layout.cellCenterX(v.col), layout.cellCenterY(Float(v.row)), 12, 240, 0xFFFFD23F, Particles.STAR, 12, 0.6)
                listener.sound(.UNLOCK)
            }
            v.wasLocked = locked
            let open = board.hasExit(v.index)
            if open && !v.wasOpen { v.wake = 1; woke = true }
            v.wasOpen = open
            if v.state.revealed && v.reveal == 0 {
                v.reveal = 0.001
                listener.sound(.STAR, 1.3, 0.5)
            }
        }
        if woke { listener.sound(.PLINK, 1.5, 0.35) }
    }

    private func updateFlying(_ dt: Float) {
        var i = 0
        while i < flying.count {
            let f = flying[i]
            f.t += dt / f.duration
            let t = f.t.coerceAtMost(1)
            if t < 0.35 {
                let k = GameEngine.easeOut(t / 0.35)
                f.x = f.x0 + (f.mx - f.x0) * k; f.y = f.y0 + (f.my - f.y0) * k
                f.scale = 1 + 0.12 * k
            } else {
                let k = (t - 0.35) / 0.65
                let ctrlX = f.mx, ctrlY = Kt.min(f.my, f.ty) - layout.cell * 1.2
                let a = (1 - k) * (1 - k), b = 2 * (1 - k) * k, cc = k * k
                f.x = a * f.mx + b * ctrlX + cc * f.tx
                f.y = a * f.my + b * ctrlY + cc * f.ty
                f.scale = 1.12 - 0.3 * k
                f.rot = 360 * k
            }
            if f.t >= 1 {
                flying.remove(at: i)
                burstAtMouth(f.state)
            } else {
                i += 1
            }
        }
    }

    /// Marbles gliding through empty cells towards the exit.
    private func updatePaths(_ dt: Float) {
        let speed: Float = 820
        var inHopper = 0
        for m in marbles where m.state == .PHYSICS { inHopper += 1 }
        for m in marbles {
            if m.state != .PATH { continue }
            if m.wait > 0 { m.wait -= dt; continue }
            guard let wp = m.wp else { continue }
            var budget = speed * dt
            let lastIdx = wp.count / 2 - 1
            while budget > 0 && m.wpi * 2 < wp.count {
                // the final hop drops into the hopper: wait in the exit cell while the hopper is full
                if m.wpi == lastIdx && inHopper >= hopperCap { m.wait = 0.06; break }
                let tx = wp[m.wpi * 2], ty = wp[m.wpi * 2 + 1]
                let dx = tx - m.x, dy = ty - m.y
                let d = Kt.sqrt(dx * dx + dy * dy)
                if d <= budget {
                    m.x = tx; m.y = ty; budget -= d; m.wpi += 1
                } else {
                    m.x += dx / d * budget; m.y += dy / d * budget; budget = 0
                }
                m.angle += 8
            }
            if m.wpi * 2 >= wp.count {
                inHopper += 1
                m.state = .PHYSICS
                m.wp = nil
                m.px = m.x; m.py = m.y - 5
            }
        }
    }

    private func physics(_ dt: Float) {
        physicsList.removeAll(keepingCapacity: true)
        for m in marbles where m.state == .PHYSICS { physicsList.append(m) }
        if physicsList.isEmpty { return }
        let sub = 3
        let h = dt / Float(sub)
        let g = 2300 * h * h
        let r = layout.marbleR
        let d2 = 4 * r * r
        let l = layout
        for _ in 0..<sub {
            for m in physicsList {
                let vx = ((m.x - m.px) * 0.995).coerceIn(-9, 9)
                let vy = ((m.y - m.py) * 0.995).coerceIn(-2, 12)
                m.px = m.x; m.py = m.y
                m.x += vx; m.y += vy + g
                m.age += h
                if m.y > l.gridBottom {
                    let f = ((m.y - l.gridBottom) / (l.spoutTop - l.gridBottom)).coerceIn(0, 1)
                    m.x += ((l.cx - m.x) * (0.004 + 0.02 * f)).coerceIn(-0.8, 0.8)
                    if Swift.abs(vx) + Swift.abs(vy) < 0.12 && m.y < l.gateY - 3 {
                        m.stuckT += h
                        if m.stuckT > 0.18 {
                            let nx = ((l.cx - m.x) * 0.25).coerceIn(-6, 6) + (EngineRandom.nextFloat() - 0.5) * 2
                            m.x += nx; m.px += nx
                            m.y += 1.5; m.py += 1.5
                            m.stuckT = 0
                        }
                    } else {
                        m.stuckT = 0
                    }
                }
            }
            for _ in 0..<2 {
                let n = physicsList.count
                for a in 0..<n {
                    let ma = physicsList[a]
                    var b = a + 1
                    while b < n {
                        let mb = physicsList[b]
                        b += 1
                        let dx = mb.x - ma.x, dy = mb.y - ma.y
                        let dd = dx * dx + dy * dy
                        if dd < d2 && dd > 0.0001 {
                            let d = Kt.sqrt(dd)
                            let soft: Float = (ma.y > l.gridBottom + r && mb.y > l.gridBottom + r) ? 0.32 : 0.5
                            let push = (2 * r - d) * soft / d
                            ma.x -= dx * push; ma.y -= dy * push
                            mb.x += dx * push; mb.y += dy * push
                            if push * d > 2.5 && time - lastClack > 0.06 {
                                lastClack = time
                                listener.sound(.CLACK, 0.9 + EngineRandom.nextFloat() * 0.5, 0.22)
                            }
                        }
                    }
                }
                for m in physicsList { walls(m, r) }
            }
        }
        for m in physicsList { m.angle += (m.x - m.px) * 6 }
    }

    private func walls(_ m: Marble, _ r: Float) {
        let l = layout
        if m.y < l.gridBottom { m.x = m.x.coerceIn(l.gridLeft + r, l.gridRight - r) }
        var k = 0
        while k < segs.count {
            let ax = segs[k], ay = segs[k + 1], bx = segs[k + 2], by = segs[k + 3]
            let ex = bx - ax, ey = by - ay
            let len2 = ex * ex + ey * ey
            var t = ((m.x - ax) * ex + (m.y - ay) * ey) / len2
            t = t.coerceIn(0, 1)
            let qx = ax + ex * t, qy = ay + ey * t
            let dx = m.x - qx, dy = m.y - qy
            let dd = dx * dx + dy * dy
            if dd < r * r && dd > 0.0001 {
                let d = Kt.sqrt(dd)
                let pen = r - d
                m.x += dx / d * pen; m.y += dy / d * pen
                if pen > 3 && time - lastClack > 0.08 {
                    lastClack = time
                    listener.sound(.CLACK, 0.8 + EngineRandom.nextFloat() * 0.3, 0.18)
                }
            }
            k += 4
        }
        if m.y > l.gridBottom + 4 {
            let f = ((m.y - l.gridBottom) / (l.spoutTop - l.gridBottom)).coerceIn(0, 1)
            let halfW = (l.gridRight - l.gridLeft) / 2 * (1 - f) + l.spoutHalf * f
            m.x = m.x.coerceIn(l.cx - halfW + r * 0.7, l.cx + halfW - r * 0.7)
        }
        if m.y > l.gateFloor - r { m.y = l.gateFloor - r }
    }

    func slotS(_ i: Int) -> Float { Float(i) * spacing + beltOffset }

    private func countSlots() -> Int {
        var n = 0
        for s in slots where s != nil { n += 1 }
        return n
    }

    private func updateBelt(_ dt: Float) {
        beltVel += (beltDir * beltSpeed - beltVel) * Kt.min(1, dt * 2.5)
        beltOffset = Kt.rem(beltOffset + beltVel * dt, layout.beltLength)
        let l = layout
        var i0 = Kt.roundToInt((-beltOffset) / spacing) % capacity
        if i0 < 0 { i0 += capacity }
        var dist = Kt.rem(slotS(i0), l.beltLength)
        if dist > l.beltLength / 2 { dist -= l.beltLength }
        if dist < -l.beltLength / 2 { dist += l.beltLength }
        if Swift.abs(dist) < spacing * 0.42 && slots[i0] == nil {
            var gate: Marble?
            for m in marbles where m.state == .PHYSICS && Swift.abs(m.x - l.cx) < l.spoutHalf && m.y > l.gateY - 4 {
                if gate == nil || m.y > gate!.y { gate = m }
            }
            if let gate {
                gate.state = .BOARDING
                gate.slot = i0; slots[i0] = gate
                gate.t = 0; gate.dur = 0.12; gate.sx = gate.x; gate.sy = gate.y
                listener.sound(.CLACK, 1.25 + EngineRandom.nextFloat() * 0.2, 0.3)
            }
        }
        for i in 0..<slots.count {
            guard let m = slots[i] else { continue }
            let p = l.beltPoint(slotS(i))
            if m.state == .BOARDING {
                m.t += dt / m.dur
                let k = GameEngine.easeOut(m.t.coerceAtMost(1))
                m.prevX = m.x
                m.x = m.sx + (p.x - m.sx) * k; m.y = m.sy + (p.y - m.sy) * k
                if m.t >= 1 { m.state = .BELT; m.squash = 0.3 }
                continue
            }
            m.prevX = m.x
            m.x = p.x; m.y = p.y
            m.angle += beltVel * dt * 4.8
            m.squash = (m.squash - dt * 2).coerceAtLeast(0)
            if m.y > l.beltCy + l.beltR * 0.3 && m.prevX != m.x {
                for c in 0..<tray.count {
                    let x = l.colCenter(c)
                    if (x - m.prevX) * (x - m.x) <= 0 {
                        guard let cup = tray[c].cups.first else { continue }
                        if accepts(cup, m.color) {
                            cup.reserved += 1
                            slots[i] = nil
                            startDrop(m, c, cup, 0.2)
                            lastDropTime = time
                            break
                        }
                    }
                }
            }
        }
        beltCount = countSlots()
        peakBelt = max(peakBelt, beltCount)
        let wasDanger = danger
        danger = Float(beltCount) >= Float(capacity) * 0.78
        if danger && !wasDanger { listener.sound(.WARNING); listener.haptic(.LIGHT) }
    }

    private func accepts(_ cup: Cup, _ color: Int) -> Bool {
        if cup.popping || cup.reserved >= 3 || cup.display > 0.3 || cup.reveal < 0.5 { return false }
        if color == cup.color { return true }
        if color == MarbleColors.RAINBOW { return need(cup.color) > 0 }
        return false
    }

    private func need(_ k: Int) -> Int {
        var slotsK = 0
        for col in tray { for cup in col.cups where cup.color == k { slotsK += 3 - cup.reserved } }
        for i in 0..<gridTmp.count { gridTmp[i] = 0 }
        board.gridMarbles(&gridTmp)
        var real = gridTmp[k]
        for m in marbles where m.color == k && m.state != .DROPPING { real += 1 }
        for f in flying where f.state.spec.marbleColor == k { real += f.state.spec.marbleCount }
        return slotsK - real
    }

    private func startDrop(_ m: Marble, _ col: Int, _ cup: Cup, _ dur: Float) {
        m.state = .DROPPING
        if m.slot >= 0 && m.slot < slots.count && slots[m.slot] === m { slots[m.slot] = nil }
        m.slot = -1
        m.targetCol = col; m.targetCup = cup; m.targetDimple = cup.reserved - 1
        m.sx = m.x; m.sy = m.y; m.t = 0; m.dur = dur
    }

    private func updateDropping(_ dt: Float) {
        let l = layout
        var i = 0
        while i < marbles.count {
            let m = marbles[i]
            if m.state != .DROPPING { i += 1; continue }
            let cup = m.targetCup!
            m.t += dt / m.dur
            let t = m.t.coerceAtMost(1)
            let tx = l.colCenter(m.targetCol) + l.dimpleDx[m.targetDimple.coerceIn(0, 2)]
            let ty = l.cupTop(cup.display) + l.dimpleDy
            m.x = m.sx + (tx - m.sx) * t
            m.y = m.sy + (ty - m.sy) * t * t - Kt.sin(t * PI_F) * 22
            if m.t >= 1 {
                marbles.remove(at: i)
                cup.arrived += 1
                cup.bounce = 1
                marblesSorted += 1
                listener.sound(.PLINK, 0.95 + 0.13 * Float(cup.arrived - 1) + EngineRandom.nextFloat() * 0.04, 0.8)
                particles.burst(tx, ty, 4, 120, 0xFFFFFFFF, Particles.DOT, 5, 0.3)
                if cup.arrived >= 3 { completeCup(m.targetCol, cup) }
                continue
            }
            i += 1
        }
    }

    private func completeCup(_ col: Int, _ cup: Cup) {
        cup.popping = true; cup.popT = 0
        cupsFilled += 1
        board.cupsDone += 1
        combo = time - lastCupTime < 1.5 ? combo + 1 : 1
        lastCupTime = time
        maxCombo = max(maxCombo, combo)
        let l = layout
        let x = l.colCenter(col), y = l.cupTop(cup.display) + l.cupH / 2
        let argb = MarbleColors.argb[cup.color]
        particles.emit(x, y, 0, 0, 0.45, l.cupW * 0.9, argb, Particles.RING)
        particles.burst(x, y, 10, 260, argb, Particles.STAR, 13, 0.7, -100)
        particles.burst(x, y, 10, 200, 0xFFFFFFFF, Particles.DOT, 6, 0.5)
        listener.sound(.CUP_COMPLETE, 1 + Float(min(combo - 1, 6)) * 0.06)
        listener.haptic(.LIGHT)
        if combo >= 2 {
            if combo >= 3 { comboCoins += combo - 2 }
            listener.combo(combo)
            listener.sound(.COMBO, 1 + Float(min(combo - 2, 8)) * 0.07, 0.8)
            texts.append(FloatingText("x\(combo)", x, y - 30, 0xFFFFE27A, 34))
        }
        refreshBlockStates()
    }

    private func updateCups(_ dt: Float) {
        for (ci, col) in tray.enumerated() {
            var i = 0
            while i < col.cups.count {
                let cup = col.cups[i]
                if cup.popping {
                    cup.popT += dt
                    if cup.popT >= 0.42 { col.cups.remove(at: i); continue }
                }
                i += 1
            }
            let go: Float = introT < GameEngine.INTRO_MACHINE + 0.15 + Float(ci) * 0.08 ? 0 : 1
            for (idx, cup) in col.cups.enumerated() {
                let target = Float(idx)
                let acc = (target - cup.display) * 170 - cup.vel * 15
                cup.vel += acc * dt * go
                cup.display += cup.vel * dt * go
                if Swift.abs(cup.display - target) < 0.002 && Swift.abs(cup.vel) < 0.01 { cup.display = target; cup.vel = 0 }
                cup.bounce = (cup.bounce - dt * 4).coerceAtLeast(0)
                cup.shuffleT = (cup.shuffleT - dt * 2).coerceAtLeast(0)
                if idx == 0 && cup.hidden && !cup.revealing && cup.display < 0.5 {
                    cup.revealing = true
                    listener.sound(.STAR, 1.2, 0.5)
                }
                if cup.revealing {
                    cup.reveal = (cup.reveal + dt * 3).coerceAtMost(1)
                    if cup.reveal >= 1 { cup.hidden = false; cup.revealing = false }
                }
            }
        }
    }

    // ============================================================ end conditions

    private func endWith(_ s: GameStatus, _ reason: FailReason, _ delay: Float) {
        if pendingEnd >= 0 { return }
        pendingStatus = s; failReason = reason; pendingEnd = delay
    }

    private func checkEnd(_ dt: Float) {
        if status != .PLAYING { return }
        if pendingEnd >= 0 {
            pendingEnd -= dt
            if pendingEnd < 0 {
                status = pendingStatus
                if status == .WON { celebrate() }
                listener.statusChanged(status)
            }
            return
        }
        if board.isEmpty && marbles.isEmpty && flying.isEmpty && tray.allSatisfy({ $0.cups.isEmpty }) {
            endWith(.WON, .JAM, 0.35)
            return
        }
        var waiting = 0
        var anyDropping = false
        for m in marbles {
            if m.state == .PHYSICS || m.state == .PATH { waiting += 1 }
            if m.state == .DROPPING || m.state == .BOARDING { anyDropping = true }
        }
        let sinceDrop = time - lastDropTime
        if beltCount >= capacity && waiting > 0 && !anyDropping && sinceDrop > lapTime * 1.1 {
            listener.sound(.FAIL)
            endWith(.FAILED, .JAM, 0.2)
            return
        }
        if beltCount >= capacity && !anyDropping && sinceDrop > lapTime * 1.3 {
            endWith(.FAILED, .JAM, 0.2)
            return
        }
        if !inIntro && waiting == 0 && !anyDropping && flying.isEmpty && !board.hasTappable() &&
            (beltCount > 0 || !board.isEmpty) && sinceDrop > lapTime * 1.25 {
            endWith(.FAILED, .NO_MOVES, 0.2)
        }
    }

    private func celebrate() {
        let colors: [UInt32] = [0xFFFF4D5E, 0xFFFFD23F, 0xFF33C8F5, 0xFF3CCB5A, 0xFF9B5CFF, 0xFFFF7AC8]
        for it in 0..<110 {
            let left = it % 2 == 0
            let x: Float = left ? -10 : layout.worldW + 10
            let y = layout.worldH * 0.62
            let vx = Float(left ? 1 : -1) * (250 + EngineRandom.nextFloat() * 520)
            let vy = -(700 + EngineRandom.nextFloat() * 700)
            particles.emit(x, y, vx, vy, 2.6 + EngineRandom.nextFloat(), 14 + EngineRandom.nextFloat() * 10, colors[it % colors.count],
                           Particles.CONFETTI, 700, (EngineRandom.nextFloat() - 0.5) * 900)
        }
        listener.haptic(.SUCCESS)
    }

    // ============================================================ results & hints

    var stars: Int {
        let ratio = Float(peakBelt) / Float(capacity)
        var s = ratio <= 0.62 ? 3 : (ratio <= 0.86 ? 2 : 1)
        if boostersUsed > 0 { s = min(s, 2) }
        if continued { s = 1 }
        return s
    }

    func coinReward() -> Int {
        (10 + spec.number / 40).coerceAtMost(60) + stars * 3 + comboCoins + (spec.isBoss ? 25 : 0)
    }

    /// World centre of a suggested block to tap (tutorial hand).
    func hintTarget() -> [Float]? {
        for id in spec.plan {
            let i = board.locate(id)
            if i < 0 { continue }
            if board.canTap(i) {
                guard let v = visuals[i] else { continue }
                return [layout.cellCenterX(v.col), layout.cellCenterY(Float(v.row) + v.dropY)]
            }
        }
        return nil
    }

    static let INTRO_MACHINE: Float = 0.55
    static func easeOut(_ t: Float) -> Float { 1 - (1 - t) * (1 - t) }
}
