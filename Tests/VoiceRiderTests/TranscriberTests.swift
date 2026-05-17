import Testing
import Foundation
@testable import VoiceRider

/// F3 fix: `MockURLProtocol` keeps static `requestHandler` and
/// `lastRequest`. Swift Testing runs tests in parallel by default, which
/// would corrupt that shared state. `.serialized` makes every test in
/// this suite run sequentially.
@Suite("Transcriber", .serialized)
struct TranscriberTests {

    private static let endpoint =
        URL(string: "http://linux:8000/v1/audio/transcriptions")!

    // MARK: Pure multipart builder

    @Test("multipart body contains both parts in correct order")
    func multipartBodyShape() throws {
        let body = Transcriber.multipartBody(
            boundary: "BOUND",
            model: "canary-qwen-2.5b",
            wavData: Data([0x52, 0x49, 0x46, 0x46]), // "RIFF"
            filename: "audio.wav")

        let str = String(data: body, encoding: .ascii) ?? ""

        #expect(str.contains("--BOUND\r\n"))
        #expect(str.contains("Content-Disposition: form-data; name=\"model\"\r\n\r\ncanary-qwen-2.5b\r\n"))
        #expect(str.contains("Content-Disposition: form-data; name=\"file\"; filename=\"audio.wav\""))
        #expect(str.contains("Content-Type: audio/wav\r\n\r\n"))
        #expect(str.hasSuffix("\r\n--BOUND--\r\n"))
        // model part appears before file part
        let modelIdx = str.range(of: "name=\"model\"")!.lowerBound
        let fileIdx  = str.range(of: "name=\"file\"")!.lowerBound
        #expect(modelIdx < fileIdx)
    }

    @Test("multipart body embeds the WAV bytes verbatim")
    func multipartEmbedsWav() {
        let wavBytes = Data([0x00, 0x01, 0x02, 0xFF, 0xAB])
        let body = Transcriber.multipartBody(
            boundary: "B",
            model: "m",
            wavData: wavBytes,
            filename: "a.wav")

        guard let blankRange = body.range(of: Data("audio/wav\r\n\r\n".utf8)) else {
            Issue.record("file part header not found")
            return
        }
        let wavStart = blankRange.upperBound
        let trailer = Data("\r\n--B--\r\n".utf8)
        guard let trailerRange = body.range(of: trailer, in: wavStart..<body.endIndex) else {
            Issue.record("trailer not found")
            return
        }
        #expect(body[wavStart..<trailerRange.lowerBound] == wavBytes)
    }

    // MARK: Model-name validation (F10)

    @Test("model name allow-list accepts canonical defaults")
    func modelNameAccepts() throws {
        try Transcriber.validate(modelName: "canary-qwen-2.5b")
        try Transcriber.validate(modelName: "whisper_large.v3")
        try Transcriber.validate(modelName: "GPT-4o-mini")
    }

    @Test("model name allow-list rejects CRLF injection")
    func modelNameRejectsCRLF() {
        let injected = "canary\r\nX-Evil: 1"
        do {
            try Transcriber.validate(modelName: injected)
            Issue.record("should have thrown invalidModel")
        } catch let Transcriber.TranscribeError.invalidModel(value) {
            #expect(value == injected)
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }

    @Test("model name allow-list rejects empty and whitespace")
    func modelNameRejectsEmpty() {
        for bad in ["", " ", "  ", "model name with spaces", "model/with/slash"] {
            do {
                try Transcriber.validate(modelName: bad)
                Issue.record("expected reject for \(bad.debugDescription)")
            } catch is Transcriber.TranscribeError {
                // ok
            } catch {
                Issue.record("wrong error: \(error)")
            }
        }
    }

    @Test("Transcriber.init throws on bad model")
    func initThrowsOnBadModel() {
        do {
            _ = try Transcriber(endpoint: Self.endpoint, model: "bad name", bearer: "x")
            Issue.record("expected throw")
        } catch is Transcriber.TranscribeError {
            // ok
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }

    // MARK: HTTP path via MockURLProtocol

    @Test("happy path: returns trimmed text on 200")
    func happyPath200() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        MockURLProtocol.requestHandler = { req in
            let body = #"{"text":"  hello world  "}"#.data(using: .utf8)!
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
            return (resp, body)
        }

        let url = try Self.makeTempWav()
        defer { try? FileManager.default.removeItem(at: url) }
        let session = MockURLProtocol.makeSession()
        let t = try Transcriber(
            endpoint: Self.endpoint,
            model: "canary-qwen-2.5b",
            bearer: "local-no-auth",
            session: session)

        let result = try await Self.run(t, wav: url)
        #expect(try result.get() == "hello world")

        guard let req = MockURLProtocol.lastRequest else {
            Issue.record("no captured request"); return
        }
        #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer local-no-auth")
        #expect(req.value(forHTTPHeaderField: "Content-Type")?.starts(with: "multipart/form-data; boundary=") == true)
        #expect(req.httpMethod == "POST")
    }

    @Test("HTTP 500 surfaces as TranscribeError.http")
    func http500() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        MockURLProtocol.requestHandler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 500,
                                       httpVersion: nil, headerFields: nil)!
            return (resp, Data("server unhealthy".utf8))
        }

        let url = try Self.makeTempWav()
        defer { try? FileManager.default.removeItem(at: url) }
        let t = try Transcriber(
            endpoint: Self.endpoint,
            model: "x", bearer: "y",
            session: MockURLProtocol.makeSession())

        let result = try await Self.run(t, wav: url)
        do {
            _ = try result.get()
            Issue.record("expected failure")
        } catch let Transcriber.TranscribeError.http(status, body) {
            #expect(status == 500)
            #expect(body == "server unhealthy")
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }

    @Test("empty text body surfaces as .empty")
    func emptyTextEmpty() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        MockURLProtocol.requestHandler = { req in
            let body = #"{"text":""}"#.data(using: .utf8)!
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
            return (resp, body)
        }

        let url = try Self.makeTempWav()
        defer { try? FileManager.default.removeItem(at: url) }
        let t = try Transcriber(
            endpoint: Self.endpoint,
            model: "x", bearer: "y",
            session: MockURLProtocol.makeSession())

        let result = try await Self.run(t, wav: url)
        do {
            _ = try result.get()
            Issue.record("expected failure")
        } catch Transcriber.TranscribeError.empty {
            // ok
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }

    @Test("malformed JSON surfaces as .decode")
    func malformedJSON() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        MockURLProtocol.requestHandler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
            return (resp, Data("not json".utf8))
        }

        let url = try Self.makeTempWav()
        defer { try? FileManager.default.removeItem(at: url) }
        let t = try Transcriber(
            endpoint: Self.endpoint,
            model: "x", bearer: "y",
            session: MockURLProtocol.makeSession())

        let result = try await Self.run(t, wav: url)
        do {
            _ = try result.get()
            Issue.record("expected failure")
        } catch Transcriber.TranscribeError.decode {
            // ok
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }

    // MARK: Helpers

    private static func makeTempWav() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice-test-\(UUID().uuidString).wav")
        try Data([0x52, 0x49, 0x46, 0x46, 0x00]).write(to: url)
        return url
    }

    /// Bridges the completion-handler API into async/await so each test
    /// can `await` exactly one result.
    private static func run(_ t: Transcriber, wav: URL) async throws
        -> Result<String, Transcriber.TranscribeError>
    {
        await withCheckedContinuation { cont in
            t.transcribe(wav: wav) { result in
                cont.resume(returning: result)
            }
        }
    }
}
