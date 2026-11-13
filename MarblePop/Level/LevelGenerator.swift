import Foundation
import GameKit

/// Deterministic level factory. Level N is always identical on every device (and identical to Android:
/// `java.util.Random` → `JavaRandom`, Kotlin `shuffled(rnd)` → `javaShuffled`).
/// Levels 1–30 follow a hand-tuned recipe table, later levels come from a difficulty curve.
///
/// Every level is built from a planned solution: blocks are removed one by one, each only when it
/// has a free path to the exit (same rule as the game). Cups and belt capacity are derived from that
/// plan, so every level is solvable by construction (verified for all 5000 levels in unit tests).
enum LevelGenerator {
    static let MAX_LEVEL = 5000
    static let THEME_COUNT = 5
    private static let MAX_CAPACITY = 48
    private static let MIN_CAPACITY = 14

    final class Recipe {
        let heights: [Int]
        let colors: Int
        let trayCols: Int
        let window: Int
        let margin: Int
        let features: [Feature: Int]
        let boss: Bool
        let holes: Int
        let walls: Int

        init(_ heights: [Int], _ colors: Int, _ trayCols: Int, _ window: Int, _ margin: Int, _ features: [Feature: Int],
             _ boss: Bool = false, holes: Int = 0, walls: Int = 0) {
            self.heights = heights
            self.colors = colors
            self.trayCols = trayCols
            self.window = window
            self.margin = margin
            self.features = features
            self.boss = boss
            self.holes = holes
            self.walls = walls
        }
    }

    // LRU of the last 12 levels (Kotlin: access-ordered LinkedHashMap + removeEldestEntry), thread-safe.
    private static let lock = NSLock()
    private static var cacheOrder: [Int] = []
    private static var cache: [Int: LevelSpec] = [:]

    static func get(_ n: Int) -> LevelSpec {
        let key = n.coerceIn(1, MAX_LEVEL)
        lock.lock(); defer { lock.unlock() }
        if let hit = cache[key] {
            if let i = cacheOrder.firstIndex(of: key) { cacheOrder.remove(at: i) }
            cacheOrder.append(key)
            return hit
        }
        let spec = generate(key)
        cache[key] = spec
        cacheOrder.append(key)
        if cacheOrder.count > 12 { cache[cacheOrder.removeFirst()] = nil }
        return spec
    }

    static func themeFor(_ n: Int) -> Int { ((n - 1) / 25) % THEME_COUNT }

    static func isBoss(_ n: Int) -> Bool { n % 50 == 0 }

    static func generate(_ n: Int) -> LevelSpec {
        for attempt in 0..<14 {
            let rnd = JavaRandom(Int64(n) &* 7919 &+ 104729 &* Int64(attempt) &+ 17)
            let recipe = recipeFor(n, rnd, attempt)
            if let spec = build(n, recipe, rnd) { return spec }
        }
        let rnd = JavaRandom(Int64(n))
        return build(n, Recipe([3, 3, 3, 3], 3, 4, 0, 14, [:]), rnd)!
    }

    // ---------------------------------------------------------------- recipes

    private static func r(_ h: String, _ c: Int, _ w: Int, _ m: Int, _ f: (Feature, Int)..., holes: Int = 0, k: Int = 4) -> Recipe {
        var map: [Feature: Int] = [:]
        for (key, v) in f { map[key] = v }
        let heights = h.split(separator: ",").map { Int($0.trimmingCharacters(in: .whitespaces))! }
        return Recipe(heights, c, k, w, m, map, holes: holes)
    }

