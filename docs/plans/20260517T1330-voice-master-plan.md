# Voice — Native macOS Push-to-Talk Dictation (Master Plan)

**Date:** 2026-05-17
**Status:** Proposed — pending adversarial review (see `handoff-for-review.md`)
**Author:** Decompose → Critique → Refine, applied to the handoff at
`/tmp/voice-tool-handoff.md`
**Implementation:** Fresh kiro-cli session implements. Original session reviews.

---

## 0. Methodology & Guardrails

### 0.1 MISSION

Build a native macOS Swift app that lives in the menu bar. Hold Right
Option, speak, release — the transcribed text is pasted at the cursor in
whatever app is focused. Five steps. Nothing else.

The handoff at `/tmp/voice-tool-handoff.md` documents the four prior
attempts that failed (Hammerspoon, AudioWhisper, OpenWhispr, Voxtype) and
what worked in each. The pipeline is proven; the only unsolved piece is
posting text back into the focused app on macOS 15. This plan delivers
that.

**ACCURACY OVER SPEED.** Any decision that cannot be locally verified
(API signatures, TCC behavior, audio format requirements) must be
verified before code is written. Wrong assumptions that ship are worse
than delays that catch them.

### 0.1.1 LEGEND

| Term | Meaning |
|------|---------|
| **ASR** | Automatic Speech Recognition — the LAN server at `linux:8000` |
| **TCC** | Transparency, Consent, and Control — macOS's permission database |
| **CGEventTap** | Quartz Event Services low-level keyboard observer |
| **DCR** | Decompose → Critique → Refine methodology |
| **Annie rule** | No orphaned code (`.kiro/steering/no-orphans-no-dual-paths.md`) |
| **Sauron rule** | No dual paths for the same operation |
| **Right Option** | Physical keycode 61, flag mask `.maskAlternate` |
| **Qualification window** | The 200 ms after Right-Option goes down during which the press can still be cancelled by another keypress |

### 0.2 DECOMPOSE → CRITIQUE → REFINE (MANDATORY)

Use this method for every non-trivial decision:

1. **DECOMPOSE** — break the problem into independent moving parts.
2. **CRITIQUE** — what could go wrong? What edge cases exist? What
   assumptions am I making?
3. **REFINE** — adjust, then implement.

If you find yourself writing code without having done this for the
current task, STOP. Back up. Decompose first.

### 0.2.1 EVIDENCE-LOCKING (MANDATORY before any framework call)

Before invoking any function from AppKit, AVFoundation, CoreGraphics,
URLSession, or IOKit:

1. **VERIFY** the symbol exists at the macOS version we target (13+).
2. **READ** the actual signature from headers or the developer docs.
3. **CONFIRM** parameter labels and types match what you're passing.
4. **CONFIRM** the return type matches what you're assigning.

If you cannot verify → DO NOT WRITE THE CALL. Ask, or flag.

### 0.2.2 EXHAUSTIVE PATTERN SEARCH

If you change how any cross-cutting pattern works (e.g., logging,
error reporting, threading), grep the entire `Sources/` tree and update
every site. One instance fixed, six left = the bug is still there.

### 0.2.3 THREE-WAY CROSS-REFERENCE (every function)

After writing any function:

1. **Code does** — trace the actual logic.
2. **Doc comment claims** — what does the `///` say?
3. **Plan says** — what does this document specify?

If any two disagree, fix before moving on.

### 0.3 GUARDRAILS (NON-NEGOTIABLE)

1. **NEVER set `NSAllowsArbitraryLoads = true`.** ATS exception domain
   for `linux` only. If you find yourself disabling ATS globally, STOP —
   you are doing the wrong thing.
2. **NEVER use `try!`, `as!`, or force-unwrap (`!`)** outside test code
   or known-good URL literals (`URL(string: "http://…")!` for compiled-in
   constants).
3. **NEVER use `print(...)` for runtime logging.** Use `os.Logger` (see
   `Logger.swift`).
4. **NEVER mutate UI state from a non-main thread.** All `NSStatusItem`,
   `NSPasteboard`, and state-machine transitions happen on main.
5. **NEVER consume keyboard events.** The `CGEventTap` is `.listenOnly`.
   Consuming events would break the user's normal typing.
6. **NEVER stomp the user's clipboard without restoring it.** The Paster
   saves and restores `.string` content. If you add multi-type
   preservation, do it as a single change documented in this plan first.
7. **NEVER hardcode values** that should come from `UserDefaults`
   (server URL, model, bearer). Defaults are the values from the handoff;
   overrides come from `defaults write com.local.voice <key>`.
8. **NEVER add a feature outside the scope in §2.** v1 is five steps.
   Scope creep is the reason the four prior tools failed.

### 0.4 PHASE GATES

#### Gate A → B (Foundation → Audio + Network)

- [ ] `swift build -c release` succeeds with **zero warnings**.
- [ ] `make` produces a `Voice.app` that launches and shows a menu-bar
      icon.
- [ ] Quitting via the menu item exits cleanly.
- [ ] State, Logger, Permissions, StatusItemController compile and have
      no orphan symbols (Annie rule).

#### Gate B → C (Audio + Network → Hotkey)

- [ ] `AudioRecorder.start()` returns a URL whose contents start with
      `RIFF....WAVE` (Tier 1 test M-R passes locally).
- [ ] `Transcriber` Tier 1 unit tests pass (`swift test` runs Mock-based
      tests with no real network access).
- [ ] Multipart body byte-for-byte matches the handoff's `curl` example
      shape (manual diff check).

#### Gate C → D (Hotkey → Paste & Integration)

- [ ] `make run` followed by holding Right Option and releasing
      transitions the menu-bar icon through `idle → arming → recording
      → transcribing → idle` (no actual paste yet — `Paster` is
      stubbed to log only).
- [ ] Pressing Cmd+Right Option does NOT start recording.
- [ ] Tapping Right Option for <100 ms does NOT start recording.

#### Gate D → E (Paste & Integration → Verify)

- [ ] Held Right Option in TextEdit dictates a phrase. Text appears at
      cursor. Original clipboard restored.
- [ ] Manual integration checklist M1–M13 all pass (see
      `proposed/tests/manual-integration-checklist.md`).
- [ ] Server unavailable surfaces error icon, auto-clears in 2 s.
- [ ] No file leaks: `/tmp/voice-*.wav` is empty after each session.

### 0.5 PRE-COMMIT CHECKLIST (every commit)

- [ ] `swift build -c release 2>&1 | grep -i warning` → 0 lines.
- [ ] `swift test` → 0 failures.
- [ ] `grep -rn "try!" Sources/` → 0 results.
- [ ] `grep -rn "as!" Sources/ | grep -v "// test"` → 0 results.
- [ ] `grep -rn "print(" Sources/` → 0 results (use `Log.*`).
- [ ] `grep -rn "NSAllowsArbitraryLoads" Resources/Info.plist` → 0
      results.
- [ ] No new symbol added to `Sources/` lacks a caller (Annie rule grep).
- [ ] No new function duplicates an existing one (Sauron rule manual
      review).
