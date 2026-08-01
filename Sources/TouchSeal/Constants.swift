import Foundation

/// Compile-time constants that define TouchSeal's public, stable surface.
///
/// `keychainService` is part of TouchSeal's on-disk contract. Changing it would
/// orphan every secret created by an earlier build, so it must stay fixed for
/// the lifetime of the project.
enum Constants {
    static let toolName = "touchseal"
    static let version = "0.1.0"

    /// Reverse-DNS namespace derived from the project's GitHub owner
    /// (https://github.com/CHHC-L/TouchSeal). Do not change after release.
    static let keychainService = "io.github.chhc-l.touchseal.secret"

    static let keychainDescription = "Secret managed by TouchSeal"

    static func keychainLabel(for name: String) -> String {
        "TouchSeal: \(name)"
    }

    /// Maximum number of Unicode characters allowed in a secret name.
    static let maximumNameLength = 128

    /// Maximum secret size in bytes. Bounded by the fixed-size buffer that
    /// `readpassphrase(3)` writes into; see `TerminalSecretInput`.
    static let maximumSecretByteCount = 8190
}
