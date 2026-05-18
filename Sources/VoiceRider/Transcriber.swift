import Foundation

/// Posts a WAV file to an OpenAI-style `/v1/audio/transcriptions` endpoint
/// and returns the transcribed text.
///
/// The session is injectable so unit tests can install a `URLProtocol` mock
/// and exercise the multipart-body builder without hitting the network.
final class Transcriber {

    /// Errors carry **`String` messages** rather than `Error` existentials.
    /// An `Error` existential captured here would cross a `URLSession`
    /// completion thread → main-actor boundary, and `Error` is not
    /// `Sendable`. Callers want a user-displayable message anyway, which
    /// `error.localizedDescription` already gives us at the catch site.
    enum TranscribeError: Error, LocalizedError, Sendable {
        case requestFailed(message: String)
        case http(status: Int, body: String?)
        case decode(message: String)
        case empty
        case invalidModel(value: String)
        case invalidBearer(value: String)

        var errorDescription: String? {
            switch self {
            case .requestFailed(let m):    return "network: \(m)"
            case .http(let s, let body):   return "HTTP \(s)" + (body.map { ": \($0)" } ?? "")
            case .decode(let m):           return "decode: \(m)"
            case .empty:                   return "server returned no text"
            case .invalidModel(let v):     return "invalid model name: \(v)"
            case .invalidBearer(let v):    return "invalid bearer token: \(v)"
            }
        }
    }

    /// Wire shape of the server response.
    struct Response: Decodable {
        let text: String
    }

    /// Allow-list for the multipart `model` field. Disallows whitespace and
    /// CRLF, which would let a malicious `voicerider.modelName` UserDefault
    /// inject extra multipart parts or forge headers.
    /// 1–128 chars, alphanumerics plus `.`, `_`, `-`.
    static let modelNameRegex = #/^[A-Za-z0-9._-]{1,128}$/#

    /// Validates `name` against `modelNameRegex`. Throws
    /// `TranscribeError.invalidModel` on failure. Surfaced so AppDelegate
    /// can validate at construction time and present a clear error.
    static func validate(modelName name: String) throws {
        guard (try? modelNameRegex.wholeMatch(in: name)) != nil else {
            throw TranscribeError.invalidModel(value: name)
        }
    }

    /// Allow-list for the bearer token. RFC 6750 token68 grammar plus
    /// strict no-whitespace / no-CRLF policy. 1–512 chars. Symmetric to
    /// `modelNameRegex` (R4-F30): `setValue("Bearer \(bearer)", ...)`
    /// is header-injection if the value contains CRLF.
    static let bearerTokenRegex = #/^[A-Za-z0-9._~+/=-]{1,512}$/#

    /// Validates `token` against `bearerTokenRegex`. Throws
    /// `TranscribeError.invalidBearer` on failure.
    static func validate(bearerToken token: String) throws {
        guard (try? bearerTokenRegex.wholeMatch(in: token)) != nil else {
            throw TranscribeError.invalidBearer(value: token)
        }
    }

    let endpoint: URL
    let model: String
    let bearer: String
    private let session: URLSession
    private let timeout: TimeInterval

    /// Validates `model` against `modelNameRegex` and `bearer` against
    /// `bearerTokenRegex` at construction time. Both values are
    /// interpolated directly into HTTP request bytes (multipart body and
    /// `Authorization` header respectively).
    init(endpoint: URL,
         model: String,
         bearer: String,
         session: URLSession = .shared,
         timeout: TimeInterval = 15) throws {
        try Self.validate(modelName: model)
        try Self.validate(bearerToken: bearer)
        self.endpoint = endpoint
        self.model = model
        self.bearer = bearer
        self.session = session
        self.timeout = timeout
    }

    /// Posts the WAV at `wavURL` and delivers the trimmed transcribed text
    /// (or an error) to `completion` on an arbitrary background thread.
    func transcribe(wav wavURL: URL,
                    completion: @escaping @Sendable (Result<String, TranscribeError>) -> Void) {
        let request: URLRequest
        do {
            request = try buildRequest(wavURL: wavURL)
        } catch let e as TranscribeError {
            completion(.failure(e))
            return
        } catch {
            completion(.failure(.requestFailed(message: error.localizedDescription)))
            return
        }

        Log.transcribe.log("POST \(self.endpoint.absoluteString, privacy: .public)")
        let task = session.dataTask(with: request) { data, response, err in
            let result = Self.parseResponse(data: data, response: response, error: err)
            if case .failure(let e) = result {
                Log.transcribe.error("transcribe: \(String(describing: e), privacy: .public)")
            }
            completion(result)
        }
        task.resume()
    }

