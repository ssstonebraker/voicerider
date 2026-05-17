# Voice Implementation Plan — Final, Research-Backed

**Date:** 2026-05-17
**Supersedes:** the Round-1 / Round-2 / Round-3 cycle in
`docs/plans/handoff-for-review.md`. Round-4 findings R4-F29 through
R4-F39 are the live punch-list. This document is the resolution.

---

## 1. Decisions, justified

### D1 — Audio capture: inline conversion + write on the audio render thread.

The Round-3 design dispatched each tap-callback `AVAudioPCMBuffer` to
`writeQueue.async`. Research confirms this is unsafe:

- **Apple's own engineer (forums/thread/763362, Sep 2024)** answers a
  related question with example code that does inline conversion +
  output-stream writes *inside* the tap callback. No dispatch to another
  queue.
- **SO/27343266 commenter "Learn OpenGL ES"** (Jan 2018) explicitly
  warns: *"This is not safe under some circumstances; i.e. if writing
  the data to a file in a dispatch queue. If there is a delay for some
  reason, the next call to installTap will have a different buffer
  object, but the remaining samples will not be there so they will be
  lost."*
- **hotpaw2 (Core Audio expert, SO/69761269):** *"My rule inside audio
  callback functions, blocks, or taps to always immediately copy any
  data to be processed out of the PCM buffers... because the underlying
  PCM buffers might be being updated in a separate RemoteIO Audio Unit
  thread running inside a hard real-time (Mach kernel) context."*
- **`-strict-concurrency=complete` agrees:** the Round-3 code emits
  `[#SendableClosureCaptures]` for the buffer capture in
  `writeQueue.async`.

The fix: convert + write *inside* the tap callback on the audio thread.
Synchronize only the file/converter/outputFormat pointer reads/writes
between `start()` / `stop()` (main thread) and the tap (audio thread)
with an `os_unfair_lock`. The lock holds for nanoseconds — RT-safe.

About `AVAudioFile.write(from:)` thread safety: Apple does **not**
formally document this as safe on the render thread, but their own
forum example writes inline. We adopt the same pattern and document it
as an assumption.

### D2 — Hotkey startup state: seed `rightOptDown` from `CGEventSource.keyState`.

Round-3's keycode-61 toggle has a startup-state inversion bug: if the
user is holding Right Option when `applicationDidFinishLaunching` runs,
the first event we see is the *release*, which the toggle reads as
"now down" → arm → 200ms later commit recording.

Research:
- **chipjarred's gist (14 stars, GitHub)** uses exactly
  `CGEventSource.keyState(.combinedSessionState, key: self)` to query
  whether any keycode is physically pressed — including modifier keys.
- **Apple docs:** `CGEventSource.keyState(_:key:)` available since
  macOS 10.4. Returns the *combined session state* — exactly what we
  want.

Fix: at the top of `HotkeyMonitor.start()` (after the tap is
successfully installed), seed `rightOptDown =
CGEventSource.keyState(.combinedSessionState, key: 61)`.

### D3 — Bearer token validation: allow-list at `Transcriber.init`.

Round-3's F10 fix sanitized `voice.modelName` against multipart-body
injection. The exact same risk applies to `voice.bearerToken`:
`setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")` is
header injection if the value contains CRLF. URLRequest does not
guarantee validation. Symmetric fix:

```swift
static let bearerTokenRegex = #/^[A-Za-z0-9._~+/=-]{1,512}$/#
static func validate(bearerToken: String) throws { ... }
```

Throw `TranscribeError.invalidBearer` at `Transcriber.init`, surface
as `setError("config: invalid bearer token: \(value)")` from
AppDelegate.

### D4 — Concurrency mode: Swift 5 default for v1.x.

`-strict-concurrency=complete` reveals 12+ warnings (most are Apple
framework imports lacking `@preconcurrency` annotations). Even Apple's
own forum thread on AVAudioEngine thread safety (forums/thread/123540)
has no authoritative answer from Apple after 5 years. Fixing all 12 for
v0.1.0 is high churn for marginal benefit.

Decision: Swift 5 default for v1.x. We add `make verify-strict` as an
opt-in CI check that runs `swift build -c release -Xswiftc
-strict-concurrency=complete` and reports warnings. The `make verify`
gate still requires zero warnings under default mode. Strict mode goes
into the v0.2.0 issue list with R4-F33.

