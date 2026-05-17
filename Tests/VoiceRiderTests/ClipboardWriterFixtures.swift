import Testing
import AppKit
@testable import VoiceRider

/// Fixture-based coverage for `ClipboardWriter`. Pasteboard-only —
/// these tests **never** synthesize Cmd+V (`PasteSynthesizer` is
/// excluded from automated tests; manual M3 covers that).
///
/// These tests are an `extension` of `ClipboardWriterTests` (defined in
/// `PasterTests.swift`) so they share the **same** `.serialized` /
/// `@MainActor` suite. `.serialized` only synchronizes within a single
/// `@Suite`-decorated struct; running these as a separate suite would
/// allow Swift Testing to interleave them with the original
/// `ClipboardWriterTests` and corrupt the shared `NSPasteboard.general`.
extension ClipboardWriterTests {

    private func resetPasteboard(to text: String?) {
        let pb = NSPasteboard.general
        pb.clearContents()
        if let text { pb.setString(text, forType: .string) }
    }

    // MARK: - Basic round-trip

    @Test("write returns success=true and saves the previous .string")
    func writeReturnsSuccess() {
        resetPasteboard(to: "PREVIOUS")
        let writer = ClipboardWriter()
        let r = writer.write("NEW")
        #expect(r.success)
        #expect(r.savedString == "PREVIOUS")
        #expect(NSPasteboard.general.string(forType: .string) == "NEW")
    }

    @Test("write captures nil savedString when pasteboard had no string")
    func writeCapturesNilSaved() {
        let pb = NSPasteboard.general
        pb.clearContents() // no setString — string slot is empty
        let writer = ClipboardWriter()
        let r = writer.write("FRESH")
        #expect(r.success)
        #expect(r.savedString == nil)
        #expect(pb.string(forType: .string) == "FRESH")
    }

    // MARK: - Restore semantics

    @Test("restore reverts when the pasteboard still holds expected")
    func restoreRevertsWhenUnchanged() {
        resetPasteboard(to: "CURRENT")
        ClipboardWriter().restore(saved: "PREVIOUS", ifCurrentIs: "CURRENT")
        #expect(NSPasteboard.general.string(forType: .string) == "PREVIOUS")
    }

    @Test("restore is a no-op when the pasteboard changed externally")
    func restoreNoOpWhenChanged() {
        resetPasteboard(to: "EXTERNAL")
        ClipboardWriter().restore(saved: "PREVIOUS", ifCurrentIs: "DIFFERENT")
        #expect(NSPasteboard.general.string(forType: .string) == "EXTERNAL")
    }

    @Test("restore with nil saved + matching current clears the .string slot")
    func restoreNilSavedClears() {
        resetPasteboard(to: "CURRENT")
        ClipboardWriter().restore(saved: nil, ifCurrentIs: "CURRENT")
        #expect(NSPasteboard.general.string(forType: .string) == nil)
    }

    @Test("restore with nil saved + non-matching current is a no-op")
    func restoreNilSavedNoOpWhenChanged() {
        resetPasteboard(to: "EXTERNAL")
        ClipboardWriter().restore(saved: nil, ifCurrentIs: "EXPECTED")
        #expect(NSPasteboard.general.string(forType: .string) == "EXTERNAL")
    }

    // MARK: - Unicode

    @Test("Unicode payload round-trips via pasteboard")
    func unicodeRoundTrips() {
        resetPasteboard(to: "PREV")
        let payloads = [
            "héllo",                        // Latin-1 supplement
            "世界",                          // CJK
            "🎙️ recording",                 // emoji + variation selector
            "RTL مرحبا",                    // RTL embedded
            "combining é (NFD): e\u{0301}", // decomposed combining accent
            "ZWJ family: 👨‍👩‍👧‍👦",        // grapheme-cluster-rich
        ]
        for text in payloads {
            let r = ClipboardWriter().write(text)
            #expect(r.success, "write failed for \(text.debugDescription)")
            #expect(NSPasteboard.general.string(forType: .string) == text,
                    "round-trip failed for \(text.debugDescription)")
        }
    }

    // MARK: - Large payloads

    @Test("10KB payload writes and round-trips")
    func tenKBRoundTrip() {
        resetPasteboard(to: nil)
        let big = String(repeating: "x", count: 10_000)
        let r = ClipboardWriter().write(big)
        #expect(r.success)
        #expect(NSPasteboard.general.string(forType: .string)?.count == 10_000)
    }

    @Test("100KB payload writes and round-trips")
    func hundredKBRoundTrip() {
        resetPasteboard(to: nil)
        // 100 KB of Lorem-ipsum-ish content (not all-same-char, to stress
        // any underlying compression / heuristic).
        let chunk = "Lorem ipsum dolor sit amet, consectetur adipiscing elit. "
        var big = ""
        big.reserveCapacity(102_400)
        while big.count < 102_400 { big.append(chunk) }
        let r = ClipboardWriter().write(big)
        #expect(r.success)
        let read = NSPasteboard.general.string(forType: .string)
        #expect(read?.count == big.count)
        #expect(read?.hasPrefix("Lorem ipsum") == true)
    }

    // MARK: - Single-char + empty edge cases

    @Test("single character round-trips")
    func singleChar() {
        resetPasteboard(to: nil)
        let r = ClipboardWriter().write("z")
        #expect(r.success)
        #expect(NSPasteboard.general.string(forType: .string) == "z")
    }

    @Test("writing the empty string is accepted and pasteboard becomes empty")
    func emptyStringWrite() {
        resetPasteboard(to: "PREV")
        // Note: `Paster.paste("")` short-circuits and never calls
        // `ClipboardWriter.write`. This test exercises the writer
        // directly to pin its behavior — empty string is a valid
        // payload at the writer layer.
        let r = ClipboardWriter().write("")
        #expect(r.success)
        #expect(r.savedString == "PREV")
        #expect(NSPasteboard.general.string(forType: .string) == "")
    }

    // MARK: - Sequencing

    @Test("two consecutive writes preserve the original via savedString chain")
    func twoConsecutiveWrites() {
        resetPasteboard(to: "ORIGINAL")
        let writer = ClipboardWriter()
        let r1 = writer.write("STEP1")
        #expect(r1.savedString == "ORIGINAL")
        let r2 = writer.write("STEP2")
        // The saved string from r2 is STEP1 — what was on the
        // pasteboard immediately before r2.write. Restoring with
        // r2.savedString gives back STEP1; restoring r1.savedString
        // separately gives back ORIGINAL. Caller is responsible for
        // sequencing if they want to chain restores; production code
        // doesn't need that.
        #expect(r2.savedString == "STEP1")
        #expect(NSPasteboard.general.string(forType: .string) == "STEP2")
    }

    // MARK: - Round-trip via Paster.paste("") (covered in parent struct)
}
