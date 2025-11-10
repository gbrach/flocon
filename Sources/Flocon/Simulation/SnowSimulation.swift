import CoreGraphics
import Foundation
import simd

/// Fixed-step particles coupled to conservative support strips. Platform snapshots enter only in updateWindows.
final class SnowSimulation {
    enum Pace { case calm, lively, interactive }
    private(set) var pace = Pace.calm
    private(set) var width: Float
    private(set) var height: Float
    let columnWidth: Float = 2
    var snowfall: Snowfall
    var density: Float = 1
    var windStrength: Float = 1
    var interactions = true
    var accumulates = true
    var thaws = false
    let ground: SnowLayer
    private(set) var ledges: [CGWindowID: SnowLayer] = [:]
    private var dormant: [CGWindowID: SnowLayer] = [:]
    private(set) var fields: [SnowLayer] = []
    private var flakes: [SnowParticle] = []
    private var fragments: [SnowParticle] = []
    private var random: SnowRandom
    private var elapsed: Float = 0
    private var variableDensity: Float = 1
    private var desiredDensity: Float = 1
    private var nextWeather: Float = 0
    private var population: Float = 0
    private var initialized = false
    private var cursorVelocity = SIMD2<Float>.zero
    private var lastCursor: SIMD2<Float>?
    private var recentInteraction: Float = -10
    private var packingClock: Float = 0
    private var clearing: Float = 0
    private var clearDirection: Float = 1
    private let maxFragments = 8192
    private(set) var escapedArea: Float = 0
    private(set) var meltedArea: Float = 0

    init(width: Float, height: Float, snowfall: Snowfall, seed: UInt64 = UInt64.random(in: 1...UInt64.max)) {
        self.width = max(1, width); self.height = max(1, height)
        self.snowfall = snowfall
        random = SnowRandom(state: seed)
        ground = SnowLayer(origin: .zero, columns: max(2, Int(ceil(width / 2))), columnWidth: 2, depth: 45, opensAtEdges: false)
        fields = [ground]
        flakes.reserveCapacity(8000); fragments.reserveCapacity(maxFragments)
    }
    var spriteCount: Int { flakes.count + fragments.count }
    var hasSnow: Bool { fields.contains { $0.top > 0.03 } }
    var snowArea: Float {
        fields.reduce(0) { $0 + $1.area } + dormant.values.reduce(0) { $0 + $1.area } + fragments.reduce(0) { $0 + $1.area }
    }
    var breezeDirection: Float { wind < 0 ? -1 : 1 }
    private var wind: Float { windStrength * (14 * sin(elapsed * 0.11) + 8 * cos(elapsed * 0.031)) }

    func resize(width: Float, height: Float) {
        self.width = max(1, width); self.height = max(1, height)
        let before = ground.area
        ground.resize(columns: max(2, Int(ceil(self.width / 2))))
        escapedArea += max(0, before - ground.area)
    }
    func spaceChanged() { lastCursor = nil }

    func updateWindows(_ surfaces: [WindowSurface], interval: Float, parked: Set<CGWindowID> = [], elsewhere: Set<CGWindowID> = [], sliding: Bool = false) {
        let ids = Set(surfaces.map(\.id))
        for id in Array(ledges.keys) where !ids.contains(id) {
            guard let field = ledges.removeValue(forKey: id) else { continue }
            if parked.contains(id) || elsewhere.contains(id) { dormant[id] = field }
            else { detach(field, fraction: 1, velocity: field.velocity) }
        }
        for surface in surfaces.sorted(by: { $0.id < $1.id }) {
            let position = SIMD2(Float(surface.frame.minX), Float(surface.frame.maxY))
            let columns = max(2, Int(ceil(Float(surface.frame.width) / columnWidth)))
            let field: SnowLayer
            if let current = ledges[surface.id] {
                field = current
                let displacement = position - field.origin
                let velocity = displacement / max(1 / 120, interval)
                let acceleration = (velocity - field.velocity) / max(1 / 120, interval)
                if !sliding && simd_length(displacement) > 0.01 {
                    let shock = max(abs(acceleration.x) / 12000, -velocity.y / 1000) / (1 + field.cohesion * 0.8)
                    if shock > 0.8 { detach(field, fraction: min(1, (shock - 0.8) * 0.6), velocity: field.velocity * 0.55) }
                    recentInteraction = elapsed
                }
                field.velocity = sliding ? .zero : velocity
            } else if let restored = dormant.removeValue(forKey: surface.id) {
                field = restored
                field.velocity = .zero
            } else {
                field = SnowLayer(origin: position, columns: columns, columnWidth: columnWidth, depth: 16, opensAtEdges: true)
            }
            let previous = field.area
            field.resize(columns: columns)
            escapedArea += max(0, previous - field.area)
            field.origin = position
            field.isDock = surface.isDock
            field.shapeCorners(radius: Float(surface.cornerRadius), exponent: Float(surface.cornerExponent))
            field.occluders = surface.blockers.prefix(128).map { SIMD4(Float($0.minX), Float($0.minY), Float($0.maxX), Float($0.maxY)) }
            field.updateVisibility(screenWidth: width, blockers: field.occluders)
            ledges[surface.id] = field
        }
        while dormant.count > 200, let id = dormant.keys.min() { escapedArea += dormant.removeValue(forKey: id)!.area }
        fields = [ground] + ledges.keys.sorted().compactMap { ledges[$0] }
    }

