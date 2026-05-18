import Testing
import Foundation
@testable import VoiceRider

@Suite("PermissionStatus")
struct PermissionStatusTests {

    // MARK: PermissionService

    @Test("all services have unique rawValues")
    func allCasesUnique() {
        let raws = PermissionService.allCases.map(\.rawValue)
        #expect(raws.count == Set(raws).count)
    }

    @Test("settings URL maps to expected pane per service")
    func settingsURLMapping() {
        #expect(PermissionService.microphone.settingsURL?.absoluteString
                 == "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        #expect(PermissionService.accessibility.settingsURL?.absoluteString
                 == "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        #expect(PermissionService.inputMonitoring.settingsURL?.absoluteString
                 == "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")
    }

    @Test("display labels are user-facing, not enum-cased")
    func labelsAreFriendly() {
        #expect(PermissionService.microphone.label      == "Microphone")
        #expect(PermissionService.accessibility.label   == "Accessibility")
        #expect(PermissionService.inputMonitoring.label == "Input Monitoring")
    }

    // MARK: PermissionStatus

    @Test("granted glyph is ✓; denied glyph is ✗")
    func glyphReflectsGranted() {
        let g = PermissionStatus(service: .microphone, granted: true)
        let d = PermissionStatus(service: .microphone, granted: false)
        #expect(g.glyph == "✓")
        #expect(d.glyph == "✗")
    }

    @Test("menuTitle is glyph + space + label")
    func menuTitleFormat() {
        let s = PermissionStatus(service: .accessibility, granted: false)
        #expect(s.menuTitle == "✗ Accessibility")
    }

    // MARK: PermissionsSnapshot — fixture-driven (every 2^3 combo)

    @Test("every snapshot fixture has correct allGranted",
          arguments: PermissionStatusFixtures.snapshots)
    func allGrantedAcrossAllScenarios(row: PermissionStatusFixtures.SnapshotRow) {
        let snap = PermissionStatusFixtures.makeSnapshot(row)
        #expect(snap.allGranted == row.allGranted, "row '\(row.label)'")
    }

    @Test("every snapshot fixture has correct firstMissing",
          arguments: PermissionStatusFixtures.snapshots)
    func firstMissingAcrossAllScenarios(row: PermissionStatusFixtures.SnapshotRow) {
        let snap = PermissionStatusFixtures.makeSnapshot(row)
        #expect(snap.firstMissing?.service == row.firstMissing, "row '\(row.label)'")
    }

    @Test("snapshot.all returns three statuses in canonical order across all fixtures",
          arguments: PermissionStatusFixtures.snapshots)
    func allOrderInvariant(row: PermissionStatusFixtures.SnapshotRow) {
        let snap = PermissionStatusFixtures.makeSnapshot(row)
        #expect(snap.all.map(\.service) == [.microphone, .accessibility, .inputMonitoring])
    }
}

// MARK: - CDHashDetection (P3) — fixture-driven

@Suite("CDHashDetection")
struct CDHashDetectionTests {

    @Test("every cdhash fixture detects to its expected result",
          arguments: PermissionStatusFixtures.cdhash)
    func allFixturesDetect(row: PermissionStatusFixtures.CDHashRow) {
        let actual = CDHashDetection.detect(current: row.current, lastSeen: row.lastSeen)
        #expect(actual == row.expected, "row '\(row.label)' got \(actual)")
    }

    @Test("tag is stable per case")
    func tagStable() {
        #expect(CDHashDetection.detect(current: "a", lastSeen: nil).tag    == "first-launch")
        #expect(CDHashDetection.detect(current: "a", lastSeen: "a").tag   == "unchanged")
        #expect(CDHashDetection.detect(current: "a", lastSeen: "b").tag   == "changed")
    }
}
