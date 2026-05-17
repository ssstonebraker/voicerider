import Testing
import AppKit
@testable import VoiceRider

/// F4 fix: tests now exercise `ClipboardWriter` (which only touches
/// `NSPasteboard`) and **never** `Paster.paste(...)` for non-empty text
/// — that path synthesizes Cmd+V at HID level, which would paste into
/// whatever app has focus. The Paster end-to-end path is verified by the
/// manual integration checklist (M3).
///
/// `.serialized` because `NSPasteboard.general` is a process-wide
/// resource; running these tests in parallel would corrupt each other.
@Suite("ClipboardWriter", .serialized)
@MainActor
struct ClipboardWriterTests {

    @Test("write returns success and saves the previous string")
    func writeSuccess() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString("ORIGINAL", forType: .string)

        let writer = ClipboardWriter()
        let r = writer.write("NEW")

        #expect(r.success)
        #expect(r.savedString == "ORIGINAL")
        #expect(pb.string(forType: .string) == "NEW")
    }

    @Test("restore puts saved back when pasteboard still holds expected")
    func restoreHappy() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString("CURRENT", forType: .string)

        let writer = ClipboardWriter()
        writer.restore(saved: "PREVIOUS", ifCurrentIs: "CURRENT")

        #expect(pb.string(forType: .string) == "PREVIOUS")
    }

    @Test("restore is a no-op if the pasteboard changed externally")
    func restoreSkipsExternal() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString("EXTERNAL", forType: .string)

        let writer = ClipboardWriter()
        writer.restore(saved: "PREVIOUS", ifCurrentIs: "DIFFERENT")

        #expect(pb.string(forType: .string) == "EXTERNAL")
    }

    @Test("restore with nil saved clears the .string content")
    func restoreNilSaved() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString("CURRENT", forType: .string)

        let writer = ClipboardWriter()
        writer.restore(saved: nil, ifCurrentIs: "CURRENT")

        #expect(pb.string(forType: .string) == nil)
    }

    @Test("paste with empty string is a no-op and still calls completion")
    func emptyPasteIsNoOp() async {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString("ORIGINAL", forType: .string)

        let p = Paster()
        await withCheckedContinuation { cont in
            p.paste("") { cont.resume() }
        }
        #expect(pb.string(forType: .string) == "ORIGINAL")
    }
}
