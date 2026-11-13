import CoreGraphics
import CoreText
import Foundation
#if canImport(UIKit)
import UIKit
#endif

// A small android.graphics equivalent on top of Core Graphics (Paint, shaders, RectF, Canvas with
// save/restore/saveLayerAlpha, BlurMaskFilter, CornerPathEffect, centred text), so that MachineArt, Painter,
// SpriteCache and the GameRenderer's baked layers port line by line from Kotlin.
// All coordinates are y-down (top-left origin), like Android. Colours are ARGB ints (low 32 bits).

/// android.graphics.Color statics for ARGB ints.
enum AColor {
    static let WHITE = 0xFFFFFFFF
    static let BLACK = 0xFF000000
    static let TRANSPARENT = 0x00000000

    @inline(__always) static func alpha(_ c: Int) -> Int { (c >> 24) & 0xFF }
    @inline(__always) static func red(_ c: Int) -> Int { (c >> 16) & 0xFF }
    @inline(__always) static func green(_ c: Int) -> Int { (c >> 8) & 0xFF }
    @inline(__always) static func blue(_ c: Int) -> Int { c & 0xFF }
    @inline(__always) static func argb(_ a: Int, _ r: Int, _ g: Int, _ b: Int) -> Int {
        ((a & 0xFF) << 24) | ((r & 0xFF) << 16) | ((g & 0xFF) << 8) | (b & 0xFF)
    }

    static func cg(_ c: Int) -> CGColor {
        CGColor(colorSpace: Bake.sRGB, components: [CGFloat(red(c)) / 255, CGFloat(green(c)) / 255,
                                                    CGFloat(blue(c)) / 255, CGFloat(alpha(c)) / 255])!
    }
}

/// Any integer ARGB value (Int, Int32, UInt32, Int64; either sign) as a positive ARGB Int.
@inline(__always) func argbInt<T: BinaryInteger>(_ v: T) -> Int { Int(truncatingIfNeeded: v) & 0xFFFFFFFF }

// MARK: - Paint & shaders

/// android.graphics.Paint subset. `blurRadius` is BlurMaskFilter(radius, NORMAL).
final class Paint {
    enum Style { case FILL, STROKE }

    var color: Int = AColor.BLACK
    var shader: Shader?
    var style: Style = .FILL
    var strokeWidth: CGFloat = 0
    var strokeCap: CGLineCap = .butt
    var strokeJoin: CGLineJoin = .miter
    var blurRadius: CGFloat = 0

    var alpha: Int {
        get { AColor.alpha(color) }
        set { color = (color & 0x00FFFFFF) | (max(0, min(255, newValue)) << 24) }
    }

    func reset() {
        color = AColor.BLACK; shader = nil; style = .FILL; strokeWidth = 0
        strokeCap = .butt; strokeJoin = .miter; blurRadius = 0
    }
}

/// LinearGradient / RadialGradient / SweepGradient with CLAMP tiling.
final class Shader {
    enum Kind {
        case linear(CGPoint, CGPoint)
        case radial(CGPoint, CGFloat)
        case sweep(CGPoint)
    }

    let kind: Kind
    let gradient: CGGradient

    init(_ kind: Kind, _ colors: [Int], _ positions: [CGFloat]?) {
        self.kind = kind
        var comps: [CGFloat] = []
        comps.reserveCapacity(colors.count * 4)
        for c in colors {
            comps.append(CGFloat(AColor.red(c)) / 255); comps.append(CGFloat(AColor.green(c)) / 255)
            comps.append(CGFloat(AColor.blue(c)) / 255); comps.append(CGFloat(AColor.alpha(c)) / 255)
        }
        if let positions {
            gradient = CGGradient(colorSpace: Bake.sRGB, colorComponents: comps, locations: positions, count: colors.count)!
        } else {
            gradient = CGGradient(colorSpace: Bake.sRGB, colorComponents: comps, locations: nil, count: colors.count)!
        }
    }

    static func linear(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat, _ colors: [Int], _ positions: [CGFloat]?) -> Shader {
        Shader(.linear(CGPoint(x: x0, y: y0), CGPoint(x: x1, y: y1)), colors, positions)
    }

    static func linear(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat, _ c0: Int, _ c1: Int) -> Shader {
        Shader(.linear(CGPoint(x: x0, y: y0), CGPoint(x: x1, y: y1)), [c0, c1], nil)
    }

