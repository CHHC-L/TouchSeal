import Foundation

/// A parsed command line.
enum Command: Equatable {
    case set(name: String)
    case get(name: String)
    case delete(name: String, skipConfirmation: Bool)
    case exists(name: String)
    case help
    case version
}

/// Parses arguments and runs commands against injected collaborators.
struct CLI {
    let store: SecretStore
    let input: SecretInput
    let confirmation: ConfirmationPrompting
    let output: OutputWriter

    init(
        store: SecretStore,
        input: SecretInput,
        confirmation: ConfirmationPrompting,
        output: OutputWriter
    ) {
        self.store = store
        self.input = input
        self.confirmation = confirmation
        self.output = output
    }

    // MARK: - Entry point

    /// Runs one command. Never throws: every failure becomes an exit code and,
    /// unless it is a deliberately silent one, a line on stderr.
    func run(arguments: [String]) -> ExitCode {
        do {
            let command = try Self.parse(arguments)
            try execute(command)
            return .success
        } catch let silent as SilentExit {
            return silent.code
        } catch let error as TouchSealError {
            output.writeStandardError("touchseal: \(error.message)")
            return error.exitCode
        } catch {
            output.writeStandardError("touchseal: \(error.localizedDescription)")
            return .generalError
        }
    }

    func execute(_ command: Command) throws {
        switch command {
        case let .set(name):
            try runSet(name: name)
        case let .get(name):
            try runGet(name: name)
        case let .delete(name, skipConfirmation):
            try runDelete(name: name, skipConfirmation: skipConfirmation)
        case let .exists(name):
            try runExists(name: name)
        case .help:
            try output.writeStandardOutput(Data(Self.usage.utf8))
        case .version:
            try output.writeStandardOutput(Data("\(Constants.version)\n".utf8))
        }
    }

    // MARK: - Parsing

    static func parse(_ arguments: [String]) throws -> Command {
        guard let first = arguments.first else {
            throw TouchSealError.invalidArguments("Missing command. Run `touchseal help`.")
        }

        let rest = Array(arguments.dropFirst())

        switch first {
        case "help", "--help", "-h":
            return .help
        case "version", "--version", "-V":
            return .version
        case "set":
            return .set(name: try singleName(from: rest, command: "set", usage: "touchseal set <name>"))
        case "get":
            return .get(name: try singleName(from: rest, command: "get", usage: "touchseal get <name>"))
        case "exists":
            return .exists(name: try singleName(from: rest, command: "exists", usage: "touchseal exists <name>"))
        case "delete":
            let parsed = try split(rest, command: "delete", allowedFlags: ["--yes", "-y"])
            let name = try exactlyOne(
                parsed.operands,
                command: "delete",
                usage: "touchseal delete <name> [--yes]"
            )
            return .delete(name: name, skipConfirmation: !parsed.flags.isEmpty)
        default:
            if first.hasPrefix("-") {
                throw TouchSealError.invalidArguments("Unknown option \"\(first)\". Run `touchseal help`.")
            }
            throw TouchSealError.invalidArguments("Unknown command \"\(first)\". Run `touchseal help`.")
        }
    }

    private static func singleName(from arguments: [String], command: String, usage: String) throws -> String {
        let parsed = try split(arguments, command: command, allowedFlags: [])
        return try exactlyOne(parsed.operands, command: command, usage: usage)
    }

    /// Separates flags from operands. Everything after a literal `--` is an
    /// operand, so names beginning with `-` remain addressable.
    private static func split(
        _ arguments: [String],
        command: String,
        allowedFlags: Set<String>
    ) throws -> (operands: [String], flags: Set<String>) {
        var operands: [String] = []
        var flags: Set<String> = []
        var operandsOnly = false

        for argument in arguments {
            if operandsOnly {
                operands.append(argument)
                continue
            }
            if argument == "--" {
                operandsOnly = true
                continue
            }
            if argument.hasPrefix("-"), argument.count > 1 {
                guard allowedFlags.contains(argument) else {
                    throw TouchSealError.invalidArguments(
                        "Unknown option \"\(argument)\" for `\(command)`. Run `touchseal help`."
                    )
                }
                flags.insert(argument)
                continue
            }
            operands.append(argument)
        }

        return (operands, flags)
    }

    private static func exactlyOne(_ operands: [String], command: String, usage: String) throws -> String {
        guard let name = operands.first else {
            throw TouchSealError.invalidArguments("Missing secret name. Usage: \(usage)")
        }
        guard operands.count == 1 else {
            throw TouchSealError.invalidArguments(
                "`\(command)` takes exactly one secret name. Usage: \(usage)"
            )
        }
        if let failure = NameValidator.validate(name) {
            throw TouchSealError.invalidName(failure)
        }
        return name
    }

    // MARK: - set

