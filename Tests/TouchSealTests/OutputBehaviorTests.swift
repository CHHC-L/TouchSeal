import Foundation
import Security
import Testing
@testable import TouchSeal

@Suite("Output and command behavior")
struct OutputBehaviorTests {
    private let secret = "sk-ant-example-0123456789"

    // MARK: get

    @Test("get writes only the secret to stdout")
    func getWritesOnlySecret() {
        let harness = TestHarness(storage: ["api-key": Data(secret.utf8)])

        #expect(harness.run("get", "api-key") == .success)
        #expect(harness.output.standardOutput == Data(secret.utf8))
        #expect(harness.output.standardErrorLines.isEmpty, "stderr must stay empty on success")
    }

    @Test("get adds no trailing newline")
    func getAddsNoNewline() {
        let harness = TestHarness(storage: ["api-key": Data(secret.utf8)])

        #expect(harness.run("get", "api-key") == .success)
        #expect(harness.output.standardOutput.last != UInt8(ascii: "\n"))
        #expect(harness.output.standardOutput.count == secret.utf8.count)
    }

    @Test("get preserves secret bytes exactly")
    func getPreservesBytes() {
        // No trimming, no normalization, no re-encoding.
        let awkward = "  padded secret with spaces\tand a tab  "
        let harness = TestHarness(storage: ["api-key": Data(awkward.utf8)])

        #expect(harness.run("get", "api-key") == .success)
        #expect(harness.output.standardOutput == Data(awkward.utf8))
    }

    @Test("a missing secret leaves stdout empty")
    func getMissingSecret() {
        let harness = TestHarness()

        #expect(harness.run("get", "api-key") == .secretNotFound)
        #expect(harness.output.standardOutput.isEmpty)
        #expect(!harness.output.standardErrorLines.isEmpty)
    }

    @Test("a canceled authentication emits no bytes")
    func getCanceled() {
        let harness = TestHarness(storage: ["api-key": Data(secret.utf8)])
        harness.store.getError = .authenticationCanceled

        #expect(harness.run("get", "api-key") == .authenticationCanceled)
        #expect(harness.output.standardOutput.isEmpty)
        #expect(harness.output.standardErrorText == "touchseal: Authentication was canceled.")
    }

    @Test("unavailable Touch ID emits no bytes")
    func getUnavailableBiometry() {
        let harness = TestHarness(storage: ["api-key": Data(secret.utf8)])
        harness.store.getError = .biometryUnavailable(.noTouchIDHardware)

        #expect(harness.run("get", "api-key") == .biometryUnavailable)
        #expect(harness.output.standardOutput.isEmpty)
    }

    @Test("stored data that is not UTF-8 is refused, not emitted")
    func getInvalidStoredData() {
        let harness = TestHarness(storage: ["api-key": Data([0xFF, 0xFE, 0x00])])

        #expect(harness.run("get", "api-key") == .invalidSecretData)
        #expect(harness.output.standardOutput.isEmpty)
    }

    @Test("get uses the documented Touch ID prompt")
    func getPromptWording() {
        let harness = TestHarness(storage: ["api-key": Data(secret.utf8)])

        _ = harness.run("get", "api-key")
        #expect(harness.store.authenticationReasons == ["TouchSeal wants to release secret \"api-key\""])
    }

    // MARK: set

    @Test("set seals a secret and reports only on stderr")
    func setSeals() {
        let harness = TestHarness(entries: [secret, secret])

        #expect(harness.run("set", "api-key") == .success)
        #expect(harness.store.storage["api-key"] == Data(secret.utf8))
        #expect(harness.output.standardOutput.isEmpty, "set must never write to stdout")
        #expect(harness.output.standardErrorText == "Secret \"api-key\" sealed.")
    }

    @Test("set prompts twice")
    func setPromptsTwice() {
        let harness = TestHarness(entries: [secret, secret])

        _ = harness.run("set", "api-key")
        #expect(harness.input.prompts == ["Enter secret: ", "Confirm secret: "])
    }

    @Test("mismatched entries store nothing")
    func setMismatch() {
        let harness = TestHarness(entries: [secret, "different"])

        #expect(harness.run("set", "api-key") == .secretMismatch)
        #expect(harness.store.storage["api-key"] == nil)
        #expect(harness.output.standardOutput.isEmpty)
    }

    @Test("an empty secret is refused before the second prompt")
    func setEmptySecret() {
        let harness = TestHarness(entries: ["", ""])

        #expect(harness.run("set", "api-key") == .invalidSecretData)
        #expect(harness.store.storage["api-key"] == nil)
        #expect(harness.input.prompts == ["Enter secret: "])
    }

