import Foundation

/// Shared CPU/GPU instance data: two float4s and one float4 color keep alignment explicit on both architectures.
struct Sprite {
    var position: SIMD2<Float>
    var size: Float
    var alpha: Float
    var color = SIMD4<Float>(1, 1, 1, 1)
    var motion = SIMD4<Float>.zero // velocity xy, material (0 snow, 1 clump, 2 bulb), phase
}

struct SnowParticle {
    var position: SIMD2<Float>
    var velocity: SIMD2<Float>
    var radius: Float
    var opacity: Float
    var phase: Float
    var terminalSpeed: Float
    var area: Float // zero for incoming flakes; positive for detached, conserved snow
    var clump: Bool = false
    var age: Float = 0
    var fractureAge: Float = .infinity
    var spin: Float = 0
}

struct SnowRandom {
    var state: UInt64
    mutating func unit() -> Float {
        state &+= 0x9e3779b97f4a7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        z ^= z >> 31
        return Float(z >> 40) / 16_777_216
    }
    mutating func between(_ a: Float, _ b: Float) -> Float { a + (b - a) * unit() }
}
