import Foundation
import os

/// Typed wrapper around `Log.trace` with stable, greppable tag prefixes.
///
/// **Why this exists.** The diagnosis plan
/// (`docs/plans/20260517T1535-overlay-diagnosis-plan.md`) places trace points
/// at every link of the press → overlay chain. Free-form `Log.trace.debug(...)`
/// calls drift over time — tags get reworded, fields get inconsistent — and
/// the trace stops being grep-stable. This wrapper makes tags compile-time
/// constants and the formatted message a single shape per link.
///
/// **R1 — pure formatter.** `format(tag:payload:)` is a pure function. The
/// `emit` path calls it. Tests don't need to read back from `os.Logger`
/// (which would require entitlements); they assert directly on the
/// formatter output via `TraceFixtures`. See §8.6 + Appendix F of the plan.
///
/// **Privacy contract.** This file MUST NOT accept transcribed text,
/// pasteboard contents, or audio bytes. Each method takes a metadata-only
/// payload (small string of integers, hex flags, state tags). The
/// underlying `Log.trace.debug(...)` uses `privacy: .public` for these
/// metadata payloads.
///
/// **Sauron compliance.** This is the single ingress point for the
/// `com.voicerider:trace` category. Production code must not emit to
/// that category by any other path. Tests verify uniqueness via
/// `TraceTests.allFixturesFormat`.
///
/// **Annie compliance.** Every static method below has at least one caller
/// in `Sources/VoiceRider/`. If a method ever becomes orphaned, delete it.
enum Trace {

    // MARK: Pure formatter (R1)

    /// Format a trace line. Pure — no side effects, no I/O, deterministic.
    /// Tests in `TraceTests.allFixturesFormat` pin the output for every
    /// row in `TraceFixtures.all`.
    ///
    /// Empty payload → just the tag, no trailing space.
    static func format(tag: String, payload: String) -> String {
        payload.isEmpty ? tag : "\(tag) \(payload)"
    }

    // MARK: HotkeyMonitor links (L1–L4 + commit/skip/cancel)

    static func tap(_ event: String, _ payload: String) {
        emit("trace:tap-\(event)", payload)
    }

    static func hk(_ event: String, _ payload: String) {
        emit("trace:hk-\(event)", payload)
    }

    // MARK: AppDelegate links (L5–L7)

    static func ad(_ event: String, _ payload: String) {
        emit("trace:ad-\(event)", payload)
    }

    static func state(prev: String, next: String) {
        emit("trace:state-didset", "prev=\(prev) next=\(next)")
    }

    // MARK: RecordingOverlay links (L8–L13)

    static func overlay(_ event: String, _ payload: String) {
        emit("trace:overlay-\(event)", payload)
    }

    /// Defensive-fix tags (D1–D5).
    static func d(_ id: String, _ payload: String) {
        emit("trace:D\(id)", payload)
    }

    // MARK: Permission UX (P1–P3)

    static func perms(_ event: String, _ payload: String) {
        emit("trace:perms-\(event)", payload)
    }

    // MARK: Settings window (S1–S17)

    static func settings(_ event: String, _ payload: String) {
        emit("trace:settings-\(event)", payload)
    }

    // MARK: Underlying emit

    private static func emit(_ tag: String, _ payload: String) {
        let line = format(tag: tag, payload: payload)
        Log.trace.info("\(line, privacy: .public)")
    }
}
