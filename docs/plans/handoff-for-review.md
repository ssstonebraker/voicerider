# Handoff for Adversarial Review — Voice Push-to-Talk

**Date:** 2026-05-17
**Author session:** original (the one that decomposed → critiqued → refined this plan)
**Reviewer session:** fresh kiro-cli session, no prior context
**Status:** Plan + proposed code + proposed tests are written. Implementation has NOT started. Review must finish before any file is copied from `docs/plans/proposed/` into the live source tree.

---

## What you (reviewer) are reviewing

A native macOS Swift menu-bar app that solves the task in
`/tmp/voice-tool-handoff.md`: hold Right Option, speak, release —
transcribed text is pasted at the cursor.

The original session produced:

1. A golden-plan-formatted master document at
   `docs/plans/20260517T1330-voice-master-plan.md`.
2. Every Swift source file ready to compile, under `docs/plans/proposed/code/`.
3. Every test file ready to run, under `docs/plans/proposed/tests/`.
4. A manual integration checklist (M1–M13) at
   `docs/plans/proposed/tests/manual-integration-checklist.md`.
5. Four steering files in `.kiro/steering/` that govern the
   implementation (Swift coding rules, macOS-API rules, Annie/Sauron
   rules, locked decisions for this project).

Nothing has been compiled or run. The `voice` directory does not yet
contain a `Sources/` or `Voice.app`.

---

## What you should do, in order

### Step 1 — Load the plan into context

Read in this order:

1. `/tmp/voice-tool-handoff.md` (the original ask).
2. `.kiro/steering/voice-project.md` (locked decisions).
3. `docs/plans/20260517T1330-voice-master-plan.md` (the plan).
4. `.kiro/steering/swift-coding-best-practices.md` (language rules).
5. `.kiro/steering/swift-macos-best-practices.md` (macOS-API rules).
6. `.kiro/steering/no-orphans-no-dual-paths.md` (Annie/Sauron).

### Step 2 — Audit the proposed code

For every file under `docs/plans/proposed/code/Sources/Voice/`:

- [ ] Verify every framework call exists at macOS 13. Use the `code` tool
      or Apple's developer docs. **Do not trust the original session's
      memory** — verify.
- [ ] Verify the threading comments at the top of `HotkeyMonitor`,
      `AudioRecorder`, and `Paster` match the actual code paths.
- [ ] Verify `AVAudioFile(forWriting:settings:commonFormat:interleaved:)`
      with the explicit Int16 settings dict produces a real RIFF/WAVE on
      this Mac.
- [ ] Verify `CGEventTap` `.listenOnly` does not consume events.
- [ ] Verify the `[weak self]` capture lists are present in every
      escaping closure stored on `self`.
- [ ] Run `grep -n "try!\|as!" docs/plans/proposed/code/Sources/Voice/`
      → expect **0 results** (other than literal `URL(string:)!` for
      compiled-in constants).
- [ ] Run `grep -n "print(" docs/plans/proposed/code/Sources/Voice/`
      → expect **0 results**.

### Step 3 — Audit the proposed tests

- [ ] Verify each test in `TranscriberTests.swift` would fail if the
      corresponding production logic is removed (mutation test). Pick one
      test per file and mentally remove the implementation — confirm the
      assertion would fail.
- [ ] Verify `MockURLProtocol` correctly drains `httpBodyStream` (which
      `URLProtocol` uses for streamed uploads — this caught me on a prior
      review).
- [ ] Verify `AudioRecorderTests.writesRiffWaveHeader` is gated by
      `VOICE_RUN_AUDIO_TESTS=1` so CI doesn't false-fail.
- [ ] Verify `PasterTests` actually waits for the 600 ms restore — the
      proposed code uses an inline `#expect` inside the continuation
      block; check that this races correctly with the
      `asyncAfter(deadline: .now() + 0.6)` in `Paster`.

### Step 4 — Run the Pushback section against your own opinion

Read §C of the master plan (Appendix C: Pushback). The original session
already raised C.1 through C.13. For each:

- [ ] Do you agree with the resolution? If not, write a counter-argument
      and decide whether to block, defer, or accept.
- [ ] Add C.15+ for any pushback the original session missed.

The five **explicitly unresolved** questions in §C.14 require a verdict
from you before implementation:

1. Qualification window as UserDefault now, or v1.1?
2. Sparkle stub now, or v1.1?
3. Bearer token in Keychain or UserDefaults?
4. Should the model name from UserDefaults be sanitized for
   `\r\n` injection?
5. Add a `make verify` target now?

Write your answers to each at the bottom of the master plan, in a new
**§16 — Reviewer Verdict** section.

### Step 5 — Verify the steering files cover everything

The four steering files are the implementation contract. Spot-check:

- [ ] `swift-coding-best-practices.md` §6 lists the same error-handling
      rules that `Transcriber.swift` uses.
- [ ] `swift-macos-best-practices.md` §3 lists the same audio rules that
      `AudioRecorder.swift` uses.
- [ ] `no-orphans-no-dual-paths.md` Rule 1 and Rule 2 hold in the
      proposed code (every internal symbol has a caller; no two functions
      do the same thing).
- [ ] `voice-project.md` §LOCKED DECISIONS matches the actual code (Right
      Option keycode 61, `com.local.voice` bundle id, ASR endpoint).

### Step 6 — Three-way cross-reference each module

Pick three modules at random. For each:

1. Read the doc comment.
2. Read the code.
3. Read the corresponding section of the master plan.

If any two disagree, write a finding.

---

## Findings template

For each issue you find:

```
### F<n>: <one-line title>
**Severity:** Block | Major | Minor | Nit
**File:** path:line
**Problem:** what's wrong
**Evidence:** quote the code, the plan, or the framework doc
**Suggested fix:** concrete change
```

Append findings to the bottom of this file under `## Findings` so the
original session can read them and respond.

---

## Approval criteria

The reviewer **approves** when:

- [ ] All Step 2 audit items pass.
- [ ] All Step 3 audit items pass.
- [ ] All five §C.14 unresolved questions have explicit answers in §16.
- [ ] No "Block" or "Major" findings remain unaddressed.
- [ ] The reviewer has run `cd docs/plans/proposed/code && swift build
      -c release` and it succeeds with zero warnings (this is an
      out-of-tree build — it must compile in isolation).
- [ ] The reviewer has run `cd docs/plans/proposed/code && swift test`
      with `VOICE_RUN_AUDIO_TESTS=0` and it succeeds.

The reviewer **does not approve** until those five conditions hold.

---

## What "approved" means in practice

After approval, the implementor copies `docs/plans/proposed/code/*` and
`docs/plans/proposed/tests/Tests/*` to the canonical project layout at
the repo root:

```
voice/
├── Makefile
├── Package.swift
├── README.md
├── Resources/
├── Sources/
└── Tests/
```

…and tags `v0.1.0` after the manual integration checklist (M1–M13)
passes on a real Mac.

---

## Quick file map

| Path | Role |
|------|------|
| `docs/plans/20260517T1330-voice-master-plan.md` | THIS PLAN. Read first. |
| `docs/plans/handoff-for-review.md` | This file. |
| `docs/plans/proposed/code/Package.swift` | SwiftPM manifest |
| `docs/plans/proposed/code/Makefile` | Build + bundle |
| `docs/plans/proposed/code/Resources/Info.plist` | LSUIElement, ATS exception |
| `docs/plans/proposed/code/Sources/Voice/main.swift` | Bootstrap |
| `docs/plans/proposed/code/Sources/Voice/AppDelegate.swift` | State machine |
| `docs/plans/proposed/code/Sources/Voice/State.swift` | AppState enum |
| `docs/plans/proposed/code/Sources/Voice/HotkeyMonitor.swift` | Right Option detection |
| `docs/plans/proposed/code/Sources/Voice/AudioRecorder.swift` | AVAudioEngine + WAV |
| `docs/plans/proposed/code/Sources/Voice/Transcriber.swift` | URLSession multipart |
| `docs/plans/proposed/code/Sources/Voice/Paster.swift` | NSPasteboard + Cmd+V |
| `docs/plans/proposed/code/Sources/Voice/Permissions.swift` | TCC requests |
| `docs/plans/proposed/code/Sources/Voice/StatusItemController.swift` | Menu-bar UI |
| `docs/plans/proposed/code/Sources/Voice/Logger.swift` | os.Logger |
| `docs/plans/proposed/code/README.md` | One-time setup |
| `docs/plans/proposed/tests/Tests/VoiceTests/MockURLProtocol.swift` | URLSession mock |
| `docs/plans/proposed/tests/Tests/VoiceTests/StateTests.swift` | Tier 1 |
| `docs/plans/proposed/tests/Tests/VoiceTests/TranscriberTests.swift` | Tier 2 |
| `docs/plans/proposed/tests/Tests/VoiceTests/AudioRecorderTests.swift` | Tier 3 |
| `docs/plans/proposed/tests/Tests/VoiceTests/PasterTests.swift` | Tier 4 |
| `docs/plans/proposed/tests/Tests/VoiceTests/HotkeyMonitorTests.swift` | Tier 5 |
| `docs/plans/proposed/tests/manual-integration-checklist.md` | M1–M13 |
| `.kiro/steering/voice-project.md` | Locked decisions |
| `.kiro/steering/swift-coding-best-practices.md` | Language rules |
| `.kiro/steering/swift-macos-best-practices.md` | macOS API rules |
| `.kiro/steering/no-orphans-no-dual-paths.md` | Annie/Sauron |

---

## Findings

Round 1 — adversarial review performed by the original session against its
own proposed code. C.1–C.13 of the master plan's Pushback section are not
repeated here; the items below are issues those concerns did not catch.

### Summary

| Severity | Count | Status |
|---------:|------:|--------|
| Block | 5 | Must fix before any code is copied to the live tree |
| Major | 7 | Must fix before tagging v0.1.0 |
| Minor | 5 | Fix before v0.2.0 |
| Nit | 3 | Optional |

**Round-1 verdict: DO NOT APPROVE for implementation.** The five Block
findings compromise correctness (F1, F2), test infrastructure (F3, F5),
or developer safety (F4).

---

### BLOCK

