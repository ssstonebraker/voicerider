import Testing
import Foundation
import AVFoundation
@testable import VoiceRider

/// M1 verification — `AudioRecorder.stop()` brings the engine down
/// (so macOS no longer shows the orange microphone-in-use indicator)
/// and `start()` brings it up again.
///
/// **Gated by `VOICERIDER_RUN_AUDIO_TESTS=1`** because
/// `AVAudioEngine.start()` touches real audio hardware. The default
/// `make verify` / `swift test` skips these tests.
@Suite("AudioRecorder.engineLifecycle", .serialized,
       .enabled(if: ProcessInfo.processInfo.environment["VOICERIDER_RUN_AUDIO_TESTS"] == "1"))
struct AudioRecorderEngineLifecycleTests {

    /// Stub that always reports authorized so we exercise the full
    /// engine path without touching `Permissions`.
    private final class StubMic: MicrophoneStatusProviding {
        func microphoneStatus() -> AVAuthorizationStatus { .authorized }
    }

    @Test("M1 fixture lifecycle pins engine state after each action",
          arguments: AudioRecorderFixtures.all)
    func lifecycle(row: AudioRecorderFixtures.LifecycleRow) throws {
        let recorder = AudioRecorder(mic: StubMic())
        defer { recorder.stop() }

        for (idx, action) in row.actions.enumerated() {
            switch action {
            case .start:
                _ = try recorder.start()
            case .stop:
                recorder.stop()
            }
            let expected = row.expected[idx]
            #expect(recorder.engineIsRunning == expected,
                    "row '\(row.label)' step \(idx) action=\(action): expected isRunning=\(expected), got \(recorder.engineIsRunning)")
        }
    }

    @Test("after stop, the engine is not running")
    func stopBringsEngineDown() throws {
        let recorder = AudioRecorder(mic: StubMic())
        _ = try recorder.start()
        #expect(recorder.engineIsRunning == true)
        recorder.stop()
        #expect(recorder.engineIsRunning == false)
    }

    @Test("calling stop before start is safe")
    func stopBeforeStartSafe() throws {
        let recorder = AudioRecorder(mic: StubMic())
        recorder.stop()
        #expect(recorder.engineIsRunning == false)
    }
}