    static func radial(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ colors: [Int], _ positions: [CGFloat]?) -> Shader {
        Shader(.radial(CGPoint(x: cx, y: cy), r), colors, positions)
    }

    static func radial(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ c0: Int, _ c1: Int) -> Shader {
        Shader(.radial(CGPoint(x: cx, y: cy), r), [c0, c1], nil)
    }

    static func sweep(_ cx: CGFloat, _ cy: CGFloat, _ colors: [Int], _ positions: [CGFloat]?) -> Shader {
        Shader(.sweep(CGPoint(x: cx, y: cy)), colors, positions)
    }
}

// MARK: - RectF

/// android.graphics.RectF.
struct RectF {
    var left: CGFloat = 0, top: CGFloat = 0, right: CGFloat = 0, bottom: CGFloat = 0

    init() {}
    init(_ l: CGFloat, _ t: CGFloat, _ r: CGFloat, _ b: CGFloat) { left = l; top = t; right = r; bottom = b }
    init(_ o: RectF) { self = o }

    mutating func set(_ l: CGFloat, _ t: CGFloat, _ r: CGFloat, _ b: CGFloat) { left = l; top = t; right = r; bottom = b }
    mutating func set(_ o: RectF) { self = o }
    mutating func inset(_ dx: CGFloat, _ dy: CGFloat) { left += dx; top += dy; right -= dx; bottom -= dy }
    mutating func offset(_ dx: CGFloat, _ dy: CGFloat) { left += dx; right += dx; top += dy; bottom += dy }

    func width() -> CGFloat { right - left }
    func height() -> CGFloat { bottom - top }
    func centerX() -> CGFloat { (left + right) * 0.5 }
    func centerY() -> CGFloat { (top + bottom) * 0.5 }

    var cg: CGRect { CGRect(x: left, y: top, width: right - left, height: bottom - top) }
}

// MARK: - Path building (Android Path verbs; all shapes clockwise in y-down space, like Path.Direction.CW)

extension CGMutablePath {
    func moveTo(_ x: CGFloat, _ y: CGFloat) { move(to: CGPoint(x: x, y: y)) }
    func lineTo(_ x: CGFloat, _ y: CGFloat) { addLine(to: CGPoint(x: x, y: y)) }
    func quadTo(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat) {
        addQuadCurve(to: CGPoint(x: x2, y: y2), control: CGPoint(x: x1, y: y1))
    }
    func cubicTo(_ x1: CGFloat, _ y1: CGFloat, _ x2: CGFloat, _ y2: CGFloat, _ x3: CGFloat, _ y3: CGFloat) {
        addCurve(to: CGPoint(x: x3, y: y3), control1: CGPoint(x: x1, y: y1), control2: CGPoint(x: x2, y: y2))
    }
    func close() { closeSubpath() }

    func addCircle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat) {
        addEllipse(in: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r))
    }
    func addOval(_ r: RectF) { addEllipse(in: r.cg) }
    func addRectF(_ l: CGFloat, _ t: CGFloat, _ r: CGFloat, _ b: CGFloat) {
        addRect(CGRect(x: min(l, r), y: min(t, b), width: abs(r - l), height: abs(b - t)))
    }
    func addRoundRect(_ rect: RectF, _ rx: CGFloat, _ ry: CGFloat) {
        let r = rect.cg.standardized
        let (cx, cy) = ACanvas.clampRadii(r, rx, ry)
        addRoundedRect(in: r, cornerWidth: cx, cornerHeight: cy)
    }
}

// MARK: - Canvas

/// android.graphics.Canvas on a y-down CGContext.
final class ACanvas {
    let cg: CGContext
    private var stack: [Bool] = [] // true = transparency layer

    init(_ cg: CGContext) {
        self.cg = cg
        cg.setShouldAntialias(true)
        cg.setAllowsAntialiasing(true)
        cg.setMiterLimit(4)
    }

    /// Skia's round-rect radius fitting: both radii are scaled by the same factor until they fit.
    static func clampRadii(_ r: CGRect, _ rx: CGFloat, _ ry: CGFloat) -> (CGFloat, CGFloat) {
        let w = r.width, h = r.height
        if w <= 0 || h <= 0 { return (0, 0) }
        var x = max(0, rx), y = max(0, ry)
        if x <= 0 || y <= 0 { return (0, 0) }
        var k: CGFloat = 1
        if x + x > w { k = min(k, w / (x + x)) }
        if y + y > h { k = min(k, h / (y + y)) }
        x *= k; y *= k
        return (min(x, w / 2), min(y, h / 2))
    }

