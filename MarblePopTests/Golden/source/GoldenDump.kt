// Golden dump for the iOS port of Marble Pop Factory.
//
// Compiled against copies of the Android sources level/*.kt and engine/*.kt (unchanged except: the engine's
// global `kotlin.random.Random` is routed through a seedable `engine/Random.kt` object, and shuffleTray's
// `shuffled()` uses that same generator), plus a resource-free `core/Sfx.kt`.
//
//   levels.json — the full definition of every level 1..5000 from LevelGenerator.generate(n), one per line.
//   traces.json — deterministic GameEngine runs: a 64-bit FNV-1a hash of the whole engine state after every
//                 frame, plus every listener event (sound / haptic / combo / status) and booster result.
//
// Build & run:
//   K="/Applications/Android Studio.app/Contents/plugins/Kotlin/kotlinc"
//   JAVA_HOME="/Applications/Android Studio.app/Contents/jbr/Contents/Home" "$K/bin/kotlinc" src dump -d out/dump.jar
//   JAVA_HOME=... "$K/bin/kotlin" -cp out/dump.jar GoldenDumpKt <outDir>
package golden

import com.puzzel.lab.marbelshort.core.Sfx
import com.puzzel.lab.marbelshort.engine.GameEngine
import com.puzzel.lab.marbelshort.engine.GameLayout
import com.puzzel.lab.marbelshort.engine.GameListener
import com.puzzel.lab.marbelshort.engine.GameStatus
import com.puzzel.lab.marbelshort.engine.Haptic
import com.puzzel.lab.marbelshort.engine.Random
import com.puzzel.lab.marbelshort.level.BlockKind
import com.puzzel.lab.marbelshort.level.LevelGenerator
import com.puzzel.lab.marbelshort.level.LevelSpec
import java.io.File

fun levelLine(s: LevelSpec): String {
    val b = StringBuilder()
    b.append("{\"n\":").append(s.number).append(",\"w\":").append(s.width).append(",\"h\":").append(s.height)
    b.append(",\"mask\":\"")
    for (m in s.mask) b.append(if (m) '1' else '0')
    b.append("\",\"cells\":[")
    s.cells.forEachIndexed { i, c ->
        if (i > 0) b.append(',')
        if (c == null) b.append("null") else b.append('[').append(c.id).append(',').append(c.color).append(',').append(c.kind.ordinal).append(',').append(c.param).append(']')
    }
    b.append("],\"tray\":[")
    s.tray.forEachIndexed { i, col ->
        if (i > 0) b.append(',')
        b.append('[')
        col.forEachIndexed { j, cup -> if (j > 0) b.append(','); b.append(cup.color + if (cup.hidden) 100 else 0) }
        b.append(']')
    }
    b.append("],\"cap\":").append(s.capacity).append(",\"theme\":").append(s.theme).append(",\"colors\":").append(s.colorCount)
    b.append(",\"boss\":").append(s.isBoss).append(",\"plan\":[")
    s.plan.forEachIndexed { i, id -> if (i > 0) b.append(','); b.append(id) }
    b.append("],\"intro\":").append(if (s.introduces == null) "null" else "\"" + s.introduces!!.name + "\"").append('}')
    return b.toString()
}

class Hasher {
    var h = -3750763034362895579L // 0xcbf29ce484222325
    fun i(v: Int) { h = (h xor (v.toLong() and 0xffffffffL)) * 1099511628211L }
    fun f(v: Float) = i(v.toRawBits())
    fun b(v: Boolean) = i(if (v) 1 else 0)
}

