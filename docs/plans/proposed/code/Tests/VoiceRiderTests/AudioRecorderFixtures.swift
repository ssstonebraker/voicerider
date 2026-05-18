import Foundation
@testable import VoiceRider

/// Fixtures for `AudioRecorderEngineLifecycleTests`. Pins the M1
/// contract: after each step in an action sequence,
/// `recorder.engineIsRunning` matches the expected value.
///
/// **These fixtures drive a test that requires
/// `VOICERIDER_RUN_AUDIO_TESTS=1`.** Without that env var, the
/// `AVAudioEngine.start()` call would touch real audio hardware which
/// the default test target intentionally skips. See plan §8.7.
enum AudioRecorderFixtures {

    enum Action: String, CustomStringConvertible {
        case start
        case stop
        var description: String { rawValue }
    }

    struct LifecycleRow {
        let label: String
        let actions: [Action]
        /// `expected[i]` is the expected `engineIsRunning` AFTER
        /// `actions[i]` has been applied to a fresh recorder.
        let expected: [Bool]
    }

    static let all: [LifecycleRow] = [
        LifecycleRow(label: "stop on never-started engine is a no-op",
                     actions:  [.stop],
                     expected: [false]),

        LifecycleRow(label: "start then stop — M1 contract: orange dot only during recording",
                     actions:  [.start, .stop],
                     expected: [true, false]),

        LifecycleRow(label: "start, stop, start, stop — engine restarts cleanly",
                     actions:  [.start, .stop, .start, .stop],
                     expected: [true, false, true, false]),

        LifecycleRow(label: "stop is idempotent — second stop after first is no-op",
                     actions:  [.start, .stop, .stop],
                     expected: [true, false, false]),

        LifecycleRow(label: "start is idempotent — second start while running is no-op",
                     actions:  [.start, .start],
                     expected: [true, true]),
    ]
}
