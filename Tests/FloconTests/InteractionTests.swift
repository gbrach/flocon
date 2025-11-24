import CoreGraphics
import Testing
@testable import Flocon

struct InteractionTests {
    private let away = SIMD2<Float>(-10_000, -10_000)
    func surface(x: CGFloat = 200, top: CGFloat = 500, blockers: [CGRect] = []) -> WindowSurface {
        WindowSurface(id: 7, frame: CGRect(x: x, y: top - 200, width: 300, height: 200), blockers: blockers, cornerRadius: 18, cornerExponent: 2.5, isDock: false)
    }
    func loaded() -> SnowSimulation {
        let s = SnowSimulation(width: 1000, height: 800, snowfall: .off, seed: 18)
        s.updateWindows([surface()], interval: 1 / 60)
        let ledge = s.ledges[7]!
        for i in 15..<135 { ledge.set(i, 8) }
        ledge.refreshTop()
        return s
    }
    @Test func closedWindowDetachesAndLandsWithoutLosingMass() {
        let s = loaded()
        let before = s.snowArea
        s.updateWindows([], interval: 1 / 60)
        #expect(s.ledges.isEmpty)
        #expect(s.spriteCount > 0)
        #expect(abs(s.snowArea - before) < 0.1)
        for _ in 0..<600 { _ = s.step(dt: 1 / 60, cursor: away) }
        #expect(s.ground.area > 0)
        #expect(abs(s.snowArea + s.escapedArea - before) < 0.5)
    }
    @Test func gentleWindowMotionCarriesSnow() {
        let s = loaded()
        let before = s.snowArea
        for frame in 1...60 {
            s.updateWindows([surface(x: 200 + CGFloat(frame) * 0.2)], interval: 1 / 60)
            _ = s.step(dt: 1 / 60, cursor: away)
        }
        #expect(s.ledges[7]!.origin.x == 212)
        #expect(s.ledges[7]!.area > before * 0.9)
        #expect(abs(s.snowArea + s.escapedArea - before) < 0.2)
    }
    @Test func abruptWindowDropDetachesSnow() {
        let s = loaded()
        for frame in 1...12 {
            s.updateWindows([surface(top: 500 - CGFloat(frame) * 20)], interval: 1 / 60)
            _ = s.step(dt: 1 / 60, cursor: away)
        }
        #expect(s.spriteCount > 0)
        #expect(s.ledges[7]!.area < 1900)
    }
    @Test func cursorDisplacesSnowAndPreservesArea() {
        let s = loaded()
        let before = s.snowArea
        for x in stride(from: Float(190), through: 500, by: 4) {
            _ = s.step(dt: 1 / 60, cursor: SIMD2(x, 514))
        }
        #expect(s.spriteCount > 0)
        #expect(abs(s.snowArea + s.escapedArea - before) < 0.5)
    }
    @Test func interactionsCanBeDisabled() {
        let s = loaded()
        s.interactions = false
        for x in stride(from: Float(190), through: 500, by: 4) {
            _ = s.step(dt: 1 / 60, cursor: SIMD2(x, 514))
        }
        #expect(s.spriteCount == 0)
    }
    @Test func spaceSwitchRetainsAndRestoresWindowSnow() {
        let s = loaded()
        let before = s.snowArea
        s.spaceChanged()
        s.updateWindows([], interval: 1 / 60, parked: [7], elsewhere: [7])
        for _ in 0..<120 { _ = s.step(dt: 1 / 60, cursor: away) }
        #expect(s.spriteCount == 0)
        #expect(abs(s.snowArea - before) < 0.01)
        s.updateWindows([surface()], interval: 1 / 60)
        #expect(abs(s.ledges[7]!.area - before) < 0.01)
    }
    @Test func occludedColumnsCannotCollectSnow() {
        let s = SnowSimulation(width: 1000, height: 800, snowfall: .off, seed: 1)
        s.updateWindows([surface(blockers: [CGRect(x: 200, y: 400, width: 150, height: 200)])], interval: 1 / 60)
        let ledge = s.ledges[7]!
        #expect(!ledge.visible[20])
        #expect(ledge.visible[100])
    }
    @Test func dormantCacheEvictsAllExcessWindowsAndAccountsForMass() {
        let s = SnowSimulation(width: 1000, height: 800, snowfall: .off, seed: 8)
        let surfaces = (1...250).map { id in
            WindowSurface(id: CGWindowID(id), frame: CGRect(x: 50, y: 100, width: 80, height: 200), blockers: [], cornerRadius: 18, cornerExponent: 2.5, isDock: false)
        }
        s.updateWindows(surfaces, interval: 1 / 60)
        for ledge in s.ledges.values { ledge.set(20, 1); ledge.refreshTop() }
        let before = s.snowArea
        let ids = Set(surfaces.map(\.id))
        s.updateWindows([], interval: 1 / 60, parked: ids, elsewhere: ids)
        #expect(abs(s.snowArea - 400) < 0.01)
        #expect(abs(s.snowArea + s.escapedArea - before) < 0.01)
    }
    @Test func restoringSmallerDormantWindowAccountsForRemovedSnow() {
        let s = loaded()
        let before = s.snowArea
        s.updateWindows([], interval: 1 / 60, parked: [7], elsewhere: [7])
        let small = WindowSurface(id: 7, frame: CGRect(x: 200, y: 300, width: 100, height: 200), blockers: [], cornerRadius: 18, cornerExponent: 2.5, isDock: false)
        s.updateWindows([small], interval: 1 / 60)
        #expect(s.escapedArea > 0)
        #expect(abs(s.snowArea + s.escapedArea - before) < 0.01)
    }

}
