import Testing
@testable import Flocon

struct RuntimeTests {
    @Test func gpuInstanceLayoutMatchesMetalOnBothArchitectures() {
        #expect(MemoryLayout<Sprite>.stride == 48)
        #expect(MemoryLayout<Sprite>.offset(of: \.color) == 16)
        #expect(MemoryLayout<Sprite>.offset(of: \.motion) == 32)
        #expect(MemoryLayout<SnowVertex>.stride == 32)
        #expect(MemoryLayout<SnowVertex>.offset(of: \.color) == 16)
        #expect(MemoryLayout<FrameUniforms>.stride == 16)
    }
    @Test func supportSnapshotsDoNotDetachSnowWithoutMovement() {
        let s = SnowSimulation(width: 800, height: 600, snowfall: .off, seed: 10)
        let window = WindowSurface(id: 1, frame: .init(x: 100, y: 100, width: 200, height: 200), blockers: [], cornerRadius: 18, cornerExponent: 2, isDock: false)
        s.updateWindows([window], interval: 0.25)
        s.ledges[1]!.deposit(500, at: 200, wide: true)
        s.ledges[1]!.refreshTop()
        let before = s.snowArea
        for _ in 0..<100 { s.updateWindows([window], interval: 0.25) }
        #expect(s.spriteCount == 0)
        #expect(abs(before - s.snowArea) < 0.001)
    }
    @Test func energyPolicyHandlesBatteryHeatAndManualOverride() {
        #expect(PowerBudget.resolve(manual: false, lowPower: false, hot: false, battery: false) == .full)
        #expect(PowerBudget.resolve(manual: false, lowPower: false, hot: false, battery: true) == .battery)
        #expect(PowerBudget.resolve(manual: false, lowPower: true, hot: false, battery: false) == .saver)
        #expect(PowerBudget.resolve(manual: false, lowPower: false, hot: true, battery: true) == .saver)
        #expect(PowerBudget.resolve(manual: true, lowPower: false, hot: false, battery: false) == .saver)
    }
}
