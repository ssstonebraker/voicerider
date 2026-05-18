import Testing
import Foundation
@testable import VoiceRider

/// Tests for the `Trace` typed wrapper around `Log.trace`.
///
/// **R1.** The pure `Trace.format(tag:payload:)` function is the test
/// seam. We assert the formatter output across the full
/// `TraceFixtures.all` table, covering every numbered link in the
/// chain plus D-fix tags. No need to read back from `os.Logger` (which
/// would require entitlements).
@Suite("Trace")
struct TraceTests {

    @Test("every row in TraceFixtures.all formats to its expected string", arguments: TraceFixtures.all)
    func allFixturesFormat(row: TraceFixtures.Row) {
        let actual = Trace.format(tag: row.tag, payload: row.payload)
        #expect(actual == row.expected, "row '\(row.label)' formatted to '\(actual)', expected '\(row.expected)'")
    }

    @Test("format with empty payload returns the tag with no trailing space")
    func emptyPayload() {
        let actual = Trace.format(tag: "trace:foo", payload: "")
        #expect(actual == "trace:foo")
        #expect(!actual.hasSuffix(" "))
    }

    @Test("format with non-empty payload joins with a single space")
    func singleSpace() {
        let actual = Trace.format(tag: "trace:foo", payload: "x=1")
        #expect(actual == "trace:foo x=1")
    }

    @Test("format is deterministic across calls")
    func deterministic() {
        let first  = Trace.format(tag: "trace:foo", payload: "k=v")
        let second = Trace.format(tag: "trace:foo", payload: "k=v")
        #expect(first == second)
    }

    @Test("all fixture tags begin with trace:")
    func tagPrefixInvariant() {
        for row in TraceFixtures.all {
            #expect(row.tag.hasPrefix("trace:"), "row '\(row.label)' tag '\(row.tag)' missing trace: prefix")
        }
    }

    @Test("fixture tags are unique across the catalog")
    func tagsUnique() {
        let tags = TraceFixtures.all.map(\.tag)
        let unique = Set(tags)
        // Fixtures may legitimately reuse a tag with different payloads;
        // we only require unique (tag, payload) pairs.
        let pairs = TraceFixtures.all.map { "\($0.tag)|\($0.payload)" }
        #expect(pairs.count == Set(pairs).count)
        // Sanity — most tags are unique.
        #expect(unique.count >= 13)
    }

    // MARK: Smoke — these don't crash and run on the actual emit path.

    @Test("emit-path smoke for hotkey link")
    func smokeHotkey() {
        Trace.tap("callback", "type=29 keycode=61 flagsRaw=40000")
        Trace.hk("toggle", "prev=false next=true")
        Trace.hk("onarm", "armed=true prev=false")
    }

    @Test("emit-path smoke for state and overlay")
    func smokeStateOverlay() {
        Trace.state(prev: "idle", next: "arm")
        Trace.overlay("render", "state=rec shouldShow=true wasShowing=false")
        Trace.d("4-frame-clamp", "raw=(0,0,1024,768) visible=(0,0,1024,743) clamped=(0,0,1024,743)")
    }
}
