import Foundation

/// Produces an in-memory RIFF/WAVE bytestream filled with silence
/// (zero samples) at 16 kHz mono Int16, the canonical format
/// VoiceRider already uploads. Used by `Transcriber.probe()` to
/// exercise the full multipart/upload path without recording the
/// user.
///
/// **Annie note.** The test target has a sibling
/// `WAVHeaderFixtures.makeMinimalWAV` that builds the same byte
/// layout; we deliberately do not import test code into the
/// production target. This 30-line duplicate is the tax for keeping
/// the test target out of the production build graph. If it ever
/// drifts from the test fixture, that's a test failure, not a code
/// review issue.
///
/// **Sauron note.** This is the single in-production "make a silent
/// WAV" function. Transcriber.probe is the only caller. If a second
/// caller appears, route through here, do not duplicate the byte
/// layout.
enum SilentWAVGenerator {

    /// 16 kHz mono 16-bit linear PCM. Header = 44 bytes; data =
    /// `frames * 2` bytes. Default 0.5 s = 8 000 frames = 16 044
    /// bytes total (~16 KB).
    static let sampleRate: UInt32 = 16_000
    static let channels: UInt16 = 1
    static let bitsPerSample: UInt16 = 16

    /// Returns a complete RIFF/WAVE file as `Data`. `seconds` is
    /// rounded down to whole frames.
    static func makeWAV(seconds: Double = 0.5) -> Data {
        let frames = UInt32(max(0, seconds * Double(sampleRate)))
        return makeWAV(frameCount: frames)
    }

    /// Frame-count form. Used by tests that want exact byte sizes.
    static func makeWAV(frameCount: UInt32) -> Data {
        let blockAlign = channels * (bitsPerSample / 8)         // 2
        let byteRate   = sampleRate * UInt32(blockAlign)        // 32 000
        let dataSize   = frameCount * UInt32(blockAlign)        // 2 * frames
        let chunkSize  = 36 + dataSize                          // 36 + dataSize

        var d = Data()
        d.append(contentsOf: "RIFF".utf8)
        d.append(contentsOf: withUnsafeBytes(of: chunkSize.littleEndian, Array.init))
        d.append(contentsOf: "WAVE".utf8)
        d.append(contentsOf: "fmt ".utf8)
        d.append(contentsOf: withUnsafeBytes(of: UInt32(16).littleEndian, Array.init))   // fmt chunk size = 16
        d.append(contentsOf: withUnsafeBytes(of: UInt16(1).littleEndian, Array.init))    // audio format = PCM
        d.append(contentsOf: withUnsafeBytes(of: channels.littleEndian, Array.init))
        d.append(contentsOf: withUnsafeBytes(of: sampleRate.littleEndian, Array.init))
        d.append(contentsOf: withUnsafeBytes(of: byteRate.littleEndian, Array.init))
        d.append(contentsOf: withUnsafeBytes(of: blockAlign.littleEndian, Array.init))
        d.append(contentsOf: withUnsafeBytes(of: bitsPerSample.littleEndian, Array.init))
        d.append(contentsOf: "data".utf8)
        d.append(contentsOf: withUnsafeBytes(of: dataSize.littleEndian, Array.init))
        // Append `dataSize` zero bytes — this is the silence.
        d.append(Data(count: Int(dataSize)))
        return d
    }
}