Update `voice-project.md`: add the Swift 5 mode decision. Remove the
"Swift 6 strict concurrency" justifications from review notes (they were
the right thing to think about but the wrong thing to gate v0.1.0 on).

### D5 — State machine doc: `error(String)` reachable from any state.

`voice-project.md`'s diagram shows `error(String)` only as a branch off
`.transcribing`. The implementation calls `setError(...)` from `.idle`
(transcriber init failure, hotkey install failure) and `.arming`
(recorder start failure). Update the diagram:

```
Any state ──failure──▶ error(String) ──2s──▶ idle
```

Keep the per-state forward arrows for the happy path.

### D6 — ATS `linux` exception domain: keep as-is for v0.1.0.

The user has presumably been using the existing `linux` `/etc/hosts`
alias. Apple's DTS engineer (forums/thread/747421) confirms
`NSExceptionDomains` is the right mechanism for HTTP via URLSession.
Single-label hostnames may fail in some setups; if so, the documented
fallback is the IP address with CIDR notation in `NSExceptionDomains`.

No code change for v0.1.0. Add a README troubleshooting note: *"if you
get `NSURLErrorAppTransportSecurityRequiresSecureConnection`, edit
`Resources/Info.plist` to use the IP address of your LAN server with
`/32` CIDR notation."*

---

## 2. Block / Major findings — disposition

| Finding | Severity | Action |
|---------|---------:|--------|
| R4-F29 audio buffer lifetime | Block | **D1: revert writeQueue.async, use os_unfair_lock + inline write.** |
| R4-F31 hotkey startup-state inversion | Block | **D2: seed rightOptDown from `CGEventSource.keyState`.** |
| R4-F30 bearer token unvalidated | Major | **D3: validate at `Transcriber.init`.** |
| R4-F33 strict concurrency 12 warnings | Major | **D4: Swift 5 mode for v1.x, `make verify-strict` opt-in.** |
| R4-F32 state diagram incomplete | Minor | **D5: update voice-project.md.** |
| R4-F35 deinit isolation | Minor | Resolved by D4 (Swift 5 mode). Tracked for v0.2. |
| R4-F34 synthesizeCmdV return discarded | Minor | Tracked for v0.2 issue list. |
| R4-F36 `var supplied` capture | Minor | Tracked for v0.2 issue list. |
| R4-F37 state-log privacy | Minor | Tracked for v0.2 issue list. |
| R4-F38 `nonisolated(unsafe)` test seam | Nit | Tracked for v0.2 issue list. |
| R4-F39 `make verify` regex | Nit | Tracked for v0.2 issue list. |

---

## 3. File-by-file changes from current `docs/plans/proposed/code/`

### 3.1 `Sources/Voice/AudioRecorder.swift` — full rewrite of the locking model

**Before (Round 3):** writeQueue serializes both pointer mutations *and*
buffer writes; tap callback dispatches to writeQueue.async.

**After (Round 5):** `os_unfair_lock` protects only the pointer
reads/writes; tap callback writes inline on the audio thread.

