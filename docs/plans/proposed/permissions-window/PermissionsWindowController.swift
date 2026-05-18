import AppKit

/// Owns the permissions status window. Three TCC rows, each showing
/// live grant state (polled every 1 s), a user-task-shaped description,
/// and a deep-link button to the exact System Settings sub-pane.
///
/// ### Design decisions (DCR)
///
/// **Decompose.** The window renders a `PermissionsSnapshot` — the same
/// type the menu-bar submenu already uses. No new TCC query path; this
/// window is a richer view of the same data. (Sauron.)
///
/// **Critique.** The 1 s timer could leak if `init` runs but `show()`
/// never fires. Fix: timer starts in `show()`, not `init`.
/// Auto-close after grants could surprise the user mid-click; fix:
/// two-tick debounce + key-window check.
///
/// **Refine.** The window is fixed-width, non-resizable, 3 rows.
/// Disclosure triangle at the top explains ad-hoc-signing's effect
/// on TCC (the #1 source of first-run confusion after a rebuild).
///
/// ### Sauron compliance
///
/// - The only TCC query path is `PermissionsSnapshot.current(perms:)`.
/// - The single owner of this window is `AppDelegate.permissionsWC`.
/// - "Open Permission Settings…" in the menu calls
///   `AppDelegate.openPermissionsWindow()` which routes here.
///   `perms.openSettingsPanes()` (the old path) is no longer the
///   primary user-visible entry point.
///
/// ### Annie compliance
///
/// Every method, property, and nested type here has at least one
/// caller in `Sources/VoiceRider/` or `Tests/VoiceRiderTests/`. The
/// `applySnapshot(_:)` method is `internal` so tests can drive the
/// snapshot loop deterministically without relying on `Timer`.
@MainActor
final class PermissionsWindowController: NSWindowController, NSWindowDelegate {

    // MARK: Dependencies

    private let perms: Permissions

    // MARK: State

    private var refreshTimer: Timer?
    private var lastSnapshot: PermissionsSnapshot?
    private var consecutiveAllGrantedTicks = 0
    private var rowViews: [PermissionService: PermissionRowView] = [:]

    // MARK: Callbacks

    /// Fires from `windowWillClose` so AppDelegate can nil out its
    /// single-instance reference.
    var onClosed: () -> Void = {}

    // MARK: Init

    init(perms: Permissions) {
        self.perms = perms

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 580, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false)
        window.title = "VoiceRider — Permissions"
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        window.delegate = self

        configureUI()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: Show / Close