    @discardableResult func step(dt: Float, cursor: SIMD2<Float>) -> Bool {
        guard dt.isFinite, dt > 0, dt <= 0.05 else { return false }
        elapsed += dt
        if elapsed >= nextWeather {
            desiredDensity = random.between(0.25, 1.8)
            nextWeather = elapsed + random.between(45, 160)
        }
        variableDensity += (desiredDensity - variableDensity) * min(1, dt / 18)
        let target = min(8000, snowfall.flakesPerMegapoint * density * (snowfall == .variable ? variableDensity : 1) * width * height / 1_000_000)
        if !initialized { population = target; initialized = true }
        population += (target - population) * min(1, dt / 3)
        let wanted = max(0, Int(population.rounded()))
        if flakes.count < wanted {
            for _ in flakes.count..<wanted { flakes.append(makeFlake(starting: elapsed <= dt)) }
        }
        if interactions { disturb(at: cursor, dt: dt) } else { lastCursor = nil }
        let moving = !flakes.isEmpty || !fragments.isEmpty
        advanceFlakes(dt: dt, cursor: cursor, limit: wanted)
        advanceFragments(dt: dt)
        var changed = moving
        packingClock += dt
        let packingStep = packingClock >= 0.5 ? packingClock : 0
        if packingStep > 0 { packingClock = 0 }
        for field in fields {
            if packingStep > 0 { changed = field.compact(dt: packingStep) || changed }
            if clearing > 0 {
                let before = field.area
                _ = field.thaw(dt: dt, down: 0, rate: 100, settle: 0.15)
                escapedArea += max(0, before - field.area)
                changed = true
            } else if thaws || !accumulates {
                let before = field.area
                changed = field.thaw(dt: dt, down: accumulates ? 8 : 0, rate: 0.015, settle: accumulates ? 50 : 3) || changed
                meltedArea += max(0, before - field.area)
            }
            changed = field.relax(repose: 0.8) || changed
            if field.spill.left > 0.1 {
                emit(area: field.spill.left, position: SIMD2(field.origin.x - 1, field.surface(0)), velocity: SIMD2(-20, -30), clump: false)
                field.spill.left = 0
            }
            if field.spill.right > 0.1 {
                emit(area: field.spill.right, position: SIMD2(field.origin.x + field.width + 1, field.surface(field.count - 1)), velocity: SIMD2(20, -30), clump: false)
                field.spill.right = 0
            }
            field.refreshTop()
        }
        clearing = max(0, clearing - dt)
        pace = elapsed - recentInteraction < 0.3 ? .interactive : fragments.count > 12 ? .lively : .calm
        return changed
    }