```swift
import AVFoundation
import os.lock

final class AudioRecorder {

    enum AudioError: Error, LocalizedError, Sendable { /* unchanged */ }

    private let mic: MicrophoneStatusProviding
    private let engine = AVAudioEngine()

    // F2 / F21 / R4-F29 fix: inline write on the audio thread; the
    // lock guards ONLY the pointer mutations done by start()/stop()
    // versus the pointer reads done by the tap callback. Hold time is
    // nanoseconds, so it's safe in a real-time context.
    private var lock = os_unfair_lock()
    private var file: AVAudioFile?
    private var converter: AVAudioConverter?
    private var outputFormat: AVAudioFormat?

    init(mic: MicrophoneStatusProviding) { self.mic = mic }

    func start() throws -> URL {
        switch mic.microphoneStatus() {
        case .authorized:        break
        case .denied, .restricted:  throw AudioError.micDenied
        case .notDetermined:     throw AudioError.micNotDetermined
        @unknown default:        throw AudioError.micDenied
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice-\(UUID().uuidString).wav")

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)

        guard let outFmt = AVAudioFormat(
            commonFormat: .pcmFormatInt16, sampleRate: 16_000,
            channels: 1, interleaved: true)
        else { throw AudioError.converterUnavailable }

        guard let conv = AVAudioConverter(from: inputFormat, to: outFmt)
        else { throw AudioError.converterUnavailable }

        let settings: [String: Any] = [
            AVFormatIDKey:             kAudioFormatLinearPCM,
            AVSampleRateKey:           16_000,
            AVNumberOfChannelsKey:     1,
            AVLinearPCMBitDepthKey:    16,
            AVLinearPCMIsFloatKey:     false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let newFile: AVAudioFile
        do {
            newFile = try AVAudioFile(
                forWriting: url, settings: settings,
                commonFormat: .pcmFormatInt16, interleaved: true)
        } catch {
            throw AudioError.fileCreateFailed(message: error.localizedDescription)
        }

        os_unfair_lock_lock(&lock)
        self.file = newFile
        self.converter = conv
        self.outputFormat = outFmt
        os_unfair_lock_unlock(&lock)

        // R4-F24: re-install tap on every start. Format passed is `nil`
        // — the OS gives us hardware native; the converter handles the rest.
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, _ in
            // R4-F29: stay on the audio thread. Convert + write inline.
            // The buffer is only valid for the duration of this closure.
            self?.writeOnAudioThread(buffer: buffer)
        }

        if !engine.isRunning {
            do { try engine.start() }
            catch { throw AudioError.engineStartFailed(message: error.localizedDescription) }
        }

        Log.audio.log("recording start path=\(url.path, privacy: .private)")
        return url
    }

    /// Stops writing. Removes the tap, then takes the lock so any
    /// currently-executing tap-callback has finished its write before
    /// we clear the pointers. After this returns, the WAV header has
    /// been finalised on disk.
    func stop() {
        engine.inputNode.removeTap(onBus: 0)
        // After removeTap, no NEW callbacks will fire. A callback already
        // executing will finish, releasing the lock; we then acquire it
        // and clear the pointers. AVAudioFile's deinit (called when
        // `newFile` strong reference goes away below) flushes the RIFF
        // chunk-size header.
        os_unfair_lock_lock(&lock)
        file = nil
        converter = nil
        outputFormat = nil
        os_unfair_lock_unlock(&lock)
        Log.audio.log("recording stop")
    }

    /// Audio render thread. Read the pointers under the lock, then
    /// release the lock and convert+write. Holding the lock during the
    /// write would defeat its RT-safety; we take a strong reference and
    /// release.
    private func writeOnAudioThread(buffer: AVAudioPCMBuffer) {
        os_unfair_lock_lock(&lock)
        guard let file = self.file,
              let converter = self.converter,
              let outputFormat = self.outputFormat else {
            os_unfair_lock_unlock(&lock)
            return
        }
        os_unfair_lock_unlock(&lock)

        let ratio = outputFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let outBuf = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity)
        else { return }

        // R4-F36: avoid the `var supplied` Sendable issue by closing
        // over an Optional buffer that we nil out after the first use.
        var input: AVAudioPCMBuffer? = buffer
        var convertError: NSError?
        let status = converter.convert(to: outBuf, error: &convertError) { _, outStatus in
            if let buf = input {
                input = nil
                outStatus.pointee = .haveData
                return buf
            }
            outStatus.pointee = .noDataNow
            return nil
        }

        switch status {
        case .haveData, .inputRanDry:
            do { try file.write(from: outBuf) }
            catch { Log.audio.error("file write failed: \(error.localizedDescription, privacy: .public)") }
        case .error:
            if let e = convertError { Log.audio.error("converter error: \(e.localizedDescription, privacy: .public)") }
        case .endOfStream: break
        @unknown default: break
        }
    }
}
```

**Why this is safe:**

- `start()` acquires the lock, sets the pointers, releases. Any tap
  callback that runs after this sees the new pointers atomically.
- The tap callback acquires the lock, copies the pointer values, releases
  before doing the actual work. Lock hold time is two memory loads.
- `stop()` calls `removeTap` first, which means no new callbacks. An
  already-running callback is doing its write *with its own strong
  reference* to `file` (captured under the lock); that reference keeps
  the file alive past `stop()`'s pointer-clear.
