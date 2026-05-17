import AppKit

/// A borderless, click-through `NSPanel` that floats above all other
/// windows while VoiceRider is in the `.recording` state, giving the
/// user a visible confirmation that audio is being captured.
///
/// Mirrors `StatusItemController`'s contract: `render(_:)` is called
/// from `AppDelegate.state.didSet` and is idempotent — the overlay
/// only animates on transitions into and out of `.recording`.
///
/// ### Trace points (overlay-diagnosis plan, links L8–L13)
///
///   - `trace:overlay-render`         — L8, every render(_:) call
///   - `trace:overlay-intends`        — L9, intendsToShow flip
///   - `trace:overlay-show`           — L10, show() entry, image load result
///   - `trace:overlay-orderfront`     — L11, after orderFrontRegardless
///   - `trace:overlay-fadein-done`    — L12, after fade-in animation completion
///   - `trace:D1-png-fallback`        — D1, PDF→PNG fallback chain result
///   - `trace:D4-frame-clamp`         — D4, frame raw / visible / clamped
///
/// ### Defensive fixes (D1–D5)
///
///   D1. PNG fallback if PDF fails. Checks `Bundle.main.url` for both
///       `RecordingOverlay.pdf` and `RecordingOverlay@2x.png`.
///   D2. Window level switched to `.popUpMenu` (was `.screenSaver`),
///       which is more reliable on macOS 13+ Stage Manager.
///   D3. Style mask reduced to `.borderless` (was
///       `[.borderless, .nonactivatingPanel]`). With
///       `ignoresMouseEvents = true` we already don't activate.
///   D4. Frame computed from `NSScreen.main!.frame`, then clamped to
///       `.visibleFrame` so the panel can't land in the menu-bar
///       exclusion zone or off the active screen.
///   D5. Image is force-rasterized via `setSize` + `lockFocus` once,
///       on the main thread, before assignment to NSImageView.
@MainActor
final class RecordingOverlay {

    // MARK: Bundle resolving (test seam)

    /// Test seam — production uses `BundleResolverDefault` which reads
    /// from `Bundle.main`. Tests can inject a synthetic resolver.
    protocol BundleResolving {
        func url(forResource: String, withExtension: String) -> URL?
    }

    private struct BundleResolverDefault: BundleResolving {
        func url(forResource name: String, withExtension ext: String) -> URL? {
            Bundle.main.url(forResource: name, withExtension: ext)
        }
    }

    // MARK: Stored

    private let image: NSImage?
    /// Original aspect ratio captured at init — immune to D5's setSize mutation.
    private let originalAspect: CGFloat
    private var window: NSPanel?
    private var lastWasRecording = false

    /// Test contract: `true` exactly when the most recent `render(_:)`
    /// transitioned the overlay into the visible state.
    private(set) var intendsToShow = false

    // MARK: Init

    /// Designated init. Tests pass `nil` (or a synthesized image) to
    /// exercise the policy without needing a bundled PDF resource.
    init(image: NSImage?) {
        self.image = image
        if let image {
            self.originalAspect = image.size.height / max(image.size.width, 1)
        } else {
            self.originalAspect = 1
        }
    }

    /// Convenience for the running app. D1 fallback chain: PDF first
    /// (vector, scalable), then PNG (raster, lower quality but more
    /// portable). Logs which path won.
    convenience init(resolver: BundleResolving = BundleResolverDefault()) {
        let img = Self.loadImage(resolver: resolver)
        self.init(image: img)
    }

    /// D1: try PDF, fall back to PNG. Trace either result.
    static func loadImage(resolver: BundleResolving) -> NSImage? {
        let pdfURL = resolver.url(forResource: "RecordingOverlay", withExtension: "pdf")
        let pngURL = resolver.url(forResource: "RecordingOverlay@2x", withExtension: "png")

        var pdfStatus = "missing"
        var pngStatus = "missing"
        var image: NSImage?

        if let pdfURL {
            if let img = NSImage(contentsOf: pdfURL) {
                image = img
                pdfStatus = "ok"
            } else {
                pdfStatus = "decode-fail"
            }
        }
        if image == nil, let pngURL {
            if let img = NSImage(contentsOf: pngURL) {
                image = img
                pngStatus = "ok"
            } else {
                pngStatus = "decode-fail"
            }
        }

        Trace.d("1-png-fallback", "pdf=\(pdfStatus) png=\(pngStatus) imageLoaded=\(image != nil)")
        if image == nil {
            Log.app.error("RecordingOverlay: both PDF and PNG failed to load (pdf=\(pdfStatus, privacy: .public) png=\(pngStatus, privacy: .public))")
        }
        return image
    }

    // MARK: Render

