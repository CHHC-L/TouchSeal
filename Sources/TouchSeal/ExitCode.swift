import Foundation

/// Stable process exit codes. These are part of TouchSeal's scripting contract
/// and must not be renumbered.
enum ExitCode: Int32, Equatable {
    /// The command completed.
    case success = 0
    /// An error that does not fit any other category.
    case generalError = 1
    /// Missing, unknown, or malformed command-line arguments (includes invalid names).
    case invalidArguments = 2
    /// No secret with the requested name exists.
    case secretNotFound = 3
    /// A secret with that name already exists and replacement was not confirmed.
    case secretAlreadyExists = 4
    /// The user dismissed the Touch ID prompt, or the system cancelled it.
    case authenticationCanceled = 5
    /// Touch ID is unusable on this Mac (absent, unenrolled, locked out, or not Touch ID).
    case biometryUnavailable = 6
    /// Touch ID ran but did not authenticate the user.
    case authenticationFailed = 7
    /// The Security framework returned an unexpected `OSStatus`.
    case keychainError = 8
    /// The two secret entries did not match.
    case secretMismatch = 9
    /// The user declined a plain (non-biometric) yes/no confirmation.
    case confirmationDeclined = 10
    /// The stored or entered secret is not valid UTF-8 text.
    case invalidSecretData = 11
}