fun hashState(e: GameEngine): Long {
    val x = Hasher()
    x.i(e.status.ordinal); x.i(e.failReason.ordinal); x.f(e.time); x.f(e.introT); x.b(e.inIntro)
    x.f(e.beltOffset); x.f(e.beltVel); x.i(e.beltCount); x.i(e.peakBelt); x.i(e.capacity); x.f(e.spacing)
    x.i(e.combo); x.i(e.maxCombo); x.i(e.comboCoins); x.i(e.cupsFilled); x.i(e.marblesSorted); x.i(e.boostersUsed)
    x.b(e.continued); x.f(e.shake); x.b(e.danger); x.f(e.dangerLevel); x.i(e.stars); x.i(e.coinReward()); x.b(e.isBusy)
    val hint = e.hintTarget()
    if (hint == null) x.i(-7) else { x.f(hint[0]); x.f(hint[1]) }
    val bd = e.board
    x.i(bd.pops); x.i(bd.moves); x.i(bd.cupsDone); x.i(bd.bombBonus)
    for (c in bd.cells) if (c == null) x.i(-1) else { x.i(c.id); x.b(c.cracked); x.b(c.revealed) }
    for (v in bd.exposed) x.b(v)
    x.i(bd.openLocks.size); for (v in bd.openLocks.sorted()) x.i(v)
    x.i(bd.paintedBuckets.size); for (v in bd.paintedBuckets.sorted()) x.i(v)
    x.i(e.marbles.size)
    for (m in e.marbles) {
        x.i(m.state.ordinal); x.i(m.color); x.f(m.x); x.f(m.y); x.f(m.px); x.f(m.py); x.i(m.channel); x.i(m.slot)
        x.f(m.angle); x.f(m.t); x.f(m.dur); x.f(m.sx); x.f(m.sy); x.i(m.targetCol); x.i(m.targetDimple)
        x.f(m.prevX); x.f(m.squash); x.f(m.age); x.f(m.stuckT); x.i(m.wp?.size ?: -1); x.i(m.wpi); x.f(m.wait)
    }
    x.i(e.slots.size)
    for (s in e.slots) x.i(if (s == null) -1 else e.marbles.indexOf(s))
    for (col in e.tray) {
        x.i(col.cups.size)
        for (c in col.cups) {
            x.i(c.color); x.b(c.hidden); x.i(c.reserved); x.i(c.arrived); x.f(c.display); x.b(c.popping); x.f(c.popT)
            x.f(c.bounce); x.f(c.vel); x.f(c.reveal); x.b(c.revealing); x.f(c.shuffleT)
        }
    }
    for (v in e.visuals) {
        if (v == null) { x.i(-1); continue }
        x.i(v.index); x.f(v.dropY); x.f(v.dropVel); x.f(v.delay); x.f(v.squash); x.f(v.shake); x.f(v.flash); x.f(v.reveal)
        x.f(v.crack); x.f(v.unlock); x.b(v.wasLocked); x.f(v.pulse); x.f(v.paint); x.f(v.open); x.b(v.wasOpen); x.f(v.wake)
    }
    x.i(e.exiting.size)
    for (b in e.exiting) { x.f(b.t); x.f(b.x); x.f(b.y); x.f(b.cell); x.i(b.state.id) }
    x.i(e.flying.size)
    for (f in e.flying) { x.f(f.t); x.f(f.x); x.f(f.y); x.f(f.rot); x.f(f.scale); x.f(f.mx); x.f(f.my); x.f(f.tx); x.f(f.ty); x.i(f.state.id) }
    x.i(e.texts.size)
    for (t in e.texts) { x.i(t.text.hashCode()); x.f(t.x); x.f(t.y); x.f(t.life); x.i(t.color); x.f(t.size) }
    val p = e.particles
    x.i(p.count)
    for (k in 0 until p.count) {
        x.f(p.x[k]); x.f(p.y[k]); x.f(p.vx[k]); x.f(p.vy[k]); x.f(p.life[k]); x.f(p.maxLife[k]); x.f(p.size[k])
        x.f(p.rot[k]); x.f(p.vrot[k]); x.f(p.grav[k]); x.i(p.color[k]); x.i(p.type[k])
    }
    return x.h
}

