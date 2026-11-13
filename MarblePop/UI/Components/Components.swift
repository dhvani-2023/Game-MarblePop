import SwiftUI
import GameKit

// Port of ui/components/Components.kt: candy text, 3D jelly buttons, pills, ribbons, panels, popups, toggles…
//
// Kotlin `LocalSound` / `LocalRepo` composition locals: on iOS the app shell injects the shared `SoundManager` and
// `GameRepository` with `.environment(sound)` / `.environment(repo)`; components read them with
// `@Environment(SoundManager.self) var snd: SoundManager?` (nullable like `LocalSound`).
//
// Compose `modifier` parameters are dropped: apply SwiftUI modifiers to the view instead. Buttons, tubes and switches
// fill the width they are offered (every Android call site uses fillMaxWidth / weight / an explicit width).

/// Jelly colours: gradient top/bottom, the darker "side" (depth) and the outline.
enum BtnColor: CaseIterable {
    case Green, Yellow, Pink, Purple, Blue, Red, Orange, Gray

    private var argb: (UInt32, UInt32, UInt32, UInt32) {
        switch self {
        case .Green: return (0xFF9DF58A, 0xFF2FBF4F, 0xFF198A3A, 0xFF0E5A26)
        case .Yellow: return (0xFFFFEB85, 0xFFFFB21A, 0xFFD27A00, 0xFF8A4A00)
        case .Pink: return (0xFFFFA8D4, 0xFFFF4C97, 0xFFC42A6E, 0xFF7E1546)
        case .Purple: return (0xFFC8ADFF, 0xFF8150FF, 0xFF5428C9, 0xFF331589)
        case .Blue: return (0xFF9BE9FF, 0xFF26ACF2, 0xFF1373BE, 0xFF0A4A80)
        case .Red: return (0xFFFFA3A3, 0xFFFF4D5E, 0xFFC0283A, 0xFF7D1222)
        case .Orange: return (0xFFFFCB85, 0xFFFF8A1F, 0xFFCF5E00, 0xFF853A00)
        case .Gray: return (0xFFE6E3EF, 0xFFABA6C2, 0xFF77718F, 0xFF4A4562)
        }
    }

    var top: Color { Color(argb: argb.0) }
    var bottom: Color { Color(argb: argb.1) }
    var depth: Color { Color(argb: argb.2) }
    var outline: Color { Color(argb: argb.3) }
}

private let GlossTextBrush = Brush.verticalGradient(stops: [
    (0, Color.white.opacity(0.62)), (0.46, Color.white.opacity(0.12)), (0.5, Color.clear), (1, Color.clear),
])

// MARK: - OutlinedText

/// Candy text: soft drop-shadow stroke, thick outline, flat or gradient fill and an optional gloss layer.
/// Outline width scales with the font size.
struct OutlinedText: View {
    let text: String
    var fontSize: CGFloat
    var color: Color
    var outline: Color
    var outlineWidth: CGFloat
    var align: TextAlign
    var shadow: Bool
    var brush: Brush?
    var gloss: Bool
    var maxLines: Int

    init(_ text: String, fontSize: CGFloat = 24, color: Color = .white, outline: Color = GameColors.Ink,
         outlineWidth: CGFloat = 0, align: TextAlign = .Center, shadow: Bool = true, brush: Brush? = nil,
         gloss: Bool = false, maxLines: Int = Int.max) {
        self.text = text
        self.fontSize = fontSize
        self.color = color
        self.outline = outline
        self.outlineWidth = outlineWidth
        self.align = align
        self.shadow = shadow
        self.brush = brush
        self.gloss = gloss
        self.maxLines = maxLines
    }

