import Testing
import Foundation
import AVFoundation
@testable import VoiceRider

/// `AudioRecorder` requires Microphone permission and a real default
/// input device. CI typically lacks both, so the real-WAV-header test
/// is gated on `VOICERIDER_RUN_AUDIO_TESTS=1`. Tests that don't need a real
/// recording use a fake `MicrophoneStatusProviding` and run everywhere.
@Suite("AudioRecorder")
struct AudioRecorderTests {

    private final class FakeMic: MicrophoneStatusProviding, @unchecked Sendable {
        var status: AVAuthorizationStatus
        init(_ s: AVAuthorizationStatus) { self.status = s }
        func microphoneStatus() -> AVAuthorizationStatus { status }
    }

    @Test("start throws .micDenied when permission is denied")
    func micDeniedThrows() {
        let recorder = AudioRecorder(mic: FakeMic(.denied))
        do {
            _ = try recorder.start()
            Issue.record("expected throw")
        } catch AudioRecorder.AudioError.micDenied {
            // ok
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }

    @Test("start throws .micDenied when permission is restricted")
    func micRestrictedThrows() {
        let recorder = AudioRecorder(mic: FakeMic(.restricted))
        do {
            _ = try recorder.start()
            Issue.record("expected throw")
        } catch AudioRecorder.AudioError.micDenied {
            // ok
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }

    @Test("start throws .micNotDetermined when permission has not been asked")
    func micNotDeterminedThrows() {
        let recorder = AudioRecorder(mic: FakeMic(.notDetermined))
        do {
            _ = try recorder.start()
            Issue.record("expected throw")
        } catch AudioRecorder.AudioError.micNotDetermined {
            // ok
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }

    @Test("stop without start is a no-op")
    func stopWithoutStart() {
        let recorder = AudioRecorder(mic: FakeMic(.authorized))
        recorder.stop() // must not crash
    }

    @Test("stop is idempotent — multiple calls are safe")
    func stopIdempotent() {
        let recorder = AudioRecorder(mic: FakeMic(.authorized))
        recorder.stop()
        recorder.stop()
        recorder.stop()
    }

    @Test("error description is non-empty for every AudioError case")
    func errorDescriptionsAreUserFacing() {
        let cases: [AudioRecorder.AudioError] = [
            .micDenied,
            .micNotDetermined,
            .engineStartFailed(message: "x"),
            .fileCreateFailed(message: "x"),
            .converterUnavailable,
        ]
        for c in cases {
            let desc = c.errorDescription ?? ""
            #expect(!desc.isEmpty, "missing description for \(c)")
            // Should not start with whitespace or a newline.
            #expect(desc.first?.isNewline != true)
        }
    }

    /// Verifies that a freshly-started recording produces a real RIFF
    /// WAV with the expected header values. Requires Microphone
    /// permission on the host. Gated on env var.
    @Test("start writes a RIFF/WAVE header to the temp file",
          .enabled(if: ProcessInfo.processInfo.environment["VOICERIDER_RUN_AUDIO_TESTS"] == "1"))
    func writesRiffWaveHeader() throws {
        let recorder = AudioRecorder(mic: FakeMic(.authorized))
        let url: URL
        do {
            url = try recorder.start()
        } catch {
            Issue.record("AudioRecorder.start failed: \(error)")
            return
        }
        // ~250 ms of silence is enough to write the data chunk.
        Thread.sleep(forTimeInterval: 0.25)
        recorder.stop()

        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            Issue.record("could not read recorded file: \(error)")
            return
        }
        defer { try? FileManager.default.removeItem(at: url) }

        guard let header = WAVHeaderFixtures.parseRIFFWAVHeader(data) else {
            Issue.record("recorded file is not a valid RIFF/WAVE")
            return
        }
        #expect(header.audioFormat == 1, "audioFormat should be PCM")
        #expect(header.channels == 1, "should be mono")
        #expect(header.sampleRate == 16_000, "should be 16 kHz")
        #expect(header.bitsPerSample == 16, "should be 16-bit")
        #expect(header.blockAlign == 2)
        #expect(header.byteRate == 32_000)
        #expect(header.dataChunkSize > 0, "should have at least some audio data")
        // chunkSize should be 36 + dataChunkSize.
        #expect(header.chunkSize == 36 + header.dataChunkSize)
    }
}
