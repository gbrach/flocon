import AppKit
import QuartzCore

struct WindowUpdate {
    let surfaces: [WindowSurface]
    let interval: Float
    let parked: Set<CGWindowID>
    let elsewhere: Set<CGWindowID>
    let sliding: Bool
}

/// Reads geometry only. A typed snapshot separates CoreGraphics dictionaries from presentation decisions.
final class WindowTracker {
    private struct Record {
        let number: CGWindowID
        let rectangle: CGRect
        let level: Int
        let dock: Bool
        init?(_ values: [String: Any], excluding process: Int32) {
            guard let owner = values[kCGWindowOwnerPID as String] as? NSNumber,
                  owner.int32Value != process,
                  let number = values[kCGWindowNumber as String] as? NSNumber,
                  let rectangle = values[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: rectangle as CFDictionary),
                  bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0
            else { return nil }
            self.number = number.uint32Value
            self.rectangle = bounds
            level = (values[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
            dock = values[kCGWindowOwnerName as String] as? String == "Dock"
            let opacity = (values[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
            guard opacity >= 0.5, level >= 0, level < Int(CGWindowLevelForKey(.statusWindow)) else { return nil }
        }
    }
    var screen = CGRect.zero // CoreGraphics top-left coordinates
    var displayID: CGDirectDisplayID?
    var menuBarHeight: CGFloat = 0
    private let process = ProcessInfo.processInfo.processIdentifier
    private var snapshot: [WindowSurface] = []
    private var readAt: Double = -1
    private var followUntil: Double = -1
    private var spaceTransitionUntil: Double = -1
    private static var sharedRecords: (time: Double, records: [[String: Any]])?

    func reset() { snapshot.removeAll(keepingCapacity: true); readAt = -1 }
    func watchClosely(now: CFTimeInterval) { followUntil = now + 0.8 }
    func spaceChanged() {
        let now = CACurrentMediaTime()
        spaceTransitionUntil = now + 1.5
        watchClosely(now: now)
    }
    func poll(now: CFTimeInterval, eager: Bool) -> WindowUpdate? {
        let interval = readAt < 0 ? 0.25 : now - readAt
        guard interval >= (eager || now < followUntil ? 0.02 : 0.25), !screen.isEmpty else { return nil }
        readAt = now
        if Self.sharedRecords == nil || now - Self.sharedRecords!.time > 0.012 {
            Self.sharedRecords = (now, CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], 0) as? [[String: Any]] ?? [])
        }
        let records = Self.sharedRecords!.records.compactMap { Record($0, excluding: process) }
        var covers: [CGRect] = []
        var supports: [WindowSurface] = []
        for record in records where record.rectangle.intersects(screen) && !record.dock {
            // Floating system backdrops can cover a whole display while remaining visually transparent.
            if record.level != 0 && record.rectangle.width * record.rectangle.height > screen.width * screen.height * 0.9 { continue }
            let global = record.rectangle
            let local = CGRect(x: global.minX - screen.minX, y: screen.maxY - global.maxY, width: global.width, height: global.height)
            let hasLedge = global.minY > screen.minY + menuBarHeight + 6 && global.width >= 80 && global.height >= 40
            if hasLedge {
                let region = CGRect(x: local.minX, y: local.maxY - 20, width: local.width, height: 100)
                supports.append(WindowSurface(id: record.number, frame: local, blockers: covers.filter { $0.intersects(region) }, cornerRadius: min(18, local.height / 2), cornerExponent: 2, isDock: false))
            }
            covers.append(local)
        }
        if let dock = dockSupport(covers: covers) { supports.append(dock) }
        guard supports != snapshot else { return nil }
        let lost = Set(snapshot.map(\.id)).subtracting(supports.map(\.id))
        let transition = now < spaceTransitionUntil
        snapshot = supports
        followUntil = now + 0.6
        return WindowUpdate(surfaces: supports, interval: Float(min(0.25, interval)), parked: transition ? lost : [], elsewhere: transition ? lost : [], sliding: transition)
    }
    private func dockSupport(covers: [CGRect]) -> WindowSurface? {
        guard let display = NSScreen.screens.first(where: { $0.displayID == displayID }) else { return nil }
        let reserved = display.visibleFrame.minY - display.frame.minY
        guard reserved > 12 else { return nil }
        let settings = UserDefaults(suiteName: "com.apple.dock")
        guard (settings?.string(forKey: "orientation") ?? "bottom") == "bottom" else { return nil }
        let items = (settings?.array(forKey: "persistent-apps")?.count ?? 0) + (settings?.array(forKey: "persistent-others")?.count ?? 0)
        let size = max(24, settings?.double(forKey: "tilesize") ?? 48)
        let span = min(screen.width - 24, CGFloat(items + 3) * size + 24)
        return WindowSurface(id: .max, frame: CGRect(x: (screen.width - span) / 2, y: 6, width: span, height: reserved - 6), blockers: covers, cornerRadius: min(22, reserved * 0.4), cornerExponent: 2, isDock: true)
    }
}
