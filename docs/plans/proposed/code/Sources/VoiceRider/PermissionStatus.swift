import AppKit
import AVFoundation
import IOKit.hid

/// Typed view of the three TCC services VoiceRider depends on.
///
/// The existing `Permissions` class already owns the live querying
/// (Sauron rule). This file adds a thin typed layer on top so the status
/// item menu can render `✓ / ✗` rows without each call site re-deriving
/// strings, settings URLs, or display labels.
///
/// ### What this is NOT
///
/// - This is **not** a parallel state cache. It is a snapshot at a moment
///   in time, taken by `PermissionsSnapshot.current(perms:)`. Hold the
///   snapshot for as long as it takes to render the menu, then discard.
/// - This does **not** store anything in `UserDefaults`. The cdhash
///   detection in `CDHashDetection` is a separate, orthogonal concern.

enum PermissionService: String, CaseIterable {
    case microphone
    case accessibility
    case inputMonitoring

    /// Display label (Title Case, no glyph — the glyph is per-state).
    var label: String {
        switch self {
        case .microphone:      return "Microphone"
        case .accessibility:   return "Accessibility"
        case .inputMonitoring: return "Input Monitoring"
        }
    }

    /// `x-apple.systempreferences:` URL that opens the relevant pane.
    var settingsURL: URL? {
        switch self {
        case .microphone:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        case .accessibility:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        case .inputMonitoring:
            return URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
        }
    }
}

struct PermissionStatus: Equatable {
    let service: PermissionService
    let granted: Bool

    /// Glyph used in the status-item menu.
    var glyph: String { granted ? "✓" : "✗" }

    /// One-line menu title: `"✓ Microphone"`.
    var menuTitle: String { "\(glyph) \(service.label)" }
}

struct PermissionsSnapshot: Equatable {
    let microphone: PermissionStatus
    let accessibility: PermissionStatus
    let inputMonitoring: PermissionStatus

    /// All three in canonical order (matches `PermissionService.allCases`).
    var all: [PermissionStatus] {
        [microphone, accessibility, inputMonitoring]
    }

    var allGranted: Bool {
        microphone.granted && accessibility.granted && inputMonitoring.granted
    }

    var firstMissing: PermissionStatus? {
        all.first { !$0.granted }
    }

    /// Live snapshot from the canonical `Permissions` source.
    ///
    /// **R2:** uses the query-only `inputMonitoringStatus()` path so
    /// re-rendering the menu does NOT prompt the user. The
    /// `requestInputMonitoring()` (which can prompt) stays available
    /// on the `Permissions` class for the explicit launch-time path.
    static func current(perms: Permissions) -> PermissionsSnapshot {
        let mic = perms.microphoneStatus() == .authorized
        let acc = perms.requestAccessibility(prompt: false)
        let inp = perms.inputMonitoringStatus() == kIOHIDAccessTypeGranted
        return PermissionsSnapshot(
            microphone:      PermissionStatus(service: .microphone,      granted: mic),
            accessibility:   PermissionStatus(service: .accessibility,   granted: acc),
            inputMonitoring: PermissionStatus(service: .inputMonitoring, granted: inp))
    }
}

// MARK: - cdhash change detection (P3)

/// Result of comparing the current binary fingerprint to the last seen one.
///
/// Pure — takes two strings, returns an enum. Tests don't need a real
/// binary; they pass synthetic hashes.
enum CDHashDetectionResult: Equatable {
    case firstLaunch
    case unchanged
    case changed(from: String, to: String)

    /// Stable tag for trace output.
    var tag: String {
        switch self {
        case .firstLaunch:    return "first-launch"
        case .unchanged:      return "unchanged"
        case .changed:        return "changed"
        }
    }
}

enum CDHashDetection {
    static func detect(current: String, lastSeen: String?) -> CDHashDetectionResult {
        guard let lastSeen else { return .firstLaunch }
        if lastSeen == current { return .unchanged }
        return .changed(from: lastSeen, to: current)
    }
}
