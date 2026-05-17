import AppKit

/// Owns the app's single source of truth (`state`) and routes hotkey events
/// through the recording → transcribing → pasting pipeline.
///
/// All state transitions happen on the main thread. Subsystems do not
/// track their own state — they answer questions about hardware (is the
/// engine running?) but the user-visible state machine lives here.
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
    private lazy var status: StatusItemController = StatusItemController()
    private lazy var overlay: RecordingOverlay = RecordingOverlay()
    private var transcriber: Transcriber?

    // F8: was `var hotkey: HotkeyMonitor!`. Now a real Optional that
    // becomes non-nil exactly once, in `applicationDidFinishLaunching`,
    // and is guard-let'd at use sites.
    private var hotkey: HotkeyMonitor?

    // MARK: State

    private var state: AppState = .idle {
        didSet {
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

        perms.requestMicrophone()
        perms.requestAccessibility(prompt: true)
        let inputAccess = perms.requestInputMonitoring()

        // Build the Transcriber. If `voicerider.modelName` is malformed
        // (CRLF / disallowed chars) we surface a precise error and stop.
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
            // F16: surface the precise denial when we can identify it.
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
        if state == .idle { state = .arming }
    }

    private func handleCancel() {
        if state == .arming { state = .idle }
    }

    private func handleCommit() {
        guard state == .arming else { return }
        do {
            currentWav = try recorder.start()
            state = .recording
        } catch {
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
            // F7: the URLSession completion handler runs on a background
            // thread. Wrap the body in `Task { @MainActor in ... }` so
            // every touch of `self.state` and `handleTranscribeResult`
            // is statically isolated to the main actor.
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
}
