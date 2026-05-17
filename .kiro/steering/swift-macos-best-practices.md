---
inclusion: auto
name: swift-macos-best-practices
description: >
  Swift and macOS app best practices for this project. Triggered by: any Swift
  file change, AVFoundation, CGEvent, NSStatusItem, AppKit, Info.plist, ATS,
  permissions, codesign, AVAudioEngine, AVAudioConverter, NSPasteboard.
---

# Swift / macOS Best Practices — VoiceRider Project

These are the rules every change in this repo must follow. Sources are cited
inline so you can verify before deviating.

---

## 1. SWIFT LANGUAGE RULES

See `swift-coding-best-practices.md`. That file is the single source of
truth for naming, type design, optionals, error handling, concurrency,
memory, access control, testing, and style. This file does **not**
re-state any of those rules — it covers only macOS-API specifics.

---

## 2. APPKIT / MENU-BAR APP

Source: Stack Overflow [24136402](https://stackoverflow.com/questions/24136402/),
Apple AppKit reference, [openillumi article](https://openillumi.com/en/en-swiftui-macos-status-bar-icon-nshostingview/).

### Hiding from the Dock
- `LSUIElement` = `true` in `Info.plist`. Do **not** also set
  `LSBackgroundOnly`; that hides the menu-bar icon too.
- In code, call `NSApplication.shared.setActivationPolicy(.accessory)` so a
  menu pop-up doesn't spuriously activate the app.

### `NSStatusItem`
- Create with
  `NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)`.
- **Retain it as a strong property on a long-lived object.** A common bug
  (SO 24136402) is letting it deinit immediately and the icon disappears.
- Set `button.image` with an `NSImage(systemSymbolName:)` and
  `image.isTemplate = true` so it adapts to dark/light menu-bar appearance.
- Set `button.toolTip` to the current state for accessibility and debugging.

### Threading
- All `NSStatusItem`, `NSMenu`, and `NSPasteboard` work happens on the main
  thread. If you're inside a URLSession completion handler, hop main first.

---

## 3. AUDIO CAPTURE — AVAudioEngine

Source: Stack Overflow [49370169](https://stackoverflow.com/questions/49370169/),
Apple Developer Forum thread 68828, Apple Developer Forum 698535.

### Tap on the input node, do not impose a format on the tap
- `engine.inputNode.installTap(onBus: 0, bufferSize: 1024, format: nil)` lets
  the OS pick the hardware native format (commonly 48 kHz Float32 mono on
  Apple Silicon). Passing a mismatched format silently produces silence or
  crashes on AirPods.
- Use `let inputFormat = inputNode.outputFormat(forBus: 0)` to read whatever
  the hardware decided to give you.

### Convert with `AVAudioConverter`
- Build a target `AVAudioFormat(commonFormat: .pcmFormatInt16,
  sampleRate: 16_000, channels: 1, interleaved: true)` for ASR-friendly WAV.
- `AVAudioConverter(from: inputFormat, to: outputFormat)` handles resampling
  and channel mixing. Do not hand-roll this.
- The converter's input block must return `.haveData` exactly once per call,
  then `.noDataNow` if asked again before the next buffer arrives. Signature
  pattern is in `AudioRecorder.swift`.

### File writing
- `AVAudioFile(forWriting:settings:commonFormat:interleaved:)` — pass an
  explicit settings dict (`AVFormatIDKey` = `kAudioFormatLinearPCM`,
  `AVLinearPCMBitDepthKey` = 16, `AVLinearPCMIsFloatKey` = false,
  `AVLinearPCMIsBigEndianKey` = false). Without this you get a CAF, not a
  proper RIFF WAV, and ASR servers may reject it.
- Writing from inside the tap callback is fine — the tap runs on a real-time
  audio thread, but `AVAudioFile.write(from:)` is documented as safe for that
  context.

### Engine lifecycle
- Cold-starting the engine on every press costs ~50 ms of clipped audio.
  **Keep `AVAudioEngine` running for the lifetime of the process.** Open and
  close `AVAudioFile` per recording instead.
- Tear down only on app quit. Calling `engine.stop()` and `start()` repeatedly
  has caused thread leaks in user reports.

---

## 4. GLOBAL HOTKEY — CGEventTap

Source: SO [47265452](https://stackoverflow.com/questions/47265452/) "Creating
a CGEventTap the right way", SO [53715095](https://stackoverflow.com/questions/53715095/),
medium articles (gaitatzis 2025).

### Required permissions
- **Both Accessibility and Input Monitoring.** Without either, `CGEvent.tapCreate`
  returns `nil` silently. Detect and surface to the user.
- Trigger the prompts with:
  - Accessibility: `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])`
  - Input Monitoring: `IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)`
- Microphone is a separate prompt: `AVCaptureDevice.requestAccess(for: .audio)`.

### Tap configuration
- Use `tap: .cgSessionEventTap` (current login session) — `.cghidEventTap`
  requires root.
- Use `place: .headInsertEventTap` so we see events before other taps.
- **Use `options: .listenOnly`** unless you actually need to swallow events.
  We do not — we observe modifiers and key presses without modifying flow.
- The C callback is invoked on a Mach port; **always hop to main with
  `DispatchQueue.main.async`** before mutating Swift state.

### Re-enable on disable
The tap can be silently disabled by the OS:
- `.tapDisabledByTimeout` — your callback took too long.
- `.tapDisabledByUserInput` — user toggled the system-wide kill switch.

The callback **must** detect these and re-enable:
```swift
if [.tapDisabledByTimeout, .tapDisabledByUserInput].contains(type) {
    CGEvent.tapEnable(tap: tap, enable: true)
    return Unmanaged.passUnretained(event)
}
```

### Distinguishing left/right modifiers
Look at the `keyboardEventKeycode` field of a `flagsChanged` event:
| Keycode | Key |
|--------:|-----|
| 54 | Right Cmd |
| 55 | Left Cmd |
| 58 | Left Option |
| 61 | Right Option |
| 56 | Left Shift |
| 60 | Right Shift |
| 59 | Left Control |
| 62 | Right Control |
| 63 | fn |

Whether the matching flag bit is set in `event.flags` tells you press vs
release for that specific physical key.

---

## 5. NETWORK — URLSession to plain-HTTP LAN host

Source: Apple ATS docs, SO [38501012](https://stackoverflow.com/questions/38501012/).

### App Transport Security
- Plain HTTP is blocked by default on macOS. Add an `NSExceptionDomains`
  entry in `Info.plist` for the specific host (e.g., `linux`).
- `NSAllowsLocalNetworking` is unreliable for `/etc/hosts` aliases — the OS
  resolves the name *after* the ATS check in some paths. Use the explicit
  exception domain instead.
- `NSAllowsArbitraryLoads = true` works but is a sledgehammer; do not use it.

### Local Network prompt (macOS 14+)
- The first connection to a private-IP LAN host triggers a system prompt.
  If the user dismisses or denies it, requests fail silently with
  `NSURLErrorNotConnectedToInternet` or similar.
- Surface the failure in the UI rather than retrying forever.

### URLSession patterns
- Set `timeoutInterval` on the request (15s for ASR is a good default).
- Build `multipart/form-data` by hand — `URLSession` has no built-in helper.
  Boundary must be a unique string per request. Append `\r\n` between parts;
  end with `--<boundary>--\r\n`.
- Decode JSON with `JSONDecoder` and a `Decodable` struct. Don't poke at
  `Any` dictionaries.

---

## 6. PASTE-BACK — NSPasteboard + CGEvent

Source: SO [27664223](https://stackoverflow.com/questions/27664223/),
SO [6118435](https://stackoverflow.com/questions/6118435/).

### Pasteboard
- Always `clearContents()` before `setString(_:forType:)`. Without
  `clearContents()` the type registration may stick from prior content.
- **Save and restore** the user's pre-existing clipboard. Stomping is
  user-hostile. v1 may save only `.string`; document this scope limit.
- After posting Cmd+V, wait ~600 ms before restoring so the target app has
  read from the pasteboard. Shorter delays cause empty pastes in slow apps.

### Synthetic Cmd+V
- `CGEventSource(stateID: .combinedSessionState)` — composes correctly with
  any modifiers the user is physically holding.
- Set `.maskCommand` on **both** keyDown and keyUp of keycode `0x09` (V).
  Do not synthesize separate Cmd-down/Cmd-up events; that race-conditions
  with the user's real key state.
- `event.post(tap: .cghidEventTap)` — posting at HID level reaches all apps.

---

## 7. PERMISSIONS / TCC

Source: Apple developer forums 730043, mintlify "macOS Permissions",
[The Apple Code Signing Handbook](https://freecodecamp.org/news/apple-code-signing-handbook).

### TCC pins permissions to: bundle id + signature + path
- Permissions persist across rebuilds **only** if all three stay stable.
- **`swift run` is unsuitable** for a daily-use tool: the binary path
  (`.build/debug/VoiceRider`) and ad-hoc signature change every build, forcing
  re-prompt every launch.
- **Build a real `.app` bundle** with a stable `CFBundleIdentifier`
  (`com.voicerider`) and ad-hoc codesign with `--identifier com.voicerider`.
  Then permissions persist across `make` rebuilds.

### Resetting permissions during development
```bash
tccutil reset Accessibility       com.voicerider
tccutil reset ListenEvent         com.voicerider
tccutil reset Microphone          com.voicerider
```

### When the tap silently fails after re-signing
There is a known race between the OS's signature cache and TCC's database
(see "CGEvent Taps and Code Signing: The Silent Disable Race"). If a fresh
build has the right entitlements but the tap returns nil:
1. Remove the app from System Settings → Privacy & Security → Accessibility
   *and* Input Monitoring.
2. Re-launch the app via `open VoiceRider.app` (not the binary directly).
3. Re-grant permissions.

---

## 8. BUILD / DISTRIBUTION

### SwiftPM + Makefile pattern
- `Package.swift` declares the executable target.
- A `Makefile` assembles `.build/release/VoiceRider` into
  `VoiceRider.app/Contents/MacOS/VoiceRider`, copies `Info.plist`, and ad-hoc signs
  with `codesign --force --deep --sign - --identifier com.voicerider`.
- This gives us a reproducible build with stable TCC identity, no Xcode
  project required.

### Why not an Xcode project?
- Xcode's `xcodeproj` files are a merge nightmare and tie us to GUI
  workflows. SwiftPM produces the same machine code with a text-only build
  graph.
- We accept that we lose Xcode's signing UI; ad-hoc is sufficient for a
  local tool that never ships.

---

## 9. ANTI-PATTERNS — DO NOT DO THESE

- ❌ `try!` or `as!` anywhere in production paths.
- ❌ Force-unwrap `event.flags`-derived values without a guard.
- ❌ Calling `engine.stop()` / `engine.start()` per recording.
- ❌ Synthesizing Cmd+V with separate Cmd-down/V-down/V-up/Cmd-up events.
- ❌ `NSAllowsArbitraryLoads = true` to "just make it work".
- ❌ Reading `event.flags` to detect *which* modifier key was pressed —
  use the keycode in `flagsChanged` events.
- ❌ Ignoring `.tapDisabledByTimeout` — it will happen, and the app will
  appear dead.
- ❌ Swallowing errors in `URLSession` completion handlers. State machine
  has `.error(String)` for a reason.
- ❌ Mutating UI state from any thread other than main.

---

## 10. ENFORCEMENT

Before merging any branch:

1. `swift build -c release` succeeds with **zero warnings**.
2. `make` produces a `VoiceRider.app` that launches.
3. The full happy path works end-to-end: hold → speak → release → text
   appears in a TextEdit window. Tested manually each release; this is the
   integration test.
4. Annie/Sauron checks (see `no-orphans-no-dual-paths.md`).