- `stop()` then acquires the lock. If a callback is in its
  acquire-pointers phase, `stop()` waits microseconds. If a callback is
  in its convert+write phase, it doesn't hold the lock — `stop()` runs
  immediately, sets the pointers to nil, releases. The callback's
  in-flight write is operating on the strong reference it already took;
  it completes safely. After both have run, ARC releases the file →
  `AVAudioFile.deinit` flushes the RIFF chunk-size header.

### 3.2 `Sources/Voice/HotkeyMonitor.swift` — seed `rightOptDown` at start

Add to `start()` after the tap is installed and `runLoopSrc` is added:

```swift
// R4-F31: seed the toggle from the physical key state. Defends
// against "user is holding Right Option when applicationDidFinishLaunching
// fires"; without this, the first event we see is interpreted as a
// press, not a release, and we record from app launch.
self.rightOptDown = CGEventSource.keyState(.combinedSessionState, key: 61)
Log.hotkey.log("seeded rightOptDown=\(self.rightOptDown, privacy: .public)")
```

No other changes to `HotkeyMonitor`.

### 3.3 `Sources/Voice/Transcriber.swift` — bearer token allow-list

Add alongside the existing modelName regex:

```swift
/// Bearer-token allow-list. Conservative regex: alphanumerics plus
/// the characters RFC 6750 token68 allows, length 1–512. Categorically
/// rejects whitespace and CRLF.
static let bearerTokenRegex = #/^[A-Za-z0-9._~+/=-]{1,512}$/#

static func validate(bearerToken token: String) throws {
    guard (try? bearerTokenRegex.wholeMatch(in: token)) != nil else {
        throw TranscribeError.invalidBearer(value: token)
    }
}
```

Add to `TranscribeError`:

```swift
case invalidBearer(value: String)
```

Add to `errorDescription`:

```swift
case .invalidBearer(let v): return "invalid bearer token: \(v)"
```

Call from `init`, after the modelName check:

```swift
init(endpoint: URL, model: String, bearer: String,
     session: URLSession = .shared, timeout: TimeInterval = 15) throws {
    try Self.validate(modelName: model)
    try Self.validate(bearerToken: bearer)   // R4-F30
    // ... rest unchanged
}
```

### 3.4 `Tests/VoiceTests/TranscriberTests.swift` — bearer-token tests

Add 4 tests symmetric to the model-name tests:

```swift
@Test("bearer token allow-list accepts canonical defaults")
func bearerTokenAccepts() throws {
    try Transcriber.validate(bearerToken: "local-no-auth")
    try Transcriber.validate(bearerToken: "sk-abc123_xyz.456")
    try Transcriber.validate(bearerToken: "AbCdEfGh+/=") // base64-ish
}

@Test("bearer token allow-list rejects CRLF injection")
func bearerTokenRejectsCRLF() {
    let injected = "tok\r\nX-Forwarded-User: admin"
    do {
        try Transcriber.validate(bearerToken: injected)
        Issue.record("should have thrown invalidBearer")
    } catch let Transcriber.TranscribeError.invalidBearer(value) {
        #expect(value == injected)
    } catch { Issue.record("wrong error: \(error)") }
}

@Test("bearer token allow-list rejects empty and whitespace")
func bearerTokenRejectsEmpty() {
    for bad in ["", " ", "  ", "tok with spaces"] {
        do {
            try Transcriber.validate(bearerToken: bad)
            Issue.record("expected reject for \(bad.debugDescription)")
        } catch is Transcriber.TranscribeError { /* ok */ }
        catch { Issue.record("wrong error: \(error)") }
    }
}

@Test("Transcriber.init throws on bad bearer")
func initThrowsOnBadBearer() {
    do {
        _ = try Transcriber(endpoint: Self.endpoint,
                            model: "canary-qwen-2.5b",
                            bearer: "bad bearer")
        Issue.record("expected throw")
    } catch is Transcriber.TranscribeError { /* ok */ }
    catch { Issue.record("wrong error: \(error)") }
}
```

### 3.5 `Sources/Voice/AppDelegate.swift` — surface invalid bearer

The existing error path already catches `TranscribeError`:

```swift
do {
    transcriber = try Transcriber(...)
} catch {
    setError("config: \(error.localizedDescription)")
    return
}
```

…so `.invalidBearer` flows through automatically. No code change. Just
verify the error message is user-friendly: it'll read *"config: invalid
bearer token: ..."*. Good.

