// HotkeyMonitor unit tests were intentionally removed (F5 + F15).
//
// CGEventTap requires:
//   - a real GUI session,
//   - Accessibility + Input Monitoring grants,
//   - a UI-attached test runner that can post and receive global key events.
//
// None of that is available in `swift test`. Every assertion that *was*
// possible at the unit level (constants, init-doesn't-arm) was tautological
// and would not catch any defect — see Round-1 findings F5 and F15.
//
// The behaviour that matters (Right-Option dwell, cancel-on-shortcut,
// modifier disqualification, tap re-enable on disable) is verified by
// the manual integration checklist:
//
//   docs/plans/proposed/tests/manual-integration-checklist.md → M2
//
// Do not re-add unit tests here without exercising the actual tap.

import Testing

@Suite("HotkeyMonitor (placeholder — see manual M2)")
struct HotkeyMonitorTests {
    @Test("placeholder so the test target compiles")
    func placeholder() {
        #expect(Bool(true))
    }
}