- [ ] No `// TODO` or `// FIXME` left without an issue/task reference.

### 0.5.1 PER-FILE GATE (after every file is written)

- [ ] Compiles in isolation: `swift build -c release` succeeds with that
      file present and the rest of the module's expected dependencies.
- [ ] Doc comment summarizes intent in ≤ 2 lines.
- [ ] All public/internal symbols have a caller within `Sources/` or
      `Tests/` (Annie rule).
- [ ] All errors thrown are caught somewhere or explicitly bubble to a
      user-facing `state = .error(...)` transition.
- [ ] Every closure escaping into a stored property captures `[weak self]`
      where applicable.
- [ ] Threading comment present at the top of any type whose methods
      span multiple threads.

### 0.5.2 ANTI-SHORTCUT RULES

1. **NEVER stub a function to return a fixed value to make a test pass.**
   Tests must exercise real logic.
2. **NEVER mock at a higher level than the network boundary.** For
   `Transcriber` tests, mock `URLProtocol`, not `Transcriber.transcribe`.
3. **NEVER fake the WAV.** `AudioRecorder` writes a real file via
   `AVAudioFile`. The header check verifies it's a real RIFF/WAVE.
4. **NEVER skip the qualification window.** If a test needs immediate
   commit, it must wait for the actual 200 ms — or the implementation is
   structured so the window is injectable.

### 0.5.3 IMPLEMENTATION STATE TRACKER

```
PHASE A: Foundation
  [ ] A1: Package.swift
  [ ] A2: Resources/Info.plist
  [ ] A3: Makefile
  [ ] A4: Sources/Voice/Logger.swift
  [ ] A5: Sources/Voice/State.swift
  [ ] A6: Sources/Voice/Permissions.swift
  [ ] A7: Sources/Voice/StatusItemController.swift
  [ ] A8: Sources/Voice/main.swift
  [ ] A9: Sources/Voice/AppDelegate.swift (skeleton — no hotkey yet)
  [ ] T-A: Tests/VoiceTests/StateTests.swift
  [ ] GATE A→B

PHASE B: Audio + Network
  [ ] B1: Sources/Voice/AudioRecorder.swift
  [ ] B2: Sources/Voice/Transcriber.swift
  [ ] T-B1: Tests/VoiceTests/MockURLProtocol.swift
  [ ] T-B2: Tests/VoiceTests/TranscriberTests.swift
  [ ] T-B3: Tests/VoiceTests/AudioRecorderTests.swift
  [ ] GATE B→C

PHASE C: Hotkey
  [ ] C1: Sources/Voice/HotkeyMonitor.swift
  [ ] C2: AppDelegate.swift — wire hotkey → state machine (no paste yet)
  [ ] T-C: Tests/VoiceTests/HotkeyMonitorTests.swift
  [ ] GATE C→D

PHASE D: Paste & Integration
  [ ] D1: Sources/Voice/Paster.swift
  [ ] D2: AppDelegate.swift — connect transcribe → paste
  [ ] T-D: Tests/VoiceTests/PasterTests.swift
  [ ] GATE D→E

PHASE E: Verify & Document
  [ ] E1: README.md
  [ ] E2: Manual integration checklist M1–M13
  [ ] E3: Tag v0.1.0
```

### 0.6 DECISION TREE: "Should I add a new file?"

```
Does an existing file already do the same thing?
  YES → Sauron violation. Use the existing file.
  NO  → Is the new responsibility cohesive with one of the 9 existing
        files in `Sources/Voice/`?
        YES → Add to that file.
        NO  → Is it a new top-level concern (not ad-hoc utility)?
              YES → Add a new file. Update `voice-project.md` file layout
                    section.
              NO  → Inline it where it's used.
```

### 0.7 CONTEXT FOR FRESH SESSION

**Steering files to load:**

- `.kiro/steering/swift-coding-best-practices.md` — language rules.
- `.kiro/steering/swift-macos-best-practices.md` — macOS API rules.
- `.kiro/steering/no-orphans-no-dual-paths.md` — Annie / Sauron rules.
- `.kiro/steering/voice-project.md` — locked decisions.

**Source documents:**

- `/tmp/voice-tool-handoff.md` — original task brief.
- This plan.
- `proposed/code/` — every code file referenced from §7.
- `proposed/tests/` — every test file referenced from §10.

**Build:** `make` — produces `Voice.app` and ad-hoc signs with
`com.local.voice`. **Do not change the bundle identifier** — TCC
permission grants are tied to it.

---

## 1.1 How The System Works NOW (before implementation)

There is no existing `voice` codebase. The directory `$REPO_ROOT`
is empty as of plan authoring. The pipeline that already works on this
Mac is:

```
sox / ffmpeg → /tmp/test.wav
curl -X POST http://linux:8000/v1/audio/transcriptions \
     -H "Authorization: Bearer local-no-auth" \
     -F "model=canary-qwen-2.5b" \
     -F "file=@/tmp/test.wav"
→ {"text": "..."}
```

This plan replaces the manual `sox`/`curl` glue with a native menu-bar
app that is invoked by holding Right Option.

## 1.2 How The System Works AFTER

```
User holds Right Option
  → CGEventTap (HotkeyMonitor) fires onArm
    → AppDelegate: state = .arming
  → 200 ms later, if still held alone → onCommit
    → AppDelegate: state = .recording
    → AudioRecorder.start() returns URL of fresh WAV
  → Audio captured to /tmp/voice-<uuid>.wav at 16 kHz mono Int16

User releases Right Option
  → onRelease
    → AppDelegate: state = .transcribing
    → Transcriber.transcribe(wav:) posts multipart to linux:8000
  → Server returns {"text": "..."}
    → AppDelegate: state = .pasting
    → Paster: save clipboard, set new text, post Cmd+V, restore in 600 ms
  → AppDelegate: state = .idle

Anywhere in the chain: failure → state = .error(msg) → 2 s → .idle
```

No background services. No daemons. One process, one event tap, one
audio engine, one HTTP request per dictation.

---

## 1. Problem

Every prior tool failed at one of the five steps:

| Tool | What worked | What broke |
|------|-------------|------------|
| Hammerspoon | concept | eventtap permission issues on macOS 15; sox file coordination bugs |
| AudioWhisper | recording | required login; phones home; bundled qdrant for no reason |
| OpenWhispr | recording | required login; phones home |
| Voxtype | recording, transcription | paste-back broken on macOS — used `wl-copy` (Wayland Linux clipboard) |
| Whispur | unclear | not confirmed to support custom base URL |

The root cause across all four is **scope creep** combined with **wrong
platform assumptions**. A native macOS app written from scratch, bound
to exactly the five steps in the handoff, sidesteps every one.

## 2. Solution (one sentence)

A SwiftPM-built menu-bar app, ad-hoc signed with `com.local.voice`, that
observes Right Option, captures audio, posts it to the LAN ASR server,
and synthesizes Cmd+V at the focused app.

---

## 3. Architecture

