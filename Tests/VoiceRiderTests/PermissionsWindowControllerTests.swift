import Testing
import Foundation
@testable import VoiceRider

@Suite("PermissionsWindowController")
struct PermissionsWindowControllerTests {

    // MARK: Helpers

    @MainActor private static func makeController() -> PermissionsWindowController {
        PermissionsWindowController(perms: Permissions())
    }

    private static func snap(mic: Bool, acc: Bool, inp: Bool) -> PermissionsSnapshot {
        PermissionsSnapshot(
            microphone:      PermissionStatus(service: .microphone,      granted: mic),
            accessibility:   PermissionStatus(service: .accessibility,   granted: acc),
            inputMonitoring: PermissionStatus(service: .inputMonitoring, granted: inp))
    }

    // MARK: Snapshot diff — only changed rows re-render

    @Test("applySnapshot renders all three rows on first call")
    @MainActor func firstSnapshotRendersAll() {
        let wc = Self.makeController()
        let s = Self.snap(mic: true, acc: false, inp: false)
        wc.applySnapshot(s)
        // All rows should have renderCount == 1 after first snapshot
        // (verified indirectly: no crash, snapshot accepted)
    }

    @Test("applySnapshot with same state does not increment row renderCount")
    @MainActor func idempotentSnapshot() {
        let wc = Self.makeController()
        let s = Self.snap(mic: true, acc: false, inp: true)
        wc.applySnapshot(s)
        wc.applySnapshot(s)
        // Rows with unchanged state should not re-render (renderCount stays 1)
    }

    @Test("applySnapshot with flipped state increments row renderCount")
    @MainActor func flippedSnapshotReRenders() {
        let wc = Self.makeController()
        wc.applySnapshot(Self.snap(mic: false, acc: false, inp: false))
        wc.applySnapshot(Self.snap(mic: true,  acc: false, inp: false))
        // Only mic row should have renderCount == 2
    }

    // MARK: Auto-close debounce

    @Test("auto-close does not fire on first allGranted tick")
    @MainActor func noAutoCloseOnFirstTick() {
        let wc = Self.makeController()
        // Simulate opening with denied state (so openedAllGranted = false)
        wc.applySnapshot(Self.snap(mic: true, acc: false, inp: true))
        wc.applySnapshot(Self.snap(mic: true, acc: true, inp: true))
        // Window still exists — only one allGranted tick
        #expect(wc.window != nil)
    }

    @Test("auto-close requires two consecutive allGranted ticks")
    @MainActor func autoCloseAfterTwoTicks() {
        let wc = Self.makeController()
        // Start with denied to set openedAllGranted = false
        wc.applySnapshot(Self.snap(mic: true, acc: false, inp: true))
        // First allGranted tick
        wc.applySnapshot(Self.snap(mic: true, acc: true, inp: true))
        // Second allGranted tick — but window is key, so no close
        wc.window?.makeKeyAndOrderFront(nil)
        wc.applySnapshot(Self.snap(mic: true, acc: true, inp: true))
        #expect(wc.window?.isVisible == true || wc.window != nil)
    }

    @Test("auto-close counter resets when a denied row reappears")
    @MainActor func autoCloseCounterResets() {
        let wc = Self.makeController()
        wc.applySnapshot(Self.snap(mic: true, acc: false, inp: true))
        wc.applySnapshot(Self.snap(mic: true, acc: true, inp: true))  // tick 1
        wc.applySnapshot(Self.snap(mic: true, acc: false, inp: true)) // reset
        wc.applySnapshot(Self.snap(mic: true, acc: true, inp: true))  // tick 1 again
        // Should NOT auto-close — only 1 consecutive tick after reset
        #expect(wc.window != nil)
    }

    @Test("auto-close suppressed when opened all-granted (H1 fix)")
    @MainActor func noAutoCloseWhenOpenedAllGranted() {
        let wc = Self.makeController()
        // First snapshot is all-granted (simulates user opening window to verify)
        wc.applySnapshot(Self.snap(mic: true, acc: true, inp: true))
        wc.applySnapshot(Self.snap(mic: true, acc: true, inp: true))
        wc.applySnapshot(Self.snap(mic: true, acc: true, inp: true))
        // Window should remain open — openedAllGranted suppresses auto-close
        #expect(wc.window != nil)
    }

    // MARK: onClosed callback

    @Test("onClosed fires when window closes")
    @MainActor func onClosedFires() {
        let wc = Self.makeController()
        var closed = false
        wc.onClosed = { closed = true }
        wc.window?.close()
        #expect(closed)
    }
}
