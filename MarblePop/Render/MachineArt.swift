import CoreGraphics
import Foundation
import GameKit

/// High quality procedural art for the factory-machine playground (port of render/MachineArt.kt).
/// Marbles are split into a rotating body layer (glass + inner swirl) and a fixed
/// lighting layer (specular, caustic, rim) so they look like they really roll.
/// Draws into an `ACanvas` (Core Graphics, y-down); used by the sprite cache and the baked layers (main thread).
enum MachineArt {
    private static let p = Paint()
    private static var path = CGMutablePath()
    private static var path2 = CGMutablePath()
    private static var rect = RectF()

    static let CHROME: [Int] = [0xFFFFFFFF, 0xFFD9DEE8, 0xFF9AA3B5, 0xFFC9CFDB, 0xFF7D8699]
    static let CHROME_POS: [CGFloat] = [0, 0.25, 0.55, 0.75, 1]

    private static func reset() { p.reset() }

    // =================================================================== marbles

    static func marble(_ c: ACanvas, _ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ colorId: Int, _ skin: Int) {
        marbleBody(c, cx, cy, r, colorId, skin)
        marbleGloss(c, cx, cy, r, colorId, skin)
    }

    static func marbleArgb(_ colorId: Int) -> Int {
        colorId == MarbleColors.RAINBOW ? 0xFFB070FF : argbInt(MarbleColors.argb[colorId])
    }

    /// Rotating layer.
    static func marbleBody(_ c: ACanvas, _ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ colorId: Int, _ skin: Int, _ argbOverride: Int? = nil) {
        let base = argbOverride ?? marbleArgb(colorId)
        let rainbow = colorId == MarbleColors.RAINBOW && argbOverride == nil
        reset()
        c.save()
        path = CGMutablePath(); path.addCircle(cx, cy, r); c.clipPath(path)
        if rainbow {
            p.alpha = 255; p.shader = Shader.sweep(cx, cy, Col.rainbow, nil)
            c.drawCircle(cx, cy, r, p)
            vane(c, cx, cy, r, AColor.WHITE, 0xFF6A3FB0, 0.24, 200)
        } else {
            switch skin {
            case 1: // crystal glass: clear body with thin white spiral
                p.alpha = 255
                p.shader = Shader.radial(cx - r * 0.2, cy - r * 0.25, r * 1.3,
                                         [Col.lighten(base, 0.65), Col.lighten(base, 0.15), Col.darken(base, 0.45)], [0, 0.55, 1])
                c.drawCircle(cx, cy, r, p)
                p.shader = nil; p.style = .STROKE; p.strokeCap = .round
                for k in 0..<3 {
                    let kf = CGFloat(k)
                    p.strokeWidth = r * (0.12 - kf * 0.03); p.color = Col.alpha(AColor.WHITE, 170 - k * 40)
                    rect.set(cx - r * (0.25 + kf * 0.22), cy - r * (0.25 + kf * 0.22), cx + r * (0.25 + kf * 0.22), cy + r * (0.25 + kf * 0.22))
                    c.drawArc(rect, kf * 110, 150, false, p)
                }
                p.style = .FILL
                bubbles(c, cx, cy, r, colorId)
            case 2: // candy: white with spiral colour stripes
                p.alpha = 255
                p.shader = Shader.radial(cx - r * 0.2, cy - r * 0.25, r * 1.3,
                                         [AColor.WHITE, Col.lighten(base, 0.8), Col.lighten(base, 0.4)], [0, 0.6, 1])
                c.drawCircle(cx, cy, r, p)
                p.shader = nil; p.color = base
                for k in 0..<5 {
                    path2 = CGMutablePath()
                    let a0 = CGFloat(k) * 2 * CGFloat.pi / 5
                    path2.moveTo(cx, cy)
                    for t in 0...12 {
                        let tt = CGFloat(t) / 12
                        let a = a0 + tt * 2.2
                        path2.lineTo(cx + cos(a) * r * 1.1 * tt, cy + sin(a) * r * 1.1 * tt)
                    }
                    for t in stride(from: 12, through: 0, by: -1) {
                        let tt = CGFloat(t) / 12
                        let a = a0 + 0.38 + tt * 2.2
                        path2.lineTo(cx + cos(a) * r * 1.1 * tt, cy + sin(a) * r * 1.1 * tt)
                    }
                    path2.close()
                    c.drawPath(path2, p)
                }
            case 3: // galaxy
                p.alpha = 255
                p.shader = Shader.radial(cx + r * 0.15, cy + r * 0.2, r * 1.25,
                                         [Col.darken(base, 0.25), Col.darken(base, 0.7), 0xFF0B0820], [0, 0.5, 1])
                c.drawCircle(cx, cy, r, p)
                p.alpha = 255
                p.shader = Shader.radial(cx - r * 0.3, cy + r * 0.15, r * 0.75, [Col.alpha(Col.lighten(base, 0.35), 210), 0x00000000], nil)
                c.drawCircle(cx, cy, r, p)
                p.alpha = 255
                p.shader = Shader.radial(cx + r * 0.35, cy - r * 0.2, r * 0.5, [0x88FF7AE0, 0x00000000], nil)
                c.drawCircle(cx, cy, r, p)
                p.shader = nil
                let rnd = KotlinRandom(intSeed: colorId * 31 + 7)
                for _ in 0..<14 {
                    let a = CGFloat(rnd.nextFloat() * 6.28); let d = CGFloat(rnd.nextFloat()) * r * 0.85
                    p.color = Col.alpha(AColor.WHITE, 120 + rnd.nextInt(135))
                    c.drawCircle(cx + cos(a) * d, cy + sin(a) * d, r * (0.02 + CGFloat(rnd.nextFloat()) * 0.05), p)
                }
            case 4: // chrome metal
                p.alpha = 255
                p.shader = Shader.linear(cx, cy - r, cx, cy + r,
                                         [Col.lighten(base, 0.9), Col.lighten(base, 0.35), Col.darken(base, 0.4), Col.lighten(base, 0.55), Col.darken(base, 0.5)],
                                         [0, 0.32, 0.5, 0.68, 1])
                c.drawCircle(cx, cy, r, p)
            case 5: // neon
                p.alpha = 255
                p.shader = Shader.radial(cx, cy, r, [0xFF1A1230, 0xFF120C24, Col.darken(base, 0.1)], [0, 0.7, 1])
                c.drawCircle(cx, cy, r, p)
                p.shader = nil; p.style = .STROKE
                p.strokeWidth = r * 0.2; p.color = Col.alpha(base, 140); c.drawCircle(cx, cy, r * 0.72, p)
                p.strokeWidth = r * 0.08; p.color = Col.lighten(base, 0.6); c.drawCircle(cx, cy, r * 0.72, p)
                p.strokeWidth = r * 0.05; p.color = Col.alpha(Col.lighten(base, 0.3), 200)
                rect.set(cx - r * 0.42, cy - r * 0.42, cx + r * 0.42, cy + r * 0.42); c.drawArc(rect, 30, 240, false, p)
                p.style = .FILL
            case 6: // smiley
                classicBody(c, cx, cy, r, base, swirl: false)
                p.shader = nil; p.color = Col.darken(base, 0.75)
                rect.set(cx - r * 0.38, cy - r * 0.22, cx - r * 0.16, cy + r * 0.1); c.drawOval(rect, p)
                rect.set(cx + r * 0.16, cy - r * 0.22, cx + r * 0.38, cy + r * 0.1); c.drawOval(rect, p)
                p.color = AColor.WHITE
                c.drawCircle(cx - r * 0.3, cy - r * 0.13, r * 0.05, p); c.drawCircle(cx + r * 0.24, cy - r * 0.13, r * 0.05, p)
                p.color = Col.darken(base, 0.75)
                p.style = .STROKE; p.strokeWidth = r * 0.1; p.strokeCap = .round
                rect.set(cx - r * 0.3, cy - r * 0.05, cx + r * 0.3, cy + r * 0.42); c.drawArc(rect, 25, 130, false, p)
                p.style = .FILL
                p.color = Col.alpha(0xFFFF5A8A, 110)
                c.drawCircle(cx - r * 0.55, cy + r * 0.18, r * 0.13, p); c.drawCircle(cx + r * 0.55, cy + r * 0.18, r * 0.13, p)
            default:
                classicBody(c, cx, cy, r, base, swirl: true, seed: colorId)
            }
        }
        // depth vignette (thick glass)
        reset()
        p.alpha = 255
        p.shader = Shader.radial(cx - r * 0.12, cy - r * 0.18, r * 1.18,
                                 [0x00000000, 0x00000000, Col.alpha(Col.darken(base, 0.75), skin == 5 ? 60 : 150)], [0, 0.6, 1])
        c.drawCircle(cx, cy, r, p)
        c.restore()
    }

