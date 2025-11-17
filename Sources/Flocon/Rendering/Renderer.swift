import MetalKit
import QuartzCore

struct FrameUniforms {
    var extent: SIMD2<Float>
    var time: Float
    var scale: Float
}
struct SnowVertex {
    var point: SIMD2<Float>
    var color: SIMD4<Float>
}
enum PresentationPlane { case all, desktop, foreground, dock }

enum RendererError: Error { case unavailable, missingShaders }

/// Builds compact surface meshes and instanced flake quads into a two-frame upload ring.
final class Renderer: NSObject, MTKViewDelegate {
    private struct Programs {
        let flakes: MTLRenderPipelineState
        let snow: MTLRenderPipelineState
        let wire: MTLRenderPipelineState
    }
    private struct Batch {
        let field: SnowLayer
        let start: Int
        let count: Int
        let ground: Bool
    }
    private struct Upload {
        var instances: MTLBuffer?
        var mesh: MTLBuffer?
    }
    private static var programs: [UInt64: Programs] = [:]
    private let device: MTLDevice
    private let queue: MTLCommandQueue
    private let programs: Programs
    private let simulation: SnowSimulation
    private var uploads = [Upload(), Upload()]
    private let available = DispatchSemaphore(value: 2)
    private var slot = 0
    private var instances: MTLBuffer?
    private var mesh: MTLBuffer?
    private var batches: [Batch] = []
    private var instanceCount = 0
    private var previousTime: Double?
    private var remainder: Float = 0
    private var invalidated = true
    private var desktop: LayerSurface?
    private var dockHasImage = false
    private var bulbs: MTLBuffer?
    private var cable: MTLBuffer?
    private var bulbCount = 0
    private var cableCount = 0
    private(set) var behindWindows = false
    var lightsVisible = false
    var reduceMotion = false
    var interactiveFrameRate = 60
    var budget = PowerBudget.full
    var isActive = false
    var dockOverlay: DockOverlay?
    var cursorLocation: () -> SIMD2<Float> = { SIMD2(-10000, -10000) }
    var windowSurfaces: (CFTimeInterval) -> WindowUpdate? = { _ in nil }

