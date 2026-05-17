import AppKit

/// A borderless, click-through `NSPanel` that floats above all other
/// windows while VoiceRider is in the `.recording` state, giving the
/// user a visible confirmation that audio is being captured.
///
/// Mirrors `StatusItemController`'s contract: `render(_:)` is called
/// from `AppDelegate.state.didSet` and is idempotent — the overlay
/// only animates on transitions into and out of `.recording`.
///
/// Click-through (`ignoresMouseEvents = true`) means the panel sits on
/// top visually but does not steal keyboard focus or block the
/// underlying app from receiving keystrokes — important because the
/// user is, by definition, holding a hotkey while it's visible.
@MainActor
final class RecordingOverlay {

    // MARK: Stored

    private let image: NSImage?
    private var window: NSPanel?
    private var lastWasRecording = false

    /// Test contract: `true` exactly when the most recent `render(_:)`
    /// transitioned the overlay into the visible state. Decoupled from
    /// the AppKit window so headless tests can verify the policy
    /// without booting `NSApplication`.
    private(set) var intendsToShow = false

    // MARK: Init

    /// Designated init. Tests pass `nil` (or a synthesized image) to
    /// exercise the policy without needing a bundled PDF resource.
    init(image: NSImage?) {
        self.image = image
    }

    /// Convenience for the running app: loads `RecordingOverlay.pdf`
    /// from the main bundle.
    convenience init() {
        let img = Bundle.main.url(forResource: "RecordingOverlay", withExtension: "pdf")
            .flatMap { NSImage(contentsOf: $0) }
        if img == nil {
            Log.app.error("RecordingOverlay.pdf not found in Bundle.main")
        }
        self.init(image: img)
    }

    // MARK: Render

    /// Called from the AppDelegate's `state` didSet. Show on entry
    /// into `.recording`, hide on exit. All other transitions are
    /// no-ops.
    func render(_ state: AppState) {
        let shouldShow = (state == .recording)
        defer { lastWasRecording = shouldShow }

        if shouldShow && !lastWasRecording {
            intendsToShow = true
            show()
        } else if !shouldShow && lastWasRecording {
            intendsToShow = false
            hide()
        }
    }

    // MARK: Window plumbing

    private func show() {
        guard let image else { return }
        let panel = window ?? makePanel(for: image)
        window = panel
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 1.0
        }
    }

    private func hide() {
        guard let panel = window else { return }
        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 0.0
        }, completionHandler: {
            panel.orderOut(nil)
        })
    }

    /// Build the panel lazily on first show. Centered horizontally on
    /// the active screen, just below the menu bar so it doesn't cover
    /// the active text caret.
    private func makePanel(for image: NSImage) -> NSPanel {
        let imageSize = image.size  // 690 × 530 from the SVG viewBox
        let aspect = imageSize.height / max(imageSize.width, 1)
        let screen = NSScreen.main ?? NSScreen.screens.first
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1280, height: 800)

        // Width: 1/4 of screen, clamped to a sensible range.
        let displayWidth = max(220, min(360, visible.width / 4))
        let displayHeight = displayWidth * aspect
        let frame = CGRect(
            x: visible.midX - displayWidth / 2,
            y: visible.maxY - displayHeight - 80,  // 80pt below top
            width: displayWidth,
            height: displayHeight)

        let panel = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]

        let imageView = NSImageView(frame: CGRect(origin: .zero, size: frame.size))
        imageView.image = image
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 20
        imageView.layer?.masksToBounds = true
        panel.contentView = imageView
        return panel
    }
}
