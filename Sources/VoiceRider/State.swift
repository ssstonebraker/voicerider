import Foundation

/// The complete user-visible state of VoiceRider.
///
/// One value of this type is the single source of truth (Sauron rule, see
/// `.kiro/steering/no-orphans-no-dual-paths.md`). No subsystem may track
/// "am I recording?" with its own Bool — they read this enum.
///
/// ```
/// idle ──arm──▶ arming ──commit──▶ recording ──release──▶ transcribing
///                  │                                            │
///                  └──cancel/release──▶ idle                    │
///                                                               ▼
///                                                            pasting
///                                                               │
///                                                               ▼
/// error(String) ◀── (any failure) ──┐                          idle
///        │                           │
///        └─── 2s timeout ──▶ idle   ─┘
/// ```
enum AppState: Equatable {
    /// Hotkey not held. Listening for the next press.
    case idle

    /// Hotkey just went down. We are inside the qualification window
    /// (default 200 ms). If another key is pressed or the hotkey is
    /// released early, this returns to `.idle` without recording.
    case arming

    /// Hotkey held past the qualification window. Audio is being captured.
    case recording

    /// Hotkey released; uploading the WAV to the ASR server.
    case transcribing

    /// Server returned text; pasteboard is set; Cmd+V was synthesized;
    /// waiting for the target app to consume it before restoring the
    /// user's previous clipboard.
    case pasting

    /// Something failed. The associated value is shown as a tooltip on the
    /// menu-bar icon. The state auto-clears to `.idle` after 2 seconds.
    case error(String)
}