class Recorder : GameListener {
    var frame = 0
    val events = ArrayList<String>()
    override fun sound(sfx: Sfx, pitch: Float, volume: Float) { events += "$frame S ${sfx.name} ${pitch.toRawBits()} ${volume.toRawBits()}" }
    override fun haptic(kind: Haptic) { events += "$frame H ${kind.name}" }
    override fun combo(count: Int) { events += "$frame C $count" }
    override fun statusChanged(status: GameStatus) { events += "$frame T ${status.name}" }
}

class TraceDef(val name: String, val level: Int, val seed: Long, val frames: Int, val policy: Int, val tapEvery: Int, val boosters: Boolean)

val TRACES = listOf(
    TraceDef("L1_plan", 1, 11L, 2400, 0, 20, false),
    TraceDef("L8_plan", 8, 12L, 3600, 0, 15, false),
    TraceDef("L15_any", 15, 13L, 3600, 1, 9, false),
    TraceDef("L20_arrow", 20, 14L, 3600, 1, 7, false),
    TraceDef("L30_jam", 30, 15L, 4000, 1, 3, false),
    TraceDef("L40_ice_boosters", 40, 16L, 3600, 0, 12, true),
    TraceDef("L55_rainbow", 55, 19L, 3600, 0, 10, false),
    TraceDef("L70_bomb", 70, 17L, 3600, 1, 10, false),
    TraceDef("L90_paint", 90, 20L, 3600, 1, 8, false),
    TraceDef("L120_switch_boosters", 120, 18L, 4000, 0, 8, true),
    TraceDef("L77_jam_continue", 77, 21L, 4000, 2, 5, false),
    TraceDef("L80_bomb_continue", 80, 22L, 4000, 3, 5, false),
    TraceDef("L130_nomoves_continue", 130, 7L, 4000, 2, 5, false),
    TraceDef("L3000_bomb_boosters", 3000, 24L, 4000, 2, 5, true),
    TraceDef("L4000_jam", 4000, 25L, 4000, 1, 5, false),
)

fun tapCell(e: GameEngine, i: Int) {
    val c = i % e.spec.width; val r = i / e.spec.width
    e.tap(e.layout.cellCenterX(c), e.layout.cellCenterY(r.toFloat()))
}

