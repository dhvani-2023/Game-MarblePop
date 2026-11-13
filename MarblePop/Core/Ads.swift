import Foundation
import GameKit

// Kotlin `core/Ads.kt` → GameKit `Ads.rewarded` (`RewardedAdGateway`: `isAvailable`, `show(placement) { granted in }`).
// No fake/test ad is ever shown on iOS: the debug `DebugRewardedAds` overlay and `NoRewardedAds` are not ported —
// the default GameKit gateway grants the reward immediately. Use `Ads.usesRealAds` to label buttons "FREE".
//
//     Ads.rewarded.show(.UNLOCK_LEVEL) { granted in if granted { repo.unlockLevelByAd(n) } }

/// Kotlin `interface RewardedAds`.
typealias RewardedAds = RewardedAdGateway

/// Kotlin `enum class AdPlacement { UNLOCK_LEVEL, UNLOCK_SKIN, UNLOCK_THEME }` as GameKit placements.
extension AdPlacement {
    static let UNLOCK_LEVEL = AdPlacement("UNLOCK_LEVEL")
    static let UNLOCK_SKIN = AdPlacement("UNLOCK_SKIN")
    static let UNLOCK_THEME = AdPlacement("UNLOCK_THEME")

    /// Kotlin `placement.name`.
    var name: String { id }
}