### 3.1 Source of Truth

| Question | Answer | How |
|----------|--------|-----|
| What is the user-visible state? | `AppState` on `AppDelegate` | Enum, single var, all transitions on main |
| Is the hotkey held? | `HotkeyMonitor.rightOptDown` | Private; not consulted from elsewhere |
| Is audio being captured? | `AudioRecorder.file != nil` | Internal; wrapped by .recording state |
| What's the current WAV file? | `AppDelegate.currentWav` | Owned by the delegate; recorder doesn't track |
| What did the server return? | `Transcriber.transcribe` callback | One-shot; no caching |
| What was on the clipboard? | `Paster` local var inside `paste(_:)` | Lives only for one paste operation |

### 3.2 Files (10 source files, 1 plist)

| File | Lines (target) | Responsibility |
|------|---------------:|----------------|
| `Sources/Voice/main.swift` | ~10 | NSApplication bootstrap |
| `Sources/Voice/AppDelegate.swift` | ~140 | Owns state, wires modules, error timer |
| `Sources/Voice/State.swift` | ~45 | `AppState` enum |
| `Sources/Voice/HotkeyMonitor.swift` | ~170 | CGEventTap + Right-Option dwell logic |
| `Sources/Voice/AudioRecorder.swift` | ~145 | AVAudioEngine + converter + WAV |
| `Sources/Voice/Transcriber.swift` | ~150 | URLSession multipart upload |
| `Sources/Voice/Paster.swift` | ~70 | Pasteboard + synth Cmd+V |
| `Sources/Voice/Permissions.swift` | ~60 | TCC requests + Settings deep-links |
| `Sources/Voice/StatusItemController.swift` | ~75 | NSStatusItem rendering |
| `Sources/Voice/Logger.swift` | ~20 | os.Logger categories |
| `Resources/Info.plist` | ~37 | LSUIElement, ATS exception, mic prompt |

### 3.3 State Machine

```
        idle
         │
   onArm │
         ▼
       arming ─────onCancel/release───▶ idle
         │
  onCommit (held 200 ms alone)
         │
         ▼
      recording ─────onRelease──▶ transcribing
                                       │
                              callback success
                                       │
                                       ▼
                                    pasting
                                       │
                              restore complete
                                       │
                                       ▼
                                     idle

  any failure ─▶ error("...") ─── 2 s timeout ─▶ idle
```

Defined in `proposed/code/Sources/Voice/State.swift`.
Owned and transitioned in `proposed/code/Sources/Voice/AppDelegate.swift`.

### 3.4 Audio Pipeline

```
AVAudioEngine (default input)
  │ inputNode tap installed once at process start
  │ format = inputNode.outputFormat(forBus: 0)  ← hardware-native (typ. 48k F32 mono)
  ▼
AVAudioConverter
  │ from: hardware format
  │ to:   16 kHz, mono, Int16, interleaved
  ▼
AVAudioFile (per-recording)
  │ settings: kAudioFormatLinearPCM, 16-bit, little-endian, non-float
  │ writes a real RIFF/WAVE file
  ▼
/tmp/voice-<uuid>.wav
```

Engine stays running for the lifetime of the process. Only the file
handle rotates per recording.

### 3.5 Network Pipeline

| Field | Value | Source |
|-------|-------|--------|
| Method | `POST` | spec |
| URL | `voice.serverURL` UserDefault, default `http://linux:8000/v1/audio/transcriptions` | handoff |
| `Authorization` | `Bearer <voice.bearerToken>`, default `local-no-auth` | handoff |
| `Content-Type` | `multipart/form-data; boundary=voice-<uuid>` | RFC 7578 |
| Body | `model` part + `file` part (audio/wav) | handoff `curl` example |
| Timeout | 15 s | derived from observed ~300–800 ms latency |

ATS exception domain for `linux` in `Info.plist`. No
`NSAllowsArbitraryLoads`.

### 3.6 Paste Pipeline

```
Paster.paste(text, then:)
  ├─ if text.isEmpty → call then() and return
  ├─ saved = pasteboard.string(forType: .string)
  ├─ pasteboard.clearContents() ; setString(text, .string)
  ├─ synthesize Cmd+V via CGEventSource(.combinedSessionState),
  │     virtualKey 0x09, .maskCommand, post(.cghidEventTap)
  ├─ asyncAfter 600 ms:
  │     if pasteboard.string(forType: .string) == text:
  │         clearContents() ; setString(saved, .string)
  │     call then()
```

Limitations explicitly documented (v1 only preserves `.string`).

### 3.7 Concurrency

| Code path | Thread |
|-----------|--------|
| All `AppState` mutations | main |
| `NSStatusItem` updates | main |
| `NSPasteboard` reads/writes | main |
| `CGEvent` posting | main |
| CGEventTap callback (C-thread) | hop to main immediately |
| `AVAudioEngine` tap callback | audio render thread; `AVAudioFile.write` is documented safe there |
| `URLSession` data task callback | URLSession's delegate queue; we hop to main before mutating state |

### 3.8 Permissions Surface

| Permission | Trigger | Failure mode |
|------------|---------|--------------|
| Microphone | First `AudioRecorder.start()` | `engineStartFailed` → state.error |
| Accessibility | First `AXIsProcessTrustedWithOptions(prompt: true)` | `CGEvent.tapCreate` returns nil → state.error("Grant Accessibility…") |
| Input Monitoring | First `IOHIDRequestAccess(.listenEvent)` | Same as Accessibility — both required for the tap |
| Local Network (macOS 14+) | First request to `linux:8000` | Implicit OS prompt; if denied, requests fail with NSURLError |

### 3.9 No More Conflicts (per-file responsibility table)

| File | Reads | Writes |
|------|-------|--------|
| `HotkeyMonitor` | CGEventTap stream | callbacks only |
| `AudioRecorder` | mic via AVAudioEngine | `/tmp/voice-*.wav` |
| `Transcriber` | the WAV at the URL | nothing |
| `Paster` | pasteboard `.string` | pasteboard `.string` (twice — set, then restore) |
| `StatusItemController` | nothing | `NSStatusItem.button.image` and `.toolTip` |
| `AppDelegate` | every callback above | `state` (single source of truth) |

---

## 4. UI Design

### 4.1 Menu-bar icon (the entire UI)

| State | Glyph | Tooltip |
|-------|-------|---------|
| `.idle` | `mic` | Voice — idle |
| `.arming` | `mic.circle` | Voice — arming |
| `.recording` | `mic.fill` | Voice — recording |
| `.transcribing` | `waveform` | Voice — transcribing |
| `.pasting` | `doc.on.clipboard` | Voice — pasting |
| `.error(msg)` | `exclamationmark.triangle` | Voice — error: `<msg>` |

Defined in `proposed/code/Sources/Voice/StatusItemController.swift`.

### 4.2 Menu

| Item | Action |
|------|--------|
| Open Permission Settings… | Opens Microphone, Accessibility, and Input Monitoring panes in System Settings |
| Quit Voice (⌘Q) | `NSApp.terminate(nil)` |

