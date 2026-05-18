import Testing
import Foundation
@testable import VoiceRider

/// Verifies `SilentWAVGenerator` produces bytes that pass through the
/// existing test-target `WAVHeaderFixtures.parseRIFFWAVHeader` parser
/// — using the parser as an oracle keeps the production generator
/// honest against the same spec the WAV-header tests pin.
@Suite("SilentWAVGenerator")
struct SilentWAVGeneratorTests {

    @Test("default 0.5s produces 16 044 bytes (44-byte header + 16 000-byte data)")
    func defaultSizeIs16044() {
        let d = SilentWAVGenerator.makeWAV()
        #expect(d.count == 44 + 16_000)
    }

    @Test("frame-count form: file size = 44 + frames * 2")
    func frameCountSizeMath() {
        for frames: UInt32 in [0, 1, 1_000, 8_000, 16_000] {
            let d = SilentWAVGenerator.makeWAV(frameCount: frames)
            #expect(d.count == 44 + Int(frames) * 2)
        }
    }

    @Test("output parses cleanly via WAVHeaderFixtures.parseRIFFWAVHeader")
    func outputParsesCleanly() {
        let d = SilentWAVGenerator.makeWAV()
        guard let h = WAVHeaderFixtures.parseRIFFWAVHeader(d) else {
            Issue.record("parser rejected SilentWAVGenerator output"); return
        }
        #expect(h.audioFormat == 1)
        #expect(h.channels == 1)
        #expect(h.sampleRate == 16_000)
        #expect(h.bitsPerSample == 16)
        #expect(h.blockAlign == 2)
        #expect(h.byteRate == 32_000)
        #expect(h.fmtChunkSize == 16)
        #expect(h.dataChunkSize == 16_000)         // 0.5s * 16 kHz * 2 bytes
        #expect(h.chunkSize == 36 + 16_000)
    }

    @Test("data section is all zeros (silence)")
    func dataIsAllZeros() {
        let d = SilentWAVGenerator.makeWAV(frameCount: 1_000)
        let dataPart = d.suffix(2_000)             // last 2 000 bytes
        #expect(dataPart.allSatisfy { $0 == 0 })
    }

    @Test("zero-frame request produces a valid 44-byte header")
    func zeroFrameValid() {
        let d = SilentWAVGenerator.makeWAV(frameCount: 0)
        guard let h = WAVHeaderFixtures.parseRIFFWAVHeader(d) else {
            Issue.record("parser rejected zero-frame WAV"); return
        }
        #expect(d.count == 44)
        #expect(h.dataChunkSize == 0)
    }
}
