import Foundation

/// Test seam: install via `URLSessionConfiguration.protocolClasses` to
/// intercept all `URLSession` traffic. Tests set `requestHandler` to a
/// closure that inspects the outgoing `URLRequest` (asserting on the
/// multipart body, headers, etc.) and returns a `(HTTPURLResponse, Data)`
/// to feed back to the client.
///
/// Static state is racy under Swift Testing's parallel default. Suites
/// that touch this protocol are annotated `@Suite(.serialized)` (F3 fix).
final class MockURLProtocol: URLProtocol {

    /// Set by tests. Called for every intercepted request.
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    /// Captures the most recent request the protocol observed. Useful for
    /// assertions on body/headers after the call site has returned.
    nonisolated(unsafe) static var lastRequest: URLRequest?

    /// Reset between tests.
    static func reset() {
        requestHandler = nil
        lastRequest = nil
    }

    /// Returns a `URLSession` configured to route through this protocol.
    static func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    // MARK: URLProtocol overrides

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        // URLProtocol replays bodies via `httpBodyStream` for streamed
        // uploads. Drain the stream into `httpBody` so tests can inspect
        // it. F27 fix: use a Swift `[UInt8]` buffer rather than raw
        // `UnsafeMutablePointer.allocate`.
        var capturedRequest = request
        if capturedRequest.httpBody == nil, let stream = capturedRequest.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var data = Data()
            var buf = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let read = buf.withUnsafeMutableBufferPointer {
                    stream.read($0.baseAddress!, maxLength: $0.count)
                }
                if read <= 0 { break }
                data.append(buf, count: read)
            }
            capturedRequest.httpBody = data
        }
        MockURLProtocol.lastRequest = capturedRequest

        guard let handler = MockURLProtocol.requestHandler else {
            client?.urlProtocol(self, didFailWithError: NSError(
                domain: "MockURLProtocol", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "no requestHandler set"]))
            return
        }

        do {
            let (response, data) = try handler(capturedRequest)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
