import Foundation
import LocalAuthentication
import Security

/// The storage operations TouchSeal needs, expressed without any reference to
/// the Security framework so the CLI can be tested against a mock.
protocol SecretStore {
    /// Creates a new Touch ID-protected item. Throws `.secretAlreadyExists` if
    /// one with that name is already present.
    func set(name: String, value: Data) throws
    /// Reads a secret. This is the only operation that requires Touch ID.
    func get(name: String, reason: String) throws -> Data
    /// Removes an item. Callers must have already required Touch ID via `get`.
    func delete(name: String) throws
    /// Reports whether an item exists, without reading it and without prompting.
    func exists(name: String) throws -> Bool
}

extension SecretStore {
    func get(name: String) throws -> Data {
        try get(name: name, reason: AuthenticationReason.release(name))
    }
}

/// `SecretStore` backed by the macOS Keychain.
///
/// Every item is a generic password in TouchSeal's own service namespace,
/// protected by `.biometryCurrentSet` and
/// `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`. TouchSeal never queries
/// outside that namespace.
struct KeychainSecretStore: SecretStore {
    let service: String
    let authenticator: AuthenticationContextProviding

    init(
        service: String = Constants.keychainService,
        authenticator: AuthenticationContextProviding = TouchIDAuthenticator()
    ) {
        self.service = service
        self.authenticator = authenticator
    }

    // MARK: Add

    func set(name: String, value: Data) throws {
        let accessControl = try makeAccessControl()

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: name,
            kSecAttrLabel as String: Constants.keychainLabel(for: name),
            kSecAttrDescription as String: Constants.keychainDescription,
            kSecAttrAccessControl as String: accessControl,
            kSecValueData as String: value,
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainErrorMapper.map(status: status, name: name, operation: "Unable to seal secret")
        }
    }

    // MARK: Read

    func get(name: String, reason: String) throws -> Data {
        // A brand new context per read, discarded when this scope exits.
        let context = try authenticator.makeContext(reason: reason)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: name,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context,
        ]

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess else {
            throw KeychainErrorMapper.map(status: status, name: name, operation: "Unable to release secret")
        }
        guard let data = result as? Data else {
            throw TouchSealError.invalidSecretData("The Keychain returned no data for secret \"\(name)\".")
        }
        return data
    }

    // MARK: Delete

    func delete(name: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: name,
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess else {
            throw KeychainErrorMapper.map(status: status, name: name, operation: "Unable to delete secret")
        }
    }

    // MARK: Existence

    func exists(name: String) throws -> Bool {
        // Metadata only: `kSecReturnData` is deliberately absent so the item's
        // protected payload is never decrypted. `interactionNotAllowed` makes
        // the call fail rather than raise a Touch ID prompt if some macOS
        // version decides authentication is required after all.
        let context = LAContext()
        context.interactionNotAllowed = true

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: name,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context,
        ]

        let status = SecItemCopyMatching(query as CFDictionary, nil)
        switch status {
        case errSecSuccess:
            return true
        case errSecItemNotFound:
            return false
        case errSecInteractionNotAllowed, errSecInteractionRequired, errSecAuthFailed:
            // The item is there; macOS just refused to hand it over without a
            // prompt. Report existence rather than weakening the item.
            return true
        default:
            throw KeychainErrorMapper.map(
                status: status,
                name: name,
                operation: "Unable to check whether the secret exists"
            )
        }
    }

    // MARK: Access control

    private func makeAccessControl() throws -> SecAccessControl {
        var error: Unmanaged<CFError>?
        // Accessibility is passed here, not as a separate `kSecAttrAccessible`
        // attribute; setting both is rejected by the Security framework.
        guard let accessControl = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .biometryCurrentSet,
            &error
        ) else {
            let detail = error?.takeRetainedValue().localizedDescription ?? "unknown reason"
            // Never fall back to an unprotected item.
            throw TouchSealError.accessControlCreationFailed(detail)
        }
        return accessControl
    }
}
