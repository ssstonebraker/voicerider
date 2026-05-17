---
inclusion: auto
name: no-orphans-no-dual-paths
description: >
  Prevents orphaned code and duplicate code paths. Triggered by: new function,
  new type, new file, refactor, new pipeline path, audio path, transcribe path,
  paste path, hotkey path, feature branch.
---

# No Orphans, No Dual Paths — Mandatory Rules

Ported from `kali-pentest-scripts-tools/.kiro/steering/no-orphans-no-dual-paths.md`
with examples adapted to Swift and this project's domain.

## WHEN THIS APPLIES

Any time new code is added, a function or type is created, or a path through
the app is modified. Especially during refactors that add a "new path"
alongside an existing one.

---

## RULE 1: No Orphaned Code (Annie Rule)

ALL code produced in a branch MUST be reachable from the running application.
Code that exists but has no path to invoke it is an orphan:

- A `func` with no caller in the source tree
- An `enum case` that no `switch` ever produces
- A `Sources/VoiceRider/Foo.swift` file no other file imports a symbol from
- A computed property nobody reads
- A new state in `AppState` that no transition writes
- A new menu item with no action wired up

**If integration cannot happen in the current branch**, the developer MUST:

1. Name the EXACT future task where the code WILL be connected
2. Document it in the plan: `ORPHAN WAIVER: [component] will be integrated in [Task X]`
3. If no future task exists, the code must be removed before merge

**Why:** Two voice-tool predecessors had partial features that everyone
forgot about: AudioWhisper bundled qdrant code that nothing exercised,
Voxtype had a paste path on macOS that compiled but called wl-copy. Code
nobody reaches is code nobody notices when it breaks.

**Gate check:** Before merging any branch, run:

```bash
# every public/internal symbol introduced in this branch
git diff main -- 'Sources/**/*.swift' | grep -E '^\+\s*(func|class|struct|enum|var|let)\s+\w' \
  | awk '{for(i=1;i<=NF;i++) if($i ~ /^[a-zA-Z_]/) {print $(i+1); break}}' \
  | sort -u
```
Verify each name has at least one call site or reference in
`Sources/`. Tests count as call sites if they actually exercise the code.

---

## RULE 2: No Dual Paths (Sauron Rule)

No two functions may answer the same question or perform the same operation
unless one explicitly delegates to the other.

**Applies to:**

- Two ways to record audio (e.g., `AVAudioEngine` tap AND a separate
  `AVAudioRecorder` for "convenience"). Pick one. Route through it.
- Two ways to paste text (e.g., one path that uses `NSPasteboard` + Cmd+V,
  another that types characters via `CGEventCreateKeyboardEvent`). Either
  delete one, or have a single `paste(_:)` that picks internally.
- Two HTTP clients (e.g., `URLSession` here, `NSURLConnection` there).
- Two state stores (e.g., `AppState` enum AND a parallel set of `Bool` flags
  like `isRecording` / `isTranscribing` on the delegate). One source of
  truth.
- Two ways to read the server URL (hardcoded constant in one file,
  `UserDefaults` in another).

**When adding a new path:** The new path and old path MUST share a common
entry point that routes between them. Do NOT create a parallel function
that duplicates logic.

**Pattern:**

```swift
// GOOD: single entry point, routes internally
func paste(_ text: String, then: @escaping () -> Void) {
    if shouldUseTypingFallback() {
        typeCharacters(text, then: then)
    } else {
        pasteboardAndCmdV(text, then: then)
    }
}

// BAD: two separate functions the caller must choose between
func pasteViaPasteboard(_ text: String, then: @escaping () -> Void) { … }
func pasteViaTyping(_ text: String, then: @escaping () -> Void) { … }
```

```swift
// GOOD: single source of truth for state
enum AppState { case idle, arming, recording, transcribing, pasting, error(String) }
var state: AppState { didSet { … } }

// BAD: ad-hoc parallel flags that drift out of sync
var isRecording = false
var isTranscribing = false
var hasError = false
```

**Why:** Hammerspoon, AudioWhisper, OpenWhispr, Voxtype each had multiple
paths to do the same thing (the handoff in `/tmp/voice-tool-handoff.md`
calls them out by name). Each of those projects ships with one path that
works and one that's silently broken. We are not doing that here.

---

## RULE 3: Deferred Integration Requires Explicit Tracking

When any feature or integration step is deferred out of the current branch:

1. The deferral MUST be documented in the plan with: what, why, and where it
   will be done.
2. If the destination is "backlog" or "later" (no specific task), the user
   must confirm TWICE:
   - "Are you sure you want to defer [X]? It was core scope for this work."
   - Only after explicit confirmation may the deferral proceed.

**Why:** The handoff says paste-back is the only piece nobody got working.
That's because every prior implementation deferred it and never came back.
We do not defer paste-back.

---

## ENFORCEMENT

These rules are checked at two points:

1. **Before merge:** Verify no orphans (Rule 1 grep above) and no dual paths
   (manual review of new entry points — does this duplicate `paste`,
   `record`, `transcribe`, or state tracking?).
2. **During code review:** The reviewer must ask:
   - "Is there any new code with no caller?"
   - "Are there two ways to perform the same operation?"
   - "Is there more than one source of truth for any piece of state?"
