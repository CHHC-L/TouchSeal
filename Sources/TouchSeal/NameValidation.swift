import Foundation

/// Why a secret name was rejected.
enum NameValidationFailure: Equatable {
    case empty
    case tooLong(actual: Int, maximum: Int)
    case containsNewline
    case containsNUL
    case containsControlCharacter
    case surroundingWhitespace

    var message: String {
        switch self {
        case .empty:
            return "Secret name must not be empty."
        case let .tooLong(actual, maximum):
            return "Secret name must be at most \(maximum) characters (got \(actual))."
        case .containsNewline:
            return "Secret name must not contain line breaks."
        case .containsNUL:
            return "Secret name must not contain NUL bytes."
        case .containsControlCharacter:
            return "Secret name must not contain control characters."
        case .surroundingWhitespace:
            return "Secret name must not begin or end with whitespace."
        }
    }
}

enum NameValidator {
    /// Validates a user-supplied secret name.
    ///
    /// Names are never trimmed: leading or trailing whitespace is an error so
    /// that `"key"` and `"key "` can never be confused for one another.
    static func validate(_ name: String) -> NameValidationFailure? {
        if name.isEmpty { return .empty }

        for scalar in name.unicodeScalars {
            if scalar.value == 0 { return .containsNUL }
            if scalar == "\n" || scalar == "\r" || scalar.value == 0x2028 || scalar.value == 0x2029 {
                return .containsNewline
            }
            // Reject C0/C1 controls (a superset of the forbidden characters
            // above) so names stay safe to echo into a terminal prompt.
            if scalar.properties.generalCategory == .control { return .containsControlCharacter }
        }

        if let first = name.first, first.isWhitespace { return .surroundingWhitespace }
        if let last = name.last, last.isWhitespace { return .surroundingWhitespace }

        let length = name.count
        if length > Constants.maximumNameLength {
            return .tooLong(actual: length, maximum: Constants.maximumNameLength)
        }

        return nil
    }

    static func isValid(_ name: String) -> Bool {
        validate(name) == nil
    }
}
