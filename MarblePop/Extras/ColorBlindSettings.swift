import SwiftUI
import GameKit

private let ColorBlindHint = TextStyle(fontFamily: Fredoka, fontWeight: .SemiBold, fontSize: 14, color: GameColors.InkSoft)

/// Settings › Accessibility (Features.colorBlindPatterns): the colour-blind switch plus a live strip of every
/// marble with its symbol, built from the Settings screen's own card, toggle row and candy switch.
struct ColorBlindSettingsGroup: View {
    @Environment(GameRepository.self) var repo

    var body: some View {
        SettingsGroup(title: "Accessibility", icon: .PALETTE) {
            ToggleRow(icon: .PALETTE, label: "Colour-blind Mode", value: repo.colorBlind, color: .Orange) { repo.setColorBlind($0) }
            Text("Every colour gets its own symbol on marbles, cups and blocks.")
                .textStyle(ColorBlindHint)
                .fixedSize(horizontal: false, vertical: true)
            Spacer().frame(height: 10)
            ColorBlindStrip(on: repo.colorBlind, skin: repo.skin)
        }
    }
}

/// The 12 marble colours and the rainbow in a glass strip (the pause panel's inset style), drawn with the player's
/// skin; the symbols spring in one after another when the mode is switched on.
private struct ColorBlindStrip: View {
    let on: Bool
    let skin: Int

    private static let ids = Array(0..<MarbleColors.COUNT) + [MarbleColors.RAINBOW]

    var body: some View {
        GeometryReader { geo in
            let ids = ColorBlindStrip.ids
            let slot = geo.size.width / CGFloat(ids.count)
            let d = min(24, slot - 2)
            HStack(spacing: 0) {
                ForEach(Array(ids.enumerated()), id: \.offset) { i, id in
                    ColorBlindStripMarble(colorId: id, skin: skin, diameter: d, on: on, index: i)
                        .frame(width: slot, height: geo.size.height)
                }
            }
        }
        .frame(height: 28)
        .padding(.vertical, 7)
        .padding(.horizontal, 6)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color(argb: 0x0F4521C2)))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(Color(argb: 0x1F4521C2), lineWidth: 1.5))
        .accessibilityHidden(true)
    }
}

private struct ColorBlindStripMarble: View {
    let colorId: Int
    let skin: Int
    let diameter: CGFloat
    let on: Bool
    let index: Int
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        let d = diameter, id = colorId, skin = self.skin
        ZStack {
            Canvas { ctx, size in
                ball(ctx, CGPoint(x: size.width / 2, y: size.height / 2), d / 2, id, skin)
            }
            if let symbol = ColorBlindSymbol.of(colorId) {
                // same proportion as in game: the symbol's half size is half the marble radius
                ColorBlindArt.image(symbol, side: d * 0.7, displayScale: displayScale)
                    .scaleEffect(on ? 1 : 0.3)
                    .opacity(on ? 1 : 0)
                    .animation(Motion.reduce ? .easeOut(duration: 0.18)
                               : .compose(dampingRatio: 0.48, stiffness: 520).delay(Double(index) * 0.03), value: on)
            }
        }
    }
}
