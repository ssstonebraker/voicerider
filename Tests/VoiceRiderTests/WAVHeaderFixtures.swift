import Testing
import Foundation
@testable import VoiceRider

/// Fixture-based coverage for a tiny RIFF/WAVE byte parser used to
/// validate the recorder's output. This is **test-only** — it is not
/// added to the production `Sources/VoiceRider/` target. Production code
/// uses `AVAudioFile`, which writes a real WAV header for us. The
/// parser exists so that the integration test
/// (`AudioRecorderTests.writesRiffWaveHeader`) can verify the bytes
/// look right when `VOICERIDER_RUN_AUDIO_TESTS=1` is set.
///
/// Spec: WAV files start with
///   bytes  0..4  : "RIFF" magic
///   bytes  4..8  : little-endian uint32 chunk size = file size − 8
///   bytes  8..12 : "WAVE" magic
///   bytes 12..16 : "fmt " (with trailing space)
///   bytes 16..20 : little-endian uint32 fmt chunk size (16 for PCM)
///   bytes 20..22 : little-endian uint16 audio format (1 for PCM)
///   bytes 22..24 : little-endian uint16 channel count
///   bytes 24..28 : little-endian uint32 sample rate
///   bytes 28..32 : little-endian uint32 byte rate
///   bytes 32..34 : little-endian uint16 block align
///   bytes 34..36 : little-endian uint16 bits per sample
///   bytes 36..40 : "data" magic
///   bytes 40..44 : little-endian uint32 data chunk size
///
/// Source: <https://soundfile.sapp.org/doc/WaveFormat/>
@Suite("WAVHeaderFixtures")
struct WAVHeaderFixtures {

    struct Header: Equatable {
        let chunkSize: UInt32
        let fmtChunkSize: UInt32
        let audioFormat: UInt16
        let channels: UInt16
        let sampleRate: UInt32
        let byteRate: UInt32
        let blockAlign: UInt16
        let bitsPerSample: UInt16
        let dataChunkSize: UInt32
    }

    /// Parses a 44-byte canonical PCM/WAV header. Returns nil if the
    /// magic bytes are missing or the file is shorter than 44 bytes.
    static func parseRIFFWAVHeader(_ data: Data) -> Header? {
        guard data.count >= 44 else { return nil }
        guard data[0..<4] == Data("RIFF".utf8),
              data[8..<12] == Data("WAVE".utf8),
              data[12..<16] == Data("fmt ".utf8),
              data[36..<40] == Data("data".utf8)
        else { return nil }

        func u16(_ offset: Int) -> UInt16 {
            UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
        }
        func u32(_ offset: Int) -> UInt32 {
            UInt32(data[offset])
                | (UInt32(data[offset + 1]) << 8)
                | (UInt32(data[offset + 2]) << 16)
                | (UInt32(data[offset + 3]) << 24)
        }

        return Header(
            chunkSize:     u32(4),
            fmtChunkSize:  u32(16),
            audioFormat:   u16(20),
            channels:      u16(22),
            sampleRate:    u32(24),
            byteRate:      u32(28),
            blockAlign:    u16(32),
            bitsPerSample: u16(34),
            dataChunkSize: u32(40))
    }

