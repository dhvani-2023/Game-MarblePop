import Foundation

final class BlockState {
    let spec: BlockSpec
    var id: Int { spec.id }
    var cracked = false
    var revealed: Bool

    init(_ spec: BlockSpec) {
        self.spec = spec
        self.revealed = spec.kind != .MYSTERY
    }
}

enum TapOutcome: Int { case NONE, CRACK, POP }

/// Grid rules shared by the real-time engine, the level generator and the unit tests.
///
/// Blocks never move. A block is *open* (tappable) when it sits in the bottom row or touches an
/// empty cell that is connected through empty cells to the bottom row — its marbles flow out along
/// that path into the hopper. Arrow blocks may alternatively leave straight in their arrow direction.
final class Board {
    let spec: LevelSpec
    let w: Int
    let h: Int
    let mask: [Bool]
    private(set) var cells: [BlockState?]

    private(set) var pops = 0
    private(set) var moves = 0
    var cupsDone = 0
    var bombBonus = 0
    private(set) var openLocks = Set<Int>()
    private(set) var paintedBuckets = Set<Int>()

    /// Empty cells that connect to the exit.
    private var reach: [Bool]
    /// Block cells with a free path to the exit.
    private(set) var exposed: [Bool]
    private var queue: [Int]
    private var parent: [Int]

    init(_ spec: LevelSpec) {
        self.spec = spec
        w = spec.width
        h = spec.height
        mask = spec.mask
        cells = spec.cells.map { $0.map { BlockState($0) } }
        let n = spec.width * spec.height
        reach = [Bool](repeating: false, count: n)
        exposed = [Bool](repeating: false, count: n)
        queue = [Int](repeating: 0, count: n)
        parent = [Int](repeating: 0, count: n)
        refresh()
    }

    @inline(__always) func idx(_ c: Int, _ r: Int) -> Int { r * w + c }
    @inline(__always) func col(_ i: Int) -> Int { i % w }
    @inline(__always) func row(_ i: Int) -> Int { i / w }
    @inline(__always) func active(_ c: Int, _ r: Int) -> Bool { c >= 0 && c < w && r >= 0 && r < h && mask[r * w + c] }
    func blockAt(_ c: Int, _ r: Int) -> BlockState? { (c >= 0 && c < w && r >= 0 && r < h) ? cells[r * w + c] : nil }

    var isEmpty: Bool {
        for b in cells where b != nil { return false }
        return true
    }

    func locate(_ id: Int) -> Int {
        for i in 0..<cells.count where cells[i]?.id == id { return i }
        return -1
    }

    /// Recomputes reachability after the grid changed.
    func refresh() {
        for i in 0..<reach.count { reach[i] = false }
        var head = 0, tail = 0
        for c in 0..<w {
            let i = idx(c, 0)
            if mask[i] && cells[i] == nil { reach[i] = true; queue[tail] = i; tail += 1 }
        }
        while head < tail {
            let i = queue[head]; head += 1
            let c = col(i), r = row(i)
            for k in 0..<4 {
                let nc = c + Board.DC[k], nr = r + Board.DR[k]
                if !active(nc, nr) { continue }
                let n = idx(nc, nr)
                if !reach[n] && cells[n] == nil { reach[n] = true; queue[tail] = n; tail += 1 }
            }
        }
        for i in 0..<cells.count {
            guard let b = cells[i] else { exposed[i] = false; continue }
            let c = col(i), r = row(i)
            var open = r == 0
            if !open {
                for k in 0..<4 {
                    let nc = c + Board.DC[k], nr = r + Board.DR[k]
                    if active(nc, nr) && reach[idx(nc, nr)] { open = true; break }
                }
            }
            exposed[i] = open
            if open { b.revealed = true }
        }
    }

    func isLocked(_ b: BlockState) -> Bool {
        switch b.spec.kind {
        case .CHAINED: return !openLocks.contains(b.spec.param)
        case .GRAY: return !paintedBuckets.contains(b.spec.param)
        case .COUNTER: return pops < b.spec.param
        case .CRATE: return cupsDone < b.spec.param
        default: return false
        }
    }

    func counterRemaining(_ b: BlockState) -> Int {
        switch b.spec.kind {
        case .COUNTER: return (b.spec.param - pops).coerceAtLeast(0)
        case .CRATE: return (b.spec.param - cupsDone).coerceAtLeast(0)
        case .BOMB: return (b.spec.param + bombBonus - moves).coerceAtLeast(0)
        default: return 0
        }
    }

    /// Straight exit for arrow blocks: every cell in the arrow direction is empty until the board edge.
    func arrowFree(_ i: Int) -> Bool {
        guard let b = cells[i] else { return false }
        if b.spec.kind != .ARROW { return false }
        let dc: Int
        switch b.spec.param { case 0: dc = -1; case 1: dc = 1; default: dc = 0 }
        let dr = b.spec.param == 2 ? 1 : 0
        var c = col(i) + dc, r = row(i) + dr
        while active(c, r) {
            if cells[idx(c, r)] != nil { return false }
            c += dc; r += dr
        }
        return true
    }

    /// True if the block has some way out (path or arrow), ignoring locks.
    func hasExit(_ i: Int) -> Bool { exposed[i] || arrowFree(i) }

    func canTap(_ i: Int) -> Bool {
        guard i >= 0 && i < cells.count, let b = cells[i] else { return false }
        return !isLocked(b) && hasExit(i)
    }

