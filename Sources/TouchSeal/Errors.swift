import Foundation
import LocalAuthentication
import Security

/// Why Touch ID cannot be used at all.
enum BiometryUnavailableReason: Equatable {
    case noTouchIDHardware
    case notTouchID(String)
    case notEnrolled
    case lockedOut
    case passcodeNotSet
    case notInteractive
    case other(String)

    var message: String {
        switch self {
        case .noTouchIDHardware:
            return "Touch ID is unavailable on this Mac."
        case let .notTouchID(kind):
            return "TouchSeal requires Touch ID, but this Mac reports \(kind)."
        case .notEnrolled:
            return "No Touch ID fingerprints are enrolled."
        case .lockedOut:
            return "Touch ID is locked. Unlock it in macOS first."
        case .passcodeNotSet:
            return "A login password must be set on this Mac before Touch ID can be used."
        case .notInteractive:
            return "Touch ID needs a graphical login session. It is unavailable over SSH or in a non-interactive session."
        case let .other(detail):
            return "Touch ID is unavailable: \(detail)"
        }
    }
}

/// Every failure TouchSeal reports. Each case carries a human-readable message
/// for stderr and a stable exit code. Messages never contain secret material.
enum TouchSealError: Error {
    case invalidArguments(String)
    case invalidName(NameValidationFailure)
    case secretNotFound(name: String)
    case secretAlreadyExists(name: String)
    case authenticationCanceled
    case biometryUnavailable(BiometryUnavailableReason)
    case authenticationFailed(String)
    case keychain(status: OSStatus, operation: String)
    case secretMismatch
    case emptySecret
    case secretTooLong(maximum: Int)
    case invalidSecretData(String)
    case confirmationDeclined
    case terminalUnavailable
    case terminalReadFailed(String)
    case accessControlCreationFailed(String)
    /// macOS refused a Touch ID-protected Keychain item because the binary's
    /// code signature does not carry a keychain access group.
    case missingEntitlement
    /// A replacement deleted the old item but could not store the new one, and
    /// the old value could not be put back. The secret is gone.
    case replacementLostSecret(name: String, addStatus: OSStatus, restoreStatus: OSStatus)
    case general(String)

    var message: String {
        switch self {
        case let .invalidArguments(detail):
            return detail
        case let .invalidName(failure):
            return failure.message
        case let .secretNotFound(name):
            return "No secret named \"\(name)\" is sealed."
        case let .secretAlreadyExists(name):
            return "Secret \"\(name)\" already exists."
        case .authenticationCanceled:
            return "Authentication was canceled."
        case let .biometryUnavailable(reason):
            return reason.message
        case let .authenticationFailed(detail):
            return detail
        case let .keychain(status, operation):
            return "\(operation): \(Self.describe(status)) (OSStatus \(status))"
        case .secretMismatch:
            return "The two entries did not match. Nothing was sealed."
        case .emptySecret:
            return "An empty secret cannot be sealed."
        case let .secretTooLong(maximum):
            return "Secret is too long. The maximum is \(maximum) bytes."
        case let .invalidSecretData(detail):
            return detail
        case .confirmationDeclined:
            return "Canceled."
        case .terminalUnavailable:
            return "TouchSeal needs an interactive terminal for this command."
        case let .terminalReadFailed(detail):
            return "Unable to read from the terminal: \(detail)"
        case let .accessControlCreationFailed(detail):
            return "Unable to create the Touch ID access control: \(detail)"
        case .missingEntitlement:
            return """
            macOS refused this Touch ID-protected Keychain item because touchseal is not signed with a \
            keychain access group. Sign the binary with an Apple-issued identity, then try again \
            (see "Code signing" in the README). TouchSeal will not fall back to an unprotected item. \
            (OSStatus \(errSecMissingEntitlement))
            """
        case let .replacementLostSecret(name, addStatus, restoreStatus):
            return """
            Secret "\(name)" could not be replaced and the previous value could not be restored. \
            The old item was removed from the Keychain and must be sealed again. \
            (store OSStatus \(addStatus), restore OSStatus \(restoreStatus))
            """
        case let .general(detail):
            return detail
        }
    }