    var body: some View {
        let ow = outlineWidth > 0 ? outlineWidth : fontSize * 0.17
        let radius = ow / 2
        let n = radius < 1.5 ? 8 : (radius < 3 ? 12 : 16)
        let base = Text(text).font(GameFonts.lilita(fontSize))
        let lines: Int? = maxLines == Int.max ? nil : maxLines
        ZStack {
            if shadow {
                OutlineCopies(base: base, color: outline, radius: radius, count: n)
                    .compositingGroup()
                    .opacity(0.5)
                    .offset(y: fontSize * 0.09)
            }
            OutlineCopies(base: base, color: outline, radius: radius, count: n)
            if let brush {
                base.foregroundStyle(brush)
            } else {
                base.foregroundStyle(color)
            }
            if gloss { base.foregroundStyle(GlossTextBrush) }
        }
        .lineLimit(lines)
        .multilineTextAlignment(align.swiftUI)
        .frame(height: lines == 1 ? fontSize * 1.05 : nil) // Compose lineHeight = 1.05 em
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

/// N offset copies give a round, even outline of the given radius (a centred stroke of twice that width).
private struct OutlineCopies: View {
    let base: Text
    let color: Color
    let radius: CGFloat
    let count: Int

    var body: some View {
        ZStack {
            ForEach(0..<count, id: \.self) { i in
                let a = Double(i) / Double(count) * 2 * Double.pi
                base.foregroundStyle(color).offset(x: CGFloat(cos(a)) * radius, y: CGFloat(sin(a)) * radius)
            }
        }
    }
}

/// Kotlin `rememberShine(periodMs, sweepMs)` value at `seconds` since start: 0..1 while sweeping, >1 while resting.
func shineValue(_ seconds: Double, periodMs: Int = 3000, sweepMs: Int = 700) -> CGFloat {
    let period = Double(periodMs) / 1000
    return CGFloat(seconds.truncatingRemainder(dividingBy: period) / (Double(sweepMs) / 1000))
}

// MARK: - GameButton

/// Chunky jelly button: soft shadow, depth side, gradient body, inner shade, gloss, outline,
/// an optional light streak ([shine]) and a springy press that sinks the body into its side.
struct GameButton: View {
    let text: String
    var color: BtnColor
    var height: CGFloat
    var fontSize: CGFloat
    var enabled: Bool
    var icon: Ico?
    var corner: CGFloat
    var sound: Sfx
    var shine: Bool
    var iconSize: CGFloat?
    let onClick: () -> Void

    @Environment(SoundManager.self) private var snd: SoundManager?

    init(_ text: String, color: BtnColor = .Green, height: CGFloat = 62, fontSize: CGFloat = 26, enabled: Bool = true,
         icon: Ico? = nil, corner: CGFloat = 20, sound: Sfx = .BUTTON, shine: Bool = false, iconSize: CGFloat? = nil,
         onClick: @escaping () -> Void) {
        self.text = text
        self.color = color
        self.height = height
        self.fontSize = fontSize
        self.enabled = enabled
        self.icon = icon
        self.corner = corner
        self.sound = sound
        self.shine = shine
        self.iconSize = iconSize
        self.onClick = onClick
    }

    var body: some View {
        Button {
            snd?.play(sound)
            snd?.haptic(.LIGHT)
            onClick()
        } label: {
            Color.clear
        }
        .buttonStyle(GameButtonStyle(button: self))
        .disabled(!enabled)
        .accessibilityLabel(text)
    }
}

private struct GameButtonStyle: ButtonStyle {
    let button: GameButton

    func makeBody(configuration: Configuration) -> some View {
        GameButtonBody(b: button, pressed: configuration.isPressed)
    }
}

private struct GameButtonBody: View {
    let b: GameButton
    let pressed: Bool

    var body: some View {
        let col = b.enabled ? b.color : .Gray
        let depth = b.height * 0.11
        let press: CGFloat = pressed ? 1 : 0
        ZStack {
            JellyButtonArt(col: col, corner: b.corner, depth: depth, press: press, shine: b.shine && b.enabled)
            HStack(spacing: 0) {
                if let icon = b.icon {
                    let isz = b.iconSize ?? b.height * 0.5
                    GameIcon(icon).frame(width: isz, height: isz)
                    if !b.text.isEmpty { Spacer().frame(width: 7) }
                }
                if !b.text.isEmpty { OutlinedText(b.text, fontSize: b.fontSize, outline: col.outline, maxLines: 1) }
            }
            .padding(.horizontal, b.text.isEmpty ? 0 : 14)
            .offset(y: -depth / 2 + press * depth * 0.8)
        }
        .frame(maxWidth: .infinity)
        .frame(height: b.height)
        .contentShape(Rectangle())
        .scaleEffect(1 - press * 0.035)
        .animation(.compose(dampingRatio: 0.45, stiffness: 1100), value: pressed)
    }
}

/// The drawn jelly body; `press` is animatable so the body sinks smoothly into its side.
private struct JellyButtonArt: View, Animatable {
    let col: BtnColor
    let corner: CGFloat
    let depth: CGFloat
    var press: CGFloat
    let shine: Bool
    @State private var start = Date()

    init(col: BtnColor, corner: CGFloat, depth: CGFloat, press: CGFloat, shine: Bool) {
        self.col = col
        self.corner = corner
        self.depth = depth
        self.press = press
        self.shine = shine
    }

    var animatableData: CGFloat {
        get { press }
        set { press = newValue }
    }

    var body: some View {
        if shine && !Motion.reduce {
            TimelineView(.animation) { tl in
                art(shineValue(tl.date.timeIntervalSince(start)))
            }
        } else {
            art(nil)
        }
    }

    private func art(_ shineP: CGFloat?) -> some View {
        let col = self.col, corner = self.corner, d = self.depth, press = self.press
        let bleed: CGFloat = 6
        // The changing values (press, shineP) are captured directly by the Canvas closure so SwiftUI redraws it.
        return Canvas { ctx0, full in
            _ = press; _ = shineP
            var ctx = ctx0
            ctx.translateBy(x: bleed, y: bleed)
            let size = CGSize(width: max(0, full.width - 2 * bleed), height: max(0, full.height - 2 * bleed))
            let cd = ComposeDraw(ctx, size)
            let w = size.width, h = size.height
            let bodyH = h - d
            let r = min(corner, bodyH / 2)
            let body = ComposeDraw.roundRectPath(0, 0, w, bodyH, r)
            let bodyBrush = cd.vGrad([col.top, col.bottom], 0, bodyH)
            let shade = cd.vGrad(stops: [.init(color: .clear, location: 0.5), .init(color: col.depth.opacity(0.45), location: 1)], 0, bodyH)
            let glossTop = bodyH * 0.07
            let glossH = bodyH * 0.38
            let glossBrush = cd.vGrad([.white.opacity(0.62), .white.opacity(0.08)], glossTop, glossTop + glossH)
            let ow: CGFloat = 2.2
            let sh: CGFloat = 3
            let py = press * d * 0.8
            cd.roundRect(.color(Color(argb: 0x38140A3C)), 0, d + sh, w, bodyH, r)
            cd.roundRect(.color(col.depth), 0, d, w, bodyH, r)
            let t = cd.translated(0, py)
            t.path(body, bodyBrush)
            t.path(body, shade)
            t.roundRect(glossBrush, w * 0.05, glossTop, w * 0.9, glossH, min(r * 0.8, glossH / 2))
            if let p = shineP, p <= 1 {
                let bandW = w * 0.14 + bodyH * 0.2
                var band = Path()
                band.move(to: CGPoint(x: bodyH * 0.55, y: -2)); band.addLine(to: CGPoint(x: bodyH * 0.55 + bandW, y: -2))
                band.addLine(to: CGPoint(x: bandW, y: bodyH + 2)); band.addLine(to: CGPoint(x: 0, y: bodyH + 2)); band.closeSubpath()
                t.clipped(body).translated(-bandW - bodyH * 0.6 + p * (w + bandW * 2 + bodyH), 0).path(band, .color(.white.opacity(0.4)))
            }
            cd.roundRect(.color(col.outline), ow / 2, py + ow / 2, w - ow, h - py - ow, max(r - ow / 2, 0), stroke: ow)
        }
        .padding(-bleed)
        .allowsHitTesting(false)
    }
}

struct IconRoundButton: View {
    let icon: Ico
    var size: CGFloat
    var color: BtnColor
    var iconScale: CGFloat
    let onClick: () -> Void

    init(_ icon: Ico, size: CGFloat = 48, color: BtnColor = .Purple, iconScale: CGFloat = 0.6, onClick: @escaping () -> Void) {
        self.icon = icon
        self.size = size
        self.color = color
        self.iconScale = iconScale
        self.onClick = onClick
    }

    var body: some View {
        GameButton("", color: color, height: size, icon: icon, corner: size * 0.36, iconSize: size * iconScale, onClick: onClick)
            .frame(width: size, height: size)
            .accessibilityLabel(icon.rawValue.lowercased())
    }
}

// MARK: - ResourcePill

/// Dark glass capsule with an overlapping icon; the icon bumps whenever the value changes.
struct ResourcePill: View {
    let icon: Ico
    let value: String
    var onPlus: (() -> Void)?

    init(_ icon: Ico, _ value: String, onPlus: (() -> Void)? = nil) {
        self.icon = icon
        self.value = value
        self.onPlus = onPlus
    }

    var body: some View {
        OutlinedText(value, fontSize: 19, maxLines: 1)
            .padding(.vertical, 2)
            .padding(.leading, 26)
            .padding(.trailing, onPlus != nil ? 36 : 14)
            .background(BleedCanvas(bleed: 3) { ctx, size in
                let cd = ComposeDraw(ctx, size)
                let w = size.width, h = size.height
                let r = h / 2
                let fill = cd.vGrad([Color(argb: 0xD9180A4C), Color(argb: 0xD93A1C9E)])
                let inner = cd.vGrad([Color(argb: 0x55000000), .clear], 0, h * 0.45)
                let rim: CGFloat = 1.2
                let ow: CGFloat = 1.8
                cd.roundRect(.color(.white.opacity(0.3)), -rim, -rim, w + rim * 2, h + rim * 2, r + rim, stroke: rim)
                cd.roundRect(fill, 0, 0, w, h, r)
                cd.roundRect(inner, 0, 0, w, h, r)
                cd.roundRect(.color(.white.opacity(0.14)), h * 0.5, h * 0.74, w - h, h * 0.1, h * 0.05)
                cd.roundRect(.color(Color(argb: 0xFF12073A)), ow / 2, ow / 2, w - ow, h - ow, r - ow / 2, stroke: ow)
            })
            .padding(.leading, 16)
            .padding(.vertical, 5)
            .frame(height: 44, alignment: .top)
            .overlay(alignment: .leading) {
                GameIcon(icon)
                    .frame(width: 40, height: 40)
                    .keyframeAnimator(initialValue: CGFloat(1), trigger: value) { content, s in
                        content.scaleEffect(s)
                    } keyframes: { _ in
                        MoveKeyframe(1.32)
                        SpringKeyframe(1, spring: Spring(mass: 1, stiffness: 520, damping: 2 * 0.38 * 520.0.squareRoot()))
                    }
            }
            .overlay(alignment: .trailing) {
                if let onPlus {
                    IconRoundButton(.PLUS, size: 34, color: .Green, iconScale: 0.5, onClick: onPlus)
                        .offset(x: 2)
                }
            }
    }
}

// MARK: - Ribbon / panel

/// Ribbon banner with folded tails, used as the title of popups.
struct Ribbon: View {
    let title: String
    let color: BtnColor
    var fontSize: CGFloat
    var minWidth: CGFloat
    var height: CGFloat

    init(_ title: String, _ color: BtnColor, fontSize: CGFloat = 30, minWidth: CGFloat = 220, height: CGFloat = 58) {
        self.title = title
        self.color = color
        self.fontSize = fontSize
        self.minWidth = minWidth
        self.height = height
    }

    var body: some View {
        let color = self.color
        OutlinedText(title, fontSize: fontSize, outline: color.outline, gloss: true, maxLines: 1)
            .padding(.horizontal, height * 0.45)
            .frame(height: height * 0.9)
            .frame(minWidth: minWidth)
            .frame(height: height, alignment: .top)
            .background(BleedCanvas(bleed: height * 0.6, key: BtnColor.allCases.firstIndex(of: color) ?? 0) { ctx, size in
                let cd = ComposeDraw(ctx, size)
                let w = size.width
                let d = size.height * 0.1
                let bandH = size.height - d
                let tail = size.height * 0.41
                let drop = size.height * 0.2
                let tailH = bandH * 0.78
                let r = size.height * 0.28
                func tailPath(_ left: Bool) -> Path {
                    let s: CGFloat = left ? -1 : 1
                    let x0 = left ? tail * 0.7 : w - tail * 0.7
                    let xo = left ? -tail : w + tail
                    var p = Path()
                    p.move(to: CGPoint(x: x0, y: drop)); p.addLine(to: CGPoint(x: xo, y: drop))
                    p.addLine(to: CGPoint(x: xo + s * -tail * 0.45, y: drop + tailH / 2)); p.addLine(to: CGPoint(x: xo, y: drop + tailH))
                    p.addLine(to: CGPoint(x: x0, y: drop + tailH)); p.closeSubpath()
                    return p
                }
                let lt = tailPath(true)
                let rt = tailPath(false)
                var fold = Path()
                fold.move(to: CGPoint(x: tail * 0.7, y: drop + tailH)); fold.addLine(to: CGPoint(x: tail * 0.7 + tail * 0.6, y: bandH + d))
                fold.addLine(to: CGPoint(x: tail * 0.7 + tail * 0.6, y: drop + tailH)); fold.closeSubpath()
                fold.move(to: CGPoint(x: w - tail * 0.7, y: drop + tailH)); fold.addLine(to: CGPoint(x: w - tail * 0.7 - tail * 0.6, y: bandH + d))
                fold.addLine(to: CGPoint(x: w - tail * 0.7 - tail * 0.6, y: drop + tailH)); fold.closeSubpath()
                let bandBrush = cd.vGrad([color.top, color.bottom], 0, bandH)
                let tailBrush = cd.vGrad([color.bottom, color.depth], drop, drop + tailH)
                let gloss = cd.vGrad([.white.opacity(0.55), .white.opacity(0.05)], bandH * 0.08, bandH * 0.48)
                let ow: CGFloat = 2.2
                cd.path(lt, tailBrush); cd.path(rt, tailBrush)
                cd.path(lt, .color(color.outline), stroke: StrokeStyle(lineWidth: ow, lineJoin: .round))
                cd.path(rt, .color(color.outline), stroke: StrokeStyle(lineWidth: ow, lineJoin: .round))
                cd.path(fold, .color(color.outline))
                cd.roundRect(.color(Color(argb: 0x40140A3C)), 0, d + 3, w, bandH, r)
                cd.roundRect(.color(color.depth), 0, d, w, bandH, r)
                cd.roundRect(bandBrush, 0, 0, w, bandH, r)
                cd.roundRect(gloss, w * 0.04, bandH * 0.08, w * 0.92, bandH * 0.4, r * 0.7)
                cd.roundRect(.color(color.outline), ow / 2, ow / 2, w - ow, size.height - ow, r - ow / 2, stroke: ow)
            })
    }
}

/// Popup card: gradient rim frame, cream interior with a faint dot pattern, ribbon title, optional sun rays behind.
struct GamePanel<Content: View>: View {
    let title: String
    var ribbon: BtnColor
    var onClose: (() -> Void)?
    var rays: Bool
    let content: Content

    init(_ title: String, ribbon: BtnColor = .Purple, onClose: (() -> Void)? = nil, rays: Bool = false,
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.ribbon = ribbon
        self.onClose = onClose
        self.rays = rays
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) { content }
                .padding(EdgeInsets(top: 44, leading: 18, bottom: 20, trailing: 18))
                .frame(maxWidth: .infinity)
                .background(Canvas { ctx, size in
                    let cd = ComposeDraw(ctx, size)
                    cd.rect(Grad.PanelFill.shading(CGRect(origin: .zero, size: size)), 0, 0, size.width, size.height)
                    var dots = Path()
                    let step: CGFloat = 18
                    let dr: CGFloat = 1.7
                    var y = step / 2
                    var row = 0
                    while y < size.height {
                        var x = row % 2 == 0 ? step / 2 : step
                        while x < size.width { dots.addEllipse(in: CGRect(x: x - dr, y: y - dr, width: dr * 2, height: dr * 2)); x += step }
                        y += step; row += 1
                    }
                    cd.path(dots, .color(Color(argb: 0x0F4521C2)))
                    cd.rect(cd.vGrad([.clear, Color(argb: 0x1A4521C2)], size.height * 0.7, size.height), 0, 0, size.width, size.height)
                    cd.roundRect(.color(.white), 2, 2, size.width - 4, size.height - 4, 27, stroke: 2)
                })
                .clipShape(RoundedRectangle(cornerRadius: 29, style: .circular))
                .padding(EdgeInsets(top: 5, leading: 5, bottom: 9, trailing: 5))
                .background(BleedCanvas(bleed: 14) { ctx, size in
                    let cd = ComposeDraw(ctx, size)
                    cd.roundRect(.color(Color(argb: 0x4D0D0530)), 0, 10, size.width, size.height, 34)
                    cd.roundRect(.color(Color(argb: 0x260D0530)), -4, 4, size.width + 8, size.height + 12, 34 + 4)
                    cd.roundRect(Grad.PanelRim.shading(CGRect(origin: .zero, size: size)), 0, 0, size.width, size.height, 34)
                })
                .padding(.top, 30)
            Ribbon(title, ribbon, minWidth: 190)
                .padding(.horizontal, 40)
        }
        .overlay(alignment: .topTrailing) {
            if let onClose {
                IconRoundButton(.CLOSE, size: 46, color: .Red, iconScale: 0.46, onClick: onClose)
                    .offset(x: 8, y: 18)
            }
        }
        .background {
            if rays { SunRays(color: Color(argb: 0xFFFFF3B0), alpha: 0.28, radiusScale: 0.95) }
        }
        .frame(maxWidth: 380)
    }
}

