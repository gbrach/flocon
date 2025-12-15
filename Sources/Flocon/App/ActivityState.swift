struct ActivityState {
    var enabled = true
    var lidClosed = false
    var systemSleeping = false
    var displaysSleeping = false
    var locked = false
    var sessionInactive = false

    var isRunning: Bool {
        enabled && !lidClosed && !systemSleeping && !displaysSleeping && !locked && !sessionInactive
    }
}
