---
inclusion: auto
name: swift-coding-best-practices
description: >
  Swift language coding standards. Triggered by any *.swift file change,
  Package.swift, type design, naming, error handling, concurrency, generics,
  protocols, optionals, memory management, access control, testing.
---

# Swift Coding Best Practices

Pure language rules — independent of which Apple framework you happen to
be calling. macOS-API-specific rules live in `swift-macos-best-practices.md`.

Primary source: [Swift API Design Guidelines](https://www.swift.org/documentation/api-design-guidelines/).
Secondary sources cited inline.

---

## 1. NAMING

### 1.1 Clarity beats brevity

Reading a name should make the intent obvious without consulting the
declaration. The Swift team explicitly rejects "smallest possible code"
as a goal.

```swift
// BAD — what does `at` mean? Position? Element to find?
employees.remove(x)

// GOOD — the role of x is unambiguous
employees.remove(at: x)
```

### 1.2 Omit needless words

A word that merely repeats type information adds noise.

```swift
// BAD
allViews.removeElement(cancelButton)
// GOOD
allViews.remove(cancelButton)
```

### 1.3 Name parameters and variables by their role, not their type

```swift
// BAD
var string = "Hello"
class Pipeline { func restock(from widgetFactory: WidgetFactory) }

// GOOD
var greeting = "Hello"
class Pipeline { func restock(from supplier: WidgetFactory) }
```

### 1.4 Compensate for weakly-typed parameters with role-naming nouns

If the parameter is `String`, `Int`, `Any`, or any framework type that
appears in many roles, prefix the argument label with a role noun.

```swift
// BAD
grid.add(self, for: graphics)
// GOOD
grid.addObserver(self, forKeyPath: graphics)
```

### 1.5 Strive for fluent usage

The call site should read like an English phrase.

```swift
x.insert(y, at: z)            // "x, insert y at z"
x.subviews(havingColor: y)    // "x's subviews having color y"
x.capitalizingNouns()         // "x, capitalizing nouns"
```

### 1.6 Side-effect convention

- Methods *with* side effects read as imperative verbs:
  `print(x)`, `recorder.start()`, `paster.paste(text)`.
- Methods *without* side effects read as noun phrases:
  `array.distance(to: y)`, `iterator.successor()`.
- Mutating/non-mutating pairs: the mutating verb is imperative
  (`array.sort()`); the non-mutating returns the result and uses the
  past participle or `-ing` form (`array.sorted()`).

### 1.7 Avoid abbreviations

The intended meaning of any abbreviation you use should be findable in
one web search. `URL`, `HTTP`, `PCM`, `WAV` are fine — `freq`, `cfg`,
`mgr` are not.

### 1.8 Booleans read as assertions

```swift
// BAD
if recorder.recording { … }
// GOOD
if recorder.isRecording { … }
```

### 1.9 Case conventions

- Types and protocols: `UpperCamelCase`.
- Everything else (vars, funcs, cases, properties): `lowerCamelCase`.
- Acronyms that are conventionally uppercase in English are uniformly
  cased: `utf8Bytes`, `userSMTPServer`, `isASCII`.
- Other acronyms become words: `radarDetector`, not `RADARDetector`.

### 1.10 Prefer methods/properties to free functions

Free functions are reserved for:
1. No obvious receiver: `min(x, y, z)`.
2. Unconstrained generics: `print(x)`.
3. Established notation: `sin(x)`.

---

## 2. ARGUMENT LABELS

### 2.1 First-argument labels follow grammar

If the first argument forms part of a prepositional phrase, label it at
the preposition:

```swift
x.removeBoxes(havingLength: 12)
view.dismiss(animated: false)
```

If the first argument is part of a continuous noun phrase with the base
name, omit its label and append the words to the base name:

```swift
view.addSubview(other)        // not view.add(subview: other)
```

### 2.2 Value-preserving conversions skip the first label

```swift
String(veryLargeNumber)
String(veryLargeNumber, radix: 16)
Int64(someUInt32)
```

Narrowing conversions take a descriptive label:

```swift
UInt32(truncating: source)
UInt32(saturating: valueToApproximate)
```

### 2.3 Default arguments beat overload families

A single function with sensible defaults is easier to learn than five
similar overloads:

```swift
// GOOD
func compare(_ other: String,
             options: CompareOptions = [],
             range: Range<Index>? = nil,
             locale: Locale? = nil) -> Ordering
```

Place defaulted parameters at the end of the list.

---

## 3. DOCUMENTATION COMMENTS

Write a `///` doc comment for every type and every public/internal
method. The act of writing it is a design check: if you can't summarize
in one sentence, the API may be wrong.

```swift
/// Posts the given text to the focused application by writing it to
/// the general pasteboard and synthesizing Cmd+V.
///
/// The current pasteboard contents (`.string` only) are restored 600 ms
/// after the paste event is posted.
///
/// - Parameters:
///   - text: The text to paste. Empty strings are ignored.
///   - then: Called on the main thread once the restore completes.
func paste(_ text: String, then: @escaping () -> Void)
```

Recognized markup: `- Parameter`, `- Parameters:`, `- Returns:`,
`- Throws:`, `- Note:`, `- Warning:`, `- Precondition:`, `- Complexity:`.

Document the complexity of any computed property that isn't O(1).

---

## 4. TYPE DESIGN — VALUE FIRST

Sources: Apple [Value and Reference Types](https://www.swift.org/documentation/articles/value-and-reference-types.html).

### 4.1 Default to `struct` and `enum`

Reach for value types unless you have a concrete reason not to. Value
types:
- have value semantics (assignment copies)
- can't form retain cycles
- compose cleanly with `Codable`, `Equatable`, `Hashable`
- avoid ARC overhead

### 4.2 Use `class` for identity, not for "convenience"

You need a class when:
- The thing has identity that must be shared (e.g., `AppDelegate`,
  long-lived service objects, owners of OS resources like
  `AVAudioEngine`).
- It must conform to an Objective-C protocol or be subclassable by
  AppKit (`NSObject` subclasses).
- You need deterministic deinitialization (`deinit`).

### 4.3 Always mark classes `final` unless you intend subclassing

```swift
final class Transcriber { … }
```

This enables compiler de-virtualization, prevents accidental
inheritance, and signals intent.

### 4.4 Use `enum` for state machines

Don't model state with parallel `Bool` flags. One enum, exhaustive
switch.

```swift
enum State { case idle, recording, transcribing, error(String) }
```

### 4.5 `actor` for shared mutable state across concurrency domains

When something must be mutated from multiple async contexts, use an
`actor`:

```swift
actor RequestQueue { … }
```

For UI-bound state, use `@MainActor` instead of an actor.

---

## 5. OPTIONALS

### 5.1 Force-unwrap (`!`) is banned in production paths

The only acceptable force-unwraps are:
- Initializing a known-good constant: `URL(string: "http://linux:8000")!`
- Inside test code, where a failure is the test result.

In all other cases use `guard let`, `if let`, or `??`.

```swift
// BAD
let count = items.count!

// GOOD
guard let items else { return }
let count = items.count
```

### 5.2 Implicitly unwrapped optionals (`String!`)

Restrict to:
- Properties that are `nil` between `init` and a guaranteed setup call
  (e.g., `@IBOutlet`, `awakeFromNib` patterns). Even there, prefer
  proper `Optional<T>` and unwrap at use.
- Bridged Objective-C APIs.

### 5.3 `try!`, `as!`, `unsafeBitCast`

Banned outside test code. Use `do/catch`, `as?`, or proper
`withMemoryRebound` patterns.

### 5.4 Optional chaining over nesting

```swift
// BAD
if let a = obj.a { if let b = a.b { if let c = b.c { use(c) } } }

// GOOD
if let c = obj.a?.b?.c { use(c) }
```

---

## 6. ERROR HANDLING

Sources: SE-0413 (typed throws), [donnywals.com](https://www.donnywals.com/designing-apis-with-typed-throws-in-swift/).

### 6.1 Make failure paths visible — `throws` over silent failure

Functions that can fail should throw, not return `nil` for "error" and
"empty" indistinguishably.

### 6.2 Define a domain `Error` enum per subsystem

```swift
enum TranscribeError: Error {
    case requestFailed(underlying: Error)
    case http(status: Int)
    case decode(underlying: Error)
    case empty
}
```

Make it `LocalizedError` to drive user-visible messages:

```swift
extension TranscribeError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .http(let s):    return "Server returned HTTP \(s)"
        case .empty:          return "Server returned no text"
        case .requestFailed:  return "Could not reach server"
        case .decode:         return "Server response was not JSON"
        }
    }
}
```

### 6.3 Typed throws (Swift 6+) where the set of errors is closed

```swift
func transcribe(wav: URL) async throws(TranscribeError) -> String { … }
```

Use untyped `throws` when callers genuinely need to bubble arbitrary
errors (most app-level code).

### 6.4 `Result` for legacy completion-handler boundaries

When you must use a completion-handler API (e.g., a C callback can't
be `async`), surface the result as `Result<Success, Error>`:

```swift
func transcribe(wav: URL,
                completion: @escaping (Result<String, Error>) -> Void)
```

### 6.5 Never use `try?` to silently discard errors

Acceptable:
```swift
// User has been informed elsewhere; we just want to skip on failure.
guard let text = try? decoder.decode(R.self, from: data) else {
    state = .error("decode failed"); return
}
```

Not acceptable:
```swift
try? doImportantWork()    // error vanishes, no log, no state change
```

### 6.6 `do/catch` reflects intent

Catch the specific cases you handle differently. Re-throw or surface a
user-visible message for the rest:

```swift
do {
    try perform()
} catch TranscribeError.http(let status) where status >= 500 {
    state = .error("Server unhealthy")
} catch {
    state = .error(error.localizedDescription)
}
```

---

## 7. PROTOCOLS & GENERICS

### 7.1 Use protocols to model capability, not inheritance

```swift
protocol AudioCapturing {
    func start() throws -> URL
    func stop()
}
```

The implementer is whatever conforms — `AVAudioEngine`-backed real
recorder, or an in-memory test fake.

### 7.2 Prefer protocol composition over inheritance hierarchies

`func handle(_ x: Recordable & Identifiable)` beats a deep type tree.

### 7.3 Generics: constrain at the call site, not at the type

```swift
// BAD — every Container instance commits to one element type forever
struct Container<T: Codable & Equatable> { … }

// GOOD — the operation is generic, the storage is concrete
struct Container { … }
extension Container {
    func encoded<T: Codable>(_ x: T) throws -> Data { … }
}
```

### 7.4 Use `some` for opaque return types when the concrete type is
implementation detail

```swift
func makeRecorder() -> some AudioCapturing { … }
```

### 7.5 Use `any` for existentials only when you need heterogeneity

In Swift 5.7+ existentials are spelled `any Protocol`. Most uses of
`any` should actually be generics with `some Protocol`.

---

## 8. CONCURRENCY

Sources: Apple WWDC sessions on Swift Concurrency,
[hackingwithswift.com](https://www.hackingwithswift.com/swift/6.0/concurrency).

### 8.1 New code uses `async`/`await`

Default to structured concurrency. Reserve `DispatchQueue` for:
- Bridging from C-style callbacks (e.g., a `CGEventTap` callback that
  must hop to main).
- Calling legacy URLSession completion-handler APIs that would require
  an `async` wrapper for marginal benefit.

### 8.2 Mark UI-touching types `@MainActor`

```swift
@MainActor
final class StatusItemController { … }
```

The compiler will then flag any cross-actor mutation.

### 8.3 `Sendable` correctness

Types passed across async boundaries must be `Sendable`. Value types
of `Sendable` members are automatically `Sendable`. For `final class`
with only immutable stored properties, declare conformance explicitly:

```swift
final class Config: Sendable {
    let endpoint: URL
    let model: String
    init(endpoint: URL, model: String) { … }
}
```

### 8.4 Do not bridge async to sync with `DispatchSemaphore`

It deadlocks under cooperative scheduling. If an interface forces sync,
spawn a `Task { await … }` and capture the result there.

### 8.5 Cancellation

Long-running async work checks `Task.checkCancellation()` at logical
yield points. Network requests inherit cancellation through
`URLSession.data(for:)`.

### 8.6 Don't capture non-`Sendable` state in detached tasks

```swift
// BAD
Task.detached { self.state = .idle }   // self is main-isolated

// GOOD
Task { @MainActor in self.state = .idle }
```

---

## 9. MEMORY & CAPTURE LISTS

Sources: [donnywals.com](https://dev.to/donnywals/when-to-use-weak-self-and-why-32p3),
[medium flawless-app](https://medium.com/flawless-app-stories/you-dont-always-need-weak-self-a778bec505ef).

### 9.1 Escaping closures stored on `self`: `[weak self]` mandatory

```swift
class Recorder {
    var onComplete: (() -> Void)?
    func setup() {
        onComplete = { [weak self] in
            guard let self else { return }
            self.cleanup()
        }
    }
}
```

Without `[weak self]`, the closure retains `self`, `self` retains the
closure, and neither deallocates.

### 9.2 Non-escaping closures (most `map`, `filter`, `forEach`, `do/catch`):
no capture list needed

The closure doesn't outlive the call.

### 9.3 One-shot `URLSession.dataTask` completion: `[weak self]` is
recommended

The task may outlive the owner. If `self` deallocating mid-request is
a normal outcome, `[weak self]` keeps the bookkeeping clean. If the
work must complete and update some state, capture explicitly with
`[strong-but-bounded]` semantics — i.e., don't capture `self`, capture
the specific objects you need:

```swift
URLSession.shared.dataTask(with: req) { [stateMachine] data, _, _ in
    stateMachine.received(data)
}
```

### 9.4 `[unowned self]` only when self lifetime is provably ≥ closure
lifetime

Rare in practice. Crashes if violated. Default to `[weak self]`.

### 9.5 Structs do not need capture lists for `self`

`self` is copied by value into the closure.

---

## 10. ACCESS CONTROL

| Level | Scope |
|-------|-------|
| `private` | Enclosing declaration + extensions in the same file |
| `fileprivate` | Entire defining file |
| `internal` (default) | The whole module |
| `public` | Other modules can use it, not subclass/override |
| `open` | Other modules can subclass / override |

### 10.1 Default to the most restrictive level that compiles

Start with `private`. Promote only when a real call site outside the
type needs it. This makes the public surface obvious.

### 10.2 Use `fileprivate` when extensions in the same file need access

```swift
// File: AppDelegate.swift
final class AppDelegate {
    fileprivate var state: AppState = .idle
}
extension AppDelegate {
    func transition(to next: AppState) { state = next }
}
```

### 10.3 Don't use `public` in this project

We are a single-target executable. There is no other module. Anything
beyond `internal` is dead access-control code.

---

## 11. TESTING

Sources: [useyourloaf.com migrating XCTest](https://useyourloaf.com/blog/migrating-xctest-to-swift-testing/).

### 11.1 Use Swift Testing for new tests (Xcode 16+)

```swift
import Testing
@testable import VoiceRider

@Test func transcriberDecodesText() throws {
    let json = #"{"text": "hello"}"#.data(using: .utf8)!
    let r = try JSONDecoder().decode(Transcriber.Response.self, from: json)
    #expect(r.text == "hello")
}
```

### 11.2 XCTest is acceptable for legacy code or integration tests
that need its lifecycle hooks

Don't mix the two in the same test file.

### 11.3 Test seams are protocols

If a unit test needs to fake out audio or networking, the production
code should depend on a protocol (`AudioCapturing`, `Transcribing`)
that both the real and fake implementation satisfy.

### 11.4 Manual integration test for end-to-end paths

Some pieces (CGEventTap, paste-back) cannot be unit-tested without an
actual user session. Document the manual test in `README.md`. That is
the integration test.

---

## 12. STYLE

### 12.1 Indentation: 4 spaces, no tabs

Match swift-format defaults.

### 12.2 Line length: aim for 100, hard cap 120

Long signatures break across lines with each parameter on its own
line, indented one level:

```swift
func transcribe(wav: URL,
                model: String,
                completion: @escaping (Result<String, Error>) -> Void)
```

### 12.3 One type per file unless tightly coupled

A private helper enum used only by the type above it is fine to keep
in the same file.

### 12.4 Member ordering inside a type

1. Type aliases / nested types
2. Stored properties
3. Computed properties
4. Initializers
5. Public/internal methods
6. Private helpers (at the bottom)

### 12.5 Use `// MARK: - SectionName` to delineate within long files

### 12.6 Prefer trailing closures only when there's exactly one closure

```swift
// GOOD
items.forEach { item in print(item) }

// BAD — multiple trailing closures hide the second's role
button.action(perform: { … }) completion: { … }
```

### 12.7 Use `guard` for early exit, `if` for the happy path

```swift
// GOOD
guard isReady else { return }
doWork()

// BAD
if isReady {
    doWork()
}
```

---

## 13. PERFORMANCE NOTES

### 13.1 Avoid unnecessary `Array` allocations in hot paths

`reduce(into:)` over `reduce`. Pre-size with `reserveCapacity(_:)` if
the count is known.

### 13.2 `String` is a value type but copies are O(1) until mutated

Don't pre-emptively pass `inout String` for "performance". Profile
first.

### 13.3 Closure-based APIs allocate

In hot paths (audio callbacks), prefer direct method calls over
stored closures.

### 13.4 `os_signpost` for profiling

For the audio-tap callback or any latency-sensitive path, use
`os_signpost` to measure rather than guessing.

---

## 14. ANTI-PATTERNS — ZERO TOLERANCE

- ❌ `try!` outside test code
- ❌ `as!` outside test code
- ❌ Force-unwrap of values not provably non-nil at the unwrap site
- ❌ `class` where `struct` would do
- ❌ Non-`final` classes without an explicit subclassing reason
- ❌ Parallel `Bool` flags instead of an enum state
- ❌ Capturing `self` strongly in escaping closures stored on `self`
- ❌ `DispatchSemaphore` to bridge async to sync
- ❌ Mutating UI from a non-main-actor context
- ❌ `print(...)` for production logging — use `os.Logger`
- ❌ Hand-rolled JSON parsing instead of `Codable`
- ❌ Using `Any` / `AnyObject` to dodge type design
- ❌ Type names abbreviated to less than the full word (`Mgr`, `Ctrl`,
  `Cfg`)
- ❌ `// TODO` or `// FIXME` left in merged code without an issue
  number

---

## 15. ENFORCEMENT

Before merge:

1. `swift build -c release` produces **zero warnings**.
2. `swift-format lint --strict Sources/` (when configured) reports
   nothing.
3. New types: verified against the naming rules in §1 and §2.
4. New escaping closures: verified for capture-list correctness (§9).
5. New error paths: verified against §6 (no silent `try?`).
6. Annie / Sauron rules in `no-orphans-no-dual-paths.md` still hold.
