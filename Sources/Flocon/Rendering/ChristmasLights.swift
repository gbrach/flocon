import Foundation

enum LightDensity: Int, CaseIterable {
    case sparse, normal, dense
    var title: String { ["Sparse", "Normal", "Dense"][rawValue] }
    /// Approximate pixels between bulbs along the cable.
    var spacing: Float { [54, 36, 22][rawValue] }
}

enum LightColor: Int, CaseIterable {
    case classic, warmWhite
    var title: String { ["Classic", "Warm White"][rawValue] }
    var palette: [SIMD3<Float>] {
        switch self {
        case .classic: [SIMD3(1, 0.19, 0.13), SIMD3(1, 0.72, 0.15), SIMD3(0.18, 0.83, 0.45), SIMD3(0.27, 0.55, 1)]
        case .warmWhite: [SIMD3(1, 0.76, 0.42)]
        }
    }
}

/// The raw value is read by the bulb shader, so keep it in step with Shaders.metal.
enum LightBlink: Int, CaseIterable {
    case steady, slow, fast, twinkle, chase
    var title: String { ["Steady", "Slow", "Fast", "Twinkle", "Chase"][rawValue] }
}

struct LightStyle: Equatable {
    var density = LightDensity.normal
    var color = LightColor.classic
    var blink = LightBlink.steady
    static let standard = LightStyle()
}

/// Display-local geometry. Each bulb carries its blink pattern and string position in `motion.xy`. The cable hangs in swags from the bottom edge of the notch or menu bar, edge to edge.
struct ChristmasLightGeometry {
    let wire: [SIMD2<Float>]
    let bulbs: [Sprite]

    init(width: Float, height: Float, topInset: Float, style: LightStyle = .standard) {
        let anchor = height - max(0, topInset)
        let swags = max(1, Int((width / 240).rounded()))
        let swagWidth = width / Float(swags)
        let steps = 40
        // each swag starts and ends on the bar edge, so the cable is always visibly hung from something
        func point(swag: Int, u: Float) -> SIMD2<Float> {
            SIMD2(Float(swag) * swagWidth + swagWidth * u, anchor - 2 - 14 * sin(u * .pi))
        }
        wire = (0..<swags).flatMap { k in
            ((k == 0 ? 0 : 1)...steps).map { point(swag: k, u: Float($0) / Float(steps)) }
        }
        let colors = style.color.palette
        let perSwag = max(3, Int(swagWidth / style.density.spacing))
        bulbs = (0..<swags * perSwag).map { i in
            let color = colors[i % colors.count]
            let u = (Float(i % perSwag) + 0.5) / Float(perSwag)
            return Sprite(position: point(swag: i / perSwag, u: u) + SIMD2(0, -4), size: 13, alpha: 1, color: SIMD4(color, 1), motion: SIMD4(Float(style.blink.rawValue), Float(i), 2, Float(i) * 0.71))
        }
    }
}
