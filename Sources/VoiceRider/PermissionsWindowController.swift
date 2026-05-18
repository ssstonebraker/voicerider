import AppKit

/// Owns the permissions-status window: live TCC grant state, deep-links
/// to System Settings panes, and auto-close once all three are granted.
///
/// ### Sauron compliance
///
///   - TCC queries go through `PermissionsSnapshot.current(perms:)` only.
///   - `Permissions.openSettingsPanes()` is deleted; per-pane open uses
///     `PermissionService.settingsURL` directly.
///   - This is the single "permissions UI" entry point — both the menu
///     item and the cdhash alert route here.
///
/// ### Annie compliance
///
///   Every public/internal method has at least one caller in Sources/ or
///   Tests/. `applySnapshot(_:)` is `internal` as a test seam.
@MainActor
final class PermissionsWindowController: NSWindowController, NSWindowDelegate {

    private let perms: Permissions
    private var refreshTimer: Timer?
    private var lastSnapshot: PermissionsSnapshot?
    private var rowViews: [PermissionService: PermissionRowView] = [:]
    private var disclosureDetail: NSTextField?
    private var consecutiveAllGrantedTicks = 0
    /// True if the opening snapshot was already all-granted (suppresses auto-close per H1).
    private var openedAllGranted = false
    private var repollWork: DispatchWorkItem?
    private var observersRegistered = false

    /// Fires from `windowWillClose` so the owner (AppDelegate) can drop
    /// its reference (single-instance invariant).
    var onClosed: () -> Void = {}

