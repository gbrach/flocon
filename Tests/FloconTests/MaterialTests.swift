import CoreGraphics
import Testing
@testable import Flocon

struct MaterialTests {
    func layer() -> SnowLayer {
        SnowLayer(origin: .zero, columns: 100, columnWidth: 2, depth: 40, opensAtEdges: false)
    }
    @Test func compactionLowersDriftWithoutRemovingMass() {
        let snow = layer()
        for i in 0..<100 { snow.set(i, 12) }
        snow.refreshTop()
        let mass = snow.area
        #expect(snow.compact(dt: 240))
        #expect(snow.top < 12 && snow.top > 8)
        #expect(snow.cohesion > 0.5)
        #expect(abs(snow.area - mass) < 0.01)
    }
    @Test func freshPowderSoftensPackedSnow() {
        let snow = layer()
        snow.set(50, 10); snow.refreshTop()
        _ = snow.compact(dt: 300)
        let packing = snow.packing[50], mass = snow.area
        snow.deposit(20, at: snow.centerX(50), wide: false)
        #expect(snow.packing[50] < packing)
        #expect(abs(snow.area - mass - 20) < 0.01)
    }
    @Test func transportingMixedDensitiesConservesMass() {
        let snow = layer()
        snow.set(45, 90); snow.refreshTop()
        _ = snow.compact(dt: 300)
        snow.deposit(120, at: snow.centerX(48), wide: true)
        let mass = snow.area
        for _ in 0..<150 { _ = snow.relax(repose: 0.8) }
        #expect(abs(snow.area - mass) < 0.03)
        #expect(snow.heights.allSatisfy { $0.isFinite && $0 >= 0 })
        #expect(snow.packing.allSatisfy { $0 >= 0 && $0 <= 1 })
    }
    @Test func removingCompactedSnowReturnsItsMass() {
        let snow = layer()
        snow.set(50, 12); snow.refreshTop()
        _ = snow.compact(dt: 300)
        let mass = snow.area
        let removed = snow.removeHeight(2, at: 50)
        #expect(removed > 4)
        #expect(abs(snow.area + removed - mass) < 0.01)
    }
    @Test func packedWindowDriftBreaksIntoPatchesAndLands() {
        let simulation = SnowSimulation(width: 1000, height: 800, snowfall: .off, seed: 54)
        let window = WindowSurface(id: 1, frame: CGRect(x: 200, y: 300, width: 300, height: 200), blockers: [], cornerRadius: 18, cornerExponent: 2, isDock: false)
        simulation.updateWindows([window], interval: 1 / 60)
        let snow = simulation.ledges[1]!
        for i in 15..<135 { snow.set(i, 10) }
        snow.refreshTop(); _ = snow.compact(dt: 180)
        let mass = simulation.snowArea
        simulation.updateWindows([], interval: 1 / 60)
        #expect(simulation.spriteCount > 0 && simulation.spriteCount < 120)
        #expect(abs(simulation.snowArea - mass) < 0.1)
        for _ in 0..<600 { _ = simulation.step(dt: 1 / 60, cursor: SIMD2(-10000, -10000)) }
        #expect(simulation.ground.area > mass * 0.8)
        #expect(abs(simulation.snowArea + simulation.escapedArea - mass) < 0.5)
    }
    @Test func packedCellsKeepMassWhenSlidingOffAnEdge() {
        let snow = layer()
        snow.set(99, 12); snow.refreshTop(); _ = snow.compact(dt: 300)
        let mass = snow.area
        let dropped = snow.slideColumn(toward: 1)
        #expect(dropped.mass > dropped.height * snow.columnWidth)
        #expect(abs(snow.area + dropped.mass - mass) < 0.01)
    }
}
