import AppKit

/// Owns the `NSStatusItem` and renders the current `AppState` as an icon
/// glyph + tooltip.
@MainActor
final class StatusItemController {

    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let menu = NSMenu()

    /// Invoked when the user picks "Quit VoiceRider".
    var onQuit: () -> Void = {}

    /// Invoked when the user picks "Open Permission Settings…".
    var onOpenPermissions: () -> Void = {}

    init() {
        let permsItem = NSMenuItem(
            title: "Open Permission Settings…",
            action: #selector(permsAction),
            keyEquivalent: "")
        permsItem.target = self

        let quitItem = NSMenuItem(
            title: "Quit VoiceRider",
            action: #selector(quitAction),
            keyEquivalent: "q")
        quitItem.target = self

        menu.addItem(permsItem)
        menu.addItem(.separator())
        menu.addItem(quitItem)
        statusItem.menu = menu

        render(.idle)
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

    @objc private func permsAction() { onOpenPermissions() }
    @objc private func quitAction()  { onQuit() }
}
