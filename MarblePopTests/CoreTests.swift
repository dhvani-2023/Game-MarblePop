import XCTest
import GameKit
@testable import MarblePop

/// Constants of core/ (SoundManager.kt, Ads.kt, GameRepository.kt) and the bundled audio.
final class CoreTests: XCTestCase {

    func testSoundFilesAreBundled() throws {
        try XCTSkipUnless(Bundle.main.bundlePath.hasSuffix(".app"), "needs the app as test host")
        for sfx in Sfx.allCases {
            XCTAssertNotNil(Bundle.main.url(forResource: sfx.res, withExtension: "caf"), "\(sfx.res).caf missing")
        }
        for m in Music.allCases {
            XCTAssertNotNil(Bundle.main.url(forResource: m.res, withExtension: "caf"), "\(m.res).caf missing")
        }
    }

    func testSfxTableMatchesKotlin() {
        let kotlin: [(String, String, Int64)] = [
            ("TAP", "sfx_tap", 30), ("POP", "sfx_pop", 40), ("CLACK", "sfx_clack", 45), ("PLINK", "sfx_plink", 25),
            ("CUP_COMPLETE", "sfx_cup_complete", 60), ("COMBO", "sfx_combo", 100), ("WIN", "sfx_win", 0), ("FAIL", "sfx_fail", 0),
            ("COIN", "sfx_coin", 40), ("BUTTON", "sfx_button", 40), ("WHOOSH", "sfx_whoosh", 60), ("STAR", "sfx_star", 50),
            ("UNLOCK", "sfx_unlock", 80), ("ICE", "sfx_ice_crack", 50), ("BOMB_TICK", "sfx_bomb_tick", 80),
            ("EXPLODE", "sfx_explode", 100), ("SPIN_TICK", "sfx_spin_tick", 20), ("REWARD", "sfx_reward", 100),
            ("WARNING", "sfx_warning", 600),
        ]
        XCTAssertEqual(Sfx.allCases.count, kotlin.count)
        for (sfx, k) in zip(Sfx.allCases, kotlin) {
            XCTAssertEqual(sfx.name, k.0)
            XCTAssertEqual(sfx.res, k.1)
            XCTAssertEqual(sfx.minGapMs, k.2, sfx.name)
            XCTAssertEqual(sfx.ordinal, Sfx.allCases.firstIndex(of: sfx))
        }
        XCTAssertEqual(Music.HOME.res, "music_home")
        XCTAssertEqual(Music.GAME.res, "music_game")
    }

    func testAdPlacements() {
        XCTAssertEqual([AdPlacement.UNLOCK_LEVEL, .UNLOCK_SKIN, .UNLOCK_THEME].map(\.name), ["UNLOCK_LEVEL", "UNLOCK_SKIN", "UNLOCK_THEME"])
    }

    func testEconomyConstants() {
        XCTAssertEqual(Booster.allCases.map(\.name), ["HAMMER", "MAGNET", "SLOTS", "SHUFFLE"])
        XCTAssertEqual(Booster.allCases.map(\.price), [150, 200, 120, 100])
        XCTAssertEqual(Booster.allCases.map(\.title), ["Hammer", "Magnet", "+6 Slots", "Shuffle"])
        XCTAssertEqual(Stat.allCases.map(\.name), ["LEVELS_WON", "THREE_STARS", "MARBLES", "CUPS", "BLOCKS", "MAX_COMBO", "BOOSTERS",
                                                   "SPINS", "DAILY_WINS", "COINS_EARNED", "CHESTS", "BOSS_WINS"])
        XCTAssertEqual(Catalog.skins.map(\.price), [0, 600, 900, 1500, 1200, 1800, 2500])
        XCTAssertEqual(Catalog.themes.map(\.name), ["Candy Lab", "Ocean", "Space", "Lava", "Forest"])
        XCTAssertEqual(GameRepository.LOGIN_REWARDS, [50, 75, 100, 125, 150, 200, 400])
        XCTAssertEqual(GameRepository.FREE_GIFT_COOLDOWN, 14_400_000)
        XCTAssertEqual(Feature.allCases.map(\.unlockLevel), [6, 8, 11, 15, 20, 25, 30, 40, 55, 70, 90, 120])
        XCTAssertEqual(Feature.introducedAt(40), .ICE)
        XCTAssertEqual(Feature.nextAfter(40), .RAINBOW)
        XCTAssertNil(Feature.nextAfter(120))
        XCTAssertEqual(MarbleColors.argb.count, MarbleColors.COUNT)
    }
}
