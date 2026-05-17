import Testing
import Foundation
@testable import VoiceRider

/// Fixture-based coverage for `Transcriber` over the network path.
///
/// These tests are an `extension` of `TranscriberTests` (defined in
/// `TranscriberTests.swift`) so they share the **same** `.serialized`
/// suite. `.serialized` only synchronizes tests within a single
/// `@Suite`-decorated struct; running these as a separate suite would
/// allow Swift Testing to interleave them with `TranscriberTests` and
/// corrupt `MockURLProtocol`'s static state.
extension TranscriberTests {

    private static let httpEndpoint =
        URL(string: "http://example.test/v1/audio/transcriptions")!

    private static let wavBytes: [UInt8] = [
        // Tiny RIFF/WAVE fixture: 4-byte 'RIFF' magic plus a marker byte.
        0x52, 0x49, 0x46, 0x46, 0xAB,
    ]

    // MARK: - Helpers

    /// Writes a deterministic WAV fixture and returns its URL. Caller
    /// is responsible for cleanup; tests use `defer { try? remove }`.
    private static func makeFixtureWav(_ bytes: [UInt8] = wavBytes) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice-fixture-\(UUID().uuidString).wav")
        try Data(bytes).write(to: url)
        return url
    }

    /// Bridges the completion-handler API into async/await.
    private static func runFixture(_ t: Transcriber, wav: URL) async
        -> Result<String, Transcriber.TranscribeError>
    {
        await withCheckedContinuation { cont in
            t.transcribe(wav: wav) { result in
                cont.resume(returning: result)
            }
        }
    }

    // MARK: - Authorization header

    @Test("Authorization header matches 'Bearer <token>' exactly")
    func authHeaderShape() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        MockURLProtocol.requestHandler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
            return (resp, #"{"text":"x"}"#.data(using: .utf8)!)
        }

        let url = try Self.makeFixtureWav()
        defer { try? FileManager.default.removeItem(at: url) }

        let t = try Transcriber(
            endpoint: Self.httpEndpoint,
            model: "canary-qwen-2.5b",
            bearer: "sk-test-1234567890",
            session: MockURLProtocol.makeSession())
        _ = await Self.runFixture(t, wav: url)

        guard let req = MockURLProtocol.lastRequest else {
            Issue.record("no captured request"); return
        }
        #expect(req.value(forHTTPHeaderField: "Authorization")
            == "Bearer sk-test-1234567890")
    }

    @Test("Authorization header with default token reads 'Bearer local-no-auth'")
    func authHeaderDefaultToken() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        MockURLProtocol.requestHandler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
            return (resp, #"{"text":"x"}"#.data(using: .utf8)!)
        }

        let url = try Self.makeFixtureWav()
        defer { try? FileManager.default.removeItem(at: url) }

        let t = try Transcriber(
            endpoint: Self.httpEndpoint,
            model: "canary-qwen-2.5b",
            bearer: "local-no-auth",
            session: MockURLProtocol.makeSession())
        _ = await Self.runFixture(t, wav: url)

        #expect(MockURLProtocol.lastRequest?.value(forHTTPHeaderField: "Authorization")
            == "Bearer local-no-auth")
    }

    // MARK: - Content-Type / boundary

    @Test("Content-Type is multipart with a unique boundary per request")
    func contentTypeAndUniqueBoundary() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        // Capture two boundaries by running twice.
        var boundaries: [String] = []
        MockURLProtocol.requestHandler = { req in
            if let ct = req.value(forHTTPHeaderField: "Content-Type") {
                let prefix = "multipart/form-data; boundary="
                if ct.hasPrefix(prefix) {
                    boundaries.append(String(ct.dropFirst(prefix.count)))
                }
            }
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
            return (resp, #"{"text":"x"}"#.data(using: .utf8)!)
        }

        let url = try Self.makeFixtureWav()
        defer { try? FileManager.default.removeItem(at: url) }

        let session = MockURLProtocol.makeSession()
        let t = try Transcriber(
            endpoint: Self.httpEndpoint,
            model: "canary-qwen-2.5b",
            bearer: "x",
            session: session)
        _ = await Self.runFixture(t, wav: url)
        _ = await Self.runFixture(t, wav: url)

        #expect(boundaries.count == 2)
        if boundaries.count == 2 {
            #expect(boundaries[0] != boundaries[1], "boundary should be unique per request")
            #expect(boundaries[0].hasPrefix("voice-"))
            #expect(boundaries[1].hasPrefix("voice-"))
        }
    }

    // MARK: - Multipart byte pinning

    @Test("multipart body is byte-stable for a fixed boundary and model")
    func multipartByteStable() {
        let body = Transcriber.multipartBody(
            boundary: "BOUND",
            model: "canary-qwen-2.5b",
            wavData: Data([0x52, 0x49, 0x46, 0x46]),
            filename: "x.wav")
        let expected = (
            "--BOUND\r\n" +
            "Content-Disposition: form-data; name=\"model\"\r\n\r\n" +
            "canary-qwen-2.5b\r\n" +
            "--BOUND\r\n" +
            "Content-Disposition: form-data; name=\"file\"; filename=\"x.wav\"\r\n" +
            "Content-Type: audio/wav\r\n\r\n"
        )
        let trailer = "\r\n--BOUND--\r\n"

        // Header bytes
        let headerBytes = Data(expected.utf8)
        #expect(body.starts(with: headerBytes))

        // Trailer bytes
        let trailerBytes = Data(trailer.utf8)
        #expect(body.suffix(trailerBytes.count) == trailerBytes)

        // WAV bytes wedged between header and trailer
        let mid = body.dropFirst(headerBytes.count).dropLast(trailerBytes.count)
        #expect(Array(mid) == [0x52, 0x49, 0x46, 0x46])
    }

    @Test("multipart body length math holds for a 1MB synthetic WAV")
    func multipartLengthMath() {
        let wav = Data(repeating: 0xCD, count: 1_000_000)
        let body = Transcriber.multipartBody(
            boundary: "B",
            model: "m",
            wavData: wav,
            filename: "x.wav")
        // Header bytes:
        let header = Data((
            "--B\r\n" +
            "Content-Disposition: form-data; name=\"model\"\r\n\r\n" +
            "m\r\n" +
            "--B\r\n" +
            "Content-Disposition: form-data; name=\"file\"; filename=\"x.wav\"\r\n" +
            "Content-Type: audio/wav\r\n\r\n"
        ).utf8)
        let trailer = Data("\r\n--B--\r\n".utf8)

        #expect(body.count == header.count + wav.count + trailer.count)
    }

    @Test("filename in multipart matches the wav URL's lastPathComponent")
    func multipartFilename() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        MockURLProtocol.requestHandler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
            return (resp, #"{"text":"x"}"#.data(using: .utf8)!)
        }

        let url = try Self.makeFixtureWav()
        defer { try? FileManager.default.removeItem(at: url) }

        let t = try Transcriber(
            endpoint: Self.httpEndpoint,
            model: "m",
            bearer: "y",
            session: MockURLProtocol.makeSession())
        _ = await Self.runFixture(t, wav: url)

        guard let req = MockURLProtocol.lastRequest,
              let body = req.httpBody,
              // Use ISO-8859-1 so non-ASCII WAV bytes don't make decoding fail.
              let s = String(data: body, encoding: .isoLatin1) else {
            Issue.record("no captured body")
            return
        }
        #expect(s.contains("filename=\"\(url.lastPathComponent)\""))
    }

    // MARK: - HTTP status code variants

    @Test("HTTP 400 surfaces with body")
    func http400WithBody() async throws {
        try await assertHTTPStatus(400, expectedBody: "bad request payload")
    }

    @Test("HTTP 401 surfaces with body")
    func http401WithBody() async throws {
        try await assertHTTPStatus(401, expectedBody: "unauthorized")
    }

    @Test("HTTP 403 surfaces with body")
    func http403WithBody() async throws {
        try await assertHTTPStatus(403, expectedBody: "forbidden")
    }

    @Test("HTTP 404 surfaces with body")
    func http404WithBody() async throws {
        try await assertHTTPStatus(404, expectedBody: "not found")
    }

    @Test("HTTP 413 (payload too large) surfaces with body")
    func http413WithBody() async throws {
        try await assertHTTPStatus(413, expectedBody: "payload too large")
    }

    @Test("HTTP 429 (rate limit) surfaces with body")
    func http429WithBody() async throws {
        try await assertHTTPStatus(429, expectedBody: "too many requests")
    }

    @Test("HTTP 500 surfaces with body")
    func http500WithBody() async throws {
        try await assertHTTPStatus(500, expectedBody: "server unhealthy")
    }

    @Test("HTTP 503 (service unavailable) surfaces with body")
    func http503WithBody() async throws {
        try await assertHTTPStatus(503, expectedBody: "service unavailable")
    }

    @Test("HTTP 200 boundary — 199 fails, 300 fails, 200/201/204 require body decode")
    func httpStatusBoundaries() async throws {
        try await assertHTTPStatus(199, expectedBody: "weird")
        try await assertHTTPStatus(300, expectedBody: "redirect-ish")
        // 200/201/204 success codes decode the body normally; covered
        // by the happy-path tests in `TranscriberTests`.
    }

    private func assertHTTPStatus(_ status: Int, expectedBody: String) async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        MockURLProtocol.requestHandler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: status,
                                       httpVersion: nil, headerFields: nil)!
            return (resp, Data(expectedBody.utf8))
        }

        let url = try Self.makeFixtureWav()
        defer { try? FileManager.default.removeItem(at: url) }

        let t = try Transcriber(
            endpoint: Self.httpEndpoint,
            model: "m",
            bearer: "y",
            session: MockURLProtocol.makeSession())
        let result = await Self.runFixture(t, wav: url)

        do {
            _ = try result.get()
            Issue.record("expected failure for HTTP \(status)")
        } catch let Transcriber.TranscribeError.http(captured, body) {
            #expect(captured == status)
            #expect(body == expectedBody)
        } catch {
            Issue.record("wrong error for HTTP \(status): \(error)")
        }
    }

    // MARK: - Network / decoding edge cases

    @Test("URL load failure surfaces as .requestFailed")
    func urlLoadFailureSurfaces() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        struct E: Error, LocalizedError { var errorDescription: String? { "fixture-network-error" } }
        MockURLProtocol.requestHandler = { _ in throw E() }

        let url = try Self.makeFixtureWav()
        defer { try? FileManager.default.removeItem(at: url) }

        let t = try Transcriber(
            endpoint: Self.httpEndpoint,
            model: "m",
            bearer: "y",
            session: MockURLProtocol.makeSession())
        let result = await Self.runFixture(t, wav: url)

        do {
            _ = try result.get()
            Issue.record("expected failure")
        } catch let Transcriber.TranscribeError.requestFailed(message) {
            #expect(message.contains("fixture-network-error")
                    || message.contains("error 1"), "got: \(message)")
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }

    @Test("decode handles forward-compat — extra fields ignored, text returned")
    func decodeForwardCompat() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        let json = #"{"text":"hello","duration":1.23,"model":"canary","extra":{"a":1}}"#
        MockURLProtocol.requestHandler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
            return (resp, Data(json.utf8))
        }

        let url = try Self.makeFixtureWav()
        defer { try? FileManager.default.removeItem(at: url) }

        let t = try Transcriber(
            endpoint: Self.httpEndpoint,
            model: "m",
            bearer: "y",
            session: MockURLProtocol.makeSession())
        let result = await Self.runFixture(t, wav: url)
        #expect(try result.get() == "hello")
    }

    @Test("decode rejects JSON missing 'text' field as .decode")
    func decodeMissingTextField() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        MockURLProtocol.requestHandler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
            return (resp, Data(#"{"transcript":"hello"}"#.utf8))
        }

        let url = try Self.makeFixtureWav()
        defer { try? FileManager.default.removeItem(at: url) }

        let t = try Transcriber(
            endpoint: Self.httpEndpoint,
            model: "m",
            bearer: "y",
            session: MockURLProtocol.makeSession())
        let result = await Self.runFixture(t, wav: url)

        do {
            _ = try result.get()
            Issue.record("expected failure")
        } catch Transcriber.TranscribeError.decode {
            // ok
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }

    @Test("whitespace-only text body surfaces as .empty")
    func whitespaceOnlyText() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        MockURLProtocol.requestHandler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
            return (resp, Data(#"{"text":"  \t\n  "}"#.utf8))
        }

        let url = try Self.makeFixtureWav()
        defer { try? FileManager.default.removeItem(at: url) }

        let t = try Transcriber(
            endpoint: Self.httpEndpoint,
            model: "m",
            bearer: "y",
            session: MockURLProtocol.makeSession())
        let result = await Self.runFixture(t, wav: url)

        do {
            _ = try result.get()
            Issue.record("expected failure")
        } catch Transcriber.TranscribeError.empty {
            // ok
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }

    @Test("Unicode in transcribed text round-trips correctly")
    func unicodeRoundTrip() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        let payload = "héllo, 世界 — emoji 🎙️ and combining ñ"
        let body = try JSONEncoder().encode(["text": payload])

        MockURLProtocol.requestHandler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
            return (resp, body)
        }

        let url = try Self.makeFixtureWav()
        defer { try? FileManager.default.removeItem(at: url) }

        let t = try Transcriber(
            endpoint: Self.httpEndpoint,
            model: "m",
            bearer: "y",
            session: MockURLProtocol.makeSession())
        let result = await Self.runFixture(t, wav: url)
        #expect(try result.get() == payload)
    }

    // MARK: - Method and URL

    @Test("HTTP method is POST and URL matches the endpoint")
    func methodAndURL() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        MockURLProtocol.requestHandler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
            return (resp, Data(#"{"text":"x"}"#.utf8))
        }

        let url = try Self.makeFixtureWav()
        defer { try? FileManager.default.removeItem(at: url) }

        let t = try Transcriber(
            endpoint: Self.httpEndpoint,
            model: "m",
            bearer: "y",
            session: MockURLProtocol.makeSession())
        _ = await Self.runFixture(t, wav: url)

        let req = MockURLProtocol.lastRequest
        #expect(req?.httpMethod == "POST")
        #expect(req?.url == Self.httpEndpoint)
    }
}