    private static let handmade: [Recipe] = [
        r("2,2,2", 2, 0, 22),
        r("2,2,2,2", 2, 0, 20),
        r("3,3,3", 3, 1, 18, holes: 1),
        r("2,3,3,2", 3, 1, 16, holes: 1),
        r("3,3,3,3", 3, 2, 14, holes: 2),
        r("3,4,4,3", 3, 2, 14, (.MYSTERY, 3), holes: 1),
        r("4,4,4,4", 4, 2, 13, (.MYSTERY, 3), holes: 2),
        r("3,3,3,3,3", 4, 2, 13, (.COUNTER, 2), holes: 1),
        r("4,3,4,3,4", 4, 3, 12, (.MYSTERY, 2), (.COUNTER, 1), holes: 2),
        r("4,4,4,4,4", 4, 3, 12, (.MYSTERY, 3), holes: 2),
        r("3,4,5,4,3", 4, 3, 12, (.HIDDEN_CUP, 4), holes: 2),
        r("5,4,3,4,5", 5, 3, 12, (.MYSTERY, 2), (.HIDDEN_CUP, 3), holes: 2),
        r("4,4,4,4,4", 5, 4, 11, (.COUNTER, 2), (.HIDDEN_CUP, 3), holes: 2),
        r("2,4,6,4,2", 5, 3, 12, (.MYSTERY, 3), (.COUNTER, 1), holes: 2),
        r("4,4,4,4,4", 4, 2, 13, (.KEY, 1), holes: 1),
        r("5,5,0,5,5", 5, 3, 12, (.KEY, 1), (.MYSTERY, 2), holes: 2),
        r("4,5,5,5,4", 5, 4, 11, (.HIDDEN_CUP, 4), (.COUNTER, 2), holes: 2),
        r("3,4,5,5,4,3", 5, 4, 11, (.KEY, 1), (.MYSTERY, 3), holes: 3),
        r("5,5,5,5,5", 6, 4, 11, (.COUNTER, 2), (.HIDDEN_CUP, 3), holes: 3),
        r("4,4,4,4,4", 5, 3, 12, (.ARROW, 4), holes: 1),
        r("5,3,5,3,5", 5, 4, 11, (.ARROW, 3), (.MYSTERY, 2), holes: 2),
        r("4,5,6,5,4", 6, 4, 11, (.KEY, 1), (.ARROW, 2), holes: 3),
        r("6,5,4,4,5,6", 6, 4, 10, (.COUNTER, 2), (.HIDDEN_CUP, 4), holes: 3),
        r("5,5,5,5,5,5", 6, 5, 10, (.MYSTERY, 4), (.ARROW, 2), holes: 3),
        r("4,4,4,4,4", 5, 3, 12, (.CRATE, 2), holes: 2),
        r("5,6,6,5", 5, 4, 11, (.CRATE, 1), (.KEY, 1), holes: 2),
        r("3,5,7,5,3", 6, 5, 10, (.ARROW, 2), (.CRATE, 1), (.MYSTERY, 2), holes: 3),
        r("5,5,5,5,5,5", 6, 4, 10, (.COUNTER, 2), (.HIDDEN_CUP, 4), holes: 3),
        r("6,4,6,4,6", 6, 5, 10, (.KEY, 1), (.MYSTERY, 3), (.CRATE, 1), holes: 3),
        r("4,5,5,5,4", 5, 3, 12, (.DOUBLE, 2), holes: 2),
    ]

