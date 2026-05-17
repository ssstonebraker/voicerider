import Foundation
@testable import VoiceRider

/// Canonical fixtures for `Trace.format(tag:payload:)`.
///
/// Each row is a complete pinning of the formatter contract: given a
/// `tag` and `payload`, `Trace.format(...)` must produce `expected`
/// exactly. Adding a new trace point requires adding a fixture row;
/// changing an existing trace point's format breaks the corresponding
/// row visibly. See plan §8.6 + Appendix F.1.
enum TraceFixtures {

    struct Row {
        let label: String
        let tag: String
        let payload: String
        let expected: String
    }

    static let all: [Row] = [
        Row(label: "L1 tap-callback",
            tag: "trace:tap-callback",
            payload: "type=29 keycode=61 flagsRaw=40000",
            expected: "trace:tap-callback type=29 keycode=61 flagsRaw=40000"),

        Row(label: "L2 hk-keycode-match",
            tag: "trace:hk-keycode-match",
            payload: "keycode=61 isRightOpt=true type=12 armedActive=false",
            expected: "trace:hk-keycode-match keycode=61 isRightOpt=true type=12 armedActive=false"),

        Row(label: "L3 hk-toggle (down)",
            tag: "trace:hk-toggle",
            payload: "prev=false next=true",
            expected: "trace:hk-toggle prev=false next=true"),

        Row(label: "L4 hk-onarm",
            tag: "trace:hk-onarm",
            payload: "armed=true prev=false",
            expected: "trace:hk-onarm armed=true prev=false"),

        Row(label: "hk-oncommit",
            tag: "trace:hk-oncommit",
            payload: "committed=true",
            expected: "trace:hk-oncommit committed=true"),

        Row(label: "hk-commit-skip (R5)",
            tag: "trace:hk-commit-skip",
            payload: "rightOptDown=true armed=false committed=false",
            expected: "trace:hk-commit-skip rightOptDown=true armed=false committed=false"),

        Row(label: "hk-cancel (R5)",
            tag: "trace:hk-cancel",
            payload: "reason=keyDown during qualify window",
            expected: "trace:hk-cancel reason=keyDown during qualify window"),

        Row(label: "L5 ad-handlearm",
            tag: "trace:ad-handlearm",
            payload: "prev=idle",
            expected: "trace:ad-handlearm prev=idle"),

        Row(label: "L6 ad-handlecommit",
            tag: "trace:ad-handlecommit",
            payload: "prev=arm",
            expected: "trace:ad-handlecommit prev=arm"),

        Row(label: "L7 state-didset",
            tag: "trace:state-didset",
            payload: "prev=arm next=rec",
            expected: "trace:state-didset prev=arm next=rec"),

        Row(label: "L8 overlay-render",
            tag: "trace:overlay-render",
            payload: "state=rec shouldShow=true wasShowing=false",
            expected: "trace:overlay-render state=rec shouldShow=true wasShowing=false"),

        Row(label: "L10 overlay-show",
            tag: "trace:overlay-show",
            payload: "imageLoaded=true imageSize=320x240",
            expected: "trace:overlay-show imageLoaded=true imageSize=320x240"),

        Row(label: "L11 overlay-orderfront",
            tag: "trace:overlay-orderfront",
            payload: "frame=(100,100,320,240) level=20",
            expected: "trace:overlay-orderfront frame=(100,100,320,240) level=20"),

        Row(label: "D1 png-fallback",
            tag: "trace:D1-png-fallback",
            payload: "pdf=ok png=missing imageLoaded=true",
            expected: "trace:D1-png-fallback pdf=ok png=missing imageLoaded=true"),

        Row(label: "D4 frame-clamp",
            tag: "trace:D4-frame-clamp",
            payload: "raw=(0,0,1024,768) visible=(0,0,1024,743) clamped=(0,0,1024,743)",
            expected: "trace:D4-frame-clamp raw=(0,0,1024,768) visible=(0,0,1024,743) clamped=(0,0,1024,743)"),

        Row(label: "perms-snapshot",
            tag: "trace:perms-snapshot",
            payload: "mic=true acc=false inp=false",
            expected: "trace:perms-snapshot mic=true acc=false inp=false"),

        Row(label: "perms-cdhash (first launch)",
            tag: "trace:perms-cdhash",
            payload: "current=abc123 lastSeen=nil result=first-launch",
            expected: "trace:perms-cdhash current=abc123 lastSeen=nil result=first-launch"),

        // Empty-payload boundary: no trailing space.
        Row(label: "empty payload yields tag-only",
            tag: "trace:overlay-fadein-done",
            payload: "",
            expected: "trace:overlay-fadein-done"),
    ]
}
