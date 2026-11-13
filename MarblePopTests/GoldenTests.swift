import XCTest
import GameKit
@testable import MarblePop

/// Bit-exact parity with Android: data dumped from the JVM by `Golden/source/GoldenDump.kt`.
final class GoldenTests: XCTestCase {

    /// Every level 1...5000: the complete definition (shape, blocks with kind/param, tray cups incl. hidden ones,
    /// capacity, theme, colours, boss flag, plan, introduced feature) equals the JVM output.
    func testAllLevelsMatchAndroid() {
        var lines = Golden.text("levels").split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.first, "[")
        XCTAssertEqual(lines.last, "]")
        lines = Array(lines.dropFirst().dropLast())
        XCTAssertEqual(lines.count, LevelGenerator.MAX_LEVEL)
        var mismatches = 0
        for (i, raw) in lines.enumerated() {
            let want = raw.hasSuffix(",") ? String(raw.dropLast()) : raw
            let got = Golden.levelLine(Golden.levels[i])
            if got != want {
                mismatches += 1
                if mismatches <= 5 { XCTFail("level \(i + 1) differs\n android: \(want)\n     ios: \(got)") }
            }
        }
        XCTAssertEqual(mismatches, 0, "\(mismatches) of \(lines.count) levels differ from Android")
    }

    /// `LevelGenerator.get` (cached) returns the same levels as `generate`.
    func testGetMatchesGenerate() {
        for n in [1, 2, 30, 31, 50, 120, 4999, 5000] {
            XCTAssertEqual(Golden.levelLine(LevelGenerator.get(n)), Golden.levelLine(Golden.levels[n - 1]))
        }
        XCTAssertEqual(LevelGenerator.get(0).number, 1)
        XCTAssertEqual(LevelGenerator.get(99999).number, LevelGenerator.MAX_LEVEL)
        XCTAssertTrue(LevelGenerator.get(7) === LevelGenerator.get(7))
    }

    /// Deterministic GameEngine runs (seeded engine RNG, scripted taps, boosters, fails + revives): the full engine
    /// state hash after every frame and every listener event equal the JVM run.
    func testSimulationTracesMatchAndroid() throws {
        let data = try Data(contentsOf: Golden.url("traces"))
        let traces = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertGreaterThanOrEqual(traces.count, 15)
        for t in traces {
            let name = t["name"] as! String
            let r = Golden.runTrace(level: t["level"] as! Int, seed: Int64(t["seed"] as! Int), frames: t["frames"] as! Int,
                                    policy: t["policy"] as! Int, tapEvery: t["tapEvery"] as! Int, boosters: t["boosters"] as! Bool)
            let hashes = t["hashes"] as! [String]
            let events = t["events"] as! [String]
            XCTAssertEqual(r.hashes.count, hashes.count, name)
            if let k = zip(r.hashes, hashes).enumerated().first(where: { $0.element.0 != $0.element.1 })?.offset {
                let frame = k + 1
                let near = r.events.filter { (Int($0.split(separator: " ")[0]) ?? 0) <= frame }.suffix(4)
                let nearA = events.filter { (Int($0.split(separator: " ")[0]) ?? 0) <= frame }.suffix(4)
                XCTFail("\(name): engine state differs from frame \(frame)\n ios events: \(Array(near))\n android:    \(Array(nearA))")
            }
            if let k = zip(r.events, events).enumerated().first(where: { $0.element.0 != $0.element.1 })?.offset {
                XCTFail("\(name): event \(k) differs — ios \(r.events[k]) vs android \(events[k])")
            }
            XCTAssertEqual(r.events.count, events.count, name)
            XCTAssertEqual(r.finalStatus, t["finalStatus"] as? String, name)
            XCTAssertEqual(r.marblesSorted, t["marblesSorted"] as? Int, name)
        }
    }
}