### 3.6 `Makefile` — add `verify-strict`

```makefile
# Optional CI knob: build with strict concurrency on. Tracked under
# R4-F33 for v0.2; not gating v0.1.0.
verify-strict:
	swift build -c release -Xswiftc -strict-concurrency=complete
```

### 3.7 `.kiro/steering/voice-project.md` — fix state diagram and language pin

Replace the state-machine block:

```
idle → arming → recording → transcribing → pasting → idle
            ↘ idle (cancelled)

Any state ──failure──▶ error(String) ──2s──▶ idle
```

Add to "Language & build":

```
- **Concurrency mode:** Swift 5 default for v1.x. The `swift build`
  gate is "zero warnings under default mode." `make verify-strict`
  runs `-strict-concurrency=complete` and is informational, not gating,
  for v1.x. Strict-concurrency adoption tracked under R4-F33 for v0.2.
```

### 3.8 `README.md` — bearer-token note + ATS troubleshooting

Add to the "Bearer token storage" section:

```
The token is also validated against `^[A-Za-z0-9._~+/=-]{1,512}$` at
launch. CRLF, whitespace, and other characters are rejected.
```

Add a new troubleshooting section:

```
## Troubleshooting

### `App Transport Security policy requires the use of a secure connection`
You changed the server hostname in `voice.serverURL` but the
`NSExceptionDomains` entry in `Resources/Info.plist` still names
`linux`. Edit the plist to match, **or** use the server's IP address
with CIDR `/32` notation:

```xml
<key>NSExceptionDomains</key>
<dict>
    <key>192.168.1.42/32</key>
    <dict>
        <key>NSExceptionAllowsInsecureHTTPLoads</key><true/>
    </dict>
</dict>
```
```

---

## 4. Verification gate

Before copying anything from `docs/plans/proposed/code/` into the live
tree (root `Sources/`, `Tests/`, `Makefile`, etc.), all of these must
succeed in `docs/plans/proposed/code/`:

```bash
# 1. Zero warnings, default Swift 5 mode.
rm -rf .build
swift build -c release 2>&1 | tee /tmp/voice-build.log
! grep -iE 'warning|error' /tmp/voice-build.log

# 2. All tests pass without the audio integration env var.
VOICE_RUN_AUDIO_TESTS=0 swift test
# Expected: 28 tests in 6 suites pass (24 from Round 3 + 4 new bearer tests).

# 3. make verify is green.
make clean && make verify

# 4. Optional: strict-concurrency report.
make verify-strict   # not gating for v0.1.0
```

After verification, copy:

```
docs/plans/proposed/code/Package.swift                       → Package.swift
docs/plans/proposed/code/Makefile                            → Makefile
docs/plans/proposed/code/README.md                           → README.md
docs/plans/proposed/code/Resources/Info.plist                → Resources/Info.plist
docs/plans/proposed/code/Sources/Voice/*.swift               → Sources/Voice/*.swift
docs/plans/proposed/code/Tests/VoiceTests/*.swift            → Tests/VoiceTests/*.swift
```

Then run the manual integration checklist M1–M13 from
`docs/plans/proposed/tests/manual-integration-checklist.md`.

If M1–M13 all pass on a real Mac, tag `v0.1.0`.

---

## 5. What's deferred to v0.2.0

Tracked, **not** silently dropped:

- **R4-F33** (Swift 6 strict concurrency adoption — full fix of the 12
  warnings).
- **R4-F34** (`PasteSynthesizer.synthesizeCmdV()` return value handling).
- **R4-F35** (`HotkeyMonitor.deinit` isolation under strict mode).
- **R4-F36** (`var supplied` capture in converter input block —
  partially mitigated in this plan via the `Optional<buffer>` rewrite,
  but still warns under strict mode).
- **R4-F37** (state-log privacy hardening).
- **R4-F38** (`MockURLProtocol` `@TaskLocal` migration).
- **R4-F39** (`make verify` regex strengthening).
- **F13** (arming-icon flicker — by-design UX).
- **F17** (error-window restart on chained errors — by-design UX).
- **§C.14 #1** (qualification-window UserDefault).
- **§C.14 #3** (Keychain bearer-token storage).

---

## 6. Open question (none)

None. Implementation can start.
