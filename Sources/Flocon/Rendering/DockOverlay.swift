import AppKit
import Metal
import QuartzCore

/// A manually presented Metal surface; it shares a command buffer with the primary MTKView.
final class LayerSurface {
    let window: OverlayWindow
    private let metal = CAMetalLayer()
    private var frame: CGRect
    init(frame: CGRect, level: NSWindow.Level, device: MTLDevice) {
        self.frame = frame
        window = OverlayWindow(frame: frame, level: level)
        metal.device = device
        metal.pixelFormat = .bgra8Unorm
        metal.isOpaque = false
        metal.framebufferOnly = true
        metal.maximumDrawableCount = 2
        let host = NSView(frame: CGRect(origin: .zero, size: frame.size))
        host.wantsLayer = true
        host.layer = metal
        window.contentView = host
        resize(frame)
    }
    func resize(_ frame: CGRect) {
        self.frame = frame
        window.setFrame(frame, display: false)
        metal.frame = CGRect(origin: .zero, size: frame.size)
        metal.drawableSize = frame.size
        metal.contentsScale = 1
    }
    func begin() -> (CAMetalDrawable, MTLRenderPassDescriptor)? {
        guard window.occlusionState.contains(.visible), let image = metal.nextDrawable() else { return nil }
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = image.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 0)
        return (image, pass)
    }
    func close() { window.close() }
}

final class DockOverlay {
    private let surface: LayerSurface
    private var displayFrame: CGRect
    private(set) var height: CGFloat = 1
    var window: OverlayWindow { surface.window }
    init(screen: NSScreen, device: MTLDevice) {
        displayFrame = screen.frame
        surface = LayerSurface(frame: CGRect(x: screen.frame.minX, y: screen.frame.minY, width: screen.frame.width, height: 1), level: OverlayWindow.belowDockLevel, device: device)
    }
    func fit(to screen: NSScreen) { displayFrame = screen.frame; place() }
    func nextFrame(reaching top: CGFloat?) -> (drawable: CAMetalDrawable, pass: MTLRenderPassDescriptor)? {
        let desired = min(displayFrame.height, max(1, ceil((top ?? 0) / 64) * 64 + 16))
        if desired != height { height = desired; place() }
        guard let (drawable, pass) = surface.begin() else { return nil }
        return (drawable, pass)
    }
    private func place() { surface.resize(CGRect(x: displayFrame.minX, y: displayFrame.minY, width: displayFrame.width, height: height)) }
    func close() { surface.close() }
}
