import Testing
@testable import Flocon

struct AccumulationTests {
    func layer(open: Bool = false) -> SnowLayer {
        SnowLayer(origin: .zero, columns: 100, columnWidth: 2, depth: 40, opensAtEdges: open)
    }
    @Test func depositionConservesMassIncludingClosedBoundary() {
        let l = layer()
        for x: Float in [0, 1, 50, 199, 200] {
            let before = l.area
            #expect(l.deposit(37, at: x, wide: true) == 0)
            #expect(abs(l.area - before - 37) < 0.001)
        }
    }
    @Test func openEdgeReturnsUnplacedMass() {
        let l = layer(open: true)
        let missed = l.deposit(100, at: 0, wide: true)
        #expect(missed > 0)
        #expect(abs(l.area + missed - 100) < 0.001)
    }
    @Test func avalancheReducesSlopeWithoutLosingMass() {
        let l = layer()
        l.set(50, 90)
        l.refreshTop()
        let before = l.area
        for _ in 0..<100 { _ = l.relax(repose: 0.8); l.refreshTop() }
        #expect(l.heights[50] < 20)
        #expect(abs(l.area - before) < 0.005)
        for i in 0..<99 { #expect(abs(l.heights[i] - l.heights[i + 1]) <= 1.63) }
        #expect(l.heights.allSatisfy { $0 >= 0 && $0.isFinite })
    }
    @Test func cornersSpillAndAccountForSnow() {
        let l = layer(open: true)
        l.shapeCorners(radius: 18, exponent: 2.5)
        #expect(l.bed[0] < 0)
        #expect(l.bed[50] == 0)
        for i in 0..<100 { l.set(i, 10) }
        l.refreshTop()
        let before = l.area
        for _ in 0..<80 { _ = l.relax(repose: 0.8); l.refreshTop() }
        #expect(l.spill.left > 0 && l.spill.right > 0)
        #expect(abs(l.area - before) < 0.02)
    }
    @Test func meltingIsMonotonicAndClamped() {
        let l = layer()
        l.set(50, 20); l.refreshTop()
        let before = l.area
        _ = l.thaw(dt: 1, down: 4, rate: 0.02, settle: 30)
        #expect(l.area < before && l.area > 0)
        _ = l.thaw(dt: 10000, down: 0, rate: 1, settle: 1)
        #expect(l.area == 0)
    }
    @Test func unsupportedSlideReturnsExactMass() {
        let l = layer(open: true)
        l.set(99, 8)
        let before = l.area
        let dropped = l.slideColumn(toward: 1)
        #expect(abs(l.area + dropped.height * l.columnWidth - before) < 0.001)
    }
}