    /// Cells the marbles travel through, from the block's own cell to an exit cell in the bottom row.
    /// Returns nil when the block can only leave by its arrow.
    func pathOut(_ i: Int) -> [Int]? {
        if row(i) == 0 { return [i] }
        for k in 0..<parent.count { parent[k] = -2 }
        var head = 0, tail = 0
        queue[tail] = i; tail += 1; parent[i] = -1
        while head < tail {
            let cur = queue[head]; head += 1
            if cur != i && row(cur) == 0 {
                var out: [Int] = []
                var p = cur
                while p != -1 { out.append(p); p = parent[p] }
                out.reverse()
                return out
            }
            let c = col(cur), r = row(cur)
            for k in Board.DOWN_FIRST {
                let nc = c + Board.DC[k], nr = r + Board.DR[k]
                if !active(nc, nr) { continue }
                let n = idx(nc, nr)
                if parent[n] != -2 || cells[n] != nil { continue }
                parent[n] = cur; queue[tail] = n; tail += 1
            }
        }
        return nil
    }

    /// Applies a tap on cell i. Returns POP when the block left the board.
    @discardableResult
    func tap(_ i: Int, force: Bool = false) -> TapOutcome {
        guard i >= 0 && i < cells.count, let b = cells[i] else { return .NONE }
        if !force && !canTap(i) { return .NONE }
        moves += 1
        if !force && b.spec.kind == .ICE && !b.cracked {
            b.cracked = true
            return .CRACK
        }
        cells[i] = nil
        pops += 1
        switch b.spec.kind {
        case .KEY: openLocks.insert(b.spec.param)
        case .PAINT: paintedBuckets.insert(b.spec.param)
        default: break
        }
        refresh()
        return .POP
    }

    func bombExpired() -> Bool {
        for case let b? in cells where b.spec.kind == .BOMB && moves >= b.spec.param + bombBonus { return true }
        return false
    }

    func hasTappable() -> Bool {
        for i in 0..<cells.count where canTap(i) { return true }
        return false
    }

    /// Real (non-rainbow) marbles still on the board, per colour.
    func gridMarbles(_ out: inout [Int]) {
        for case let b? in cells where b.spec.kind != .RAINBOW { out[b.spec.color] += b.spec.marbleCount }
    }

    // left, right, down, up
    static let DC = [-1, 1, 0, 0]
    static let DR = [0, 0, -1, 1]
    private static let DOWN_FIRST = [2, 0, 1, 3]
}

/// Cup columns for the discrete simulation.
final class TraySim {
    final class Cup {
        let color: Int
        var filled = 0
        init(_ color: Int) { self.color = color }
    }

    var columns: [[Cup]]

    init(_ spec: LevelSpec) {
        columns = spec.tray.map { col in col.map { Cup($0.color) } }
    }

    func slotsRemaining(_ out: inout [Int]) {
        for col in columns { for cup in col { out[cup.color] += 3 - cup.filled } }
    }

    var isEmpty: Bool {
        for col in columns where !col.isEmpty { return false }
        return true
    }
}

/// Discrete, idealised simulation of a level: every marble that can go to a top cup goes there instantly.
/// Used by the generator to size the belt and by tests to prove every level is solvable.
final class PuzzleSim {
    let spec: LevelSpec
    let board: Board
    let tray: TraySim
    var belt = [Int](repeating: 0, count: MarbleColors.COUNT)
    var rainbow = 0
    private(set) var peakLoad = 0
    var load: Int { belt.reduce(0, +) + rainbow }
    private var tmpA = [Int](repeating: 0, count: MarbleColors.COUNT)
    private var tmpB = [Int](repeating: 0, count: MarbleColors.COUNT)

    init(_ spec: LevelSpec) {
        self.spec = spec
        board = Board(spec)
        tray = TraySim(spec)
    }

    func tapId(_ id: Int) -> Bool {
        let i = board.locate(id)
        if i < 0 || !board.canTap(i) { return false }
        let b = board.cells[i]!
        let out = board.tap(i)
        if board.bombExpired() { return false }
        if out == .POP {
            if b.spec.kind == .RAINBOW { rainbow += b.spec.marbleCount } else { belt[b.spec.color] += b.spec.marbleCount }
            peakLoad = max(peakLoad, load)
            settle()
        }
        return true
    }

    func need(_ out: inout [Int]) {
        for i in 0..<out.count { out[i] = 0 }
        for i in 0..<tmpB.count { tmpB[i] = 0 }
        tray.slotsRemaining(&out)
        board.gridMarbles(&tmpB)
        for i in 0..<out.count { out[i] -= tmpB[i] + belt[i] }
    }

    func settle() {
        var changed = true
        while changed {
            changed = false
            for c in 0..<tray.columns.count {
                guard let cup = tray.columns[c].first else { continue }
                let k = cup.color
                let take = min(3 - cup.filled, belt[k])
                if take > 0 { belt[k] -= take; cup.filled += take; changed = true }
                if cup.filled < 3 && rainbow > 0 {
                    need(&tmpA)
                    let r = min(3 - cup.filled, rainbow, tmpA[k])
                    if r > 0 { rainbow -= r; cup.filled += r; changed = true }
                }
                if cup.filled == 3 { tray.columns[c].removeFirst(); board.cupsDone += 1; changed = true }
            }
        }
    }

    var solved: Bool { board.isEmpty && load == 0 && tray.isEmpty }
}
