import Testing
import Foundation
@testable import VoiceRider

/// Fixture-based coverage for `Transcriber.validate(bearerToken:)`.
///
/// The regex is `^[A-Za-z0-9._~+/=-]{1,512}$`. Token68 (RFC 6750
/// §2.1) plus length cap. The threat model is "anything that flows
/// into `Authorization: Bearer …` header without further sanitization,"
/// so the negative cases focus on header-injection and length abuse.
///
/// `.serialized` is not strictly needed (validate is a pure function),
/// but keeps console output deterministic.
@Suite("BearerTokenFixtures", .serialized)
struct BearerTokenFixtures {

    // MARK: Positive — accepts

    @Test("accepts the project default")
    func acceptsDefault() throws {
        try Transcriber.validate(bearerToken: "local-no-auth")
    }

    @Test("accepts realistic-looking tokens")
    func acceptsRealistic() throws {
        // OpenAI-style
        try Transcriber.validate(bearerToken: "sk-abcdef0123456789ABCDEF0123456789")
        // GitHub-style classic
        try Transcriber.validate(bearerToken: "ghp_AbCdEf0123456789AbCdEf0123456789AbCd")
        // JWT-ish base64url
        try Transcriber.validate(
            bearerToken: "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiJ4In0.signature_123")
        // Hex token
        try Transcriber.validate(bearerToken: "0123456789abcdef0123456789abcdef")
        // UUID with hyphens
        try Transcriber.validate(bearerToken: "550e8400-e29b-41d4-a716-446655440000")
    }

    @Test("accepts every individual allow-listed character")
    func acceptsEveryAllowedChar() throws {
        let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._~+/=-"
        // Each char alone is valid (length 1).
        for ch in alphabet {
            try Transcriber.validate(bearerToken: String(ch))
        }
        // The full alphabet smushed together is also valid.
        try Transcriber.validate(bearerToken: alphabet)
    }

    // MARK: Boundary — length

    @Test("accepts length boundary 1")
    func acceptsLengthOne() throws {
        try Transcriber.validate(bearerToken: "x")
    }

    @Test("accepts length boundary 512")
    func acceptsLength512() throws {
        let token = String(repeating: "a", count: 512)
        try Transcriber.validate(bearerToken: token)
    }

    @Test("rejects length 0 (empty)")
    func rejectsEmpty() {
        do {
            try Transcriber.validate(bearerToken: "")
            Issue.record("expected throw")
        } catch let Transcriber.TranscribeError.invalidBearer(value) {
            #expect(value == "")
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }

    @Test("rejects length 513 (over cap)")
    func rejectsLength513() {
        let token = String(repeating: "a", count: 513)
        do {
            try Transcriber.validate(bearerToken: token)
            Issue.record("expected throw")
        } catch is Transcriber.TranscribeError {
            // ok
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }

    // MARK: Negative — header injection

    @Test("rejects CRLF injection")
    func rejectsCRLF() {
        let injected = "tok\r\nX-Forwarded-User: admin"
        do {
            try Transcriber.validate(bearerToken: injected)
            Issue.record("expected throw")
        } catch let Transcriber.TranscribeError.invalidBearer(value) {
            #expect(value == injected)
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }

    @Test("rejects bare LF")
    func rejectsLF() {
        let injected = "tok\nX-Hijack: 1"
        do {
            try Transcriber.validate(bearerToken: injected)
            Issue.record("expected throw")
        } catch is Transcriber.TranscribeError {
            // ok
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }

    @Test("rejects bare CR")
    func rejectsCR() {
        let injected = "tok\rX-Hijack: 1"
        do {
            try Transcriber.validate(bearerToken: injected)
            Issue.record("expected throw")
        } catch is Transcriber.TranscribeError {
            // ok
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }

    @Test("rejects null byte")
    func rejectsNull() {
        let injected = "tok\u{0}injection"
        do {
            try Transcriber.validate(bearerToken: injected)
            Issue.record("expected throw")
        } catch is Transcriber.TranscribeError {
            // ok
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }

    // MARK: Negative — whitespace family

    @Test("rejects whitespace variants")
    func rejectsWhitespace() {
        for bad in [" ", "  ", "\t", " token", "token ", "to ken", "\u{2003}wide-space"] {
            do {
                try Transcriber.validate(bearerToken: bad)
                Issue.record("expected reject for \(bad.debugDescription)")
            } catch is Transcriber.TranscribeError {
                // ok
            } catch {
                Issue.record("wrong error: \(error)")
            }
        }
    }

    // MARK: Negative — disallowed punctuation

    @Test("rejects disallowed punctuation")
    func rejectsPunctuation() {
        // Quotes, semicolons, and other characters that headers might
        // interpret.
        for bad in ["tok;n", "tok\"q", "tok'q", "tok(p)", "tok<x>", "tok,c", "tok:c"] {
            do {
                try Transcriber.validate(bearerToken: bad)
                Issue.record("expected reject for \(bad.debugDescription)")
            } catch is Transcriber.TranscribeError {
                // ok
            } catch {
                Issue.record("wrong error: \(error)")
            }
        }
    }

    // MARK: Negative — Unicode

    @Test("rejects non-ASCII characters")
    func rejectsUnicode() {
        for bad in ["tókén", "тoken", "🔑secret", "token\u{200B}zero-width"] {
            do {
                try Transcriber.validate(bearerToken: bad)
                Issue.record("expected reject for \(bad.debugDescription)")
            } catch is Transcriber.TranscribeError {
                // ok
            } catch {
                Issue.record("wrong error: \(error)")
            }
        }
    }

    // MARK: Init wiring

    @Test("Transcriber.init throws on bad bearer with valid model")
    func initThrowsOnBadBearer() {
        let endpoint = URL(string: "http://example.test/")!
        do {
            _ = try Transcriber(endpoint: endpoint,
                                model: "canary-qwen-2.5b",
                                bearer: "bad bearer")
            Issue.record("expected throw")
        } catch let Transcriber.TranscribeError.invalidBearer(value) {
            #expect(value == "bad bearer")
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }

    @Test("Transcriber.init validates model before bearer")
    func initValidatesModelFirst() {
        // If both are bad, the model error wins (it's checked first).
        // This pins the diagnostic order so users with two bad
        // UserDefaults see the model error first and fix that, rather
        // than fixing bearer and getting hit with a fresh model error.
        let endpoint = URL(string: "http://example.test/")!
        do {
            _ = try Transcriber(endpoint: endpoint,
                                model: "bad model",
                                bearer: "bad bearer")
            Issue.record("expected throw")
        } catch let Transcriber.TranscribeError.invalidModel(value) {
            #expect(value == "bad model")
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }

    @Test("Transcriber.init accepts both default values")
    func initAcceptsDefaults() throws {
        let endpoint = URL(string: "http://linux:8000/v1/audio/transcriptions")!
        _ = try Transcriber(endpoint: endpoint,
                            model: "canary-qwen-2.5b",
                            bearer: "local-no-auth")
        // Reaching here is the assertion.
    }

    @Test("invalidBearer.errorDescription includes the rejected value")
    func errorDescriptionFormat() {
        let err = Transcriber.TranscribeError.invalidBearer(value: "abc def")
        #expect(err.errorDescription == "invalid bearer token: abc def")
    }
}