    private static func recipeFor(_ n: Int, _ rnd: JavaRandom, _ attempt: Int) -> Recipe {
        if n <= handmade.count { return handmade[n - 1] }
        let boss = isBoss(n)
        let intro = Feature.introducedAt(n)
        let base = 1.0 - Foundation.exp(Double(-(n - 30)) / 700.0)
        let saw = [0.0, 0.05, 0.1, 0.16, -0.08][n % 5]
        var d = 0.22 + 0.68 * base + saw + (boss ? 0.18 : 0.0) + (n % 10 == 7 ? 0.08 : 0.0)
        if intro != nil { d -= 0.15 }
        d = (d - Double(attempt) * 0.06).coerceIn(0.05, 1.0)

        let target = Kt.roundToInt(12 + d * 26 + Double(rnd.nextInt(5)) - 2).coerceIn(9, 40)
        let w = Kt.roundToInt((Double(target) * 1.15).squareRoot()).coerceIn(4, 7)
        let h = Kt.toInt((Double(target) / Double(w)).rounded(.up)).coerceIn(2, 7)
        let heights = shape(rnd, w, h)
        let cellsCount = heights.reduce(0, +)
        let colors = (3 + Kt.roundToInt(d * 5.5) + rnd.nextInt(3) - 1).coerceIn(3, min(9, cellsCount - 2))
        let trayCols = n < 45 ? 4 : (rnd.nextDouble() < 0.25 + 0.45 * d ? 5 : 4)
        let window = Kt.roundToInt(1 + d * 7)
        let margin = Kt.roundToInt(14 - d * 11).coerceAtLeast(3) - (boss ? 1 : 0)
        let holes = (1 + rnd.nextInt(2 + cellsCount / 10)).coerceAtMost(cellsCount / 4)
        let walls = (n > 40 && rnd.nextDouble() < 0.3 + 0.4 * d) ? 1 + rnd.nextInt(2) : 0

        var features: [Feature: Int] = [:]
        let unlocked = Feature.allCases.filter { $0.unlockLevel <= n }
        let maxTypes = 1 + Kt.roundToInt(d * 3)
        for f in unlocked.javaShuffled(rnd) {
            if features.count >= maxTypes { break }
            let p = (0.32 + 0.45 * d) * weight(f)
            if rnd.nextDouble() < p { features[f] = countFor(f, d, rnd) }
        }
        if let intro { features[intro] = max(features[intro] ?? 0, intro == .KEY ? 1 : 2) }
        return Recipe(heights, colors, trayCols, window, margin, features, boss, holes: holes, walls: walls)
    }

    private static func weight(_ f: Feature) -> Double {
        switch f {
        case .MYSTERY, .HIDDEN_CUP: return 1.2
        case .BOMB, .SWITCH, .RAINBOW: return 0.6
        default: return 0.9
        }
    }

    private static func countFor(_ f: Feature, _ d: Double, _ rnd: JavaRandom) -> Int {
        switch f {
        case .KEY, .PAINT: return 1 + ((d > 0.7 && rnd.nextBoolean()) ? 1 : 0)
        case .BOMB, .SWITCH, .RAINBOW: return 1
        case .DOUBLE: return 1 + rnd.nextInt(2)
        case .MYSTERY, .HIDDEN_CUP: return 2 + rnd.nextInt(2 + Kt.toInt(d * 4))
        default: return 1 + rnd.nextInt(1 + Kt.toInt(d * 2.5))
        }
    }

    private static func shape(_ rnd: JavaRandom, _ w: Int, _ h: Int) -> [Int] {
        let mid = Double(w - 1) / 2.0
        var out: [Int]
        switch rnd.nextInt(11) {
        case 0: out = (0..<w).map { _ in h }
        case 1: out = (0..<w).map { h - Kt.roundToInt(Swift.abs(Double($0) - mid) * 0.9) }
        case 2: out = (0..<w).map { h - 2 + Kt.roundToInt(Swift.abs(Double($0) - mid) * 0.9) }
        case 3: out = (0..<w).map { h - (w - 1 - $0) * 2 / max(1, w - 1) - (w - 1 - $0) / 2 }
        case 4: out = (0..<w).map { h - $0 * 2 / max(1, w - 1) - $0 / 2 }
        case 5: out = (0..<w).map { $0 % 2 == 0 ? h : h - 2 }
        case 6: out = (0..<w).map { $0 % 2 == 0 ? h : h - 1 }
        case 7: out = (0..<w).map { ($0 == 1 || $0 == w - 2) ? h : h - 2 }
        case 8: out = (0..<w).map { (w >= 5 && w % 2 == 1 && $0 == w / 2) ? 0 : h }
        case 9: out = (0..<w).map { ($0 == 0 || $0 == w - 1) ? h : h - 1 }
        default:
            var cur = h
            out = []
            out.reserveCapacity(w)
            for _ in 0..<w {
                cur = (cur + rnd.nextInt(3) - 1).coerceIn(max(2, h - 3), h)
                out.append(cur)
            }
        }
        for i in 0..<out.count where out[i] != 0 { out[i] = out[i].coerceIn(1, 7) }
        if out.max()! < h { out[rnd.nextInt(w)] = h }
        return out
    }

