import Foundation
import Observation
import GameKit

enum Booster: String, CaseIterable {
    case HAMMER, MAGNET, SLOTS, SHUFFLE

    var title: String {
        switch self {
        case .HAMMER: return "Hammer"
        case .MAGNET: return "Magnet"
        case .SLOTS: return "+6 Slots"
        case .SHUFFLE: return "Shuffle"
        }
    }

    var price: Int {
        switch self {
        case .HAMMER: return 150
        case .MAGNET: return 200
        case .SLOTS: return 120
        case .SHUFFLE: return 100
        }
    }

    var description: String {
        switch self {
        case .HAMMER: return "Smash any block, even locked ones."
        case .MAGNET: return "Pull marbles of one colour straight into their cups."
        case .SLOTS: return "Adds 6 extra slots to the belt."
        case .SHUFFLE: return "Shuffles the colours of the waiting cups."
        }
    }

    static var entries: [Booster] { allCases }
    var ordinal: Int { Self.order.firstIndex(of: self)! }
    private static let order = allCases
    var name: String { rawValue }
}

enum Stat: String, CaseIterable {
    case LEVELS_WON, THREE_STARS, MARBLES, CUPS, BLOCKS, MAX_COMBO, BOOSTERS, SPINS, DAILY_WINS, COINS_EARNED, CHESTS, BOSS_WINS

    static var entries: [Stat] { allCases }
    var ordinal: Int { Self.order.firstIndex(of: self)! }
    private static let order = allCases
    var name: String { rawValue }
}

struct Skin: Hashable {
    let name: String
    let price: Int
    init(_ name: String, _ price: Int) { self.name = name; self.price = price }
}

struct ThemeInfo: Hashable {
    let name: String
    let price: Int
    init(_ name: String, _ price: Int) { self.name = name; self.price = price }
}

enum Catalog {
    static let skins = [
        Skin("Glossy", 0), Skin("Glass", 600), Skin("Candy", 900), Skin("Galaxy", 1500),
        Skin("Metal", 1200), Skin("Neon", 1800), Skin("Smiley", 2500),
    ]
    static let themes = [
        ThemeInfo("Candy Lab", 0), ThemeInfo("Ocean", 800), ThemeInfo("Space", 1500),
        ThemeInfo("Lava", 1200), ThemeInfo("Forest", 1000),
    ]
}

/// All persistent player data, observable by SwiftUI. Stored in GameKit `Prefs(name: "marble_pop")` with the
/// Android SharedPreferences keys and encodings (`stars` = 5001-char digit string, `booster_<NAME>`,
/// `stat_<NAME>` longs, comma-separated int sets in insertion order, …).
/// Kotlin `repo.coins.intValue` / `repo.musicOn.value` → `repo.coins` / `repo.musicOn` (read-only; use the methods).
@Observable
final class GameRepository {
    private let prefs: Prefs

    private(set) var onboardingDone: Bool
    private(set) var level: Int
    private(set) var coins: Int
    private(set) var boosters: [Int]
    private(set) var skin: Int
    private(set) var ownedSkins: Set<Int>
    private(set) var theme: Int // -1 = auto rotate
    private(set) var ownedThemes: Set<Int>
    private(set) var musicOn: Bool
    private(set) var sfxOn: Bool
    private(set) var hapticsOn: Bool
    /// Extras (Features.colorBlindPatterns): colour-blind symbols on marbles, cups and blocks (key `color_blind`).
    private(set) var colorBlind: Bool
    private(set) var playerName: String
    private(set) var avatar: Int

    @ObservationIgnored private var starChars: [UInt8]
    private(set) var starsVersion = 0

    private(set) var stats: [Int64]
    private(set) var claimedAchievements: Set<Int>
    private(set) var openedChests: Set<Int>
    /// Levels unlocked early by watching a rewarded ad.
    private(set) var adUnlockedLevels: Set<Int>

    // daily
    private(set) var lastSpinDay: Int64
    private(set) var loginStreak: Int
    private(set) var lastLoginClaimDay: Int64
    private(set) var dailyWinDay: Int64
    private(set) var freeGiftAt: Int64

    /// Insertion order of the int sets (Kotlin `toSet()` / `set + i` are LinkedHashSets, saved with `joinToString(",")`).
    @ObservationIgnored private var setOrder: [String: [Int]] = [:]

    var today: Int64 { Int64(Days.epochDay()) }

