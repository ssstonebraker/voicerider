import AVFoundation
import os.lock

/// Captures audio from the default input device, converts it to 16 kHz mono
/// 16-bit PCM, and writes a real RIFF WAV file. The engine stays running
/// for the process lifetime — only the output file rotates per recording.
///
/// ### Threading model (R4-F29 fix)
/// The Round-3 design dispatched each tap-callback `AVAudioPCMBuffer` to
/// a serial `DispatchQueue.async`. Research (Apple's own engineer at
/// `forums/thread/763362`, hotpaw2 at SO/69761269, "Learn OpenGL ES" on
/// SO/27343266) confirms this is unsafe: the engine may recycle the
/// underlying audio data before the deferred block runs, causing silent
/// frame loss under load.
///
/// Round-5 design: convert + write **inline on the audio render thread**.
/// An `os_unfair_lock` protects only the pointer reads/writes between
/// `start()` / `stop()` (main thread) and the tap callback (audio
/// thread). Lock hold time is two memory loads — RT-safe. After
/// `removeTap`, no new callbacks fire; an in-flight callback owns its
/// own strong reference to `file` (taken under the lock) and finishes
/// safely.
///
/// `AVAudioFile.write(from:)` thread-safety is not formally documented
/// by Apple, but Apple's own forum example writes inside the tap. We
/// adopt the same pattern.
///
/// ### Mic-permission gate (F1 / F25 fix)
/// `start()` consults the injected `MicrophoneStatusProviding` (in
/// production: `Permissions`) and throws `.micDenied` /
/// `.micNotDetermined` rather than letting the engine produce silent
/// frames.
///
/// ### Re-install on every start (F24 fix)
/// The tap is removed and re-installed on every `start()` so an input
/// device change between recordings (built-in → AirPods) doesn't leave a
/// stale sample-format snapshot behind.
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

    /// Protects only the three pointer properties below. Held for
    /// nanoseconds — read-the-pointer-and-go from the audio thread,
    /// install/clear from the main thread.
    private var lock = os_unfair_lock()
    private var file: AVAudioFile?
    private var converter: AVAudioConverter?
    private var outputFormat: AVAudioFormat?

    init(mic: MicrophoneStatusProviding) {
        self.mic = mic
    }

    /// Begins writing audio to a fresh temp WAV file. Returns the URL.
    func start() throws -> URL {
        // F1 / F25: mic check before any engine work. Single source of
        // truth lives in `Permissions.microphoneStatus()`.
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
        // F24: read input format fresh on every start — input device may
        // have changed since last recording.
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

        // Explicit settings produce a real RIFF WAV (not a CAF).
        // F19: AVLinearPCMIsNonInterleaved was redundant for mono and
        // contradicted `interleaved: true` below. Dropped.
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

        // R4-F29 fix: install pointers under the lock. After this returns,
        // any tap callback that runs sees a coherent snapshot.
        os_unfair_lock_lock(&lock)
        self.file = newFile
        self.converter = conv
        self.outputFormat = outFmt
        os_unfair_lock_unlock(&lock)

        // F24: re-install the tap on every start. removeTap is a no-op
        // if none is installed, so it's safe on the first call too.
        // Format `nil` lets the OS pick hardware-native; the converter
        // bridges to our 16 kHz Int16 target.
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            // Audio render thread. Buffer is valid only for the duration
            // of this closure (Apple does not retain its underlying
            // bytes past the call). Convert + write inline.
            self?.writeOnAudioThread(buffer: buffer)
        }

        if !engine.isRunning {
            do {
                try engine.start()
            } catch {
                throw AudioError.engineStartFailed(message: error.localizedDescription)
            }
        }

        // F28: tmp paths can include the user's short username on some
        // configs (`/var/folders/.../T/`). Keep the path private.
        Log.audio.log("recording start path=\(url.path, privacy: .private)")
        return url
    }

    /// Stops writing. The engine keeps running so the next start() is fast.
    /// After this returns, no new tap callbacks will fire and the WAV
    /// header is finalised on disk.
    func stop() {
        // 1. Remove the tap. After this, no NEW callbacks will fire.
        engine.inputNode.removeTap(onBus: 0)

        // 2. Acquire the lock and clear the pointers. If a callback is
        //    in its acquire-pointer phase, we wait microseconds for it
        //    to finish copying the strong refs and release the lock.
        //    If a callback is in its convert+write phase, it doesn't
        //    hold the lock, so we proceed immediately. Either way, the
        //    callback's local strong refs keep the file alive past our
        //    nil. ARC then drops `newFile`'s last reference and
        //    AVAudioFile.deinit flushes the RIFF chunk-size header.
        os_unfair_lock_lock(&lock)
        file = nil
        converter = nil
        outputFormat = nil
        os_unfair_lock_unlock(&lock)
        Log.audio.log("recording stop")
    }

    // MARK: Tap callback (audio render thread)

    /// Runs on the audio render thread. Acquires the lock just long
    /// enough to copy the three pointers, releases, then converts +
    /// writes. The captured strong references survive past `stop()`'s
    /// pointer-clear.
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

        // R4-F36: avoid a captured `var Bool` (warns under strict
        // concurrency) by closing over an Optional buffer that we nil
        // after the first feed. Same semantics as the prior `supplied`
        // flag, no captured mutation of a value type.
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
