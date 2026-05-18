import Foundation
@testable import VoiceRider

/// Frame-clamp fixtures for `RecordingOverlay.clampRect(_:into:)`.
/// Pins the D4 defensive-fix behavior across the screen geometries
/// VoiceRider users actually encounter. See plan §8.6 + Appendix F.3.
enum RecordingOverlayFixtures {

    struct ClampRow {
        let label: String
        let raw: CGRect
        let bounds: CGRect
        /// Closure-based assertion — many clamp outcomes have a
        /// "must satisfy" relation rather than a single equality.
        let validate: (CGRect) -> Bool
    }

    static let clamp: [ClampRow] = [
        ClampRow(label: "default 1024×768; centered fits",
                 raw: CGRect(x: 412, y: 250, width: 200, height: 154),
                 bounds: CGRect(x: 0, y: 0, width: 1024, height: 768),
                 validate: { $0 == CGRect(x: 412, y: 250, width: 200, height: 154) }),

        ClampRow(label: "notched MBP M3 16\"; raw above visible top → y clamps down",
                 raw: CGRect(x: 684, y: 1100, width: 360, height: 277),
                 bounds: CGRect(x: 0, y: 0, width: 1728, height: 1079),
                 validate: { $0.maxY <= 1079 }),

        ClampRow(label: "external 4K 3840×2160; raw fits → identity",
                 raw: CGRect(x: 1740, y: 80, width: 360, height: 277),
                 bounds: CGRect(x: 0, y: 0, width: 3840, height: 2120),
                 validate: { $0 == CGRect(x: 1740, y: 80, width: 360, height: 277) }),

        ClampRow(label: "ultra-wide 5120×1440; oversize raw → fills bounds",
                 raw: CGRect(x: 0, y: 0, width: 9999, height: 9999),
                 bounds: CGRect(x: 0, y: 0, width: 5120, height: 1440),
                 validate: { $0 == CGRect(x: 0, y: 0, width: 5120, height: 1440) }),

        ClampRow(label: "vertical 1080×1920; very tall raw → height clamps",
                 raw: CGRect(x: 0, y: 0, width: 200, height: 5000),
                 bounds: CGRect(x: 0, y: 0, width: 1080, height: 1920),
                 validate: { $0.height == 1920 && $0.width == 200 }),

        ClampRow(label: "Mac mini 1280×800; raw below origin → y clamps up",
                 raw: CGRect(x: 530, y: -50, width: 220, height: 169),
                 bounds: CGRect(x: 0, y: 0, width: 1280, height: 800),
                 validate: { $0.minY >= 0 }),
    ]
}
