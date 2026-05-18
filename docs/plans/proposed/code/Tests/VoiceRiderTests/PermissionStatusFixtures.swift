import Foundation
@testable import VoiceRider

/// Fixtures for `PermissionsSnapshot` and `CDHashDetection`.
/// See plan §8.6 + Appendix F.2.
enum PermissionStatusFixtures {

    // MARK: Snapshot fixtures (8 = 2^3 combinations)

    struct SnapshotRow {
        let label: String
        let mic: Bool
        let acc: Bool
        let inp: Bool
        let allGranted: Bool
        let firstMissing: PermissionService?
    }

    static let snapshots: [SnapshotRow] = [
        SnapshotRow(label: "all granted",
                    mic: true,  acc: true,  inp: true,
                    allGranted: true,  firstMissing: nil),

        SnapshotRow(label: "input-monitoring missing",
                    mic: true,  acc: true,  inp: false,
                    allGranted: false, firstMissing: .inputMonitoring),

        SnapshotRow(label: "accessibility missing",
                    mic: true,  acc: false, inp: true,
                    allGranted: false, firstMissing: .accessibility),

        SnapshotRow(label: "accessibility + input-monitoring missing",
                    mic: true,  acc: false, inp: false,
                    allGranted: false, firstMissing: .accessibility),

        SnapshotRow(label: "microphone missing",
                    mic: false, acc: true,  inp: true,
                    allGranted: false, firstMissing: .microphone),

        SnapshotRow(label: "microphone + input-monitoring missing",
                    mic: false, acc: true,  inp: false,
                    allGranted: false, firstMissing: .microphone),

        SnapshotRow(label: "microphone + accessibility missing",
                    mic: false, acc: false, inp: true,
                    allGranted: false, firstMissing: .microphone),

        SnapshotRow(label: "everything denied (fresh install)",
                    mic: false, acc: false, inp: false,
                    allGranted: false, firstMissing: .microphone),
    ]

    static func makeSnapshot(_ row: SnapshotRow) -> PermissionsSnapshot {
        PermissionsSnapshot(
            microphone:      PermissionStatus(service: .microphone,      granted: row.mic),
            accessibility:   PermissionStatus(service: .accessibility,   granted: row.acc),
            inputMonitoring: PermissionStatus(service: .inputMonitoring, granted: row.inp))
    }

    // MARK: cdhash detection fixtures

    struct CDHashRow {
        let label: String
        let current: String
        let lastSeen: String?
        let expected: CDHashDetectionResult
    }

    static let cdhash: [CDHashRow] = [
        CDHashRow(label: "first launch — lastSeen nil",
                  current: "abc", lastSeen: nil,
                  expected: .firstLaunch),

        CDHashRow(label: "unchanged — same hash both sides",
                  current: "abc", lastSeen: "abc",
                  expected: .unchanged),

        CDHashRow(label: "changed — different hash",
                  current: "abc", lastSeen: "xyz",
                  expected: .changed(from: "xyz", to: "abc")),

        CDHashRow(label: "edge: empty current with nil lastSeen",
                  current: "", lastSeen: nil,
                  expected: .firstLaunch),

        CDHashRow(label: "edge: empty lastSeen counts as a real previous",
                  current: "abc", lastSeen: "",
                  expected: .changed(from: "", to: "abc")),
    ]
}
