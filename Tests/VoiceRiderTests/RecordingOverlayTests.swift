import Testing
import AppKit
@testable import VoiceRider

/// Tests pin the policy contract — `intendsToShow` flips on entry to
/// `.recording` and back on exit. The actual `NSPanel` work happens in
/// `show()`/`hide()` and is exercised by the live `/Applications/VoiceRider.app`
/// integration; tests do not need an `NSApplication` to run.
@Suite("RecordingOverlay")
@MainActor
struct RecordingOverlayTests {

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
        #expect(overlay.intendsToShow == false)
        overlay.render(.arming)
        #expect(overlay.intendsToShow == false)
        overlay.render(.recording)
        #expect(overlay.intendsToShow == true)
        overlay.render(.transcribing)
        #expect(overlay.intendsToShow == false)
        overlay.render(.pasting)
        #expect(overlay.intendsToShow == false)
        overlay.render(.idle)
        #expect(overlay.intendsToShow == false)
    }

    @Test("error during recording immediately hides the overlay")
    func errorWhileRecordingHides() {
        let img = NSImage(size: NSSize(width: 10, height: 10))
        let overlay = RecordingOverlay(image: img)

        overlay.render(.recording)
        #expect(overlay.intendsToShow == true)
        overlay.render(.error("mic died"))
        #expect(overlay.intendsToShow == false)
    }
}