/// Kotlin `rememberLatest(value)`: keeps the last non-null value so a closing popup can still render its content while
/// animating out. Hold it in `@State` and call it with the current value.
final class LatestBox<T> {
    private(set) var value: T?
    init() {}
    func callAsFunction(_ v: T?) -> T? {
        if let v { value = v }
        return value
    }
}

// MARK: - PopupHost

/// Dimmed overlay hosting a popup. Animates in (dim fade + springy pop) and, when [visible] turns
/// false, animates out before leaving the hierarchy. Place it in a full-screen ZStack.
struct PopupHost<Content: View>: View {
    var visible: Bool
    var onDismiss: (() -> Void)?
    var dim: Float
    let content: () -> Content

    @State private var present = false
    @State private var p: CGFloat = 0
    @State private var dimA: Double = 0
    @State private var entering = true
    @Environment(SoundManager.self) private var snd: SoundManager?

    init(visible: Bool = true, onDismiss: (() -> Void)? = nil, dim: Float = 0.66, @ViewBuilder content: @escaping () -> Content) {
        self.visible = visible
        self.onDismiss = onDismiss
        self.dim = dim
        self.content = content
    }

    var body: some View {
        ZStack {
            if present {
                PopupDim(dim: Double(dim))
                    .opacity(dimA)
                    .contentShape(Rectangle())
                    .onTapGesture { if visible { onDismiss?() } }
                content()
                    .padding(20)
                    .contentShape(Rectangle())
                    .onTapGesture {}
                    .scaleEffect(entering ? 0.72 + 0.28 * p : 0.88 + 0.12 * p)
                    .opacity(Double(min(max(p, 0), 1)))
                    .offset(y: entering ? (1 - p) * 36 : 0)
                    .onAppear { animateIn() }
            }
        }
        .onAppear { if visible && !present { entering = true; p = 0; dimA = 0; present = true } }
        .onChange(of: visible) { _, v in
            if v {
                if present { animateIn() } else { entering = true; p = 0; dimA = 0; present = true }
            } else if present {
                animateOut()
            }
        }
    }

