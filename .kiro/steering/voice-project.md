---
inclusion: always
name: voice-project
description: >
  Locked architectural decisions for the voice push-to-talk dictation tool.
  Read this before changing anything in Sources/VoiceRider/.
---

# VoiceRider — Project Locked Decisions

Source of truth for choices already made. Anything contradicting this file
is a bug or requires a deliberate, documented change to this file *first*.

---

## SCOPE (UNCHANGED FROM HANDOFF)

The app does exactly five things:

1. Detect a held global hotkey
2. Record audio while held
3. Send the WAV to the configured ASR endpoint on release
4. Put the response text on the pasteboard
5. Synthesize Cmd+V to paste at the focused cursor

If you find yourself adding history, accounts, settings UI beyond a single
hotkey choice, telemetry, model selection, or local transcription — STOP.
That is not in scope.

---

## LOCKED DECISIONS

### Language & build
- **Language:** Swift 5.9+, targeting macOS 13+.
- **Concurrency mode:** Swift 5 default for v1.x. The pre-commit gate
  is "zero warnings under `swift build -c release`" in default mode.
  `make verify-strict` runs `-strict-concurrency=complete` and is
  informational, not gating, for v1.x. Strict-concurrency adoption is
  tracked under R4-F33 for v0.2. The reasoning: Apple's own
  AVFoundation / CoreFoundation imports are not yet `Sendable`-clean,
  so going strict for v0.1.0 is high churn for marginal value.
- **Build system:** SwiftPM (`swift build -c release`).
- **Bundling:** `Makefile` assembles `VoiceRider.app` and ad-hoc codesigns with
  `--identifier com.voicerider`.
- **No Xcode project.** No `.xcodeproj` or `.xcworkspace` checked in.

### Bundle identity
- `CFBundleIdentifier` = `com.voicerider` — **never change this.** TCC
  permission grants are tied to it.

### Hotkey
- **Right Option** (keycode `61`, flag `.maskAlternate`).
- 200 ms qualification window before recording starts.
- If any non-modifier key is pressed while Right Option is held, the
  in-flight arming is cancelled (treated as a regular shortcut, not
  dictation).

### ASR server
- **Endpoint:** `http://linux:8000/v1/audio/transcriptions`
- **Model name:** `canary-qwen-2.5b`
- **Auth header:** `Authorization: Bearer local-no-auth`
- **Request:** `multipart/form-data` with fields `model` and `file` (WAV).
- **Response:** `{"text": "..."}`.

These can be overridden via `UserDefaults` (`voicerider.serverURL`,
`voicerider.modelName`, `voicerider.bearerToken`) but the *defaults* are the values
above.

### Audio
- Capture via `AVAudioEngine.inputNode.installTap(onBus: 0, bufferSize: 1024,
  format: nil)`.
- Convert to 16 kHz mono Int16 with `AVAudioConverter`.
- Write a real RIFF WAV via `AVAudioFile` with explicit settings dict.
- Engine stays running for the lifetime of the process. Open/close the
  `AVAudioFile` per recording.

### Paste-back
- Save current `NSPasteboard.general.string(forType: .string)` before write.
- Restore it 600 ms after posting Cmd+V.
- Multi-type clipboard preservation is **out of scope for v1**. The README
  must call this limitation out so users know.

### State machine — single source of truth
```
idle → arming → recording → transcribing → pasting → idle
            ↘ idle (cancelled)

Any state ──failure──▶ error(String) ──2s──▶ idle
```
- One `AppState` enum on the `AppDelegate`. No parallel `Bool` flags. No
  shadowed state in subsystems.
- All transitions happen on the main thread.
- `error(String)` is reachable from any state on failure
  (transcriber init, hotkey install, recorder start, transcribe
  failure). Auto-clears after 2s; chained errors restart the timer.

### Permissions
- Microphone, Accessibility, Input Monitoring requested at first launch.
- Local Network permission prompt fires on first request to `linux:8000`.
- A "Open Permission Settings…" menu item opens the three relevant System
  Settings panes.

### App Transport Security
- Single `NSExceptionDomains` entry for `linux`. No
  `NSAllowsArbitraryLoads`. If the user changes the server hostname,
  they edit `Info.plist` and rebuild.

---

## FILE LAYOUT — DON'T REARRANGE WITHOUT REASON

```
VoiceRider/
├── Makefile                       # bundles + signs VoiceRider.app
├── Package.swift                  # SwiftPM manifest
├── build.sh                       # dev: swift build + test
├── prod-build.sh                  # release: gate + bundle
├── Resources/
│   └── Info.plist                 # LSUIElement, ATS, mic usage
├── Sources/VoiceRider/
│   ├── VoiceRiderApp.swift        # @main entry point
│   ├── AppDelegate.swift          # Owns state machine, wires modules
│   ├── State.swift                # AppState enum
│   ├── HotkeyMonitor.swift        # CGEventTap + dwell logic
│   ├── AudioRecorder.swift        # AVAudioEngine + converter + WAV
│   ├── Transcriber.swift          # URLSession multipart upload
│   ├── Paster.swift               # NSPasteboard + synth Cmd+V
│   ├── Permissions.swift          # AX, mic, IOHID, settings deeplinks
│   ├── Logger.swift               # os.Logger subsystem
│   └── StatusItemController.swift # NSStatusItem + menu + icon render
├── Tests/VoiceRiderTests/         # 12 test files, 109 fixtures
├── README.md                      # one-time setup, hotkey, limitations
├── docs/plans/                    # design + DCR audit trail
└── .kiro/
    └── steering/                  # this directory
```

Each file has a single responsibility. If something doesn't fit any of
these, that's a signal to think before adding a new file.

---

## NON-GOALS (DO NOT IMPLEMENT)

- ❌ Local transcription (Whisper, MLX, anything)
- ❌ Account / login / cloud sync
- ❌ Telemetry / analytics
- ❌ Audio post-processing (denoising, VAD, silence trim) — server handles
  it well enough
- ❌ Recording history / transcript log
- ❌ Multi-clipboard preservation in v1
- ❌ Configurable model in UI — `UserDefaults` only
- ❌ App Store distribution
- ❌ Auto-update mechanism

---

## WHAT TO DO IF A REQUIREMENT CHANGES

1. Update **this file first** to reflect the new locked decision.
2. Then change the code.
3. The diff to this file is the audit trail of what changed and why.