    /// All active cells must reach the bottom row through active cells.
    private static func connected(_ w: Int, _ h: Int, _ mask: [Bool]) -> Bool {
        var seen = [Bool](repeating: false, count: w * h)
        var q: [Int] = []
        var head = 0
        for c in 0..<w where mask[c] { seen[c] = true; q.append(c) }
        while head < q.count {
            let i = q[head]; head += 1
            let c = i % w, r = i / w
            for k in 0..<4 {
                let nc = c + Board.DC[k], nr = r + Board.DR[k]
                if nc < 0 || nc >= w || nr < 0 || nr >= h { continue }
                let n = nr * w + nc
                if mask[n] && !seen[n] { seen[n] = true; q.append(n) }
            }
        }
        for i in 0..<mask.count where mask[i] && !seen[i] { return false }
        return true
    }

    // ---------------------------------------------------------------- builder

    private final class Slot {
        let index: Int
        let col: Int
        let row: Int
        var kind = BlockKind.NORMAL
        var color = 0
        var param = 0
        var id = 0
        var startsOpen = false

        init(_ index: Int, _ col: Int, _ row: Int) {
            self.index = index
            self.col = col
            self.row = row
        }
    }

    private static func build(_ n: Int, _ recipe: Recipe, _ rnd: JavaRandom) -> LevelSpec? {
        let heights = recipe.heights
        let w = heights.count
        let h = heights.max()!
        if h <= 0 { return nil }
        var mask = (0..<(w * h)).map { i in (i / w) < heights[i % w] }
        // inner walls (never in the bottom row, never disconnecting the shape)
        for _ in 0..<max(0, recipe.walls) {
            let cands = (0..<mask.count).filter { mask[$0] && $0 / w >= 1 && $0 / w < h - 1 }
            if cands.isEmpty { continue }
            let i = cands[rnd.nextInt(cands.count)]
            mask[i] = false
            if !connected(w, h, mask) { mask[i] = true }
        }
        if !connected(w, h, mask) { return nil }
        let activeCells = (0..<mask.count).filter { mask[$0] }
        // initial empty slots
        var empty = Set<Int>()
        let holeCands = activeCells.javaShuffled(rnd)
        for i in holeCands {
            if empty.count >= recipe.holes { break }
            empty.insert(i)
        }
        let slots = activeCells.filter { !empty.contains($0) }.map { Slot($0, $0 % w, $0 / w) }
        let total = slots.count
        if total < 2 { return nil }
        var isSlot = [Bool](repeating: false, count: w * h)
        for s in slots { isSlot[s.index] = true }

        // 1. Planned removal order under the real rule (path to exit).
        let dummyCells: [BlockSpec?] = (0..<(w * h)).map { i in isSlot[i] ? BlockSpec(i + 1, 0) : nil }
        let dummy = LevelSpec(number: n, width: w, height: h, mask: mask, cells: dummyCells, tray: [], capacity: 99,
                              theme: 0, colorCount: 1, isBoss: false, plan: [], introduces: nil)
        let planBoard = Board(dummy)
        for s in slots { s.startsOpen = planBoard.exposed[s.index] }
        var order: [Slot] = []
        order.reserveCapacity(total)
        while order.count < total {
            let open = slots.filter { planBoard.cells[$0.index] != nil && planBoard.exposed[$0.index] }
            if open.isEmpty { return nil }
            // favour lower blocks a little so plans feel natural (Kotlin minByOrNull: a single
            // candidate is returned without calling the selector, ties keep the first)
            var pick = open[0]
            if open.count > 1 {
                var best = Double(pick.row) + rnd.nextDouble() * 2.5
                for j in 1..<open.count {
                    let v = Double(open[j].row) + rnd.nextDouble() * 2.5
                    if best > v { pick = open[j]; best = v }
                }
            }
            order.append(pick)
            planBoard.tap(pick.index, force: true)
        }
        for (i, s) in order.enumerated() { s.id = i + 1 }

        // 2. Colours.
        let colorCount = recipe.colors.coerceIn(2, min(9, total))
        let paletteChoices = (0..<MarbleColors.COUNT).filter { n >= 60 || $0 < 8 }.javaShuffled(rnd)
        let palette = Array(paletteChoices.prefix(colorCount))
        var colorSeq: [Int] = []
        colorSeq.reserveCapacity(total)
        colorSeq.append(contentsOf: palette)
        while colorSeq.count < total { colorSeq.append(palette[rnd.nextInt(colorCount)]) }
        colorSeq.javaShuffle(rnd)
        for (i, s) in order.enumerated() { s.color = colorSeq[i] }

        // 3. Special kinds, consistent with the plan.
        let f = recipe.features
        func free(_ pred: (Int, Slot) -> Bool) -> [Int] {
            (0..<order.count).filter { order[$0].kind == .NORMAL && pred($0, order[$0]) }
        }

        var lockId = 0
        for _ in 0..<(f[.KEY] ?? 0) {
            let keyCands = free { i, _ in i < total - 2 && Double(i) < Double(total) * 0.6 }
            if keyCands.isEmpty { continue }
            let k = keyCands[rnd.nextInt(keyCands.count)]
            let shuffledChained = free { i, _ in i > k + 1 }.javaShuffled(rnd)
            let chained = Array(shuffledChained.prefix(1 + rnd.nextInt(3)))
            if chained.isEmpty { continue }
            order[k].kind = .KEY; order[k].param = lockId
            for c in chained { order[c].kind = .CHAINED; order[c].param = lockId }
            lockId += 1
        }
        var bucketId = 0
        for _ in 0..<(f[.PAINT] ?? 0) {
            let cands = free { i, _ in i < total - 2 && Double(i) < Double(total) * 0.6 }
            if cands.isEmpty { continue }
            let p = cands[rnd.nextInt(cands.count)]
            let bucket = order[p]
            let nearShuffled = free { i, s in i > p + 1 && Swift.abs(s.col - bucket.col) + Swift.abs(s.row - bucket.row) <= 2 }.javaShuffled(rnd)
            var grays = Array(nearShuffled.prefix(1 + rnd.nextInt(3)))
            if grays.isEmpty { grays = Array(free { i, _ in i > p + 1 }.javaShuffled(rnd).prefix(2)) }
            if grays.isEmpty { continue }
            bucket.kind = .PAINT; bucket.param = bucketId
            for g in grays { order[g].kind = .GRAY; order[g].param = bucketId; order[g].color = bucket.color }
            bucketId += 1
        }
        func assign(_ feature: Feature, _ kind: BlockKind, _ pred: (Int, Slot) -> Bool = { _, _ in true }) {
            for i in free(pred).javaShuffled(rnd).prefix(f[feature] ?? 0) { order[i].kind = kind }
        }
        assign(.DOUBLE, .DOUBLE)
        if colorCount >= 2 { assign(.RAINBOW, .RAINBOW) }
        assign(.ICE, .ICE)
        assign(.MYSTERY, .MYSTERY) { _, s in !s.startsOpen }
        assign(.COUNTER, .COUNTER) { i, _ in i >= 1 }
        assign(.CRATE, .CRATE) { i, _ in i >= 2 }
        assign(.BOMB, .BOMB) { i, _ in i >= 2 && i < total - 1 }
        assign(.SWITCH, .SWITCH)
        if let cnt = f[.ARROW] {
            for i in free({ _, s in !s.startsOpen }).javaShuffled(rnd).prefix(cnt) {
                order[i].kind = .ARROW
                order[i].param = rnd.nextInt(3)
            }
        }

        // 4. Tray cups from the plan, perturbed by the difficulty window.
        var cups: [Int] = []
        for s in order { for _ in 0..<(s.kind == .DOUBLE ? 6 : 3) { cups.append(s.color) } }
        for attemptWindow in stride(from: recipe.window, through: 0, by: -1) {
            var seq = cups
            if attemptWindow > 0 {
                for i in 0..<seq.count {
                    let j = (i + rnd.nextInt(attemptWindow + 1)).coerceAtMost(seq.count - 1)
                    let t = seq[i]; seq[i] = seq[j]; seq[j] = t
                }
            }
            var trayCols = [[CupSpec]](repeating: [], count: recipe.trayCols)
            for color in seq {
                var minLen = Int.max
                for col in trayCols { minLen = min(minLen, col.count) }
                let opts = (0..<trayCols.count).filter { trayCols[$0].count <= minLen + 1 }
                trayCols[opts[rnd.nextInt(opts.count)]].append(CupSpec(color))
            }
            let hiddenCount = f[.HIDDEN_CUP] ?? 0
            if hiddenCount > 0 {
                var cands: [(Int, Int)] = []
                for (c, col) in trayCols.enumerated() { for i in col.indices where i > 0 { cands.append((c, i)) } }
                for (c, i) in cands.javaShuffled(rnd).prefix(hiddenCount) { trayCols[c][i] = trayCols[c][i].copy(hidden: true) }
            }

            // 5. Timeline with timers open.
            var planIds: [Int] = []
            for s in order {
                if s.kind == .ICE { planIds.append(s.id) }
                planIds.append(s.id)
            }
            let timelineSpec = makeSpec(n, recipe, w, h, mask, slots, trayCols, 999, planIds, colorCount, openTimers: true)
            let sim = PuzzleSim(timelineSpec)
            var popsBefore: [Int: Int] = [:]
            var movesBefore: [Int: Int] = [:]
            var cupsBefore: [Int: Int] = [:]
            var ok = true
            for id in planIds {
                popsBefore[id] = sim.board.pops
                movesBefore[id] = sim.board.moves
                cupsBefore[id] = sim.board.cupsDone
                if !sim.tapId(id) { ok = false; break }
            }
            if !ok || !sim.solved { continue }

            // 6. Timer parameters derived from the plan.
            for s in order {
                switch s.kind {
                case .COUNTER:
                    let p = popsBefore[s.id]!
                    if p < 1 { s.kind = .NORMAL } else { s.param = 1 + rnd.nextInt(min(p, 6)) }
                case .CRATE:
                    let c = cupsBefore[s.id]!
                    if c < 1 { s.kind = .NORMAL } else { s.param = max(1, c - rnd.nextInt(min(c, 4))) }
                case .BOMB:
                    s.param = movesBefore[s.id]! + 2 + rnd.nextInt(3)
                default:
                    break
                }
            }

            // 7. Verify and size the belt.
            let spec0 = makeSpec(n, recipe, w, h, mask, slots, trayCols, 999, planIds, colorCount, openTimers: false)
            let verify = PuzzleSim(spec0)
            var allOk = true
            for id in planIds where !verify.tapId(id) { allOk = false; break }
            if !allOk || !verify.solved { continue }
            let peak = verify.peakLoad
            if peak + 2 > MAX_CAPACITY { continue }
            let capacity = (peak + recipe.margin).coerceIn(max(MIN_CAPACITY, peak + 2), MAX_CAPACITY)
            return makeSpec(n, recipe, w, h, mask, slots, trayCols, capacity, planIds, colorCount, openTimers: false)
        }
        return nil
    }

    private static func makeSpec(
        _ n: Int, _ recipe: Recipe, _ w: Int, _ h: Int, _ mask: [Bool], _ slots: [Slot], _ tray: [[CupSpec]],
        _ capacity: Int, _ plan: [Int], _ colorCount: Int, openTimers: Bool
    ) -> LevelSpec {
        var cells = [BlockSpec?](repeating: nil, count: w * h)
        for s in slots {
            let timer = s.kind == .COUNTER || s.kind == .CRATE || s.kind == .BOMB
            cells[s.index] = BlockSpec(s.id, s.color, (openTimers && timer) ? .NORMAL : s.kind, s.param)
        }
        return LevelSpec(
            number: n, width: w, height: h, mask: mask, cells: cells,
            tray: tray, capacity: capacity, theme: themeFor(n), colorCount: colorCount,
            isBoss: recipe.boss, plan: plan, introduces: Feature.introducedAt(n)
        )
    }
}