    /// Probes the configured endpoint with a 0.5 s silent WAV (no
    /// disk I/O). Result shape is identical to `transcribe(wav:)` —
    /// `Result<String, TranscribeError>`. The probe does NOT
    /// special-case empty-text-as-success; that interpretation is UI
    /// policy and lives in `SettingsWindowController.renderResult`.
    /// Probe success here means HTTP 2xx + JSON parses to `Response`
    /// with non-empty trimmed `text`. Empty text surfaces as
    /// `TranscribeError.empty` exactly like dictation.
    ///
    /// Returns the in-flight `URLSessionDataTask?` so the caller can
    /// `cancel()` on window close. Returns `nil` only if request
    /// construction itself fails (unreachable in practice — `init`
    /// already validated model/bearer).
    ///
    /// On `URLError.cancelled`, completion is **suppressed**: the
    /// closure simply returns without invoking `completion`. The
    /// caller treats cancellation as "no signal", which the settings
    /// window does naturally because it cancels in `windowWillClose`.
    @discardableResult
    func probe(timeout: TimeInterval = 15,
               completion: @escaping @Sendable (Result<String, TranscribeError>) -> Void)
        -> URLSessionDataTask?
    {
        let wavBytes = SilentWAVGenerator.makeWAV(seconds: 0.5)
        let request: URLRequest
        do {
            request = try buildRequest(wavData: wavBytes,
                                       filename: "probe.wav",
                                       timeout: timeout)
        } catch let e as TranscribeError {
            completion(.failure(e))
            return nil
        } catch {
            completion(.failure(.requestFailed(message: error.localizedDescription)))
            return nil
        }

        Log.transcribe.log("PROBE \(self.endpoint.absoluteString, privacy: .public)")
        let task = session.dataTask(with: request) { data, response, err in
            // C19: suppress completion on user-initiated cancel.
            if let urlErr = err as? URLError, urlErr.code == .cancelled {
                return
            }
            let result = Self.parseResponse(data: data, response: response, error: err)
            if case .failure(let e) = result {
                Log.transcribe.error("probe: \(String(describing: e), privacy: .public)")
            }
            completion(result)
        }
        task.resume()
        return task
    }

    /// Returns the failing host name iff `error` is a URLError with
    /// code `.appTransportSecurityRequiresSecureConnection` (-1022).
    /// Used by the settings window to surface a precise ATS message
    /// pointing at `Resources/Info.plist.template`.
    static func atsBlockedHost(in error: Error) -> String? {
        guard let urlErr = error as? URLError else { return nil }
        // `URLError.Code.appTransportSecurityRequiresSecureConnection`
        // is -1022. We compare on rawValue rather than the enum case
        // because the case name has shifted across SDK versions.
        guard urlErr.code.rawValue == -1022 else { return nil }
        return urlErr.failureURLString.flatMap { URL(string: $0)?.host }
            ?? (urlErr.userInfo[NSURLErrorFailingURLErrorKey] as? URL)?.host
    }

    // MARK: Shared response parser

    /// Pure decoder of `(data, response, error)` into the canonical
    /// `Result<String, TranscribeError>`. Both `transcribe` and
    /// `probe` route through this. Single response-parsing path —
    /// Sauron compliant.
    ///
    /// On `URLError` code -1022 (App Transport Security blocked the
    /// connection), the message is enriched with the failing host
    /// name via `Transcriber.atsBlockedHost(in:)`. Callers that
    /// surface the message to a UI (the settings window) detect ATS
    /// by substring, which is reliable because Foundation localises
    /// "App Transport Security" into the same prefix on every locale
    /// VoiceRider supports (English-only as of v0.1.x).
    static func parseResponse(data: Data?, response: URLResponse?, error: Error?)
        -> Result<String, TranscribeError>
    {
        if let error {
            if let host = Self.atsBlockedHost(in: error) {
                return .failure(.requestFailed(
                    message: "App Transport Security blocked the connection to \(host). \(error.localizedDescription)"))
            }
            return .failure(.requestFailed(message: error.localizedDescription))
        }
        guard let http = response as? HTTPURLResponse else {
            return .failure(.requestFailed(message: "no HTTP response"))
        }
        guard (200..<300).contains(http.statusCode) else {
            let body = data.flatMap { String(data: $0, encoding: .utf8) }
            return .failure(.http(status: http.statusCode, body: body))
        }
        guard let data else {
            return .failure(.empty)
        }
        do {
            let decoded = try JSONDecoder().decode(Response.self, from: data)
            let trimmed = decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                return .failure(.empty)
            }
            return .success(trimmed)
        } catch {
            return .failure(.decode(message: error.localizedDescription))
        }
    }

    // MARK: Multipart

    /// Builds the multipart/form-data request from a WAV file on disk.
    /// `internal` so tests can inspect the body without invoking the
    /// network path. Reads the file then delegates to the Data form.
    func buildRequest(wavURL: URL) throws -> URLRequest {
        let wavData: Data
        do {
            wavData = try Data(contentsOf: wavURL)
        } catch {
            throw TranscribeError.requestFailed(message: error.localizedDescription)
        }
        return try buildRequest(wavData: wavData,
                                filename: wavURL.lastPathComponent,
                                timeout: timeout)
    }

    /// Builds the multipart/form-data request from in-memory bytes.
    /// Used by `probe()` (silent WAV, no disk) and indirectly by
    /// `buildRequest(wavURL:)` after reading the file. Single
    /// multipart-construction path — Sauron compliant.
    func buildRequest(wavData: Data,
                      filename: String,
                      timeout: TimeInterval) throws -> URLRequest {
        var req = URLRequest(url: endpoint, timeoutInterval: timeout)
        req.httpMethod = "POST"
        req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")

        let boundary = "voice-\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)",
                     forHTTPHeaderField: "Content-Type")

        req.httpBody = Self.multipartBody(boundary: boundary,
                                          model: model,
                                          wavData: wavData,
                                          filename: filename)
        return req
    }

    /// Pure builder: no I/O. Tests pin this against a fixed boundary to
    /// verify byte-for-byte correctness.
    static func multipartBody(boundary: String,
                              model: String,
                              wavData: Data,
                              filename: String) -> Data {
        var body = Data()
        func add(_ s: String) { body.append(Data(s.utf8)) }

        add("--\(boundary)\r\n")
        add("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
        add("\(model)\r\n")

        add("--\(boundary)\r\n")
        add("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n")
        add("Content-Type: audio/wav\r\n\r\n")
        body.append(wavData)
        add("\r\n--\(boundary)--\r\n")

        return body
    }
}
