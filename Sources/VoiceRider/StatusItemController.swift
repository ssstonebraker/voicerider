import AppKit

/// Owns the `NSStatusItem` and renders the current `AppState` as an icon
/// glyph + tooltip, plus a Permissions submenu showing live ✓/✗ for
/// Microphone, Accessibility, and Input Monitoring (P1) with a
/// "Re-check Permissions" item (P2).
@MainActor
final class StatusItemController {

    private let perms: Permissions
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()
    private let permsSubmenu = NSMenu()
    private let permsRoot = NSMenuItem(title: "Permissions", action: nil, keyEquivalent: "")
    private let recheckItem = NSMenuItem(title: "Re-check Permissions",
                                          action: #selector(recheckAction),
                                          keyEquivalent: "")
    private let traceItem = NSMenuItem(title: "Show Live Trace…",
                                       action: #selector(traceAction),
                                       keyEquivalent: "")
    private let openPermsItem = NSMenuItem(title: "Open Permission Settings…",
                                           action: #selector(permsAction),
                                           keyEquivalent: "")
    private let quitItem = NSMenuItem(title: "Quit VoiceRider",
                                      action: #selector(quitAction),
                                      keyEquivalent: "q")

    /// Current snapshot — re-rendered whenever `refreshPermissions()` is called.
    private var snapshot: PermissionsSnapshot?

    /// Invoked when the user picks "Quit VoiceRider".
    var onQuit: () -> Void = {}

    /// Invoked when the user picks "Open Permission Settings…" (legacy — opens all panes).
    var onOpenPermissions: () -> Void = {}

    /// Invoked when the user picks "Re-check Permissions".
    var onRecheckPermissions: () -> Void = {}

    /// Invoked when the user picks "Show Live Trace…".
    var onShowTrace: () -> Void = {}

    init(perms: Permissions) {
        self.perms = perms

        recheckItem.target = self
        traceItem.target = self
        openPermsItem.target = self
        quitItem.target = self

        permsRoot.submenu = permsSubmenu

        menu.addItem(permsRoot)
        menu.addItem(recheckItem)
        menu.addItem(.separator())
        menu.addItem(traceItem)
        menu.addItem(openPermsItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)
        statusItem.menu = menu

        render(.idle)
        refreshPermissions()
    }

    /// Renders the given state. Idempotent — calling repeatedly with the
    /// same state is cheap and visually stable.
    func render(_ state: AppState) {
        let glyph: String
        let tip: String
        switch state {
        case .idle:
            glyph = "mic"
            tip = "VoiceRider — idle"
        case .arming:
            glyph = "mic.circle"
            tip = "VoiceRider — arming"
        case .recording:
            glyph = "mic.fill"
            tip = "VoiceRider — recording"
        case .transcribing:
            glyph = "waveform"
            tip = "VoiceRider — transcribing"
        case .pasting:
            glyph = "doc.on.clipboard"
            tip = "VoiceRider — pasting"
        case .error(let msg):
            glyph = "exclamationmark.triangle"
            tip = "VoiceRider — error: \(msg)"
        }
        if let img = NSImage(systemSymbolName: glyph, accessibilityDescription: tip) {
            img.isTemplate = true
            statusItem.button?.image = img
        }
        statusItem.button?.toolTip = tip
    }

    /// P1+P2: re-query TCC and rebuild the Permissions submenu.
    func refreshPermissions() {
        let snap = PermissionsSnapshot.current(perms: perms)
        snapshot = snap

        permsSubmenu.removeAllItems()
        for status in snap.all {
            let item = NSMenuItem(
                title: status.menuTitle,
                action: #selector(openServicePane(_:)),
                keyEquivalent: "")
            item.target = self
            item.representedObject = status.service.rawValue
            // R3: keep all rows clickable. Even a granted row is useful
            // — clicking opens the relevant Settings pane so the user
            // can verify or revoke without hunting.
            item.isEnabled = true
            permsSubmenu.addItem(item)
        }
        // Adjust the parent label to show overall state.
        if snap.allGranted {
            permsRoot.title = "Permissions ✓"
        } else if let missing = snap.firstMissing {
            permsRoot.title = "Permissions — fix \(missing.service.label)"
        } else {
            permsRoot.title = "Permissions"
        }

        Trace.perms("snapshot",
                    "mic=\(snap.microphone.granted) acc=\(snap.accessibility.granted) inp=\(snap.inputMonitoring.granted)")
    }

    @objc private func openServicePane(_ sender: NSMenuItem) {
        guard
            let raw = sender.representedObject as? String,
            let service = PermissionService(rawValue: raw),
            let url = service.settingsURL
        else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func recheckAction() {
        onRecheckPermissions()
    }

    @objc private func traceAction()  { onShowTrace() }
    @objc private func permsAction()  { onOpenPermissions() }
    @objc private func quitAction()   { onQuit() }
}