    private func animateIn() {
        snd?.play(.WHOOSH, pitch: 1.1, volume: 0.6)
        entering = true
        withAnimation(.compose(dampingRatio: 0.6, stiffness: 430)) { p = 1 }
        withAnimation(CubicBezierEasing.FastOutSlowIn.tween(220)) { dimA = 1 }
    }

    private func animateOut() {
        withAnimation(Motion.EaseOut.tween(170)) {
            entering = false
            p = 0
        } completion: {
            if !visible { present = false }
        }
        withAnimation(CubicBezierEasing.FastOutSlowIn.tween(190)) { dimA = 0 }
    }
}

private struct PopupDim: View {
    let dim: Double

    var body: some View {
        Canvas { ctx, size in
            let r = CGRect(origin: .zero, size: size)
            ctx.fill(Path(r), with: .color(Color(argb: 0xFF12082E).opacity(dim)))
            ctx.fill(Path(r), with: .radialGradient(
                Gradient(colors: [Color(argb: 0x00000000), Color(argb: 0xFF0A0420).opacity(dim * 0.5)]),
                center: CGPoint(x: size.width / 2, y: size.height / 2), startRadius: 0, endRadius: max(size.width, size.height) * 0.75))
        }
        .ignoresSafeArea()
    }
}

// MARK: - Small widgets

