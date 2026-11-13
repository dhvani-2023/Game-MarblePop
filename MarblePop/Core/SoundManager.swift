import Foundation
import Observation
import GameKit

/// Kotlin `enum class Sfx(val res, val minGapMs)`; `res` is the base name of the `.caf` in Resources/Audio.
enum Sfx: Int, CaseIterable {
    case TAP, POP, CLACK, PLINK, CUP_COMPLETE, COMBO, WIN, FAIL, COIN, BUTTON, WHOOSH, STAR, UNLOCK, ICE, BOMB_TICK, EXPLODE,
         SPIN_TICK, REWARD, WARNING

    var res: String { Self.table[rawValue].res }
    /// Minimum time between two plays of this sound (rapid events don't stack).
    var minGapMs: Int64 { Self.table[rawValue].gap }
    var name: String { Self.table[rawValue].name }
    var ordinal: Int { rawValue }
    static var entries: [Sfx] { allCases }

    private static let table: [(name: String, res: String, gap: Int64)] = [
        ("TAP", "sfx_tap", 30),
        ("POP", "sfx_pop", 40),
        ("CLACK", "sfx_clack", 45),
        ("PLINK", "sfx_plink", 25),
        ("CUP_COMPLETE", "sfx_cup_complete", 60),
        ("COMBO", "sfx_combo", 100),
        ("WIN", "sfx_win", 0),
        ("FAIL", "sfx_fail", 0),
        ("COIN", "sfx_coin", 40),
        ("BUTTON", "sfx_button", 40),
        ("WHOOSH", "sfx_whoosh", 60),
        ("STAR", "sfx_star", 50),
        ("UNLOCK", "sfx_unlock", 80),
        ("ICE", "sfx_ice_crack", 50),
        ("BOMB_TICK", "sfx_bomb_tick", 80),
        ("EXPLODE", "sfx_explode", 100),
        ("SPIN_TICK", "sfx_spin_tick", 20),
        ("REWARD", "sfx_reward", 100),
        ("WARNING", "sfx_warning", 600),
    ]
}

enum Music: String, CaseIterable {
    case HOME, GAME

    var res: String { self == .HOME ? "music_home" : "music_game" }
    var name: String { rawValue }
}

/// Low-latency SFX (GameKit `SoundBank`, 12 voices like the Android SoundPool) plus looping background music
/// (GameKit `MusicPlayer`), and haptics. Kotlin `SoundManager(context, repo)` → `SoundManager(repo)`.
/// `Observable` (no tracked state) so the shell can inject it with `.environment(sound)` / `@Environment(SoundManager.self)`.
final class SoundManager: Observable {
    private let repo: GameRepository
    private let bank: SoundBank
    private let player: MusicPlayer
    private var last: [Int64]
    private var currentMusic: Music?
    /// Kotlin `player != null`: a music track has been started (and not stopped).
    private var playerActive = false
    private var paused = false

    /// Short ramps instead of MediaPlayer's hard start/stop, so tracks never click.
    private let musicFade: TimeInterval = 0.25

    convenience init(repo: GameRepository) { self.init(repo) }

    init(_ repo: GameRepository) {
        self.repo = repo
        bank = SoundBank(voices: 12)
        player = MusicPlayer()
        last = [Int64](repeating: 0, count: Sfx.allCases.count)
        for sfx in Sfx.allCases { bank.load(sfx.res) }
        player.trackGain[Music.GAME.res] = 0.45
        player.trackGain[Music.HOME.res] = 0.55
        AudioSystem.shared.start()
        // music decodes to memory (~30 s each); do it off the main thread, then start whatever is wanted
        let player = self.player
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            for m in Music.allCases { player.load(m.res) }
            DispatchQueue.main.async { self?.onMusicLoaded() }
        }
    }

    private static func uptimeMillis() -> Int64 { Int64(ProcessInfo.processInfo.systemUptime * 1000) }

    /// Kotlin `play(sfx, pitch = 1f, volume = 1f)`.
    func play(_ sfx: Sfx, _ pitch: Float = 1, _ volume: Float = 1) {
        if !repo.sfxOn { return }
        let now = SoundManager.uptimeMillis()
        let o = sfx.ordinal
        if now - last[o] < sfx.minGapMs { return }
        last[o] = now
        let v = (volume * 0.9).coerceIn(0, 1)
        bank.play(sfx.res, volume: v, rate: pitch.coerceIn(0.5, 2))
    }

    func play(_ sfx: Sfx, pitch: Float, volume: Float = 1) { play(sfx, pitch, volume) }
    func play(_ sfx: Sfx, volume: Float) { play(sfx, 1, volume) }

    /// Android: LIGHT 12 ms @70, MEDIUM 22 ms @140, HEAVY 70 ms @255, SUCCESS waveform 0/30/60/40 ms @0/160/0/220.
    func haptic(_ kind: Haptic) {
        if !repo.hapticsOn { return }
        #if canImport(UIKit)
        let fire = {
            MainActor.assumeIsolated {
                switch kind {
                case .LIGHT: Haptics.tap(0.5)
                case .MEDIUM: Haptics.medium(0.7)
                case .HEAVY: Haptics.heavy(1)
                case .SUCCESS: Haptics.pattern(timings: [0, 30, 60, 40], amplitudes: [0, 160, 0, 220])
                }
            }
        }
        if Thread.isMainThread { fire() } else { DispatchQueue.main.async(execute: fire) }
        #endif
    }

    func playMusic(_ music: Music) {
        if currentMusic == music && playerActive { if !paused { resumeIfAllowed() }; return }
        stopMusic()
        currentMusic = music
        if !repo.musicOn { return }
        startPlayer(music)
    }

    private func startPlayer(_ music: Music) {
        playerActive = true
        if !paused { player.play(music.res, fade: musicFade) }
    }

    private func resumeIfAllowed() {
        guard playerActive, let m = currentMusic else { return }
        if repo.musicOn { player.play(m.res, fade: musicFade) }
    }

    func stopMusic() {
        if playerActive { player.stop(fade: musicFade) }
        playerActive = false
    }

    func onMusicSettingChanged() {
        if repo.musicOn {
            let m = currentMusic
            currentMusic = nil
            if let m { playMusic(m) }
        } else {
            stopMusic()
        }
    }

    /// App went to the background (Kotlin `onPause`): music pauses where it is.
    func pause() {
        paused = true
        AudioSystem.shared.suspend()
    }

    /// App came back (Kotlin `onResume`).
    func resume() {
        paused = false
        AudioSystem.shared.resume()
        resumeIfAllowed()
        if !playerActive, let m = currentMusic, repo.musicOn {
            currentMusic = nil
            playMusic(m)
        }
    }

    func release() {
        stopMusic()
        bank.stopAll()
    }

    private func onMusicLoaded() {
        if playerActive && !paused, let m = currentMusic, repo.musicOn { player.play(m.res, fade: musicFade) }
    }
}
