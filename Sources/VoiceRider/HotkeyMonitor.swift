import AppKit

/// Watches Right-Option globally and reports a four-stage lifecycle:
///   `onArm`     — Right-Option went down. Qualification window started.
///   `onCommit`  — Held alone past the window. Begin recording.
///   `onCancel`  — Another key was pressed during the window. Not dictation.
///   `onRelease` — Right-Option went up after `onCommit`. (Always paired.)
///
/// Right-Option is keycode `61`. The qualification window prevents
/// accidental triggers from short modifier presses that are part of normal
/// shortcuts.
///
/// ### Left/right disambiguation (F22 fix)
/// We **toggle** `rightOptDown` on every `keycode == 61` `flagsChanged`
/// event. The `.maskAlternate` bit is the OR of left+right and cannot be
/// used to tell us "is right-option specifically up now?" when the user
/// is also holding left-option.
///
/// ### Disqualifying-modifier checks (F6 + F23 fix)
///   - F6: at the moment Right-Option goes down, if any of `Cmd`, `Ctrl`,
///     `Shift` is *already* set in the event flags, we skip arming —
///     this is the user composing a shortcut, not dictating.
///   - F23: while we are inside the qualification window (armed but not
///     yet committed), any `flagsChanged` for a non-Right-Option keycode
///     also cancels arming.
///
/// ### Refcon retention (F12 fix)
/// The CGEventTap callback receives a `userInfo` pointer to `self`. We
/// `passRetained` so the pointer stays valid for the tap's lifetime; the
/// matching `release()` happens in `stop()` (called from `deinit`).
///
/// ### Threading
/// The tap callback runs on a Mach port. All state mutation and all
/// delivered callbacks happen on the main thread.
@MainActor
final class HotkeyMonitor {

    // MARK: Configuration

    /// Right-Option physical keycode.
    private static let rightOptKeycode: Int64 = 61

    /// Window in milliseconds during which the press can be cancelled by
    /// any other keydown or modifier change. Long enough to filter
    /// accidental quick taps; short enough that real dictation doesn't
    /// feel laggy.
    private static let qualifyMs: Int = 200

    /// Modifier bits whose presence at right-option-down means the user is
    /// composing a shortcut, not dictating.
    private static let disqualifyingMods: CGEventFlags = [
        .maskCommand, .maskControl, .maskShift,
    ]

    // MARK: Callbacks

    private let onArm:     () -> Void
    private let onCommit:  () -> Void
    private let onCancel:  () -> Void
    private let onRelease: () -> Void

    // MARK: State (main-thread only)

    private var tap: CFMachPort?
    private var runLoopSrc: CFRunLoopSource?
    /// Opaque pointer we passed to `CGEvent.tapCreate` as `userInfo`. We
    /// own a retain on `self` through this pointer; `stop()` releases it.
    private var refcon: UnsafeMutableRawPointer?
    private var rightOptDown = false
    private var armed        = false
    private var committed    = false
    private var armWork:     DispatchWorkItem?

    // MARK: Init / deinit

    init(onArm: @escaping () -> Void,
         onCommit: @escaping () -> Void,
         onCancel: @escaping () -> Void,
         onRelease: @escaping () -> Void) {
        self.onArm = onArm
        self.onCommit = onCommit
        self.onCancel = onCancel
        self.onRelease = onRelease
    }