    init(perms: Permissions) {
        self.perms = perms

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 380),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false)
        window.title = "VoiceRider — Permissions"
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        window.delegate = self

        setupContent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }

    /// Opens the window and starts the 1 s refresh timer. Flips
    /// activation policy to `.regular` for the LSUIElement quirk.
    func show() {
        NSApplication.shared.setActivationPolicy(.regular)
        window?.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
        Trace.permsWindow("open", "")

        let snap = PermissionsSnapshot.current(perms: perms)
        openedAllGranted = snap.allGranted
        applySnapshot(snap)
        startTimer()
        if !observersRegistered {
            addObservers()
            observersRegistered = true
        }
    }

    /// Internal test seam: applies a snapshot and re-renders rows.
    func applySnapshot(_ snapshot: PermissionsSnapshot) {
        lastSnapshot = snapshot
        Trace.permsWindow("snap",
                          "mic=\(snapshot.microphone.granted) acc=\(snapshot.accessibility.granted) inp=\(snapshot.inputMonitoring.granted)")

        for status in snapshot.all {
            rowViews[status.service]?.render(status)
        }

        // Auto-close logic: only if we didn't open in all-granted state.
        if snapshot.allGranted && !openedAllGranted {
            consecutiveAllGrantedTicks += 1
            if consecutiveAllGrantedTicks >= 2, window?.isKeyWindow == false {
                Trace.permsWindow("autoclose", "")
                window?.close()
            }
        } else {
            consecutiveAllGrantedTicks = 0
        }
    }

    // MARK: NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        refreshTimer?.invalidate()
        refreshTimer = nil
        removeObservers()
        observersRegistered = false
        NSApplication.shared.setActivationPolicy(.accessory)
        onClosed()
    }

    // MARK: Private

    /// Observe system events that signal a TCC change. Apple's TCC database
    /// write is asynchronous — `AXIsProcessTrusted()` returns stale values if
    /// read immediately after the toggle. We observe two signals and re-poll
    /// after a short delay:
    ///
    ///   1. `com.apple.accessibility.api` distributed notification (fires when
    ///      Accessibility grants change — SO #63271532, Apple Forum #727984).
    ///   2. App-activation (catches all three permissions — the user was in
    ///      System Settings and switched back to VoiceRider).
    ///
    /// Both fire `delayedRepoll()` which waits 200 ms then reads fresh state.
    private func addObservers() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(accessibilityDidChange),
            name: NSNotification.Name("com.apple.accessibility.api"),
            object: nil)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidActivate),
            name: NSApplication.didBecomeActiveNotification,
            object: nil)
    }

    private func removeObservers() {
        DistributedNotificationCenter.default().removeObserver(self)
        NotificationCenter.default.removeObserver(self, name: NSApplication.didBecomeActiveNotification, object: nil)
    }

    @objc private func accessibilityDidChange(_ note: Notification) {
        Trace.permsWindow("ax-notify", "")
        delayedRepoll()
    }

    @objc private func appDidActivate(_ note: Notification) {
        Trace.permsWindow("app-activate", "")
        delayedRepoll()
    }

    /// Apple's TCC writes are async — immediate reads return stale data.
    /// Delay 200 ms then re-poll. Multiple calls within the window coalesce
    /// via the cancel-and-reschedule pattern.
    private func delayedRepoll() {
        repollWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let snap = PermissionsSnapshot.current(perms: self.perms)
                self.applySnapshot(snap)
            }
        }
        repollWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: work)
    }

    private func startTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let snap = PermissionsSnapshot.current(perms: self.perms)
                self.applySnapshot(snap)
            }
        }
    }

    private func setupContent() {
        guard let contentView = window?.contentView else { return }

        // Header
        let header = NSTextField(wrappingLabelWithString:
            "VoiceRider needs three macOS permissions to do its job. " +
            "After you toggle a permission in System Settings, this window updates automatically.")
        header.font = .systemFont(ofSize: 12)
        header.translatesAutoresizingMaskIntoConstraints = false

        // Disclosure triangle — ad-hoc signing caveat
        let disclosure = makeDisclosure()

        // Rows
        let rows = PermissionService.allCases.map { service -> PermissionRowView in
            let row = PermissionRowView(service: service)
            row.onAction = { [weak self] in self?.openPane(for: service) }
            rowViews[service] = row
            return row
        }

        // Close button
        let closeButton = NSButton(title: "Close", target: self, action: #selector(closeWindow))
        closeButton.keyEquivalent = "\u{1b}" // Esc
        closeButton.translatesAutoresizingMaskIntoConstraints = false

        // Main stack
        var views: [NSView] = [header, disclosure]
        views.append(contentsOf: rows)
        views.append(closeButton)

        let stack = NSStackView(views: views)
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            closeButton.trailingAnchor.constraint(equalTo: stack.trailingAnchor),
        ])

        // Row widths fill the stack
        for row in rows {
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
    }

    private func makeDisclosure() -> NSView {
        let disclosureButton = NSButton()
        disclosureButton.setButtonType(.pushOnPushOff)
        disclosureButton.bezelStyle = .disclosure
        disclosureButton.title = ""
        disclosureButton.translatesAutoresizingMaskIntoConstraints = false

        let summaryLabel = NSTextField(labelWithString: "Why does this need to be re-granted after every rebuild?")
        summaryLabel.font = .systemFont(ofSize: 11, weight: .medium)
        summaryLabel.translatesAutoresizingMaskIntoConstraints = false

        let detailLabel = NSTextField(wrappingLabelWithString:
            "Ad-hoc code signing produces a new identity hash for every build. " +
            "macOS resets Privacy & Security grants when that hash changes " +
            "(Apple DTS confirms this is by design — forum thread #795739). " +
            "You may need to re-grant Accessibility and Input Monitoring after each rebuild. " +
            "End users installing a release build are not affected.")
        detailLabel.font = .systemFont(ofSize: 11)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.isHidden = true
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.preferredMaxLayoutWidth = 500

        disclosureButton.target = self
        disclosureButton.action = #selector(toggleDisclosure(_:))

        let headerStack = NSStackView(views: [disclosureButton, summaryLabel])
        headerStack.orientation = .horizontal
        headerStack.spacing = 4
        headerStack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSStackView(views: [headerStack, detailLabel])
        container.orientation = .vertical
        container.alignment = .leading
        container.spacing = 4
        container.translatesAutoresizingMaskIntoConstraints = false

        self.disclosureDetail = detailLabel

        return container
    }

    @objc private func toggleDisclosure(_ sender: NSButton) {
        disclosureDetail?.isHidden.toggle()
    }

    private func openPane(for service: PermissionService) {
        guard let url = service.settingsURL else {
            Log.perms.error("No settings URL for \(service.rawValue, privacy: .public)")
            return
        }
        Trace.permsWindow("pane", "service=\(service.rawValue)")
        NSWorkspace.shared.open(url)
    }

    @objc private func closeWindow() {
        window?.close()
    }
}
