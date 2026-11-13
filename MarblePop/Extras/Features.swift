import Foundation

/// iOS extras on top of the Android port. Every extra sits behind one flag here; set a flag to `false` to ship
/// exactly the Android behaviour for that part (each hook in the ported code checks its flag).
enum Features {
    /// Colour-blind symbols: one distinct symbol per marble colour (12 + rainbow) baked into the game's marble,
    /// cup and block sprites. Player toggle in Settings › Accessibility (`GameRepository.colorBlind`, default off).
    static var colorBlindPatterns = true

    /// Core Haptics: a soft transient per marble landing in a cup (stronger during combos, at most 25 per second),
    /// a firmer tap when a cup fills and a success pattern on win. Follows the Vibration setting.
    static var landingHaptics = true

    /// Render-only polish: a gentle spring bounce of a cup on every landing, and a shimmer sweep across a filled cup
    /// as it flies away (inside the engine's 0.42 s pop, so gameplay timing is unchanged). Off under Reduce Motion.
    static var smoothPolish = true
}