    init(prefs: Prefs = Prefs(name: "marble_pop")) {
        self.prefs = prefs
        onboardingDone = prefs.bool("onboarding", false)
        level = prefs.int("level", 1)
        coins = prefs.int("coins", 300)
        boosters = Booster.allCases.map { prefs.int("booster_\($0.name)", 2) }
        skin = prefs.int("skin", 0)
        theme = prefs.int("theme", -1)
        musicOn = prefs.bool("music", true)
        sfxOn = prefs.bool("sfx", true)
        hapticsOn = prefs.bool("haptics", true)
        colorBlind = prefs.bool(ColorBlind.KEY, false)
        playerName = prefs.string("name", "Marble Master")
        avatar = prefs.int("avatar", 0)

        var chars = Array((prefs.optionalString("stars") ?? "").utf8)
        if chars.count < LevelGenerator.MAX_LEVEL + 1 {
            chars.append(contentsOf: [UInt8](repeating: UInt8(ascii: "0"), count: LevelGenerator.MAX_LEVEL + 1 - chars.count))
        }
        starChars = chars

        stats = Stat.allCases.map { prefs.long("stat_\($0.name)", 0) }

        lastSpinDay = prefs.long("spin_day", -1)
        loginStreak = prefs.int("login_streak", 0)
        lastLoginClaimDay = prefs.long("login_day", -1)
        dailyWinDay = prefs.long("daily_win", -1)
        freeGiftAt = prefs.long("free_gift_at", 0)

        var order: [String: [Int]] = [:]
        for (key, def) in [("owned_skins", "0"), ("owned_themes", "0"), ("ach", ""), ("chests", ""), ("ad_levels", "")] {
            order[key] = GameRepository.decodeList(prefs.string(key, def))
        }
        ownedSkins = Set(order["owned_skins"]!)
        ownedThemes = Set(order["owned_themes"]!)
        claimedAchievements = Set(order["ach"]!)
        openedChests = Set(order["chests"]!)
        adUnlockedLevels = Set(order["ad_levels"]!)
        setOrder = order
    }

    private static func decodeList(_ s: String) -> [Int] {
        var out: [Int] = []
        var seen = Set<Int>()
        for part in s.split(separator: ",", omittingEmptySubsequences: false) {
            let t = part.trimmingCharacters(in: .whitespacesAndNewlines)
            if let v = Int32(t).map({ Int($0) }), seen.insert(v).inserted { out.append(v) }
        }
        return out
    }

    /// `set.value = set.value + i` followed by `putString(key, encodeSet(...))`.
    private func addToSet(_ key: String, _ i: Int) -> Set<Int> {
        var list = setOrder[key] ?? []
        if !list.contains(i) { list.append(i) }
        setOrder[key] = list
        prefs.set(key, list.map { String($0) }.joined(separator: ","))
        return Set(list)
    }

    func finishOnboarding() { onboardingDone = true; prefs.set("onboarding", true) }

    func starsFor(_ n: Int) -> Int {
        _ = starsVersion
        return (n >= 1 && n <= LevelGenerator.MAX_LEVEL) ? Int(starChars[n]) - 48 : 0
    }

    var totalStars: Int {
        _ = starsVersion
        var s = 0
        for c in starChars { s += Int(c) - 48 }
        return s
    }

    func recordWin(_ n: Int, _ stars: Int) {
        if stars > starsFor(n) && n >= 0 && n < starChars.count {
            starChars[n] = UInt8(48 + stars)
            prefs.set("stars", String(decoding: starChars, as: UTF8.self))
            starsVersion += 1
        }
        if n == level && n < LevelGenerator.MAX_LEVEL {
            level = n + 1
            prefs.set("level", n + 1)
        }
    }

    func isLevelPlayable(_ n: Int) -> Bool { n <= level || adUnlockedLevels.contains(n) }

    func unlockLevelByAd(_ n: Int) { adUnlockedLevels = addToSet("ad_levels", n) }

    /// Grants a skin without spending coins (rewarded ad).
    func grantSkin(_ i: Int) { ownedSkins = addToSet("owned_skins", i) }

    /// Grants a theme without spending coins (rewarded ad).
    func grantTheme(_ i: Int) { ownedThemes = addToSet("owned_themes", i) }

    func addCoins(_ amount: Int) {
        coins = (coins + amount).coerceAtLeast(0)
        prefs.set("coins", coins)
        if amount > 0 { addStat(.COINS_EARNED, Int64(amount)) }
    }

    @discardableResult
    func spend(_ amount: Int) -> Bool {
        if coins < amount { return false }
        addCoins(-amount)
        return true
    }

    func boosterCount(_ b: Booster) -> Int { boosters[b.ordinal] }

    func addBooster(_ b: Booster, _ n: Int) {
        boosters[b.ordinal] = (boosters[b.ordinal] + n).coerceAtLeast(0)
        prefs.set("booster_\(b.name)", boosters[b.ordinal])
    }

    func addStat(_ s: Stat, _ v: Int64) {
        stats[s.ordinal] = stats[s.ordinal] + v
        prefs.set("stat_\(s.name)", stats[s.ordinal])
    }

    func addStat(_ s: Stat, _ v: Int) { addStat(s, Int64(v)) }

    func maxStat(_ s: Stat, _ v: Int64) {
        if v > stats[s.ordinal] { stats[s.ordinal] = v; prefs.set("stat_\(s.name)", v) }
    }