    private static func classicBody(_ c: ACanvas, _ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ base: Int, swirl: Bool, seed: Int = 0) {
        p.alpha = 255
        p.shader = Shader.radial(cx - r * 0.22, cy - r * 0.28, r * 1.4, [Col.lighten(base, 0.5), base, Col.darken(base, 0.5)], [0, 0.48, 1])
        c.drawCircle(cx, cy, r, p)
        p.alpha = 255
        p.shader = Shader.radial(cx, cy + r * 0.1, r * 0.75, [Col.alpha(Col.lighten(base, 0.55), 120), Col.alpha(base, 0)], nil)
        c.drawCircle(cx, cy, r, p)
        p.shader = nil
        if swirl {
            // cat's-eye vanes inside the glass
            vane(c, cx, cy, r, Col.lighten(base, 0.85), Col.darken(base, 0.35), 0.2, 215)
            c.save(); c.rotate(90, cx, cy)
            vane(c, cx, cy, r * 0.8, Col.lighten(base, 0.5), Col.darken(base, 0.2), 0.13, 150)
            c.restore()
            bubbles(c, cx, cy, r, seed)
        }
    }

    private static func vane(_ c: ACanvas, _ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ light: Int, _ dark: Int, _ width: CGFloat, _ alpha: Int) {
        path2 = CGMutablePath()
        path2.moveTo(cx - r * 0.95, cy + r * 0.12)
        path2.cubicTo(cx - r * 0.35, cy - r * (0.55 + width), cx + r * 0.35, cy + r * (0.55 - width), cx + r * 0.95, cy - r * 0.12)
        path2.cubicTo(cx + r * 0.35, cy + r * (0.55 + width), cx - r * 0.35, cy - r * (0.55 - width), cx - r * 0.95, cy + r * 0.12)
        path2.close()
        p.reset()
        p.alpha = 255
        p.shader = Shader.linear(cx, cy - r * 0.4, cx, cy + r * 0.4,
                                 [Col.alpha(light, alpha), Col.alpha(Col.mix(light, dark, 0.5), alpha), Col.alpha(dark, alpha)], nil)
        c.drawPath(path2, p)
        p.shader = nil
    }

