import AppKit

// MARK: - ClipboardWriter

/// Writes a string to `NSPasteboard.general` and (separately) restores a
/// previously-saved string. **Does not** synthesize Cmd+V — that lives in
/// `PasteSynthesizer`. The split is deliberate (F4 split): the writer is
/// fully unit-testable; the synthesizer affects whatever app has focus and
/// is verified only by the manual integration checklist (M3).
final class ClipboardWriter {

    /// Result of a write: whether the OS accepted the string, plus the
    /// `.string` content we displaced (so the caller can restore it).
    struct WriteResult: Equatable {
        let success: Bool
        let savedString: String?
    }

    /// Saves the current `.string` content, then writes `text`. Returns
    /// `WriteResult.success == false` if `setString` failed (rare; macOS
    /// does this when a higher-priority pasteboard owner is established).
    @discardableResult
    func write(_ text: String) -> WriteResult {
        let pb = NSPasteboard.general
        let saved = pb.string(forType: .string)
        pb.clearContents()
        let ok = pb.setString(text, forType: .string)
        return WriteResult(success: ok, savedString: saved)
    }

    /// Restores `saved` to the pasteboard, but only if the pasteboard still
    /// holds `expectedCurrent`. If it changed (e.g., the user copied
    /// something else in the meantime) we leave the new content alone.
    func restore(saved: String?, ifCurrentIs expectedCurrent: String) {
        let pb = NSPasteboard.general
        guard pb.string(forType: .string) == expectedCurrent else {
            Log.paste.log("pasteboard changed externally; skipping restore")
            return
        }
        pb.clearContents()
        if let saved {
            pb.setString(saved, forType: .string)
        }
        Log.paste.log("pasteboard restored")
    }
}

// MARK: - PasteSynthesizer

/// Synthesizes a Cmd+V keystroke at HID level. **Affects whatever app has
/// focus** — never call from a unit test. Manual integration checklist M3
/// is the only verification path.
final class PasteSynthesizer {

    /// Posts Cmd+V. Returns `false` if the events could not be constructed
    /// (which is essentially never under macOS 13+, but we surface it).
    @discardableResult
    func synthesizeCmdV() -> Bool {
        let source = CGEventSource(stateID: .combinedSessionState)
        let v: CGKeyCode = 0x09 // ANSI 'V'

        guard let down = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: true),
              let up   = CGEvent(keyboardEventSource: source, virtualKey: v, keyDown: false) else {
            Log.paste.error("could not construct Cmd+V events")
            return false
        }
        down.flags = .maskCommand
        up.flags   = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        Log.paste.log("posted Cmd+V")
        return true
    }
}

// MARK: - Paster (orchestrator)

/// Single public entry point for posting text to the focused app. Routes
/// internally through `ClipboardWriter` (test-safe) and `PasteSynthesizer`
/// (untestable). Sauron rule: callers do not invoke writer/synth directly
/// in production code.
///
/// Sequence:
///   1. Save current `.string` clipboard content
///   2. Write the new text to the pasteboard
///   3. Synthesize Cmd+V (only if write succeeded — F11)
///   4. Restore the saved clipboard 600 ms later
///   5. Call `then()` on main
///
/// v1 only preserves the `.string` representation. Files, images, RTF,
/// etc. in the user's clipboard are lost. The pasteboard's `changeCount`
/// is bumped twice (write + restore) which pollutes clipboard managers
/// like Maccy / Paste — see `README.md` Limitations and F26 in the
/// review handoff.
@MainActor
final class Paster {

    /// Delay before clipboard restore. Long enough for the target app's
    /// paste implementation to read the pasteboard, short enough that the
    /// user doesn't notice.
    private static let restoreDelaySeconds: TimeInterval = 0.6

    private let writer: ClipboardWriter
    private let synthesizer: PasteSynthesizer

    init(writer: ClipboardWriter = ClipboardWriter(),
         synthesizer: PasteSynthesizer = PasteSynthesizer()) {
        self.writer = writer
        self.synthesizer = synthesizer
    }

    /// Posts `text` and calls `then` on the main thread once the restore
    /// completes. `then` is also called on the early-return paths (empty
    /// text or pasteboard write failed).
    func paste(_ text: String, then: @escaping @MainActor () -> Void) {
        guard !text.isEmpty else {
            Log.paste.log("skip paste: empty text")
            DispatchQueue.main.async { then() }
            return
        }

        let result = writer.write(text)
        guard result.success else {
            // F11: setString returned false. Don't post Cmd+V — that would
            // paste the user's previous clipboard content into their app.
            Log.paste.error("clipboard.setString returned false; aborting paste")
            DispatchQueue.main.async { then() }
            return
        }

        Log.paste.log("set pasteboard chars=\(text.count, privacy: .public)")
        synthesizer.synthesizeCmdV()

        let saved = result.savedString
        let writer = self.writer
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.restoreDelaySeconds) {
            writer.restore(saved: saved, ifCurrentIs: text)
            then()
        }
    }
}
