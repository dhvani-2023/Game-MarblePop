import Foundation

/// Port of render/Themes.kt. Colours are ARGB ints (use `Color(argbInt:)` in SwiftUI).
struct GameTheme {
    let name: String
    let bgTop: Int, bgBottom: Int
    let bubble: Int
    let wall: Int, wallDark: Int, wallLight: Int
    let glassTop: Int, glassBottom: Int
    let interior: Int, slot: Int
    let funnel: Int, funnelDark: Int
    let dish: Int, dishDark: Int
    let groove: Int, rail: Int, accent: Int
    /// Sky behind the machine: top, mid, bottom, glowA, glowB, silhouette (same as ui.theme.Skies).
    let sky: [Int]

    init(_ name: String,
         _ bgTop: Int, _ bgBottom: Int, _ bubble: Int,
         _ wall: Int, _ wallDark: Int, _ wallLight: Int,
         _ glassTop: Int, _ glassBottom: Int, _ interior: Int, _ slot: Int,
         _ funnel: Int, _ funnelDark: Int, _ dish: Int, _ dishDark: Int,
         _ groove: Int, _ rail: Int, _ accent: Int,
         _ sky: [Int] = []) {
        self.name = name
        self.bgTop = bgTop; self.bgBottom = bgBottom; self.bubble = bubble
        self.wall = wall; self.wallDark = wallDark; self.wallLight = wallLight
        self.glassTop = glassTop; self.glassBottom = glassBottom; self.interior = interior; self.slot = slot
        self.funnel = funnel; self.funnelDark = funnelDark; self.dish = dish; self.dishDark = dishDark
        self.groove = groove; self.rail = rail; self.accent = accent
        self.sky = sky
    }
}

enum Themes {
    static let all: [GameTheme] = [
        GameTheme(
            "Candy Lab", 0xFF9C7DFF, 0xFF6440E6, 0x33FFFFFF,
            0xFF8E6EF2, 0xFF5534C4, 0xFFC0ADFF,
            0xFFE4DBFF, 0xFFCFC2FA, 0xFFF1EDFF, 0xFFDCD2FA,
            0xFFEDE8FC, 0xFFB7A7EA, 0xFFF6F3FE, 0xFFC6B9EE,
            0xFF3B3557, 0xFFFFFFFF, 0xFFFF5FA2,
            [0xFF5A3BEF, 0xFF8A52F5, 0xFFE77BD8, 0xFFFF9AD5, 0xFF6FD3FF, 0xFF3B1FA6]
        ),
        GameTheme(
            "Ocean", 0xFF63C9FF, 0xFF2F6FE0, 0x33FFFFFF,
            0xFF4E92EC, 0xFF2B5DB6, 0xFFA3CDFF,
            0xFFDDF0FF, 0xFFC2E0FA, 0xFFEAF6FF, 0xFFD0E6FA,
            0xFFE6F1FB, 0xFFA2C2E6, 0xFFF2F8FE, 0xFFB5CFEA,
            0xFF2F3B57, 0xFFFFFFFF, 0xFF33D6F5,
            [0xFF1F5FD6, 0xFF2E9BEA, 0xFF5FD9E6, 0xFF9AF0FF, 0xFF7DFFC8, 0xFF15489E]
        ),
        GameTheme(
            "Space", 0xFF3A2D86, 0xFF120C35, 0x22FFFFFF,
            0xFF43389A, 0xFF241C63, 0xFF7A6FD6,
            0xFFD6D0FA, 0xFFB8AEEE, 0xFFE7E3FF, 0xFFCAC2F2,
            0xFFE0DBF8, 0xFF9E94D6, 0xFFEAE6FB, 0xFFA79DDB,
            0xFF231E3D, 0xFFFFFFFF, 0xFFFFC93C,
            [0xFF140A3F, 0xFF2D1B7A, 0xFF6A2EB8, 0xFFB57BFF, 0xFF5FA8FF, 0xFF0D0630]
        ),
        GameTheme(
            "Lava", 0xFFFF9466, 0xFFC6344C, 0x33FFFFFF,
            0xFFE45A6C, 0xFFA8303F, 0xFFFFA6AF,
            0xFFFFE2DD, 0xFFFACAC4, 0xFFFFF0EC, 0xFFF8D6D0,
            0xFFFDEDEA, 0xFFE7AFA8, 0xFFFFF6F4, 0xFFEDBEB8,
            0xFF4A2F38, 0xFFFFFFFF, 0xFFFFC93C,
            [0xFFFF8A5C, 0xFFF2557A, 0xFF9C3FB5, 0xFFFFD36E, 0xFFFF9AD5, 0xFF6E2380]
        ),
        GameTheme(
            "Forest", 0xFF86DB7E, 0xFF2D9460, 0x33FFFFFF,
            0xFF5DB86E, 0xFF2F7F48, 0xFFADE6A6,
            0xFFE3F7DD, 0xFFC9EBC1, 0xFFF0FAEC, 0xFFD5EECD,
            0xFFEAF6E5, 0xFFA9D59E, 0xFFF5FBF2, 0xFFB9DDB0,
            0xFF2F3D33, 0xFFFFFFFF, 0xFFFFC93C,
            [0xFF3CC88A, 0xFF1FA27A, 0xFF137A66, 0xFFC8FF8A, 0xFF7DF0D0, 0xFF0C5A4B]
        ),
    ]

    static func get(_ i: Int) -> GameTheme { all[((i % all.count) + all.count) % all.count] }
}
