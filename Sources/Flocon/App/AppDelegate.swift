import AppKit
import MetalKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var screens: [ScreenSnow] = []
    private var statusItem: NSStatusItem!
    private var device: MTLDevice!
    private let power = PowerMonitor()
    private let lid = LidMonitor()
    private var observers: [(NotificationCenter, NSObjectProtocol)] = []
    private var visibilityTimer: Timer?
    private var activity = ActivityState()
    private var covered = Set<CGDirectDisplayID>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Preferences.registerDefaults()
        guard let device = MTLCreateSystemDefaultDevice() else {
            let alert = NSAlert()
            alert.messageText = "Flocon needs a Metal-capable graphics processor."
            alert.informativeText = "Intel and Apple Silicon Macs are supported with macOS 14 or later and a Metal-capable GPU."
            alert.runModal()
            NSApp.terminate(nil)
            return
        }
        self.device = device
        statusItem = makeMenu()
        power.forceSaver = Preferences.energySaver
        power.changed = { [weak self] in self?.applyPreferences() }
        lid.changed = { [weak self] in self?.updateActivity() }
        observeSystem()
        syncScreens()
        updateActivity()
        UpdateChecker.run(silent: true)
    }

    func applicationWillTerminate(_ notification: Notification) {
        visibilityTimer?.invalidate()
        screens.forEach { $0.close() }
        for (center, token) in observers { center.removeObserver(token) }
    }

    private func syncScreens() {
        let current = NSScreen.screens
        let ids = Set(current.compactMap(\.displayID))
        for removed in screens where !ids.contains(removed.displayID) { removed.close() }
        screens.removeAll { !ids.contains($0.displayID) }
        for display in current {
            if let existing = screens.first(where: { $0.displayID == display.displayID }) {
                existing.fit(to: display)
            } else if let scene = ScreenSnow(screen: display, device: device, snowOnWindows: { Preferences.snowOnWindows }) {
                screens.append(scene)
            }
        }
        applyPreferences()
        checkCoverage()
    }

    private func applyPreferences() {
        for scene in screens {
            scene.simulation.snowfall = Preferences.snowfall
            scene.simulation.windStrength = Preferences.wind
            scene.simulation.accumulates = Preferences.accumulate
            scene.simulation.thaws = Preferences.meltSnow
            scene.simulation.interactions = Preferences.interactions
            scene.window.behindWindows = Preferences.behindWindows
            scene.window.showsInScreenshots = Preferences.showInScreenshots
            scene.dock.window.showsInScreenshots = Preferences.showInScreenshots
            scene.setChristmasLights(Preferences.christmasLights)
            if !Preferences.snowOnWindows { scene.dropWindowSnow() }
            scene.apply(power.budget)
        }
        statusItem.button?.appearsDisabled = !Preferences.enabled
        updateActivity()
    }

    private func makeMenu() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "snowflake", accessibilityDescription: "Flocon")
        item.button?.toolTip = "Flocon — snowfall and winter lights"
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        add("Enable Flocon", key: "enabled", to: menu)
        let snowfall = NSMenu(title: "Snowfall")
        snowfall.delegate = self
        for value in Snowfall.allCases {
            let row = snowfall.addItem(withTitle: value.title, action: #selector(selectSnowfall(_:)), keyEquivalent: "")
            row.target = self
            row.tag = value.rawValue
            row.representedObject = "snowfall"
        }
        submenu("Snowfall", menu: snowfall, to: menu)
        let wind = NSMenu(title: "Wind")
        wind.delegate = self
        for (index, title) in ["Still", "Gentle", "Breezy", "Gusty"].enumerated() {
            let row = wind.addItem(withTitle: title, action: #selector(selectWind(_:)), keyEquivalent: "")
            row.target = self
            row.tag = index
            row.representedObject = "wind"
        }
        submenu("Wind", menu: wind, to: menu)
        menu.addItem(.separator())
        add("Accumulate Snow", key: "accumulate", to: menu)
        add("Snow on Windows", key: "snowOnWindows", to: menu)
        add("Cursor Interactions", key: "interactions", to: menu)
        add("Melt Snow", key: "meltSnow", to: menu)
        let clear = menu.addItem(withTitle: "Clear Snow", action: #selector(clearSnow), keyEquivalent: "")
        clear.target = self
        menu.addItem(.separator())
        add("Christmas Lights", key: "christmasLights", to: menu)
        add("Energy Saving", key: "energySaver", to: menu)
        add("Behind Windows", key: "behindWindows", to: menu)
        add("Show in Screenshots", key: "showInScreenshots", to: menu)
        let login = menu.addItem(withTitle: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.representedObject = "login"
        let update = menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        update.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Flocon", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        return item
    }

    private func submenu(_ title: String, menu child: NSMenu, to parent: NSMenu) {
        let row = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        row.submenu = child
        parent.addItem(row)
    }

    private func add(_ title: String, key: String, to menu: NSMenu) {
        let row = menu.addItem(withTitle: title, action: #selector(toggle(_:)), keyEquivalent: "")
        row.target = self
        row.representedObject = key
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        for row in menu.items {
            guard let key = row.representedObject as? String else { continue }
            let selected: Bool
            switch key {
            case "snowfall": selected = Preferences.snowfall.rawValue == row.tag
            case "wind": selected = Int(Preferences.wind.rounded()) == row.tag
            case "login": selected = SMAppService.mainApp.status == .enabled
            default: selected = UserDefaults.standard.bool(forKey: key)
            }
            row.state = selected ? .on : .off
        }
    }

    @objc private func toggle(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: key), forKey: key)
        power.forceSaver = Preferences.energySaver
        applyPreferences()
    }
    @objc private func selectSnowfall(_ sender: NSMenuItem) {
        Preferences.snowfall = Snowfall(rawValue: sender.tag) ?? .moderate
        applyPreferences()
    }
    @objc private func selectWind(_ sender: NSMenuItem) {
        Preferences.wind = Float(sender.tag)
        applyPreferences()
    }
    @objc private func clearSnow() {
        let direction = screens.first?.simulation.breezeDirection ?? 1
        for scene in screens { scene.simulation.blowAway(direction: direction, calm: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) }
    }
    @objc private func checkForUpdates() { UpdateChecker.run() }
    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            else {
                try SMAppService.mainApp.register()
                if SMAppService.mainApp.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn’t change Launch at Login"
            alert.informativeText = "Move Flocon to Applications and try again. \(error.localizedDescription)"
            alert.runModal()
        }
    }
    private func observeSystem() {
        let workspace = NSWorkspace.shared.notificationCenter
        observe(workspace, NSWorkspace.willSleepNotification) { $0.activity.systemSleeping = true }
        observe(workspace, NSWorkspace.didWakeNotification) { $0.activity.systemSleeping = false; $0.lid.refresh(); $0.checkCoverage() }
        observe(workspace, NSWorkspace.screensDidSleepNotification) { $0.activity.displaysSleeping = true }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.activity.displaysSleeping = false; $0.lid.refresh(); $0.checkCoverage() }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { $0.activity.sessionInactive = true }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { $0.activity.sessionInactive = false; $0.checkCoverage() }
        observe(DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsLocked")) { $0.activity.locked = true }
        observe(DistributedNotificationCenter.default(), Notification.Name("com.apple.screenIsUnlocked")) { $0.activity.locked = false; $0.checkCoverage() }
        observe(.default, NSApplication.didChangeScreenParametersNotification) { $0.syncScreens() }
        observe(workspace, NSWorkspace.activeSpaceDidChangeNotification) { app in
            app.screens.forEach { $0.spaceChanged() }
            app.checkCoverage()
        }
        observe(workspace, NSWorkspace.didActivateApplicationNotification) { app in
            app.screens.forEach { $0.watchWindows() }
            app.checkCoverage()
        }
    }
    private func observe(_ center: NotificationCenter, _ name: Notification.Name, change: @escaping (AppDelegate) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            change(self)
            self.updateActivity()
        }
        observers.append((center, token))
    }
    private func updateActivity() {
        activity.enabled = Preferences.enabled
        activity.lidClosed = lid.isClosed
        let awake = activity.isRunning
        for scene in screens { scene.setVisible(awake && !covered.contains(scene.displayID)) }
        if awake && visibilityTimer == nil {
            let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in self?.checkCoverage() }
            timer.tolerance = 0.5
            RunLoop.main.add(timer, forMode: .common)
            visibilityTimer = timer
        } else if !awake {
            visibilityTimer?.invalidate()
            visibilityTimer = nil
        }
    }
    private func checkCoverage() {
        guard activity.isRunning else { return }
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        var next = Set<CGDirectDisplayID>()
        for scene in screens {
            let f = scene.screen.frame
            let area = CGRect(x: f.minX, y: primaryHeight - f.maxY, width: f.width, height: f.height).insetBy(dx: 2, dy: 2)
            if list.contains(where: { entry in
                guard entry[kCGWindowOwnerPID as String] as? Int32 != ProcessInfo.processInfo.processIdentifier,
                      entry[kCGWindowLayer as String] as? Int == 0,
                      (entry[kCGWindowAlpha as String] as? Double ?? 1) > 0.98,
                      let info = entry[kCGWindowBounds as String] as? NSDictionary,
                      let bounds = CGRect(dictionaryRepresentation: info) else { return false }
                return bounds.contains(area)
            }) { next.insert(scene.displayID) }
        }
        if covered != next { covered = next; updateActivity() }
    }
}