fun runTrace(d: TraceDef): String {
    Random.rng = kotlin.random.Random(d.seed)
    val spec = LevelGenerator.generate(d.level)
    val layout = GameLayout(1560f, 210f, 8f, spec)
    val rec = Recorder()
    val e = GameEngine(spec, layout, rec)
    var planIdx = 0
    var continues = 0
    val hashes = ArrayList<Long>()
    for (f in 1..d.frames) {
        rec.frame = f
        val dt = if (f % 7 == 3) 0.05f else if (f % 11 == 5) 0.004f else 1f / 60f
        e.update(dt)
        if (e.status == GameStatus.FAILED && continues < 2 && f % 30 == 0) { e.continueGame(); continues++; rec.events += "$f K ${e.failReason.name}" }
        if (e.status == GameStatus.PLAYING && !e.inIntro) {
            if (f % d.tapEvery == 0) {
                if (d.policy == 0) {
                    while (planIdx < spec.plan.size) {
                        val i = e.board.locate(spec.plan[planIdx])
                        if (i < 0) { planIdx++; continue }
                        if (e.board.canTap(i)) { tapCell(e, i); planIdx++ }
                        break
                    }
                } else {
                    // 1: first tappable cell, 2: last tappable cell, 3: first tappable non-bomb cell; else poke a blocked one
                    var pick = -1
                    val n = e.board.cells.size
                    for (k in 0 until n) {
                        val i = if (d.policy == 2) n - 1 - k else k
                        if (!e.board.canTap(i)) continue
                        if (d.policy == 3 && e.board.cells[i]!!.spec.kind == BlockKind.BOMB) continue
                        pick = i; break
                    }
                    if (pick < 0) for (i in 0 until n) if (e.board.cells[i] != null) { pick = i; break }
                    if (pick >= 0) tapCell(e, pick)
                }
            }
            if (d.boosters) {
                when (f) {
                    150, 330 -> {
                        // hammer the top-most block (usually locked / without a path → it flies to the hopper)
                        var done = false
                        for (k in e.visuals.indices.reversed()) {
                            val v = e.visuals[k] ?: continue
                            done = e.hammer(layout.cellCenterX(v.col), layout.cellCenterY(v.row.toFloat())); break
                        }
                        rec.events += "$f B hammer $done"
                    }
                    200 -> { e.boosterSlots(); rec.events += "$f B slots" }
                    260, 520 -> rec.events += "$f B magnet ${e.magnet()}"
                    280, 600 -> rec.events += "$f B shuffle ${e.boosterShuffle()}"
                }
            }
            if (f % 97 == 0) e.tap(layout.cx, layout.gridTop + 1f)
            if (f % 89 == 0) e.tap(5f, 5f)
        }
        hashes += hashState(e)
    }
    val b = StringBuilder()
    b.append("{\"name\":\"").append(d.name).append("\",\"level\":").append(d.level).append(",\"seed\":").append(d.seed)
        .append(",\"frames\":").append(d.frames).append(",\"policy\":").append(d.policy).append(",\"tapEvery\":").append(d.tapEvery)
        .append(",\"boosters\":").append(d.boosters)
        .append(",\"finalStatus\":\"").append(e.status.name).append("\",\"marblesSorted\":").append(e.marblesSorted)
        .append(",\"hashes\":[")
    hashes.forEachIndexed { i, h -> if (i > 0) b.append(','); b.append('"').append(java.lang.Long.toHexString(h)).append('"') }
    b.append("],\"events\":[")
    rec.events.forEachIndexed { i, s -> if (i > 0) b.append(','); b.append('"').append(s).append('"') }
    b.append("]}")
    System.err.println("trace ${d.name}: status=${e.status} sorted=${e.marblesSorted} events=${rec.events.size} pops=${e.board.pops}")
    return b.toString()
}

fun search() {
    val levels = listOf(70, 72, 75, 77, 80, 95, 100, 130, 150, 177, 200, 297, 500, 777, 1000, 1500, 2000, 2500, 3000, 3500, 4000, 4500, 5000)
    for (lv in levels) for (pol in listOf(1, 2, 3)) for (te in listOf(2, 5)) {
        val d = TraceDef("s", lv, 7L, 4000, pol, te, false)
        val line = runTrace(d)
        val fails = Regex("\"(\\d+) T FAILED\"").findAll(line).count()
        val ks = Regex("\"\\d+ K (\\w+)\"").findAll(line).map { it.groupValues[1] }.toList()
        if (fails > 0) println("level $lv policy $pol tapEvery $te fails=$fails continues=$ks")
    }
}

fun main(args: Array<String>) {
    if (args.getOrNull(0) == "search") { search(); return }
    val out = File(args.getOrElse(0) { "." })
    out.mkdirs()
    val t0 = System.currentTimeMillis()
    File(out, "levels.json").bufferedWriter().use { w ->
        w.write("[\n")
        for (n in 1..LevelGenerator.MAX_LEVEL) {
            w.write(levelLine(LevelGenerator.generate(n)))
            w.write(if (n < LevelGenerator.MAX_LEVEL) ",\n" else "\n")
        }
        w.write("]\n")
    }
    System.err.println("levels: ${System.currentTimeMillis() - t0} ms")
    File(out, "traces.json").bufferedWriter().use { w ->
        w.write("[\n")
        TRACES.forEachIndexed { i, d ->
            w.write(runTrace(d))
            w.write(if (i < TRACES.size - 1) ",\n" else "\n")
        }
        w.write("]\n")
    }
}
