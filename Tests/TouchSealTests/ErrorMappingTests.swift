import LocalAuthentication
import Security
import Testing
@testable import TouchSeal

@Suite("Error and exit-code mapping")
struct ErrorMappingTests {
    // MARK: Exit codes

    @Test("exit code numbers are a stable contract")
    func exitCodeNumbers() {
        // Changing any of these is a breaking change for scripts, so they are
        // pinned literally rather than derived.
        #expect(ExitCode.success.rawValue == 0)
        #expect(ExitCode.generalError.rawValue == 1)
        #expect(ExitCode.invalidArguments.rawValue == 2)
        #expect(ExitCode.secretNotFound.rawValue == 3)
        #expect(ExitCode.secretAlreadyExists.rawValue == 4)
        #expect(ExitCode.authenticationCanceled.rawValue == 5)
        #expect(ExitCode.biometryUnavailable.rawValue == 6)
        #expect(ExitCode.authenticationFailed.rawValue == 7)
        #expect(ExitCode.keychainError.rawValue == 8)
        #expect(ExitCode.secretMismatch.rawValue == 9)
        #expect(ExitCode.confirmationDeclined.rawValue == 10)
        #expect(ExitCode.invalidSecretData.rawValue == 11)
    }

    @Test("each error maps to its documented exit code")
    func errorExitCodes() {
        let expectations: [(TouchSealError, ExitCode)] = [
            (.invalidArguments("x"), .invalidArguments),
            (.invalidName(.empty), .invalidArguments),
            (.secretNotFound(name: "k"), .secretNotFound),
            (.secretAlreadyExists(name: "k"), .secretAlreadyExists),
            (.authenticationCanceled, .authenticationCanceled),
            (.biometryUnavailable(.notEnrolled), .biometryUnavailable),
            (.authenticationFailed("x"), .authenticationFailed),
            (.keychain(status: errSecIO, operation: "x"), .keychainError),
            (.accessControlCreationFailed("x"), .keychainError),
            (.missingEntitlement, .keychainError),
            (.replacementLostSecret(name: "k", addStatus: -1, restoreStatus: -1), .keychainError),
            (.secretMismatch, .secretMismatch),
            (.emptySecret, .invalidSecretData),
            (.secretTooLong(maximum: 10), .invalidSecretData),
            (.invalidSecretData("x"), .invalidSecretData),
            (.confirmationDeclined, .confirmationDeclined),
            (.terminalUnavailable, .generalError),
            (.terminalReadFailed("x"), .generalError),
            (.general("x"), .generalError),
        ]
        for (error, expected) in expectations {
            #expect(error.exitCode == expected, "for \(error)")
        }
    }

    // MARK: OSStatus mapping

    @Test("OSStatus values map to the right exit codes")
    func osStatusMapping() {
        let expectations: [(OSStatus, ExitCode)] = [
            (errSecItemNotFound, .secretNotFound),
            (errSecDuplicateItem, .secretAlreadyExists),
            (errSecUserCanceled, .authenticationCanceled),
            (errSecAuthFailed, .authenticationFailed),
            (errSecInteractionNotAllowed, .biometryUnavailable),
            (errSecInteractionRequired, .biometryUnavailable),
            (errSecNotAvailable, .keychainError),
            (errSecMissingEntitlement, .keychainError),
            (errSecIO, .keychainError),
        ]
        for (status, expected) in expectations {
            let error = KeychainErrorMapper.map(status: status, name: "k", operation: "op")
            #expect(error.exitCode == expected, "for OSStatus \(status)")
        }
    }

    @Test("a changed fingerprint set is explained on auth failure")
    func changedFingerprintsExplained() {
        // macOS reports a wrong finger and an invalidated `.biometryCurrentSet`
        // ACL with the same status, so the message must cover both.
        let message = KeychainErrorMapper.map(status: errSecAuthFailed, name: "k", operation: "op").message
        #expect(message.lowercased().contains("fingerprint"))
        #expect(message.lowercased().contains("sealed again"))
    }

    @Test("Keychain messages carry the numeric OSStatus")
    func messagesIncludeStatus() {
        let message = TouchSealError.keychain(status: errSecIO, operation: "Unable to seal secret").message
        #expect(message.contains("\(errSecIO)"), "got: \(message)")
    }

    @Test("OSStatus text comes from the Security framework")
    func secCopyErrorMessageStringIsUsed() {
        #expect(!TouchSealError.describe(errSecItemNotFound).isEmpty)
        #expect(TouchSealError.describe(errSecItemNotFound) != TouchSealError.describe(errSecAuthFailed))
    }