    private func makeFlake(starting: Bool) -> SnowParticle {
        let depth = random.unit()
        let speed = 22 + 65 * depth
        return SnowParticle(position: SIMD2(random.between(0, width), starting ? random.between(0, height) : height + random.between(4, 80)), velocity: SIMD2(wind, -speed), radius: random.between(1.5, 3) + 2.5 * depth, opacity: 0.35 + 0.5 * depth, phase: random.between(0, 6.28), terminalSpeed: speed, area: 0)
    }
    private func landing(x: Float, from: Float, to: Float) -> SnowLayer? {
        var candidate: SnowLayer?
        var level = -Float.greatestFiniteMagnitude
        for field in fields {
            guard let i = field.index(at: x), field.visible[i] else { continue }
            let y = field.surface(i)
            if to <= y && from >= field.floor(i) - 0.5 && y > level { level = y; candidate = field }
        }
        return candidate
    }
    private func add(_ area: Float, to field: SnowLayer, at x: Float) {
        let missing = field.deposit(area, at: x, wide: true)
        if missing > 0 {
            let left = x < field.origin.x + field.width / 2
            let edge = left ? field.origin.x - 1 : field.origin.x + field.width + 1
            emit(area: missing, position: SIMD2(edge, field.origin.y - 1), velocity: SIMD2(left ? -12 : 12, -20), clump: false)
        }
    }
    private func advanceFlakes(dt: Float, cursor: SIMD2<Float>, limit: Int) {
        for i in flakes.indices.reversed() {
            var p = flakes[i]
            let previous = p.position.y
            p.phase += dt * (0.6 + p.radius * 0.13)
            p.velocity.x += (wind + 9 * sin(p.phase) - p.velocity.x) * min(1, dt * 1.5)
            if clearing > 0 { p.velocity.x += clearDirection * 650 * dt }
            if interactions, simd_distance_squared(cursor, p.position) < 3600 {
                p.velocity += cursorVelocity * min(0.03, dt) * 0.2
            }
            p.position += p.velocity * dt
            if p.position.x < -10 { p.position.x = width + 5 }
            if p.position.x > width + 10 { p.position.x = -5 }
            let support = accumulates ? landing(x: p.position.x, from: previous, to: p.position.y) : nil
            if support != nil || p.position.y < -10 {
                if let support, let cell = support.index(at: p.position.x) {
                    add(p.radius * p.radius * 0.7 * max(0, 1 - support.heights[cell] / support.depth), to: support, at: p.position.x)
                }
                if flakes.count > limit || clearing > 0 { flakes.swapAt(i, flakes.count - 1); flakes.removeLast() }
                else { flakes[i] = makeFlake(starting: false) }
            } else { flakes[i] = p }
        }
    }
    private func emit(area: Float, position: SIMD2<Float>, velocity: SIMD2<Float>, clump: Bool) {
        guard area > 0 else { return }
        if fragments.count >= maxFragments { ground.deposit(area, at: position.x, wide: true); return }
        fragments.append(SnowParticle(position: position, velocity: velocity, radius: min(13, max(1.5, sqrt(area) * 0.8)), opacity: 0.96, phase: random.between(0, 6.28), terminalSpeed: 0, area: area, clump: clump, fractureAge: clump ? random.between(0.35, 0.9) : .infinity, spin: random.between(-3, 3)))
    }
    private func detach(_ field: SnowLayer, fraction: Float, velocity: SIMD2<Float>) {
        let cohesion = field.cohesion
        var start = 0
        while start < field.count {
            let span = max(3, Int(random.between(3, 9) + 8 * cohesion))
            let end = min(field.count, start + span)
            defer { start = end }
            guard fraction >= 1 || random.unit() < fraction else { continue }
            var mass: Float = 0, bonded: Float = 0
            var center = SIMD2<Float>.zero
            var depth: Float = 0
            for i in start..<end {
                let height = field.heights[i]
                let packing = field.packing[i]
                let position = SIMD2(field.centerX(i), field.floor(i) + height * 0.5)
                let removed = field.removeFraction(1, at: i)
                mass += removed; bonded += removed * packing
                center += position * removed
                depth = max(depth, height)
            }
            guard mass > 0 else { continue }
            center /= mass
            let cohesive = mass * (0.65 + 0.25 * bonded / mass)
            let jitter = SIMD2(random.between(-25, 25), random.between(-35, 45))
            emit(area: cohesive, position: center + SIMD2(0, 1), velocity: velocity * random.between(0.8, 1.05) + jitter, clump: true)
            let powder = (mass - cohesive) / 2
            for _ in 0..<2 {
                let scatter = SIMD2(random.between(-Float(span) * columnWidth * 0.4, Float(span) * columnWidth * 0.4), random.between(-depth * 0.3, depth * 0.5))
                emit(area: powder, position: center + scatter, velocity: velocity * 0.5 + SIMD2(random.between(-70, 70), random.between(-20, 90)), clump: false)
            }
        }
        if fraction == 1 {
            emit(area: field.spill.left + field.spill.right, position: field.origin, velocity: velocity, clump: false)
            field.spill = (0, 0)
        }
        field.refreshTop()
    }
    private func fracture(_ particle: SnowParticle) {
        let parts: [Float] = [0.45, 0.35, 0.2]
        let direction = SIMD2(random.between(20, 60), random.between(-15, 25))
        for (i, share) in parts.enumerated() {
            let spread = Float(i) - 0.75
            emit(area: particle.area * share, position: particle.position + SIMD2(spread * particle.radius * 0.5, random.between(-2, 2)), velocity: particle.velocity + direction * spread, clump: true)
        }
    }
    private func advanceFragments(dt: Float) {
        let end = fragments.count
        guard end > 0 else { return }
        for i in (0..<end).reversed() {
            var p = fragments[i]
            let previous = p.position.y
            p.age += dt
            p.phase += p.spin * dt
            p.velocity.y -= 1500 * dt
            let drag = p.clump ? 0.15 + 0.4 / p.radius : 1.1 / sqrt(p.radius)
            p.velocity *= exp(-dt * drag)
            p.position += p.velocity * dt
            if p.position.x < 0 || p.position.x >= width {
                escapedArea += p.area
            } else if p.velocity.y < 0, let field = landing(x: p.position.x, from: previous, to: p.position.y) {
                let splash = p.clump ? p.area * 0.16 : 0
                add(p.area - splash, to: field, at: p.position.x)
                if splash > 0 {
                    let surface = field.surface(field.index(at: p.position.x)!)
                    for _ in 0..<3 {
                        emit(area: splash / 3, position: SIMD2(p.position.x + random.between(-4, 4), surface + 2), velocity: SIMD2(random.between(-65, 65), random.between(45, 120)), clump: false)
                    }
                }
            } else if p.position.y < -20 { escapedArea += p.area }
            else if p.clump && p.area > 64 && p.age > p.fractureAge && simd_length(p.velocity) > 220 { fracture(p) }
            else { fragments[i] = p; continue }
            fragments.swapAt(i, fragments.count - 1); fragments.removeLast()
        }
    }
    private func disturb(at point: SIMD2<Float>, dt: Float) {
        defer {
            cursorVelocity = lastCursor.map { (point - $0) / dt } ?? .zero
            let speed = simd_length(cursorVelocity)
            if speed > 800 { cursorVelocity *= 800 / speed }
            lastCursor = point
        }
        guard let previous = lastCursor else { return }
        let travel = simd_distance(previous, point)
        guard travel > 0.1, travel < 400 else { return }
        let velocity = (point - previous) / dt
        let steps = max(1, Int(ceil(travel / 6)))
        for step in 1...steps {
            let center = previous + (point - previous) * (Float(step) / Float(steps)) + SIMD2(4, -8)
            for field in fields where field.top > 0 {
                guard center.y >= field.origin.y - 25 && center.y <= field.origin.y + field.top + 18 else { continue }
                let lo = max(0, Int(floor((center.x - 12 - field.origin.x) / columnWidth)))
                let hi = min(field.count - 1, Int(ceil((center.x + 12 - field.origin.x) / columnWidth)))
                guard lo <= hi else { continue }
                for cell in lo...hi where field.visible[cell] {
                    let dx = field.centerX(cell) - center.x
                    let reach = sqrt(max(0, 144 - dx * dx))
                    let remaining = max(0, center.y - reach - field.floor(cell))
                    let removed = max(0, field.heights[cell] - remaining)
                    if removed > 0 {
                        let mass = field.removeHeight(removed, at: cell)
                        emit(area: mass, position: SIMD2(field.centerX(cell), field.floor(cell) + remaining + 2), velocity: SIMD2(min(300, max(-300, velocity.x * 0.3)), 75), clump: false)
                        recentInteraction = elapsed
                    }
                }
            }
        }
    }
    func blowAway(direction: Float, calm: Bool) {
        clearing = 2
        clearDirection = calm ? 0 : direction
        for field in dormant.values { escapedArea += field.area }
        dormant.removeAll()
    }
    func writeSprites(into buffer: UnsafeMutablePointer<Sprite>, capacity: Int) -> Int {
        var n = 0
        for p in flakes {
            guard n < capacity else { break }
            buffer[n] = Sprite(position: p.position, size: p.radius, alpha: p.opacity, motion: SIMD4(p.velocity.x, p.velocity.y, 0, p.phase)); n += 1
        }
        for p in fragments {
            guard n < capacity else { break }
            buffer[n] = Sprite(position: p.position, size: p.radius, alpha: p.opacity, motion: SIMD4(p.velocity.x, p.velocity.y, p.clump ? 1 : 0, p.phase)); n += 1
        }
        return n
    }
}