    private static func bubbles(_ c: ACanvas, _ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ seed: Int) {
        let rnd = KotlinRandom(intSeed: seed * 13 + 5)
        p.shader = nil
        for _ in 0..<3 {
            let a = CGFloat(rnd.nextFloat() * 6.28); let d = r * (0.25 + CGFloat(rnd.nextFloat()) * 0.45)
            let br = r * (0.04 + CGFloat(rnd.nextFloat()) * 0.04)
            p.style = .FILL; p.color = 0x55FFFFFF
            c.drawCircle(cx + cos(a) * d, cy + sin(a) * d, br, p)
            p.color = 0xAAFFFFFF
            c.drawCircle(cx + cos(a) * d - br * 0.35, cy + sin(a) * d - br * 0.35, br * 0.35, p)
        }
    }

    /// Fixed lighting layer — never rotates.
    static func marbleGloss(_ c: ACanvas, _ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ colorId: Int, _ skin: Int, _ argbOverride: Int? = nil) {
        let base = argbOverride ?? marbleArgb(colorId)
        reset()
        c.save()
        path = CGMutablePath(); path.addCircle(cx, cy, r); c.clipPath(path)
        // caustic: light focused through the glass onto the lower side
        p.alpha = 255
        p.shader = Shader.radial(cx + r * 0.2, cy + r * 0.55, r * 0.62,
                                 [Col.alpha(Col.lighten(base, 0.8), skin == 5 ? 70 : 215), Col.alpha(Col.lighten(base, 0.4), 60), 0x00FFFFFF], [0, 0.5, 1])
        c.drawCircle(cx, cy, r, p)
        c.restore()
        // rim light
        p.shader = nil; p.style = .STROKE; p.strokeCap = .round
        p.strokeWidth = r * 0.09; p.color = 0x70FFFFFF
        rect.set(cx - r * 0.86, cy - r * 0.86, cx + r * 0.86, cy + r * 0.86)
        c.drawArc(rect, 15, 75, false, p)
        // definition outline
        p.strokeWidth = max(1, r * 0.06); p.color = Col.alpha(Col.darken(base, 0.65), 190)
        c.drawCircle(cx, cy, r - p.strokeWidth / 2, p)
        p.style = .FILL
        // main soft specular
        c.save()
        c.rotate(-35, cx - r * 0.32, cy - r * 0.42)
        rect.set(cx - r * 0.72, cy - r * 0.68, cx + r * 0.05, cy - r * 0.2)
        p.alpha = 255; p.shader = Shader.linear(0, rect.top, 0, rect.bottom, [0xF8FFFFFF, 0x66FFFFFF, 0x00FFFFFF], [0, 0.55, 1])
        c.drawOval(rect, p)
        c.restore()
        p.shader = nil
        // sharp window glint
        p.color = AColor.WHITE
        rect.set(cx - r * 0.5, cy - r * 0.56, cx - r * 0.28, cy - r * 0.42)
        c.drawOval(rect, p)
        p.color = 0xB0FFFFFF
        c.drawCircle(cx + r * 0.5, cy + r * 0.32, r * 0.07, p)
    }

    /// Soft blurred contact shadow.
    static func shadow(_ c: ACanvas, _ cx: CGFloat, _ cy: CGFloat, _ rx: CGFloat, _ ry: CGFloat, _ alpha: Int) {
        reset()
        p.color = Col.alpha(0xFF0A0420, alpha)
        p.blurRadius = max(1, ry * 0.6)
        rect.set(cx - rx, cy - ry, cx + rx, cy + ry)
        c.drawOval(rect, p)
        p.blurRadius = 0
    }

    // =================================================================== crates (grid blocks)