    /// Called from the AppDelegate's `state` didSet. Show on entry
    /// into `.recording`, hide on exit. All other transitions are
    /// no-ops.
    func render(_ state: AppState) {
        let shouldShow = (state == .recording)
        Trace.overlay("render", "state=\(state.tag) shouldShow=\(shouldShow) wasShowing=\(lastWasRecording)")
        defer { lastWasRecording = shouldShow }

        if shouldShow && !lastWasRecording {
            intendsToShow = true
            Trace.overlay("intends", "intendsToShow=true")
            show()
        } else if !shouldShow && lastWasRecording {
            intendsToShow = false
            Trace.overlay("intends", "intendsToShow=false")
            hide()
        }
    }

    // MARK: Window plumbing

    private func show() {
        guard let image else {
            Trace.overlay("show", "imageLoaded=false (skip)")
            return
        }
        Trace.overlay("show", "imageLoaded=true imageSize=\(Int(image.size.width))x\(Int(image.size.height))")

        let panel = window ?? makePanel(for: image)
        window = panel
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        Trace.overlay("orderfront", "frame=\(rectString(panel.frame)) level=\(panel.level.rawValue)")

        NSAnimationContext.runAnimationGroup({ ctx in
            ctx.duration = 0.15
            panel.animator().alphaValue = 1.0
        }, completionHandler: {
            Trace.overlay("fadein-done", "alpha=\(panel.alphaValue)")
        })
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

    /// Build the panel lazily on first show.
    ///
    /// D2: `.popUpMenu` window level (between app windows and system UI).
    /// D3: style mask reduced to `.borderless` only.
    /// D4: frame from full-screen `.frame` then clamped to `.visibleFrame`.
    /// D5: image rasterized at the panel size before assignment.
    private func makePanel(for image: NSImage) -> NSPanel {
        let aspect = originalAspect
        let screen = NSScreen.main ?? NSScreen.screens.first
        let fullFrame = screen?.frame ?? CGRect(x: 0, y: 0, width: 1280, height: 800)
        let visible   = screen?.visibleFrame ?? fullFrame

        let displayWidth = max(220, min(360, fullFrame.width / 4))
        let displayHeight = displayWidth * aspect

        let raw = CGRect(
            x: fullFrame.midX - displayWidth / 2,
            y: fullFrame.maxY - displayHeight - 80,
            width: displayWidth,
            height: displayHeight)

        // D4: clamp into visibleFrame so we never land under the menu bar
        // or off the active screen.
        let clamped = Self.clampRect(raw, into: visible)
        Trace.d("4-frame-clamp",
                "raw=\(rectString(raw)) visible=\(rectString(visible)) clamped=\(rectString(clamped))")

        // D3 reverted: .nonactivatingPanel is REQUIRED for LSUIElement apps.
        // Without it, orderFrontRegardless triggers a silent app-activation
        // attempt that fails (the app has no activation policy), and the
        // window's alpha=1 but it's not visible to the user.
        let panel = NSPanel(
            contentRect: clamped,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false)
        // D2: popUpMenu instead of screenSaver
        panel.level = NSWindow.Level(
            rawValue: Int(CGWindowLevelForKey(.popUpMenuWindow)))
        panel.isOpaque = false
        panel.backgroundColor = NSColor.clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle] as NSWindow.CollectionBehavior

        // D5: set the display size on the image view's own image instance.
        // Do NOT mutate self.image — that would corrupt originalAspect on
        // subsequent makePanel calls.
        let displayImage = image.copy() as? NSImage ?? image
        displayImage.size = NSSize(width: clamped.width, height: clamped.height)

        let imageView = NSImageView(frame: CGRect(origin: .zero, size: clamped.size))
        imageView.image = displayImage
        imageView.imageScaling = NSImageScaling.scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.cornerRadius = 20
        imageView.layer?.masksToBounds = true
        panel.contentView = imageView
        return panel
    }

    // MARK: Helpers

    /// Stable rect formatter for trace output.
    private func rectString(_ r: CGRect) -> String {
        "(\(Int(r.origin.x)),\(Int(r.origin.y)),\(Int(r.size.width))x\(Int(r.size.height)))"
    }

    /// D4 clamp helper. Pure function; tested in `RecordingOverlayTests.frameClampStaysInVisible`.
    static func clampRect(_ rect: CGRect, into bounds: CGRect) -> CGRect {
        let w = min(rect.width, bounds.width)
        let h = min(rect.height, bounds.height)
        let x = min(max(rect.origin.x, bounds.minX), bounds.maxX - w)
        let y = min(max(rect.origin.y, bounds.minY), bounds.maxY - h)
        return CGRect(x: x, y: y, width: w, height: h)
    }
}
