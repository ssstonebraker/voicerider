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
            if let err {
                Log.transcribe.error("request failed: \(err.localizedDescription, privacy: .public)")
                completion(.failure(.requestFailed(message: err.localizedDescription)))
                return
            }
            guard let http = response as? HTTPURLResponse else {
                completion(.failure(.requestFailed(message: "no HTTP response")))
                return
            }
            guard (200..<300).contains(http.statusCode) else {
                let body = data.flatMap { String(data: $0, encoding: .utf8) }
                Log.transcribe.error("http \(http.statusCode, privacy: .public)")
                completion(.failure(.http(status: http.statusCode, body: body)))
                return
            }
            guard let data else {
                completion(.failure(.empty))
                return
            }
            do {
                let decoded = try JSONDecoder().decode(Response.self, from: data)
                let trimmed = decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    completion(.failure(.empty))
                } else {
                    completion(.success(trimmed))
                }
            } catch {
                completion(.failure(.decode(message: error.localizedDescription)))
            }
        }
        task.resume()
    }

    // MARK: Multipart

    /// Builds the multipart/form-data request. `internal` so tests can
    /// inspect the body without invoking the network path.
    func buildRequest(wavURL: URL) throws -> URLRequest {
        var req = URLRequest(url: endpoint, timeoutInterval: timeout)
        req.httpMethod = "POST"
        req.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")

        let boundary = "voice-\(UUID().uuidString)"
        req.setValue("multipart/form-data; boundary=\(boundary)",
                     forHTTPHeaderField: "Content-Type")

        let wavData: Data
        do {
            wavData = try Data(contentsOf: wavURL)
        } catch {
            throw TranscribeError.requestFailed(message: error.localizedDescription)
        }

        req.httpBody = Self.multipartBody(boundary: boundary,
                                          model: model,
                                          wavData: wavData,
                                          filename: wavURL.lastPathComponent)
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
