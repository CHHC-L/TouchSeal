import Foundation
import LocalAuthentication

/// Supplies a freshly configured `LAContext` for a single protected Keychain
/// operation.
///
/// TouchSeal never reuses a context between commands and never stores one, so
/// every protected read costs exactly one new Touch ID approval.
protocol AuthenticationContextProviding {
    /// Returns a new context, or throws if Touch ID cannot be used.
    ///
    /// - Parameter reason: Text shown in the system authentication prompt.
    func makeContext(reason: String) throws -> LAContext
}

struct TouchIDAuthenticator: AuthenticationContextProviding {
    func makeContext(reason: String) throws -> LAContext {
        let context = LAContext()

        // "Allow Once" semantics: never reuse a previous Touch ID match.
        context.touchIDAuthenticationAllowableReuseDuration = 0

        // Suppress the "Use Password…" affordance. `.biometryCurrentSet` items
        // cannot be unlocked with the login password anyway, so offering it
        // would only produce a dead end.
        context.localizedFallbackTitle = ""

        // Replaces the deprecated `kSecUseOperationPrompt` query key
        // (deprecated in macOS 11 in favour of this property).
        context.localizedReason = reason

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            throw AuthenticationErrorMapper.map(error)
        }

        // `canEvaluatePolicy` succeeding is not enough: a Face ID Mac would
        // also pass. TouchSeal v0.1 supports Touch ID only and refuses to
        // silently weaken its policy on other hardware.
        guard context.biometryType == .touchID else {
            throw TouchSealError.biometryUnavailable(.notTouchID(Self.describe(context.biometryType)))
        }

        return context
    }

    private static func describe(_ type: LABiometryType) -> String {
        switch type {
        case .none: return "no biometric sensor"
        case .touchID: return "Touch ID"
        case .faceID: return "Face ID"
        case .opticID: return "Optic ID"
        @unknown default: return "an unrecognized biometric type"
        }
    }
}

/// Phrasing for the system Touch ID prompt. Names appear here, secrets never do.
enum AuthenticationReason {
    static func release(_ name: String) -> String {
        "TouchSeal wants to release secret \"\(name)\""
    }

    static func replace(_ name: String) -> String {
        "TouchSeal wants to replace secret \"\(name)\""
    }

    static func delete(_ name: String) -> String {
        "TouchSeal wants to delete secret \"\(name)\""
    }
}
