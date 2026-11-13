import SwiftUI
import UIKit
import CoreText
import GameKit

// Port of ui/theme/Theme.kt: colour tokens, gradients, skies, motion tokens, fonts and text styles
// of the "Candy Glass Factory" look (UI_GRAPHICS_PLAN.md §1).

// MARK: - Colour helpers

extension Color {
    /// Kotlin `Color(intArgb)` for ARGB values stored in an `Int` (either sign; the low 32 bits are used).
    init(argbInt v: Int) { self.init(argb: UInt32(truncatingIfNeeded: v)) }

    /// Compose `Color.copy(alpha = a)`.
    func copy(alpha a: Double) -> Color { opacity(a) }
}

/// Compose `lerp(start, stop, fraction)` for colours. Like Compose, interpolates in Oklab.
func lerp(_ start: Color, _ stop: Color, _ fraction: Float) -> Color {
    let a = ColorMath.rgba(start), b = ColorMath.rgba(stop)
    let t = Double(fraction)
    let la = ColorMath.toOklab(a.0, a.1, a.2), lb = ColorMath.toOklab(b.0, b.1, b.2)
    let L = la.0 + (lb.0 - la.0) * t, A = la.1 + (lb.1 - la.1) * t, B = la.2 + (lb.2 - la.2) * t
    let rgb = ColorMath.fromOklab(L, A, B)
    let alpha = a.3 + (b.3 - a.3) * t
    return Color(.sRGB, red: rgb.0, green: rgb.1, blue: rgb.2, opacity: min(max(alpha, 0), 1))
}