    /// Glass candy crate filled with 9 marbles. variant: 0 normal, 1 mystery, 2 grey(paint), 3 rainbow
    static func crate(_ c: ACanvas, _ x: CGFloat, _ y: CGFloat, _ s: CGFloat, _ colorId: Int, _ variant: Int, _ skin: Int) {
        let base: Int
        switch variant {
        case 1: base = 0xFF7E86A6
        case 2: base = 0xFF9DA2B6
        case 3: base = 0xFFA06BFF
        default: base = Painter.colorOf(colorId)
        }
        let pad = s * 0.055
        let lidH = s * 0.15
        let rad = s * 0.17
        let body = RectF(x + pad, y + pad + lidH * 0.45, x + s - pad, y + s - pad)
        // shadow
        shadow(c, x + s / 2, body.bottom - s * 0.02, s * 0.42, s * 0.07, 120)
        reset()
        // back wall
        p.alpha = 255; p.shader = Shader.linear(0, body.top, 0, body.bottom, Col.lighten(base, 0.2), Col.darken(base, 0.4))
        c.drawRoundRect(body, rad, rad, p)
        p.alpha = 255; p.shader = Shader.radial(body.centerX(), body.centerY(), s * 0.5, [Col.alpha(Col.lighten(base, 0.55), 190), Col.alpha(base, 0)], nil)
        c.drawRoundRect(body, rad, rad, p)
        p.shader = nil
        // contents
        var inner = RectF(body); inner.inset(s * 0.06, s * 0.05)
        if variant == 1 {
            // frosted: no contents visible, just blurry blobs
            p.color = 0x55FFFFFF
            let rnd = KotlinRandom(intSeed: 9)
            for _ in 0..<6 {
                c.drawCircle(inner.left + CGFloat(rnd.nextFloat()) * inner.width(), inner.top + CGFloat(rnd.nextFloat()) * inner.height(), s * 0.09, p)
            }
        } else {
            let mr = s * 0.118
            let rnd = KotlinRandom(intSeed: colorId * 7 + variant * 3 + 1)
            for iy in 0..<3 {
                for ix in 0..<3 {
                    let mx = inner.left + inner.width() * (0.2 + 0.3 * CGFloat(ix)) + (CGFloat(rnd.nextFloat()) - 0.5) * s * 0.025
                    let my = inner.top + inner.height() * (0.22 + 0.29 * CGFloat(iy)) + (CGFloat(rnd.nextFloat()) - 0.5) * s * 0.02
                    let id = variant == 3 ? [0, 1, 2, 3, 4, 5, 6, 7, 0][iy * 3 + ix] : colorId
                    let over: Int? = variant == 2 ? 0xFFA7ABBE : nil
                    marbleBody(c, mx, my, mr, id, skin, over)
                    marbleGloss(c, mx, my, mr, id, skin, over)
                }
            }
        }
        // front glass
        reset()
        p.alpha = 255
        p.shader = Shader.linear(body.left, body.top, body.right, body.bottom,
                                 [Col.alpha(AColor.WHITE, variant == 1 ? 175 : 70), Col.alpha(AColor.WHITE, variant == 1 ? 140 : 12), Col.alpha(base, variant == 1 ? 120 : 55)],
                                 [0, 0.5, 1])
        c.drawRoundRect(body, rad, rad, p)
        p.shader = nil
        c.save()
        path = CGMutablePath(); path.addRoundRect(body, rad, rad); c.clipPath(path)
        path2 = CGMutablePath()
        path2.moveTo(body.left + body.width() * 0.08, body.bottom); path2.lineTo(body.left + body.width() * 0.3, body.bottom)
        path2.lineTo(body.left + body.width() * 0.75, body.top); path2.lineTo(body.left + body.width() * 0.53, body.top); path2.close()
        p.color = 0x2EFFFFFF; c.drawPath(path2, p)
        path2 = CGMutablePath()
        path2.moveTo(body.left + body.width() * 0.36, body.bottom); path2.lineTo(body.left + body.width() * 0.42, body.bottom)
        path2.lineTo(body.left + body.width() * 0.87, body.top); path2.lineTo(body.left + body.width() * 0.81, body.top); path2.close()
        p.color = 0x24FFFFFF; c.drawPath(path2, p)
        c.restore()
        // coloured frame
        p.style = .STROKE
        p.strokeWidth = s * 0.075
        p.alpha = 255; p.shader = Shader.linear(0, body.top, 0, body.bottom, [Col.lighten(base, 0.45), base, Col.darken(base, 0.45)], nil)
        var fr = RectF(body); fr.inset(p.strokeWidth / 2, p.strokeWidth / 2)
        c.drawRoundRect(fr, rad * 0.85, rad * 0.85, p)
        p.shader = nil
        p.strokeWidth = s * 0.018; p.color = 0x99FFFFFF
        fr.inset(s * 0.045, s * 0.045); c.drawRoundRect(fr, rad * 0.6, rad * 0.6, p)
        p.strokeWidth = s * 0.02; p.color = Col.alpha(Col.darken(base, 0.6), 200)
        c.drawRoundRect(body, rad, rad, p)
        p.style = .FILL
        // chrome lid
        let lid = RectF(x + s * 0.17, y + pad, x + s - s * 0.17, y + pad + lidH)
        p.alpha = 255; p.shader = Shader.linear(0, lid.top, 0, lid.bottom, CHROME, CHROME_POS)
        c.drawRoundRect(lid, lidH * 0.4, lidH * 0.4, p)
        p.shader = nil
        p.style = .STROKE; p.strokeWidth = s * 0.016; p.color = 0xFF4E5568
        c.drawRoundRect(lid, lidH * 0.4, lidH * 0.4, p); p.style = .FILL
        // lid bolts + colour LED
        p.color = 0xFF5E667A
        c.drawCircle(lid.left + lidH * 0.45, lid.centerY(), lidH * 0.14, p)
        c.drawCircle(lid.right - lidH * 0.45, lid.centerY(), lidH * 0.14, p)
        let led: Int = variant == 1 ? 0xFFE6E9F2 : (variant == 2 ? 0xFFB6BACB : Col.lighten(base, 0.15))
        p.color = Col.alpha(led, 110); p.blurRadius = lidH * 0.3
        c.drawCircle(lid.centerX(), lid.centerY(), lidH * 0.42, p); p.blurRadius = 0
        p.alpha = 255
        if variant == 3 { p.shader = Shader.sweep(lid.centerX(), lid.centerY(), Col.rainbow, nil) } else { p.color = led }
        c.drawCircle(lid.centerX(), lid.centerY(), lidH * 0.3, p); p.shader = nil
        p.color = 0xCCFFFFFF; c.drawCircle(lid.centerX() - lidH * 0.1, lid.centerY() - lidH * 0.1, lidH * 0.09, p)
        if variant == 1 { Painter.text(c, "?", body.centerX(), body.centerY() + s * 0.02, s * 0.5, AColor.WHITE, 0xFF3E4560, s * 0.08) }
    }

