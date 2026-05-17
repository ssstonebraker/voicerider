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
///
/// ### R2 — request vs query
///
/// Two flavours per service:
///
///   - `request*()` — may trigger a system prompt the first time
///     (calls `IOHIDRequestAccess`, `AVCaptureDevice.requestAccess`,
///     or passes `prompt: true` to `AXIsProcessTrustedWithOptions`).
///   - `*Status()` — query-only, never prompts. Safe to call on every
///     status-menu render.
///
/// `PermissionsSnapshot.current(perms:)` uses ONLY the `*Status()`
/// flavour so re-rendering the menu does not nudge the user into a
/// prompt loop.
final class Permissions: MicrophoneStatusProviding {

    /// Triggers the standard mic prompt. Result is delivered asynchronously.
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
    ///
    /// **Belt-and-suspenders:** calls BOTH `IOHIDRequestAccess` (IOKit)
    /// AND `CGRequestListenEventAccess` (Quartz). These hit different
    /// TCC code paths; ad-hoc-signed LSUIElement apps sometimes fail to
    /// trigger the prompt via one but succeed via the other. Calling
    /// both maximizes the chance the user sees the prompt on first
    /// launch.
    ///
    /// References:
    ///  - Apple DTS thread #795739 — ad-hoc signing has no stable
    ///    designated requirement, so TCC re-prompts on rebuild.
    ///  - Apple Forum thread #128641 — Apple bug r.55284204: Input
    ///    Monitoring `+` button hidden when list empty.
    @discardableResult
    func requestInputMonitoring() -> IOHIDAccessType {
        _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        // Quartz Event Services equivalent — different code path,
        // sometimes triggers the prompt when IOHIDRequestAccess alone
        // does not (especially for LSUIElement apps).
        _ = CGRequestListenEventAccess()
        let access = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        Log.perms.log("input-monitoring access=\(access.rawValue, privacy: .public)")
        return access
    }

    /// R2: query-only path. Does NOT call `IOHIDRequestAccess` (which
    /// can prompt). Safe to invoke from a status-menu render every time
    /// the menu opens.
    func inputMonitoringStatus() -> IOHIDAccessType {
        IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
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