    // MARK: LAError mapping

    @Test("LAError codes map to the right exit codes")
    func laErrorMapping() {
        let expectations: [(LAError.Code, ExitCode)] = [
            (.userCancel, .authenticationCanceled),
            (.appCancel, .authenticationCanceled),
            (.systemCancel, .authenticationCanceled),
            (.authenticationFailed, .authenticationFailed),
            (.userFallback, .authenticationFailed),
            (.biometryNotAvailable, .biometryUnavailable),
            (.biometryNotEnrolled, .biometryUnavailable),
            (.biometryLockout, .biometryUnavailable),
            (.passcodeNotSet, .biometryUnavailable),
            (.notInteractive, .biometryUnavailable),
            (.invalidContext, .generalError),
        ]
        for (code, expected) in expectations {
            #expect(AuthenticationErrorMapper.map(code).exitCode == expected, "for LAError \(code.rawValue)")
        }
    }

    @Test("Touch ID messages match the documented wording")
    func documentedWording() {
        #expect(AuthenticationErrorMapper.map(.biometryNotAvailable).message == "Touch ID is unavailable on this Mac.")
        #expect(AuthenticationErrorMapper.map(.biometryNotEnrolled).message == "No Touch ID fingerprints are enrolled.")
        #expect(AuthenticationErrorMapper.map(.biometryLockout).message == "Touch ID is locked. Unlock it in macOS first.")
        #expect(AuthenticationErrorMapper.map(.userCancel).message == "Authentication was canceled.")
    }

    @Test("password fallback is never offered as a recovery")
    func noPasswordFallback() {
        let error = AuthenticationErrorMapper.map(.userFallback)
        #expect(error.message.contains("not supported"))
        #expect(error.exitCode == .authenticationFailed)
    }

    @Test("a non-LocalAuthentication error still reports unavailability")
    func foreignErrorDomain() {
        let error = NSError(domain: NSOSStatusErrorDomain, code: -1, userInfo: nil)
        #expect(AuthenticationErrorMapper.map(error).exitCode == .biometryUnavailable)
        #expect(AuthenticationErrorMapper.map(nil).exitCode == .biometryUnavailable)
    }

    @Test("non-Touch ID biometry is refused rather than accommodated")
    func faceIDIsRefused() {
        let error = TouchSealError.biometryUnavailable(.notTouchID("Face ID"))
        #expect(error.exitCode == .biometryUnavailable)
        #expect(error.message.contains("Face ID"))
        #expect(error.message.contains("requires Touch ID"))
    }

    @Test("a missing entitlement explains the code-signing requirement")
    func missingEntitlementIsActionable() {
        let error = KeychainErrorMapper.map(status: errSecMissingEntitlement, name: "k", operation: "op")
        #expect(error.exitCode == .keychainError)
        // The failure is unrecoverable without signing, so the message must say
        // so rather than looking like a transient Keychain glitch.
        #expect(error.message.contains("keychain access group"))
        #expect(error.message.contains("README"))
        // It must never suggest storing the secret unprotected instead.
        #expect(error.message.contains("will not fall back"))
    }

    @Test("a non-interactive session reports a clear reason")
    func nonInteractiveReason() {
        let message = TouchSealError.biometryUnavailable(.notInteractive).message
        #expect(message.contains("SSH"))
    }

    // MARK: Message hygiene

    @Test("no error message is empty or carries secret material")
    func messageHygiene() {
        let canary = "sk-ant-CANARY"
        let errors: [TouchSealError] = [
            .invalidArguments("bad"),
            .invalidName(.empty),
            .secretNotFound(name: "k"),
            .secretAlreadyExists(name: "k"),
            .authenticationCanceled,
            .biometryUnavailable(.lockedOut),
            .authenticationFailed("nope"),
            .keychain(status: errSecIO, operation: "op"),
            .secretMismatch,
            .emptySecret,
            .secretTooLong(maximum: 8190),
            .invalidSecretData("bad"),
            .confirmationDeclined,
            .terminalUnavailable,
            .terminalReadFailed("io"),
            .accessControlCreationFailed("nope"),
            .missingEntitlement,
            .replacementLostSecret(name: "k", addStatus: -1, restoreStatus: -2),
            .general("boom"),
        ]
        for error in errors {
            #expect(!error.message.isEmpty, "every error needs a message")
            #expect(!error.message.contains(canary))
        }
    }
}