    /// Board block — a candy-glass jelly cube. [open] blocks (they have a way out) are raised, glossy
    /// and show 9 marbles through a glass window; blocked ones sit lower with the marbles behind a
    /// frosted lid. variant: 0 normal, 1 mystery, 2 grey (paint), 3 rainbow.
    static func jelly(_ c: ACanvas, _ x: CGFloat, _ y: CGFloat, _ s: CGFloat, _ colorId: Int, _ variant: Int, _ open: Bool, _ skin: Int) {
        let base: Int
        switch variant {
        case 1: base = 0xFF9A82F0
        case 2: base = 0xFFA9ADC2
        case 3: base = 0xFFB98CFF
        default: base = Painter.colorOf(colorId)
        }
        let white = colorId == 8 && variant == 0
        let pad = s * 0.05
        let rad = s * 0.25
        let depth = open ? s * 0.1 : s * 0.05
        let outline = white ? 0xFF8C93AE : Col.darken(base, 0.55)
        // contact shadow
        shadow(c, x + s / 2, y + s - pad - depth * 0.15, s * 0.43, s * 0.075, open ? 120 : 70)
        reset()
        // depth side
        rect.set(x + pad, y + pad + depth, x + s - pad, y + s - pad)
        p.color = open ? Col.darken(base, white ? 0.22 : 0.34) : Col.darken(Col.lighten(base, 0.3), 0.22)
        c.drawRoundRect(rect, rad, rad, p)
        p.color = Col.alpha(AColor.WHITE, open ? 46 : 30)
        rect.set(x + pad + rad * 0.5, y + s - pad - depth * 0.55, x + s - pad - rad * 0.5, y + s - pad - depth * 0.35)
        c.drawRoundRect(rect, depth * 0.1, depth * 0.1, p)
        // face
        let face = RectF(x + pad, y + pad, x + s - pad, y + s - pad - depth)
        p.alpha = 255
        if variant == 3 {
            p.shader = Shader.linear(face.left, face.top, face.right, face.bottom,
                                     open ? Col.rainbow : Col.rainbow.map { Col.lighten($0, 0.5) }, nil)
        } else if open {
            p.shader = Shader.linear(0, face.top, 0, face.bottom, [Col.lighten(base, 0.38), base, Col.darken(base, 0.06)], [0, 0.5, 1])
        } else {
            p.shader = Shader.linear(0, face.top, 0, face.bottom, Col.lighten(base, 0.5), Col.lighten(base, 0.26))
        }
        c.drawRoundRect(face, rad, rad, p); p.shader = nil
        c.save(); path = CGMutablePath(); path.addRoundRect(face, rad, rad); c.clipPath(path)
        if variant == 1 {
            // candy stripes
            p.color = Col.alpha(AColor.WHITE, open ? 34 : 40)
            let step = s * 0.2
            var k = -s
            while k < s * 1.2 {
                path2 = CGMutablePath()
                path2.moveTo(face.left + k, face.bottom); path2.lineTo(face.left + k + step * 0.5, face.bottom)
                path2.lineTo(face.left + k + step * 0.5 + face.height(), face.top); path2.lineTo(face.left + k + face.height(), face.top); path2.close()
                c.drawPath(path2, p)
                k += step
            }
        }
        c.restore()
        var win = RectF(face); win.inset(s * 0.125, s * 0.115)
        let wr = rad * 0.62
        if variant == 1 {
            Painter.text(c, "?", face.centerX(), face.centerY() + s * 0.01, s * 0.56, 0xFFFFD54A, 0xFF3B1F7A, s * 0.075)
            Painter.star4(c, face.left + face.width() * 0.2, face.top + face.height() * 0.28, s * 0.05, 0xDDFFFFFF)
            Painter.star4(c, face.right - face.width() * 0.18, face.bottom - face.height() * 0.26, s * 0.035, 0xBBFFFFFF)
        } else {
            // recessed window
            p.color = open ? Col.alpha(Col.darken(base, white ? 0.25 : 0.42), 150) : Col.alpha(Col.darken(base, 0.1), 70)
            c.drawRoundRect(win, wr, wr, p)
            c.save(); path = CGMutablePath(); path.addRoundRect(win, wr, wr); c.clipPath(path)
            p.alpha = 255
            p.shader = Shader.linear(0, win.top, 0, win.top + win.height() * 0.35, Col.alpha(Col.darken(base, 0.6), open ? 110 : 40), 0)
            c.drawRect(win, p); p.shader = nil
            c.restore()
            let mr = s * 0.104
            let stepX = win.width() / 3; let stepY = win.height() / 3
            if !open { c.saveLayerAlpha(win, 150) }
            for iy in 0..<3 {
                for ix in 0..<3 {
                    let mx = win.left + stepX * (CGFloat(ix) + 0.5)
                    let my = win.top + stepY * (CGFloat(iy) + 0.5) - s * 0.008
                    let id = variant == 3 ? [0, 1, 2, 3, 4, 5, 6, 7, 0][iy * 3 + ix] : colorId
                    reset(); p.color = Col.alpha(Col.darken(base, 0.7), 70)
                    rect.set(mx - mr * 0.8, my + mr * 0.55, mx + mr * 0.8, my + mr * 1.12); c.drawOval(rect, p)
                    if variant == 2 {
                        marbleBody(c, mx, my, mr, id, skin, 0xFFB4B8CA); marbleGloss(c, mx, my, mr, id, skin, 0xFFB4B8CA)
                    } else {
                        marble(c, mx, my, mr, id, skin)
                    }
                }
            }
            if !open { c.restore() }
            reset()
            if !open {
                // frosted lid over the stuck marbles
                p.color = Col.alpha(Col.lighten(base, 0.75), 100); c.drawRoundRect(win, wr, wr, p)
                let rnd = KotlinRandom(intSeed: colorId * 5 + variant)
                p.color = 0x99FFFFFF
                for _ in 0..<7 {
                    c.drawCircle(win.left + CGFloat(rnd.nextFloat()) * win.width(), win.top + CGFloat(rnd.nextFloat()) * win.height(),
                                 s * (0.008 + CGFloat(rnd.nextFloat()) * 0.012), p)
                }
            }
            p.style = .STROKE; p.strokeWidth = s * 0.02
            p.color = open ? 0x66FFFFFF : 0xB3FFFFFF
            rect.set(win); rect.offset(0, s * 0.006); c.drawRoundRect(rect, wr, wr, p)
            p.style = .FILL
        }
        // glass gloss over the whole face
        c.save(); path = CGMutablePath(); path.addRoundRect(face, rad, rad); c.clipPath(path)
        path2 = CGMutablePath()
        path2.moveTo(face.left, face.top + face.height() * 0.5)
        path2.cubicTo(face.left + face.width() * 0.25, face.top + face.height() * 0.3, face.left + face.width() * 0.6, face.top + face.height() * 0.22,
                      face.right, face.top + face.height() * 0.24)
        path2.lineTo(face.right, face.top); path2.lineTo(face.left, face.top); path2.close()
        p.alpha = 255
        p.shader = Shader.linear(0, face.top, 0, face.top + face.height() * 0.5, Col.alpha(AColor.WHITE, open ? 110 : 70), 0x00FFFFFF)
        c.drawPath(path2, p); p.shader = nil
        c.restore()
        // bevel + outline
        p.style = .STROKE; p.strokeWidth = s * 0.03
        p.alpha = 255
        p.shader = Shader.linear(0, face.top, 0, face.bottom,
                                 [Col.alpha(AColor.WHITE, open ? 230 : 170), Col.alpha(AColor.WHITE, 40), 0x00FFFFFF], [0, 0.45, 1])
        var rim = RectF(face); rim.inset(s * 0.032, s * 0.032)
        c.drawRoundRect(rim, rad * 0.82, rad * 0.82, p); p.shader = nil
        p.strokeWidth = s * 0.024; p.color = Col.alpha(outline, open ? 220 : 110)
        rect.set(x + pad, y + pad, x + s - pad, y + s - pad); c.drawRoundRect(rect, rad, rad, p)
        p.style = .FILL
        // glint
        p.color = Col.alpha(AColor.WHITE, open ? 235 : 160)
        rect.set(face.left + s * 0.1, face.top + s * 0.07, face.left + s * 0.27, face.top + s * 0.12)
        c.save(); c.rotate(-14, rect.centerX(), rect.centerY()); c.drawOval(rect, p); c.restore()
        c.drawCircle(face.left + s * 0.31, face.top + s * 0.085, s * 0.018, p)
    }

