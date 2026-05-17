import Testing
import Foundation
import IOKit.hid
@testable import VoiceRider

/// R2 verification — `Permissions.inputMonitoringStatus()` is the
/// query-only path. Cannot trigger an `IOHIDRequestAccess` prompt.
///
/// This test cannot mechanically observe whether a prompt fires (that
/// would require a UI test target with screen access), but it CAN
/// verify the contract by inspection: the implementation returns
/// `IOHIDCheckAccess(...)` directly and never calls
/// `IOHIDRequestAccess(...)`. This file pins the contract by a
/// behavioral round-trip — calling the method many times in a tight
/// loop should never block on user input.
@Suite("Permissions")
struct PermissionsTests {

    @Test("inputMonitoringStatus returns one of the documented IOHIDAccessType values")
    func returnsKnownAccessType() {
        let perms = Permissions()
        let status = perms.inputMonitoringStatus()
        let known: [IOHIDAccessType] = [
            kIOHIDAccessTypeGranted,
            kIOHIDAccessTypeDenied,
            kIOHIDAccessTypeUnknown,
        ]
        #expect(known.contains(status))
    }

    @Test("inputMonitoringStatus is fast — 10 calls under 5s (no UI prompt)")
    func fast() {
        let perms = Permissions()
        let start = Date()
        for _ in 0..<10 {
            _ = perms.inputMonitoringStatus()
        }
        let elapsed = Date().timeIntervalSince(start)
        // If a prompt fires, the test blocks indefinitely. 5s is generous;
        // IOHIDCheckAccess takes ~10ms per kernel round-trip on Apple Silicon.
        #expect(elapsed < 5.0, "elapsed=\(elapsed)s — prompts may have fired")
    }

    @Test("inputMonitoringStatus is deterministic between back-to-back calls")
    func deterministic() {
        let perms = Permissions()
        let a = perms.inputMonitoringStatus()
        let b = perms.inputMonitoringStatus()
        #expect(a == b)
    }

    @Test("microphoneStatus is one of the documented AVAuthorizationStatus values")
    func micStatusKnown() {
        let perms = Permissions()
        let status = perms.microphoneStatus()
        let known: [AVAuthorizationStatus] = [
            .notDetermined, .restricted, .denied, .authorized,
        ]
        #expect(known.contains(status))
    }
}

import AVFoundation
