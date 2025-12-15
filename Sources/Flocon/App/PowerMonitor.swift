import Foundation
import IOKit.ps

enum PowerBudget {
    case full, battery, saver
    var density: Float {
        switch self { case .full: 1; case .battery: 0.85; case .saver: 0.6 }
    }
    static func resolve(manual: Bool, lowPower: Bool, hot: Bool, battery: Bool) -> PowerBudget {
        if manual || lowPower || hot { return .saver }
        return battery ? .battery : .full
    }
}

final class PowerMonitor {
    private final class BatteryListener { weak var owner: PowerMonitor? }
    private let listener = BatteryListener()
    private var batterySource: CFRunLoopSource?
    private var subscriptions: [NSObjectProtocol] = []
    private(set) var budget: PowerBudget = .full
    var changed: () -> Void = {}
    var forceSaver = false { didSet { refresh() } }

    init() {
        listener.owner = self
        let raw = Unmanaged.passUnretained(listener).toOpaque()
        batterySource = IOPSNotificationCreateRunLoopSource({ raw in
            guard let raw else { return }
            Unmanaged<BatteryListener>.fromOpaque(raw).takeUnretainedValue().owner?.refresh()
        }, raw)?.takeRetainedValue()
        if let batterySource { CFRunLoopAddSource(CFRunLoopGetMain(), batterySource, .commonModes) }
        let center = NotificationCenter.default
        subscriptions = [ProcessInfo.thermalStateDidChangeNotification, .NSProcessInfoPowerStateDidChange].map { event in
            center.addObserver(forName: event, object: nil, queue: .main) { [weak self] _ in self?.refresh() }
        }
        refresh()
    }
    deinit {
        listener.owner = nil
        subscriptions.forEach { NotificationCenter.default.removeObserver($0) }
        if let batterySource { CFRunLoopRemoveSource(CFRunLoopGetMain(), batterySource, .commonModes) }
    }
    private func refresh() {
        let process = ProcessInfo.processInfo
        var battery = false
        if let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let source = IOPSGetProvidingPowerSourceType(snapshot)?.takeUnretainedValue() {
            battery = (source as String) == kIOPMBatteryPowerKey
        }
        let proposed = PowerBudget.resolve(manual: forceSaver, lowPower: process.isLowPowerModeEnabled, hot: process.thermalState == .serious || process.thermalState == .critical, battery: battery)
        if proposed != budget { budget = proposed; changed() }
    }
}
