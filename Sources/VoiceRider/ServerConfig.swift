import Foundation

/// The three values that together define "what server are we talking to?":
/// endpoint URL, model name, bearer token.
///
/// One source of truth for this triple is **`UserDefaults`**. `ServerConfig`
/// is the read/write shim. Everything else in the app derives from it:
/// `AppDelegate.transcriber` is rebuilt from the latest `ServerConfig` on
/// launch and on every settings save; nothing else maintains a parallel
/// copy. (Sauron rule.)
///
/// The same three `UserDefaults` keys (`voicerider.serverURL`,
/// `voicerider.modelName`, `voicerider.bearerToken`) that the CLI
/// `defaults write` workflow uses are the same keys this struct
/// reads/writes. The settings window is a *UI* over the same persistence
/// layer; no new schema.
struct ServerConfig: Equatable, Sendable {
    var endpoint: URL
    var model: String
    var bearer: String

    // MARK: UserDefaults keys (single source of truth)

    static let serverURLKey   = "voicerider.serverURL"
    static let modelNameKey   = "voicerider.modelName"
    static let bearerTokenKey = "voicerider.bearerToken"

    // MARK: Defaults

    /// Allow-listed force-unwrap per
    /// `swift-coding-best-practices.md` §5.1: "Initializing a known-good
    /// constant: `URL(string: "...")!`". The literal is checked at
    /// compile time by Swift's URL initializer.
    static let defaults = ServerConfig(
        endpoint: URL(string: "http://localhost:8000/v1/audio/transcriptions")!,
        model:    "canary-qwen-2.5b",
        bearer:   "")

    // MARK: Load / Save

    /// Reads the three keys from `defaults` (or `.standard` by default).
    /// Falls back to `ServerConfig.defaults` on missing or malformed
    /// values. A malformed serverURL string is treated like a missing
    /// one — same behaviour as the previous `AppDelegate.Config.load`.
    ///
    /// "Malformed" here is stricter than `URL(string:)` returning nil:
    /// `URL(string: "not a url")` actually succeeds (returns
    /// `not%20a%20url` with no scheme), so `load()` additionally
    /// requires the round-tripped URL to satisfy
    /// `isAcceptableURLString` — http/https scheme, non-empty host.
    /// This keeps `defaults write voicerider.serverURL "junk"` from
    /// landing a nonsense URL in the live Transcriber.
    static func load(from defaults: UserDefaults = .standard) -> ServerConfig {
        let d = ServerConfig.defaults
        let endpoint: URL = {
            guard let raw = defaults.string(forKey: Self.serverURLKey),
                  Self.isAcceptableURLString(raw),
                  let parsed = URL(string: raw) else {
                return d.endpoint
            }
            return parsed
        }()
        let model = defaults.string(forKey: Self.modelNameKey) ?? d.model
        let bearer = defaults.string(forKey: Self.bearerTokenKey) ?? d.bearer
        return ServerConfig(endpoint: endpoint, model: model, bearer: bearer)
    }

    /// Writes the three keys atomically (each `set` is independently
    /// atomic; we accept an extremely brief inconsistency window
    /// between writes — UserDefaults has no transactional API). The
    /// settings window calls this at most once per Save click.
    static func save(_ cfg: ServerConfig, to defaults: UserDefaults = .standard) {
        defaults.set(cfg.endpoint.absoluteString, forKey: Self.serverURLKey)
        defaults.set(cfg.model,                   forKey: Self.modelNameKey)
        defaults.set(cfg.bearer,                  forKey: Self.bearerTokenKey)
    }

    // MARK: URL acceptability

    /// Returns true iff `s` parses as a URL with `scheme` ∈
    /// {http, https} and a non-empty `host`. Treats `URL(string:)`
    /// success alone as insufficient — Foundation's URL initializer
    /// accepts garbage like `"junk"`, `"not a url"`, or `"/path"`
    /// and returns a URL with `scheme=nil`, which makes the
    /// resulting Transcriber post HTTP to a non-host. This guard
    /// lives on `ServerConfig` (single source of truth — Sauron)
    /// and is reused by `SettingsForm.isAcceptableURLString`.
    static func isAcceptableURLString(_ s: String) -> Bool {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let url = URL(string: trimmed) else { return false }
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return false }
        guard let host = url.host, !host.isEmpty else { return false }
        return true
    }
}