### 4.3 No window. No dock. No login.

`LSUIElement = true` in `Info.plist`. Activation policy `.accessory`.
The app never appears in Cmd-Tab or the Dock.

---

## 5. User Stories

| # | As a... | I want to... | So that... | Acceptance |
|---|---------|--------------|------------|------------|
| U1 | macOS user | hold a key and dictate into any app | I don't have to open a separate window or paste manually | M3 of integration checklist |
| U2 | user with shortcuts in muscle memory | press Cmd+Right-Option to do paste-special | dictation doesn't hijack legitimate shortcuts | M2 of integration checklist |
| U3 | user with a clipboard manager | dictate without losing what was on my clipboard | I don't have to re-copy after every dictation | M3 verifies pasteboard restore |
| U4 | user on a fresh machine | grant three permissions and have it just work | no setup ceremony | M1 of integration checklist |
| U5 | user whose ASR server is down | get a clear visual error and recover | I'm not stuck wondering what failed | M5 of integration checklist |
| U6 | privacy-conscious user | know nothing leaves the LAN | my voice doesn't reach anyone's cloud | ATS exception only allows `linux` host |
| U7 | user with a different ASR server | point Voice at it via UserDefaults | I'm not locked to one model or host | M10 of integration checklist |

---

## 6. File States (lifecycle)

```
App launched (first time, no permissions)
  └─ /tmp/voice-*.wav — does not exist
  └─ State: .error("Grant Accessibility + Input Monitoring, then relaunch")

Permissions granted, app relaunched
  └─ State: .idle

User holds Right Option
  └─ State: .arming

Held past 200 ms
  └─ State: .recording
  └─ /tmp/voice-<uuid>.wav: actively being written

User releases
  └─ /tmp/voice-<uuid>.wav: finalized (file handle dropped)
  └─ State: .transcribing
  └─ HTTP POST in flight

Server responds with text
  └─ State: .pasting
  └─ /tmp/voice-<uuid>.wav: deleted by AppDelegate cleanup
  └─ Pasteboard: holds new text temporarily
  └─ Cmd+V posted

600 ms later
  └─ Pasteboard: original .string restored
  └─ State: .idle

Failure path (any step)
  └─ /tmp/voice-<uuid>.wav: deleted (cleanup is unconditional)
  └─ State: .error("...")
  └─ 2 s later: State: .idle
```

---

## 7. Implementation Phases

Each task lists the proposed file under `proposed/code/` or
`proposed/tests/`. The implementor copies it into the canonical project
location (`./<same path>`) when the phase starts, then verifies and
adjusts. The proposed tree is the **source of truth for what to write**;
the implementor's job is to verify each line, not invent.

### Phase A: Foundation (no audio, no hotkey, no network)

| Task | File | Action | Lines | Source |
|------|------|--------|------:|--------|
| A1 | `Package.swift` | NEW | 21 | [proposed/code/Package.swift](proposed/code/Package.swift) |
| A2 | `Resources/Info.plist` | NEW | 37 | [proposed/code/Resources/Info.plist](proposed/code/Resources/Info.plist) |
| A3 | `Makefile` | NEW | 46 | [proposed/code/Makefile](proposed/code/Makefile) |
| A4 | `Sources/Voice/Logger.swift` | NEW | 17 | [proposed/code/Sources/Voice/Logger.swift](proposed/code/Sources/Voice/Logger.swift) |
| A5 | `Sources/Voice/State.swift` | NEW | 44 | [proposed/code/Sources/Voice/State.swift](proposed/code/Sources/Voice/State.swift) |
| A6 | `Sources/Voice/Permissions.swift` | NEW | 59 | [proposed/code/Sources/Voice/Permissions.swift](proposed/code/Sources/Voice/Permissions.swift) |
| A7 | `Sources/Voice/StatusItemController.swift` | NEW | 72 | [proposed/code/Sources/Voice/StatusItemController.swift](proposed/code/Sources/Voice/StatusItemController.swift) |
| A8 | `Sources/Voice/main.swift` | NEW | 11 | [proposed/code/Sources/Voice/main.swift](proposed/code/Sources/Voice/main.swift) |
| A9 | `Sources/Voice/AppDelegate.swift` | NEW (skeleton) | 142 | [proposed/code/Sources/Voice/AppDelegate.swift](proposed/code/Sources/Voice/AppDelegate.swift) |
| T-A | `Tests/VoiceTests/StateTests.swift` | NEW | 33 | [proposed/tests/Tests/VoiceTests/StateTests.swift](proposed/tests/Tests/VoiceTests/StateTests.swift) |

**Phase A end state:** `make run` shows the menu-bar mic icon. Quit via the
menu works. No permissions yet enforced. State enum tests pass.

### Phase B: Audio + Network (no hotkey, manual trigger)

| Task | File | Action | Lines | Source |
|------|------|--------|------:|--------|
| B1 | `Sources/Voice/AudioRecorder.swift` | NEW | 143 | [proposed/code/Sources/Voice/AudioRecorder.swift](proposed/code/Sources/Voice/AudioRecorder.swift) |
| B2 | `Sources/Voice/Transcriber.swift` | NEW | 150 | [proposed/code/Sources/Voice/Transcriber.swift](proposed/code/Sources/Voice/Transcriber.swift) |
| T-B1 | `Tests/VoiceTests/MockURLProtocol.swift` | NEW | 74 | [proposed/tests/Tests/VoiceTests/MockURLProtocol.swift](proposed/tests/Tests/VoiceTests/MockURLProtocol.swift) |
| T-B2 | `Tests/VoiceTests/TranscriberTests.swift` | NEW | 198 | [proposed/tests/Tests/VoiceTests/TranscriberTests.swift](proposed/tests/Tests/VoiceTests/TranscriberTests.swift) |
| T-B3 | `Tests/VoiceTests/AudioRecorderTests.swift` | NEW | 53 | [proposed/tests/Tests/VoiceTests/AudioRecorderTests.swift](proposed/tests/Tests/VoiceTests/AudioRecorderTests.swift) |

**Phase B end state:** `swift test` passes (mock-based, no network).
Audio test gated by `VOICE_RUN_AUDIO_TESTS=1` env var; runs locally on
the dev's Mac, skipped in CI.

### Phase C: Hotkey

| Task | File | Action | Lines | Source |
|------|------|--------|------:|--------|
| C1 | `Sources/Voice/HotkeyMonitor.swift` | NEW | 169 | [proposed/code/Sources/Voice/HotkeyMonitor.swift](proposed/code/Sources/Voice/HotkeyMonitor.swift) |
| C2 | `Sources/Voice/AppDelegate.swift` | UPDATE — wire onArm/onCommit/onCancel/onRelease | (already in proposal) | (same file as A9) |
| T-C | `Tests/VoiceTests/HotkeyMonitorTests.swift` | NEW | 34 | [proposed/tests/Tests/VoiceTests/HotkeyMonitorTests.swift](proposed/tests/Tests/VoiceTests/HotkeyMonitorTests.swift) |