    func maxStat(_ s: Stat, _ v: Int) { maxStat(s, Int64(v)) }

    func stat(_ s: Stat) -> Int64 { stats[s.ordinal] }

    func selectSkin(_ i: Int) { skin = i; prefs.set("skin", i) }

    @discardableResult
    func buySkin(_ i: Int) -> Bool {
        if ownedSkins.contains(i) { return true }
        if !spend(Catalog.skins[i].price) { return false }
        ownedSkins = addToSet("owned_skins", i)
        return true
    }

    func selectTheme(_ i: Int) { theme = i; prefs.set("theme", i) }

    @discardableResult
    func buyTheme(_ i: Int) -> Bool {
        if ownedThemes.contains(i) { return true }
        if !spend(Catalog.themes[i].price) { return false }
        ownedThemes = addToSet("owned_themes", i)
        return true
    }

    /// Theme used for a level: the player's pick, or the rotating level theme.
    func themeForLevel(_ n: Int) -> Int { theme >= 0 ? theme : LevelGenerator.themeFor(n) }

    func setMusic(_ on: Bool) { musicOn = on; prefs.set("music", on) }
    func setSfx(_ on: Bool) { sfxOn = on; prefs.set("sfx", on) }
    func setHaptics(_ on: Bool) { hapticsOn = on; prefs.set("haptics", on) }
    func setColorBlind(_ on: Bool) { colorBlind = on; prefs.set(ColorBlind.KEY, on) }
    func setName(_ n: String) { playerName = n; prefs.set("name", n) }
    func setAvatar(_ a: Int) { avatar = a; prefs.set("avatar", a) }

    func claimAchievement(_ id: Int, _ reward: Int) {
        if claimedAchievements.contains(id) { return }
        claimedAchievements = addToSet("ach", id)
        addCoins(reward)
    }

    func openChest(_ index: Int) {
        openedChests = addToSet("chests", index)
        addStat(.CHESTS, 1)
    }

    // ---- daily
    var canSpin: Bool { lastSpinDay != today }

    func markSpin() {
        let t = today
        lastSpinDay = t
        prefs.set("spin_day", t)
        addStat(.SPINS, 1)
    }

    /// Streak index (0..6) of the next login reward, resetting when a day was missed.
    var loginIndex: Int {
        let last = lastLoginClaimDay
        let t = today
        return (last == t - 1 || last == t) ? loginStreak % 7 : 0
    }

    var canClaimLogin: Bool { lastLoginClaimDay != today }

    @discardableResult
    func claimLogin() -> Int {
        guard canClaimLogin else { return 0 }
        let idx = loginIndex
        let reward = GameRepository.LOGIN_REWARDS[idx]
        let streakBase = lastLoginClaimDay == today - 1 ? loginStreak : 0
        loginStreak = streakBase + 1
        let t = today
        lastLoginClaimDay = t
        prefs.set("login_streak", loginStreak)
        prefs.set("login_day", t)
        addCoins(reward)
        if idx == 6 { for b in Booster.allCases { addBooster(b, 1) } }
        return reward
    }

    var dailyChallengeDone: Bool { dailyWinDay == today }

    func markDailyWin() {
        let t = today
        dailyWinDay = t
        prefs.set("daily_win", t)
        addStat(.DAILY_WINS, 1)
    }

    /// Today's challenge maps to a deterministic level well ahead of the player.
    var dailyLevel: Int { Int((today * 37 + 11) % 3000 + 100) }

    /// `now` = epoch milliseconds (`Days.nowMillis()`).
    @discardableResult
    func claimFreeGift(_ now: Int64) -> Bool {
        if now < freeGiftAt { return false }
        freeGiftAt = now + GameRepository.FREE_GIFT_COOLDOWN
        prefs.set("free_gift_at", freeGiftAt)
        addCoins(100)
        return true
    }

    func resetProgress() {
        prefs.clearAll()
        prefs.set("onboarding", true)
        level = 1; coins = 300
        boosters = Booster.allCases.map { _ in 2 }
        for i in 0..<starChars.count { starChars[i] = UInt8(ascii: "0") }
        starsVersion += 1
        stats = Stat.allCases.map { _ in 0 }
        skin = 0; ownedSkins = [0]; theme = -1; ownedThemes = [0]
        claimedAchievements = []; openedChests = []; adUnlockedLevels = []
        setOrder = ["owned_skins": [0], "owned_themes": [0], "ach": [], "chests": [], "ad_levels": []]
        lastSpinDay = -1; loginStreak = 0; lastLoginClaimDay = -1; dailyWinDay = -1; freeGiftAt = 0
        musicOn = true; sfxOn = true; hapticsOn = true; colorBlind = false
    }

    static let LOGIN_REWARDS = [50, 75, 100, 125, 150, 200, 400]
    static let FREE_GIFT_COOLDOWN: Int64 = 4 * 60 * 60 * 1000
}
