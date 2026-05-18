import AVFoundation
import os.lock

/// Captures audio from the default input device, converts it to 16 kHz mono
/// 16-bit PCM, and writes a real RIFF WAV file.
///
/// ### M1: engine lifecycle = recording lifecycle
///
/// Previously the engine ran for the entire process lifetime so the
/// next `start()` was instantaneous. The cost was that macOS shows the
/// orange microphone-in-use indicator the whole time the engine is up,
/// even with no tap installed. M1 changes the contract:
///
///   - `start()` brings the engine up if not running (unchanged)
///   - `stop()` removes the tap, clears pointers, and **stops the
///     engine** (NEW)
///
/// This makes the orange indicator show only when the user is actually
/// holding the hotkey. The cold-start cost on the next press is
/// ~20–80ms, well under the 200ms hotkey qualification window — no
/// user-visible latency added.
///
/// ### Threading model (R4-F29 fix, unchanged)
/// The Round-3 design dispatched each tap-callback `AVAudioPCMBuffer` to
/// a serial `DispatchQueue.async`. Research confirms this is unsafe:
/// the engine may recycle the underlying audio data before the deferred
/// block runs. Round-5 design: convert + write **inline on the audio
/// render thread**. An `os_unfair_lock` protects only the pointer
/// reads/writes between `start()` / `stop()` (main thread) and the tap
/// callback (audio thread).
///
/// ### Mic-permission gate (F1 / F25 fix, unchanged)
/// `start()` consults the injected `MicrophoneStatusProviding` and
/// throws `.micDenied` / `.micNotDetermined` rather than letting the
/// engine produce silent frames.
///
/// ### Re-install on every start (F24 fix, unchanged)
/// The tap is removed and re-installed on every `start()` so an input
/// device change between recordings (built-in → AirPods) doesn't leave
/// a stale sample-format snapshot behind.
final class AudioRecorder {

    enum AudioError: Error, LocalizedError, Sendable {
        case micDenied
        case micNotDetermined
        case engineStartFailed(message: String)
        case fileCreateFailed(message: String)
        case converterUnavailable

        var errorDescription: String? {
            switch self {
            case .micDenied:
                return "Microphone access denied. Open System Settings → Privacy & Security → Microphone."
            case .micNotDetermined:
                return "Microphone permission not yet granted. Click the menu-bar icon and try again."
            case .engineStartFailed(let m): return "audio engine: \(m)"
            case .fileCreateFailed(let m):  return "audio file: \(m)"
            case .converterUnavailable:     return "audio converter unavailable"
            }
        }
    }

    private let mic: MicrophoneStatusProviding
    private let engine = AVAudioEngine()

    /// Test seam — `AudioRecorderEngineLifecycleTests` reads this to
    /// assert the M1 contract.
    var engineIsRunning: Bool { engine.isRunning }

    /// Protects only the three pointer properties below. Held for
    /// nanoseconds.
    private var lock = os_unfair_lock()
    private var file: AVAudioFile?
    private var converter: AVAudioConverter?
    private var outputFormat: AVAudioFormat?

    init(mic: MicrophoneStatusProviding) {
        self.mic = mic
    }

    /// Begins writing audio to a fresh temp WAV file. Returns the URL.
    func start() throws -> URL {
        switch mic.microphoneStatus() {
        case .authorized:
            break
        case .denied, .restricted:
            throw AudioError.micDenied
        case .notDetermined:
            throw AudioError.micNotDetermined
        @unknown default:
            throw AudioError.micDenied
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice-\(UUID().uuidString).wav")

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)

        guard let outFmt = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16_000,
            channels: 1,
            interleaved: true
        ) else {
            throw AudioError.converterUnavailable
        }

        guard let conv = AVAudioConverter(from: inputFormat, to: outFmt) else {
            throw AudioError.converterUnavailable
        }

        let settings: [String: Any] = [
            AVFormatIDKey:             kAudioFormatLinearPCM,
            AVSampleRateKey:           16_000,
            AVNumberOfChannelsKey:     1,
            AVLinearPCMBitDepthKey:    16,
            AVLinearPCMIsFloatKey:     false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let newFile: AVAudioFile
        do {
            newFile = try AVAudioFile(
                forWriting: url,
                settings: settings,
                commonFormat: .pcmFormatInt16,
                interleaved: true)
        } catch {
            throw AudioError.fileCreateFailed(message: error.localizedDescription)
        }

        os_unfair_lock_lock(&lock)
        self.file = newFile
        self.converter = conv
        self.outputFormat = outFmt
        os_unfair_lock_unlock(&lock)

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            self?.writeOnAudioThread(buffer: buffer)
        }

        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                throw AudioError.engineStartFailed(message: error.localizedDescription)
            }
        }

        Log.audio.log("recording start path=\(url.path, privacy: .private)")
        return url
    }

    /// Stops writing AND brings the engine down. After this returns:
    ///   1. No new tap callbacks will fire.
    ///   2. The WAV header is finalised on disk (via AVAudioFile.deinit
    ///      flushing on the last strong reference dropped).
    ///   3. **The engine is stopped.** macOS no longer shows the
    ///      microphone-in-use indicator. (M1)
    ///
    /// Idempotent — calling `stop()` on a never-started engine is a
    /// no-op (verified by `AudioRecorderEngineLifecycleTests`).
    func stop() {
        // 1. Remove the tap. After this, no NEW callbacks will fire.
        engine.inputNode.removeTap(onBus: 0)

        // 2. Acquire the lock and clear the pointers. If a callback is
        //    in its acquire-pointer phase, we wait microseconds for it
        //    to finish copying the strong refs and release the lock.
        //    If a callback is in its convert+write phase, it doesn't
        //    hold the lock. Either way, the callback's local strong
        //    refs keep the file alive past our nil. ARC then drops
        //    `newFile`'s last reference and AVAudioFile.deinit flushes
        //    the RIFF chunk-size header.
        os_unfair_lock_lock(&lock)
        file = nil
        converter = nil
        outputFormat = nil
        os_unfair_lock_unlock(&lock)

        // 3. M1: stop the engine. Cleared pointers + removed tap mean
        //    no in-flight work depends on the engine being up.
        if engine.isRunning {
            engine.stop()
        }
        Log.audio.log("recording stop")
    }

    // MARK: Tap callback (audio render thread)

    private func writeOnAudioThread(buffer: AVAudioPCMBuffer) {
        os_unfair_lock_lock(&lock)
        guard let file = self.file,
              let converter = self.converter,
              let outputFormat = self.outputFormat else {
            os_unfair_lock_unlock(&lock)
            return
        }
        os_unfair_lock_unlock(&lock)

        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let outBuf = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            return
        }

        var input: AVAudioPCMBuffer? = buffer
        var convertError: NSError?
        let status = converter.convert(to: outBuf, error: &convertError) { _, outStatus in
            if let buf = input {
                input = nil
                outStatus.pointee = .haveData
                return buf
            }
            outStatus.pointee = .noDataNow
            return nil
        }

        switch status {
        case .haveData, .inputRanDry:
            do {
                try file.write(from: outBuf)
            } catch {
                Log.audio.error("file write failed: \(error.localizedDescription, privacy: .public)")
            }
        case .error:
            if let e = convertError {
                Log.audio.error("converter error: \(e.localizedDescription, privacy: .public)")
            }
        case .endOfStream:
            break
        @unknown default:
            break
        }
    }
}
