import Foundation
import Testing
@testable import TouchSeal

@Suite("Secret validation")
struct SecretValidationTests {
    @Test("rejects an empty secret")
    func rejectsEmpty() {
        let error = #expect(throws: TouchSealError.self) {
            try SecretValidator.validate(Data())
        }
        #expect(error?.exitCode == .invalidSecretData)
    }

    @Test(
        "accepts ordinary secrets",
        arguments: ["sk-ant-abc123", "a", "text with \"quotes\"", "密码", "emoji🔐key", " padded "]
    )
    func acceptsOrdinarySecrets(_ text: String) throws {
        try SecretValidator.validate(Data(text.utf8))
    }

    @Test("size limit is inclusive")
    func sizeBoundary() throws {
        let atLimit = Data(repeating: UInt8(ascii: "a"), count: Constants.maximumSecretByteCount)
        try SecretValidator.validate(atLimit)

        let overLimit = Data(repeating: UInt8(ascii: "a"), count: Constants.maximumSecretByteCount + 1)
        let error = #expect(throws: TouchSealError.self) {
            try SecretValidator.validate(overLimit)
        }
        #expect(error?.exitCode == .invalidSecretData)
    }

    // MARK: UTF-8 validation
    //
    // Validation runs over raw bytes so a secret is never materialized as a
    // `String`. These cases pin that hand-written decoder to the Unicode rules.

    @Test("accepts well-formed UTF-8", arguments: ["", "ascii", "é", "中文", "🔐", "a🔐é中"])
    func acceptsWellFormed(_ text: String) {
        #expect(SecretValidator.isValidUTF8(Data(text.utf8)))
    }

    @Test("rejects truncated sequences")
    func rejectsTruncated() {
        #expect(!SecretValidator.isValidUTF8(Data([0xC3])))
        #expect(!SecretValidator.isValidUTF8(Data([0xE4, 0xB8])))
        #expect(!SecretValidator.isValidUTF8(Data([0xF0, 0x9F, 0x94])))
    }

    @Test("rejects stray continuation bytes")
    func rejectsStrayContinuations() {
        #expect(!SecretValidator.isValidUTF8(Data([0x80])))
        #expect(!SecretValidator.isValidUTF8(Data([0xBF])))
        #expect(!SecretValidator.isValidUTF8(Data([0x41, 0x80, 0x41])))
    }

    @Test("rejects overlong encodings")
    func rejectsOverlong() {
        // U+002F encoded in two and three bytes.
        #expect(!SecretValidator.isValidUTF8(Data([0xC0, 0xAF])))
        #expect(!SecretValidator.isValidUTF8(Data([0xE0, 0x80, 0xAF])))
        // Overlong four-byte form of U+0000.
        #expect(!SecretValidator.isValidUTF8(Data([0xF0, 0x80, 0x80, 0x80])))
    }

    @Test("rejects surrogates and out-of-range scalars")
    func rejectsSurrogates() {
        // U+D800, a UTF-16 surrogate, is not a valid UTF-8 scalar.
        #expect(!SecretValidator.isValidUTF8(Data([0xED, 0xA0, 0x80])))
        // Above U+10FFFF.
        #expect(!SecretValidator.isValidUTF8(Data([0xF4, 0x90, 0x80, 0x80])))
        #expect(!SecretValidator.isValidUTF8(Data([0xF5, 0x80, 0x80, 0x80])))
        #expect(!SecretValidator.isValidUTF8(Data([0xFE])))
        #expect(!SecretValidator.isValidUTF8(Data([0xFF])))
    }

    @Test("accepts the boundary scalar at each encoded width")
    func boundaryScalars() {
        #expect(SecretValidator.isValidUTF8(Data([0x00])))                    // U+0000
        #expect(SecretValidator.isValidUTF8(Data([0x7F])))                    // U+007F
        #expect(SecretValidator.isValidUTF8(Data([0xC2, 0x80])))              // U+0080
        #expect(SecretValidator.isValidUTF8(Data([0xDF, 0xBF])))              // U+07FF
        #expect(SecretValidator.isValidUTF8(Data([0xE0, 0xA0, 0x80])))        // U+0800
        #expect(SecretValidator.isValidUTF8(Data([0xEF, 0xBF, 0xBF])))        // U+FFFF
        #expect(SecretValidator.isValidUTF8(Data([0xF0, 0x90, 0x80, 0x80])))  // U+10000
        #expect(SecretValidator.isValidUTF8(Data([0xF4, 0x8F, 0xBF, 0xBF])))  // U+10FFFF
    }

    @Test("agrees with Foundation on random input")
    func agreesWithFoundation() {
        // Cross-checks the hand-written decoder against the standard library.
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<4000 {
            let count = Int.random(in: 0...8, using: &generator)
            let bytes = (0..<count).map { _ in UInt8.random(in: 0...255, using: &generator) }
            let data = Data(bytes)
            let expected = String(data: data, encoding: .utf8) != nil
            #expect(
                SecretValidator.isValidUTF8(data) == expected,
                "disagreement on \(bytes.map { String(format: "%02X", $0) }.joined(separator: " "))"
            )
        }
    }
}
