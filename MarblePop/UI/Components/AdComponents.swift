import SwiftUI
import GameKit

// Port of ui/components/AdComponents.kt.
// iOS ships no fake ads: the reward button calls GameKit `Ads.rewarded.show(placement)` (granted instantly in this
// build) and reads "FREE" while `Ads.usesRealAds` is false; the Android debug "TEST AD" overlay is not ported.

/// "Unlock with an ad" dialog used for locked levels, marble skins and themes.
/// The reward button only appears when `Ads.rewarded` is available; [coinPrice] adds an optional "Buy" alternative.
struct WatchAdDialog<Preview: View>: View {
    var visible: Bool
    let title: String
    let message: String
    let placement: AdPlacement
    let onUnlocked: () -> Void
    let onClose: () -> Void
    var coinPrice: Int?
    var coins: Int
    var onBuy: (() -> Void)?
    let preview: () -> Preview

    init(visible: Bool = true, title: String, message: String, placement: AdPlacement,
         onUnlocked: @escaping () -> Void, onClose: @escaping () -> Void,
         coinPrice: Int? = nil, coins: Int = 0, onBuy: (() -> Void)? = nil,
         @ViewBuilder preview: @escaping () -> Preview) {
        self.visible = visible
        self.title = title
        self.message = message
        self.placement = placement
        self.onUnlocked = onUnlocked
        self.onClose = onClose
        self.coinPrice = coinPrice
        self.coins = coins
        self.onBuy = onBuy
        self.preview = preview
    }

    var body: some View {
        let ads = Ads.rewarded
        PopupHost(visible: visible, onDismiss: onClose) {
            GamePanel(title, ribbon: .Pink, onClose: onClose, rays: true) {
                ZStack { preview() }.frame(width: 150, height: 120)
                Spacer().frame(height: 8)
                Text(message)
                    .font(.fredoka(17))
                    .foregroundStyle(GameColors.Ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer().frame(height: 16)
                if ads.isAvailable {
                    GameButton(Ads.usesRealAds ? "Watch Ad" : "FREE", color: .Green, icon: .PLAY, shine: true) {
                        ads.show(placement) { rewarded in if rewarded { onUnlocked() } }
                        onClose()
                    }
                    .idleBounce(amount: 0.04)
                }
                if let coinPrice, let onBuy {
                    Spacer().frame(height: 10)
                    GameButton("Buy  \(coinPrice)", color: .Yellow, height: 54, fontSize: 22, enabled: coins >= coinPrice,
                               icon: .COIN, sound: .COIN) { onBuy() }
                }
                if !ads.isAvailable && onBuy == nil {
                    Text("Keep playing to unlock this!")
                        .font(.fredoka(15))
                        .foregroundStyle(GameColors.InkSoft)
                }
            }
        }
    }
}

/// Android debug builds show a fake full-screen "TEST AD" here. iOS never shows a fake ad (rewards come from
/// `Ads.rewarded`), so this renders nothing; it is kept so the app root can be ported unchanged.
struct DebugAdOverlay: View {
    var body: some View { EmptyView() }
}
