import Testing
@testable import Flocon

struct ParticleTests {
    private let away = SIMD2<Float>(-10_000, -10_000)

    @Test func testSeededParticlesMoveDownAndRemainFinite() {
        let simulation = SnowSimulation(width: 1200, height: 800, snowfall: .moderate, seed: 42)
        _ = simulation.step(dt: 1 / 60, cursor: away)
        let buffer = UnsafeMutablePointer<Sprite>.allocate(capacity: 1000)
        defer { buffer.deallocate() }
        let count = simulation.writeSprites(into: buffer, capacity: 1000)
        #expect(count > 0)
        let index = (0..<count).first { buffer[$0].position.y > 50 }!
        let initial = buffer[index].position
        _ = simulation.step(dt: 1 / 60, cursor: away)
        #expect(simulation.writeSprites(into: buffer, capacity: 1000) == count)
        #expect(buffer[index].position.y < initial.y)
        for i in 0..<count {
            #expect(buffer[i].position.x.isFinite && buffer[i].position.y.isFinite)
        }
    }

    @Test func testSeedReproducesTrajectory() {
        let a = SnowSimulation(width: 1000, height: 800, snowfall: .variable, seed: 91)
        let b = SnowSimulation(width: 1000, height: 800, snowfall: .variable, seed: 91)
        let buffers = (UnsafeMutablePointer<Sprite>.allocate(capacity: 2000), UnsafeMutablePointer<Sprite>.allocate(capacity: 2000))
        defer { buffers.0.deallocate(); buffers.1.deallocate() }
        for _ in 0..<600 {
            _ = a.step(dt: 1 / 60, cursor: away)
            _ = b.step(dt: 1 / 60, cursor: away)
        }
        let count = a.writeSprites(into: buffers.0, capacity: 2000)
        #expect(count == b.writeSprites(into: buffers.1, capacity: 2000))
        for i in 0..<count { #expect(buffers.0[i].position == buffers.1[i].position) }
    }

    @Test func testOffSpawnsNothingAndInvalidTimeIsIgnored() {
        let simulation = SnowSimulation(width: 1000, height: 800, snowfall: .off, seed: 1)
        #expect(!simulation.step(dt: 0, cursor: away))
        #expect(!simulation.step(dt: .nan, cursor: away))
        for _ in 0..<120 { _ = simulation.step(dt: 1 / 60, cursor: away) }
        #expect(simulation.spriteCount == 0)
    }
}