    /// Opens the window and starts the 1 s refresh timer. Flips
    /// activation policy to `.regular` for LSUIElement key-window
    /// acquisition (same pattern as SettingsWindowController).
    func show() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)

        // Immediate first render.
        let snap = PermissionsSnapshot.current(perms: perms)
        applySnapshot(snap)

        // 1 s polling.
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let snap = PermissionsSnapshot.current(perms: self.perms)
            self.applySnapshot(snap)
        }
        Trace.permsWindow("open", "")
    }

    func windowWillClose(_ notification: Notification) {
        refreshTimer?.invalidate()
        refreshTimer = nil
        NSApp.setActivationPolicy(.accessory)
        onClosed()
    }

    // MARK: Snapshot application (internal for testability)

    /// Applies a snapshot: diffs against `lastSnapshot`, re-renders
    /// only the rows that changed. Drives auto-close logic.
    ///
    /// `internal` (not private) so tests can call it directly via
    /// `@testable import VoiceRider` without involving Timer.
    func applySnapshot(_ snap: PermissionsSnapshot) {
        Trace.permsWindow("snap",
                          "mic=\(snap.microphone.granted) acc=\(snap.accessibility.granted) inp=\(snap.inputMonitoring.granted)")

        // Diff and render.
        for status in snap.all {
            guard let row = rowViews[status.service] else { continue }
            let prev = lastSnapshot?.all.first { $0.service == status.service }
            if prev == nil || prev?.granted != status.granted {
                row.render(status)
            }
        }
        lastSnapshot = snap

        // Auto-close debounce.
        if snap.allGranted {
            consecutiveAllGrantedTicks += 1
        } else {
            consecutiveAllGrantedTicks = 0
        }
        if consecutiveAllGrantedTicks >= 2,
           let w = window, !w.isKeyWindow {
            Trace.permsWindow("autoclose", "")
            w.close()
        }
    }

    // MARK: UI building

    private func configureUI() {
        guard let contentView = window?.contentView else { return }

        // Header text.
        let header = NSTextField(wrappingLabelWithString:
            "VoiceRider needs three macOS permissions to do its job. " +
            "Below shows the live state — after you toggle a permission " +
            "in System Settings, this window updates automatically.")
        header.font = .systemFont(ofSize: 12)
        header.textColor = .secondaryLabelColor

        // Disclosure triangle: ad-hoc signing caveat.
        let disclosureButton = NSButton(
            title: "Why does this need to be re-granted after every rebuild?",
            target: self, action: #selector(toggleDisclosure(_:)))
        disclosureButton.bezelStyle = .disclosure
        disclosureButton.setButtonType(.pushOnPushOff)
        disclosureButton.state = .off

        let disclosureText = NSTextField(wrappingLabelWithString:
            "VoiceRider is ad-hoc code signed. Every rebuild produces a new " +
            "code-directory hash, so macOS treats it as a brand-new app and " +
            "resets previously granted permissions. This is an Apple-documented " +
            "limitation of ad-hoc signing (DTS forum #795739). To avoid this, " +
            "sign with a Developer ID ($99/year) — until then, re-grant after " +
            "each rebuild by removing and re-adding VoiceRider in the relevant " +
            "Privacy & Security pane.")
        disclosureText.font = .systemFont(ofSize: 11)
        disclosureText.textColor = .tertiaryLabelColor
        disclosureText.isHidden = true
        disclosureText.tag = 999  // for toggle lookup

        // Permission rows.
        var rows: [NSView] = []
        for service in PermissionService.allCases {
            let row = PermissionRowView(service: service)
            row.onAction = { [weak self] in self?.openPane(for: service) }
            rowViews[service] = row
            rows.append(row)
        }

        // Close button.
        let closeButton = NSButton(title: "Close", target: self, action: #selector(closeTapped))
        closeButton.bezelStyle = .rounded
        closeButton.keyEquivalent = "\u{1b}"  // Esc

        let buttonRow = NSStackView(views: [NSView(), closeButton])
        buttonRow.orientation = .horizontal

        // Assemble.
        var allViews: [NSView] = [header, disclosureButton, disclosureText]
        allViews.append(contentsOf: rows)
        allViews.append(buttonRow)

        let stack = NSStackView(views: allViews)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
        ])

        for row in rows {
            row.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -48).isActive = true
        }
    }

    // MARK: Actions

    private func openPane(for service: PermissionService) {
        guard let url = service.settingsURL else { return }
        let ok = NSWorkspace.shared.open(url)
        if !ok {
            Log.perms.error("Could not open settings URL for \(service.rawValue, privacy: .public)")
        }
        Trace.permsWindow("pane", "service=\(service.rawValue)")
    }

    @objc private func closeTapped() {
        window?.close()
    }

    @objc private func toggleDisclosure(_ sender: NSButton) {
        guard let contentView = window?.contentView else { return }
        // Find the disclosure text by tag.
        func findByTag(_ view: NSView, tag: Int) -> NSView? {
            if view.tag == tag { return view }
            for sub in view.subviews {
                if let found = findByTag(sub, tag: tag) { return found }
            }
            return nil
        }
        if let text = findByTag(contentView, tag: 999) {
            text.isHidden = (sender.state == .off)
        }
    }
}

// MARK: - Trace

extension Trace {
    /// Trace ingress for `trace:perms-window-*` events.
    static func permsWindow(_ event: String, _ payload: String) {
        emit("trace:perms-window-\(event)", payload)
    }
}
