import SwiftUI
import GameKit

private let GroupTitle = TextStyle(fontFamily: LilitaOne, fontSize: 21, color: GameColors.Purple700)
private let RowLabel = TextStyle(fontFamily: LilitaOne, fontSize: 20, color: GameColors.Ink)
private let Hint = TextStyle(fontFamily: Fredoka, fontWeight: .SemiBold, fontSize: 14, color: GameColors.InkSoft)

struct SettingsScreen: View {
    let nav: Nav
    @Environment(GameRepository.self) var repo
    @Environment(SoundManager.self) var sound
    @State var confirmReset = false

    init(nav: Nav) { self.nav = nav }

    private var version: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0"
    }

    var body: some View {
        ZStack {
            SkyBackground(Skies.Menu).ignoresSafeArea()
            VStack(spacing: 0) {
                ScreenHeader("Settings", onBack: { nav.back() })
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        Color.clear.frame(height: 2)
                        SettingsGroup(title: "Sound & Feel", icon: .SOUND) {
                            ToggleRow(icon: .MUSIC, label: "Music", value: repo.musicOn, color: .Pink) { repo.setMusic($0); sound.onMusicSettingChanged() }
                            RowDivider()
                            ToggleRow(icon: .SOUND, label: "Sound Effects", value: repo.sfxOn, color: .Blue) { repo.setSfx($0) }
                            RowDivider()
                            ToggleRow(icon: .VIBRATE, label: "Vibration", value: repo.hapticsOn, color: .Purple) {
                                repo.setHaptics($0)
                                if $0 { sound.haptic(.MEDIUM) }
                            }
                        }
                        if Features.colorBlindPatterns { ColorBlindSettingsGroup() } // Extras: Accessibility
                        SettingsGroup(title: "Legal", icon: .SHIELD) {
                            LinkRow(icon: .DOC, color: .Purple, label: "Terms of Service") { nav.go(.Legal(page: "terms")) }
                            RowDivider()
                            LinkRow(icon: .SHIELD, color: .Green, label: "Privacy Policy") { nav.go(.Legal(page: "privacy")) }
                        }
                        SettingsGroup(title: "Progress", icon: .FLAG) {
                            Text("Your game is saved on this device only.").textStyle(Hint)
                            Spacer().frame(height: 10)
                            GameButton("Reset Progress", color: .Red, height: 52, fontSize: 20, icon: .RETRY) { confirmReset = true }
                                .frame(maxWidth: .infinity)
                        }
                        // footer
                        VStack(spacing: 0) {
                            Image("LaunchMark")
                                .resizable()
                                .frame(width: 108, height: 108)
                                .floaty(amplitude: 4, periodMs: 3000)
                            OutlinedText("Marble Pop Factory", fontSize: 24, brush: Grad.Gold, gloss: true)
                            Spacer().frame(height: 4)
                            Text("Version \(version)  ·  NG Studio")
                                .textStyle(Hint.copy(color: .white.opacity(0.85), textAlign: .Center))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 6)
                        Color.clear.frame(height: 24)
                    }
                    .padding(.horizontal, 16)
                }
            }
            PopupHost(visible: confirmReset, onDismiss: { confirmReset = false }) {
                GamePanel("Reset?", ribbon: .Red, onClose: { confirmReset = false }) {
                    IconTile(.RETRY, .Red, size: 72, iconScale: 0.55)
                    Spacer().frame(height: 10)
                    Text("All levels, stars, coins and items will be erased. This cannot be undone.")
                        .textStyle(TextStyle(fontFamily: Fredoka, fontWeight: .SemiBold, fontSize: 17, color: GameColors.Ink, lineHeight: 23, textAlign: .Center))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer().frame(height: 16)
                    GameButton("Erase Everything", color: .Red, height: 54, fontSize: 20) {
                        repo.resetProgress(); sound.onMusicSettingChanged(); confirmReset = false
                    }
                    .frame(maxWidth: .infinity)
                    Spacer().frame(height: 10)
                    GameButton("Keep My Progress", color: .Green, height: 54, fontSize: 20, shine: true) { confirmReset = false }
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

/// Titled settings card (also used by the Extras' Accessibility group).
struct SettingsGroup<Content: View>: View {
    let title: String
    let icon: Ico
    @ViewBuilder let content: () -> Content

    var body: some View {
        SectionCard {
            HStack(alignment: .center, spacing: 0) {
                GameIcon(icon, tint: GameColors.Purple700).frame(width: 24, height: 24)
                Spacer().frame(width: 6)
                Text(title).textStyle(GroupTitle)
            }
            Spacer().frame(height: 6)
            content()
        }
        .frame(maxWidth: .infinity)
    }
}

private struct RowDivider: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(Color(argb: 0x1A4521C2))
            .frame(height: 1.5)
            .padding(.leading, 56)
            .frame(maxWidth: .infinity)
    }
}

/// Tappable row with an icon tile and a chevron; squishes slightly while pressed.
private struct LinkRow: View {
    let icon: Ico
    let color: BtnColor
    let label: String
    let onClick: () -> Void
    @Environment(SoundManager.self) var sound

    var body: some View {
        Button {
            sound.play(.BUTTON)
            onClick()
        } label: {
            HStack(alignment: .center, spacing: 0) {
                IconTile(icon, color, size: 44, iconScale: 0.62)
                Spacer().frame(width: 12)
                Text(label).textStyle(RowLabel).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(argb: 0x144521C2))
                    GameIcon(.CHEVRON, tint: GameColors.Purple700).frame(width: 20, height: 20)
                }
                .frame(width: 34, height: 34)
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(LinkRowStyle())
    }
}

private struct LinkRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        LinkRowPress(press: configuration.isPressed ? 1 : 0) { configuration.label }
            .animation(.compose(dampingRatio: 0.5, stiffness: 900), value: configuration.isPressed)
    }
}

private struct LinkRowPress<Label: View>: View, Animatable {
    var press: CGFloat
    @ViewBuilder let label: () -> Label
    var animatableData: CGFloat {
        get { press }
        set { press = newValue }
    }

    var body: some View {
        label()
            .background {
                if press > 0.01 {
                    RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color(argb: 0xFF4521C2).opacity(Double(0.08 * press)))
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .scaleEffect(1 - press * 0.03)
    }
}

struct LegalScreen: View {
    let page: String
    let onBack: () -> Void

    init(page: String, onBack: @escaping () -> Void) {
        self.page = page
        self.onBack = onBack
    }

    var body: some View {
        let title = page == "terms" ? "Terms of Service" : "Privacy Policy"
        ZStack {
            SkyBackground(Skies.Menu, particles: false).ignoresSafeArea()
            VStack(spacing: 0) {
                ScreenHeader(title, onBack: onBack)
                ZStack {
                    Color(argb: 0xFF7C55FF)
                    if let url = Bundle.main.url(forResource: page, withExtension: "html")
                        ?? Bundle.main.url(forResource: page, withExtension: "html", subdirectory: "Legal") {
                        LegalWebView(url: url, onClose: onBack)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .padding(4)
                .background {
                    ZStack {
                        RoundedRectangle(cornerRadius: 30, style: .continuous).fill(Color(argb: 0x4D0D0530)).offset(y: 8)
                        RoundedRectangle(cornerRadius: 30, style: .continuous)
                            .fill(LinearGradient(colors: [GameColors.RimTop, GameColors.RimBottom], startPoint: .top, endPoint: .bottom))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
            }
        }
    }
}