enum ColorMath {
    /// sRGB components (0...1) of a SwiftUI colour.
    static func rgba(_ c: Color) -> (Double, Double, Double, Double) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(c).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (Double(r), Double(g), Double(b), Double(a))
    }

    private static func lin(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
    private static func gam(_ c: Double) -> Double {
        let v = c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055
        return min(max(v, 0), 1)
    }

    static func toOklab(_ r: Double, _ g: Double, _ b: Double) -> (Double, Double, Double) {
        let lr = lin(r), lg = lin(g), lb = lin(b)
        let l = cbrt(0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb)
        let m = cbrt(0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb)
        let s = cbrt(0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb)
        return (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
    }

    static func fromOklab(_ L: Double, _ A: Double, _ B: Double) -> (Double, Double, Double) {
        let l_ = L + 0.3963377774 * A + 0.2158037573 * B
        let m_ = L - 0.1055613458 * A - 0.0638541728 * B
        let s_ = L - 0.0894841775 * A - 1.2914855480 * B
        let l = l_ * l_ * l_, m = m_ * m_ * m_, s = s_ * s_ * s_
        return (gam(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
                gam(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
                gam(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s))
    }
}

// MARK: - Brush (Compose Brush.verticalGradient / horizontalGradient)

/// A Compose-style gradient brush. Usable as a SwiftUI `ShapeStyle` (spans the filled view's bounds, like a
/// Compose brush with default start/end) and as a `GraphicsContext.Shading` via `shading(...)`.
struct Brush: ShapeStyle {
    enum Axis { case vertical, horizontal }
    let stops: [Gradient.Stop]
    let axis: Axis

    var gradient: Gradient { Gradient(stops: stops) }

    /// `Brush.verticalGradient(listOf(a, b, c))` (evenly spaced).
    static func verticalGradient(_ colors: [Color]) -> Brush { Brush(stops: evenly(colors), axis: .vertical) }
    /// `Brush.verticalGradient(0f to a, 0.5f to b, ...)`.
    static func verticalGradient(stops: [(CGFloat, Color)]) -> Brush {
        Brush(stops: stops.map { Gradient.Stop(color: $0.1, location: $0.0) }, axis: .vertical)
    }
    static func horizontalGradient(_ colors: [Color]) -> Brush { Brush(stops: evenly(colors), axis: .horizontal) }

    private static func evenly(_ colors: [Color]) -> [Gradient.Stop] {
        let n = max(colors.count - 1, 1)
        return colors.enumerated().map { Gradient.Stop(color: $0.element, location: CGFloat($0.offset) / CGFloat(n)) }
    }

    func resolve(in environment: EnvironmentValues) -> LinearGradient {
        axis == .vertical
            ? LinearGradient(gradient: gradient, startPoint: .top, endPoint: .bottom)
            : LinearGradient(gradient: gradient, startPoint: .leading, endPoint: .trailing)
    }

    /// Shading for a Canvas, spanning `rect` (Compose: the draw scope size when start/end are not given).
    func shading(_ rect: CGRect) -> GraphicsContext.Shading {
        axis == .vertical
            ? .linearGradient(gradient, startPoint: CGPoint(x: rect.minX, y: rect.minY), endPoint: CGPoint(x: rect.minX, y: rect.maxY))
            : .linearGradient(gradient, startPoint: CGPoint(x: rect.minX, y: rect.minY), endPoint: CGPoint(x: rect.maxX, y: rect.minY))
    }

    /// Shading between explicit coordinates (Compose `startY`/`endY` or `startX`/`endX`).
    func shading(from a: CGFloat, to b: CGFloat) -> GraphicsContext.Shading {
        axis == .vertical
            ? .linearGradient(gradient, startPoint: CGPoint(x: 0, y: a), endPoint: CGPoint(x: 0, y: b))
            : .linearGradient(gradient, startPoint: CGPoint(x: a, y: 0), endPoint: CGPoint(x: b, y: 0))
    }
}

// MARK: - Colour tokens

/// Colour tokens of the "Candy Glass Factory" look (see UI_GRAPHICS_PLAN.md §1.1).
enum GameColors {
    static let Ink = Color(argb: 0xFF2A1463)
    static let InkSoft = Color(argb: 0xFF5B4A8E)
    static let Night = Color(argb: 0xFF1A0B4A)
    static let Purple900 = Color(argb: 0xFF33178F)
    static let Purple800 = Color(argb: 0xFF4521C2)
    static let Purple700 = Color(argb: 0xFF5A33D6)
    static let Purple600 = Color(argb: 0xFF6C44F0)
    static let Purple500 = Color(argb: 0xFF7C55FF)
    static let Purple400 = Color(argb: 0xFF9775FF)
    static let Purple300 = Color(argb: 0xFFB9A3FF)
    static let Purple200 = Color(argb: 0xFFD5C8FF)
    static let Purple100 = Color(argb: 0xFFEEE8FF)
    static let Pink = Color(argb: 0xFFFF5FA2)
    static let PinkDark = Color(argb: 0xFFC42A6E)
    static let Yellow = Color(argb: 0xFFFFC93C)
    static let YellowLight = Color(argb: 0xFFFFE27A)
    static let YellowDark = Color(argb: 0xFFD27A00)
    static let Green = Color(argb: 0xFF34C759)
    static let GreenLight = Color(argb: 0xFF8EF08A)
    static let GreenDark = Color(argb: 0xFF198A3A)
    static let Cyan = Color(argb: 0xFF33D6F5)
    static let CyanDark = Color(argb: 0xFF1373BE)
    static let Red = Color(argb: 0xFFFF4D5E)
    static let RedDark = Color(argb: 0xFFC0283A)
    static let Orange = Color(argb: 0xFFFF9F1C)
    static let White = Color(argb: 0xFFFFFFFF)
    static let Card = Color(argb: 0xFFFFFFFF)
    static let CardSoft = Color(argb: 0xFFF4EFFF)
    static let Gray = Color(argb: 0xFFB8B3CC)
    static let GrayDark = Color(argb: 0xFF77718F)

    // panel frame + interior
    static let RimTop = Color(argb: 0xFF8A63FF)
    static let RimBottom = Color(argb: 0xFF4521C2)
    static let FillTop = Color(argb: 0xFFFFFFFF)
    static let FillBottom = Color(argb: 0xFFF2ECFF)

    // glass
    static let Glass = Color(argb: 0x29FFFFFF)
    static let GlassRim = Color(argb: 0x59FFFFFF)
    static let GlassDark = Color(argb: 0x8C24105F)

    static let MenuBackground = Brush.verticalGradient([Color(argb: 0xFF5A3BEF), Color(argb: 0xFF8A52F5), Color(argb: 0xFFE77BD8)])
}

/// Gradient fills for candy text and highlights.
enum Grad {
    static let Gold = Brush.verticalGradient([Color(argb: 0xFFFFF6B0), Color(argb: 0xFFFFD23F), Color(argb: 0xFFFFA81A)])
    static let Pink = Brush.verticalGradient([Color(argb: 0xFFFFD0EA), Color(argb: 0xFFFF7BBE), Color(argb: 0xFFFF3D8E)])
    static let Aqua = Brush.verticalGradient([Color(argb: 0xFFD9FAFF), Color(argb: 0xFF6BE0FF), Color(argb: 0xFF1FA8EE)])
    static let Mint = Brush.verticalGradient([Color(argb: 0xFFE6FFD6), Color(argb: 0xFF8EF08A), Color(argb: 0xFF2FBF4F)])
    static let Snow = Brush.verticalGradient([Color(argb: 0xFFFFFFFF), Color(argb: 0xFFF1EAFF), Color(argb: 0xFFD9CCFF)])
    static let Coral = Brush.verticalGradient([Color(argb: 0xFFFFE0D6), Color(argb: 0xFFFF9A8A), Color(argb: 0xFFFF4D5E)])
    static let PanelRim = Brush.verticalGradient([GameColors.RimTop, GameColors.RimBottom])
    static let PanelFill = Brush.verticalGradient([GameColors.FillTop, GameColors.FillBottom])
}

/// A sky backdrop: three gradient stops, two coloured glows and the skyline silhouette colour.
struct SkyPalette: Equatable {
    let top: Color, mid: Color, bottom: Color
    let glowA: Color, glowB: Color
    let silhouette: Color

    func lerpTo(_ o: SkyPalette, _ t: Float) -> SkyPalette {
        SkyPalette(top: lerp(top, o.top, t), mid: lerp(mid, o.mid, t), bottom: lerp(bottom, o.bottom, t),
                   glowA: lerp(glowA, o.glowA, t), glowB: lerp(glowB, o.glowB, t), silhouette: lerp(silhouette, o.silhouette, t))
    }
}

extension SkyPalette {
    init(_ top: UInt32, _ mid: UInt32, _ bottom: UInt32, _ glowA: UInt32, _ glowB: UInt32, _ silhouette: UInt32) {
        self.init(top: Color(argb: top), mid: Color(argb: mid), bottom: Color(argb: bottom),
                  glowA: Color(argb: glowA), glowB: Color(argb: glowB), silhouette: Color(argb: silhouette))
    }
}

enum Skies {
    static let Menu = SkyPalette(0xFF5A3BEF, 0xFF8A52F5, 0xFFE77BD8, 0xFFFF9AD5, 0xFF6FD3FF, 0xFF3B1FA6)
    static let Ocean = SkyPalette(0xFF1F5FD6, 0xFF2E9BEA, 0xFF5FD9E6, 0xFF9AF0FF, 0xFF7DFFC8, 0xFF15489E)
    static let Space = SkyPalette(0xFF140A3F, 0xFF2D1B7A, 0xFF6A2EB8, 0xFFB57BFF, 0xFF5FA8FF, 0xFF0D0630)
    static let Sunset = SkyPalette(0xFFFF8A5C, 0xFFF2557A, 0xFF9C3FB5, 0xFFFFD36E, 0xFFFF9AD5, 0xFF6E2380)
    static let Forest = SkyPalette(0xFF3CC88A, 0xFF1FA27A, 0xFF137A66, 0xFFC8FF8A, 0xFF7DF0D0, 0xFF0C5A4B)

    private static let worlds = [Menu, Ocean, Space, Sunset, Forest]
    /// Sky for a world/theme index (same order as render.Themes).
    static func forWorld(_ i: Int) -> SkyPalette { worlds[Kt.mod(i, worlds.count)] }
}

// MARK: - Motion

/// Compose `CubicBezierEasing`; `tween(ms)` gives the SwiftUI animation (`tween(ms, easing = this)`).
struct CubicBezierEasing {
    let a: Double, b: Double, c: Double, d: Double
    init(_ a: Double, _ b: Double, _ c: Double, _ d: Double) { self.a = a; self.b = b; self.c = c; self.d = d }

    func tween(_ durationMillis: Int, delayMillis: Int = 0) -> Animation {
        let anim = Animation.timingCurve(a, b, c, d, duration: Double(durationMillis) / 1000)
        return delayMillis > 0 ? anim.delay(Double(delayMillis) / 1000) : anim
    }

    static let FastOutSlowIn = CubicBezierEasing(0.4, 0, 0.2, 1)
    static let LinearOutSlowIn = CubicBezierEasing(0, 0, 0.2, 1)
    static let FastOutLinearIn = CubicBezierEasing(0.4, 0, 1, 1)
    static let Linear = CubicBezierEasing(0, 0, 1, 1)
}

/// Motion tokens (see UI_GRAPHICS_PLAN.md §1.4). Also forwards GameKit's reduce-motion switch, because this
/// type shadows `GameKit.Motion` inside the app module.
enum Motion {
    static let MICRO = 120
    static let FAST = 200
    static let STANDARD = 300
    static let EMPHASIZED = 420
    static let EaseIn = CubicBezierEasing(0.05, 0.7, 0.1, 1)   // decelerate, for entering elements
    static let EaseOut = CubicBezierEasing(0.3, 0, 0.8, 0.15)  // accelerate, for leaving elements
    static let Standard = CubicBezierEasing(0.2, 0, 0, 1)
    static func bouncy() -> Animation { .compose(dampingRatio: 0.5, stiffness: 450) }
    static func snappy() -> Animation { .compose(dampingRatio: 0.75, stiffness: 700) }
    static func gentle() -> Animation { .compose(dampingRatio: 0.85, stiffness: 220) }

    /// iOS Reduce Motion (or the app's own toggle): ambient decoration stops.
    @MainActor static var reduce: Bool { GameKit.Motion.reduce }
    @MainActor static var appReduceMotion: Bool {
        get { GameKit.Motion.appReduceMotion }
        set { GameKit.Motion.appReduceMotion = newValue }
    }
}

// MARK: - Fonts

/// Font family tokens (Kotlin `LilitaOne` / `Fredoka` FontFamily vals).
struct FontFamily: Equatable {
    /// PostScript name of the face.
    let postScriptName: String
    /// Variable font with a weight axis (Fredoka).
    let variable: Bool
}

let LilitaOne = FontFamily(postScriptName: "LilitaOne", variable: false)
let Fredoka = FontFamily(postScriptName: "Fredoka-Regular", variable: true)

/// Compose `FontWeight`.
struct FontWeight: Equatable {
    let weight: Int
    init(_ weight: Int) { self.weight = weight }
    static let Normal = FontWeight(400)
    static let Medium = FontWeight(500)
    static let SemiBold = FontWeight(600)
    static let Bold = FontWeight(700)

    /// Fredoka's wght axis value for this weight, as declared by the Kotlin FontFamily
    /// (Normal → 450, Medium → 500, SemiBold → 600, Bold → 700; other weights fall to the nearest entry).
    var fredokaAxis: CGFloat {
        switch weight {
        case ..<500: return 450
        case 500..<600: return 500
        case 600..<700: return 600
        default: return 700
        }
    }
}

/// Font helper: bundled Lilita One (titles, buttons, candy text) and Fredoka (body text).
/// Fonts are registered on first use (`FontRegistry.registerAll()`), so components work even before the app shell
/// registers them.
enum GameFonts {
    static let registered: Void = { FontRegistry.registerAll() }()

    static func register() { _ = registered }

    /// SwiftUI Lilita One (fixed size, like `sp` in a game UI).
    static func lilita(_ size: CGFloat) -> Font {
        _ = registered
        return .custom(LilitaOne.postScriptName, fixedSize: size)
    }

    /// SwiftUI Fredoka at the Kotlin FontFamily's weight-axis value.
    static func fredoka(_ size: CGFloat, _ weight: FontWeight = .Normal) -> Font {
        _ = registered
        return .variable(Fredoka.postScriptName, size: size, weight: weight.fredokaAxis)
    }

    static func uiLilita(_ size: CGFloat) -> UIFont {
        _ = registered
        return UIFont(name: LilitaOne.postScriptName, size: size) ?? .systemFont(ofSize: size, weight: .heavy)
    }

    static func uiFredoka(_ size: CGFloat, _ weight: FontWeight = .Normal) -> UIFont {
        _ = registered
        return FontRegistry.variable(Fredoka.postScriptName, size: size, weight: weight.fredokaAxis)
    }

    /// Core Text Lilita One, used by the procedural art (`Painter.text`). Cached per size.
    static func ctLilita(_ size: CGFloat) -> CTFont {
        _ = registered
        let key = Int((size * 64).rounded())
        if let f = ctCache[key] { return f }
        let f = CTFontCreateWithName(LilitaOne.postScriptName as CFString, size, nil)
        if ctCache.count > 256 { ctCache.removeAll() }
        ctCache[key] = f
        return f
    }

    private static var ctCache: [Int: CTFont] = [:]

    static func font(_ family: FontFamily, _ size: CGFloat, _ weight: FontWeight = .Normal) -> Font {
        family.variable ? fredoka(size, weight) : lilita(size)
    }

    static func uiFont(_ family: FontFamily, _ size: CGFloat, _ weight: FontWeight = .Normal) -> UIFont {
        family.variable ? uiFredoka(size, weight) : uiLilita(size)
    }
}

extension Font {
    static func lilita(_ size: CGFloat) -> Font { GameFonts.lilita(size) }
    static func fredoka(_ size: CGFloat, weight: FontWeight = .Normal) -> Font { GameFonts.fredoka(size, weight) }
}

// MARK: - Text styles

/// Compose `TextAlign`.
enum TextAlign {
    case Start, Center, End

    var swiftUI: TextAlignment {
        switch self {
        case .Start: return .leading
        case .Center: return .center
        case .End: return .trailing
        }
    }

    var frameAlignment: Alignment {
        switch self {
        case .Start: return .leading
        case .Center: return .center
        case .End: return .trailing
        }
    }
}

/// Compose `TextStyle` subset used by the game. Apply with `.textStyle(style)`.
struct TextStyle {
    var fontFamily: FontFamily
    var fontWeight: FontWeight
    var fontSize: CGFloat
    var color: Color
    var lineHeight: CGFloat?
    var textAlign: TextAlign?

    init(fontFamily: FontFamily = Fredoka, fontWeight: FontWeight = .Normal, fontSize: CGFloat = 14,
         color: Color = .black, lineHeight: CGFloat? = nil, textAlign: TextAlign? = nil) {
        self.fontFamily = fontFamily
        self.fontWeight = fontWeight
        self.fontSize = fontSize
        self.color = color
        self.lineHeight = lineHeight
        self.textAlign = textAlign
    }

    var font: Font { GameFonts.font(fontFamily, fontSize, fontWeight) }

    /// Extra line spacing so that multi-line text uses the Compose line height.
    var lineSpacing: CGFloat {
        guard let lh = lineHeight else { return 0 }
        return max(0, lh - GameFonts.uiFont(fontFamily, fontSize, fontWeight).lineHeight)
    }

    func copy(fontSize: CGFloat? = nil, color: Color? = nil, fontWeight: FontWeight? = nil,
              lineHeight: CGFloat? = nil, textAlign: TextAlign? = nil) -> TextStyle {
        var s = self
        if let fontSize { s.fontSize = fontSize }
        if let color { s.color = color }
        if let fontWeight { s.fontWeight = fontWeight }
        if let lineHeight { s.lineHeight = lineHeight }
        if let textAlign { s.textAlign = textAlign }
        return s
    }
}

extension View {
    /// Applies a Compose-style `TextStyle` (font, colour, line height, alignment).
    func textStyle(_ s: TextStyle) -> some View {
        self.font(s.font)
            .foregroundStyle(s.color)
            .lineSpacing(s.lineSpacing)
            .multilineTextAlignment(s.textAlign?.swiftUI ?? .leading)
    }
}

enum GameText {
    static let Title = TextStyle(fontFamily: LilitaOne, fontSize: 34, color: GameColors.White)
    static let Heading = TextStyle(fontFamily: LilitaOne, fontSize: 22, color: GameColors.Ink)
    static let Button = TextStyle(fontFamily: LilitaOne, fontSize: 22, color: GameColors.White)
    static let Body = TextStyle(fontFamily: Fredoka, fontWeight: .SemiBold, fontSize: 16, color: GameColors.Ink, lineHeight: 21)
    static let Small = TextStyle(fontFamily: Fredoka, fontWeight: .SemiBold, fontSize: 13, color: GameColors.InkSoft, lineHeight: 17)
    static let Caption = TextStyle(fontFamily: Fredoka, fontWeight: .Medium, fontSize: 12, color: GameColors.InkSoft)
}

/// Kotlin `MarbleTheme { content }` (MaterialTheme with the game colours).
struct MarbleTheme<Content: View>: View {
    @ViewBuilder var content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
        GameFonts.register()
    }

    var body: some View {
        content().tint(GameColors.Purple500)
    }
}
