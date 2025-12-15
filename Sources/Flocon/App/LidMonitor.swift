import Foundation
import IOKit
import IOKit.pwr_mgt

/// Receives lid changes from the power-management service without a polling timer.
final class LidMonitor {
    // kIOPMMessageClamshellStateChange is a C macro that Swift cannot import.
    private static let lidDidChange: UInt32 = 0xe00d0100
    private final class Listener { weak var owner: LidMonitor? }
    private let listener = Listener()
    private var service: io_service_t = 0
    private var notification: io_object_t = 0
    private var port: IONotificationPortRef?
    private var source: CFRunLoopSource?
    private(set) var isClosed = false
    var isMonitoring: Bool { notification != 0 && source != nil }
    var changed: () -> Void = {}

    init() {
        listener.owner = self
        service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return }
        if let port = IONotificationPortCreate(kIOMainPortDefault) {
            self.port = port
            let result = IOServiceAddInterestNotification(port, service, kIOGeneralInterest, { raw, _, message, _ in
                guard message == LidMonitor.lidDidChange, let raw else { return }
                Unmanaged<Listener>.fromOpaque(raw).takeUnretainedValue().owner?.refresh()
            }, Unmanaged.passUnretained(listener).toOpaque(), &notification)
            if result == KERN_SUCCESS {
                source = IONotificationPortGetRunLoopSource(port)?.takeUnretainedValue()
                if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
            }
        }
        refresh()
    }

    deinit {
        listener.owner = nil
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        if notification != 0 { IOObjectRelease(notification) }
        if let port { IONotificationPortDestroy(port) }
        if service != 0 { IOObjectRelease(service) }
    }

    func refresh() {
        guard service != 0 else { return }
        // Desktops have no lid property and remain eligible to animate.
        let value = IORegistryEntryCreateCFProperty(service, kAppleClamshellStateKey as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        let closed = (value as? NSNumber)?.boolValue ?? false
        if closed != isClosed { isClosed = closed; changed() }
    }
}