struct StarRow: View {
    let stars: Int
    var size: CGFloat

    init(_ stars: Int, size: CGFloat = 18) {
        self.stars = stars
        self.size = size
    }

    var body: some View {
        HStack(spacing: -2) {
            ForEach(0..<3, id: \.self) { i in
                GameIcon(i < stars ? .STAR : .STAR_EMPTY)
                    .frame(width: size, height: size)
                    .offset(y: i == 1 ? -3 : 0)
            }
        }
    }
}

/// Candy switch with ON/OFF label and a marble knob.
struct GameToggle: View {
    let checked: Bool
    let onChange: (Bool) -> Void
    @Environment(SoundManager.self) private var snd: SoundManager?

    init(_ checked: Bool, onChange: @escaping (Bool) -> Void) {
        self.checked = checked
        self.onChange = onChange
    }

    init(checked: Bool, onChange: @escaping (Bool) -> Void) {
        self.init(checked, onChange: onChange)
    }

    var body: some View {
        let pos: CGFloat = checked ? 1 : 0
        ZStack {
            ToggleArt(pos: pos, checked: checked)
            Text("ON").font(.lilita(13)).foregroundStyle(.white)
                .padding(.leading, 11).padding(.bottom, 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(Double(pos))
            Text("OFF").font(.lilita(13)).foregroundStyle(.white)
                .padding(.trailing, 9).padding(.bottom, 3)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .opacity(Double(1 - pos))
        }
        .frame(width: 78, height: 40)
        .clipShape(Capsule())
        .contentShape(Capsule())
        .onTapGesture {
            snd?.play(.BUTTON)
            snd?.haptic(.LIGHT)
            onChange(!checked)
        }
        .animation(.compose(dampingRatio: 0.55, stiffness: 520), value: checked)
        .accessibilityElement()
        .accessibilityAddTraits(.isButton)
        .accessibilityValue(checked ? "On" : "Off")
    }
}

private struct ToggleArt: View, Animatable {
    var pos: CGFloat
    let checked: Bool