    // ---- state

    func save() { cg.saveGState(); stack.append(false) }

    func restore() {
        guard let layer = stack.popLast() else { return }
        if layer { cg.endTransparencyLayer() }
        cg.restoreGState()
    }

    func saveLayerAlpha(_ l: CGFloat, _ t: CGFloat, _ r: CGFloat, _ b: CGFloat, _ alpha: Int) {
        cg.saveGState()
        cg.setAlpha(CGFloat(max(0, min(255, alpha))) / 255)
        cg.beginTransparencyLayer(in: CGRect(x: l, y: t, width: r - l, height: b - t), auxiliaryInfo: nil)
        stack.append(true)
    }

    func saveLayerAlpha(_ r: RectF, _ alpha: Int) { saveLayerAlpha(r.left, r.top, r.right, r.bottom, alpha) }

    func translate(_ dx: CGFloat, _ dy: CGFloat) { cg.translateBy(x: dx, y: dy) }
    func scale(_ sx: CGFloat, _ sy: CGFloat) { cg.scaleBy(x: sx, y: sy) }
    func scale(_ sx: CGFloat, _ sy: CGFloat, _ px: CGFloat, _ py: CGFloat) {
        cg.translateBy(x: px, y: py); cg.scaleBy(x: sx, y: sy); cg.translateBy(x: -px, y: -py)
    }
    func rotate(_ degrees: CGFloat) { cg.rotate(by: degrees * .pi / 180) }
    func rotate(_ degrees: CGFloat, _ px: CGFloat, _ py: CGFloat) {
        cg.translateBy(x: px, y: py); cg.rotate(by: degrees * .pi / 180); cg.translateBy(x: -px, y: -py)
    }

    func clipPath(_ path: CGPath) { cg.addPath(path); cg.clip() }
    func clipRect(_ l: CGFloat, _ t: CGFloat, _ r: CGFloat, _ b: CGFloat) {
        cg.clip(to: CGRect(x: l, y: t, width: r - l, height: b - t))
    }

    // ---- primitives

