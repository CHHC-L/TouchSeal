import Foundation

// TouchSeal — Seal secrets locally. Release them with a touch.
//
// Wiring only: every decision lives in `CLI`, which is driven through
// protocols so it can be tested without a Keychain or a terminal.

let terminal = TerminalSecretInput()

let cli = CLI(
    store: KeychainSecretStore(),
    input: terminal,
    confirmation: terminal,
    output: StandardOutputWriter()
)

let exitCode = cli.run(arguments: Array(CommandLine.arguments.dropFirst()))
exit(exitCode.rawValue)
