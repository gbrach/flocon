import AppKit
import MetalKit

/// Owns the presentation and lifecycle of a single display; all simulation units are logical points.
final class ScreenSnow {
    let displayID: CGDirectDisplayID
    let simulation: SnowSimulation
    let window: OverlayWindow
    let dock: DockOverlay
    private let metalView: MTKView
    private let renderer: Renderer
    private let windows = WindowTracker()
    private(set) var screen: NSScreen
    private var showing = false
    private let tracksWindows: () -> Bool

    init?(screen: NSScreen, device: MTLDevice, snowOnWindows: @escaping () -> Bool) {
        guard let id = screen.displayID else { return nil }
        self.screen = screen; displayID = id; tracksWindows = snowOnWindows
        simulation = SnowSimulation(width: Float(screen.frame.width), height: Float(screen.frame.height), snowfall: Preferences.snowfall)
        do { renderer = try Renderer(device: device, pixelFormat: .bgra8Unorm, simulation: simulation) }
        catch { NSLog("Flocon renderer unavailable: %@", String(describing: error)); return nil }
        window = OverlayWindow(screen: screen)
        dock = DockOverlay(screen: screen, device: device)
        metalView = MTKView(frame: CGRect(origin: .zero, size: screen.frame.size), device: device)
        metalView.colorPixelFormat = .bgra8Unorm
        metalView.clearColor = MTLClearColorMake(0, 0, 0, 0)
        metalView.wantsLayer = true
        metalView.layer?.isOpaque = false
        metalView.autoResizeDrawable = false
        metalView.autoresizingMask = [.width, .height]
        metalView.preferredFramesPerSecond = 30
        metalView.isPaused = true
        (metalView.layer as? CAMetalLayer)?.maximumDrawableCount = 2
        window.contentView = metalView
        window.behindWindows = Preferences.behindWindows
        window.showsInScreenshots = Preferences.showInScreenshots
        dock.window.showsInScreenshots = Preferences.showInScreenshots
        simulation.accumulates = Preferences.accumulate
        simulation.thaws = Preferences.meltSnow
        simulation.interactions = Preferences.interactions
        simulation.windStrength = Preferences.wind
        renderer.dockOverlay = dock
        renderer.cursorLocation = { [weak self] in
            guard let self else { return SIMD2(-10000, -10000) }
            let p = NSEvent.mouseLocation
            return SIMD2(Float(p.x - self.screen.frame.minX), Float(p.y - self.screen.frame.minY))
        }
        renderer.windowSurfaces = { [weak self] time in
            guard let self, self.tracksWindows() else { return nil }
            return self.windows.poll(now: time, eager: NSEvent.pressedMouseButtons != 0)
        }
        fit(to: screen)
        metalView.delegate = renderer
    }
    func fit(to screen: NSScreen) {
        self.screen = screen
        window.setFrame(screen.frame, display: false)
        dock.fit(to: screen)
        Renderer.fitDrawable(of: metalView)
        simulation.resize(width: Float(screen.frame.width), height: Float(screen.frame.height))
        renderer.interactiveFrameRate = min(60, max(30, screen.maximumFramesPerSecond))
        windows.displayID = displayID
        windows.screen = CGRect(x: screen.frame.minX, y: (NSScreen.screens.first?.frame.maxY ?? 0) - screen.frame.maxY, width: screen.frame.width, height: screen.frame.height)
        windows.menuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
        windows.reset()
        renderer.configureLights(width: Float(screen.frame.width), height: Float(screen.frame.height), topInset: Float(max(screen.safeAreaInsets.top, windows.menuBarHeight)))
        synchronizePlanes()
    }
    private func synchronizePlanes() {
        renderer.configureDesktop(frame: screen.frame, behindWindows: window.behindWindows, visible: showing, capture: window.showsInScreenshots)
    }
    func setChristmasLights(_ enabled: Bool, style: LightStyle) {
        renderer.lightsVisible = enabled
        renderer.reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        var style = style
        if renderer.reduceMotion { style.blink = .steady }
        renderer.lightStyle = style
        synchronizePlanes()
        renderer.invalidate()
    }
    func apply(_ budget: PowerBudget) {
        renderer.budget = budget
        simulation.density = budget.density
    }
    func setVisible(_ visible: Bool) {
        guard showing != visible else { return }
        showing = visible
        renderer.isActive = visible
        metalView.isPaused = !visible
        if visible {
            renderer.resetClock()
            window.orderFrontRegardless(); dock.window.orderFrontRegardless()
        } else {
            window.orderOut(nil); dock.window.orderOut(nil)
            metalView.releaseDrawables()
        }
        synchronizePlanes()
    }
    func watchWindows() { windows.watchClosely(now: CACurrentMediaTime()) }
    func spaceChanged() { simulation.spaceChanged(); windows.spaceChanged(); renderer.invalidate() }
    func dropWindowSnow() { simulation.updateWindows([], interval: 0.1); windows.reset(); renderer.invalidate() }
    func close() {
        renderer.isActive = false
        metalView.isPaused = true
        metalView.delegate = nil
        renderer.close(); dock.close(); window.close()
    }
}
extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