    var animatableData: CGFloat {
        get { pos }
        set { pos = newValue }
    }

    var body: some View {
        let p = Float(pos), checked = self.checked
        return Canvas { ctx, size in
            _ = p; _ = checked
            let cd = ComposeDraw(ctx, size)
            let w = size.width, h = size.height
            let rr = h / 2
            let d: CGFloat = 3
            cd.roundRect(.color(lerp(Color(argb: 0xFF6E6889), Color(argb: 0xFF167A33), p)), 0, 0, w, h, rr)
            let top = lerp(Color(argb: 0xFFD3CFE2), Color(argb: 0xFF7BE37F), p)
            let bot = lerp(Color(argb: 0xFFA7A1BE), Color(argb: 0xFF2FBF4F), p)
            let inH = h - d - 2
            cd.roundRect(cd.vGrad([bot, top], 0, inH), 1.5, 1.5, w - 3, inH, inH / 2)
            cd.roundRect(cd.vGrad([Color(argb: 0x40000000), .clear], 0, inH * 0.5), 1.5, 1.5, w - 3, inH, inH / 2)
            let r = h * 0.4
            let cx = r + 3 + (w - 2 * r - 6) * CGFloat(p)
            ball(ctx, CGPoint(x: cx, y: h / 2 - 1.5), r, checked ? 3 : 8)
        }
    }
}

/// Header used by full screen sub pages (place it inside the safe area).
struct ScreenHeader: View {
    let title: String
    let onBack: () -> Void

    init(_ title: String, onBack: @escaping () -> Void) {
        self.title = title
        self.onBack = onBack
    }