    @Test("non-UTF-8 input is refused")
    func setInvalidInput() {
        let harness = TestHarness()
        harness.input.entries = [Data([0xC3, 0x28]), Data([0xC3, 0x28])]

        #expect(harness.run("set", "api-key") == .invalidSecretData)
        #expect(harness.store.storage["api-key"] == nil)
    }

    // MARK: set over an existing secret

    @Test("replacing defaults to no")
    func replaceDefaultsToNo() {
        let harness = TestHarness(storage: ["api-key": Data("old".utf8)], entries: [secret, secret])
        // No scripted answer, so the confirmation returns its default: no.

        #expect(harness.run("set", "api-key") == .secretAlreadyExists)
        #expect(harness.store.storage["api-key"] == Data("old".utf8))
        #expect(harness.confirmation.questions == ["Secret \"api-key\" already exists. Replace it? [y/N]"])
        // The user is never asked to type a secret they have declined to store.
        #expect(harness.input.prompts.isEmpty)
    }

    @Test("replacing requires Touch ID on the existing secret first")
    func replaceRequiresAuthentication() {
        let harness = TestHarness(
            storage: ["api-key": Data("old".utf8)],
            entries: [secret, secret],
            answers: [true]
        )

        #expect(harness.run("set", "api-key") == .success)
        #expect(harness.store.storage["api-key"] == Data(secret.utf8))
        #expect(
            harness.store.calls == [.exists("api-key"), .get("api-key"), .delete("api-key"), .set("api-key")],
            "the protected read must come before the delete"
        )
        #expect(harness.store.authenticationReasons == ["TouchSeal wants to replace secret \"api-key\""])
        #expect(harness.output.standardErrorText == "Secret \"api-key\" resealed.")
        #expect(harness.output.standardOutput.isEmpty)
    }

    @Test("a failed Touch ID leaves the old secret intact")
    func replaceAuthenticationFailure() {
        let harness = TestHarness(
            storage: ["api-key": Data("old".utf8)],
            entries: [secret, secret],
            answers: [true]
        )
        harness.store.getError = .authenticationCanceled

        #expect(harness.run("set", "api-key") == .authenticationCanceled)
        #expect(harness.store.storage["api-key"] == Data("old".utf8))
        #expect(!harness.store.calls.contains(.delete("api-key")))
    }

    @Test("a failed replacement restores the previous secret")
    func replaceRollback() {
        let harness = TestHarness(
            storage: ["api-key": Data("old".utf8)],
            entries: [secret, secret],
            answers: [true]
        )
        // Storing the new value fails; the restore that follows succeeds.
        harness.store.setErrors = [.keychain(status: errSecIO, operation: "Unable to seal secret"), nil]

        #expect(harness.run("set", "api-key") == .keychainError)
        #expect(harness.store.storage["api-key"] == Data("old".utf8), "the old secret must come back")
        #expect(harness.output.standardOutput.isEmpty)
        #expect(harness.output.standardErrorText.contains("restored"))
    }

    @Test("an unrecoverable replacement is reported loudly")
    func replaceUnrecoverable() {
        let harness = TestHarness(
            storage: ["api-key": Data("old".utf8)],
            entries: [secret, secret],
            answers: [true]
        )
        // Both the store and the restore fail: the secret is genuinely gone.
        let failure = TouchSealError.keychain(status: errSecIO, operation: "Unable to seal secret")
        harness.store.setErrors = [failure, failure]

        #expect(harness.run("set", "api-key") == .keychainError)
        #expect(harness.store.storage["api-key"] == nil)
        #expect(harness.output.standardErrorText.contains("must be sealed again"))
    }

    // MARK: delete

    @Test("delete requires Touch ID, then confirmation")
    func deleteFlow() {
        let harness = TestHarness(storage: ["api-key": Data(secret.utf8)], answers: [true])

        #expect(harness.run("delete", "api-key") == .success)
        #expect(harness.store.storage["api-key"] == nil)
        #expect(harness.store.calls == [.exists("api-key"), .get("api-key"), .delete("api-key")])
        #expect(harness.confirmation.questions == ["Delete secret \"api-key\"? [y/N]"])
        #expect(harness.output.standardOutput.isEmpty)
        #expect(harness.output.standardErrorText == "Secret \"api-key\" deleted.")
    }

    @Test("delete defaults to no")
    func deleteDefaultsToNo() {
        let harness = TestHarness(storage: ["api-key": Data(secret.utf8)])

        #expect(harness.run("delete", "api-key") == .confirmationDeclined)
        #expect(harness.store.storage["api-key"] == Data(secret.utf8))
    }

    @Test("--yes skips only the typed confirmation")
    func yesSkipsOnlyConfirmation() {
        let harness = TestHarness(storage: ["api-key": Data(secret.utf8)])

        #expect(harness.run("delete", "api-key", "--yes") == .success)
        #expect(harness.confirmation.questions.isEmpty, "--yes skips the question")
        #expect(harness.store.calls.contains(.get("api-key")), "--yes must not skip the authenticated read")
        #expect(harness.store.authenticationReasons == ["TouchSeal wants to delete secret \"api-key\""])
    }

    @Test("--yes cannot bypass a failed authentication")
    func yesCannotBypassAuthentication() {
        let harness = TestHarness(storage: ["api-key": Data(secret.utf8)])
        harness.store.getError = .authenticationFailed("nope")

        #expect(harness.run("delete", "api-key", "--yes") == .authenticationFailed)
        #expect(harness.store.storage["api-key"] == Data(secret.utf8), "nothing may be deleted")
        #expect(!harness.store.calls.contains(.delete("api-key")))
    }

    @Test("deleting a missing secret never prompts for Touch ID")
    func deleteMissingSecret() {
        let harness = TestHarness()

        #expect(harness.run("delete", "api-key") == .secretNotFound)
        #expect(harness.store.calls == [.exists("api-key")])
    }

    @Test("delete never emits the secret it read to authenticate")
    func deleteEmitsNothing() {
        let harness = TestHarness(storage: ["api-key": Data(secret.utf8)], answers: [true])

        _ = harness.run("delete", "api-key")
        #expect(harness.output.standardOutput.isEmpty)
        #expect(!harness.output.standardErrorText.contains(secret))
    }

    // MARK: exists

    @Test("exists succeeds silently when present")
    func existsPresent() {
        let harness = TestHarness(storage: ["api-key": Data(secret.utf8)])

        #expect(harness.run("exists", "api-key") == .success)
        #expect(harness.output.standardOutput.isEmpty)
        #expect(harness.output.standardErrorLines.isEmpty)
    }

    @Test("exists fails silently when absent")
    func existsAbsent() {
        let harness = TestHarness()

        #expect(harness.run("exists", "api-key") == .secretNotFound)
        #expect(harness.output.standardOutput.isEmpty)
        #expect(harness.output.standardErrorLines.isEmpty, "absence must not be announced")
    }

    @Test("exists never triggers an authenticated read")
    func existsDoesNotAuthenticate() {
        let harness = TestHarness(storage: ["api-key": Data(secret.utf8)])

        _ = harness.run("exists", "api-key")
        #expect(harness.store.calls == [.exists("api-key")])
        #expect(harness.store.authenticationReasons.isEmpty)
    }

    @Test("a Keychain failure during exists is still reported")
    func existsKeychainFailure() {
        let harness = TestHarness()
        harness.store.existsError = .keychain(status: errSecIO, operation: "op")

        #expect(harness.run("exists", "api-key") == .keychainError)
        #expect(!harness.output.standardErrorLines.isEmpty)
    }

    // MARK: help and version

    @Test("help goes to stdout")
    func helpToStdout() {
        let harness = TestHarness()

        #expect(harness.run("help") == .success)
        #expect(harness.output.standardOutputText.contains("USAGE"))
        #expect(harness.output.standardErrorLines.isEmpty)
    }

    @Test("version prints only the version")
    func versionOutput() {
        let harness = TestHarness()

        #expect(harness.run("version") == .success)
        #expect(harness.output.standardOutputText == "\(Constants.version)\n")
    }

    @Test("usage errors go to stderr only")
    func usageErrorsToStderr() {
        let harness = TestHarness()

        #expect(harness.run("frobnicate") == .invalidArguments)
        #expect(harness.output.standardOutput.isEmpty)
        #expect(harness.output.standardErrorText.hasPrefix("touchseal: "))
    }

    @Test("no arguments prints to stderr only")
    func noArgumentsToStderr() {
        let harness = TestHarness()

        #expect(harness.cli.run(arguments: []) == .invalidArguments)
        #expect(harness.output.standardOutput.isEmpty)
        #expect(!harness.output.standardErrorLines.isEmpty)
    }

    // MARK: Namespace

    @Test("the Keychain service namespace is fixed")
    func keychainNamespaceIsFixed() {
        // Changing this string would orphan every previously sealed secret.
        #expect(Constants.keychainService == "io.github.chhc-l.touchseal.secret")
    }

    @Test("Keychain metadata never carries secret material")
    func keychainMetadataIsClean() {
        #expect(Constants.keychainLabel(for: "api-key") == "TouchSeal: api-key")
        #expect(!Constants.keychainLabel(for: "api-key").contains(secret))
        #expect(!Constants.keychainDescription.contains(secret))
    }
}