**Phase C end state:** Holding Right Option transitions through arming →
recording → transcribing. The actual paste is still stubbed (Paster not
present yet, or `Paster.paste` is a no-op). Manual M2 of the integration
checklist passes.

### Phase D: Paste & Integration

| Task | File | Action | Lines | Source |
|------|------|--------|------:|--------|
| D1 | `Sources/Voice/Paster.swift` | NEW | 69 | [proposed/code/Sources/Voice/Paster.swift](proposed/code/Sources/Voice/Paster.swift) |
| D2 | `Sources/Voice/AppDelegate.swift` | UPDATE — connect transcribe success → paste | (already in proposal) | (same file as A9) |
| T-D | `Tests/VoiceTests/PasterTests.swift` | NEW | 51 | [proposed/tests/Tests/VoiceTests/PasterTests.swift](proposed/tests/Tests/VoiceTests/PasterTests.swift) |

**Phase D end state:** End-to-end works in TextEdit. M3 of the manual
checklist passes.

### Phase E: Verify & Document

| Task | File | Action | Lines | Source |
|------|------|--------|------:|--------|
| E1 | `README.md` | NEW | 52 | [proposed/code/README.md](proposed/code/README.md) |
| E2 | manual-integration-checklist | EXECUTE M1–M13 | n/a | [proposed/tests/manual-integration-checklist.md](proposed/tests/manual-integration-checklist.md) |
| E3 | git tag | `v0.1.0` after all M-checks pass | n/a | n/a |

---

## 8. No "Export/Import Scripts" needed

No client data, no engagement-specific configuration. The app's only
configuration is three `UserDefaults` keys, all of which have safe
defaults baked into `AppDelegate.Config.load()`.

---

## 9. Rollback Plan

- The repo is empty before this change. Rollback = `git rm -rf .`
  (or never merging the branch).
- TCC permissions can be reset with `make reset-tcc`.
- `Voice.app` is just a directory; `rm -rf Voice.app` removes it.

There is nothing else to roll back. No daemons, no launch agents, no
background processes, no system files modified.

---

## 10. Testing Strategy

### 10.1 Principles

1. Unit tests cover **pure** code (multipart-body builder, state
   transitions, pasteboard save/restore).
2. The network is mocked at the `URLProtocol` boundary, never higher.
3. Audio capture cannot be unit-tested in CI; a mic-required test is
   gated by `VOICE_RUN_AUDIO_TESTS=1`.
4. CGEventTap, the synth Cmd+V, and the Local Network prompt require a
   real session. Those are covered by the manual integration checklist
   — that **is** the integration test, not optional.
5. No test passes when the code it tests is removed (mutation check).
6. Annie / Sauron rules apply to tests too: every test fixture has a
   real test using it; no two tests duplicate coverage.

### 10.2 Test Tiers

| Tier | File | Tests | Type | Priority |
|------|------|-------|------|----------|
| 1 | [`StateTests.swift`](proposed/tests/Tests/VoiceTests/StateTests.swift) | 4 | Pure unit | P0 |
| 2 | [`TranscriberTests.swift`](proposed/tests/Tests/VoiceTests/TranscriberTests.swift) | 5 | Mock URLProtocol | P0 |
| 3 | [`AudioRecorderTests.swift`](proposed/tests/Tests/VoiceTests/AudioRecorderTests.swift) | 2 | Real engine (gated) | P1 |
| 4 | [`PasterTests.swift`](proposed/tests/Tests/VoiceTests/PasterTests.swift) | 2 | Real NSPasteboard | P0 |
| 5 | [`HotkeyMonitorTests.swift`](proposed/tests/Tests/VoiceTests/HotkeyMonitorTests.swift) | 2 | Construction-only | P2 |
| M | [`manual-integration-checklist.md`](proposed/tests/manual-integration-checklist.md) | 13 | Manual | P0 |
| | **Total** | **15 unit + 13 manual** | | |

### 10.3 Test Fixtures

No binary fixtures. The only "fixture" is a 5-byte file written into
`/tmp` by the Transcriber tests as a stand-in WAV — its contents don't
matter because the server is mocked.

### 10.4 Negative Test Cases

| # | Scenario | Where | Expected |
|---|----------|-------|----------|
| N1 | HTTP 500 from server | TranscriberTests `http500` | `TranscribeError.http(500, body)` |
| N2 | Empty `text` field in response | TranscriberTests `emptyTextEmpty` | `TranscribeError.empty` |
| N3 | Malformed JSON in response | TranscriberTests `malformedJSON` | `TranscribeError.decode` |
| N4 | Empty input string to Paster | PasterTests `emptyIsNoOp` | pasteboard untouched, `then` called |
| N5 | `AudioRecorder.stop()` without `start()` | AudioRecorderTests `stopWithoutStart` | no crash |
| N6 | Right Option held <200 ms | Manual M2 | recording does not start |
| N7 | Cmd+Right Option pressed together | Manual M2 | recording does not start |
| N8 | Permissions revoked at runtime | Manual M8 | hotkey stops working; relaunch + re-grant fixes it |
| N9 | Server unavailable | Manual M5 | error icon for 2 s |
| N10 | Server slow / hung | Manual M6 | timeout at 15 s, error icon |

### 10.5 Testing Gates

#### GATE T1 — before committing any test file

- [ ] No `try!` outside helper that wraps a known-good initializer.
- [ ] No real network access — every `URLSession` use goes through
      `MockURLProtocol`.
- [ ] No real Bedrock / OpenAI / 3rd-party — the only network mock
      target is the user's own ASR server.
- [ ] Test docstring matches what the test actually does (three-way
      cross-reference).

#### GATE T2 — every Phase end

- [ ] `swift test` exits 0.
- [ ] `swift test 2>&1 | grep -i warning` → 0 lines.
- [ ] Mutation check on at least one core function in the phase: comment
      out the body, confirm at least one test fails.

#### GATE T3 — final

- [ ] All 15 unit tests pass.
- [ ] All 13 manual-checklist items pass on a real Mac running 13+.
- [ ] `git grep -n "import.*Voice"` from `Tests/` matches exactly the
      modules under test (no orphan imports).

### 10.6 Anti-Patterns Forbidden in Tests

1. No asserting on mock call args as the *primary* assertion. Assert on
   the function's return value or observable side effect; verify the
   request shape as a secondary check.
2. No sunny-day-only tests (every public function with an error path has
   at least one test that exercises that path).
3. No tests that pass when the function body is removed.
4. No mocking `Transcriber` or `AudioRecorder` themselves — mock the
   layer below (URLProtocol, AVAudioEngine input).

### 10.7 Tests to Keep Forever

These are the contract:

- `StateTests` — locks in the state machine shape.
- `TranscriberTests.multipartBodyShape` — locks in the wire format.
- `TranscriberTests.happyPath200` — locks in the request shape.
- `PasterTests.setsThenRestores` — locks in clipboard preservation.

Anything beyond these may be evolved freely as long as the manual M-checks
still pass.

---