    init(device: MTLDevice, pixelFormat: MTLPixelFormat, simulation: SnowSimulation) throws {
        guard let queue = device.makeCommandQueue() else { throw RendererError.unavailable }
        self.device = device; self.queue = queue; self.simulation = simulation
        let key = device.registryID ^ UInt64(pixelFormat.rawValue)
        if let cached = Self.programs[key] { programs = cached }
        else {
            guard let url = Bundle.main.url(forResource: "Shaders", withExtension: "metal") ?? Bundle.module.url(forResource: "Shaders", withExtension: "metal") else { throw RendererError.missingShaders }
            let library = try device.makeLibrary(source: String(contentsOf: url, encoding: .utf8), options: nil)
            func create(_ vertex: String, _ fragment: String) throws -> MTLRenderPipelineState {
                let recipe = MTLRenderPipelineDescriptor()
                recipe.vertexFunction = library.makeFunction(name: vertex)
                recipe.fragmentFunction = library.makeFunction(name: fragment)
                let color = recipe.colorAttachments[0]!
                color.pixelFormat = pixelFormat
                color.isBlendingEnabled = true
                color.sourceRGBBlendFactor = .one; color.sourceAlphaBlendFactor = .one
                color.destinationRGBBlendFactor = .oneMinusSourceAlpha; color.destinationAlphaBlendFactor = .oneMinusSourceAlpha
                return try device.makeRenderPipelineState(descriptor: recipe)
            }
            let built = try Programs(flakes: create("flakeQuad", "flakePixel"), snow: create("snowMesh", "snowPixel"), wire: create("cableVertex", "cablePixel"))
            Self.programs[key] = built
            programs = built
        }
        super.init()
        batches.reserveCapacity(128)
    }
    func configureDesktop(frame: CGRect, behindWindows: Bool, visible: Bool, capture: Bool) {
        self.behindWindows = behindWindows
        if behindWindows {
            if desktop == nil { desktop = LayerSurface(frame: frame, level: OverlayWindow.desktopLevel, device: device) }
            desktop?.resize(frame)
            desktop?.window.showsInScreenshots = capture
            if visible { desktop?.window.orderFrontRegardless() } else { desktop?.window.orderOut(nil) }
        } else { desktop?.close(); desktop = nil }
        invalidate()
    }
    func close() { desktop?.close(); desktop = nil }
    func configureLights(width: Float, height: Float, topInset: Float) {
        let geometry = ChristmasLightGeometry(width: width, height: height, topInset: topInset)
        bulbCount = geometry.bulbs.count; cableCount = geometry.wire.count
        bulbs = geometry.bulbs.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }
        cable = geometry.wire.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }
        invalidate()
    }
    func invalidate() { invalidated = true }
    func resetClock() { previousTime = nil; remainder = 0; invalidate() }
    static func fitDrawable(of view: MTKView) { view.drawableSize = view.bounds.size }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { invalidate() }

    func draw(in view: MTKView) {
        guard isActive, !view.isPaused else { return }
        let time = CACurrentMediaTime()
        remainder += Float(min(0.05, max(0, previousTime.map { time - $0 } ?? (1 / 60))))
        previousTime = time
        if let windows = windowSurfaces(time) {
            simulation.updateWindows(windows.surfaces, interval: windows.interval, parked: windows.parked, elsewhere: windows.elsewhere, sliding: windows.sliding)
            invalidated = true
        }
        var changed = false
        let cursor = cursorLocation()
        while remainder >= 1 / Float(60) {
            changed = simulation.step(dt: 1 / 60, cursor: cursor) || changed
            remainder -= 1 / 60
        }
        let fps = budget == .full && simulation.pace != .calm ? interactiveFrameRate : 30
        if view.preferredFramesPerSecond != fps { view.preferredFramesPerSecond = fps }
        guard changed || lightsVisible || invalidated else { return }
        guard available.wait(timeout: .now()) == .success else { return }
        guard let pass = view.currentRenderPassDescriptor, let image = view.currentDrawable,
              let command = queue.makeCommandBuffer(), prepare() else { available.signal(); return }
        let uniforms = FrameUniforms(extent: SIMD2(simulation.width, simulation.height), time: reduceMotion ? 0 : Float(time.truncatingRemainder(dividingBy: 1000)), scale: 1)
        paint(pass, command: command, frame: uniforms, plane: behindWindows ? .foreground : .all)
        command.present(image)
        if let desktop, let (image, pass) = desktop.begin() {
            paint(pass, command: command, frame: uniforms, plane: .desktop)
            command.present(image)
        }
        var dockTop: CGFloat?
        for batch in batches where batch.field.isDock {
            dockTop = max(dockTop ?? 0, CGFloat(batch.field.origin.y + batch.field.top + 2))
        }
        if let dock = dockOverlay, dockTop != nil || dockHasImage, let layer = dock.nextFrame(reaching: dockTop) {
            var dockFrame = uniforms; dockFrame.extent.y = Float(dock.height)
            paint(layer.pass, command: command, frame: dockFrame, plane: .dock)
            command.present(layer.drawable)
            dockHasImage = dockTop != nil
        }
        command.addCompletedHandler { [available] _ in available.signal() }
        command.commit()
        invalidated = false
    }
    private func grow(_ buffer: inout MTLBuffer?, bytes: Int) {
        let needed = max(256, bytes)
        if (buffer?.length ?? 0) < needed { buffer = device.makeBuffer(length: needed + needed / 2, options: .storageModeShared) }
    }
    private func prepare() -> Bool {
        let n = slot % uploads.count
        slot = (slot + 1) % uploads.count
        grow(&uploads[n].instances, bytes: simulation.spriteCount * MemoryLayout<Sprite>.stride)
        let capacity = simulation.fields.reduce(0) { $0 + ($1.count - 1) * 6 }
        grow(&uploads[n].mesh, bytes: capacity * MemoryLayout<SnowVertex>.stride)
        instances = uploads[n].instances; mesh = uploads[n].mesh
        guard let instances, let mesh else { return false }
        instanceCount = simulation.writeSprites(into: instances.contents().assumingMemoryBound(to: Sprite.self), capacity: instances.length / MemoryLayout<Sprite>.stride)
        let vertices = mesh.contents().assumingMemoryBound(to: SnowVertex.self)
        var written = 0
        batches.removeAll(keepingCapacity: true)
        for field in simulation.fields where field.top > 0.01 {
            let start = written
            func top(_ i: Int) -> Float {
                field.floor(i) + 0.2 * field.heights[max(0, i - 1)] + 0.6 * field.heights[i] + 0.2 * field.heights[min(field.count - 1, i + 1)]
            }
            for i in 0..<(field.count - 1) {
                let x0 = field.centerX(i), x1 = field.centerX(i + 1)
                let y0 = top(i), y1 = top(i + 1)
                let bottom0 = field.floor(i), bottom1 = field.floor(i + 1)
                guard max(y0 - bottom0, y1 - bottom1) > 0.01 else { continue }
                let white = SIMD4<Float>(0.97, 0.98, 1, 1)
                let shade = SIMD4<Float>(0.73, 0.81, 0.91, 1)
                let a = SnowVertex(point: SIMD2(x0, bottom0), color: shade)
                let b = SnowVertex(point: SIMD2(x1, bottom1), color: shade)
                let c = SnowVertex(point: SIMD2(x0, y0), color: white)
                let d = SnowVertex(point: SIMD2(x1, y1), color: white)
                vertices[written] = a; vertices[written + 1] = b; vertices[written + 2] = c
                vertices[written + 3] = c; vertices[written + 4] = b; vertices[written + 5] = d
                written += 6
            }
            batches.append(Batch(field: field, start: start, count: written - start, ground: field === simulation.ground))
        }
        return true
    }
    private func paint(_ pass: MTLRenderPassDescriptor, command: MTLCommandBuffer, frame: FrameUniforms, plane: PresentationPlane) {
        guard let encoder = command.makeRenderCommandEncoder(descriptor: pass) else { return }
        var frame = frame
        encoder.setVertexBytes(&frame, length: MemoryLayout<FrameUniforms>.stride, index: 1)
        encoder.setRenderPipelineState(programs.snow)
        encoder.setVertexBuffer(mesh, offset: 0, index: 0)
        for batch in batches {
            let included: Bool
            switch plane {
            case .all: included = !batch.field.isDock || dockOverlay == nil
            case .desktop: included = batch.ground
            case .foreground: included = !batch.ground && !batch.field.isDock
            case .dock: included = batch.field.isDock
            }
            guard included else { continue }
            var count = UInt32(batch.field.occluders.count)
            encoder.setFragmentBytes(&count, length: 4, index: 1)
            if count > 0 { batch.field.occluders.withUnsafeBytes { encoder.setFragmentBytes($0.baseAddress!, length: $0.count, index: 0) } }
            else {
                var dummy = SIMD4<Float>.zero
                encoder.setFragmentBytes(&dummy, length: 16, index: 0)
            }
            encoder.drawPrimitives(type: .triangle, vertexStart: batch.start, vertexCount: batch.count)
        }
        if plane == .all || plane == .desktop {
            encoder.setRenderPipelineState(programs.flakes)
            encoder.setVertexBuffer(instances, offset: 0, index: 0)
            if instanceCount > 0 { encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: instanceCount) }
        }
        if lightsVisible && (plane == .all || plane == .foreground), let bulbs, let cable {
            encoder.setRenderPipelineState(programs.wire)
            encoder.setVertexBuffer(cable, offset: 0, index: 0)
            encoder.drawPrimitives(type: .lineStrip, vertexStart: 0, vertexCount: cableCount)
            encoder.setRenderPipelineState(programs.flakes)
            encoder.setVertexBuffer(bulbs, offset: 0, index: 0)
            encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: bulbCount)
        }
        encoder.endEncoding()
    }
}
