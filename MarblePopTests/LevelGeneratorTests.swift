import XCTest
@testable import MarblePop

/// 1:1 port of app/src/test/.../level/LevelGeneratorTest.kt.
final class LevelGeneratorTests: XCTestCase {

    func testAllLevelsAreSolvableWithinBeltCapacity() {
        var featureCounts: [BlockKind: Int] = [:]
        var minCap = 99, maxCap = 0, maxBlocks = 0
        for n in 1...LevelGenerator.MAX_LEVEL {
            let spec = Golden.levels[n - 1] // == LevelGenerator.generate(n), shared with the golden test
            XCTAssertEqual(spec.number, n)
            let sim = PuzzleSim(spec)
            XCTAssertTrue(sim.board.hasTappable(), "level \(n) has no open block at start")
            for id in spec.plan { XCTAssertTrue(sim.tapId(id), "level \(n): planned tap \(id) illegal") }
            XCTAssertTrue(sim.solved, "level \(n) not solved")
            XCTAssertTrue(sim.peakLoad <= spec.capacity, "level \(n) peak \(sim.peakLoad) > cap \(spec.capacity)")
            // marble / slot balance per colour
            var slots = [Int](repeating: 0, count: MarbleColors.COUNT)
            for cup in spec.tray.joined() { slots[cup.color] += 3 }
            var real = [Int](repeating: 0, count: MarbleColors.COUNT)
            var rainbow = 0
            for b in spec.blocks { if b.kind == .RAINBOW { rainbow += 9 } else { real[b.color] += b.marbleCount } }
            XCTAssertEqual(slots.reduce(0, +), real.reduce(0, +) + rainbow, "level \(n) balance")
            for i in 0..<slots.count { XCTAssertTrue(real[i] <= slots[i], "level \(n) colour \(i)") }
            for b in spec.blocks { featureCounts[b.kind, default: 0] += 1 }
            minCap = min(minCap, spec.capacity); maxCap = max(maxCap, spec.capacity)
            maxBlocks = max(maxBlocks, spec.blockCount)
            if let f = spec.introduces {
                let kinds = Set(spec.blocks.map { $0.kind })
                let ok: Bool
                switch f {
                case .HIDDEN_CUP: ok = spec.tray.joined().contains { $0.hidden }
                case .KEY: ok = kinds.contains(.KEY)
                default: ok = kinds.contains { $0.name == f.name || (f == .COUNTER && $0 == .COUNTER) }
                }
                XCTAssertTrue(ok, "level \(n) should introduce \(f)")
            }
        }
        print("open-at-start check passed")
        print("capacity range \(minCap)..\(maxCap), max blocks \(maxBlocks)")
        print("kinds: \(BlockKind.allCases.compactMap { k in featureCounts[k].map { "\(k)=\($0)" } }.joined(separator: ", "))")
    }

    func testDeterministic() {
        let a = LevelGenerator.generate(1234)
        let b = LevelGenerator.generate(1234)
        XCTAssertEqual(a.plan, b.plan)
        XCTAssertEqual(a.capacity, b.capacity)
    }
}
