import Foundation

/// Cell mass is conserved independently of height. Packing turns loose powder into denser snow.
final class SnowLayer {
    let columnWidth: Float
    let opensAtEdges: Bool
    var origin: SIMD2<Float>
    private(set) var heights: [Float]
    private(set) var packing: [Float]
    private var loads: [Float]
    private(set) var bed: [Float]
    private(set) var visible: [Bool]
    private(set) var top: Float = 0
    var isDock = false
    var occluders: [SIMD4<Float>] = []
    var velocity = SIMD2<Float>.zero
    var spill: (left: Float, right: Float) = (0, 0)
    private var flux: [Float]
    private var packedFlux: [Float]
    private var radius: Float = 0
    private var cornerExponent: Float = 2
    let depth: Float

    init(origin: SIMD2<Float>, columns: Int, columnWidth: Float, depth: Float, opensAtEdges: Bool) {
        self.origin = origin
        self.columnWidth = columnWidth
        self.depth = depth
        self.opensAtEdges = opensAtEdges
        let n = max(2, columns)
        heights = Array(repeating: 0, count: n)
        loads = heights; packing = heights; bed = heights; flux = heights; packedFlux = heights
        visible = Array(repeating: true, count: n)
    }
    var count: Int { heights.count }
    var width: Float { Float(count) * columnWidth }
    /// Snow mass expressed as the area it would occupy at fresh-powder density.
    var area: Float { loads.reduce(0, +) * columnWidth + spill.left + spill.right }
    var base: SIMD2<Float> { origin }
    var cohesion: Float {
        var mass: Float = 0, packed: Float = 0
        for i in loads.indices { mass += loads[i]; packed += loads[i] * packing[i] }
        return mass > 0 ? packed / mass : 0
    }
    private func density(_ i: Int) -> Float { 1 + 0.45 * packing[i] }
    private func updateHeight(_ i: Int) { heights[i] = loads[i] / density(i) }
    func centerX(_ i: Int) -> Float { origin.x + (Float(i) + 0.5) * columnWidth }
    func floor(_ i: Int) -> Float { origin.y + bed[i] }
    func surface(_ i: Int) -> Float { floor(i) + heights[i] }
    func index(at x: Float) -> Int? {
        let i = Int(Foundation.floor((x - origin.x) / columnWidth))
        return heights.indices.contains(i) ? i : nil
    }
    func set(_ i: Int, _ height: Float) {
        loads[i] = (height.isFinite ? max(0, height) : 0) * density(i)
        updateHeight(i)
    }
    @discardableResult func removeHeight(_ height: Float, at i: Int) -> Float {
        let removed = min(heights[i], max(0, height)) * density(i)
        loads[i] = max(0, loads[i] - removed)
        updateHeight(i)
        return removed * columnWidth
    }
    @discardableResult func removeFraction(_ fraction: Float, at i: Int) -> Float {
        let mass = loads[i] * min(1, max(0, fraction))
        loads[i] -= mass
        updateHeight(i)
        return mass * columnWidth
    }
    func refreshTop() { top = heights.max() ?? 0 }
    func resize(columns: Int) {
        let n = max(2, columns), old = count
        guard n != old else { return }
        func resized(_ values: [Float]) -> [Float] { Array(values.prefix(n)) + Array(repeating: 0, count: max(0, n - old)) }
        heights = resized(heights); loads = resized(loads); packing = resized(packing)
        visible = Array(repeating: true, count: n)
        flux = Array(repeating: 0, count: n); packedFlux = flux
        shapeCorners(radius: radius, exponent: cornerExponent)
        refreshTop()
    }
    func shapeCorners(radius: Float, exponent: Float) {
        self.radius = max(0, min(radius, width / 2)); cornerExponent = exponent
        bed = heights.indices.map { i in
            let edge = min((Float(i) + 0.5) * columnWidth, width - (Float(i) + 0.5) * columnWidth)
            let t = self.radius > 0 ? max(0, 1 - edge / self.radius) : 0
            return -self.radius * pow(t, max(1, exponent)) * (0.75 + 0.25 * t)
        }
    }
    func updateVisibility(screenWidth: Float, blockers: [SIMD4<Float>]) {
        for i in heights.indices {
            let p = SIMD2(centerX(i), floor(i) + 1)
            visible[i] = p.x >= 0 && p.x < screenWidth && !blockers.contains { p.x >= $0.x && p.x < $0.z && p.y >= $0.y && p.y < $0.w }
        }
    }
    private func addPowder(_ mass: Float, at i: Int) {
        let old = loads[i]
        loads[i] += mass
        packing[i] = loads[i] > 0 ? packing[i] * old / loads[i] : 0
        updateHeight(i)
    }
    @discardableResult func deposit(_ area: Float, at x: Float, wide: Bool) -> Float {
        guard area > 0, area.isFinite else { return 0 }
        let center = Int(Foundation.floor((x - origin.x) / columnWidth))
        let reach = wide ? 2 : 1
        let normalization = Float((reach + 1) * (reach + 1))
        var outside: Float = 0
        for offset in -reach...reach {
            let share = area * Float(reach + 1 - abs(offset)) / normalization
            let i = center + offset
            if heights.indices.contains(i) { addPowder(share / columnWidth, at: i) }
            else if opensAtEdges { outside += share }
            else { addPowder(share / columnWidth, at: min(max(i, 0), count - 1)) }
        }
        return outside
    }
    @discardableResult func compact(dt: Float) -> Bool {
        guard dt.isFinite, dt > 0 else { return false }
        var movement: Float = 0
        for i in loads.indices where loads[i] > 0 {
            let oldHeight = heights[i]
            let pressure = 0.3 + min(1, loads[i] / depth)
            packing[i] += (1 - packing[i]) * (1 - exp(-dt * pressure / 90))
            updateHeight(i)
            movement = max(movement, oldHeight - heights[i])
        }
        refreshTop()
        return movement > 0.001
    }
    @discardableResult func relax(repose: Float) -> Bool {
        guard top > 0 else { return false }
        var changed = false
        for _ in 0..<12 {
            var largest: Float = 0
            for i in 0..<(count - 1) {
                let limit = max(0.05, repose * columnWidth * (1 + 0.4 * min(packing[i], packing[i + 1])))
                let difference = surface(i) - surface(i + 1)
                let excess = difference - min(limit, max(-limit, difference))
                let mass = excess * 0.48 / (1 / density(i) + 1 / density(i + 1))
                flux[i] = mass > 0 ? min(mass, loads[i] * 0.24) : max(mass, -loads[i + 1] * 0.24)
                packedFlux[i] = flux[i] * (flux[i] >= 0 ? packing[i] : packing[i + 1])
                largest = max(largest, abs(flux[i]))
                changed = changed || abs(flux[i]) > 0.001
            }
            for i in loads.indices {
                let packed = loads[i] * packing[i] + (i > 0 ? packedFlux[i - 1] : 0) - (i < count - 1 ? packedFlux[i] : 0)
                loads[i] = max(0, loads[i] + (i > 0 ? flux[i - 1] : 0) - (i < count - 1 ? flux[i] : 0))
                packing[i] = loads[i] > 0 ? min(1, max(0, packed / loads[i])) : 0
                updateHeight(i)
            }
            if opensAtEdges {
                let limit = max(0.05, repose * columnWidth)
                let left = removeHeight(max(0, heights[0] - limit) * 0.24, at: 0)
                let right = removeHeight(max(0, heights[count - 1] - limit) * 0.24, at: count - 1)
                spill.left += left; spill.right += right
                largest = max(largest, (left + right) / columnWidth)
                changed = changed || left + right > 0.001
            }
            if largest < 0.0001 { break }
        }
        refreshTop()
        return changed
    }
    @discardableResult func thaw(dt: Float, down floor: Float, rate: Float, settle: Float) -> Bool {
        guard dt > 0 else { return false }
        var removed: Float = 0
        for i in heights.indices {
            removed += removeHeight(dt * (rate + max(0, heights[i] - floor) / max(settle, 0.001)), at: i)
        }
        refreshTop()
        return removed > 0.001
    }
    func slideColumn(toward direction: Int) -> (height: Float, mass: Float, x: Float, y: Float) {
        let i = direction > 0 ? count - 1 : 0
        let result = (heights[i], loads[i] * columnWidth, centerX(i), floor(i))
        if direction > 0 {
            for j in stride(from: count - 1, through: 1, by: -1) { loads[j] = loads[j - 1]; packing[j] = packing[j - 1] }
            loads[0] = 0; packing[0] = 0
        } else {
            for j in 0..<(count - 1) { loads[j] = loads[j + 1]; packing[j] = packing[j + 1] }
            loads[count - 1] = 0; packing[count - 1] = 0
        }
        for i in loads.indices { updateHeight(i) }
        refreshTop()
        return result
    }
}
