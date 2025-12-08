import Foundation

/// Display-local geometry. The cable hangs in swags from the bottom edge of the notch or menu bar, edge to edge.
struct ChristmasLightGeometry {
    let wire: [SIMD2<Float>]
    let bulbs: [Sprite]

    init(width: Float, height: Float, topInset: Float) {
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
        let colors: [SIMD3<Float>] = [SIMD3(1, 0.19, 0.13), SIMD3(1, 0.72, 0.15), SIMD3(0.18, 0.83, 0.45), SIMD3(0.27, 0.55, 1)]
        let perSwag = max(3, Int(swagWidth / 36))
        bulbs = (0..<swags * perSwag).map { i in
            let color = colors[i % colors.count]
            let u = (Float(i % perSwag) + 0.5) / Float(perSwag)
            return Sprite(position: point(swag: i / perSwag, u: u) + SIMD2(0, -4), size: 13, alpha: 1, color: SIMD4(color, 1), motion: SIMD4(0, 0, 2, Float(i) * 0.71))
        }
    }
}