    deinit {
        // Tear down the tap synchronously. `deinit` is nonisolated, but
        // these CF / DispatchWorkItem APIs are thread-safe to call here.
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let runLoopSrc {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSrc, .commonModes)
        }
        if let refcon {
            Unmanaged<HotkeyMonitor>.fromOpaque(refcon).release()
        }
    }

    // MARK: Public

    /// Installs the event tap. Returns `false` if either Accessibility or
    /// Input Monitoring is missing — caller should surface a permission
    /// error.
    func start() -> Bool {
        guard tap == nil else { return true }

        let mask = (1 << CGEventType.flagsChanged.rawValue) |
                   (1 << CGEventType.keyDown.rawValue)

        // F12: passRetained — the C tap holds a strong reference for its
        // lifetime. Matching release() lives in `stop()` / `deinit`.
        let retained = Unmanaged.passRetained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: HotkeyMonitor.callback,
            userInfo: retained
        ) else {
            // Tap creation failed; release the retain we just took.
            Unmanaged<HotkeyMonitor>.fromOpaque(retained).release()
            Log.hotkey.error("CGEvent.tapCreate returned nil — check Accessibility + Input Monitoring")
            return false
        }
        self.tap = tap
        self.refcon = retained

        let src = CFMachPortCreateRunLoopSource(nil, tap, 0)
        self.runLoopSrc = src
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        // R4-F31: seed `rightOptDown` from the **physical** key state so
        // we survive "user is already holding Right Option when the app
        // launches." Without this the first event we observe is the
        // release, which the toggle reads as "now down" → arm → 200ms
        // later commit → the app starts recording at launch with no
        // user intent.
        self.rightOptDown = CGEventSource.keyState(
            .combinedSessionState, key: CGKeyCode(Self.rightOptKeycode))
        Log.hotkey.log(
            "event tap installed; seeded rightOptDown=\(self.rightOptDown, privacy: .public)")
        return true
    }

    /// Tears down the tap explicitly (otherwise `deinit` does it). Safe to
    /// call multiple times.
    func stop() {
        if let tap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let runLoopSrc {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSrc, .commonModes)
        }
        if let refcon {
            Unmanaged<HotkeyMonitor>.fromOpaque(refcon).release()
        }
        tap = nil
        runLoopSrc = nil
        refcon = nil
    }

    // MARK: Callback

    /// C-callable trampoline. Re-enables the tap if the OS disabled it,
    /// then hops to main and dispatches into instance methods.
    private static let callback: CGEventTapCallBack = { _, type, event, ctx in
        // Re-enable on disable per Apple docs and SO/47265452. Without
        // this, a slow callback or system kill switch silently kills the
        // tap.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let ctx {
                let me = Unmanaged<HotkeyMonitor>.fromOpaque(ctx).takeUnretainedValue()
                DispatchQueue.main.async {
                    if let tap = me.tap {
                        CGEvent.tapEnable(tap: tap, enable: true)
                        Log.hotkey.log("event tap re-enabled after \(type.rawValue, privacy: .public)")
                    }
                }
            }
            return Unmanaged.passUnretained(event)
        }

        guard let ctx else { return Unmanaged.passUnretained(event) }
        let me = Unmanaged<HotkeyMonitor>.fromOpaque(ctx).takeUnretainedValue()

        // Snapshot fields off the C-thread event before dispatching.
        let keycode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags

        DispatchQueue.main.async {
            me.handleOnMain(type: type, keycode: keycode, flags: flags)
        }
        return Unmanaged.passUnretained(event)
    }

    // MARK: Main-thread state machine

    private func handleOnMain(type: CGEventType, keycode: Int64, flags: CGEventFlags) {
        switch type {
        case .flagsChanged:
            if keycode == Self.rightOptKeycode {
                handleRightOptionToggle(flags: flags)
            } else if rightOptDown && armed && !committed {
                // F23: any non-Right-Option modifier change while armed
                // means the user is composing a shortcut. Cancel.
                cancelArming(reason: "modifier change during qualify window")
            }

        case .keyDown:
            // Any real key press while armed but before commit means the
            // user is composing a shortcut, not dictating.
            if rightOptDown, armed, !committed {
                cancelArming(reason: "keyDown during qualify window")
            }

        default:
            return
        }
    }

    /// F22: drive the right-option state machine off the keycode-61 toggle
    /// rather than `.maskAlternate` (which is left|right OR'd and can't
    /// disambiguate when both Options are held).
    private func handleRightOptionToggle(flags: CGEventFlags) {
        if rightOptDown {
            // Was down → now up.
            rightOptDown = false
            armWork?.cancel()
            armWork = nil
            let wasCommitted = committed
            let wasArmed = armed
            armed = false
            committed = false
            // Only deliver onRelease if we actually committed (i.e.,
            // recording was started). Otherwise the release is silent —
            // a brief tap or a cancelled arm.
            if wasCommitted {
                onRelease()
            } else if wasArmed {
                // Arm fired but we never committed (released inside the
                // qualify window). Tell the delegate we're idle again.
                onCancel()
            }
            _ = flags // unused; sanity-check could assert .maskAlternate cleared
        } else {
            // Was up → now down.
            rightOptDown = true
            // F6: don't even arm if a disqualifying modifier is already
            // held when right-option goes down.
            if !flags.intersection(Self.disqualifyingMods).isEmpty {
                Log.hotkey.log("skip arm: disqualifying modifier held with right-option")
                return
            }
            armed = true
            committed = false
            onArm()

            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                guard self.rightOptDown, self.armed, !self.committed else { return }
                self.committed = true
                Log.hotkey.log("commit: held past qualify window")
                self.onCommit()
            }
            armWork = work
            DispatchQueue.main.asyncAfter(
                deadline: .now() + .milliseconds(Self.qualifyMs),
                execute: work)
        }
    }

    private func cancelArming(reason: String) {
        armWork?.cancel()
        armWork = nil
        armed = false
        Log.hotkey.log("cancel: \(reason, privacy: .public)")
        onCancel()
    }
}