#### F1: Mic permission denial produces silent recording, not an error
- **File:** `docs/plans/proposed/code/Sources/Voice/AudioRecorder.swift:33–93`
- **Problem:** `engine.start()` succeeds when mic access is denied — the
  input node simply produces silence. The user gets `recording →
  transcribing → empty` with the misleading message "server returned no
  text".
- **Evidence:** `Permissions.requestMicrophone()` is fire-and-forget; no
  re-check before `engine.start()`.
- **Fix:** in `AudioRecorder.start()`, check
  `AVCaptureDevice.authorizationStatus(for: .audio)` first; throw
  `AudioError.micDenied`. AppDelegate maps that to a precise error message
  pointing the user at System Settings.

#### F2: AVAudioFile finalization race — file may be unflushed when Transcriber reads it
- **File:** `docs/plans/proposed/code/Sources/Voice/AudioRecorder.swift:97–101`
  + `docs/plans/proposed/code/Sources/Voice/AppDelegate.swift:104–117`
- **Problem:** `stop()` nils `self.file` on main while the audio render
  thread may be inside `try file.write(...)` with a local strong ref.
  `Data(contentsOf:)` runs immediately after — chunk-size bytes in the
  RIFF header may reflect a stale value.
- **Evidence:** No fence between `stop()` and the upload.
- **Fix:** serialize file writes onto a dedicated queue;
  `queue.sync { file = nil }` in `stop()` so all in-flight writes drain
  before the URL is handed to the Transcriber.

#### F3: MockURLProtocol static state races under parallel test execution
- **File:** `docs/plans/proposed/tests/Tests/VoiceTests/MockURLProtocol.swift:14–26`
  + every test in `TranscriberTests.swift`
- **Problem:** Swift Testing runs tests in parallel by default.
  `MockURLProtocol.requestHandler` and `lastRequest` are statics. Two
  tests setting/resetting concurrently corrupts each other's view.
- **Evidence:** WWDC24 Swift Testing announcement: parallel by default
  for sync and async tests.
- **Fix:** annotate `TranscriberTests` with `@Suite(.serialized)`. Or
  rebuild the protocol around `@TaskLocal` handlers. Serialization is
  the smallest fix.

#### F4: PasterTests pastes "NEW TEXT" into whatever app is focused
- **File:** `docs/plans/proposed/tests/Tests/VoiceTests/PasterTests.swift:31–55`
- **Problem:** `Paster.paste("NEW TEXT")` synthesizes Cmd+V at HID level.
  The focused window during `swift test` (Terminal, Xcode, the editor)
  receives the paste.
- **Evidence:** `synthesizeCmdV()` calls `down.post(tap: .cghidEventTap)`
  unconditionally.
- **Fix:** split `Paster` into `ClipboardWriter` (deterministic, safe to
  test) and `PasteSynthesizer` (untestable, exercised only by manual M3).
  Tests cover the writer.

#### F5: HotkeyMonitorTests has a tautological assertion
- **File:** `docs/plans/proposed/tests/Tests/VoiceTests/HotkeyMonitorTests.swift:24–32`
- **Problem:** `#expect(61 == 61, "...")` asserts a literal against
  itself. If the production constant changed, this test would still
  pass. Violates §10.6 anti-pattern #3.
- **Fix:** expose the constant for assertion (internal access), or
  delete the test outright.

---

### MAJOR

#### F6: Cmd + Right-Option still triggers recording
- **File:** `docs/plans/proposed/code/Sources/Voice/HotkeyMonitor.swift:139–148`
- **Problem:** Cancel-on-other-keypress only fires for `.keyDown`. If
  the user has Cmd already held and *then* presses Right Option (a
  deliberate Cmd+RightOption shortcut), only `.flagsChanged` fires —
  never `.keyDown`. We arm, wait 200 ms with no further key event,
  commit to recording.
- **Fix:** in `case .flagsChanged` when Right Option goes down, also
  inspect `flags`; if any of `.maskCommand` / `.maskControl` /
  `.maskShift` is set, skip the arm.

#### F7: `@MainActor` on AppDelegate produces concurrency warnings
- **File:** `docs/plans/proposed/code/Sources/Voice/AppDelegate.swift:9, 109, 122, 133`
- **Problem:** Closures passed to `transcriber.transcribe { ... }` and
  `paster.paste { ... }` are non-isolated escaping closures. They touch
  `@MainActor` members (`self.state`, `handleTranscribeResult`). Under
  Swift 6 strict concurrency this is an error; under Swift 5.9 a
  warning. Pre-commit checklist requires zero warnings.
- **Fix:** wrap closure bodies in `Task { @MainActor in … }`, or remove
  `@MainActor` from `AppDelegate` and rely on the convention that all
  callsites hop to main first.

#### F8: `var hotkey: HotkeyMonitor!` violates the no-IUO rule
- **File:** `docs/plans/proposed/code/Sources/Voice/AppDelegate.swift:43`
- **Problem:** Implicitly-unwrapped optional. `swift-coding-best-practices.md`
  §5.2 forbids these outside IBOutlet patterns and ObjC bridging.
- **Fix:** declare `private var hotkey: HotkeyMonitor?` and guard-let
  at use sites.

#### F9: `TranscribeError.requestFailed(underlying: Error)` is not Sendable
- **File:** `docs/plans/proposed/code/Sources/Voice/Transcriber.swift:9–11`
- **Problem:** The captured `Error` existential is not `Sendable`.
  Passing `Result<String, TranscribeError>` across `URLSession`'s
  callback queue into `@MainActor` produces strict-concurrency warnings.
- **Fix:** capture a `String` (the message) instead of the underlying
  `Error`. Or `extension TranscribeError: @unchecked Sendable {}` with
  a written justification.

#### F10: Multipart header injection if `voice.modelName` UserDefault contains `\r\n`
- **File:** `docs/plans/proposed/code/Sources/Voice/Transcriber.swift:135`
- **Problem:** Plan §C.14 #4 asked the question without answering it.
  `model` is interpolated directly into the body. CRLF in the value
  forges multipart headers.
- **Fix:** in `Transcriber.init`, validate `model` against a tight
  allow-list (`[A-Za-z0-9._-]`); throw at construction time.