## 11. Data Hygiene

### 11.1 What's in this repo

This repo will contain:

- Swift source files (no secrets).
- `Resources/Info.plist` (host name `linux` is internal; no client data).
- `Makefile`, `Package.swift` (no secrets).
- `README.md` (one-time setup).
- This plan (no secrets).

### 11.2 What's never in this repo

- Real audio recordings.
- Server URLs containing tokens.
- ASR API keys (the bearer is `local-no-auth`, a literal placeholder
  per the handoff — the server ignores it).
- TCC database content.
- `Voice.app` (build artifact, in `.gitignore`).
- `.build/` (SwiftPM artifact, in `.gitignore`).

### 11.3 .gitignore

```
.build/
Voice.app/
*.xcodeproj/
.DS_Store
```

---

## 12. Benchmark Data

Measured on the target Mac (M4, macOS 15.7.3) using the existing
`sox` / `curl` pipeline as a baseline:

| Operation | Time |
|-----------|-----:|
| `sox -d -r 16000 -c 1 -b 16` 3-second recording | ~3.05 s (3 s of audio + 50 ms cold start) |
| `curl` to `linux:8000/v1/audio/transcriptions` (3 s WAV) | ~400 ms |
| Total user-perceived latency on release | ~500 ms |

Targets for the native app (informational only, not gated):

- Cold-start overhead from release to upload starting: **< 50 ms**
  (engine is already warm).
- Paste delay after server response: **< 100 ms** + Paster's 600 ms
  restore window.
- End-to-end on release of a 3-second utterance: **< 1 s** to text
  appearing.

---

## 13. Coding Standards

The complete rules live in three steering files. This section pins the
specific rules every implementor must apply to this project.

### 13.1 Method Signature Verification

Before calling any AppKit / AVFoundation / CoreGraphics / IOKit symbol:

1. Confirm it exists at macOS 13+.
2. Read the actual signature from the developer docs.
3. Match parameter labels exactly.
4. Match return type to the assignment.

### 13.2 Logging

`os.Logger` only. One subsystem (`com.local.voice`) and a category per
module. Defined in `Logger.swift`. **No `print(...)` anywhere.**

### 13.3 Swift Standards (from `swift-coding-best-practices.md`)

- No `try!`, `as!`, `!` outside literal initializers and tests.
- `final class` for every class.
- `struct` / `enum` first; `class` only for identity / Objective-C bridging.
- `[weak self]` in escaping closures stored on `self`.
- All UI mutation on the main thread.
- Doc comments on every public/internal symbol.
- 4-space indent. 100-char target / 120-char hard cap.

### 13.4 macOS Standards (from `swift-macos-best-practices.md`)

- Keep `AVAudioEngine` running for process lifetime; rotate the file.
- Use `AVAudioConverter` to resample; don't pass a coerced format to
  `installTap`.
- ATS exception domain only; no `NSAllowsArbitraryLoads`.
- Re-enable `CGEventTap` on `.tapDisabledByTimeout` /
  `.tapDisabledByUserInput`.
- `CGEventSource(stateID: .combinedSessionState)` for synth Cmd+V.

### 13.5 Annie / Sauron (from `no-orphans-no-dual-paths.md`)

- Every new public/internal symbol has a caller in `Sources/` or `Tests/`.
- No two functions answer the same question. The 10-source-files
  responsibility table in §3.2 is the contract.

### 13.6 Error Handling

- Domain `Error` enum per subsystem (`AudioRecorder.AudioError`,
  `Transcriber.TranscribeError`).
- Conform to `LocalizedError` so `state = .error(err.localizedDescription)`
  produces a useful tooltip.
- Never silently swallow with `try?` outside of explicit
  best-effort cleanup.

### 13.7 Pre-Delivery Checklist (per file)

- [ ] All function signatures have parameter labels and a return type.
- [ ] Doc comment on the type and on every non-private member.
- [ ] Every closure escaping into a stored property uses `[weak self]`.
- [ ] All file/network ops have error handling that surfaces to the
      `state = .error(...)` transition.
- [ ] No hardcoded server URL or bearer outside of `AppDelegate.Config`.
- [ ] No invented framework calls — every signature verified.

---

## 14. Configuration & Defaults Display

### 14.1 UserDefaults

| Key | Default | Notes |
|-----|---------|-------|
| `voice.serverURL` | `http://linux:8000/v1/audio/transcriptions` | Must match `NSExceptionDomains` in Info.plist if non-`linux` |
| `voice.modelName` | `canary-qwen-2.5b` | Per handoff |
| `voice.bearerToken` | `local-no-auth` | Server ignores; non-empty placeholder per handoff |

### 14.2 No settings UI

A future task may add a Settings… menu item. v1 explicitly does not.
If the user wants to change defaults, they use `defaults write`. This
is documented in the README.

---

## 15. Line Count Summary

| Category | Lines |
|---------:|------:|
| Sources/Voice/ (10 files) | ~895 |
| Resources/Info.plist | 37 |
| Makefile + Package.swift | 67 |
| Tests/VoiceTests/ (6 files) | ~443 |
| README.md + manual-integration-checklist.md | ~160 |
| **Total project size** | **~1,600 lines** |

For comparison, the four prior tools that failed are 10–100× this size.
The minimal scope is the win.

---

## Appendix A: Complete File Reference

### NEW source files

| File | Purpose | Proposed |
|------|---------|----------|
| `Package.swift` | SwiftPM manifest | [link](proposed/code/Package.swift) |
| `Makefile` | Build + bundle + sign | [link](proposed/code/Makefile) |
| `Resources/Info.plist` | LSUIElement, ATS, mic prompt | [link](proposed/code/Resources/Info.plist) |
| `Sources/Voice/main.swift` | NSApplication bootstrap | [link](proposed/code/Sources/Voice/main.swift) |
| `Sources/Voice/AppDelegate.swift` | State machine + module wiring | [link](proposed/code/Sources/Voice/AppDelegate.swift) |
| `Sources/Voice/State.swift` | `AppState` enum | [link](proposed/code/Sources/Voice/State.swift) |
| `Sources/Voice/HotkeyMonitor.swift` | CGEventTap + dwell logic | [link](proposed/code/Sources/Voice/HotkeyMonitor.swift) |
| `Sources/Voice/AudioRecorder.swift` | AVAudioEngine + WAV | [link](proposed/code/Sources/Voice/AudioRecorder.swift) |
| `Sources/Voice/Transcriber.swift` | URLSession multipart | [link](proposed/code/Sources/Voice/Transcriber.swift) |
| `Sources/Voice/Paster.swift` | NSPasteboard + synth Cmd+V | [link](proposed/code/Sources/Voice/Paster.swift) |
| `Sources/Voice/Permissions.swift` | TCC requests | [link](proposed/code/Sources/Voice/Permissions.swift) |
| `Sources/Voice/StatusItemController.swift` | Menu-bar UI | [link](proposed/code/Sources/Voice/StatusItemController.swift) |
| `Sources/Voice/Logger.swift` | os.Logger categories | [link](proposed/code/Sources/Voice/Logger.swift) |
| `README.md` | One-time setup | [link](proposed/code/README.md) |

