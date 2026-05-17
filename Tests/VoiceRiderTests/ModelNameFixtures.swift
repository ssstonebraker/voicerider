import Testing
import Foundation
@testable import VoiceRider

/// Fixture-based coverage for `Transcriber.validate(modelName:)`.
///
/// The regex is `^[A-Za-z0-9._-]{1,128}$`. Tighter than the bearer
/// regex because the model field is interpolated into the multipart
/// body where slashes / equals / etc. could be repurposed by a
/// malicious server. The threat model is "anything that flows into
/// `Content-Disposition: form-data; name="model"\r\n\r\n<value>` —
/// CRLF here forges multipart parts.
@Suite("ModelNameFixtures", .serialized)
struct ModelNameFixtures {

    // MARK: Positive — accepts

    @Test("accepts the project default")
    func acceptsDefault() throws {
        try Transcriber.validate(modelName: "canary-qwen-2.5b")
    }

    @Test("accepts realistic model names from the wild")
    func acceptsRealistic() throws {
        for ok in [
            "whisper-1",
            "whisper-large-v3",
            "whisper_large.v3",
            "GPT-4o-mini",
            "Llama-3.1-70B",
            "Mistral-7B-Instruct.v0.2",
            "openai-whisper",
            "Distil-Whisper",
            "qwen2.5-7b-instruct",
        ] {
            try Transcriber.validate(modelName: ok)
        }
    }

    @Test("accepts every individual allow-listed character")
    func acceptsEveryAllowedChar() throws {
        let alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-"
        for ch in alphabet {
            try Transcriber.validate(modelName: String(ch))
        }
        try Transcriber.validate(modelName: alphabet)
    }

    // MARK: Boundary — length

    @Test("accepts length boundary 1")
    func acceptsLengthOne() throws {
        try Transcriber.validate(modelName: "x")
    }

    @Test("accepts length boundary 128")
    func acceptsLength128() throws {
        let name = String(repeating: "a", count: 128)
        try Transcriber.validate(modelName: name)
    }

    @Test("rejects length 0 (empty)")
    func rejectsEmpty() {
        do {
            try Transcriber.validate(modelName: "")
            Issue.record("expected throw")
        } catch let Transcriber.TranscribeError.invalidModel(value) {
            #expect(value == "")
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }

    @Test("rejects length 129 (over cap)")
    func rejectsLength129() {
        let name = String(repeating: "a", count: 129)
        do {
            try Transcriber.validate(modelName: name)
            Issue.record("expected throw")
        } catch is Transcriber.TranscribeError {
            // ok
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }

    // MARK: Negative — multipart injection

    @Test("rejects CRLF (forges multipart parts)")
    func rejectsCRLF() {
        let injected = "model\r\n--BOUNDARY\r\nContent-Disposition: form-data; name=\"file\"; filename=\"x.wav\"\r\n\r\nFAKE"
        do {
            try Transcriber.validate(modelName: injected)
            Issue.record("expected throw")
        } catch let Transcriber.TranscribeError.invalidModel(value) {
            #expect(value == injected)
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }

    @Test("rejects bare LF and CR")
    func rejectsBareLineEndings() {
        for bad in ["model\nx", "model\rx", "\nmodel", "model\r"] {
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

    @Test("rejects null byte")
    func rejectsNull() {
        let injected = "model\u{0}x"
        do {
            try Transcriber.validate(modelName: injected)
            Issue.record("expected throw")
        } catch is Transcriber.TranscribeError {
            // ok
        } catch {
            Issue.record("wrong error: \(error)")
        }
    }

    // MARK: Negative — characters that are valid in bearer but not model

    @Test("rejects characters allowed in bearer but not model")
    func rejectsBearerOnlyChars() {
        // bearer regex permits ~ + / =, model does not.
        for bad in ["whisper~v3", "model+1", "path/with/slash", "key=value"] {
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

    // MARK: Negative — whitespace and Unicode

    @Test("rejects whitespace variants")
    func rejectsWhitespace() {
        for bad in [" ", "\t", " model", "model ", "mo del", "\u{2003}model"] {
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

    @Test("rejects non-ASCII characters")
    func rejectsUnicode() {
        for bad in ["mödel", "модель", "🤖model", "model\u{200B}zwsp"] {
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

    @Test("rejects path traversal-ish payloads")
    func rejectsPathTraversal() {
        for bad in ["../etc/passwd", "/abs/path", "model:8000", "model;rm -rf"] {
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

    // MARK: Error description format

    @Test("invalidModel.errorDescription includes the rejected value")
    func errorDescriptionFormat() {
        let err = Transcriber.TranscribeError.invalidModel(value: "bad value")
        #expect(err.errorDescription == "invalid model name: bad value")
    }
}
