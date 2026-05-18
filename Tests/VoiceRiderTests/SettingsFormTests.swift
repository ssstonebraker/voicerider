import Testing
import Foundation
@testable import VoiceRider

@Suite("SettingsForm")
struct SettingsFormTests {

    // MARK: Round-trip with ServerConfig

    @Test("from(ServerConfig) round-trips through resolve()")
    func roundTrip() throws {
        let cfg = ServerConfig.defaults
        let form = SettingsForm.from(cfg)
        let resolved = try form.resolve()
        #expect(resolved == cfg)
    }

    // MARK: Valid forms

    @Test("default LAN config is valid")
    func defaultIsValid() {
        let form = SettingsForm.from(ServerConfig.defaults)
        #expect(form.isValid)
        #expect(form.validate().isEmpty)
    }

    @Test("https URLs are accepted")
    func httpsAccepted() {
        let form = SettingsForm(
            endpointString: "https://api.openai.com/v1/audio/transcriptions",
            model:          "whisper-1",
            bearer:         "sk-AbCdEf123")
        #expect(form.isValid)
    }

    @Test("URL with port and path is accepted")
    func urlWithPortAccepted() {
        let form = SettingsForm(
            endpointString: "http://my-asr-host:9000/transcribe",
            model:          "canary-qwen-2.5b",
            bearer:         "local-no-auth")
        #expect(form.isValid)
    }

    // MARK: Empty-field errors

    @Test("empty endpoint reported as .empty(.endpoint)")
    func emptyEndpoint() {
        let form = SettingsForm(endpointString: "", model: "x", bearer: "y")
        let errors = form.validate()
        #expect(errors.contains(.empty(field: .endpoint)))
        #expect(!form.isEndpointValid)
    }

    @Test("whitespace-only endpoint reported as .empty(.endpoint)")
    func whitespaceOnlyEndpoint() {
        let form = SettingsForm(endpointString: "   \n\t  ", model: "x", bearer: "y")
        #expect(form.validate().contains(.empty(field: .endpoint)))
    }

    @Test("empty model reported as .empty(.model)")
    func emptyModel() {
        let form = SettingsForm.from(ServerConfig.defaults)
        var f = form; f.model = ""
        #expect(f.validate().contains(.empty(field: .model)))
        #expect(!f.isModelValid)
    }

    @Test("empty bearer is valid (optional field)")
    func emptyBearer() {
        var f = SettingsForm.from(ServerConfig.defaults)
        f.bearer = ""
        #expect(!f.validate().contains(.empty(field: .bearer)))
        #expect(f.isBearerValid)
    }

    // MARK: URL malformed errors

    @Test("URL with no scheme is rejected")
    func noScheme() {
        let form = SettingsForm(endpointString: "localhost:8000", model: "x", bearer: "y")
        #expect(form.validate().contains(.malformedURL))
    }

    @Test("URL with non-http(s) scheme is rejected")
    func ftpRejected() {
        let form = SettingsForm(endpointString: "ftp://server/file", model: "x", bearer: "y")
        #expect(form.validate().contains(.malformedURL))
    }

    @Test("plain garbage is rejected")
    func garbageRejected() {
        let form = SettingsForm(endpointString: "junk", model: "x", bearer: "y")
        #expect(form.validate().contains(.malformedURL))
    }

    @Test("path-only URL is rejected (no host)")
    func pathOnlyRejected() {
        let form = SettingsForm(endpointString: "/foo/bar", model: "x", bearer: "y")
        #expect(form.validate().contains(.malformedURL))
    }

    @Test("trimmable whitespace around a valid URL is accepted")
    func leadingTrailingWhitespaceAccepted() {
        let form = SettingsForm(
            endpointString: "  http://localhost:8000/v1/audio/transcriptions  ",
            model:          "canary-qwen-2.5b",
            bearer:         "local-no-auth")
        #expect(form.isValid)
        let resolved = try? form.resolve()
        #expect(resolved?.endpoint.absoluteString == "http://localhost:8000/v1/audio/transcriptions")
    }

    // MARK: Regex delegation to Transcriber

    @Test("invalid model name surfaces as .modelRegex (Transcriber regex)")
    func invalidModelRegex() {
        var f = SettingsForm.from(ServerConfig.defaults)
        f.model = "model with spaces"
        #expect(f.validate().contains(.modelRegex))
        #expect(!f.isModelValid)
    }

    @Test("CRLF in model name is rejected via Transcriber regex")
    func modelCRLFRejected() {
        var f = SettingsForm.from(ServerConfig.defaults)
        f.model = "model\r\nX-Evil: 1"
        #expect(f.validate().contains(.modelRegex))
    }

    @Test("invalid bearer surfaces as .bearerRegex")
    func invalidBearerRegex() {
        var f = SettingsForm.from(ServerConfig.defaults)
        f.bearer = "bearer with spaces"
        #expect(f.validate().contains(.bearerRegex))
        #expect(!f.isBearerValid)
    }

    @Test("CRLF in bearer is rejected via Transcriber regex")
    func bearerCRLFRejected() {
        var f = SettingsForm.from(ServerConfig.defaults)
        f.bearer = "valid\r\nInjected-Header: yes"
        #expect(f.validate().contains(.bearerRegex))
    }

    // MARK: Resolve behavior

    @Test("resolve() throws first error when invalid")
    func resolveThrowsFirstError() {
        let form = SettingsForm(endpointString: "", model: "", bearer: "")
        do {
            _ = try form.resolve()
            Issue.record("expected throw")
        } catch let err as SettingsForm.FieldError {
            // First in stable order is .empty(.endpoint)
            #expect(err == .empty(field: .endpoint))
        } catch {
            Issue.record("wrong error type: \(error)")
        }
    }

    @Test("resolve() succeeds after trimming whitespace")
    func resolveTrimsWhitespace() throws {
        let form = SettingsForm(
            endpointString: "\n http://x:1/y \t",
            model:          "canary-qwen-2.5b",
            bearer:         "local-no-auth")
        let cfg = try form.resolve()
        #expect(cfg.endpoint.absoluteString == "http://x:1/y")
    }

    // MARK: Equatable

    @Test("Equatable distinguishes each field")
    func equatable() {
        let a = SettingsForm.from(ServerConfig.defaults)
        var b = a; b.bearer = "different"
        var c = a; c.model = "different"
        var d = a; d.endpointString = "https://example.com/x"
        #expect(a == a)
        #expect(a != b)
        #expect(a != c)
        #expect(a != d)
    }

    // MARK: isAcceptableURLString helper

    @Test("isAcceptableURLString accepts canonical forms")
    func acceptableAccepts() {
        #expect(SettingsForm.isAcceptableURLString("http://localhost:8000/v1/audio/transcriptions"))
        #expect(SettingsForm.isAcceptableURLString("https://api.openai.com/v1/audio/transcriptions"))
        #expect(SettingsForm.isAcceptableURLString("HTTP://X/Y"))   // case-insensitive scheme
    }

    @Test("isAcceptableURLString rejects edge cases")
    func acceptableRejects() {
        #expect(!SettingsForm.isAcceptableURLString(""))
        #expect(!SettingsForm.isAcceptableURLString("junk"))
        #expect(!SettingsForm.isAcceptableURLString("/path"))
        #expect(!SettingsForm.isAcceptableURLString("ftp://server"))
        #expect(!SettingsForm.isAcceptableURLString("localhost:8000"))   // no scheme
    }
}
