import Testing
@testable import VoiceRider

/// Fixture-based coverage of `AppState`. The state machine is the
/// single source of truth (Sauron rule); these tests pin its
/// equality semantics so a future refactor can't silently change
/// them.
@Suite("AppStateFixtures")
struct AppStateFixtures {

    /// Every legal AppState case, in canonical order. Used for
    /// pairwise inequality checks.
    private static let allCases: [AppState] = [
        .idle, .arming, .recording, .transcribing, .pasting, .error("E"),
    ]

    @Test("self-equality holds for every case")
    func selfEquality() {
        for s in Self.allCases {
            #expect(s == s, "\(s) != \(s)")
        }
    }

    @Test("distinct cases are not equal — pairwise")
    func pairwiseInequality() {
        for (i, a) in Self.allCases.enumerated() {
            for (j, b) in Self.allCases.enumerated() where i != j {
                #expect(a != b, "\(a) == \(b)")
            }
        }
    }

    @Test("error cases compare by associated message")
    func errorAssociatedValueEquality() {
        #expect(AppState.error("boom") == .error("boom"))
        #expect(AppState.error("boom") != .error("BOOM"))
        #expect(AppState.error("") != .error("x"))
        #expect(AppState.error("a") != .error("a "))
    }

    @Test("error pattern-matches with `case` regardless of message")
    func errorPatternMatches() {
        for msg in ["", "x", "longer error message", "Unicode héllo"] {
            let s = AppState.error(msg)
            var matched = false
            if case .error = s { matched = true }
            #expect(matched, "case .error did not match for \(msg.debugDescription)")
        }
    }

    @Test("non-error cases do not pattern-match `case .error`")
    func nonErrorDoesNotMatchError() {
        for s in [AppState.idle, .arming, .recording, .transcribing, .pasting] {
            var matched = false
            if case .error = s { matched = true }
            #expect(!matched, "non-error \(s) matched .error")
        }
    }

    @Test("error message preserves Unicode and edge characters")
    func errorMessagePreservation() {
        let messages = [
            "",
            "ASCII only",
            "Unicode 世界",
            "with newline\nin it",
            "with quote \"in it\"",
            "very long: " + String(repeating: "x", count: 1024),
        ]
        for m in messages {
            let s = AppState.error(m)
            guard case .error(let captured) = s else {
                Issue.record("not an error case for \(m.debugDescription)")
                continue
            }
            #expect(captured == m,
                    "message lost for \(m.debugDescription): got \(captured.debugDescription)")
        }
    }
}