    // =================================================================== cups (cylindrical pucks)

    static func puck(_ c: ACanvas, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ colorId: Int, _ hidden: Bool) {
        let base = hidden ? 0xFF8C7BD6 : Painter.colorOf(colorId)
        let eh = h * 0.4
        reset()
        // body: rect + bottom half ellipse
        let bodyRect = CGMutablePath()
        bodyRect.addRectF(x, y + eh / 2, x + w, y + h - eh / 2)
        rect.set(x, y + h - eh, x + w, y + h)
        let bottomOval = CGMutablePath(); bottomOval.addOval(rect)
        let shape: CGPath = bodyRect.union(bottomOval)
        p.alpha = 255
        p.shader = Shader.linear(x, 0, x + w, 0,
                                 [Col.darken(base, 0.42), Col.lighten(base, 0.22), Col.lighten(base, 0.06), base, Col.darken(base, 0.18), Col.darken(base, 0.5)],
                                 [0, 0.16, 0.32, 0.6, 0.86, 1])
        c.drawPath(shape, p)
        c.save(); c.clipPath(shape)
        // bottom shade + lower rim
        p.alpha = 255; p.shader = Shader.linear(0, y + h * 0.45, 0, y + h, 0x00000000, Col.alpha(Col.darken(base, 0.7), 120))
        c.drawRect(x, y, x + w, y + h, p); p.shader = nil
        // specular stripe
        p.alpha = 255; p.shader = Shader.linear(0, y + eh / 2, 0, y + h, Col.alpha(AColor.WHITE, 150), 0x00FFFFFF)
        rect.set(x + w * 0.1, y + eh / 2, x + w * 0.17, y + h)
        c.drawRoundRect(rect, w * 0.03, w * 0.03, p)
        rect.set(x + w * 0.2, y + eh / 2, x + w * 0.225, y + h * 0.85)
        c.drawRect(rect, p); p.shader = nil
        // light band under the lip
        p.style = .STROKE; p.strokeWidth = h * 0.05; p.color = Col.alpha(AColor.WHITE, 70)
        rect.set(x, y + h * 0.66 - eh / 2, x + w, y + h * 0.66 + eh / 2)
        c.drawArc(rect, 10, 160, false, p)
        p.style = .FILL
        c.restore()
        p.style = .STROKE; p.strokeWidth = h * 0.03; p.color = Col.alpha(Col.darken(base, 0.6), 160)
        c.drawPath(shape, p); p.style = .FILL
        // top lip
        rect.set(x, y, x + w, y + eh)
        p.alpha = 255; p.shader = Shader.linear(0, y, 0, y + eh, Col.lighten(base, 0.6), Col.lighten(base, 0.18))
        c.drawOval(rect, p); p.shader = nil
        var inner = RectF(rect); inner.inset(w * 0.035, eh * 0.14)
        p.alpha = 255; p.shader = Shader.radial(x + w * 0.45, y + eh * 0.35, w * 0.6, [Col.lighten(base, 0.3), base], nil)
        c.drawOval(inner, p); p.shader = nil
        p.style = .STROKE; p.strokeWidth = h * 0.035; p.color = Col.darken(base, 0.4)
        c.drawOval(rect, p)
        p.strokeWidth = h * 0.028; p.color = 0xCCFFFFFF
        var hl = RectF(rect); hl.inset(w * 0.02, eh * 0.06)
        c.drawArc(hl, 195, 120, false, p)
        p.style = .FILL
        if hidden {
            Painter.text(c, "?", x + w / 2, y + h * 0.64, h * 0.56, 0xFFFFD54A, 0xFF3B1F7A, h * 0.09)
            return
        }
        // sockets
        for k in -1...1 {
            let sx = x + w / 2 + CGFloat(k) * w * 0.26
            let sy = y + eh / 2
            rect.set(sx - w * 0.1, sy - eh * 0.27, sx + w * 0.1, sy + eh * 0.27)
            p.color = Col.alpha(AColor.WHITE, 120)
            rect.offset(0, eh * 0.06); c.drawOval(rect, p); rect.offset(0, -eh * 0.06)
            p.alpha = 255; p.shader = Shader.radial(sx, sy - eh * 0.12, w * 0.11, [Col.darken(base, 0.82), Col.darken(base, 0.5)], nil)
            c.drawOval(rect, p)
            p.shader = nil
            p.style = .STROKE; p.strokeWidth = h * 0.024; p.color = Col.alpha(Col.lighten(base, 0.35), 210)
            c.drawArc(rect, 25, 130, false, p)
            p.style = .FILL
        }
    }