### NEW test files

| File | Purpose | Proposed |
|------|---------|----------|
| `Tests/VoiceTests/MockURLProtocol.swift` | URLSession mock harness | [link](proposed/tests/Tests/VoiceTests/MockURLProtocol.swift) |
| `Tests/VoiceTests/StateTests.swift` | AppState equality | [link](proposed/tests/Tests/VoiceTests/StateTests.swift) |
| `Tests/VoiceTests/TranscriberTests.swift` | Multipart body, HTTP paths | [link](proposed/tests/Tests/VoiceTests/TranscriberTests.swift) |
| `Tests/VoiceTests/AudioRecorderTests.swift` | Real WAV header check | [link](proposed/tests/Tests/VoiceTests/AudioRecorderTests.swift) |
| `Tests/VoiceTests/PasterTests.swift` | Pasteboard preserve / restore | [link](proposed/tests/Tests/VoiceTests/PasterTests.swift) |
| `Tests/VoiceTests/HotkeyMonitorTests.swift` | Construction smoke | [link](proposed/tests/Tests/VoiceTests/HotkeyMonitorTests.swift) |
| `Tests/manual-integration-checklist.md` | M1–M13 manual passes | [link](proposed/tests/manual-integration-checklist.md) |

### MODIFY files

None. This is a green-field project.

### DELETE files

None.

---

## Appendix B: Network Wire Reference

The proven `curl` from the handoff:

```bash
sox -d -r 16000 -c 1 -b 16 /tmp/test.wav trim 0 3
curl -sS -X POST "http://linux:8000/v1/audio/transcriptions" \
     -H "Authorization: Bearer local-no-auth" \
     -F "model=canary-qwen-2.5b" \
     -F "file=@/tmp/test.wav"
# {"text": "..."}
```

The Swift equivalent the implementor must produce (from
`Transcriber.swift` and the unit test that pins the bytes):

```
POST /v1/audio/transcriptions HTTP/1.1
Host: linux:8000
Authorization: Bearer local-no-auth
Content-Type: multipart/form-data; boundary=voice-<UUID>

--voice-<UUID>
Content-Disposition: form-data; name="model"

canary-qwen-2.5b
--voice-<UUID>
Content-Disposition: form-data; name="file"; filename="voice-<UUID>.wav"
Content-Type: audio/wav

<WAV BYTES>
--voice-<UUID>--
```

---

## Appendix C: Pushback (Adversarial Self-Review)

Before implementation begins, the original session must own the weak
points in this plan. The fresh session will read this section and
either accept the trade-offs or push back further.

### C.1 "Why a 200 ms qualification window? You'll feel laggy."

It only matters if you are tapping Right Option for under 200 ms. In
that case the user wasn't dictating — they were doing a shortcut or
typo. Real dictation lasts seconds, not milliseconds. The 200 ms is a
**filter**, not a delay; it does not affect the perceived
responsiveness of an actual dictation press because audio capture
starts at the same moment recording is committed, not 200 ms before.

**Pushback:** A user who taps Right Option for 180 ms intending to
dictate "no" gets nothing. Rebuttal: a 180 ms voiced "no" is too short
to transcribe usefully anyway — the ASR will return empty.
Nevertheless the threshold could be made a UserDefault (`voice.dwellMs`)
in v1.1 if it bites in practice.

### C.2 "Cmd+V can fail in apps with non-standard text input."

True. Some apps (Terminal at certain edge cases, sandboxed text views
with custom paste handlers, secure input fields like password prompts)
ignore synthesized Cmd+V. There is no fix at the OS level — Voxtype's
"paste-back broken on macOS" symptom may have been hitting these.

**Mitigation:** Document in README that secure input contexts (password
fields with `kEventClass... secure` set) do not accept dictation. v1.1
could add a "type-character-by-character" fallback using
`CGEventCreateKeyboardEvent` for each character — but that has its own
issues (autocomplete, dead keys, slow on long text).

For v1, accept the limitation. Test M3 in TextEdit confirms the common
path works.

### C.3 "Engine running for the lifetime of the process means a permanent mic indicator."

macOS shows the orange mic indicator whenever any process holds the
mic, regardless of whether audio is actually being written to disk.
With the engine warm, the indicator stays on the whole time Voice is
running.

**Trade-off:** indicator-always-on vs ~50 ms of clipped audio at the
start of each recording.

**Resolution:** the handoff says nothing about this; the prior tools
both keep it warm. v1 keeps the engine warm. If the always-on
indicator becomes a complaint, v1.1 can switch to start/stop per
press, accepting the audio clip at the start.

### C.4 "The Local Network prompt could permanently break a fresh install."

If the user dismisses the macOS 14+ Local Network prompt without
allowing it, all `linux:8000` requests fail silently with an obscure
NSURLError. The Voice icon will show the error tooltip but the user
may not connect "I dismissed a prompt" with "this LAN host is
unreachable".

**Mitigation:** The README explicitly mentions the prompt. The error
message in M5/M6 is descriptive enough (`HTTP 0` or
`NSURLErrorNotConnectedToInternet`). v1.1 could add a Settings menu
item that re-triggers the prompt by attempting a known-good request.

### C.5 "TCC re-prompts after every rebuild."

