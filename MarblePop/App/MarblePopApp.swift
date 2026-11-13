import SwiftUI
import GameKit

/// Port of `MainActivity` (+ the Application root): creates the repository and the sound manager once,
/// registers the fonts and hands both to [MarbleApp]. Sound pauses/resumes with the scene like
/// Android's onPause/onResume.
@main
struct MarblePopApp: App {
    @UIApplicationDelegateAdaptor(GameAppDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase

    @State private var repo: GameRepository
    @State private var sound: SoundManager

    init() {
        FontRegistry.registerAll()
        OrientationLock.shared.mask = .portrait
        let r = GameRepository()
        _repo = State(initialValue: r)
        _sound = State(initialValue: SoundManager(repo: r))
        Haptics.prepare()
    }

    var body: some Scene {
        WindowGroup {
            MarbleApp(repo: repo, sound: sound)
                // Android: edge-to-edge, light status-bar icons, navigation bar hidden (transient swipe).
                .preferredColorScheme(.dark)
                .persistentSystemOverlays(.hidden)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: sound.resume()
            case .background, .inactive: sound.pause()
            @unknown default: break
            }
        }
    }
}
