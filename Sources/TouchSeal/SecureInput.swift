import Darwin
import Foundation

/// Reads a secret from the user without echoing it.
protocol SecretInput {
    /// Prompts on the controlling terminal and returns the raw bytes entered.
    func readSecret(prompt: String) throws -> Data
}

/// Asks the user a yes/no question. Always defaults to "no".
protocol ConfirmationPrompting {
    func confirm(_ question: String) throws -> Bool
}

/// Secure terminal input built on `readpassphrase(3)`.
///
/// `readpassphrase` disables echo, restores the terminal on normal return and
/// on signals (including Ctrl+C, which it re-raises after restoring), and
/// reads from `/dev/tty` so a redirected stdin cannot feed it. `RPP_REQUIRE_TTY`
/// makes it fail rather than silently succeed in a non-interactive session.
struct TerminalSecretInput: SecretInput, ConfirmationPrompting {
    /// One byte larger than the maximum secret, leaving room for the NUL
    /// terminator and making an over-long entry detectable.
    private static let bufferSize = Constants.maximumSecretByteCount + 2

    func readSecret(prompt: String) throws -> Data {
        let buffer = UnsafeMutablePointer<CChar>.allocate(capacity: Self.bufferSize)
        buffer.initialize(repeating: 0, count: Self.bufferSize)
        defer {
            // Best-effort scrub of our own buffer. This does not extend to
            // copies the Swift runtime or the kernel may hold.
            Self.scrub(buffer, count: Self.bufferSize)
            buffer.deallocate()
        }

        let flags = Int32(RPP_REQUIRE_TTY) | Int32(RPP_ECHO_OFF)
        guard readpassphrase(prompt, buffer, Self.bufferSize, flags) != nil else {
            let code = errno
            if code == ENOTTY || code == ENXIO || code == ENOENT {
                throw TouchSealError.terminalUnavailable
            }
            throw TouchSealError.terminalReadFailed(String(cString: strerror(code)))
        }

        let length = strnlen(buffer, Self.bufferSize)
        // `readpassphrase` truncates silently, so a full buffer means the user
        // typed at least `bufferSize - 1` bytes. Refuse rather than store a
        // partial secret.
        if length >= Self.bufferSize - 1 {
            throw TouchSealError.secretTooLong(maximum: Constants.maximumSecretByteCount)
        }

        return buffer.withMemoryRebound(to: UInt8.self, capacity: Self.bufferSize) { bytes in
            Data(bytes: bytes, count: length)
        }
    }

    func confirm(_ question: String) throws -> Bool {
        guard let tty = fopen("/dev/tty", "r+") else {
            throw TouchSealError.terminalUnavailable
        }
        defer { fclose(tty) }

        // The question goes to the terminal, never to stdout.
        fputs("\(question) ", tty)
        fflush(tty)

        var line: UnsafeMutablePointer<CChar>?
        var capacity = 0
        defer { free(line) }

        let read = getline(&line, &capacity, tty)
        // EOF or a bare Return keeps the default answer: no.
        guard read > 0, let line else { return false }

        let answer = String(cString: line).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return answer == "y" || answer == "yes"
    }

    private static func scrub(_ pointer: UnsafeMutablePointer<CChar>, count: Int) {
        // `memset_s` is not elided by the optimizer, unlike `memset`.
        _ = memset_s(pointer, count, 0, count)
    }
}

// MARK: - Secret validation

enum SecretValidator {
    /// Checks a secret before it is sealed or emitted.
    ///
    /// UTF-8 validity is checked over the raw bytes so the secret is never
    /// materialized as a `String`.
    static func validate(_ data: Data) throws {
        if data.isEmpty { throw TouchSealError.emptySecret }
        if data.count > Constants.maximumSecretByteCount {
            throw TouchSealError.secretTooLong(maximum: Constants.maximumSecretByteCount)
        }
        guard isValidUTF8(data) else {
            throw TouchSealError.invalidSecretData("The secret is not valid UTF-8 text.")
        }
    }

    /// True if `data` is a well-formed UTF-8 sequence, per the Unicode
    /// definition (rejects overlong forms, surrogates, and values above U+10FFFF).
    static func isValidUTF8(_ data: Data) -> Bool {
        var index = data.startIndex
        let end = data.endIndex

        while index < end {
            let byte = data[index]
            let width: Int
            var lowerBound: UInt8 = 0x80
            var upperBound: UInt8 = 0xBF

            switch byte {
            case 0x00...0x7F:
                width = 1
            case 0xC2...0xDF:
                width = 2
            case 0xE0:
                width = 3; lowerBound = 0xA0
            case 0xE1...0xEC, 0xEE...0xEF:
                width = 3
            case 0xED:
                width = 3; upperBound = 0x9F
            case 0xF0:
                width = 4; lowerBound = 0x90
            case 0xF1...0xF3:
                width = 4
            case 0xF4:
                width = 4; upperBound = 0x8F
            default:
                return false
            }

            guard data.index(index, offsetBy: width, limitedBy: end) != nil else { return false }

            var offset = 1
            while offset < width {
                let continuation = data[data.index(index, offsetBy: offset)]
                let low = offset == 1 ? lowerBound : 0x80
                let high = offset == 1 ? upperBound : 0xBF
                guard continuation >= low, continuation <= high else { return false }
                offset += 1
            }

            index = data.index(index, offsetBy: width)
        }

        return true
    }
}
