import Testing
import Foundation
@testable import VoiceRider

/// `MockURLProtocol` keeps static state — these tests share the same
/// `.serialized` suite as `TranscriberTests` (per the project pattern
/// also used in `TranscriberHTTPFixtures`). `.serialized` only
/// synchronizes within a single `@Suite`-decorated struct, so we
/// extend `TranscriberTests` rather than declaring a separate suite.
extension TranscriberTests {

    private static let probeEndpoint =
        URL(string: "http://example.test/v1/audio/transcriptions")!

    private static func makeProbe() throws -> Transcriber {
        try Transcriber(
            endpoint: Self.probeEndpoint,
            model: "canary-qwen-2.5b",
            bearer: "local-no-auth",
            session: MockURLProtocol.makeSession())
    }

    /// Bridges probe completion handler to async/await for ergonomic tests.
    private static func runProbe(_ t: Transcriber)
        async -> Result<String, Transcriber.TranscribeError>
    {
        await withCheckedContinuation { cont in
            _ = t.probe { result in cont.resume(returning: result) }
        }
    }

    // MARK: HTTP 200 + non-empty text

    @Test("probe happy path: non-empty text bubbles up as .success")
    func probeHappyPath() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        MockURLProtocol.requestHandler = { req in
            let body = #"{"text":"silence captured as something"}"#.data(using: .utf8)!
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
            return (resp, body)
        }