    /// Builds a minimal 16 kHz mono Int16 PCM WAV file with `frameCount`
    /// silent frames. Useful for round-trip parser tests and as a
    /// stand-in fixture when the real recorder isn't available.
    static func makeMinimalWAV(sampleRate: UInt32 = 16_000,
                               channels: UInt16 = 1,
                               bitsPerSample: UInt16 = 16,
                               frameCount: UInt32 = 0) -> Data {
        let blockAlign = channels * (bitsPerSample / 8)
        let byteRate = sampleRate * UInt32(blockAlign)
        let dataSize = frameCount * UInt32(blockAlign)
        let chunkSize = 36 + dataSize
        var d = Data()
        d.append(contentsOf: "RIFF".utf8)
        d.append(contentsOf: withUnsafeBytes(of: chunkSize.littleEndian, Array.init))
        d.append(contentsOf: "WAVE".utf8)
        d.append(contentsOf: "fmt ".utf8)
        d.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian, Array.init))
        d.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian, Array.init))   // PCM
        d.append(contentsOf: withUnsafeBytes(of: channels.littleEndian, Array.init))
        d.append(contentsOf: withUnsafeBytes(of: sampleRate.littleEndian, Array.init))
        d.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian, Array.init))
        d.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian, Array.init))
        d.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian, Array.init))
        d.append(contentsOf: "data".utf8)
        d.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian, Array.init))
        // append `dataSize` silent bytes
        d.append(Data(count: Int(dataSize)))
        return d
    }

    // MARK: - Parser tests

    @Test("parser rejects empty data")
    func rejectsEmpty() {
        #expect(Self.parseRIFFWAVHeader(Data()) == nil)
    }

    @Test("parser rejects sub-44-byte data")
    func rejectsTooShort() {
        #expect(Self.parseRIFFWAVHeader(Data(count: 43)) == nil)
    }

    @Test("parser rejects missing RIFF magic")
    func rejectsMissingRIFF() {
        var d = Self.makeMinimalWAV()
        d[0] = 0x00
        #expect(Self.parseRIFFWAVHeader(d) == nil)
    }

    @Test("parser rejects missing WAVE magic")
    func rejectsMissingWAVE() {
        var d = Self.makeMinimalWAV()
        d[8] = 0x00
        #expect(Self.parseRIFFWAVHeader(d) == nil)
    }

    @Test("parser rejects missing fmt chunk")
    func rejectsMissingFMT() {
        var d = Self.makeMinimalWAV()
        d[12] = 0x00
        #expect(Self.parseRIFFWAVHeader(d) == nil)
    }

    @Test("parser rejects missing data chunk")
    func rejectsMissingDATA() {
        var d = Self.makeMinimalWAV()
        d[36] = 0x00
        #expect(Self.parseRIFFWAVHeader(d) == nil)
    }

    @Test("parser reads a 16 kHz mono Int16 zero-frame fixture correctly")
    func parsesZeroFrameFixture() {
        let d = Self.makeMinimalWAV()
        guard let h = Self.parseRIFFWAVHeader(d) else {
            Issue.record("parser returned nil for canonical fixture"); return
        }
        #expect(h.audioFormat == 1)         // PCM
        #expect(h.channels == 1)
        #expect(h.sampleRate == 16_000)
        #expect(h.bitsPerSample == 16)
        #expect(h.blockAlign == 2)
        #expect(h.byteRate == 32_000)        // 16000 sps * 2 bytes/frame
        #expect(h.fmtChunkSize == 16)
        #expect(h.dataChunkSize == 0)
        #expect(h.chunkSize == 36)           // 36 + dataSize
    }

    @Test("parser computed fields are consistent for a 1 s mono fixture")
    func parsesOneSecondFixture() {
        let d = Self.makeMinimalWAV(frameCount: 16_000)
        guard let h = Self.parseRIFFWAVHeader(d) else {
            Issue.record("parser returned nil"); return
        }
        // 1 s of 16 kHz mono Int16 = 16000 frames * 2 bytes = 32000 bytes.
        #expect(h.dataChunkSize == 32_000)
        #expect(h.chunkSize == 36 + 32_000)
        #expect(h.byteRate == h.sampleRate * UInt32(h.blockAlign))
    }

    @Test("parser handles stereo and 24-bit fixtures")
    func parsesStereoFixture() {
        let d = Self.makeMinimalWAV(
            sampleRate: 48_000, channels: 2, bitsPerSample: 24, frameCount: 100)
        guard let h = Self.parseRIFFWAVHeader(d) else {
            Issue.record("parser returned nil"); return
        }
        #expect(h.channels == 2)
        #expect(h.sampleRate == 48_000)
        #expect(h.bitsPerSample == 24)
        #expect(h.blockAlign == 6)           // 2 ch * 3 bytes/sample
        #expect(h.byteRate == 288_000)
        #expect(h.dataChunkSize == 600)      // 100 frames * 6 bytes
    }

    @Test("makeMinimalWAV produces total file size = 44 + dataSize")
    func fileSizeMath() {
        for frames: UInt32 in [0, 1, 1_000, 16_000] {
            let d = Self.makeMinimalWAV(frameCount: frames)
            #expect(d.count == 44 + Int(frames) * 2)
        }
    }
}