    func drawCircle(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ p: Paint) {
        if r <= 0 { return }
        drawPath(CGPath(ellipseIn: CGRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r), transform: nil), p)
    }

    func drawOval(_ r: RectF, _ p: Paint) {
        drawPath(CGPath(ellipseIn: r.cg.standardized, transform: nil), p)
    }

    func drawRect(_ r: RectF, _ p: Paint) { drawRect(r.left, r.top, r.right, r.bottom, p) }
    func drawRect(_ l: CGFloat, _ t: CGFloat, _ r: CGFloat, _ b: CGFloat, _ p: Paint) {
        drawPath(CGPath(rect: CGRect(x: l, y: t, width: r - l, height: b - t).standardized, transform: nil), p)
    }

    func drawRoundRect(_ r: RectF, _ rx: CGFloat, _ ry: CGFloat, _ p: Paint) {
        let rect = r.cg.standardized
        let (cx, cy) = ACanvas.clampRadii(rect, rx, ry)
        drawPath(CGPath(roundedRect: rect, cornerWidth: cx, cornerHeight: cy, transform: nil), p)
    }

    func drawRoundRect(_ l: CGFloat, _ t: CGFloat, _ r: CGFloat, _ b: CGFloat, _ rx: CGFloat, _ ry: CGFloat, _ p: Paint) {
        drawRoundRect(RectF(l, t, r, b), rx, ry, p)
    }

    /// Angles in degrees, 0 = 3 o'clock, positive = clockwise (parametric on the oval, like Skia).
    func drawArc(_ oval: RectF, _ startAngle: CGFloat, _ sweepAngle: CGFloat, _ useCenter: Bool, _ p: Paint) {
        let path = CGMutablePath()
        let t = CGAffineTransform(translationX: oval.centerX(), y: oval.centerY())
            .scaledBy(x: oval.width() / 2, y: oval.height() / 2)
        let a0 = startAngle * .pi / 180, a1 = (startAngle + sweepAngle) * .pi / 180
        if useCenter {
            path.move(to: CGPoint(x: oval.centerX(), y: oval.centerY()))
            path.addLine(to: CGPoint(x: cos(a0), y: sin(a0)), transform: t)
            path.addArc(center: .zero, radius: 1, startAngle: a0, endAngle: a1, clockwise: sweepAngle < 0, transform: t)
            path.closeSubpath()
        } else {
            path.move(to: CGPoint(x: cos(a0), y: sin(a0)), transform: t)
            path.addArc(center: .zero, radius: 1, startAngle: a0, endAngle: a1, clockwise: sweepAngle < 0, transform: t)
        }
        drawPath(path, p)
    }

    /// Lines are always stroked (Android ignores the paint style).
    func drawLine(_ x0: CGFloat, _ y0: CGFloat, _ x1: CGFloat, _ y1: CGFloat, _ p: Paint) {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: x0, y: y0)); path.addLine(to: CGPoint(x: x1, y: y1))
        let style = p.style
        p.style = .STROKE
        drawPath(path, p)
        p.style = style
    }

    /// Draws a bitmap into [dst] (upright in the y-down space).
    func drawBitmap(_ img: CGImage, _ dst: RectF, alpha: Int = 255) {
        cg.saveGState()
        cg.translateBy(x: dst.left, y: dst.bottom)
        cg.scaleBy(x: 1, y: -1)
        if alpha < 255 { cg.setAlpha(CGFloat(max(0, alpha)) / 255) }
        cg.interpolationQuality = .high
        cg.draw(img, in: CGRect(x: 0, y: 0, width: dst.width(), height: dst.height()))
        cg.restoreGState()
    }

    func drawPath(_ path: CGPath, _ p: Paint) {
        if p.blurRadius > 0 { drawBlurred(path, p); return }
        if p.style == .FILL {
            if let sh = p.shader {
                cg.saveGState()
                cg.addPath(path); cg.clip()
                paintShader(sh, p.alpha)
                cg.restoreGState()
            } else {
                cg.setFillColor(AColor.cg(p.color))
                cg.addPath(path); cg.fillPath()
            }
        } else {
            applyStroke(p)
            if let sh = p.shader {
                cg.saveGState()
                cg.addPath(path); cg.replacePathWithStrokedPath(); cg.clip()
                paintShader(sh, p.alpha)
                cg.restoreGState()
            } else {
                cg.setStrokeColor(AColor.cg(p.color))
                cg.addPath(path); cg.strokePath()
            }
        }
    }

    private func applyStroke(_ p: Paint) {
        cg.setLineWidth(p.strokeWidth)
        cg.setLineCap(p.strokeCap)
        cg.setLineJoin(p.strokeJoin)
        cg.setMiterLimit(4)
    }

    private func paintShader(_ sh: Shader, _ alpha: Int) {
        if alpha < 255 { cg.setAlpha(CGFloat(max(0, alpha)) / 255) }
        switch sh.kind {
        case let .linear(a, b):
            cg.drawLinearGradient(sh.gradient, start: a, end: b, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        case let .radial(c, r):
            cg.drawRadialGradient(sh.gradient, startCenter: c, startRadius: 0, endCenter: c, endRadius: max(r, 0.0001),
                                  options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        case let .sweep(c):
            CGContextDrawConicGradient(cg, sh.gradient, c, 0)
        }
    }

    /// BlurMaskFilter(NORMAL): only the Gaussian-blurred shape is drawn. Done with an off-canvas shape and a
    /// shadow offset that brings its shadow back in place. Sigma follows Android (0.57735 r + 0.5, scaled by the CTM).
    private func drawBlurred(_ path: CGPath, _ p: Paint) {
        let ctm = cg.ctm
        let sx = max((ctm.a * ctm.a + ctm.b * ctm.b).squareRoot(), 0.0001)
        let sigma = (0.57735 * p.blurRadius + 0.5) * sx
        let shift: CGFloat = 40000 // device px
        cg.saveGState()
        cg.setShadow(offset: CGSize(width: shift, height: 0), blur: 2 * sigma, color: AColor.cg(p.color))
        cg.translateBy(x: -shift / sx, y: 0)
        if p.style == .FILL {
            cg.setFillColor(AColor.cg(AColor.BLACK))
            cg.addPath(path); cg.fillPath()
        } else {
            applyStroke(p)
            cg.setStrokeColor(AColor.cg(AColor.BLACK))
            cg.addPath(path); cg.strokePath()
        }
        cg.restoreGState()
    }
}

// MARK: - Path effects

enum PathFx {
    private enum Seg {
        case line(CGPoint, CGPoint)
        case quad(CGPoint, CGPoint, CGPoint)
        case cubic(CGPoint, CGPoint, CGPoint, CGPoint)
    }

    private struct Contour {
        var start: CGPoint
        var segs: [Seg] = []
        var closed = false
    }

    @inline(__always) private static func same(_ a: CGPoint, _ b: CGPoint) -> Bool {
        let dx = a.x - b.x, dy = a.y - b.y
        return dx * dx + dy * dy < 1e-10
    }

    private static func contours(_ p: CGPath) -> [Contour] {
        var out: [Contour] = []
        var cur: Contour?
        var pt = CGPoint.zero
        var lastStart = CGPoint.zero
        p.applyWithBlock { e in
            let el = e.pointee
            switch el.type {
            case .moveToPoint:
                if let c = cur { out.append(c) }
                pt = el.points[0]; lastStart = pt
                cur = Contour(start: pt)
            case .addLineToPoint:
                if cur == nil { cur = Contour(start: lastStart); pt = lastStart }
                let q = el.points[0]
                if !same(q, pt) { cur!.segs.append(.line(pt, q)) } // consume degenerate lines
                pt = q
            case .addQuadCurveToPoint:
                if cur == nil { cur = Contour(start: lastStart); pt = lastStart }
                let c1 = el.points[0], q = el.points[1]
                cur!.segs.append(.quad(pt, c1, q)); pt = q
            case .addCurveToPoint:
                if cur == nil { cur = Contour(start: lastStart); pt = lastStart }
                let c1 = el.points[0], c2 = el.points[1], q = el.points[2]
                cur!.segs.append(.cubic(pt, c1, c2, q)); pt = q
            case .closeSubpath:
                if var c = cur {
                    if !same(pt, c.start) { c.segs.append(.line(pt, c.start)) } // Skia's auto-close line
                    c.closed = true
                    out.append(c)
                    pt = c.start
                }
                cur = nil
            @unknown default:
                break
            }
        }
        if let c = cur { out.append(c) }
        return out
    }

    private static func computeStep(_ a: CGPoint, _ b: CGPoint, _ radius: CGFloat) -> (Bool, CGPoint) {
        let dx = b.x - a.x, dy = b.y - a.y
        let dist = (dx * dx + dy * dy).squareRoot()
        if dist <= radius * 2 { return (false, CGPoint(x: dx * 0.5, y: dy * 0.5)) }
        let k = radius / dist
        return (true, CGPoint(x: dx * k, y: dy * k))
    }

    /// Port of Skia's CornerPathEffect: every corner between two line segments is replaced by a quadratic
    /// through the corner; curves are passed through (the line before a curve is shortened, as in Skia).
    static func corner(_ src: CGPath, _ radius: CGFloat) -> CGPath {
        let dst = CGMutablePath()
        if radius <= 0 { dst.addPath(src); return dst }
        for c in contours(src) {
            var prevIsValid = !c.closed
            if !c.closed { dst.move(to: c.start) }
            var firstStep = CGPoint.zero
            var step = CGPoint.zero
            var lastCorner = c.start
            var lastWasLine = false
            for (i, s) in c.segs.enumerated() {
                switch s {
                case let .line(a, b):
                    let (drawSegment, st) = computeStep(a, b, radius)
                    step = st
                    if !prevIsValid {
                        dst.move(to: CGPoint(x: c.start.x + step.x, y: c.start.y + step.y))
                        prevIsValid = true
                    } else {
                        dst.addQuadCurve(to: CGPoint(x: a.x + step.x, y: a.y + step.y), control: a)
                    }
                    if drawSegment { dst.addLine(to: CGPoint(x: b.x - step.x, y: b.y - step.y)) }
                    lastCorner = b
                    if i == 0 { firstStep = step }
                    lastWasLine = true
                case let .quad(a, c1, b):
                    if !prevIsValid { dst.move(to: a); prevIsValid = true }
                    dst.addQuadCurve(to: b, control: c1)
                    lastCorner = b; firstStep = .zero; lastWasLine = false
                case let .cubic(a, c1, c2, b):
                    if !prevIsValid { dst.move(to: a); prevIsValid = true }
                    dst.addCurve(to: b, control1: c1, control2: c2)
                    lastCorner = b; firstStep = .zero; lastWasLine = false
                }
            }
            if c.closed {
                if firstStep.x != 0 || firstStep.y != 0 {
                    dst.addQuadCurve(to: CGPoint(x: lastCorner.x + firstStep.x, y: lastCorner.y + firstStep.y), control: lastCorner)
                }
                dst.closeSubpath()
            } else if lastWasLine && prevIsValid {
                dst.addLine(to: lastCorner)
            }
        }
        return dst
    }

    /// PathDashPathEffect(circle(radius), advance, phase 0, TRANSLATE) along a quadratic: dot centres at
    /// arc-length 0, advance, 2·advance… (< length).
    static func dotsAlongQuad(_ p0: CGPoint, _ c: CGPoint, _ p1: CGPoint, advance: CGFloat, radius: CGFloat) -> CGPath {
        let out = CGMutablePath()
        let n = 256
        var prev = p0
        var acc: CGFloat = 0
        var next: CGFloat = 0
        out.addEllipse(in: CGRect(x: p0.x - radius, y: p0.y - radius, width: radius * 2, height: radius * 2))
        next += advance
        for i in 1...n {
            let t = CGFloat(i) / CGFloat(n), u = 1 - t
            let q = CGPoint(x: u * u * p0.x + 2 * u * t * c.x + t * t * p1.x, y: u * u * p0.y + 2 * u * t * c.y + t * t * p1.y)
            let d = hypot(q.x - prev.x, q.y - prev.y)
            while d > 0 && acc + d > next {
                let k = (next - acc) / d
                let x = prev.x + (q.x - prev.x) * k, y = prev.y + (q.y - prev.y) * k
                out.addEllipse(in: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2))
                next += advance
            }
            acc += d
            prev = q
        }
        return out
    }
}

