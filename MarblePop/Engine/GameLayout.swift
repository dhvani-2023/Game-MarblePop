import Foundation
import GameKit

/// Geometry of the play field in world units. The world is always 720 units wide; its height follows
/// the screen. Top to bottom: board (grid) → hopper → spout → belt → tray.
final class GameLayout {
    let worldH: Float
    let worldW: Float = 720
    let cx: Float
    let marbleR: Float = 12

    // ---- tray
    let trayCols: Int
    let trayLeft: Float = 40
    let trayRight: Float = 680
    let colW: Float
    let cupW: Float
    let cupH: Float = 58
    let cupGap: Float = 2
    private let rowH: Float

    // ---- grid
    let gridW: Int
    let gridH: Int
    let gridMaxH: Int
    let mask: [Bool]
    let boardPad: Float = 20
    let cell: Float
    let gridTop: Float
    let gridBottom: Float
    let funnelH: Float

    // tank aliases kept for the renderer
    let tankLeft: Float = 22
    let tankRight: Float = 698
    let tankTop: Float

    let tankBottom: Float
    let gridLeft: Float
    let gridRight: Float

    // ---- hopper & spout
    let spoutTop: Float
    let spoutHalf: Float
    let gateY: Float
    let gateFloor: Float

    // ---- belt
    let beltR: Float = 34
    let beltLeft: Float = 76
    let beltRight: Float = 644
    let topRunY: Float
    let beltCy: Float
    let trayTop: Float
    let straight: Float
    let xl: Float
    let xr: Float
    let beltLength: Float
    let dishTop: Float
    let dishLeft: Float = 26
    let dishRight: Float = 694

    let dimpleDx: [Float]
    let dimpleDy: Float

    convenience init(worldH: Float, topInset: Float, bottomInset: Float, spec: LevelSpec) {
        self.init(worldH, topInset, bottomInset, spec)
    }

    init(_ worldH: Float, _ topInset: Float, _ bottomInset: Float, _ spec: LevelSpec) {
        self.worldH = worldH
        cx = worldW / 2

        trayCols = spec.tray.count
        colW = (trayRight - trayLeft) / Float(trayCols)
        cupW = colW - 16
        rowH = cupH + cupGap

        gridW = spec.width
        gridH = spec.height
        gridMaxH = spec.height
        mask = spec.mask
        tankTop = topInset

        let belowFunnel: Float = 46 + 2 * marbleR + 6 + 34 + 52
        let minFunnel: Float = 92, maxFunnel: Float = 150
        let rowsMin: Float = 3.2, rowsMax: Float = 4.3
        let avail = worldH - bottomInset - topInset - boardPad * 2 - belowFunnel
        var c = Kt.min((worldW - 90) / Float(gridW), 128)
        c = Kt.min(c, (avail - minFunnel - rowsMin * rowH) / Float(gridH))
        var left = avail - Float(gridH) * c - minFunnel - rowsMin * rowH
        let rowsExtra = Kt.min(left.coerceAtLeast(0), (rowsMax - rowsMin) * rowH); left -= rowsExtra
        let funnelExtra = Kt.min(left.coerceAtLeast(0), maxFunnel - minFunnel); left -= funnelExtra
        cell = c
        funnelH = minFunnel + funnelExtra
        gridTop = topInset + boardPad + left.coerceAtLeast(0) * 0.55
        gridBottom = gridTop + Float(gridH) * c

        tankBottom = gridBottom
        gridLeft = cx - cell * Float(gridW) / 2
        gridRight = cx + cell * Float(gridW) / 2

        spoutTop = gridBottom + funnelH
        spoutHalf = marbleR * 1.3
        gateY = spoutTop + 46
        gateFloor = gateY + marbleR

        topRunY = gateY + marbleR * 2 + 6
        beltCy = topRunY + beltR
        trayTop = beltCy + 52
        straight = (beltRight - beltLeft) - 2 * beltR
        xl = cx - straight / 2
        xr = cx + straight / 2
        // Kotlin: (2 * straight + 2 * PI * beltR).toFloat() — the arc term is Double maths
        beltLength = Float(Double(2 * straight) + 2 * Double.pi * Double(beltR))
        dishTop = beltCy - beltR - 36

        dimpleDx = [-cupW * 0.26, 0, cupW * 0.26]
        dimpleDy = cupH * 0.19 - marbleR * 0.45
    }

    func colCenter(_ c: Int) -> Float { trayLeft + colW * (Float(c) + 0.5) }
    func cupTop(_ index: Float) -> Float { trayTop + index * (cupH + cupGap) }

    func active(_ c: Int, _ r: Int) -> Bool { c >= 0 && c < gridW && r >= 0 && r < gridH && mask[r * gridW + c] }
    func cellLeft(_ c: Int) -> Float { gridLeft + Float(c) * cell }
    func cellCenterX(_ c: Int) -> Float { gridLeft + (Float(c) + 0.5) * cell }
    /// Top y of a cell whose (animated) row is `row`; row 0 is the bottom row.
    func cellTop(_ row: Float) -> Float { gridBottom - (row + 1) * cell }
    func cellCenterY(_ row: Float) -> Float { gridBottom - (row + 0.5) * cell }

    /// Belt path position for arc-length s (0 = entry point at the top centre, moving right).
    func beltPoint(_ sIn: Float, _ out: inout [Float]) {
        let p = beltPoint(sIn)
        out[0] = p.x; out[1] = p.y
    }

    /// Tuple form of `beltPoint(s, out)` (same maths, no array).
    func beltPoint(_ sIn: Float) -> (x: Float, y: Float) {
        var s = Kt.rem(sIn, beltLength)
        if s < 0 { s += beltLength }
        let half = straight / 2
        let arc = Float(Double.pi * Double(beltR))
        if s < half {
            return (cx + s, topRunY)
        } else if s < half + arc {
            let t = (s - half) / beltR
            return (xr + beltR * Kt.sin(t), beltCy - beltR * Kt.cos(t))
        } else if s < half + arc + straight {
            return (xr - (s - half - arc), beltCy + beltR)
        } else if s < half + 2 * arc + straight {
            let t = (s - half - arc - straight) / beltR
            return (xl - beltR * Kt.sin(t), beltCy + beltR * Kt.cos(t))
        } else {
            return (xl + (s - half - 2 * arc - straight), topRunY)
        }
    }
}
