# Contributing to TouchSeal

Thanks for your interest. TouchSeal is small on purpose, and most of its rules
exist to keep it that way.

## Before anything else

**Never paste API keys, passwords, Keychain contents, or other secrets into an
issue, a pull request, a commit, or a test fixture.** Use an obvious placeholder
such as `sk-ant-REDACTED`. For security issues, follow [SECURITY.md](SECURITY.md)
rather than opening a public issue.

## Getting set up

```bash
swift build
./Scripts/test.sh
```

The tests use swift-testing and touch neither the Keychain, Touch ID, nor the
network. `Scripts/test.sh` adds the search paths swift-testing needs on a Mac
with only the Command Line Tools; with full Xcode, plain `swift test` also works.

To exercise the tool end to end you need a code-signing identity — see
"Code signing" in [README.md](README.md). Without one, `set` fails with
`errSecMissingEntitlement`.

## Project layout

```text
Sources/TouchSeal/
    main.swift            Wiring only; every decision lives in CLI.
    CLI.swift             Argument parsing and command routing.
    KeychainStore.swift   SecItemAdd, SecItemCopyMatching, SecItemDelete.
    Authentication.swift  Creates and checks LAContext.
    SecureInput.swift     Secure terminal input and secret validation.
    Output.swift          Keeps stdout and stderr strictly separated.
    Errors.swift          OSStatus, LAError, and business error mapping.
    ExitCode.swift        The stable exit codes.
    NameValidation.swift  Secret name rules.
    Constants.swift       Version and the fixed Keychain namespace.
```

`CLI` talks only to the `SecretStore`, `SecretInput`, `ConfirmationPrompting`,
and `OutputWriter` protocols, which is what makes it testable without a Keychain.
Please keep Security framework calls inside `KeychainStore.swift` and
LocalAuthentication calls inside `Authentication.swift`.

## Things that will not be merged

These are design decisions, not oversights:

- Switching to `.userPresence`, or any change that permits a login-password
  fallback
- Creating an unprotected Keychain item when Touch ID is unavailable, or any
  other silent downgrade
- A flag that skips authentication, including any form of `--force`
- Accepting a secret as a command-line argument
- Caching, reusing, or persisting an `LAContext` between commands
- A `list` command, or anything else that enumerates secret names
- Any network request, telemetry, analytics, or update check
- Writing a secret to a file, an argument, an environment variable, the
  clipboard, a log, or an error message
- Third-party Swift package dependencies
- Claims of guaranteed memory erasure, "unhackable", "military-grade", or
  similar marketing language
- Changing `Constants.keychainService`, which would orphan existing secrets

If you think one of these should change, please open an issue to discuss it
before writing code.

## When Apple's behaviour is unclear

Several parts of this tool depend on Keychain and LocalAuthentication behaviour
that is not fully specified. If you hit an unclear case:

1. Write the smallest program that demonstrates the behaviour.
2. Record the result, the macOS version, and the build number.
3. Add the finding to the README.
4. Fail explicitly rather than degrading security.

The "Code signing" section of the README is an example of the format.

## Pull requests

- Keep changes focused; one concern per pull request.
- Add tests for anything a test can reach — parsing, validation, error mapping,
  exit codes, and stream separation are all covered today.
- Run `./Scripts/test.sh` before pushing.
- Match the surrounding style. Comments explain *why*; the code already says
  what.
- Update the README when you change observable behaviour, and CHANGELOG.md for
  anything user-visible.

## Manual testing

Some behaviour cannot be covered by CI, which has no Touch ID, no GUI session,
and no signing identity. If your change touches authentication, storage, or
terminal input, please run through the manual checklist in
[docs/MANUAL-TESTING.md](docs/MANUAL-TESTING.md) and say what you verified, on
which macOS version.

## Code of conduct

Be decent to each other. Assume good faith, keep criticism about the code, and
remember that everyone here is volunteering their time.