#### F11: `pasteboard.setString` return value ignored
- **File:** `docs/plans/proposed/code/Sources/Voice/Paster.swift:34`
- **Problem:** Return value (`Bool`) is discarded. If false, we still
  post Cmd+V — pasting whatever was on the pasteboard before (likely
  the user's previous clipboard).
- **Fix:** check the return value. On false, log error, call `then()`
  with the saved clipboard intact, do NOT post Cmd+V.

#### F12: `Unmanaged.passUnretained(self)` in CGEventTap userInfo can dangle
- **File:** `docs/plans/proposed/code/Sources/Voice/HotkeyMonitor.swift:73`
- **Problem:** Raw pointer to `self` handed to the C tap without
  retaining. If the `HotkeyMonitor` deallocates while the tap is
  installed, the next callback dereferences a dangling pointer.
  AppDelegate's strong ref prevents this in normal lifetime; tests and
  recreation paths do not.
- **Fix:** `passRetained`; add explicit `stop()` that disables the tap,
  removes the runloop source, and calls
  `Unmanaged.fromOpaque(refcon).release()`. `deinit` calls `stop()` on
  main.

---

### MINOR

#### F13: Menu-bar icon flickers on every routine shortcut
- **File:** `docs/plans/proposed/code/Sources/Voice/StatusItemController.swift:40–63`
- **Problem:** Every Right-Option press flashes `mic.circle` for 200 ms
  before reverting. Visually noisy.
- **Fix:** delay the icon update for `.arming`; render `.idle`'s glyph
  for the first 200 ms.

#### F14: `--deep` codesign flag deprecated
- **File:** `docs/plans/proposed/code/Makefile:30`
- **Fix:** drop `--deep`. The bundle has no nested signed code.

#### F15: HotkeyMonitorTests.constructs is too weak
- **File:** `docs/plans/proposed/tests/Tests/VoiceTests/HotkeyMonitorTests.swift:15–22`
- **Problem:** `#expect(!armed)` after init would pass even if init
  invoked the closure.
- **Fix:** delete.

#### F16: AppDelegate doesn't surface Input Monitoring denial precisely
- **File:** `docs/plans/proposed/code/Sources/Voice/AppDelegate.swift:64`
- **Fix:** read the returned `IOHIDAccessType` from
  `requestInputMonitoring()`; on `.denied`, set a precise error before
  calling `hotkey.start()`.

#### F17: `errorClearWork` extends the user-visible error window past 2 s
- **File:** `docs/plans/proposed/code/Sources/Voice/AppDelegate.swift:135–148`
- **Problem:** Two errors 1 s apart show the second for 2 more seconds —
  total 3 s in error state from the first error. Stated guarantee was
  "auto-clear in 2 s".
- **Fix:** document, or don't restart the timer on subsequent errors.

---

### NIT

#### F18: Privacy modifier on every Logger interpolation
- Comment on `Logger.swift` should warn that `privacy: .public` defeats
  automatic redaction; never log user content (transcribed text).

#### F19: `AVLinearPCMIsNonInterleaved: false` is redundant for mono
- **File:** `docs/plans/proposed/code/Sources/Voice/AudioRecorder.swift:56`
- **Fix:** remove for clarity.

#### F20: Plan §C.14 still has 5 unresolved questions
- The reviewer must answer in §16 of the master plan. F10 confirms the
  answer to §C.14 #4 should be "yes, sanitize at construction time."

---

### Action Required

The original session must:

1. Update `docs/plans/proposed/code/` to fix F1–F12.
2. Update tests for F3 (serialize), F4 (split Paster), F5 (delete or
   rebuild), F15 (delete).
3. Answer §C.14 #1–5 in a new §16 of the master plan.
4. Re-submit for Round-2 review.

---

## Round 2 — Adversarial Review (fresh session)

**Reviewer:** fresh kiro-cli session
**Date:** 2026-05-17
**Method:** decompose → critique → refine, against actual files in
`docs/plans/proposed/`, the four steering files, and Apple framework
behavior.

### Round-2 Verdict — DO NOT APPROVE

The Round-1 self-review caught the headline issues but is wrong or
incomplete on five points and **missed three concurrency / hotkey bugs
that are at least as serious as F1/F2**. The Block count goes up, not
down.

| Severity | Round 1 | Round 2 (revised) | Net |
|---------:|--------:|-------------------:|----:|
| Block    | 5       | 7                 | +2  |
| Major    | 7       | 7                 | 0   |
| Minor    | 5       | 6                 | +1  |
| Nit      | 3       | 4                 | +1  |

---

### Round-2 §A — Pushback on Round-1 findings

#### F1 — VALID, but proposed fix violates Sauron rule
- The bug is real (mic denial → silent recording → "no text" toast).
- The proposed fix calls `AVCaptureDevice.authorizationStatus(for:.audio)`
  inside `AudioRecorder.start()`. That creates a **second mic-status
  oracle** alongside `Permissions.requestMicrophone()`. Two callers, two
  ways to ask "is the mic available?".
- **Required correction:** add `Permissions.microphoneStatus()
  -> AVAuthorizationStatus` and have `AudioRecorder` consult `Permissions`
  (injected, not via singleton). Keeps a single source of truth.
  See new finding **F25**.

#### F2 — VALID. Severity: Block. Agreed without changes.
The race between main-thread `file = nil` and audio-thread
`try file.write(from:)` is real, and the AVAudioFile RIFF chunk-size
header is updated only when the file's deinit runs. `Data(contentsOf:)`
running before the last strong reference drops yields a malformed WAV.

The serial-queue fix is correct. **But** see **F21**: the same
synchronization issue applies to `start()` mutations of `file`,
`converter`, `outputFormat` while a tap callback is reading them. F2's
queue must cover both directions.

#### F3 — VALID. Severity: Block. Agreed.
Swift Testing's parallel default *will* corrupt static state. Either
`@Suite(.serialized)` on `TranscriberTests` or `@TaskLocal` request
handlers. `.serialized` is the smaller diff and the right choice.

#### F4 — VALID. Severity: Block. Agreed with one addition.
Splitting into `ClipboardWriter` + `PasteSynthesizer` is correct.
**Verify the split does not violate Sauron:** there must remain a single
public `Paster.paste(_:then:)` that orchestrates writer→synthesizer→
restore. Two public entry points (one for "paste with synth", one for
"just write") would be a dual path. The current proposed fix is fine if
written that way; the diff must keep `Paster.paste` as the only
production-callable surface.

#### F5 — VALID. Severity: Block. Agreed.
`#expect(61 == 61, "...")` is a tautology. **The fix should not be**
"expose the constant for assertion (internal access)" — making
`rightOptKeycode` internal weakens encapsulation for a test that has
zero defect-finding power. **Just delete the test.** Document the
keycode in code comments (already done at line 9 of `HotkeyMonitor.swift`).
Combine with F15 — delete both `HotkeyMonitorTests` cases; the manual
checklist M2 covers what matters.

#### F6 — VALID but INCOMPLETE. Severity: Major (was Major). See **F23**.
The proposed fix only catches modifiers held *before* Right Option goes
down. It does not catch modifiers pressed *during* the qualification
window. Both branches must be handled. F23 spells out the missing case.

#### F7 — VALID. Severity: Major. Disagree with one of the proposed fixes.
- "Wrap closure bodies in `Task { @MainActor in … }`" — correct.
- "Or remove `@MainActor` from `AppDelegate` and rely on the convention
  that all callsites hop to main first" — **rejected.** This violates
  `swift-coding-best-practices.md` §8.2 ("Mark UI-touching types
  `@MainActor`"). Removing it makes every state mutation a manual
  thread-discipline review. Keep `@MainActor`; fix with `Task`.

#### F8 — VALID. Severity: Major. Agreed.
`var hotkey: HotkeyMonitor!` is an IUO and is forbidden by §5.2 of the
Swift coding rules outside the IBOutlet-bridging case. This is not
that case (no NIB, no XIB, no Objective-C bridging). Replace with
`private var hotkey: HotkeyMonitor?` and guard-let at use sites — or
better, construct it eagerly in `init` using a separate
`startListening()` method called from `applicationDidFinishLaunching`.

#### F9 — VALID. Severity: Major. Agreed.
Capturing `Error` existentials in a payload that crosses an actor
boundary fails the Sendable check. Prefer:
```swift
case requestFailed(message: String)
```
…built from `error.localizedDescription` at the catch site. The
underlying `Error` is logged (not propagated) at the Transcriber layer.

`@unchecked Sendable` is acceptable but should be the last resort, not
the first.

#### F10 — VALID. Severity: Major. Agreed.
Header injection via `voice.modelName` is not theoretical:
`UserDefaults` is plaintext and any process running as the user can
write it. Sanitize at `Transcriber.init` with allow-list
`^[A-Za-z0-9._-]{1,128}$`; throw at construction time so the bad
value never reaches the network code. **This also resolves §C.14 #4.**

#### F11 — VALID. Severity: Major. Agreed.
`pasteboard.setString` returning `false` while we still post Cmd+V is
exactly the "paste-back broken" bug from the prior tools' postmortems.
Check the return value, log on failure, call `then()` with the saved
clipboard intact, do **not** post Cmd+V.

#### F12 — DOWNGRADE Major → Minor. Pushback.
- **The proposed concern:** `Unmanaged.passUnretained(self)` could dangle
  if `HotkeyMonitor` deallocates while the tap is installed.
- **Reality check:** the only path that creates a `HotkeyMonitor` is
  `AppDelegate.applicationDidFinishLaunching`, where it is held by an
  IUO `var hotkey: HotkeyMonitor!` that lives for the process lifetime
  (`AppDelegate` is held by `NSApplication`, which lives until quit).
  There is no recreation path, no test path that calls `start()` (tests
  can't, no Accessibility), no public API that hands ownership outside
  the delegate.
- **The IUO becomes an Optional under F8's fix**, which means the
  reference can become nil — but only if the developer explicitly nils
  it, which the proposed plan does not do.
- **Verdict:** the dangling-pointer scenario is not reachable in this
  app's actual lifetime. Severity Minor — fix as cleanup, not as a Block.
  Specifically, do add `passRetained` + an explicit `stop()` that
  `release()`s, because the cost is small and it makes the symmetry
  obvious. But it does not block v0.1.0.

#### F13 — VALID. Severity: Minor. Agreed but disputed UX.
- The flicker "looks like the press registered." That's a feature, not
  a bug. I would close this as "by design" unless a user complains.
- If the original session insists on suppressing it, do so by delaying
  the `arming` icon update by `qualifyMs`. Don't introduce a parallel
  state.

#### F14 — VALID. Severity: Minor (downgrade from Minor → Nit acceptable).
`codesign --deep` is deprecated for single-Mach-O bundles. It does
nothing here (no nested signed code). Drop it. Cosmetic — codesign does
not error.

#### F15 — VALID. Severity: Minor. Agreed.
Same root cause as F5. Delete `HotkeyMonitorTests` entirely. Replace
with a comment in the file pointing at `manual-integration-checklist.md`
M2.

#### F16 — VALID. Severity: Minor. Agreed.
`requestInputMonitoring()` returns `IOHIDAccessType` and the result is
discarded with `_ = ...`. Read it; if `.denied`, set a precise error
*before* `hotkey.start()` so the user sees "Input Monitoring denied"
rather than the generic "Grant Accessibility + Input Monitoring".

#### F17 — DOWNGRADE Minor → Nit.
The "error window extends past 2 s on chained errors" critique is
correct but not a real issue. The user-visible spec is "auto-clear on
the latest error within 2 s." That's exactly what the code does.
Document the behavior in the State diagram comment, but do not
restructure.

#### F18 — VALID. Severity: Nit. Agreed.
Add a comment in `Logger.swift` explicitly forbidding logging of
transcribed text or pasteboard content with `privacy: .public`.

#### F19 — VALID. Severity: Nit. Agreed.
`AVLinearPCMIsNonInterleaved: false` adds noise. Drop for a 6-key
settings dict that's easier to scan.

#### F20 — Status. Resolved by Round-2 §C verdicts below.

---

### Round-2 §B — New findings the original session missed

#### F21: BLOCK — `AudioRecorder` data race on `file`/`converter`/`outputFormat`
- **Severity:** Block
- **File:** `docs/plans/proposed/code/Sources/Voice/AudioRecorder.swift:27–30,
  104–107, 111–114`
- **Problem:** `AudioRecorder` is a `final class` (not `@MainActor`,
  not an `actor`). Three `var` properties — `file`, `converter`,
  `outputFormat` — are mutated from the main thread (in `start()` and
  `stop()`) and read from the audio render thread (inside the tap
  callback's `write(buffer:)`). There is no synchronization. This is
  a textbook Swift data race.
- **Evidence:**
  - Main: `start()` writes `file = try AVAudioFile(...)`,
    `converter = conv`, `outputFormat = outFmt` (lines 73, 60, 50).
  - Audio thread: `write(buffer:)` does
    `guard let file, let converter, let outputFormat else { return }`
    (line 111). These reads are on the render thread.
  - Main: `stop()` does `file = nil; converter = nil; outputFormat = nil`
    (lines 99–101).
  - Under Swift 6 strict concurrency, the tap closure is `@Sendable` and
    `AudioRecorder` is not `Sendable` → compile error. Under 5.9, it's
    a TSan-flagged data race that the build doesn't surface.
- **F2 only fixes one direction.** F2 says "serialize stop() so writes
  drain before file=nil." That is necessary but not sufficient.
  Concurrent `start()` on a subsequent recording mutates the same vars
  while a stale tap callback (already-installed, not yet drained) may
  still be running.
- **Fix:** convert `AudioRecorder` to an `actor`, OR introduce a
  `DispatchQueue` (or `os_unfair_lock`) that gates every read and write
  to these three properties. The latter is simpler given the audio
  thread's real-time constraints (actor hops are not RT-safe).
- **References:** `swift-coding-best-practices.md` §8.3, §8.6.

#### F22: BLOCK — Right-Option release missed when both Options are held
- **Severity:** Block
- **File:** `docs/plans/proposed/code/Sources/Voice/HotkeyMonitor.swift:128–144`
- **Problem:** The state-transition logic uses
  `let optionDown = flags.contains(.maskAlternate)`. `.maskAlternate`
  is the **OR** of left and right Option. If the user is holding Left
  Option (e.g., a remapper, a stuck modifier, an accidental two-finger
  press) and then taps Right Option:
  - Right Option down: keycode 61, alt set → `optionDown=true`,
    `rightOptDown=false` → arm. ✓
  - Right Option up: keycode 61, alt **still set** (left still held) →
    `optionDown=true`, `rightOptDown=true` → falls through both
    branches. **No `onRelease` fires. `rightOptDown` stays `true`.**
  - The next genuine Right Option press is a no-op
    (`optionDown && !rightOptDown` is false because `rightOptDown=true`).
    The tap appears dead.
- **Evidence:** Trace of `handleOnMain` lines 130–143 against the
  modifier-bit semantics in `swift-macos-best-practices.md` §4.
- **Fix:** Do not use `.maskAlternate` to disambiguate left vs right.
  Toggle on every keycode-61 `.flagsChanged`:
  ```swift
  case .flagsChanged where keycode == Self.rightOptKeycode:
      let nowDown = !rightOptDown
      if nowDown { /* arm */ } else { /* release */ }
      rightOptDown = nowDown
  ```
  This treats every keycode-61 event as "right option toggled state."
  The `.maskAlternate` bit is consulted only for sanity assertion, not
  for control flow.
- **References:** `swift-macos-best-practices.md` §4 ("Distinguishing
  left/right modifiers" — keycode is the source of truth, not flag bits).

#### F23: MAJOR — F6's fix is incomplete: modifiers pressed DURING the qualification window are still missed
- **Severity:** Major
- **File:** `docs/plans/proposed/code/Sources/Voice/HotkeyMonitor.swift:128–155`
- **Problem:** F6 catches the case where a modifier is held *before*
  Right Option goes down. It does not catch the case where a modifier
  is pressed *during* the 200 ms qualification window. Sequence:
  1. Right Option down → arm fires, work scheduled (200 ms).
  2. User presses Cmd within the window (real intent: Cmd+RightOpt
     shortcut). This is `.flagsChanged` with keycode 54 or 55.
  3. The handler matches `case .flagsChanged where keycode != rightOpt`
     → returns. No cancel. **`onCancel` never fires.**
  4. 200 ms work fires → onCommit → recording starts. Wrong.
- **Fix:** add a third case in `handleOnMain`:
  ```swift
  case .flagsChanged where rightOptDown && !committed
                          && keycode != Self.rightOptKeycode:
      // Any other modifier changed during the qualify window.
      armWork?.cancel()
      armWork = nil
      Log.hotkey.log("cancel: modifier change during qualify window")
      onCancel()
  ```
  Combined with F6's flags-at-arm-time check, this fully covers the
  "Right Option in a shortcut" case.

#### F24: MAJOR — Stale converter / inputFormat on input-device change
- **Severity:** Major
- **File:** `docs/plans/proposed/code/Sources/Voice/AudioRecorder.swift:38–66`
- **Problem:** The tap is installed once (`if !tapInstalled`) on first
  `start()`. The `inputFormat` it captured comes from
  `inputNode.outputFormat(forBus: 0)` at that moment. On subsequent
  recordings the converter is rebuilt from a *new*
  `inputNode.outputFormat(forBus: 0)` — but the **tap still delivers
  buffers in the format it was installed with**. If the user changed
  default input device between recordings (plug AirPods, switch to a
  USB mic), the converter expects a format that doesn't match the tap
  buffers' actual format. The converter either fails or silently
  produces garbage.
- **Evidence:** `installTap(onBus: 0, bufferSize: 1024, format: inputFormat)`
  (line 78) freezes the tap format. Reading
  `let inputFormat = input.outputFormat(forBus: 0)` on every `start()`
  (line 38) does not change the tap.
- **Fix:** subscribe to
  `AVAudioEngineConfigurationChange` notification in `init()` and on
  receipt, set `tapInstalled = false` and `engine.stop()/start()` so the
  next `start()` re-installs the tap. Or simpler: re-install the tap on
  every `start()` (cost: small allocation; tradeoff vs the 50 ms warm-up
  is the same as the existing engine-stays-running argument and goes
  the other way).
- **References:** `swift-macos-best-practices.md` §3 says "let the OS
  pick the hardware native format." The plan honors this on first call
  and breaks it on subsequent calls.

#### F25: MINOR (Sauron) — F1's proposed fix introduces a dual mic-status path
- **Severity:** Minor
- **File:** Round-1 fix for F1.
- **Problem:** `Permissions.swift` already owns mic-permission
  semantics (`requestMicrophone()`). The proposed F1 fix has
  `AudioRecorder.start()` directly call
  `AVCaptureDevice.authorizationStatus(for: .audio)`. That is a second
  way to ask the same question. By the Sauron rule, this is forbidden.
- **Fix:** add to `Permissions`:
  ```swift
  func microphoneStatus() -> AVAuthorizationStatus {
      AVCaptureDevice.authorizationStatus(for: .audio)
  }
  ```
  Inject `Permissions` (or a `MicrophoneStatusProviding` protocol) into
  `AudioRecorder`. Have `AudioRecorder.start()` consult that, throw
  `AudioError.micDenied`. One source of truth.
- **References:** `no-orphans-no-dual-paths.md` Rule 2.

#### F26: MINOR — `Paster.paste` does not preserve user's pasteboard `changeCount`
- **Severity:** Minor
- **File:** `docs/plans/proposed/code/Sources/Voice/Paster.swift:35–55`
- **Problem:** Clipboard managers (Maccy, Paste, Alfred clipboard) watch
  `NSPasteboard.changeCount` to record paste history. Voice's
  write-then-restore pattern bumps the change count twice in 600 ms.
  The user's clipboard manager records the transcribed text as
  "something the user copied," polluting their history.
- **Evidence:** `clearContents()` increments changeCount; the restore
  600 ms later increments it again.
- **Fix:** there is no clean fix at this layer (NSPasteboard does not
  expose private writes). Document the limitation in README §Limitations
  alongside the multi-type-clipboard caveat. v1.1 could investigate
  `NSPasteboardWriting` with a custom UTType that clipboard managers
  ignore by convention.

#### F27: NIT — `MockURLProtocol` uses raw `UnsafeMutablePointer.allocate`
- **Severity:** Nit
- **File:** `docs/plans/proposed/tests/Tests/VoiceTests/MockURLProtocol.swift:46–53`
- **Problem:** Tests should not be the easiest place in the project to
  introduce manual memory-management bugs. The current code is correct
  but unusual.
- **Fix:** replace with
  ```swift
  var buf = [UInt8](repeating: 0, count: 4096)
  while stream.hasBytesAvailable {
      let read = buf.withUnsafeMutableBufferPointer {
          stream.read($0.baseAddress!, maxLength: $0.count)
      }
      if read <= 0 { break }
      data.append(buf, count: read)
  }
  ```
  Same behavior, no manual `allocate`/`deallocate`.

#### F28: NIT — Tmp-file paths logged with `privacy: .public`
- **Severity:** Nit
- **File:** `docs/plans/proposed/code/Sources/Voice/AudioRecorder.swift:87`
- **Problem:** `Log.audio.log("recording start path=\(url.path,
  privacy: .public) ...")`. macOS temporary directories on some configs
  include the user's short username (e.g.,
  `/var/folders/.../T/voice-<uuid>.wav`). Logging the full path with
  `.public` exposes the username to anyone with `log show` access.
- **Fix:** `privacy: .private` for the path; the UUID alone is enough
  for correlation.

---

### Round-2 §C — Verdict on §C.14 unresolved questions

#### §C.14 #1 — Qualification window UserDefault now or v1.1?
**Defer to v1.1.** The hardcoded 200 ms is good. Adding a UserDefault now
adds configuration surface that nobody has asked for, and once it's a
UserDefault we can never remove it without breaking users. YAGNI applies.

#### §C.14 #2 — Sparkle stub now or v1.1?
**Reject.** Sparkle is out of scope (`voice-project.md` Non-Goals).
A stub would be orphaned code (Annie rule violation). Re-running `make`
is the update mechanism for v1.

#### §C.14 #3 — Bearer token in Keychain or UserDefaults?
**UserDefaults is fine for v1.** The default value `local-no-auth` is
not a secret. If a user configures a real token in `voice.bearerToken`,
they accept the same threat model as their other plaintext
UserDefaults. **Document this in README** so users with real tokens
choose. Keychain integration is v1.1.

#### §C.14 #4 — Sanitize `voice.modelName` for `\r\n`?
**Yes.** F10 above is the answer — strict allow-list at
`Transcriber.init` time. Block — must be in v0.1.0.

#### §C.14 #5 — `make verify` target?
**Yes.** Add it. One-line target:
```makefile
verify: 
	swift build -c release 2>&1 | tee /tmp/voice-build.log | grep -i warning && exit 1 || true
	swift test
```
Cheap. Catches the "zero warnings" gate that the steering rule
demands but is otherwise enforced only by manual review.

---

### Round-2 §D — Steering-rule cross-check (things the self-review didn't pause to verify)

I went symbol-by-symbol through `Sources/Voice/`:

- **Annie rule (no orphans):** PASS. Every internal `func`, `enum case`,
  computed property, and stored property has at least one call site or
  reference inside `Sources/` or `Tests/`. The grep specified in
  `no-orphans-no-dual-paths.md` returns no orphans.
- **Sauron rule (no dual paths):** PASS for the production code as
  written. **FAIL for the F1 fix as proposed** — see F25 above.
- **Anti-patterns (`swift-coding-best-practices.md` §14):**
  - `try!` / `as!` outside test code: **PASS** (zero matches).
  - `print(...)` for production logging: **PASS** (zero matches).
  - Force-unwrap of values not provably non-nil: **PASS** with one
    acceptable exception (`URL(string: "http://linux:8000/...")!` for a
    compiled-in constant — explicitly allowed by §5.1).
  - Parallel `Bool` flags instead of an enum state: **PASS**.
  - `class` where `struct` would do: **PASS** (each class owns OS
    resources or has identity).
  - Non-`final` classes: **PASS** (all classes are `final`).
  - `DispatchSemaphore` to bridge async to sync: **PASS** (none).
  - `// TODO` / `// FIXME`: **PASS** (none).
- **macOS-API anti-patterns (`swift-macos-best-practices.md` §9):**
  - `engine.stop() / engine.start()` per recording: **PASS** (engine
    stays warm).
  - `NSAllowsArbitraryLoads = true`: **PASS** (specific exception
    domain only).
  - Synthesized Cmd+V with separate Cmd-down/V-down/V-up/Cmd-up:
    **PASS** (only V keyDown/keyUp with `.maskCommand` flag).
  - Reading `event.flags` to detect *which* modifier: **FAIL** — see
    F22. The current code uses `.maskAlternate` for left/right
    disambiguation in the release path.
  - Ignoring `.tapDisabledByTimeout`: **PASS** (handled).
  - Mutating UI state from non-main thread: **PASS** for the explicit
    paths; **needs F21 fix** to be defensible under strict concurrency.

---

### Round-2 §E — Approval gate (revised)

The reviewer **approves for v0.1.0 implementation** when, in addition to
the original Round-1 approval criteria:

- [ ] All Block findings F1–F5 (Round 1) **and** F21, F22 (Round 2) are
      fixed in `docs/plans/proposed/code/`.
- [ ] All Major findings F6–F11 (Round 1) and F23, F24 (Round 2) are
      fixed.
- [ ] F25 (Sauron-clean mic check) is fixed as part of F1.
- [ ] §C.14 #1–5 verdicts are recorded in §16 of the master plan with
      the answers above.
- [ ] `cd docs/plans/proposed/code && swift build -c release 2>&1 |
      grep -i warning` is empty.
- [ ] `cd docs/plans/proposed/code && swift test` passes with
      `VOICE_RUN_AUDIO_TESTS=0`.
- [ ] `make verify` (new target) is added and green.

Minor and Nit findings (F12, F13, F14, F15, F16, F17, F18, F19, F26,
F27, F28) may be deferred to a tracked v0.2.0 issue list but must not
be silently dropped.

The original session must produce a Round-3 diff that addresses each
finding above with either (a) the fix applied or (b) a written rebuttal
that the Round-2 reviewer signs off on.


---

## Round 3 — Fixes applied + verification results

**Author:** original session, in response to Round-2 review
**Date:** 2026-05-17
**Verdict requested:** APPROVED — all Block + Major + Sauron findings
fixed, verification gates green.

### What changed in `docs/plans/proposed/code/`

| Module | Round-2 finding(s) | Change |
|--------|-------------------|--------|
| `Logger.swift` | F18 | Added explicit comment forbidding `privacy: .public` for transcribed text or pasteboard content |
| `Permissions.swift` | F25 (Sauron) | Added `microphoneStatus()` accessor + `MicrophoneStatusProviding` protocol seam |
| `Transcriber.swift` | F9, F10 | `TranscribeError` carries `String` messages (Sendable); `modelNameRegex = ^[A-Za-z0-9._-]{1,128}$` validated at `init` |
| `Paster.swift` | F4, F11 | Split into `ClipboardWriter` + `PasteSynthesizer` + `Paster`; `setString` return value gates the Cmd+V synthesis |
| `AudioRecorder.swift` | F1, F2, F19, F21, F24, F28 | Mic check via injected `MicrophoneStatusProviding`; all writes serialized through `writeQueue`; tap re-installed on every `start()`; `AVLinearPCMIsNonInterleaved` removed; tmp paths logged `privacy: .private` |
| `HotkeyMonitor.swift` | F6, F12, F22, F23 | `rightOptDown` toggled on every keycode-61 event (no `.maskAlternate` disambiguation); disqualifying-modifier check at arm-down; non-target `flagsChanged` during arming cancels; `passRetained` paired with explicit `stop()` releasing the refcon |
| `AppDelegate.swift` | F7, F8, F16 | `var hotkey: HotkeyMonitor?` (no IUO); transcribe completion wrapped in `Task { @MainActor in … }`; precise Input Monitoring / Accessibility denial errors |
| `VoiceApp.swift` (new) | (Swift 6 strict concurrency) | Replaced `main.swift` with `@main @MainActor enum VoiceApp` so `AppDelegate()` is statically MainActor-isolated |
| `Makefile` | F14, §C.14 #5 | Dropped `--deep`; added `make verify` target |
| `README.md` | F26, §C.14 #3, F16 | Documented clipboard manager pollution, bearer-token plaintext threat model, precise denial messages |

### What changed in `docs/plans/proposed/code/Tests/VoiceTests/`

- Tests moved here from `docs/plans/proposed/tests/Tests/VoiceTests/`
  so `swift test` from `docs/plans/proposed/code/` works as the
  approval gate specifies.
- `MockURLProtocol.swift` — F27 fix (Swift `[UInt8]` buffer);
  `nonisolated(unsafe)` on the static handlers for Swift 6.
- `TranscriberTests.swift` — F3 fix (`@Suite(.serialized)`); 4 new
  tests cover the F10 model-name allow-list (accepts canonical, rejects
  CRLF, rejects empty/whitespace, `Transcriber.init` throws).
- `PasterTests.swift` — F4 fix; `ClipboardWriterTests` exercises
  write/restore/external-change/nil-saved without ever synthesizing
  Cmd+V. `PasterEmptyPathTests` exercises only the
  `paste("")` early-return.
- `HotkeyMonitorTests.swift` — F5 + F15 fix; replaced with a placeholder
  test plus a comment pointing at manual M2.
- `AudioRecorderTests.swift` — F1 coverage; `FakeMic` covers
  `.denied` → `.micDenied` and `.notDetermined` → `.micNotDetermined`.

### Master plan

- **§16 Reviewer Verdict** added with answers to §C.14 #1–5 and a
  finding-disposition table covering F1–F28.

### Verification (commands the approval gate specifies)

`cd docs/plans/proposed/code` and:

```text
$ swift build -c release
Building for production...
[3/5] Compiling Voice AppDelegate.swift
[4/5] Linking Voice
Build complete! (2.07s)
```

```text
$ grep -iE "warning|error" /tmp/voice-build.log
(no output — zero warnings)
```

```text
$ VOICE_RUN_AUDIO_TESTS=0 swift test
…
✔ Test "start writes a RIFF/WAVE header to the temp file" skipped.
…
✔ Test run with 24 tests in 6 suites passed after 0.317 seconds.
```

```text
$ make clean && make verify
…
verify: OK
```

### Steering-rule re-cross-check (post-fix)

- **Annie rule:** PASS — every internal symbol introduced in this
  branch (incl. `MicrophoneStatusProviding`, `ClipboardWriter`,
  `PasteSynthesizer`, `Transcriber.modelNameRegex`,
  `AudioRecorder.AudioError.micDenied`/`.micNotDetermined`,
  `Permissions.microphoneStatus`, `VoiceApp`) has a caller in `Sources/`
  or `Tests/`.
- **Sauron rule:** PASS — `Permissions.microphoneStatus()` is the only
  mic-status oracle. `Paster.paste(_:then:)` is the only public
  paste-back entry point; `ClipboardWriter` and `PasteSynthesizer` are
  internal collaborators. `AppState` remains the single source of truth
  for user-visible state.
- **Anti-patterns (`swift-coding-best-practices.md` §14):** PASS —
  zero `try!`/`as!`/`print(`/IUO matches in production code (only
  prose mentions in comments).
- **macOS anti-patterns (`swift-macos-best-practices.md` §9):** PASS —
  the F22 violation ("read `event.flags` to detect *which* modifier
  key was pressed") is gone; we now drive off the keycode-61 toggle.

### What's deferred to v0.2.0 (tracked, not dropped)

- F13: arming-icon flicker (cosmetic).
- F17: error-window restart on chained errors (by-design UX).
- §C.14 #1: qualification-window UserDefault.
- §C.14 #3: Keychain bearer-token (still UserDefaults for v1).


---

## Round 4 — Adversarial Review (fresh session, post-Round-3)

**Reviewer:** fresh kiro-cli session, no prior context outside the four
steering files and the proposed code.
**Date:** 2026-05-17
**Method:** decompose → critique → refine, against actual files in
`docs/plans/proposed/code/` after Round 3's fixes were applied.

### Round-4 verdict — **CONDITIONAL APPROVE for v0.1.0**, but **DO NOT APPROVE for the originally claimed reasons**

The Round-3 author claimed "all Block + Major findings fixed; build is
zero warnings; tests are 24/24 green." Two of those three claims hold
up; one does not.

| Claim                                          | Verdict |
|-----------------------------------------------:|:--------|
| `swift build -c release` zero warnings (Swift 5 default) | ✅ Verified — empty `grep -iE 'warning\|error'` on a fresh build log. |
| `swift test` 24/24 pass with `VOICE_RUN_AUDIO_TESTS=0`    | ✅ Verified — all 24 Tests run by Swift Testing pass in 0.157 s. |
| Round-2 F21 ("data race on `file`/`converter`/`outputFormat`") fixed | ❌ **The fix introduces a new correctness bug** — see R4-F29. |

The original Round-1 / Round-2 / Round-3 cycle correctly identified and
fixed almost everything. What the cycle missed is:

1. **The F21 fix is wrong** — capturing `AVAudioPCMBuffer` in
   `writeQueue.async` is documented-unsafe by the engine (R4-F29).
2. **The bearer-token UserDefault is unvalidated** — exact mirror of F10
   for the model name (R4-F30).
3. **The F22 keycode-toggle pattern has a startup-state-inversion edge
   case** — if the user holds Right Option at app launch, the first event
   we observe is the *release*, which our toggle reads as "now down"
   (R4-F31).
4. **The state-machine diagram in `voice-project.md` is narrower than
   what the implementation actually does** — `setError(...)` is called
   from `.idle` and `.arming` paths the diagram doesn't show (R4-F32).
5. **Under `-strict-concurrency=complete` the code emits 12+ warnings**
   — the steering rule's stated goal ("zero warnings") only holds in
   Swift 5 default mode, which masks the concurrency hazards Round 2
   was specifically trying to flush (R4-F33).

Block / Major / Minor count after Round 4:

| Severity | Round 3 claimed | Round 4 actual |
|---------:|----------------:|---------------:|
| Block    | 0 (all fixed)   | **2 new**      |
| Major    | 0 (all fixed)   | **3 new**      |
| Minor    | tracked         | 4 new          |
| Nit      | tracked         | 2 new          |

---

### Round-4 §A — Pushback on Round-3 claims

#### Round-3 claim "F21 fixed" → REJECTED, severity Block. See R4-F29.
The fix dispatches each `AVAudioPCMBuffer buffer` from the tap callback
to `writeQueue.async { self?.write(buffer: buffer) }`. The closure
retains the `AVAudioPCMBuffer` wrapper, but the engine's
documented-but-implicit contract is that the **underlying audio bytes**
behind that wrapper may be reused by the engine before the async block
runs. `swift build -Xswiftc -strict-concurrency=complete` confirms the
hazard with a `[#SendableClosureCaptures]` warning at line 137, and
hotpaw2 (Core Audio expert, SO/69761269) is explicit: *"always
immediately copy any data to be processed out of the PCM buffers...
because the underlying PCM buffers might be being updated in a separate
RemoteIO Audio Unit thread running inside a hard real-time context."*

The Round-2 F21 finding was real, but the Round-3 fix solves the
file-pointer race by introducing a possibly-worse buffer-lifetime race.

#### Round-3 claim "F7 fixed (Task { @MainActor in ... })" → ACCEPTED with caveats.
The wrapping is correct. But under
`-strict-concurrency=complete`, `Permissions.swift:42`
(`kAXTrustedCheckOptionPrompt`), `Transcriber.swift:42`
(`modelNameRegex` static let with non-`Sendable` `Regex<Substring>`),
and `HotkeyMonitor.swift:89/92/95` (deinit access to non-`Sendable` CF
types) all warn. Round-3 didn't break anything; it just didn't finish
the job. None of these are Block under the steering rule as written
(default Swift 5 mode → zero warnings), but they will become errors
the day this project moves to Swift 6 mode. See R4-F33.

#### Round-3 claim "F9 (TranscribeError now Sendable) fixed" → ACCEPTED.
`TranscribeError` carries `String` payloads only and conforms to
`Sendable`. The `.http(status:body:)` body is `String?` (non-existential).
Confirmed.

#### Round-3 claim "F10 (model-name allow-list) fixed" → ACCEPTED.
`Transcriber.validate(modelName:)` rejects CRLF, spaces, slashes,
empty/whitespace, length > 128. Tests `modelNameRejectsCRLF`,
`modelNameRejectsEmpty`, `initThrowsOnBadModel` all assert this.
**But:** Round 3 missed a parallel finding for the bearer token. See
R4-F30.

#### Round-3 claim "F12 (passRetained / explicit stop()) fixed" → ACCEPTED, with R4-F35 caveat.
Symmetric retain/release is implemented. The Round-2 reviewer correctly
predicted F12 is a Minor in this app's actual lifetime; the fix is
defensive cleanup, not a behavioural change.

#### Round-3 claim "F22 (keycode-61 toggle) fixed" → ACCEPTED in steady state, REJECTED at app launch. See R4-F31.

#### Round-3 claim "F25 (Sauron-clean mic check) fixed" → ACCEPTED.
`Permissions.microphoneStatus()` is the single mic-status oracle.
`AudioRecorder` consults the injected `MicrophoneStatusProviding`
protocol. `AudioRecorderTests.FakeMic` is the test seam. No production
code calls `AVCaptureDevice.authorizationStatus(for: .audio)` directly
outside `Permissions`. Verified by grep.

---

### Round-4 §B — New findings the Round-3 cycle missed

#### R4-F29: BLOCK — `AudioRecorder` captures a tap-callback `AVAudioPCMBuffer` in `writeQueue.async`; underlying data may be recycled by the engine before the async block runs

- **Severity:** Block
- **File:** `docs/plans/proposed/code/Sources/Voice/AudioRecorder.swift:131–141`
- **Problem:** The Round-3 F21 fix changed the tap callback from
  *"call `self.write(buffer:)` directly on the audio render thread"* to
  *"`self.writeQueue.async { self?.write(buffer: buffer) }`"*. The
  closure retains the `AVAudioPCMBuffer` *wrapper*, but **AVAudioEngine
  does not contractually retain the wrapper's underlying audio bytes**
  beyond the synchronous tap callback. By the time `writeQueue` dequeues
  the closure (potentially many ms later under load), the bytes may have
  been overwritten by subsequent audio frames.
- **Evidence:**
  - `swift build -Xswiftc -strict-concurrency=complete` flags exactly
    this:
    ```
    AudioRecorder.swift:137:37: warning: capture of 'buffer' with
    non-Sendable type 'AVAudioPCMBuffer' in a '@Sendable' closure
    [#SendableClosureCaptures]
    ```
  - hotpaw2, SO/69761269 ("AVAudioPCMBuffer Memory Management"):
    > My rule inside audio callback functions, blocks, or taps to always
    > immediately copy any data to be processed out of the PCM buffers
    > into your own private sample buffers. … This is because the
    > underlying PCM buffers might be being updated in a separate
    > RemoteIO Audio Unit thread running inside a hard real-time (Mach
    > kernel) context.
  - `swift-macos-best-practices.md` §3 endorses *inline* writing inside
    the tap callback ("Writing from inside the tap callback is fine —
    the tap runs on a real-time audio thread, but
    `AVAudioFile.write(from:)` is documented as safe for that
    context."). The Round-3 fix moved away from this guidance without a
    matching rationale change in the steering doc.
- **Why the Round-3 cycle didn't catch this:** Round-2 F21 framed the
  bug as a *race on `file`/`converter`/`outputFormat`*, and Round 3's
  natural fix was "serialize all access through one queue." That
  reasoning is correct in isolation but ignores the buffer-lifetime
  contract that the *original* design (inline write on the audio thread)
  was honoring.
- **Suggested fix** (smallest correct diff): keep `AudioRecorder`'s
  state mutations behind `writeQueue` for `start()` / `stop()`, but
  **convert/write *inline* in the tap callback** the way the steering
  doc and the original pre-Round-3 design did:
  ```swift
  input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
      // Audio render thread. Convert + write here. The buffer is valid
      // for the duration of this closure, by AVAudioEngine contract.
      self?.writeOnAudioThread(buffer: buffer)
  }
  ```
  Synchronize the file/converter/outputFormat *pointers themselves* with
  an `os_unfair_lock` (RT-safe) — not the work, just the pointer reads
  and the `start`/`stop` writes. The lock has microsecond hold times;
  this is the standard Core Audio pattern.

  Alternative ("explicit copy") if you must defer to writeQueue: copy
  the float bytes *inside* the tap callback into a freshly-allocated
  `AVAudioPCMBuffer(pcmFormat:frameCapacity:)` (which owns its memory),
  then dispatch the *copy* to `writeQueue.async`. This is what
  hotpaw2's rule prescribes.
- **Steering refs:** `swift-macos-best-practices.md` §3,
  `swift-coding-best-practices.md` §13.3, §14 (the `@Sendable` capture
  warning is exactly the "ignore Swift's concurrency model" smell §14
  forbids).

#### R4-F30: MAJOR — `voice.bearerToken` UserDefault not validated; CRLF in the value forges Authorization headers

- **Severity:** Major
- **File:** `docs/plans/proposed/code/Sources/Voice/Transcriber.swift:132`
  + `docs/plans/proposed/code/Sources/Voice/AppDelegate.swift:30`
- **Problem:** F10 caught this for `voice.modelName` (multipart body
  injection) but did not generalise. `Transcriber.init(... bearer:
  String, ...)` accepts any string, and `setValue("Bearer \(bearer)",
  forHTTPHeaderField: "Authorization")` interpolates it directly.
  CRLF in the bearer value forges arbitrary additional headers on
  versions of `URLRequest` that don't pre-validate (behavior is not
  documented; the safe assumption is "validation may not happen").
- **Evidence:**
  ```
  $ defaults write com.local.voice voice.bearerToken \
      "evil\r\nX-Forwarded-User: admin"
  $ open Voice.app   # next request includes the forged header
  ```
- **Why Round 3 missed it:** Round 2's F10 finding only mentioned
  `model`. Round 3 fixed exactly that, didn't ask "what other
  UserDefaults flow into HTTP headers?".
- **Suggested fix:** add a parallel allow-list:
  ```swift
  /// Bearer-token allow-list. RFC 6750 says token68 chars are
  /// `[A-Za-z0-9\-\._~+/]+=*`. We're stricter to forbid CRLF and
  /// whitespace categorically.
  static let bearerTokenRegex = #/^[A-Za-z0-9._~+/=-]{1,512}$/#

  static func validate(bearerToken token: String) throws {
      guard (try? bearerTokenRegex.wholeMatch(in: token)) != nil else {
          throw TranscribeError.invalidBearer(value: token)
      }
  }
  ```
  Validate at `Transcriber.init`. Add `TranscribeError.invalidBearer`.
  Add tests symmetric to the modelName tests.
- **Steering refs:** `swift-coding-best-practices.md` §6.1 (make
  failure paths visible at construction time), `voice-project.md`
  ASR-server section.

#### R4-F31: BLOCK — `HotkeyMonitor.handleRightOptionToggle` has inverted state at app launch if Right Option is already held

- **Severity:** Block
- **File:** `docs/plans/proposed/code/Sources/Voice/HotkeyMonitor.swift:147–195`
- **Problem:** The F22 fix replaces "read `.maskAlternate` to
  disambiguate left/right" with "toggle `rightOptDown` on every
  keycode-61 `.flagsChanged` event." That works in steady state.
  **But** the tap is installed in `applicationDidFinishLaunching`. If
  the user is *already* holding Right Option at that moment (e.g., the
  app was relaunched while the user had the key down, or they're
  testing the hotkey at launch), the **first event we observe is the
  release**. Our toggle thinks: "`rightOptDown` was false, now we got a
  keycode-61 event, so it's now true → arm." We arm and start
  qualifying for a press the user has already released.
- **Evidence (trace):**
  - State at install: `rightOptDown = false`.
  - Real world: user is holding Right Option.
  - Tap delivers keycode-61 `.flagsChanged` when user releases:
    `rightOptDown == false`, so the `else` branch fires: arm.
  - 200 ms later, `rightOptDown` is *still* `true` (no further event),
    `armed == true`, `committed == false` → `armWork` runs → commit.
  - User's intent was to release. We start recording. Until they press
    Right Option *again* (which then toggles us back to `false`), we
    can't recover.
- **Why the Round-2 / Round-3 cycle missed it:** Round 2's F22 was
  framed entirely around "both Options held simultaneously." The
  startup-with-key-held case is the same arithmetic mistake from a
  different angle — the toggle is only safe when initial state matches
  reality, and the OS gives no guarantee.
- **Suggested fix:** at `start()` (or first tap event), seed
  `rightOptDown` from the **physical** key state via
  `CGEventSource.keyState(_:.combinedSessionState, key: 61)`. Or:
  treat keycode-61 as a *synchronization* event, deriving the new state
  from the event's `flags & .maskAlternate` *combined with the keycode*
  — but only when we can rule out left-Option held. The simplest robust
  fix is the keyState seed:
  ```swift
  func start() -> Bool {
      ...
      // F22b: seed rightOptDown from physical key state to defend
      // against the "user is already holding Right Option at launch"
      // case. Without this, the first event we see is interpreted as
      // a press, not a release.
      let physicallyDown = CGEventSource.keyState(
          .combinedSessionState, key: 61)
      self.rightOptDown = physicallyDown
      ...
  }
  ```
- **Steering refs:** `swift-macos-best-practices.md` §4 ("keycode is the
  source of truth, not flag bits") — but that rule is not enough on its
  own; you also need an initial-state seed.

#### R4-F32: MINOR — `voice-project.md` state diagram is incomplete vs the implementation

- **Severity:** Minor
- **File:** `.kiro/steering/voice-project.md` LOCKED DECISIONS / state
  machine + `docs/plans/proposed/code/Sources/Voice/AppDelegate.swift`
  (`setError`)
- **Problem:** The diagram shows `error(String)` only as a branch off
  `transcribing`. The implementation calls `setError(...)` from at
  least three other states:
  1. `applicationDidFinishLaunching` on `Transcriber` init failure
     (state = `.idle` → `.error`).
  2. `applicationDidFinishLaunching` on `hotkey.start()` failure
     (state = `.idle` → `.error`).
  3. `handleCommit` on `recorder.start()` failure (state = `.arming` →
     `.error`).
- **Why this matters:** the steering doc says it is the *source of
  truth* and that "anything contradicting this file is a bug or
  requires a deliberate, documented change to this file *first*." The
  current behavior is correct; the documentation is wrong.
- **Suggested fix:** update `voice-project.md` to:
  ```
  any state ──failure──▶ error(String) ──2s──▶ idle
  ```
  …then keep the per-state forward arrows for the happy path.
- **Steering refs:** `voice-project.md` "What to do if a requirement
  changes" §1.

#### R4-F33: MAJOR — under `-strict-concurrency=complete`, 12+ warnings remain; the steering rule's "zero warnings" goal masks them in Swift 5 mode

- **Severity:** Major (degrades to Minor if "Swift 6 in v1.x" is
  explicitly off the roadmap)
- **File:** multiple — see list below.
- **Problem:** the four steering files repeatedly cite Swift 6 strict
  concurrency as the framework against which the design is justified
  (e.g., F7 / F9 / F21 in Round 2). The pre-commit gate is "zero
  warnings under `swift build -c release`." That gate, as currently
  written, is satisfied trivially by Swift 5 mode, which doesn't run
  the analyses Round 2's reasoning depended on. A motivated reviewer
  who turns on `-strict-concurrency=complete` finds:
  ```
  AudioRecorder.swift:137: capture of 'self' with non-Sendable type
                          'AudioRecorder?' in a '@Sendable' closure
  AudioRecorder.swift:137: capture of 'buffer' with non-Sendable type
                          'AVAudioPCMBuffer' in a '@Sendable' closure
                          ← the R4-F29 buffer-lifetime hazard
  AudioRecorder.swift:191: reference to captured var 'supplied' in
                          concurrently-executing code
  AudioRecorder.swift:195: mutation of captured var 'supplied' in
                          concurrently-executing code
  Permissions.swift:42:   reference to var 'kAXTrustedCheckOptionPrompt'
                          is not concurrency-safe …; this is an error in
                          the Swift 6 language mode
  Transcriber.swift:42:   static property 'modelNameRegex' is not
                          concurrency-safe because non-'Sendable' type
                          'Regex<Substring>' may have shared mutable
                          state; this is an error in the Swift 6 language
                          mode
  HotkeyMonitor.swift:89/92/95: cannot access property 'tap' / 'runLoopSrc'
                          / 'refcon' with a non-Sendable type
                          '...?' from nonisolated deinit; this is an
                          error in the Swift 6 language mode
  ```
- **Why this matters:** Round 2 explicitly cited "Swift 6 strict
  concurrency" as the rationale for F7 and F9. Round 3 implemented the
  fixes locally but didn't re-run the analysis to verify the rest of
  the codebase is clean. This is the same "zero warnings doesn't mean
  zero hazards" smell that bit prior projects (the handoff cites
  AudioWhisper, OpenWhispr).
- **Suggested fix (pick one):**
  1. Add `-strict-concurrency=complete` to `Package.swift`'s
     `swiftSettings` and fix the warnings genuinely (this is the
     Sauron-respecting choice — one verification mode, not two).
  2. Or update the steering rule to explicitly say "default Swift 5
     mode is the verification mode; strict-concurrency is out of scope
     for v1" and remove the Swift 6 references from the Round-2
     reasoning — i.e., admit that F7/F9 were over-justified.
  3. Or update `make verify` to invoke
     `swift build -c release -Xswiftc -strict-concurrency=complete`
     and gate on its output. This catches future regressions even if
     the language mode itself stays Swift 5.
- **Steering refs:** `swift-coding-best-practices.md` §8, §15
  (enforcement — "zero warnings"), `voice-project.md` "language" lock.

#### R4-F34: MINOR — `PasteSynthesizer.synthesizeCmdV()` return value is `@discardableResult` but `Paster.paste` discards it

- **Severity:** Minor
- **File:** `docs/plans/proposed/code/Sources/Voice/Paster.swift:72`
  + `Paster.swift:148`
- **Problem:** F11 caught the parallel issue for
  `pasteboard.setString` (`Paster.paste` was discarding the success
  bool and posting Cmd+V anyway). The Round-3 fix gates Cmd+V on the
  setString success bool ✅. But it then calls
  `synthesizer.synthesizeCmdV()` and discards *its* return value, even
  though the synthesizer also returns `Bool`. If both
  `CGEvent(keyboardEventSource:virtualKey:keyDown:true)` and
  `...keyDown:false` fail to construct (essentially impossible on
  macOS 13+, but the contract allows it), `paste(_:then:)` cheerfully
  calls `then()` and returns to `.idle` while the user's clipboard
  was overwritten and nothing was pasted.
- **Suggested fix:** either drop the `@discardableResult` and force
  the caller to handle it, or have `Paster.paste` log + transition to
  `.error("paste failed: could not synthesize Cmd+V")` on `false`.
- **Steering refs:** `swift-macos-best-practices.md` §6,
  `swift-coding-best-practices.md` §6.1 (don't silently discard
  failure paths), `no-orphans-no-dual-paths.md` Rule 2 (the "single
  paste entry point" must report failures all the way out).

#### R4-F35: MINOR — `HotkeyMonitor.deinit` reaches non-Sendable CF properties from a nonisolated deinit; warn under strict concurrency

- **Severity:** Minor
- **File:** `docs/plans/proposed/code/Sources/Voice/HotkeyMonitor.swift:86–98`
- **Problem:** `HotkeyMonitor` is `@MainActor`. Its `deinit` is, by
  language rule, *nonisolated*. `deinit` reads `self.tap`,
  `self.runLoopSrc`, `self.refcon` — all `@MainActor`-isolated stored
  properties of non-Sendable types (`CFMachPort?`, `CFRunLoopSource?`,
  `UnsafeMutableRawPointer?`). Under
  `-strict-concurrency=complete`:
  ```
  warning: cannot access property 'tap' with a non-Sendable type
           'CFMachPort?' from nonisolated deinit; this is an error in
           the Swift 6 language mode
  ```
  (and likewise for the other two). The `@MainActor`-as-singleton
  argument from F12 says these accesses are practically safe, but the
  language-level guarantee is gone in Swift 6.
- **Suggested fix:** in Swift 5/6, call `stop()` from a `Task {
  @MainActor in await self.stop() }` inside `deinit` — or, simpler,
  have `AppDelegate` call `hotkey?.stop()` in
  `applicationWillTerminate(_:)` (which is `@MainActor`-isolated by
  protocol conformance) and have `deinit` do nothing. This makes the
  teardown deterministic and main-actor-safe.
- **Steering refs:** `swift-coding-best-practices.md` §8.2, §8.6.

#### R4-F36: MINOR — `AVAudioConverter` input block captures and mutates `var supplied` across thread boundaries

- **Severity:** Minor
- **File:** `docs/plans/proposed/code/Sources/Voice/AudioRecorder.swift:188–199`
- **Problem:** `let status = converter.convert(to: outBuf, error:
  &convertError) { _, outStatus in ... }` captures a local `var
  supplied = false` and mutates it inside the block. Under
  `-strict-concurrency=complete` Apple's `AVFAudio` is treated as a
  non-`@preconcurrency` import → the input block is `@Sendable` →
  capturing a `var` is a warning. In practice the convert-input block
  is called *synchronously* by the converter, so the mutation is
  thread-safe by accident-of-implementation.
- **Suggested fix:** move `supplied` into a class-scope counter or use
  the converter's documented "EOF" sentinel idiom:
  ```swift
  var input: AVAudioPCMBuffer? = buffer
  let status = converter.convert(to: outBuf, error: &convertError) {
      _, outStatus in
      if let buf = input {
          input = nil
          outStatus.pointee = .haveData
          return buf
      } else {
          outStatus.pointee = .noDataNow
          return nil
      }
  }
  ```
  Same semantics, no captured `var`. (Or wrap `supplied` in a class
  ref-type "Box" if the bool readability matters.)
- **Steering refs:** `swift-coding-best-practices.md` §8 / §13.

#### R4-F37: MINOR — `AppDelegate` logs `String(describing: state)` with `privacy: .public`, and `AppState.error(String)` may carry user-visible content

- **Severity:** Minor
- **File:** `docs/plans/proposed/code/Sources/Voice/AppDelegate.swift:54`
- **Problem:** The `Logger.swift` doc-comment is explicit:
  > **never** log user content with `privacy: .public`
  Today `AppState.error`'s associated string is always developer-controlled
  ("Microphone access denied", "HTTP 500", etc.), so the policy is
  satisfied in practice. But the policy + the implementation are one
  refactor apart from leaking. If somebody adds an error case that
  embeds the transcribed text or a server-supplied message, this log
  line will leak it.
- **Suggested fix:** log only the case name, not the associated value:
  ```swift
  Log.app.log("state -> \(self.state.tag, privacy: .public)")
  ```
  …with `var tag: String { switch self { case .idle: "idle"; ... case
  .error: "error" } }` on `AppState`.
- **Steering refs:** `Logger.swift` doc-comment (Round-3 added it for
  exactly this concern), `swift-coding-best-practices.md` §15.

#### R4-F38: NIT — `MockURLProtocol`'s `nonisolated(unsafe)` static handlers rely on a manual `.serialized` contract

- **Severity:** Nit
- **File:** `docs/plans/proposed/code/Tests/VoiceTests/MockURLProtocol.swift:14–18`
- **Problem:** Round 3 stamped `nonisolated(unsafe)` on the static
  `requestHandler` and `lastRequest` and relies on a doc-comment to
  point future test authors at `@Suite(.serialized)`. A future
  contributor who forgets `.serialized` will silently corrupt their
  own tests with no compiler help. `@TaskLocal` was the alternative
  Round 1 suggested and is the Sauron-clean solution (one knob
  enforced by the type system).
- **Suggested fix:** rewrite using `@TaskLocal`:
  ```swift
  enum MockHandler {
      @TaskLocal static var requestHandler:
          ((URLRequest) throws -> (HTTPURLResponse, Data))?
      @TaskLocal static var lastRequest: URLRequest?
  }
  ```
  …and run tests inside `MockHandler.$requestHandler.withValue { ... }`.
  Eliminates the static-state hazard at the type-system level.
- **Steering refs:** `swift-coding-best-practices.md` §11.3 (test seams
  are protocols / first-class types).

#### R4-F39: NIT — `make verify` greps `^(.*: )?warning:` in a way that misses Swift's `<n> warning generated.` summary line

- **Severity:** Nit
- **File:** `docs/plans/proposed/code/Makefile:38–48`
- **Problem:** The pattern
  `grep -E '^(.*: )?warning:'` matches inline `<file>:<line>: warning:`
  diagnostics (good) but not all warning surfaces. Compiler-driver and
  package-manager warnings can appear with prefixes the regex doesn't
  cover (e.g., `'<target>' has warnings:` from older toolchains, or
  warnings from `Package.swift` itself). The verify target is meant to
  be a paranoid gate; the regex should err toward false positives.
- **Suggested fix:** drop the `^(.*: )?` constraint and just `grep -i
  warning`. Yes, that risks matching content with the literal word
  "warning" in stdout, but `swift build` doesn't emit such content
  unless something *is* warning.
- **Steering refs:** `swift-coding-best-practices.md` §15 (enforcement).

---

### Round-4 §C — What stays Approved from Round 3

The following Round-3 fixes I verified directly and accept as final:

- **F1 + F25 (Sauron-clean mic check):** `Permissions.microphoneStatus()`
  is the only mic-status oracle in the source tree. AudioRecorder
  consults the injected `MicrophoneStatusProviding`. Verified by
  `grep` on `AVCaptureDevice.authorizationStatus` (zero hits outside
  `Permissions.swift`). ✅
- **F3 (`@Suite(.serialized)`):** Confirmed at `TranscriberTests.swift:9`.
  ✅
- **F4 (`Paster` split into `ClipboardWriter` + `PasteSynthesizer` +
  orchestrator):** Verified single public `Paster.paste(_:then:)`
  entry point in production. Tests exercise only the writer + the
  empty-text Paster path. ✅
- **F5 + F15 (HotkeyMonitorTests deletion):** Replaced with a
  placeholder pointing at manual M2. ✅
- **F8 (no IUO):** `private var hotkey: HotkeyMonitor?` confirmed.
  Use sites guard-let. ✅
- **F10 (model-name allow-list):** Validates at `Transcriber.init`,
  throws `.invalidModel`. Tests cover canonical, CRLF, empty/whitespace,
  init-throws. ✅
- **F11 (gate Cmd+V on setString success):** Confirmed at
  `Paster.swift:131–141`. ✅
- **F14 (drop `--deep` in Makefile):** Confirmed. ✅
- **F19 (drop `AVLinearPCMIsNonInterleaved` from settings dict):**
  Confirmed at `AudioRecorder.swift:79–86`. ✅
- **F23 (cancel arming on non-Right-Opt `flagsChanged` during
  qualify window):** Confirmed at `HotkeyMonitor.swift:218–223`. ✅
- **F24 (re-install tap on every start):** Confirmed at
  `AudioRecorder.swift:128`. ✅
- **F27 (Swift `[UInt8]` buffer in `MockURLProtocol`):** Confirmed
  at `MockURLProtocol.swift:46–55`. ✅
- **F28 (tmp paths logged with `privacy: .private`):** Confirmed at
  `AudioRecorder.swift:139`. ✅

---

### Round-4 §D — Annie / Sauron re-check (post-Round-3)

- **Annie (no orphans):** PASS. I walked every `internal`/`private`
  `func`, `enum case`, `struct`, `class`, computed property, and stored
  property in `Sources/Voice/` and confirmed each has at least one call
  site or reference inside `Sources/` or `Tests/`. New symbols
  introduced by Round 3 (`ClipboardWriter`, `PasteSynthesizer`,
  `MicrophoneStatusProviding`, `Permissions.microphoneStatus`,
  `Transcriber.modelNameRegex`, `Transcriber.validate`,
  `AudioRecorder.AudioError.micDenied` / `.micNotDetermined`,
  `VoiceApp`, `make verify`) all have clear callers.

- **Sauron (no dual paths):** PASS in production. Verified by symbol
  search:
  - mic-status: only `Permissions.microphoneStatus()` (no other call
    to `AVCaptureDevice.authorizationStatus`).
  - paste: only `Paster.paste(_:then:)` is the public entry; writer
    and synthesizer are internal collaborators.
  - state: only `AppDelegate.state: AppState`.
  - HTTP: only `Transcriber` + `URLSession`.
  - audio capture: only `AudioRecorder` + `AVAudioEngine`.
  - hotkey: only `HotkeyMonitor` + `CGEventTap`.
  - logging: only `Log.*` (zero `print(` matches).

- **Anti-patterns (`swift-coding-best-practices.md` §14):**
  - `try!` outside test code: 0 ✅
  - `as!` outside test code: 0 ✅
  - Force-unwrap: 1 (`URL(string: "http://linux:8000/...")!` — allowed
    by §5.1 for known-good constants). ✅
  - `class` where `struct` would do: none. All classes own OS
    resources or have identity. ✅
  - Non-`final` classes: none. All 7 classes are `final`. ✅
  - Parallel `Bool` flags instead of an enum state: none. ✅
  - `DispatchSemaphore`: none. ✅
  - `// TODO` / `// FIXME` without an issue number: none. ✅
  - `print(...)` for production logging: 0 ✅
  - IUO in production code: 0 ✅
  - Hand-rolled JSON parsing: none — `Codable` Response struct ✅

- **macOS anti-patterns (`swift-macos-best-practices.md` §9):**
  - `engine.stop() / engine.start()` per recording: PASS — engine
    stays warm. ✅
  - `NSAllowsArbitraryLoads = true`: PASS — exception domain only. ✅
  - Synth Cmd+V with separate Cmd-down/V-down/V-up/Cmd-up: PASS ✅
  - Reading `event.flags` to detect *which* modifier: PASS — the F22
    fix removed this. ✅
  - Ignoring `.tapDisabledByTimeout`: PASS ✅
  - Mutating UI state from non-main thread: PASS for explicit paths.

---

### Round-4 §E — Required actions for v0.1.0 implementation

The original session must, before any code is copied to the live tree:

1. **R4-F29 (Block):** revert the buffer-async pattern in
   `AudioRecorder` to inline-write-on-tap with a small lock around
   the file/converter/outputFormat pointers, **OR** copy the buffer's
   audio bytes into a fresh `AVAudioPCMBuffer` inside the tap callback
   before dispatching the copy. Add a manual integration check that
   compares 16 kHz Int16 byte counts to expected duration to detect
   recycled-buffer corruption.
2. **R4-F30 (Major):** validate `voice.bearerToken` symmetric to
   `voice.modelName`. Add `TranscribeError.invalidBearer`. Add tests.
3. **R4-F31 (Block):** seed `HotkeyMonitor.rightOptDown` from
   `CGEventSource.keyState(.combinedSessionState, key: 61)` at
   `start()` so the toggle survives "user is already holding Right
   Option at app launch."
4. **R4-F32 (Minor):** update `voice-project.md` state diagram so
   `error(String)` can be entered from any state, not just
   `.transcribing`.
5. **R4-F33 (Major):** decide whether v1 targets Swift 6 strict
   concurrency. If yes, fix the 12 warnings before tagging v0.1.0. If
   no, remove the Swift 6 justifications from the Round-2 / Round-3
   reasoning and add a pinned note to `voice-project.md` saying the
   project is Swift 5 mode for the v1.x line.

R4-F34 through R4-F39 are tracked but not blocking. They should appear
in a v0.2.0 issue list rather than be silently dropped.

### Round-4 §F — §C.14 verdicts I concur with from Round 2

I read and concur with Round-2's §C verdicts on §C.14 #1–#5. No
changes:

- **#1 (qualifyMs UserDefault):** Defer to v1.1. Concur.
- **#2 (Sparkle stub):** Reject. Concur — Annie violation.
- **#3 (Bearer token in Keychain):** UserDefaults for v1, with the
  README threat-model paragraph. Concur. (R4-F30 addresses validation,
  not storage.)
- **#4 (sanitize `voice.modelName`):** Yes. Concur. F10 is the answer.
  R4-F30 extends this principle to bearer.
- **#5 (`make verify`):** Yes. Concur — Round 3 implemented it. R4-F39
  refines the regex.

---

### Round-4 §G — Approval signature

The reviewer **approves for v0.1.0 implementation** when **all of**
the Round-1 + Round-2 + Round-4 Block / Major findings have explicit
fixes applied (R4-F29, R4-F30, R4-F31) **or** explicit, written rebuttals
that address the framework-contract / steering-rule citation above.

Until R4-F29 in particular is addressed, the audio path is **not safe
to ship** — silent corruption of recordings under load is a worse
failure mode than the silent-recording bug F1 fixed.