    var body: some View {
        ZStack {
            IconRoundButton(.BACK, size: 50, color: .Yellow, iconScale: 0.5, onClick: onBack)
                .frame(maxWidth: .infinity, alignment: .leading)
            OutlinedText(title, fontSize: 32, brush: Grad.Snow, gloss: true, maxLines: 1)
        }
        .frame(height: 58)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Ambient motion modifiers

private struct PeriodicScaleEffect: GeometryEffect {
    var phase: CGFloat
    let amount: CGFloat
    let pulse: Bool

    var animatableData: CGFloat {
        get { phase }
        set { phase = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let w = sin(phase * 2 * .pi)
        let k = pulse ? max(w, 0) : 0.5 + 0.5 * w
        let s = 1 + amount * k
        let t = CGAffineTransform(translationX: size.width / 2, y: size.height / 2)
            .scaledBy(x: s, y: s)
            .translatedBy(x: -size.width / 2, y: -size.height / 2)
        return ProjectionTransform(t)
    }
}

private struct PeriodicOffsetEffect: GeometryEffect {
    var phase: CGFloat
    let amplitude: CGFloat
    let shift: CGFloat

    var animatableData: CGFloat {
        get { phase }
        set { phase = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 0, y: sin((phase + shift) * 2 * .pi) * amplitude))
    }
}

/// Drives a 0→1 phase with a repeating linear animation while `enabled` (and not Reduce Motion).
private struct PhaseDriver<E: GeometryEffect>: ViewModifier {
    let enabled: Bool
    let periodMs: Int
    let effect: (CGFloat) -> E
    @State private var phase: CGFloat = 0

    init(enabled: Bool, periodMs: Int, effect: @escaping (CGFloat) -> E) {
        self.enabled = enabled
        self.periodMs = periodMs
        self.effect = effect
    }

    func body(content: Content) -> some View {
        content
            .modifier(effect(phase))
            .onAppear { restart(enabled) }
            .onChange(of: enabled) { _, on in restart(on) }
    }

    private func restart(_ on: Bool) {
        var t = Transaction()
        t.disablesAnimations = true
        withTransaction(t) { phase = 0 }
        guard on, !Motion.reduce else { return }
        DispatchQueue.main.async {
            withAnimation(.linear(duration: Double(periodMs) / 1000).repeatForever(autoreverses: false)) { phase = 1 }
        }
    }
}

extension View {
    /// Gentle breathing pulse for call-to-action elements (render-only).
    func idleBounce(_ enabled: Bool = true, amount: Float = 0.05, periodMs: Int = 1400) -> some View {
        modifier(PhaseDriver(enabled: enabled, periodMs: periodMs) { ph in
            PeriodicScaleEffect(phase: ph, amount: enabled ? CGFloat(amount) : 0, pulse: false)
        })
    }

    func idleBounce(enabled: Bool, amount: Float = 0.05, periodMs: Int = 1400) -> some View {
        idleBounce(enabled, amount: amount, periodMs: periodMs)
    }

    /// Slow floating bob (translationY), phase-shifted so neighbours don't move in lockstep.
    func floaty(amplitude: CGFloat = 3, periodMs: Int = 2600, phase: Float = 0) -> some View {
        modifier(PhaseDriver(enabled: true, periodMs: periodMs) { ph in
            PeriodicOffsetEffect(phase: ph, amplitude: amplitude, shift: CGFloat(phase))
        })
    }

    /// Compose `Modifier.fillMaxWidth()`.
    func fillMaxWidth() -> some View { frame(maxWidth: .infinity) }
}

// MARK: - Cards & tiles

/// Candy card: gradient rim with a 3D bottom edge, cream interior with a soft bottom shade.
struct SectionCard<Content: View>: View {
    var padding: CGFloat
    let content: Content

    init(padding: CGFloat = 14, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .padding(padding)
            .background(Canvas { ctx, size in
                let cd = ComposeDraw(ctx, size)
                let r: CGFloat = 23
                cd.roundRect(Grad.PanelFill.shading(CGRect(origin: .zero, size: size)), 0, 0, size.width, size.height, r)
                cd.roundRect(cd.vGrad([.clear, Color(argb: 0x144521C2)], size.height * 0.6, size.height), 0, 0, size.width, size.height, r)
            })
            .padding(EdgeInsets(top: 3, leading: 3, bottom: 6, trailing: 3))
            .background(BleedCanvas(bleed: 8) { ctx, size in
                let cd = ComposeDraw(ctx, size)
                cd.roundRect(.color(Color(argb: 0x400D0530)), 0, 6, size.width, size.height, 26)
                cd.roundRect(Grad.PanelRim.shading(CGRect(origin: .zero, size: size)), 0, 0, size.width, size.height, 26)
            })
    }
}

/// Gradient rounded-square tile holding an icon.
struct IconTile: View {
    let icon: Ico
    let color: BtnColor
    var size: CGFloat
    var iconScale: CGFloat

    init(_ icon: Ico, _ color: BtnColor, size: CGFloat = 44, iconScale: CGFloat = 0.64) {
        self.icon = icon
        self.color = color
        self.size = size
        self.iconScale = iconScale
    }

    var body: some View {
        let color = self.color
        ZStack {
            Canvas { ctx, sz in
                let cd = ComposeDraw(ctx, sz)
                let w = sz.width, h = sz.height
                let d: CGFloat = 3
                let r = w * 0.3
                let body = cd.vGrad([color.top, color.bottom], 0, h - d)
                let gloss = cd.vGrad([.white.opacity(0.6), .white.opacity(0.05)], 0, (h - d) * 0.46)
                let ow: CGFloat = 1.6
                cd.roundRect(.color(color.depth), 0, d, w, h - d, r)
                cd.roundRect(body, 0, 0, w, h - d, r)
                cd.roundRect(gloss, w * 0.08, h * 0.05, w * 0.84, (h - d) * 0.42, r * 0.7)
                cd.roundRect(.color(color.outline), ow / 2, ow / 2, w - ow, h - ow, r, stroke: ow)
            }
            GameIcon(icon)
                .frame(width: size * iconScale, height: size * iconScale)
                .offset(y: -1.5)
        }
        .frame(width: size, height: size)
    }
}

/// Small gradient pill label (e.g. "BEST VALUE", rarity, "-17%").
struct Chip: View {
    let text: String
    let color: BtnColor
    var fontSize: CGFloat

    init(_ text: String, _ color: BtnColor, fontSize: CGFloat = 12) {
        self.text = text
        self.color = color
        self.fontSize = fontSize
    }

    var body: some View {
        let color = self.color
        OutlinedText(text, fontSize: fontSize, outline: color.outline, shadow: false, maxLines: 1)
            .padding(.horizontal, 9)
            .padding(.vertical, 2)
            .background(Canvas { ctx, size in
                let cd = ComposeDraw(ctx, size)
                let h = size.height
                let r = h / 2
                let ow: CGFloat = 1.5
                cd.roundRect(cd.vGrad([color.top, color.bottom]), 0, 0, size.width, h, r)
                cd.roundRect(.color(.white.opacity(0.35)), h * 0.3, h * 0.12, size.width - h * 0.6, h * 0.28, h * 0.14)
                cd.roundRect(.color(color.outline), ow / 2, ow / 2, size.width - ow, h - ow, r - ow / 2, stroke: ow)
            })
    }
}

/// Track with a sliding jelly thumb.
struct SegmentedSwitch: View {
    let options: [String]
    let selected: Int
    let onSelect: (Int) -> Void
    @Environment(SoundManager.self) private var snd: SoundManager?

    init(_ options: [String], _ selected: Int, onSelect: @escaping (Int) -> Void) {
        self.options = options
        self.selected = selected
        self.onSelect = onSelect
    }

    var body: some View {
        let c = BtnColor.Pink
        ZStack {
            SegmentArt(pos: CGFloat(selected), count: options.count)
            HStack(spacing: 0) {
                ForEach(Array(options.enumerated()), id: \.offset) { i, label in
                    OutlinedText(label, fontSize: 20, color: i == selected ? .white : .white.opacity(0.72),
                                 outline: i == selected ? c.outline : GameColors.Ink, maxLines: 1)
                        .offset(y: -1)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if i != selected {
                                snd?.play(.BUTTON)
                                onSelect(i)
                            }
                        }
                        .accessibilityAddTraits(i == selected ? [.isButton, .isSelected] : .isButton)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 54)
        .animation(Motion.snappy(), value: selected)
    }
}

private struct SegmentArt: View, Animatable {
    var pos: CGFloat
    let count: Int

    var animatableData: CGFloat {
        get { pos }
        set { pos = newValue }
    }

    var body: some View {
        let pos = self.pos, n = max(count, 1)
        let c = BtnColor.Pink
        let bleed: CGFloat = 2
        return Canvas { ctx0, full in
            _ = pos
            var ctx = ctx0
            ctx.translateBy(x: bleed, y: bleed)
            let size = CGSize(width: max(0, full.width - 2 * bleed), height: max(0, full.height - 2 * bleed))
            let cd = ComposeDraw(ctx, size)
            let w = size.width, h = size.height
            let rr = h / 2
            let pad: CGFloat = 4
            let tw = (w - pad * 2) / CGFloat(n)
            let th = h - pad * 2
            let d: CGFloat = 4
            let tr = (th - d) / 2
            let thumb = cd.vGrad([c.top, c.bottom], pad, pad + th - d)
            let gloss = cd.vGrad([.white.opacity(0.55), .white.opacity(0.05)], pad, pad + (th - d) * 0.5)
            cd.roundRect(.color(Color(argb: 0x73140A3C)), 0, 0, w, h, rr)
            cd.roundRect(.color(Color(argb: 0x33000000)), 0, 0, w, h * 0.5, rr)
            cd.roundRect(.color(.white.opacity(0.28)), 0, 0, w, h, rr, stroke: 1.5)
            let x = pad + tw * pos
            cd.roundRect(.color(c.depth), x, pad + d, tw, th - d, tr)
            cd.roundRect(thumb, x, pad, tw, th - d, tr)
            cd.roundRect(gloss, x + tw * 0.06, pad + (th - d) * 0.08, tw * 0.88, (th - d) * 0.38, tr * 0.7)
            cd.roundRect(.color(c.outline), x, pad, tw, th, tr, stroke: 1.8)
        }
        .padding(-bleed)
        .allowsHitTesting(false)
    }
}

/// Glass tube progress bar with gloss; optional centred label.
struct ProgressTube: View {
    let progress: Float
    var height: CGFloat
    var fill: BtnColor
    var label: String?

    init(_ progress: Float, height: CGFloat = 16, fill: BtnColor = .Green, label: String? = nil) {
        self.progress = progress
        self.height = height
        self.fill = fill
        self.label = label
    }

    var body: some View {
        let fill = self.fill, progress = self.progress
        ZStack {
            Canvas { ctx, size in
                let cd = ComposeDraw(ctx, size)
                let h = size.height
                let rr = h / 2
                cd.roundRect(.color(Color(argb: 0x2E2A1463)), 0, 0, size.width, h, rr)
                cd.roundRect(cd.vGrad([Color(argb: 0x40000000), .clear], 0, h * 0.55), 0, 0, size.width, h, rr)
                let p = CGFloat(min(max(progress, 0), 1))
                if p > 0 {
                    let w = max(size.width * p, h)
                    cd.roundRect(.color(fill.depth), 0, 0, w, h, rr)
                    cd.roundRect(cd.vGrad([fill.top, fill.bottom]), 0, 0, w, h - 2, rr)
                    cd.roundRect(.color(.white.opacity(0.5)), h * 0.32, h * 0.15, max(w - h * 0.64, 0), h * 0.24, h * 0.12)
                }
                cd.roundRect(.color(Color(argb: 0x592A1463)), 0, 0, size.width, h, rr, stroke: 1.4)
            }
            if let label { OutlinedText(label, fontSize: height * 0.62, shadow: false, maxLines: 1) }
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
    }
}

/// Pulsing red notification badge with an optional count.
struct NotifyBadge: View {
    var size: CGFloat
    var count: Int?

    init(size: CGFloat = 16, count: Int? = nil) {
        self.size = size
        self.count = count
    }

    var body: some View {
        ZStack {
            Canvas { ctx, sz in
                let cd = ComposeDraw(ctx, sz)
                let r = min(sz.width, sz.height) / 2
                let c = CGPoint(x: sz.width / 2, y: sz.height / 2)
                cd.circle(.color(.white), r, c)
                cd.circle(.linearGradient(Gradient(colors: [Color(argb: 0xFFFF8A8A), Color(argb: 0xFFE8273D)]),
                                          startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: 0, y: sz.height)), r - 2, c)
                cd.circle(.color(.white.opacity(0.55)), r * 0.28, CGPoint(x: r * 0.72, y: r * 0.68))
            }
            if let count { OutlinedText(String(count), fontSize: size * 0.55, outline: Color(argb: 0xFF8A1020), shadow: false) }
        }
        .frame(width: size, height: size)
        .modifier(PhaseDriver(enabled: true, periodMs: 1500) { ph in PeriodicScaleEffect(phase: ph, amount: 0.16, pulse: true) })
    }
}

/// Section heading on the sky: glossy white candy text with optional icon and trailing content.
struct SectionTitle<Trailing: View>: View {
    let text: String
    var icon: Ico?
    let trailing: Trailing

    init(_ text: String, icon: Ico? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.text = text
        self.icon = icon
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 0) {
            if let icon {
                GameIcon(icon).frame(width: 30, height: 30)
                Spacer().frame(width: 6)
            }
            OutlinedText(text, fontSize: 24, brush: Grad.Snow, maxLines: 1)
            Spacer(minLength: 0)
            trailing
        }
        .padding(.top, 4)
        .padding(.leading, 2)
        .frame(maxWidth: .infinity)
    }
}

extension SectionTitle where Trailing == EmptyView {
    init(_ text: String, icon: Ico? = nil) {
        self.init(text, icon: icon) { EmptyView() }
    }
}

let CardTitleStyle = TextStyle(fontFamily: LilitaOne, fontSize: 21, color: GameColors.Ink)
let CardBodyStyle = TextStyle(fontFamily: Fredoka, fontWeight: .SemiBold, fontSize: 14, color: GameColors.InkSoft, lineHeight: 18)

struct Dot: View {
    let color: Color
    let size: CGFloat

    init(_ color: Color, _ size: CGFloat) {
        self.color = color
        self.size = size
    }

    var body: some View {
        Circle().fill(color).frame(width: size, height: size)
    }
}