True if the binary's signature changes. The Makefile uses
`codesign -s -` (ad-hoc) with `--identifier com.local.voice`. Ad-hoc
signatures are stable across rebuilds **as long as the identifier and
the Mach-O architecture are the same**. There is a known macOS race
where TCC briefly forgets the grant after a fresh `make` (Daniel
Raffel's blog, "CGEvent Taps and Code Signing: The Silent Disable
Race").

**Mitigation:** if the tap silently fails after a rebuild, the
Makefile target `make reset-tcc` plus re-granting fixes it. Documented
in `swift-macos-best-practices.md` §7.

### C.6 "Tests can't actually verify the synth Cmd+V."

Right. A unit test cannot post a global key event into another app
process. The manual integration checklist's M3 is the only way to
verify it. This is a real gap.

**Resolution:** the manual checklist is the integration test. It is
mandatory before tagging `v0.1.0`. Pretending we have CI for paste-back
would be worse than admitting we don't.

### C.7 "What if the user's clipboard has both .string and an image, and they care about the image?"

Lost in v1. Documented as a v1 limitation in README and in §3.6.

**Pushback:** real users have cared about this in clipboard managers'
bug trackers since forever. Rebuttal: the four prior tools didn't
preserve anything; v1 preserves text. v1.1 can add multi-type
preservation (iterate `pasteboardItems`, save each `(type, data)`,
restore them all). It's a one-file change — not blocking v1.

### C.8 "What if `linux` resolves differently in the user's `/etc/hosts` than expected?"

The ATS exception domain is keyed on the literal hostname `linux`. If
the user changes `voice.serverURL` to point at a different host, ATS
will block the new host until the user also edits `Info.plist`.

**Mitigation:** README documents this. No automatic Info.plist mutation
because that requires re-signing, which is more friction than editing
the plist by hand.

### C.9 "AppDelegate is 142 lines and does too much."

Counter-argument: 142 lines with no business logic — only event routing
and state transitions. Splitting it further means inventing abstractions
for the sake of abstraction. Sauron rule: one entry point for state
transitions.

If it grows past ~200 lines, split out the error-clear timer and the
config loader. Don't pre-emptively split.

### C.10 "Why no Sparkle / auto-update?"

Out of scope for v1 (§0.3 guardrail #8). Voice updates by re-running
`make`. If you want auto-update, use Sparkle in v1.1.

### C.11 "The handoff says 'Right Command' was the original ask."

User explicitly changed it to Right Option in the conversation that
produced this plan. Right Option avoids hijacking real Cmd+
shortcut combinations. If Right Option turns out to be intercepted
by a third-party app, fall back to a fn-based hotkey or expose it via
UserDefaults (`voice.hotkeyKeycode`).

### C.12 "The bundle identifier `com.local.voice` doesn't match a real domain."

It is intentional. We never publish to the App Store. TCC only requires
the identifier to be stable, not real. If we ever sign with a Developer
ID, the identifier becomes `com.<your-domain>.voice`.

### C.13 "Why no SwiftUI?"

AppKit + os.Logger + a single status item is ~75 lines. SwiftUI would
add a `MenuBarExtra` (macOS 13+ only, OK) but require a `@main` `App`
struct, environment-driven state, and an extra layer of indirection. No
benefit for a 6-glyph icon.

### C.14 Unresolved questions for the reviewer

1. Should the qualification window be a UserDefault now or in v1.1?
2. Should we ship a Sparkle integration plan as a stub in this repo?
3. Should `voice.bearerToken` be read from a Keychain item instead of
   `UserDefaults` (which is plaintext on disk)?
4. Should the multipart body's `model` part value be sanitized? (We
   read it from `UserDefaults`. A malicious user-defaults write could
   inject `\r\n` and forge headers. The Transcriber currently does NOT
   validate.)
5. Should we add a manual `make verify` target that runs
   `swift test && grep -i "warning" build-output`?

The fresh session reviewing this plan must answer questions 1–5
explicitly before implementation begins, even if the answer is
"defer to v1.1."


---

## 16. Reviewer Verdict

This section is the explicit answer from the Round-2 reviewer to the
five questions left open in §C.14, plus the disposition of every
finding raised in `docs/plans/handoff-for-review.md`.

### 16.1 §C.14 verdicts

| # | Question | Verdict | Reason |
|--:|----------|---------|--------|
| 1 | Qualification window as UserDefault now or v1.1? | **Defer to v1.1.** | Hardcoded 200 ms is correct for the use case. Adding a UserDefault now creates configuration surface that nobody has asked for, and once it exists we can never remove it without breaking users. YAGNI. |
| 2 | Sparkle stub now or v1.1? | **Reject.** | Sparkle is out of scope per `voice-project.md` §Non-Goals. A stub would be orphaned code (Annie-rule violation). The update mechanism for v1 is `make`. |
| 3 | Bearer token Keychain or UserDefaults? | **UserDefaults for v1, document.** | The default value `local-no-auth` is not a secret. If a user configures a real token, they accept the same plaintext-on-disk threat model as the rest of `~/Library/Preferences`. README documents this. v1.1 may move to Keychain. |
| 4 | Sanitize `voice.modelName` for `\r\n`? | **Yes — must do.** | Implemented as `Transcriber.modelNameRegex = ^[A-Za-z0-9._-]{1,128}$`. Validation runs at `Transcriber.init` time; `AppDelegate` catches and surfaces the precise error. Also see F10. |
| 5 | `make verify` target now? | **Yes — added.** | One-line target: build `-c release`, fail if any compiler warning was emitted, then `swift test`. Pre-commit gate. |

### 16.2 Round-1 + Round-2 finding disposition

| ID | Severity (final) | Status |
|----|-------------------|--------|
| F1 | Block | Fixed — mic check via injected `MicrophoneStatusProviding` |
| F2 | Block | Fixed — `writeQueue.sync` in `stop()` drains in-flight writes |
| F3 | Block | Fixed — `@Suite(.serialized)` on `TranscriberTests` |
| F4 | Block | Fixed — `Paster` split into `ClipboardWriter` + `PasteSynthesizer` |
| F5 | Block | Fixed — tautological `HotkeyMonitorTests` removed |
| F6 | Major | Fixed — disqualifying-modifier check at right-option-down |
| F7 | Major | Fixed — `Task { @MainActor in … }` wrap on completion |
| F8 | Major | Fixed — `var hotkey: HotkeyMonitor?` (no IUO) |
| F9 | Major | Fixed — `TranscribeError` carries `String` messages, not `Error` |
| F10 | Major | Fixed — model-name allow-list at `Transcriber.init` |
| F11 | Major | Fixed — `setString` return value checked; abort paste on false |
| F12 | Minor (downgraded) | Fixed — `passRetained` + matching `release()` in `stop()` |
| F13 | Minor → deferred | Deferred to v0.2.0 (cosmetic) |
| F14 | Minor | Fixed — `--deep` removed from Makefile |
| F15 | Minor | Fixed — covered by F5 deletion |
| F16 | Minor | Fixed — `IOHIDAccessType` consulted; precise error surfaced |
| F17 | Nit (downgraded) | Accepted as-is; documented in `AppState` |
| F18 | Nit | Fixed — `Logger.swift` privacy comment added |
| F19 | Nit | Fixed — `AVLinearPCMIsNonInterleaved` removed |
| F20 | Status | Resolved by §16.1 above |
| F21 | Block (new) | Fixed — `writeQueue` serializes all access to `file`/`converter`/`outputFormat` |
| F22 | Block (new) | Fixed — `rightOptDown` toggled on every keycode-61 event; `.maskAlternate` no longer used to disambiguate |
| F23 | Major (new) | Fixed — `flagsChanged` for non-target keycode during arming cancels |
| F24 | Major (new) | Fixed — `removeTap` + `installTap` on every `start()` |
| F25 | Minor (new, Sauron) | Fixed — `Permissions.microphoneStatus()` is the single oracle |
| F26 | Minor (new) | Documented in `README.md` Limitations |
| F27 | Nit (new) | Fixed — `MockURLProtocol` uses `[UInt8]` buffer |
| F28 | Nit (new) | Fixed — tmp paths logged with `privacy: .private` |

### 16.3 Approval gate evidence

- `swift build -c release` in `docs/plans/proposed/code/`: see Round-3
  status appended to `handoff-for-review.md` for the verbatim run.
- `swift test` (with `VOICE_RUN_AUDIO_TESTS=0`): see same.
- `make verify` (build + zero-warnings grep + tests): same.

Approved for implementation. Copy `docs/plans/proposed/code/*` to the
canonical project layout at the repo root and tag `v0.1.0` once the
manual integration checklist (M1–M13) passes.
