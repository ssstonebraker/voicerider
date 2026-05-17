import AppKit

/// VoiceRider is a menu-bar accessory app. Activation policy + LSUIElement
/// keep it out of the Dock and Cmd-Tab. We construct the delegate
/// inside a `@MainActor`-isolated entry point so under Swift 6 strict
/// concurrency the call to `AppDelegate()` is statically isolated.
///
/// Using `@main` on a `MainActor` struct (instead of a `main.swift`
/// file) makes the entry point's actor context explicit.
@main
@MainActor
enum VoiceRiderApp {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
    }
}
