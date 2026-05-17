import Testing
@testable import VoiceRider

@Suite("AppState")
struct StateTests {

    @Test("idle equals idle")
    func idleEqualsIdle() {
        #expect(AppState.idle == .idle)
    }

    @Test("error cases compare by message")
    func errorEqualityByMessage() {
        #expect(AppState.error("boom") == .error("boom"))
        #expect(AppState.error("boom") != .error("BOOM"))
    }

    @Test("distinct cases are not equal")
    func distinctCasesNotEqual() {
        #expect(AppState.idle != .recording)
        #expect(AppState.recording != .transcribing)
        #expect(AppState.transcribing != .pasting)
        #expect(AppState.arming != .recording)
    }

    @Test("error case pattern-matches even with different messages")
    func errorPatternMatch() {
        let s = AppState.error("anything")
        var matched = false
        if case .error = s { matched = true }
        #expect(matched)
    }
}
