import AppKit

/// Owns the single AppKit settings window. Pure AppKit, programmatic
/// auto-layout, no SwiftUI (the project is AppKit-only — Sauron rule).
///
/// ### State model (Sauron — single source of truth)
///
/// `UserDefaults` is the persisted source of truth, accessed via
/// `ServerConfig.load()` / `ServerConfig.save()`. The window itself
/// holds two transient values:
///
///   - `initialForm` — snapshot at open time, used to detect "is the
///     form dirty?" for the Cmd-Q / X confirm path (C17).
///   - `form` — the live in-memory edit buffer, mirrored from each
///     `NSTextField` via `controlTextDidChange`.
///
/// `AppDelegate.transcriber` is rebuilt from `ServerConfig` after Save.
/// Nothing else maintains a parallel copy.
///
/// ### Annie compliance
///
/// `SettingsWindowController` does **not** take a `Permissions`
/// parameter. The original plan had a `private let perms` field
/// "reserved for future use" — that was an orphan and was removed
/// during review. If a permissions panel ever lands in this window,
/// that PR adds the field.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {

    // MARK: Dependencies (injected for testability)

    private let transcriberFactory: @Sendable (ServerConfig) throws -> Transcriber

    // MARK: State

    private let initialForm: SettingsForm
    private var form: SettingsForm
    private var savedConfig: ServerConfig?
    private var probeTask: URLSessionDataTask?
    private var probeTranscriber: Transcriber?

    // MARK: Callbacks

    /// Fires on Save with the new (validated, distinct-from-initial)
    /// config. Caller (AppDelegate) is responsible for persistence
    /// via `ServerConfig.save` and Transcriber rebuild.
    var onSave: (ServerConfig) -> Void = { _ in }

    /// Fires from `windowWillClose` so the owner can drop its
    /// reference (single-instance invariant on AppDelegate).
    var onClosed: () -> Void = {}

    // MARK: UI elements

    private let urlField = NSTextField()
    private let modelField = NSTextField()
    private let bearerField = NSSecureTextField()
    private let urlStatus = NSTextField(labelWithString: "")
    private let modelStatus = NSTextField(labelWithString: "")
    private let bearerStatus = NSTextField(labelWithString: "")
    private let testButton = NSButton(title: "Test Connection",
                                       target: nil, action: nil)
    private let testSpinner = NSProgressIndicator()
    private let testStatus = NSTextField(wrappingLabelWithString: "")
    private let saveButton = NSButton(title: "Save",
                                       target: nil, action: nil)
    private let cancelButton = NSButton(title: "Cancel",
                                         target: nil, action: nil)

    // MARK: Init

    init(initial: ServerConfig,
         transcriberFactory: @escaping @Sendable (ServerConfig) throws -> Transcriber
            = { cfg in
                try Transcriber(endpoint: cfg.endpoint,
                                model: cfg.model,
                                bearer: cfg.bearer)
            }) {
        let initialForm = SettingsForm.from(initial)
        self.initialForm = initialForm
        self.form = initialForm
        self.transcriberFactory = transcriberFactory

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 540, height: 360),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false)
        window.title = "VoiceRider — Settings"
        window.isReleasedWhenClosed = false
        window.center()

        super.init(window: window)
        window.delegate = self

        configureUI()
        renderForm()
        Trace.settings("load",
                       "urlOk=\(initialForm.isEndpointValid) modelOk=\(initialForm.isModelValid) bearerOk=\(initialForm.isBearerValid)")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    // MARK: Show / dismiss

    /// Opens (or re-fronts) the window. Flips the activation policy
    /// to `.regular` so the window can claim key-window status from
    /// an LSUIElement process; flips back to `.accessory` in
    /// `windowWillClose`.
    func show() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: NSWindowDelegate

    /// C17: Cmd-Q + window-X both reach this hook. If the user has
    /// unsaved edits, present a confirm sheet before tearing down.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard isDirty, savedConfig == nil else { return true }

        let alert = NSAlert()
        alert.messageText = "Discard changes?"
        alert.informativeText = "You have unsaved changes to your server configuration. Closing the window will discard them."
        alert.addButton(withTitle: "Discard")
        alert.addButton(withTitle: "Keep Editing")

        let response = alert.runModal()
        // First button (.alertFirstButtonReturn) → Discard → close.
        return response == .alertFirstButtonReturn
    }

    func windowWillClose(_ notification: Notification) {
        probeTask?.cancel()
        probeTask = nil
        probeTranscriber = nil
        NSApp.setActivationPolicy(.accessory)
        onClosed()
    }

    // MARK: Field-change wiring

    @objc private func fieldChanged(_ sender: NSTextField) {
        // NSSecureTextField inherits from NSTextField; share one path.
        if sender === urlField {
            form.endpointString = sender.stringValue
        } else if sender === modelField {
            form.model = sender.stringValue
        } else if sender === bearerField {
            form.bearer = sender.stringValue
        }
        renderValidation()
    }

    @objc private func testTapped() {
        runProbe()
    }

    @objc private func saveTapped() {
        guard form.isValid else { return }   // belt-and-suspenders; button should be disabled
        do {
            let new = try form.resolve()
            // R2 — short-circuit no-op saves.
            let current = ServerConfig.load()
            if new == current {
                savedConfig = current
                onSave(current)
                Trace.settings("save", "")
                window?.close()
                return
            }
            ServerConfig.save(new)
            savedConfig = new
            onSave(new)
            Trace.settings("save", "")
            window?.close()
        } catch {
            // Validate-before-save is enforced via isEnabled; if we
            // ever land here, surface the error inline rather than
            // crashing or persisting bad state.
            testStatus.stringValue = "Cannot save: \(error)"
            testStatus.textColor = .systemRed
        }
    }

    @objc private func cancelTapped() {
        window?.close()
    }

    // MARK: Probe

    private func runProbe() {
        guard form.isValid else { return }

        let cfg: ServerConfig
        do { cfg = try form.resolve() } catch {
            testStatus.stringValue = "Invalid config; fix the highlighted field."
            testStatus.textColor = .systemRed
            return
        }

        let transcriber: Transcriber
        do {
            transcriber = try transcriberFactory(cfg)
        } catch {
            testStatus.stringValue = "Could not initialise client: \(error.localizedDescription)"
            testStatus.textColor = .systemRed
            return
        }
        // Hold a strong reference for the duration of the probe;
        // dropping it before completion would deallocate the
        // URLSession config.
        probeTranscriber = transcriber

        // Cancel any in-flight probe before starting another.
        probeTask?.cancel()

        testButton.isEnabled = false
        testSpinner.startAnimation(nil)
        testStatus.stringValue = "Probing…"
        testStatus.textColor = .secondaryLabelColor
        Trace.settings("probe-start", "endpointHost=\(cfg.endpoint.host ?? "?")")

        let task = transcriber.probe { [weak self] result in
            // Hop main; renderResult mutates UI.
            Task { @MainActor [weak self] in
                self?.renderResult(result, for: cfg)
            }
        }
        probeTask = task
    }

    private func renderResult(_ result: Result<String, Transcriber.TranscribeError>,
                              for cfg: ServerConfig) {
        testButton.isEnabled = true
        testSpinner.stopAnimation(nil)
        probeTask = nil
        probeTranscriber = nil

        // UI policy lives here, NOT in Transcriber.probe.
        switch result {
        case .success(let text):
            testStatus.stringValue =
                "✓ Server reachable. Returned text: \"\(text.prefix(60))\"."
            testStatus.textColor = .systemGreen
            Trace.settings("probe-result", "kind=ok status=200")

        case .failure(.empty):
            // Silence accepted — the canonical "good" outcome for the
            // probe (it sent silence, after all).
            testStatus.stringValue =
                "✓ Server reachable; returned empty text for silent probe — that's expected."
            testStatus.textColor = .systemGreen
            Trace.settings("probe-result", "kind=empty-ok status=200")

        case .failure(.http(let status, let body)):
            let bodySnippet = body?.prefix(120).description ?? ""
            testStatus.stringValue = "✗ HTTP \(status). \(bodySnippet)"
            testStatus.textColor = .systemRed
            Trace.settings("probe-result", "kind=http status=\(status)")

        case .failure(.decode(let m)):
            testStatus.stringValue =
                "✗ Server reachable but response shape unexpected; expected {\"text\":...}. \(m)"
            testStatus.textColor = .systemOrange
            Trace.settings("probe-result", "kind=decode status=200")

        case .failure(.requestFailed(let m)):
            // Translate ATS specifically (C1). The underlying URLError
            // has been flattened to a String at this point, so we
            // detect ATS by message-substring (Foundation localises
            // "App Transport Security policy requires the use of a
            // secure connection." for code -1022). Host is taken from
            // the configured endpoint, not from the error itself.
            if m.localizedCaseInsensitiveContains("transport security") {
                let host = cfg.endpoint.host ?? "(no host)"
                testStatus.stringValue =
                    "✗ App Transport Security blocked the request to \(host). " +
                    "To use a different HTTP host, update Resources/Info.plist.template " +
                    "and rebuild. HTTPS hosts work without rebuild."
                testStatus.textColor = .systemRed
                Trace.settings("probe-result", "kind=ats status=-1022")
            } else {
                testStatus.stringValue = "✗ Network error: \(m)"
                testStatus.textColor = .systemRed
                Trace.settings("probe-result", "kind=net status=0")
            }

        case .failure(.invalidModel(let v)):
            testStatus.stringValue = "✗ Model name rejected by client validation: \(v)"
            testStatus.textColor = .systemRed
            Trace.settings("probe-result", "kind=invalid status=0")

        case .failure(.invalidBearer):
            testStatus.stringValue = "✗ Bearer token rejected by client validation."
            testStatus.textColor = .systemRed
            Trace.settings("probe-result", "kind=invalid status=0")
        }
    }

    // MARK: Render

    private var isDirty: Bool { form != initialForm }

    private func renderForm() {
        urlField.stringValue = form.endpointString
        modelField.stringValue = form.model
        bearerField.stringValue = form.bearer
        renderValidation()
    }

    private func renderValidation() {
        renderField(status: urlStatus, ok: form.isEndpointValid,
                    okText: "✓ valid URL",
                    errorText: form.endpointString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "Required"
                        : "Must be http:// or https:// with a host")
        renderField(status: modelStatus, ok: form.isModelValid,
                    okText: "✓ valid",
                    errorText: form.model.isEmpty
                        ? "Required"
                        : "Allowed: A–Z, a–z, 0–9, period, underscore, dash (1–128 chars)")
        renderField(status: bearerStatus, ok: form.isBearerValid,
                    okText: "✓ valid",
                    errorText: form.bearer.isEmpty
                        ? "Required"
                        : "Allowed: A–Z, a–z, 0–9, ._~+/=- (1–512 chars)")

        saveButton.isEnabled = form.isValid
        testButton.isEnabled = form.isValid && probeTask == nil
    }

    private func renderField(status: NSTextField, ok: Bool,
                             okText: String, errorText: String) {
        if ok {
            status.stringValue = okText
            status.textColor = .systemGreen
        } else {
            status.stringValue = errorText
            status.textColor = .systemRed
        }
    }

    // MARK: UI building

    private func configureUI() {
        guard let contentView = window?.contentView else { return }

        urlField.placeholderString = "http://host:8000/v1/audio/transcriptions"
        modelField.placeholderString = "canary-qwen-2.5b"
        bearerField.placeholderString = "Optional. Leave blank if your server has no auth."

        for field: NSTextField in [urlField, modelField, bearerField] {
            field.target = self
            field.action = #selector(fieldChanged(_:))
            field.delegate = self
        }

        for label in [urlStatus, modelStatus, bearerStatus] {
            label.font = NSFont.systemFont(ofSize: 11)
            label.textColor = .secondaryLabelColor
        }

        testButton.target = self
        testButton.action = #selector(testTapped)
        testButton.bezelStyle = .rounded

        testSpinner.style = .spinning
        testSpinner.controlSize = .small
        testSpinner.isDisplayedWhenStopped = false

        testStatus.font = NSFont.systemFont(ofSize: 11)
        testStatus.maximumNumberOfLines = 4

        saveButton.target = self
        saveButton.action = #selector(saveTapped)
        saveButton.bezelStyle = .rounded
        saveButton.keyEquivalent = "\r"

        cancelButton.target = self
        cancelButton.action = #selector(cancelTapped)
        cancelButton.bezelStyle = .rounded
        cancelButton.keyEquivalent = "\u{1b}"  // Esc

        // Layout: form rows on top, test row in the middle, button row
        // at the bottom.
        let urlRow = labeledRow(label: "Server URL", control: urlField, status: urlStatus)
        let modelRow = labeledRow(label: "Model name", control: modelField, status: modelStatus)
        let bearerRow = labeledRow(label: "Bearer token (optional)", control: bearerField, status: bearerStatus)

        let testRow = NSStackView(views: [testButton, testSpinner, testStatus])
        testRow.orientation = .horizontal
        testRow.alignment = .top
        testRow.spacing = 8
        testRow.distribution = .fill
        testStatus.setContentHuggingPriority(.defaultLow, for: .horizontal)
        testStatus.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let buttonRow = NSStackView(views: [NSView(), cancelButton, saveButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 12

        let stack = NSStackView(views: [urlRow, modelRow, bearerRow, testRow, buttonRow])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)
        stack.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stack.topAnchor.constraint(equalTo: contentView.topAnchor),
            stack.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            urlField.widthAnchor.constraint(equalToConstant: 380),
            modelField.widthAnchor.constraint(equalToConstant: 380),
            bearerField.widthAnchor.constraint(equalToConstant: 380),
            testStatus.widthAnchor.constraint(greaterThanOrEqualToConstant: 280),
        ])
    }

    private func labeledRow(label: String, control: NSTextField,
                            status: NSTextField) -> NSStackView {
        let title = NSTextField(labelWithString: label)
        title.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        title.alignment = .right
        title.widthAnchor.constraint(equalToConstant: 110).isActive = true

        let body = NSStackView(views: [control, status])
        body.orientation = .vertical
        body.alignment = .leading
        body.spacing = 2

        let row = NSStackView(views: [title, body])
        row.orientation = .horizontal
        row.alignment = .firstBaseline
        row.spacing = 12
        return row
    }
}

// MARK: - NSTextFieldDelegate (live edit propagation)

extension SettingsWindowController: NSTextFieldDelegate {

    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSTextField else { return }
        fieldChanged(field)
    }
}
