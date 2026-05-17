import AppKit
import CommonCrypto

/// Owns the app's single source of truth (`state`) and routes hotkey events
/// through the recording → transcribing → pasting pipeline.
///
/// All state transitions happen on the main thread. Subsystems do not
/// track their own state — they answer questions about hardware (is the
/// engine running?) but the user-visible state machine lives here.
///
/// ### Trace points (overlay-diagnosis plan)
///
///   - `trace:ad-handlearm`     — L5 entry to handleArm()
///   - `trace:ad-handlecommit`  — L6, after recorder.start() succeeds or fails
///   - `trace:state-didset`     — L7, every state mutation
///
/// ### P3: cdhash-change detection
///
/// On launch we hash `/Applications/VoiceRider.app/Contents/MacOS/VoiceRider`
/// and compare to `voicerider.lastSeenCDHash` in UserDefaults. If different
/// AND a TCC service is denied, we emit a single `Log.app.warning` AND show
/// an `NSAlert` once per cdhash (the user can dismiss with "Don't show
/// again" via `voicerider.suppressCDHashAlert`).
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {

    // MARK: Configuration (UserDefaults-overridable)

    private struct Config {
        let endpoint: URL
        let model: String
        let bearer: String

        static let defaultEndpoint =
            URL(string: "http://localhost:8000/v1/audio/transcriptions")!
        static let defaultModel = "canary-qwen-2.5b"
        static let defaultBearer = "local-no-auth"

        static func load() -> Config {
            let defaults = UserDefaults.standard
            let endpoint = defaults.string(forKey: "voicerider.serverURL")
                .flatMap { URL(string: $0) }
                ?? defaultEndpoint
            let model = defaults.string(forKey: "voicerider.modelName")  ?? defaultModel
            let bearer = defaults.string(forKey: "voicerider.bearerToken") ?? defaultBearer
            return Config(endpoint: endpoint, model: model, bearer: bearer)
        }
    }

    // MARK: Subsystems

    private let perms = Permissions()
    private lazy var recorder = AudioRecorder(mic: perms)
    private let paster = Paster()
    private lazy var status: StatusItemController = StatusItemController(perms: perms)
    private lazy var overlay: RecordingOverlay = RecordingOverlay()
    private var transcriber: Transcriber?

    private var hotkey: HotkeyMonitor?

    // MARK: State

    private var state: AppState = .idle {
        didSet {
            // L7: every state transition logged with stable tags.
            Trace.state(prev: oldValue.tag, next: self.state.tag)
            status.render(state)
            overlay.render(state)
            Log.app.log("state -> \(String(describing: self.state), privacy: .public)")
        }
    }
    private var currentWav: URL?
    private var errorClearWork: DispatchWorkItem?

    // MARK: Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        status.onQuit = { NSApp.terminate(nil) }
        status.onOpenPermissions = { [weak self] in self?.perms.openSettingsPanes() }
        status.onRecheckPermissions = { [weak self] in
            self?.status.refreshPermissions()  // P2
        }
        status.onShowTrace = { [weak self] in
            self?.openConsoleAppFiltered()  // diagnostic helper
        }

        perms.requestMicrophone()
        perms.requestAccessibility(prompt: true)
        let inputAccess = perms.requestInputMonitoring()

        // P3: cdhash-change detection.
        runCDHashCheck()

        // Initial permission render so the menu shows ✓/✗ from launch.
        status.refreshPermissions()

        let cfg = Config.load()
        do {
            transcriber = try Transcriber(
                endpoint: cfg.endpoint,
                model: cfg.model,
                bearer: cfg.bearer)
        } catch {
            setError("config: \(error.localizedDescription)")
            return
        }

        let monitor = HotkeyMonitor(
            onArm:     { [weak self] in self?.handleArm() },
            onCommit:  { [weak self] in self?.handleCommit() },
            onCancel:  { [weak self] in self?.handleCancel() },
            onRelease: { [weak self] in self?.handleRelease() }
        )
        self.hotkey = monitor

        if !monitor.start() {
            if inputAccess == kIOHIDAccessTypeDenied {
                setError("Input Monitoring denied. Open System Settings → Privacy & Security → Input Monitoring.")
            } else if !perms.requestAccessibility(prompt: false) {
                setError("Accessibility denied. Open System Settings → Privacy & Security → Accessibility.")
            } else {
                setError("Could not install hotkey tap. Grant Accessibility + Input Monitoring, then relaunch.")
            }
        }
    }

    // MARK: Hotkey handlers (main thread)

    private func handleArm() {
        Trace.ad("handlearm", "prev=\(state.tag)")
        if state == .idle { state = .arming }
    }

    private func handleCancel() {
        if state == .arming { state = .idle }
    }

    private func handleCommit() {
        Trace.ad("handlecommit", "prev=\(state.tag)")
        guard state == .arming else { return }
        do {
            currentWav = try recorder.start()
            Trace.ad("handlecommit-recorder-ok", "wav=\(currentWav?.lastPathComponent ?? "nil")")
            state = .recording
        } catch {
            Trace.ad("handlecommit-recorder-err", "err=\(String(describing: error))")
            setError("mic: \(error.localizedDescription)")
        }
    }

    private func handleRelease() {
        switch state {
        case .arming:
            state = .idle
        case .recording:
            recorder.stop()
            guard let wav = currentWav, let transcriber else {
                state = .idle
                return
            }
            currentWav = nil
            state = .transcribing
            transcriber.transcribe(wav: wav) { [weak self] result in
                Task { @MainActor [weak self] in
                    try? FileManager.default.removeItem(at: wav)
                    self?.handleTranscribeResult(result)
                }
            }
        default:
            return
        }
    }

    private func handleTranscribeResult(_ result: Result<String, Transcriber.TranscribeError>) {
        switch result {
        case .success(let text):
            state = .pasting
            paster.paste(text) { [weak self] in
                self?.state = .idle
            }
        case .failure(let err):
            setError(err.errorDescription ?? "transcribe failed")
        }
    }

    // MARK: Error helper

    private func setError(_ message: String) {
        Log.app.error("\(message, privacy: .public)")
        state = .error(message)
        errorClearWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if case .error = self.state { self.state = .idle }
        }
        errorClearWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0, execute: work)
    }

    // MARK: P3 — cdhash detection

    private func runCDHashCheck() {
        guard let path = Bundle.main.executablePath else { return }
        let url = URL(fileURLWithPath: path)
        let current: String
        do {
            current = try AppDelegate.computeCDHash(of: url)
        } catch {
            Log.app.error("cdhash compute failed: \(error.localizedDescription, privacy: .public)")
            return
        }
        let lastSeen = UserDefaults.standard.string(forKey: "voicerider.lastSeenCDHash")

        let result = CDHashDetection.detect(current: current, lastSeen: lastSeen)
        Trace.perms("cdhash", "current=\(current.prefix(12)) lastSeen=\(lastSeen?.prefix(12) ?? "nil") result=\(result.tag)")

        UserDefaults.standard.set(current, forKey: "voicerider.lastSeenCDHash")

        if case .changed = result {
            // Only warn once per (new) cdhash. If the user explicitly
            // suppressed the alert before, honor that.
            let suppressed = UserDefaults.standard.bool(forKey: "voicerider.suppressCDHashAlert")
            let acc = perms.requestAccessibility(prompt: false)
            let inp = perms.inputMonitoringStatus()
            let denied = !acc || inp != kIOHIDAccessTypeGranted
            if denied && !suppressed {
                // R4: defer the alert past `applicationDidFinishLaunching`
                // so the modal doesn't block hotkey monitor installation.
                // Without this, presses during the dialog are dropped.
                DispatchQueue.main.async { [weak self] in
                    self?.showCDHashAlert()
                }
            }
        }
    }

    private func showCDHashAlert() {
        let alert = NSAlert()
        alert.messageText = "VoiceRider was rebuilt"
        alert.informativeText = """
            Ad-hoc code signing assigns a new identity hash to every build. \
            macOS resets some Privacy & Security grants when that hash changes.

            You may need to re-grant:
              • Accessibility
              • Input Monitoring
            """
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Don't show again")
        let resp = alert.runModal()
        if resp == .alertFirstButtonReturn {
            perms.openSettingsPanes()
        } else if resp == .alertSecondButtonReturn {
            UserDefaults.standard.set(true, forKey: "voicerider.suppressCDHashAlert")
        }
    }

    /// SHA-256 of the executable as a hex string. Stable across `cp -R`
    /// (since `cp -R` preserves bytes), changes when the binary is
    /// recompiled and re-codesigned. Not the actual codesign cdhash, but
    /// serves the same purpose: a fingerprint of "is this the same build
    /// I saw last launch?".
    ///
    /// R7: guard against empty Data. CC_SHA256 with a nil pointer is
    /// undefined behavior. Empty input maps to the SHA-256 of zero bytes
    /// (well-known constant); we choose to return the zero hash here so
    /// callers can pin the contract.
    private static func computeCDHash(of file: URL) throws -> String {
        let data = try Data(contentsOf: file)
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { (buf: UnsafeRawBufferPointer) in
            guard let base = buf.baseAddress, !buf.isEmpty else { return }
            _ = CC_SHA256(base, CC_LONG(data.count), &hash)
        }
        return hash.map { String(format: "%02x", $0) }.joined()
    }

    private func openConsoleAppFiltered() {
        // Best-effort: open Console.app. The user can paste the predicate
        // from the README. We can't pre-fill the search field via URL.
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Console.app"))
    }
}
