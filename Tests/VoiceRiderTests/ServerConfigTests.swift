import Testing
import Foundation
@testable import VoiceRider

/// Round-trips ServerConfig through an isolated UserDefaults suite so
/// the tests don't pollute the real app domain.
@Suite("ServerConfig")
struct ServerConfigTests {

    /// Returns a fresh, isolated UserDefaults with a unique suite name.
    /// Cleaned up at the end of each test.
    private static func isolatedDefaults() -> (UserDefaults, () -> Void) {
        let suite = "voicerider.tests.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        let cleanup: () -> Void = {
            d.removePersistentDomain(forName: suite)
        }
        return (d, cleanup)
    }

    @Test("defaults match the documented LAN-friendly defaults")
    func defaultsShape() {
        let d = ServerConfig.defaults
        #expect(d.endpoint.absoluteString == "http://localhost:8000/v1/audio/transcriptions")
        #expect(d.model == "canary-qwen-2.5b")
        #expect(d.bearer == "local-no-auth")
    }

    @Test("load() returns defaults when the suite is empty")
    func loadReturnsDefaultsOnEmpty() {
        let (d, cleanup) = Self.isolatedDefaults()
        defer { cleanup() }

        let cfg = ServerConfig.load(from: d)
        #expect(cfg == ServerConfig.defaults)
    }

    @Test("save then load round-trips faithfully")
    func saveLoadRoundTrip() throws {
        let (d, cleanup) = Self.isolatedDefaults()
        defer { cleanup() }

        let original = ServerConfig(
            endpoint: URL(string: "https://api.example.com/v1/audio/transcriptions")!,
            model:    "whisper-1",
            bearer:   "sk-AbCdEf123")
        ServerConfig.save(original, to: d)

        let loaded = ServerConfig.load(from: d)
        #expect(loaded == original)
    }

    @Test("malformed serverURL string falls back to default endpoint")
    func malformedURLFallsBack() {
        let (d, cleanup) = Self.isolatedDefaults()
        defer { cleanup() }

        // Spaces aren't a valid URL; URL(string:) returns nil.
        d.set("not a url", forKey: ServerConfig.serverURLKey)
        d.set("custom-model", forKey: ServerConfig.modelNameKey)
        d.set("custom-bearer", forKey: ServerConfig.bearerTokenKey)

        let cfg = ServerConfig.load(from: d)
        #expect(cfg.endpoint == ServerConfig.defaults.endpoint)
        #expect(cfg.model == "custom-model")
        #expect(cfg.bearer == "custom-bearer")
    }

    @Test("Equatable distinguishes endpoint, model, and bearer")
    func equatableSensitivity() {
        let base = ServerConfig.defaults
        let differentEndpoint = ServerConfig(
            endpoint: URL(string: "http://other:8000/v1/audio/transcriptions")!,
            model: base.model, bearer: base.bearer)
        let differentModel = ServerConfig(
            endpoint: base.endpoint, model: "other", bearer: base.bearer)
        let differentBearer = ServerConfig(
            endpoint: base.endpoint, model: base.model, bearer: "other")

        #expect(base != differentEndpoint)
        #expect(base != differentModel)
        #expect(base != differentBearer)
        #expect(base == ServerConfig.defaults)
    }

    @Test("partial UserDefaults — only some keys set — fills the rest from defaults")
    func partialDefaultsFillsRest() {
        let (d, cleanup) = Self.isolatedDefaults()
        defer { cleanup() }

        d.set("custom-model", forKey: ServerConfig.modelNameKey)
        // serverURLKey and bearerTokenKey not set

        let cfg = ServerConfig.load(from: d)
        #expect(cfg.endpoint == ServerConfig.defaults.endpoint)
        #expect(cfg.model == "custom-model")
        #expect(cfg.bearer == ServerConfig.defaults.bearer)
    }
}
