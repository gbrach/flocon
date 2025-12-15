import MetalKit
import Testing
@testable import Flocon

struct ActivityTests {
    @MainActor @Test func lidWatcherRegistersWithThePowerService() {
        let monitor = LidMonitor()
        #expect(monitor.isMonitoring)
    }

    @Test func eachPauseReasonStopsAnimation() {
        let reasons: [WritableKeyPath<ActivityState, Bool>] = [
            \.lidClosed, \.systemSleeping, \.displaysSleeping, \.locked, \.sessionInactive,
        ]
        for reason in reasons {
            var state = ActivityState()
            #expect(state.isRunning)
            state[keyPath: reason] = true
            #expect(!state.isRunning)
            state[keyPath: reason] = false
            #expect(state.isRunning)
        }
        var disabled = ActivityState()
        disabled.enabled = false
        #expect(!disabled.isRunning)
    }

    @Test func wakingDoesNotOverrideAClosedLidOrSleepingDisplays() {
        var state = ActivityState()
        state.lidClosed = true
        state.systemSleeping = true
        state.displaysSleeping = true
        state.locked = true
        state.systemSleeping = false
        #expect(!state.isRunning)
        state.displaysSleeping = false
        #expect(!state.isRunning)
        state.lidClosed = false
        #expect(!state.isRunning)
        state.locked = false
        #expect(state.isRunning)
    }

    @Test func openingLidDoesNotOverrideDisabledPreference() {
        var state = ActivityState()
        state.enabled = false
        state.lidClosed = true
        state.lidClosed = false
        #expect(!state.isRunning)
        state.enabled = true
        #expect(state.isRunning)
    }

    @MainActor @Test(.enabled(if: MTLCreateSystemDefaultDevice() != nil))
    func queuedDrawsWhilePausedDoNotPollWindowsOrStepPhysics() throws {
        let device = try #require(MTLCreateSystemDefaultDevice())
        let simulation = SnowSimulation(width: 800, height: 600, snowfall: .moderate, seed: 1)
        let renderer = try Renderer(device: device, pixelFormat: .bgra8Unorm, simulation: simulation)
        let view = MTKView(frame: .zero, device: device)
        view.isPaused = true
        defer { view.isPaused = true }
        var polls = 0
        renderer.windowSurfaces = { _ in polls += 1; return nil }
        renderer.lightsVisible = true
        renderer.isActive = true
        renderer.draw(in: view)
        renderer.isActive = false
        view.isPaused = false
        renderer.draw(in: view)
        #expect(polls == 0)
        #expect(simulation.spriteCount == 0)
    }
}
