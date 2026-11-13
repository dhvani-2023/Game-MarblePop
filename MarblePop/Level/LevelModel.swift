import Foundation

/// Marble / block colour palette (ARGB). Index is the colour id used everywhere.
enum MarbleColors {
    static let RAINBOW = 99
    static let argb: [UInt32] = [
        0xFFFF4D5E, // 0 red
        0xFFFFD23F, // 1 yellow
        0xFF33C8F5, // 2 sky
        0xFF3CCB5A, // 3 green
        0xFF9B5CFF, // 4 purple
        0xFFFF9F1C, // 5 orange
        0xFFFF7AC8, // 6 pink
        0xFF3D6BFF, // 7 blue
        0xFFEFF3FA, // 8 white
        0xFF9C5A2E, // 9 brown
        0xFF1F7A4D, // 10 dark green
        0xFF4A4E69, // 11 charcoal
    ]
    static let names = ["Red", "Yellow", "Sky", "Green", "Purple", "Orange", "Pink", "Blue", "White", "Brown", "Forest", "Charcoal"]
    static let COUNT = 12
}

enum BlockKind: Int, CaseIterable {
    case NORMAL, MYSTERY, COUNTER, KEY, CHAINED, CRATE, ICE, ARROW, DOUBLE, RAINBOW, BOMB, PAINT, GRAY, SWITCH

    static var entries: [BlockKind] { allCases }
    var ordinal: Int { rawValue }
    var name: String { Self.names[rawValue] }
    private static let names = ["NORMAL", "MYSTERY", "COUNTER", "KEY", "CHAINED", "CRATE", "ICE", "ARROW", "DOUBLE", "RAINBOW", "BOMB", "PAINT", "GRAY", "SWITCH"]
}

/// Mechanics that unlock over the level curve.
enum Feature: Int, CaseIterable {
    case MYSTERY, COUNTER, HIDDEN_CUP, KEY, ARROW, CRATE, DOUBLE, ICE, RAINBOW, BOMB, PAINT, SWITCH

    var unlockLevel: Int { Self.table[rawValue].0 }
    var title: String { Self.table[rawValue].1 }
    var description: String { Self.table[rawValue].2 }

    static var entries: [Feature] { allCases }
    var ordinal: Int { rawValue }
    var name: String { Self.names[rawValue] }

    private static let names = ["MYSTERY", "COUNTER", "HIDDEN_CUP", "KEY", "ARROW", "CRATE", "DOUBLE", "ICE", "RAINBOW", "BOMB", "PAINT", "SWITCH"]
    private static let table: [(Int, String, String)] = [
        (6, "Mystery Block", "Its colour is revealed as soon as it has a way out."),
        (8, "Caged Block", "The cage opens after you pop the shown number of blocks."),
        (11, "Mystery Cup", "Covered cups reveal their colour when they reach the top."),
        (15, "Key & Chains", "Pop the key block to break every chain."),
        (20, "Arrow Block", "Can also slide out in its arrow direction when that way is clear."),
        (25, "Crate", "Opens after the shown number of cups are filled."),
        (30, "Double Block", "Holds twice the marbles. Make room on the belt!"),
        (40, "Ice Block", "Tap once to crack the ice, tap again to pop it."),
        (55, "Rainbow Block", "Rainbow marbles fill any cup that still needs them."),
        (70, "Bomb Block", "Pop it before its move timer runs out!"),
        (90, "Paint Bucket", "Pop the bucket to paint the grey blocks with colour."),
        (120, "Belt Switch", "Popping it reverses the belt direction."),
    ]

    static func introducedAt(_ level: Int) -> Feature? { allCases.first { $0.unlockLevel == level } }
    static func nextAfter(_ level: Int) -> Feature? { allCases.first { $0.unlockLevel > level } }
}

/// `param` meaning depends on kind: COUNTER pops needed, CRATE cups needed, BOMB move limit,
/// ARROW direction (0 left, 1 right, 2 up), KEY/CHAINED lock id, PAINT/GRAY bucket id.
struct BlockSpec: Hashable {
    let id: Int
    let color: Int
    let kind: BlockKind
    let param: Int

    init(_ id: Int, _ color: Int, _ kind: BlockKind = .NORMAL, _ param: Int = 0) {
        self.id = id
        self.color = color
        self.kind = kind
        self.param = param
    }

    init(id: Int, color: Int, kind: BlockKind = .NORMAL, param: Int = 0) {
        self.init(id, color, kind, param)
    }

    var marbleCount: Int { kind == .DOUBLE ? 18 : 9 }
    var marbleColor: Int { kind == .RAINBOW ? MarbleColors.RAINBOW : color }
}

struct CupSpec: Hashable {
    let color: Int
    let hidden: Bool

    init(_ color: Int, _ hidden: Bool = false) {
        self.color = color
        self.hidden = hidden
    }

    init(color: Int, hidden: Bool = false) { self.init(color, hidden) }

    func copy(hidden: Bool) -> CupSpec { CupSpec(color, hidden) }
}

/// Grid cells are indexed `row * width + col`, row 0 being the bottom row that opens into the hopper.
/// Blocks never fall: a block can be tapped when it has a path of empty cells to the bottom exit.
final class LevelSpec {
    let number: Int
    let width: Int
    let height: Int
    /// Active (playable) cells of the board shape.
    let mask: [Bool]
    /// Block per cell, nil = empty slot.
    let cells: [BlockSpec?]
    /// Tray columns, top cup first.
    let tray: [[CupSpec]]
    let capacity: Int
    let theme: Int
    let colorCount: Int
    let isBoss: Bool
    /// Planned (verified) tap order of block ids — includes the double tap of ice blocks.
    let plan: [Int]
    let introduces: Feature?

    init(number: Int, width: Int, height: Int, mask: [Bool], cells: [BlockSpec?], tray: [[CupSpec]],
         capacity: Int, theme: Int, colorCount: Int, isBoss: Bool, plan: [Int], introduces: Feature?) {
        self.number = number
        self.width = width
        self.height = height
        self.mask = mask
        self.cells = cells
        self.tray = tray
        self.capacity = capacity
        self.theme = theme
        self.colorCount = colorCount
        self.isBoss = isBoss
        self.plan = plan
        self.introduces = introduces
    }

    var maxHeight: Int { height }
    var blocks: [BlockSpec] { cells.compactMap { $0 } }
    var blockCount: Int { cells.reduce(0) { $1 != nil ? $0 + 1 : $0 } }
    func active(_ c: Int, _ r: Int) -> Bool { c >= 0 && c < width && r >= 0 && r < height && mask[r * width + c] }
}