    private func runSet(name: String) throws {
        let alreadyExists = try store.exists(name: name)

        var previousValue: Data?
        if alreadyExists {
            guard try confirmation.confirm("Secret \"\(name)\" already exists. Replace it? [y/N]") else {
                throw TouchSealError.secretAlreadyExists(name: name)
            }
            // Replacement is only allowed to someone who can unseal the current
            // value. There is no `--force`.
            previousValue = try store.get(name: name, reason: AuthenticationReason.replace(name))
        }

        let secret = try input.readSecret(prompt: "Enter secret: ")
        try SecretValidator.validate(secret)

        let confirmationSecret = try input.readSecret(prompt: "Confirm secret: ")
        guard secret == confirmationSecret else {
            throw TouchSealError.secretMismatch
        }

        if let previousValue {
            try replace(name: name, with: secret, previousValue: previousValue)
            output.writeStandardError("Secret \"\(name)\" resealed.")
        } else {
            try store.set(name: name, value: secret)
            output.writeStandardError("Secret \"\(name)\" sealed.")
        }
    }

    /// Deletes then re-adds, because the access control of an existing item
    /// cannot be updated in place.
    ///
    /// Keychain operations are not transactional, so a failure between the two
    /// steps is recovered by restoring the previous value. If that also fails,
    /// the loss is reported loudly rather than swallowed.
    private func replace(name: String, with secret: Data, previousValue: Data) throws {
        try store.delete(name: name)

        do {
            try store.set(name: name, value: secret)
        } catch {
            do {
                try store.set(name: name, value: previousValue)
            } catch let restoreError {
                throw TouchSealError.replacementLostSecret(
                    name: name,
                    addStatus: Self.status(of: error),
                    restoreStatus: Self.status(of: restoreError)
                )
            }
            output.writeStandardError(
                "touchseal: the new value could not be stored; the previous secret \"\(name)\" was restored."
            )
            throw error
        }
    }

    private static func status(of error: Error) -> OSStatus {
        if case let .keychain(status, _)? = error as? TouchSealError { return status }
        return errSecInternalError
    }

    // MARK: - get

    private func runGet(name: String) throws {
        let secret = try store.get(name: name)
        // Guards against corrupted or foreign data; TouchSeal only ever seals
        // valid UTF-8.
        guard SecretValidator.isValidUTF8(secret) else {
            throw TouchSealError.invalidSecretData("Secret \"\(name)\" is not valid UTF-8 text.")
        }
        // Only reached after Touch ID succeeded, so stdout stays empty on
        // every failure path above.
        try output.writeStandardOutput(secret)
    }

    // MARK: - delete

    private func runDelete(name: String, skipConfirmation: Bool) throws {
        guard try store.exists(name: name) else {
            throw TouchSealError.secretNotFound(name: name)
        }

        // `SecItemDelete` does not itself require authentication, so a
        // protected read supplies the Touch ID gate. The value is discarded.
        _ = try store.get(name: name, reason: AuthenticationReason.delete(name))

        if !skipConfirmation {
            guard try confirmation.confirm("Delete secret \"\(name)\"? [y/N]") else {
                throw TouchSealError.confirmationDeclined
            }
        }

        try store.delete(name: name)
        output.writeStandardError("Secret \"\(name)\" deleted.")
    }

    // MARK: - exists

    private func runExists(name: String) throws {
        guard try store.exists(name: name) else {
            // Silent by design: scripts read the exit code, and the absence of
            // a name is itself metadata worth not printing.
            throw SilentExit(code: .secretNotFound)
        }
    }

    // MARK: - Help

    static let usage = """
    touchseal \(Constants.version) — Seal secrets locally. Release them with a touch.

    USAGE
      touchseal <command> [options]

    COMMANDS
      set <name>             Seal a secret. Prompts twice; input is never echoed.
      get <name>             Release a secret to stdout after Touch ID approval.
      delete <name> [--yes]  Delete a secret. Always requires Touch ID.
      exists <name>          Exit 0 if sealed, 3 if not. No Touch ID, no output.
      help                   Show this help.
      version                Show the version.

    OPTIONS
      -h, --help             Show this help.
          --version          Show the version.
      -y, --yes              For `delete`, skip the typed confirmation only.
                             It never skips Touch ID.

    EXIT CODES
      0  success                    6  Touch ID unavailable
      1  general error              7  authentication failed
      2  invalid arguments          8  Keychain error
      3  secret not found           9  entries did not match
      4  secret already exists     10  confirmation declined
      5  authentication canceled   11  invalid secret data

    NOTES
      On success, `get` writes only the secret to stdout, with no trailing
      newline. Prompts, confirmations, and errors all go to stderr.

      Names are 1-128 characters with no line breaks, control characters, or
      leading/trailing whitespace. Put `--` before a name that starts with `-`.

      Secrets are stored only in the macOS Keychain, protected by the currently
      enrolled Touch ID fingerprints. TouchSeal makes no network requests.

    """
}

/// Exits with a specific code and prints nothing.
struct SilentExit: Error {
    let code: ExitCode
}
