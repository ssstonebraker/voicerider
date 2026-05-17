import AppKit
import AVFoundation
import IOKit.hid

/// Centralised TCC permission requests + Settings deep-links.
///
/// VoiceRider needs three TCC grants:
///   - Microphone        (record audio)
///   - Accessibility     (post synthetic Cmd+V; observe modifier keys)
///   - Input Monitoring  (CGEventTap on key events)
///
/// macOS 14+ also surfaces a Local Network prompt the first time we open a
/// connection to the LAN ASR host. That prompt is fired implicitly by the
/// first `URLSession` request — we do not request it here.
///
/// Sauron rule: this is the **single** source of truth for "is permission X
/// granted?" Other modules consult `Permissions` rather than calling
/// `AVCaptureDevice.authorizationStatus` / `AXIsProcessTrusted` /
/// `IOHIDCheckAccess` directly.
final class Permissions: MicrophoneStatusProviding {

    /// Triggers the standard mic prompt. Result is delivered asynchronously
    /// to the system-managed handler; we re-check on each record attempt
    /// via `microphoneStatus()`.
    func requestMicrophone() {
        AVCaptureDevice.requestAccess(for: .audio) { granted in
            Log.perms.log("mic granted=\(granted, privacy: .public)")
        }
    }

    /// Synchronous current authorization status for the microphone.
    /// Single source of truth — `AudioRecorder` consults this rather than
    /// calling `AVCaptureDevice.authorizationStatus(for:)` directly.
    func microphoneStatus() -> AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    /// Returns `true` if Accessibility is already granted. Passing
    /// `prompt: true` shows the system prompt the first time.
    @discardableResult
    func requestAccessibility(prompt: Bool = true) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let trusted = AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
        Log.perms.log("accessibility trusted=\(trusted, privacy: .public)")
        return trusted
    }

    /// Triggers the Input Monitoring prompt the first time. Subsequent calls
    /// return the current `IOHIDAccessType` cheaply.
    @discardableResult
    func requestInputMonitoring() -> IOHIDAccessType {
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        let access = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        Log.perms.log("input-monitoring access=\(access.rawValue, privacy: .public)")
        return access
    }

    /// Opens the three relevant System Settings panes so the user can grant
    /// or revoke permissions.
    func openSettingsPanes() {
        let urls = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent",
        ]
        for s in urls {
            if let url = URL(string: s) {
                NSWorkspace.shared.open(url)
            }
        }
    }
}

/// Test seam for mic-permission status. `AudioRecorder` depends on this
/// protocol rather than on the concrete `Permissions` class so unit tests
/// can inject a deterministic status.
protocol MicrophoneStatusProviding: AnyObject {
    func microphoneStatus() -> AVAuthorizationStatus
}