// MARK: - Text outlines

enum TextPaths {
    /// Glyph outlines of one line: baseline at y = 0 (y-down), pen starting at x = 0. Returns the outline and the advance width.
    static func line(_ s: String, _ font: CTFont) -> (CGPath, CGFloat) {
        let attr = NSAttributedString(string: s, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font])
        let line = CTLineCreateWithAttributedString(attr)
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        let path = CGMutablePath()
        let runs = CTLineGetGlyphRuns(line) as? [CTRun] ?? []
        for run in runs {
            let attrs = CTRunGetAttributes(run) as NSDictionary
            var runFont = font
            if let v = attrs[kCTFontAttributeName as String] { runFont = v as! CTFont }
            let n = CTRunGetGlyphCount(run)
            if n == 0 { continue }
            var glyphs = [CGGlyph](repeating: 0, count: n)
            var pos = [CGPoint](repeating: .zero, count: n)
            CTRunGetGlyphs(run, CFRange(location: 0, length: n), &glyphs)
            CTRunGetPositions(run, CFRange(location: 0, length: n), &pos)
            for i in 0..<n {
                var t = CGAffineTransform(a: 1, b: 0, c: 0, d: -1, tx: pos[i].x, ty: -pos[i].y)
                if let gp = CTFontCreatePathForGlyph(runFont, glyphs[i], &t) { path.addPath(gp) }
            }
        }
        return (path, width)
    }
}

// MARK: - Baking

enum Bake {
    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    /// A premultiplied RGBA bitmap context with a y-down coordinate system in pixels.
    static func context(_ w: Int, _ h: Int) -> CGContext {
        let ctx = CGContext(data: nil, width: max(1, w), height: max(1, h), bitsPerComponent: 8, bytesPerRow: 0,
                            space: sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.translateBy(x: 0, y: CGFloat(max(1, h)))
        ctx.scaleBy(x: 1, y: -1)
        ctx.interpolationQuality = .high
        return ctx
    }

    static func image(_ w: Int, _ h: Int, _ draw: (ACanvas) -> Void) -> CGImage {
        let ctx = context(w, h)
        draw(ACanvas(ctx))
        return ctx.makeImage()!
    }
}

/// Device pixels per point (3 on current iPhones).
enum DisplayScale {
    static let value: CGFloat = {
        #if canImport(UIKit)
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                for scene in UIApplication.shared.connectedScenes {
                    if let ws = scene as? UIWindowScene, ws.screen.scale >= 1 { return ws.screen.scale }
                }
                let t = UITraitCollection.current.displayScale
                return t >= 1 ? t : 3
            }
        }
        #endif
        return 3
    }()
}
