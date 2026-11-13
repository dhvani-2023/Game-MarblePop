import XCTest
import GameKit
@testable import MarblePop

/// GameRepository keeps the Android SharedPreferences ("marble_pop") keys, defaults and encodings.
final class GameRepositoryTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "MarblePopTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    private func makeRepo() -> GameRepository { GameRepository(prefs: Prefs(name: "marble_pop", defaults: defaults)) }
    private func raw(_ key: String) -> Any? { defaults.object(forKey: "marble_pop." + key) }

    func testDefaults() {
        let r = makeRepo()
        XCTAssertFalse(r.onboardingDone)
        XCTAssertEqual(r.level, 1)
        XCTAssertEqual(r.coins, 300)
        XCTAssertEqual(Booster.allCases.map { r.boosterCount($0) }, [2, 2, 2, 2])
        XCTAssertEqual(r.skin, 0)
        XCTAssertEqual(r.ownedSkins, [0])
        XCTAssertEqual(r.theme, -1)
        XCTAssertEqual(r.ownedThemes, [0])
        XCTAssertTrue(r.musicOn && r.sfxOn && r.hapticsOn)
        XCTAssertEqual(r.playerName, "Marble Master")
        XCTAssertEqual(r.totalStars, 0)
        XCTAssertEqual(r.starsFor(1), 0)
        XCTAssertTrue(r.claimedAchievements.isEmpty && r.openedChests.isEmpty && r.adUnlockedLevels.isEmpty)
        XCTAssertEqual(r.lastSpinDay, -1)
        XCTAssertEqual(r.freeGiftAt, 0)
        XCTAssertTrue(r.canSpin && r.canClaimLogin)
        XCTAssertEqual(r.loginIndex, 0)
        XCTAssertEqual(r.dailyLevel, Int((r.today * 37 + 11) % 3000 + 100))
        XCTAssertEqual(r.themeForLevel(26), 1)
    }

    func testKeysAndEncodings() {
        let r = makeRepo()
        r.recordWin(1, 3)
        r.recordWin(1, 2) // never lowers
        r.recordWin(5, 1) // not the current level: no unlock
        let stars = raw("stars") as? String
        XCTAssertEqual(stars?.count, LevelGenerator.MAX_LEVEL + 1)
        XCTAssertEqual(stars.map { Array($0)[1] }, "3")
        XCTAssertEqual(stars.map { Array($0)[5] }, "1")
        XCTAssertEqual(r.totalStars, 4)
        XCTAssertEqual(r.level, 2)
        XCTAssertEqual(raw("level") as? Int, 2)

        r.addBooster(.HAMMER, -1)
        XCTAssertEqual(raw("booster_HAMMER") as? Int, 1)
        r.addStat(.MARBLES, Int64(27))
        r.maxStat(.MAX_COMBO, 4)
        r.maxStat(.MAX_COMBO, 2)
        XCTAssertEqual((raw("stat_MARBLES") as? NSNumber)?.int64Value, 27)
        XCTAssertEqual((raw("stat_MAX_COMBO") as? NSNumber)?.int64Value, 4)

        r.grantSkin(3); r.grantSkin(1); r.grantSkin(3)
        XCTAssertEqual(raw("owned_skins") as? String, "0,3,1")
        XCTAssertTrue(r.spend(100))
        XCTAssertFalse(r.spend(10_000))
        XCTAssertEqual(raw("coins") as? Int, 200)
        XCTAssertFalse(r.buyTheme(1)) // Ocean costs 800 > 200 coins
        r.addCoins(1000)
        XCTAssertTrue(r.buyTheme(1))
        XCTAssertEqual(raw("owned_themes") as? String, "0,1")
        XCTAssertEqual(r.coins, 400)
        XCTAssertEqual(r.stat(.COINS_EARNED), 1000)
        r.claimAchievement(4, 50); r.claimAchievement(4, 50)
        XCTAssertEqual(raw("ach") as? String, "4")
        XCTAssertEqual(r.coins, 450)
        r.openChest(2); r.unlockLevelByAd(40)
        XCTAssertEqual(raw("chests") as? String, "2")
        XCTAssertEqual(raw("ad_levels") as? String, "40")
        XCTAssertTrue(r.isLevelPlayable(40))
        XCTAssertFalse(r.isLevelPlayable(41))

        XCTAssertEqual(r.claimLogin(), 50)
        XCTAssertEqual(r.claimLogin(), 0)
        XCTAssertEqual(raw("login_streak") as? Int, 1)
        XCTAssertEqual((raw("login_day") as? NSNumber)?.int64Value, r.today)
        r.markSpin()
        XCTAssertFalse(r.canSpin)
        XCTAssertTrue(r.claimFreeGift(1_000))
        XCTAssertFalse(r.claimFreeGift(2_000))
        XCTAssertEqual((raw("free_gift_at") as? NSNumber)?.int64Value, 1_000 + GameRepository.FREE_GIFT_COOLDOWN)
        r.setMusic(false); r.setName("Raj"); r.selectTheme(2)

        // a fresh repository reads everything back
        let r2 = makeRepo()
        XCTAssertEqual(r2.starsFor(1), 3)
        XCTAssertEqual(r2.totalStars, 4)
        XCTAssertEqual(r2.boosterCount(.HAMMER), 1)
        XCTAssertEqual(r2.stat(.MARBLES), 27)
        XCTAssertEqual(r2.ownedSkins, [0, 1, 3])
        XCTAssertEqual(r2.claimedAchievements, [4])
        XCTAssertFalse(r2.musicOn)
        XCTAssertEqual(r2.playerName, "Raj")
        XCTAssertEqual(r2.theme, 2)
        XCTAssertEqual(r2.themeForLevel(1), 2)
        XCTAssertFalse(r2.canClaimLogin)
        r2.grantSkin(5)
        XCTAssertEqual(raw("owned_skins") as? String, "0,3,1,5")
    }

    func testResetProgressKeepsOnlyOnboarding() {
        let r = makeRepo()
        r.finishOnboarding()
        r.addCoins(500); r.recordWin(1, 3); r.grantSkin(2); r.addStat(.CUPS, 9); r.setSfx(false)
        r.resetProgress()
        let keys = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("marble_pop.") }
        XCTAssertEqual(keys, ["marble_pop.onboarding"])
        XCTAssertEqual(r.coins, 300)
        XCTAssertEqual(r.level, 1)
        XCTAssertEqual(r.totalStars, 0)
        XCTAssertEqual(r.ownedSkins, [0])
        XCTAssertEqual(r.stat(.CUPS), 0)
        XCTAssertTrue(r.sfxOn)
        XCTAssertTrue(makeRepo().onboardingDone)
    }
}
