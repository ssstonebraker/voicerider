import Testing
@testable import VoiceRider

/// Pins `AppState.tag` values so trace lines stay grep-stable across refactors.
/// Changing a tag value breaks this test — intentional.
@Suite("AppState.tag")
struct StateTagTests {

    @Test("tag values are stable")
    func tagStability() {
        #expect(AppState.idle.tag == "idle")
        #expect(AppState.arming.tag == "arm")
        #expect(AppState.recording.tag == "rec")
        #expect(AppState.transcribing.tag == "tx")
        #expect(AppState.pasting.tag == "paste")
        #expect(AppState.error("anything").tag == "err")
    }

    @Test("error tag does not leak the error message")
    func errorTagOpaques() {
        let s = AppState.error("secret path /Users/foo")
        #expect(!s.tag.contains("secret"))
        #expect(!s.tag.contains("/Users"))
    }
}
