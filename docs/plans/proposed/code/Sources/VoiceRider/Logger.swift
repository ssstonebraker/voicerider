import Foundation
import os

/// Centralised loggers. One subsystem ("com.voicerider") + a category per
/// module so `log show --predicate 'subsystem == "com.voicerider"'` filters
/// the whole app at once.
///
/// Steering rule: never use `print(...)` for runtime logging.
///
/// Privacy rule: do **not** log user content with `privacy: .public`.
/// Specifically, **never** log:
///   - the transcribed text returned by the ASR server
///   - the contents of `NSPasteboard.general`
///   - the body of any HTTP request that contains audio bytes
///
/// `privacy: .public` defeats automatic redaction in `os_log`. Only
/// metadata (counts, sizes, status codes, error categories) and
/// developer-controlled constants are safe to mark `.public`. File system
/// paths often include the user's short username (`/var/folders/.../`)
/// and should be `.private`.
///
/// ### `trace` category
///
/// `Log.trace` is the diagnostic firehose used by the press → overlay
/// chain instrumentation. It is **only** emitted via the `Trace` enum
/// in `Trace.swift` (single ingress point — Sauron rule). Filter with:
///
///     log show --predicate 'subsystem == "com.voicerider" AND category == "trace"'
///
/// or use the helper `./scripts/show-voicerider-trace.sh`.
enum Log {
    static let app        = Logger(subsystem: "com.voicerider", category: "app")
    static let hotkey     = Logger(subsystem: "com.voicerider", category: "hotkey")
    static let audio      = Logger(subsystem: "com.voicerider", category: "audio")
    static let transcribe = Logger(subsystem: "com.voicerider", category: "transcribe")
    static let paste      = Logger(subsystem: "com.voicerider", category: "paste")
    static let perms      = Logger(subsystem: "com.voicerider", category: "perms")
    static let trace      = Logger(subsystem: "com.voicerider", category: "trace")
}