    // =================================================================== belt parts

    /// Recessed belt socket, drawn centred in a box of side [d].
    static func socket(_ c: ACanvas, _ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) {
        reset()
        p.color = 0x40FFFFFF; c.drawCircle(cx, cy + r * 0.1, r, p)
        p.alpha = 255; p.shader = Shader.radial(cx, cy - r * 0.25, r * 1.05, [0xFF07051A, 0xFF141038, 0xFF3A2F86], [0, 0.68, 1])
        c.drawCircle(cx, cy, r * 0.93, p); p.shader = nil
        p.style = .STROKE; p.strokeWidth = r * 0.12; p.strokeCap = .round
        p.color = 0x5591A0FF; rect.set(cx - r * 0.72, cy - r * 0.72, cx + r * 0.72, cy + r * 0.72)
        c.drawArc(rect, 30, 120, false, p)
        p.style = .FILL
    }

    /// Candy roller hub at the belt ends; rotated at draw time.
    static func hub(_ c: ACanvas, _ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ tint: Int) {
        reset()
        p.color = 0x55000000; c.drawCircle(cx, cy + r * 0.08, r, p)
        p.alpha = 255; p.shader = Shader.linear(0, cy - r, 0, cy + r, CHROME, CHROME_POS)
        c.drawCircle(cx, cy, r * 0.97, p); p.shader = nil
        p.alpha = 255; p.shader = Shader.radial(cx - r * 0.2, cy - r * 0.25, r, [Col.lighten(tint, 0.45), tint, Col.darken(tint, 0.3)], [0, 0.6, 1])
        c.drawCircle(cx, cy, r * 0.78, p); p.shader = nil
        p.color = Col.lighten(tint, 0.75)
        for k in 0..<5 {
            c.save(); c.rotate(CGFloat(k) * 72, cx, cy)
            rect.set(cx - r * 0.1, cy - r * 0.7, cx + r * 0.1, cy - r * 0.2)
            c.drawRoundRect(rect, r * 0.1, r * 0.1, p)
            c.restore()
        }
        p.alpha = 255; p.shader = Shader.radial(cx - r * 0.06, cy - r * 0.06, r * 0.26, [AColor.WHITE, 0xFFA7AFC0], nil)
        c.drawCircle(cx, cy, r * 0.22, p); p.shader = nil
        p.style = .STROKE; p.strokeWidth = r * 0.06; p.color = Col.darken(tint, 0.5)
        c.drawCircle(cx, cy, r * 0.78, p); p.style = .FILL
    }

