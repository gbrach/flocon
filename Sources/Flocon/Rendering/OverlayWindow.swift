import AppKit

/// An input-transparent presentation surface, never a participant in the responder chain.
final class OverlayWindow: NSWindow {
    static let belowDockLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) - 1)
    static let desktopLevel = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopWindow)) + 1)
    var behindWindows = false
    var showsInScreenshots = false {
        didSet { sharingType = showsInScreenshots ? .readOnly : .none }
    }
    init(screen: NSScreen, level: NSWindow.Level = .statusBar) {
        super.init(contentRect: screen.frame, styleMask: [], backing: .buffered, defer: false)
        configure(level: level)
    }
    init(frame: CGRect, level: NSWindow.Level) {
        super.init(contentRect: frame, styleMask: [], backing: .buffered, defer: false)
        configure(level: level)
    }
    private func configure(level: NSWindow.Level) {
        self.level = level
        backgroundColor = .clear
        isOpaque = false
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        sharingType = .none
        collectionBehavior = [.stationary, .canJoinAllSpaces, .ignoresCycle]
        animationBehavior = .none
    }
    override var canBecomeMain: Bool { false }
    override var canBecomeKey: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}
