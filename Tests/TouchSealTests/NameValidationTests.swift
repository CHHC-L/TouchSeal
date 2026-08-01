import Testing
@testable import TouchSeal

@Suite("Name validation")
struct NameValidationTests {
    @Test(
        "accepts typical names",
        arguments: ["anthropic-api-key", "github-token", "work/vpn/password", "a", "key with spaces", "密钥", "key🔐"]
    )
    func acceptsTypicalNames(_ name: String) {
        #expect(NameValidator.validate(name) == nil)
        #expect(NameValidator.isValid(name))
    }

    @Test("rejects an empty name")
    func rejectsEmpty() {
        #expect(NameValidator.validate("") == .empty)
    }

    @Test("length limit is inclusive")
    func lengthBoundary() {
        let atLimit = String(repeating: "a", count: Constants.maximumNameLength)
        #expect(NameValidator.validate(atLimit) == nil)

        let overLimit = String(repeating: "a", count: Constants.maximumNameLength + 1)
        #expect(
            NameValidator.validate(overLimit)
                == .tooLong(actual: Constants.maximumNameLength + 1, maximum: Constants.maximumNameLength)
        )
    }

    @Test("length counts grapheme clusters, not bytes")
    func lengthCountsCharacters() {
        // 128 emoji are 128 characters but far more than 128 bytes.
        #expect(NameValidator.validate(String(repeating: "🔐", count: 128)) == nil)
        #expect(NameValidator.validate(String(repeating: "🔐", count: 129)) != nil)
    }

    @Test("rejects line breaks", arguments: ["two\nlines", "two\rlines", "trailing\n", "line\u{2028}separator", "para\u{2029}separator"])
    func rejectsNewlines(_ name: String) {
        #expect(NameValidator.validate(name) == .containsNewline)
    }

    @Test("rejects NUL")
    func rejectsNUL() {
        #expect(NameValidator.validate("nul\0byte") == .containsNUL)
    }

    @Test("rejects other control characters", arguments: ["tab\there", "bell\u{0007}", "escape\u{001B}[0m"])
    func rejectsControlCharacters(_ name: String) {
        #expect(NameValidator.validate(name) == .containsControlCharacter)
    }

    @Test("rejects surrounding whitespace instead of trimming it", arguments: [" leading", "trailing ", " both ", "\u{00A0}nbsp"])
    func rejectsSurroundingWhitespace(_ name: String) {
        // Trimming would let "key" and "key " silently address the same item.
        #expect(NameValidator.validate(name) == .surroundingWhitespace)
    }

    @Test("interior whitespace is allowed")
    func allowsInteriorWhitespace() {
        #expect(NameValidator.validate("in between") == nil)
    }

    @Test("every failure has a message")
    func failuresHaveMessages() {
        let failures: [NameValidationFailure] = [
            .empty,
            .tooLong(actual: 200, maximum: 128),
            .containsNewline,
            .containsNUL,
            .containsControlCharacter,
            .surroundingWhitespace,
        ]
        for failure in failures {
            #expect(!failure.message.isEmpty)
        }
    }
}