    // =================================================================== machine parts

    static func gear(_ c: ACanvas, _ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ teeth: Int, _ tint: Int) {
        reset()
        path = CGMutablePath()
        let inner = r * 0.8
        for i in 0..<(teeth * 4) {
            let a = CGFloat(i) * CGFloat.pi * 2 / CGFloat(teeth * 4)
            let rr = ((i / 2) % 2 == 0) ? r : inner
            let px = cx + cos(a) * rr; let py = cy + sin(a) * rr
            if i == 0 { path.moveTo(px, py) } else { path.lineTo(px, py) }
        }
        path.close()
        p.color = 0x66000000
        c.save(); c.translate(0, r * 0.06); c.drawPath(path, p); c.restore()
        p.alpha = 255; p.shader = Shader.radial(cx - r * 0.3, cy - r * 0.3, r * 1.4, [Col.lighten(tint, 0.7), tint, Col.darken(tint, 0.45)], nil)
        c.drawPath(path, p)
        p.shader = nil
        p.style = .STROKE; p.strokeWidth = r * 0.05; p.color = Col.darken(tint, 0.55); c.drawPath(path, p); p.style = .FILL
        // spoke holes
        p.color = Col.darken(tint, 0.6)
        for k in 0..<5 {
            let a = CGFloat(k) * 2 * CGFloat.pi / 5
            c.drawCircle(cx + cos(a) * r * 0.5, cy + sin(a) * r * 0.5, r * 0.13, p)
        }
        p.alpha = 255; p.shader = Shader.radial(cx - r * 0.08, cy - r * 0.08, r * 0.3, [0xFFFFFFFF, 0xFF8A93A6], nil)
        c.drawCircle(cx, cy, r * 0.24, p); p.shader = nil
        p.color = 0xFF3E4456; c.drawCircle(cx, cy, r * 0.08, p)
    }

    /// Chain link / marble cradle, drawn horizontally (direction of travel = +x).
    /// Deep indigo with a dark socket so the bright candy marbles pop on top of it.
    static func cradle(_ c: ACanvas, _ cx: CGFloat, _ cy: CGFloat, _ len: CGFloat, _ wid: CGFloat) {
        reset()
        rect.set(cx - len / 2, cy - wid / 2, cx + len / 2, cy + wid / 2)
        p.alpha = 255; p.shader = Shader.linear(0, rect.top, 0, rect.bottom, [0xFF7566D6, 0xFF4B3DAA, 0xFF2C2270], [0, 0.45, 1])
        c.drawRoundRect(rect, wid * 0.32, wid * 0.32, p); p.shader = nil
        p.style = .STROKE; p.strokeWidth = wid * 0.07; p.color = 0xFF17113D
        c.drawRoundRect(rect, wid * 0.32, wid * 0.32, p); p.style = .FILL
        p.color = 0x55FFFFFF
        c.drawRoundRect(rect.left + wid * 0.2, rect.top + wid * 0.07, rect.right - wid * 0.2, rect.top + wid * 0.15, wid * 0.04, wid * 0.04, p)
        // gold pins
        p.color = 0xFFFFC93C
        c.drawCircle(rect.left + wid * 0.17, cy, wid * 0.085, p); c.drawCircle(rect.right - wid * 0.17, cy, wid * 0.085, p)
        // deep socket
        p.alpha = 255; p.shader = Shader.radial(cx, cy - wid * 0.06, wid * 0.36, [0xFF0B0820, 0xFF1A1442, 0xFF6A5BD0], [0, 0.74, 1])
        c.drawCircle(cx, cy, wid * 0.34, p); p.shader = nil
    }

    static func rivet(_ c: ACanvas, _ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) {
        reset()
        p.color = 0x55000000; c.drawCircle(cx + r * 0.2, cy + r * 0.3, r, p)
        p.alpha = 255; p.shader = Shader.radial(cx - r * 0.35, cy - r * 0.35, r * 1.4, [0xFFFFFFFF, 0xFFB7BFCD, 0xFF6B7387], [0, 0.5, 1])
        c.drawCircle(cx, cy, r, p); p.shader = nil
    }

    static func chromeRect(_ c: ACanvas, _ r: RectF, _ radius: CGFloat, _ vertical: Bool = true) {
        reset()
        p.alpha = 255
        p.shader = vertical ? Shader.linear(0, r.top, 0, r.bottom, CHROME, CHROME_POS) : Shader.linear(r.left, 0, r.right, 0, CHROME, CHROME_POS)
        c.drawRoundRect(r, radius, radius, p); p.shader = nil
        p.style = .STROKE; p.strokeWidth = 1.6; p.color = 0xFF4E5568
        c.drawRoundRect(r, radius, radius, p); p.style = .FILL
    }
}
