import Testing
import AppKit
@testable import VoiceRider

@Suite("RecordingOverlay")
@MainActor
struct RecordingOverlayTests {

    // MARK: Existing policy tests (kept from v0.1.0)

    @Test("init with nil image does not crash and starts hidden")
    func initNilImageHidden() {
        let overlay = RecordingOverlay(image: nil)
        #expect(overlay.intendsToShow == false)
    }

    @Test("init with a synthesized image starts hidden")
    func initWithImageHidden() {
        let img = NSImage(size: NSSize(width: 10, height: 10))
        let overlay = RecordingOverlay(image: img)
        #expect(overlay.intendsToShow == false)
    }

    @Test("render(.recording) flips intendsToShow on; render(.idle) flips it off")
    func recordingTogglesIntent() {
        let img = NSImage(size: NSSize(width: 10, height: 10))
        let overlay = RecordingOverlay(image: img)
        overlay.render(.recording)
        #expect(overlay.intendsToShow == true)
        overlay.render(.idle)
        #expect(overlay.intendsToShow == false)
    }

    @Test("render is idempotent within the recording state")
    func recordingIdempotent() {
        let img = NSImage(size: NSSize(width: 10, height: 10))
        let overlay = RecordingOverlay(image: img)
        overlay.render(.recording)
        overlay.render(.recording)
        overlay.render(.recording)
        #expect(overlay.intendsToShow == true)
    }

    @Test("render is idempotent in the hidden states")
    func hiddenIdempotent() {
        let overlay = RecordingOverlay(image: nil)
        for s: AppState in [.idle, .arming, .transcribing, .pasting, .error("x")] {
            overlay.render(s)
            #expect(overlay.intendsToShow == false)
        }
    }

    @Test("non-recording states never show the overlay")
    func nonRecordingNeverShows() {
        let img = NSImage(size: NSSize(width: 10, height: 10))
        let overlay = RecordingOverlay(image: img)
        for s: AppState in [.idle, .arming, .transcribing, .pasting, .error("boom")] {
            overlay.render(s)
            #expect(overlay.intendsToShow == false, "state \(s) wrongly showed overlay")
        }
    }

    @Test("recording → transcribing → idle path: shown then hidden")
    func recordingToTranscribingToIdle() {
        let img = NSImage(size: NSSize(width: 10, height: 10))
        let overlay = RecordingOverlay(image: img)
        overlay.render(.idle)
        overlay.render(.arming)
        overlay.render(.recording)
        #expect(overlay.intendsToShow == true)
        overlay.render(.transcribing)
        #expect(overlay.intendsToShow == false)
        overlay.render(.pasting)
        overlay.render(.idle)
        #expect(overlay.intendsToShow == false)
    }

    @Test("error during recording immediately hides the overlay")
    func errorWhileRecordingHides() {
        let img = NSImage(size: NSSize(width: 10, height: 10))
        let overlay = RecordingOverlay(image: img)
        overlay.render(.recording)
        overlay.render(.error("mic died"))
        #expect(overlay.intendsToShow == false)
    }

    // MARK: D1 — PNG fallback

    /// Test resolver that synthesises whichever resources we want present.
    private struct TestResolver: RecordingOverlay.BundleResolving {
        let pdfURL: URL?
        let pngURL: URL?
        func url(forResource name: String, withExtension ext: String) -> URL? {
            switch (name, ext) {
            case ("RecordingOverlay", "pdf"):     return pdfURL
            case ("RecordingOverlay@2x", "png"):  return pngURL
            default: return nil
            }
        }
    }

    @Test("loadImage with neither PDF nor PNG returns nil")
    func loadImageNeitherResource() {
        let resolver = TestResolver(pdfURL: nil, pngURL: nil)
        let img = RecordingOverlay.loadImage(resolver: resolver)
        #expect(img == nil)
    }

    @Test("loadImage with a missing PDF and present PNG falls back to PNG")
    func loadImagePNGFallback() throws {
        // Synthesise a tiny PNG on disk and point the resolver at it.
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("rec-overlay-test-\(UUID()).png")
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 4, pixelsHigh: 4,
            bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 16, bitsPerPixel: 32)!
        let pngData = bitmap.representation(using: .png, properties: [:])!
        try pngData.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let resolver = TestResolver(pdfURL: nil, pngURL: tmp)
        let img = RecordingOverlay.loadImage(resolver: resolver)
        #expect(img != nil)
    }

    // MARK: D4 — frame clamping (fixture-driven)

    @Test("every clamp fixture stays within its bounds and satisfies its assertion",
          arguments: RecordingOverlayFixtures.clamp)
    func clampFixtures(row: RecordingOverlayFixtures.ClampRow) {
        let clamped = RecordingOverlay.clampRect(row.raw, into: row.bounds)
        // Universal invariants:
        #expect(clamped.minX >= row.bounds.minX, "row '\(row.label)' x below bounds")
        #expect(clamped.minY >= row.bounds.minY, "row '\(row.label)' y below bounds")
        #expect(clamped.maxX <= row.bounds.maxX, "row '\(row.label)' x above bounds")
        #expect(clamped.maxY <= row.bounds.maxY, "row '\(row.label)' y above bounds")
        // Per-row assertion:
        #expect(row.validate(clamped), "row '\(row.label)' clamp=\(clamped) failed validate")
    }

    @Test("clampRect is idempotent — clamp(clamp(r)) == clamp(r)")
    func clampIdempotent() {
        for row in RecordingOverlayFixtures.clamp {
            let once  = RecordingOverlay.clampRect(row.raw, into: row.bounds)
            let twice = RecordingOverlay.clampRect(once,    into: row.bounds)
            #expect(once == twice, "row '\(row.label)' not idempotent")
        }
    }
}