    var exitCode: ExitCode {
        switch self {
        case .invalidArguments, .invalidName:
            return .invalidArguments
        case .secretNotFound:
            return .secretNotFound
        case .secretAlreadyExists:
            return .secretAlreadyExists
        case .authenticationCanceled:
            return .authenticationCanceled
        case .biometryUnavailable:
            return .biometryUnavailable
        case .authenticationFailed:
            return .authenticationFailed
        case .keychain, .accessControlCreationFailed, .replacementLostSecret, .missingEntitlement:
            return .keychainError
        case .secretMismatch:
            return .secretMismatch
        case .emptySecret, .secretTooLong, .invalidSecretData:
            return .invalidSecretData
        case .confirmationDeclined:
            return .confirmationDeclined
        case .terminalUnavailable, .terminalReadFailed, .general:
            return .generalError
        }
    }

    /// Human-readable text for an `OSStatus`, via the Security framework.
    static func describe(_ status: OSStatus) -> String {
        if let text = SecCopyErrorMessageString(status, nil) as String? {
            return text
        }
        return "Unknown Keychain error."
    }
}

// MARK: - OSStatus mapping

enum KeychainErrorMapper {
    /// Translates a Keychain `OSStatus` into a `TouchSealError`.
    ///
    /// `operation` is a short description of what failed, e.g.
    /// "Unable to release secret". It must never contain secret material.
    static func map(status: OSStatus, name: String, operation: String) -> TouchSealError {
        switch status {
        case errSecItemNotFound:
            return .secretNotFound(name: name)
        case errSecDuplicateItem:
            return .secretAlreadyExists(name: name)
        case errSecUserCanceled:
            return .authenticationCanceled
        case errSecAuthFailed:
            // macOS reports a wrong finger and an invalidated `.biometryCurrentSet`
            // ACL with the same status, so both possibilities are named here.
            return .authenticationFailed(
                """
                Touch ID authentication failed for secret "\(name)". \
                If you added or removed a fingerprint since sealing it, the secret can no longer \
                be accessed and must be sealed again. (OSStatus \(status))
                """
            )
        case errSecInteractionNotAllowed:
            return .biometryUnavailable(.notInteractive)
        case errSecInteractionRequired:
            return .biometryUnavailable(.notInteractive)
        case errSecNotAvailable:
            return .keychain(status: status, operation: "The Keychain is not available (it may be locked)")
        case errSecMissingEntitlement:
            return .missingEntitlement
        default:
            return .keychain(status: status, operation: operation)
        }
    }
}

// MARK: - LAError mapping

enum AuthenticationErrorMapper {
    /// Translates an error from `LAContext` into a `TouchSealError`.
    static func map(_ error: NSError?) -> TouchSealError {
        guard let error else {
            return .biometryUnavailable(.other("unknown reason"))
        }
        guard error.domain == LAErrorDomain, let code = LAError.Code(rawValue: error.code) else {
            return .biometryUnavailable(.other(error.localizedDescription))
        }
        return map(code)
    }

    static func map(_ code: LAError.Code) -> TouchSealError {
        switch code {
        case .userCancel, .appCancel, .systemCancel:
            return .authenticationCanceled
        case .authenticationFailed:
            return .authenticationFailed("Touch ID did not recognize your fingerprint.")
        case .biometryNotAvailable:
            return .biometryUnavailable(.noTouchIDHardware)
        case .biometryNotEnrolled:
            return .biometryUnavailable(.notEnrolled)
        case .biometryLockout:
            return .biometryUnavailable(.lockedOut)
        case .passcodeNotSet:
            return .biometryUnavailable(.passcodeNotSet)
        case .notInteractive:
            return .biometryUnavailable(.notInteractive)
        case .userFallback:
            // Password fallback is deliberately unsupported for
            // `.biometryCurrentSet` items.
            return .authenticationFailed("Password fallback is not supported. TouchSeal requires Touch ID.")
        case .invalidContext:
            return .general("The authentication context was invalidated.")
        default:
            return .biometryUnavailable(.other("LAError code \(code.rawValue)"))
        }
    }
}