        let t = try Self.makeProbe()
        let result = await Self.runProbe(t)
        switch result {
        case .success(let text):
            #expect(text == "silence captured as something")
        case .failure(let e):
            Issue.record("expected .success, got \(e)")
        }
    }

    // MARK: HTTP 200 + empty text → .empty (UI interprets as success)

    @Test("probe: empty text from server surfaces as TranscribeError.empty (UI policy maps to OK)")
    func probeEmptyTextSurfacesAsEmpty() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        MockURLProtocol.requestHandler = { req in
            let body = #"{"text":""}"#.data(using: .utf8)!
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
            return (resp, body)
        }

        let t = try Self.makeProbe()
        let result = await Self.runProbe(t)
        switch result {
        case .success:
            Issue.record("expected .empty failure")
        case .failure(.empty):
            break  // ✓ probe returns transport-only result; UI maps this
        case .failure(let e):
            Issue.record("wrong error: \(e)")
        }
    }

    // MARK: HTTP 5xx

    @Test("probe HTTP 500 surfaces as .http with body")
    func probeHttp500() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        MockURLProtocol.requestHandler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 500,
                                       httpVersion: nil, headerFields: nil)!
            return (resp, Data("internal explosion".utf8))
        }

        let t = try Self.makeProbe()
        let result = await Self.runProbe(t)
        switch result {
        case .failure(.http(let status, let body)):
            #expect(status == 500)
            #expect(body == "internal explosion")
        default:
            Issue.record("expected .http(500), got \(result)")
        }
    }

    @Test("probe HTTP 401 surfaces as .http(401)")
    func probeHttp401() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        MockURLProtocol.requestHandler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 401,
                                       httpVersion: nil, headerFields: nil)!
            return (resp, Data())
        }

        let t = try Self.makeProbe()
        let result = await Self.runProbe(t)
        if case .failure(.http(let status, _)) = result {
            #expect(status == 401)
        } else {
            Issue.record("expected .http(401), got \(result)")
        }
    }

    // MARK: Decode failures

    @Test("probe non-JSON body surfaces as .decode")
    func probeDecodeFailure() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        MockURLProtocol.requestHandler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
            return (resp, Data("<html>not JSON</html>".utf8))
        }

        let t = try Self.makeProbe()
        let result = await Self.runProbe(t)
        if case .failure(.decode) = result {
            // ok
        } else {
            Issue.record("expected .decode, got \(result)")
        }
    }

    @Test("probe JSON without text key surfaces as .decode")
    func probeDecodeWrongShape() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        MockURLProtocol.requestHandler = { req in
            let body = #"{"transcript":"hello"}"#.data(using: .utf8)!
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
            return (resp, body)
        }

        let t = try Self.makeProbe()
        let result = await Self.runProbe(t)
        if case .failure(.decode) = result {
            // ok
        } else {
            Issue.record("expected .decode, got \(result)")
        }
    }

    // MARK: Network error

    @Test("probe URLError → .requestFailed (non-cancellation)")
    func probeNetworkError() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        MockURLProtocol.requestHandler = { _ in
            throw URLError(.cannotConnectToHost)
        }

        let t = try Self.makeProbe()
        let result = await Self.runProbe(t)
        if case .failure(.requestFailed) = result {
            // ok
        } else {
            Issue.record("expected .requestFailed, got \(result)")
        }
    }

    // MARK: Cancellation suppresses completion (C19)

    @Test("probe URLError.cancelled suppresses the completion handler")
    func probeCancellationSuppressesCompletion() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        MockURLProtocol.requestHandler = { _ in
            throw URLError(.cancelled)
        }

        let t = try Self.makeProbe()

        // Run with a 250ms cap. If completion fires (it shouldn't) the
        // continuation resumes; otherwise the timeout returns nil.
        let result: Result<String, Transcriber.TranscribeError>? =
            await withCheckedContinuation { cont in
                var didResume = false
                let lock = NSLock()
                func resumeOnce(_ value: Result<String, Transcriber.TranscribeError>?) {
                    lock.lock(); defer { lock.unlock() }
                    if !didResume {
                        didResume = true
                        cont.resume(returning: value)
                    }
                }

                _ = t.probe { result in
                    resumeOnce(result)
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + 0.25) {
                    resumeOnce(nil)
                }
            }

        #expect(result == nil, "completion fired despite URLError.cancelled — should have been suppressed")
    }

    // MARK: probe sends a real WAV body

    @Test("probe request body contains a 16 KB silent WAV via multipart")
    func probeSendsSilentWAV() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        MockURLProtocol.requestHandler = { req in
            let body = #"{"text":""}"#.data(using: .utf8)!
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
            return (resp, body)
        }

        let t = try Self.makeProbe()
        _ = await Self.runProbe(t)

        guard let req = MockURLProtocol.lastRequest else {
            Issue.record("no captured request"); return
        }
        guard let body = req.httpBody else {
            Issue.record("no body"); return
        }
        // Body is binary (multipart with raw WAV bytes), so search by
        // byte sequences. ASCII decoding silently drops once we hit
        // non-ASCII bytes, so we don't use it here.
        #expect(body.range(of: Data("RIFF".utf8)) != nil, "expected RIFF magic in body")
        #expect(body.range(of: Data("WAVE".utf8)) != nil, "expected WAVE magic in body")
        #expect(body.range(of: Data(#"filename="probe.wav""#.utf8)) != nil,
                "expected filename=\"probe.wav\" in body")
        // Body should be at least the silent WAV plus boundary
        // overhead (~ 16 044 + ~200 bytes).
        #expect(body.count > 16_000)
    }

    @Test("probe sets Authorization and Content-Type headers")
    func probeHeaders() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        MockURLProtocol.requestHandler = { req in
            let body = #"{"text":"x"}"#.data(using: .utf8)!
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
            return (resp, body)
        }

        let t = try Self.makeProbe()
        _ = await Self.runProbe(t)

        guard let req = MockURLProtocol.lastRequest else {
            Issue.record("no captured request"); return
        }
        #expect(req.value(forHTTPHeaderField: "Authorization") == "Bearer local-no-auth")
        #expect(req.value(forHTTPHeaderField: "Content-Type")?.starts(with: "multipart/form-data; boundary=") == true)
        #expect(req.httpMethod == "POST")
    }

    // MARK: probe returns a cancellable task

    @Test("probe returns a non-nil URLSessionDataTask")
    func probeReturnsTask() async throws {
        MockURLProtocol.reset()
        defer { MockURLProtocol.reset() }

        MockURLProtocol.requestHandler = { req in
            let body = #"{"text":"x"}"#.data(using: .utf8)!
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
            return (resp, body)
        }

        let t = try Self.makeProbe()
        let task = await withCheckedContinuation { cont in
            let task = t.probe { _ in }
            // Yield a tick so the URLSession task starts.
            DispatchQueue.main.async { cont.resume(returning: task) }
        }
        #expect(task != nil)
    }
}

@Suite("Transcriber.atsBlockedHost")
struct TranscriberATSTests {

    @Test("non-URLError returns nil")
    func nonURLError() {
        let err = NSError(domain: "x", code: 0)
        #expect(Transcriber.atsBlockedHost(in: err) == nil)
    }

    @Test("URLError with non-ATS code returns nil")
    func nonATSURLError() {
        let err = URLError(.cannotConnectToHost)
        #expect(Transcriber.atsBlockedHost(in: err) == nil)
    }

    @Test("URLError with code -1022 + failingURL extracts host")
    func atsExtractsHost() {
        var info = [String: Any]()
        info[NSURLErrorFailingURLStringErrorKey] = "http://blocked-host.example.com/path"
        info[NSURLErrorFailingURLErrorKey] = URL(string: "http://blocked-host.example.com/path")!
        // -1022 = NSURLErrorAppTransportSecurityRequiresSecureConnection
        let err = URLError(URLError.Code(rawValue: -1022), userInfo: info)
        #expect(Transcriber.atsBlockedHost(in: err) == "blocked-host.example.com")
    }
}

