import Foundation

/// The transient UI state of the settings window's three text fields.
///
/// `endpointString` is stored as `String`, not `URL`, so the user's
/// typed text survives whitespace/edits before validation runs. Only
/// `validate()` and `resolve()` invoke `URL(string:)` — and only on a
/// trimmed copy.
///
/// **Sauron — single definition of "valid":** model and bearer are
/// validated by calling `Transcriber.validate(modelName:)` and
/// `Transcriber.validate(bearerToken:)` directly. The regex literals
/// live exactly once in the codebase, on `Transcriber`. If those
/// regexes ever change, this form's behavior updates automatically.
///
/// Pure value type. No I/O. Tested in `SettingsFormTests`.
struct SettingsForm: Equatable {

    var endpointString: String
    var model: String
    var bearer: String

    enum Field: String, CaseIterable, Sendable {
        case endpoint, model, bearer
    }

    enum FieldError: Error, Equatable, Sendable {
        case empty(field: Field)
        /// Trimmed string isn't a `URL`, has no `scheme`, scheme is
        /// not `http`/`https`, or host is empty.
        case malformedURL
        /// Failed `Transcriber.validate(modelName:)`.
        case modelRegex
        /// Failed `Transcriber.validate(bearerToken:)`.
        case bearerRegex
    }

    // MARK: Construction

    /// Builds a form pre-populated from the given persisted config.
    static func from(_ cfg: ServerConfig) -> SettingsForm {
        SettingsForm(
            endpointString: cfg.endpoint.absoluteString,
            model:          cfg.model,
            bearer:         cfg.bearer)
    }

    // MARK: Validation

    /// Returns every field error. Empty array means valid. The order
    /// is stable (endpoint → model → bearer) so the UI can render
    /// each error next to its field consistently.
    func validate() -> [FieldError] {
        var errors: [FieldError] = []

        // -- endpoint --------------------------------------------------
        let trimmed = endpointString.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            errors.append(.empty(field: .endpoint))
        } else if !Self.isAcceptableURLString(trimmed) {
            errors.append(.malformedURL)
        }

        // -- model -----------------------------------------------------
        if model.isEmpty {
            errors.append(.empty(field: .model))
        } else {
            do {
                try Transcriber.validate(modelName: model)
            } catch {
                errors.append(.modelRegex)
            }
        }

        // -- bearer (optional — empty means "no auth header") --------
        if !bearer.isEmpty {
            do {
                try Transcriber.validate(bearerToken: bearer)
            } catch {
                errors.append(.bearerRegex)
            }
        }

        return errors
    }

    var isValid: Bool { validate().isEmpty }

    /// True when the endpoint field passes URL validation in
    /// isolation (used for inline UI status next to that field).
    var isEndpointValid: Bool {
        !validate().contains { err in
            if case .empty(.endpoint) = err { return true }
            if case .malformedURL = err { return true }
            return false
        }
    }

    var isModelValid: Bool {
        !validate().contains { err in
            if case .empty(.model) = err { return true }
            if case .modelRegex = err { return true }
            return false
        }
    }

    var isBearerValid: Bool {
        !validate().contains { err in
            if case .bearerRegex = err { return true }
            return false
        }
    }

    // MARK: Resolve

    /// Materialises a `ServerConfig`. Throws the **first** error from
    /// `validate()` if invalid; otherwise constructs a fresh config
    /// using the trimmed endpoint string.
    func resolve() throws -> ServerConfig {
        let errors = validate()
        if let first = errors.first { throw first }

        let trimmed = endpointString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else {
            // Should be unreachable given validate() passed.
            throw FieldError.malformedURL
        }
        return ServerConfig(endpoint: url, model: model, bearer: bearer)
    }

    // MARK: Helpers

    /// Returns true iff `s` parses as a URL with `scheme` ∈
    /// {http, https} and a non-empty `host`. Delegates to
    /// `ServerConfig.isAcceptableURLString` so the load-from-defaults
    /// path and the form-validation path enforce the same rule
    /// (Sauron — single definition of "acceptable URL").
    static func isAcceptableURLString(_ s: String) -> Bool {
        ServerConfig.isAcceptableURLString(s)
    }
}
