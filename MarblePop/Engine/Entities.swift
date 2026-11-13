import Foundation
import GameKit

/// The engine's stand-in for Kotlin's unseeded global `kotlin.random.Random` (marble spin, particle spread,
/// sound pitch jitter, anti-jam nudge, shuffle booster). A randomly seeded XorWow in the app; tests reseed
/// `source` to replay JVM simulation traces bit-exactly.
enum EngineRandom {
    static var source = KotlinRandom(Int64.random(in: Int64.min...Int64.max))
    @inline(__always) static func nextFloat() -> Float { source.nextFloat() }
}

enum MarbleState: Int { case PATH, PHYSICS, BOARDING, BELT, DROPPING, FLYING }

final class Marble {
    let color: Int
    var state = MarbleState.PHYSICS
    var x: Float = 0; var y: Float = 0
    var px: Float = 0; var py: Float = 0
    var channel = -1
    var slot = -1
    var angle: Float
    // tween
    var t: Float = 0
    var dur: Float = 0.2
    var sx: Float = 0; var sy: Float = 0
    var targetCol = -1
    var targetCup: Cup?
    var targetDimple = 0
    var prevX: Float = 0
    var squash: Float = 0
    var age: Float = 0
    var stuckT: Float = 0
    /// PATH waypoints (x,y pairs) the marble follows out of the board.
    var wp: [Float]?
    var wpi = 0
    var wait: Float = 0

    init(_ color: Int) {
        self.color = color
        angle = EngineRandom.nextFloat() * 360
    }
}

final class Cup {
    var color: Int
    var hidden: Bool
    var reserved = 0
    var arrived = 0
    var display: Float = 0        // animated stack index
    var popping = false
    var popT: Float = 0
    var bounce: Float = 0
    var vel: Float = 0
    var reveal: Float
    var revealing = false
    var shuffleT: Float = 0

    init(_ color: Int, _ hidden: Bool) {
        self.color = color
        self.hidden = hidden
        reveal = hidden ? 0 : 1
    }
}

final class TrayColumn {
    var cups: [Cup] = []
}

final class BlockVisual {
    let state: BlockState
    let index: Int
    let col: Int
    let row: Int
    /// Extra rows above the resting place (intro drop).
    var dropY: Float = 0
    var dropVel: Float = 0
    var delay: Float = 0
    var squash: Float = 0
    var shake: Float = 0
    var flash: Float = 0
    var reveal: Float
    var crack: Float = 0
    var unlock: Float = 0
    var wasLocked = false
    var pulse: Float = 0
    var paint: Float = 0
    /// 0 = blocked (flat), 1 = open (has a way out). Animated for smooth wake-ups.
    var open: Float = 0
    var wasOpen = false
    var wake: Float = 0

    init(_ state: BlockState, _ index: Int, _ col: Int, _ row: Int) {
        self.state = state
        self.index = index
        self.col = col
        self.row = row
        reveal = state.revealed ? 1 : 0
    }
}

/// A block that just left the board (quick shrink + fade).
final class ExitingBlock {
    let state: BlockState
    let x: Float
    let y: Float
    let cell: Float
    var t: Float = 0

    init(_ state: BlockState, _ x: Float, _ y: Float, _ cell: Float) {
        self.state = state
        self.x = x
        self.y = y
        self.cell = cell
    }
}

final class FlyingBlock {
    let state: BlockState
    let x0: Float
    let y0: Float
    let cell: Float
    var t: Float = 0
    let duration: Float = 0.55
    var mx: Float = 0; var my: Float = 0 // exit point
    var tx: Float = 0; var ty: Float = 0 // burst point
    var x: Float; var y: Float
    var rot: Float = 0
    var scale: Float = 1

    init(_ state: BlockState, _ x0: Float, _ y0: Float, _ cell: Float) {
        self.state = state
        self.x0 = x0
        self.y0 = y0
        self.cell = cell
        x = x0
        y = y0
    }
}

final class FloatingText {
    let text: String
    var x: Float
    var y: Float
    let color: UInt32
    let size: Float
    var life: Float = 0
    let maxLife: Float = 0.9

    init(_ text: String, _ x: Float, _ y: Float, _ color: UInt32, _ size: Float) {
        self.text = text
        self.x = x
        self.y = y
        self.color = color
        self.size = size
    }
}

private let PI_F = Float(Double.pi)

/// Pooled particle system using flat arrays (no allocation per frame).
final class Particles {
    let capacity: Int
    private(set) var x: [Float]; private(set) var y: [Float]
    private(set) var vx: [Float]; private(set) var vy: [Float]
    private(set) var life: [Float]; private(set) var maxLife: [Float]
    private(set) var size: [Float]; private(set) var rot: [Float]; private(set) var vrot: [Float]
    private(set) var grav: [Float]
    private(set) var color: [UInt32]; private(set) var type: [Int]
    private(set) var count = 0

    static let DOT = 0, STAR = 1, CONFETTI = 2, RING = 3, SHARD = 4, SMOKE = 5, LID = 6

    init(_ capacity: Int = 420) {
        self.capacity = capacity
        let z = [Float](repeating: 0, count: capacity)
        x = z; y = z; vx = z; vy = z; life = z; maxLife = z; size = z; rot = z; vrot = z; grav = z
        color = [UInt32](repeating: 0, count: capacity)
        type = [Int](repeating: 0, count: capacity)
    }

    func emit(_ px: Float, _ py: Float, _ pvx: Float, _ pvy: Float, _ l: Float, _ s: Float, _ c: UInt32, _ t: Int,
              _ g: Float = 0, _ vr: Float = 0) {
        if count >= capacity { return }
        let i = count
        count += 1
        x[i] = px; y[i] = py; vx[i] = pvx; vy[i] = pvy; life[i] = l; maxLife[i] = l
        size[i] = s; color[i] = c; type[i] = t; grav[i] = g; rot[i] = EngineRandom.nextFloat() * 360; vrot[i] = vr
    }

    func burst(_ px: Float, _ py: Float, _ n: Int, _ speed: Float, _ c: UInt32, _ t: Int, _ s: Float, _ l: Float, _ g: Float = 0) {
        for _ in 0..<max(0, n) {
            let a = EngineRandom.nextFloat() * 2 * PI_F
            let sp = speed * (0.4 + EngineRandom.nextFloat() * 0.8)
            emit(px, py, Kt.cos(a) * sp, Kt.sin(a) * sp, l * (0.7 + EngineRandom.nextFloat() * 0.5), s * (0.6 + EngineRandom.nextFloat() * 0.7), c, t, g,
                 (EngineRandom.nextFloat() - 0.5) * 720)
        }
    }

    func update(_ dt: Float) {
        var i = 0
        while i < count {
            life[i] -= dt
            if life[i] <= 0 {
                count -= 1
                let last = count
                if i != last {
                    x[i] = x[last]; y[i] = y[last]; vx[i] = vx[last]; vy[i] = vy[last]
                    life[i] = life[last]; maxLife[i] = maxLife[last]; size[i] = size[last]
                    rot[i] = rot[last]; vrot[i] = vrot[last]; grav[i] = grav[last]
                    color[i] = color[last]; type[i] = type[last]
                }
                continue
            }
            vy[i] += grav[i] * dt
            if type[i] == Particles.CONFETTI { vx[i] *= 0.985; vy[i] = vy[i].coerceAtMost(260) } else { vx[i] *= 0.97; vy[i] *= 0.97 }
            x[i] += vx[i] * dt; y[i] += vy[i] * dt
            rot[i] += vrot[i] * dt
            i += 1
        }
    }

    func clear() { count = 0 }
}
