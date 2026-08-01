**English** · [简体中文](README.zh-CN.md)

# TouchSeal

> Seal secrets locally. Release them with a touch.

TouchSeal is a small, native macOS command-line tool that stores secrets in the
system Keychain and releases them only after Touch ID approval.

It requires no cloud account, daemon, browser extension, or third-party password
manager. TouchSeal performs no network requests and stores secrets only in the
macOS Keychain.

## Example

```bash
touchseal set anthropic-api-key
touchseal get anthropic-api-key
```

The first command prompts twice, without echo, and stores the secret. The second
raises a Touch ID prompt and, on approval, writes the secret to stdout with no
trailing newline and nothing else.

---

## Status

TouchSeal v0.1 is feature-complete and unit-tested, but **it cannot create
Touch ID-protected Keychain items unless the binary is signed with an
Apple-issued code-signing identity.** This is a macOS restriction, not a
TouchSeal bug, and it is unavoidable without weakening the security model.

Read [Code signing](#code-signing) before installing. If you have no signing
identity, `touchseal set` will fail with a clear error and exit code 8 rather
than silently storing your secret unprotected.

---

## What it is for

Command-line tools frequently need an API key. The usual options are all
unpleasant: an environment variable in your shell profile, a plaintext dotfile,
or a password manager that wants a subscription and a browser extension.

TouchSeal keeps the secret in the macOS Keychain, protected by the currently
enrolled Touch ID fingerprints, and hands it out one approval at a time.

```text
Claude Code
  → executes touchseal
  → TouchSeal requests the Keychain item
  → macOS shows Touch ID
  → you approve
  → TouchSeal writes the secret to stdout
  → Claude Code receives the API key
```

---

## Security model

### Storage

Every secret is a generic password item in TouchSeal's own service namespace:

| Attribute | Value |
| --- | --- |
| `kSecClass` | `kSecClassGenericPassword` |
| `kSecAttrService` | `io.github.chhc-l.touchseal.secret` |
| `kSecAttrAccount` | the name you provide |
| `kSecAttrLabel` | `TouchSeal: <name>` |
| `kSecAttrDescription` | `Secret managed by TouchSeal` |

TouchSeal only ever queries its own service namespace. It never reads, lists, or
modifies Keychain items belonging to other programs, and it never puts secret
material into a label, description, or account name.

The service string is a stable contract. Changing it would orphan every
previously sealed secret, so it will not change across versions.

### Access control

Items are created with `SecAccessControlCreateWithFlags` using:

- Accessibility: `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
- Flags: `.biometryCurrentSet`

Together these mean:

- The secret can only be read with a currently enrolled Touch ID fingerprint.
- The secret cannot be read while the Mac is locked.
- The secret never syncs to iCloud Keychain; it exists on this device only.
- If the enrolled fingerprint set changes, the secret becomes permanently
  unreadable.

The accessibility constant is passed into `SecAccessControlCreateWithFlags`
rather than set separately as `kSecAttrAccessible`; setting both is rejected by
the Security framework.

### Why `.biometryCurrentSet` and not `.userPresence`

`.userPresence` lets macOS accept your login password as a substitute for
biometry. That turns "prove you are physically here with an enrolled finger"
into "type the password that anyone watching your screen may have seen".

`.biometryCurrentSet` also invalidates the item when the enrolled fingerprint
set changes. That is inconvenient — and deliberate. If an attacker with your
login password enrolls their own fingerprint, `.biometryCurrentSet` makes your
existing secrets unreadable instead of readable by the new finger.

### Why there is no password fallback

For a `.biometryCurrentSet` item, the login password is not an alternative
credential — the item is cryptographically bound to the fingerprint set. Offering
a password prompt would only produce a dead end, so TouchSeal suppresses the
fallback button and reports `LAError.userFallback` as a failure.

TouchSeal does not lower its policy when Touch ID is unavailable. On a Mac
without Touch ID, on a Face ID device, or with no fingerprints enrolled, it fails
with exit code 6 rather than creating a less protected item.

### One approval per read

Every `get` builds a brand-new `LAContext`, sets
`touchIDAuthenticationAllowableReuseDuration = 0`, passes it to the Keychain
query via `kSecUseAuthenticationContext`, and discards it when the command exits.

There is no session, no daemon, no cached approval, and no flag that skips
authentication. Running `touchseal get` twice raises two separate Touch ID
prompts.

TouchSeal sets the prompt text through `LAContext.localizedReason`. The
`kSecUseOperationPrompt` query key described in older documentation was
deprecated in macOS 11 in favour of exactly this property.

### The caller model

Any local program that can execute `touchseal` can ask for a secret. Touch ID
proves that *you approved this release*, not that the calling program is
trustworthy.

TouchSeal v0.1 deliberately does not inspect the parent process, the caller's
code signature, or the caller's path. Those checks are straightforward to spoof
from a compromised session and would give a false sense of protection.

---

## Requirements

- macOS 13 or later
- A Mac with Touch ID, with at least one fingerprint enrolled
- Swift 6.0 or later to build from source
- An Apple code-signing identity — see [Code signing](#code-signing)

TouchSeal has no third-party dependencies. It uses only Foundation, Security,
LocalAuthentication, and Darwin.

---

## Build

```bash
swift build -c release
```

The binary is written to `.build/release/touchseal`.

Run the unit tests with:

```bash
./Scripts/test.sh
```

The tests use swift-testing and never touch the Keychain, Touch ID, or the
network. The script exists because swift-testing needs extra search paths on a
Mac that has the Command Line Tools but not full Xcode; with Xcode installed,
plain `swift test` works too.

---

## Code signing

**This section is not optional.** On macOS, `kSecAttrAccessControl` is only
available to binaries whose code signature carries a keychain access group.
Without one, `SecItemAdd` fails with `errSecMissingEntitlement` (-34018).

### Measured behaviour

Tested on macOS 26.5.2 (build 25F84), Apple Swift 6.3.3, Apple silicon:

| Configuration | `SecItemAdd` with `.biometryCurrentSet` |
| --- | --- |
| Ad-hoc signature (SwiftPM default) | `-34018` |
| Ad-hoc signature with explicit `--identifier` | `-34018` |
| Ad-hoc signature inside a `.app` bundle | `-34018` |
| Ad-hoc signature + `keychain-access-groups` entitlement | process terminated by the system on launch |

For comparison, a plain generic password with no access control stores
successfully under the same ad-hoc signature, which confirms the failure is
specific to the access-control path rather than to Keychain access in general.

The conclusion is that an ad-hoc signature is **not** sufficient, and that
faking the entitlement does not work: macOS refuses to honour a
`keychain-access-groups` entitlement on an ad-hoc signature and kills the
process.

### Signing with your own identity

List your identities:

```bash
security find-identity -v -p codesigning
```

Then sign the release binary:

```bash
swift build -c release
./Scripts/sign.sh "Apple Development: you@example.com (XXXXXXXXXX)"
```

The script derives the team ID from the identity name and substitutes it into
`Resources/touchseal.entitlements`, because macOS only honours a keychain access
group whose prefix matches the signing identity's team.

Both a free *Apple Development* certificate and a paid *Developer ID
Application* certificate carry a team ID. Apple Development certificates are
available with any Apple ID through Xcode.

### Re-signing after a rebuild

Keychain items created with `.biometryCurrentSet` are bound to the fingerprint
set, not to the calling binary, so rebuilding and re-signing `touchseal` does
not invalidate secrets you have already sealed — provided you keep using the
same keychain access group. Changing the access group makes existing items
unreachable in the same way that changing the service string would.

This project makes no claim that unsigned or ad-hoc builds provide stable access
across versions, because they cannot create these items at all.

---

## Install

```bash
mkdir -p "$HOME/.local/bin"
install -m 755 ".build/release/touchseal" "$HOME/.local/bin/touchseal"
```

Sign the installed copy as described above, then confirm:

```bash
"$HOME/.local/bin/touchseal" version
```

Make sure `$HOME/.local/bin` is on your `PATH`.

---

## Commands

### `set`

```bash
touchseal set anthropic-api-key
```

```text
Enter secret:
Confirm secret:
Secret "anthropic-api-key" sealed.
```

Input is read from `/dev/tty` with echo disabled and is requested twice. The
secret is never accepted as a command-line argument, because arguments leak into
shell history, the process list, and crash reports. Success is reported on
stderr; stdout stays empty.

If the name already exists:

```text
Secret "anthropic-api-key" already exists. Replace it? [y/N]
```

The default is No. Replacing requires Touch ID approval of the *existing*
secret first — there is no `--force`. Because the access control of an existing
item cannot be updated in place, replacement deletes and re-adds. Keychain
operations are not transactional, so if the new value cannot be stored TouchSeal
restores the previous one and says so. In the rare case where the restore also
fails, it reports that the secret is gone rather than exiting quietly.

### `get`

```bash
touchseal get anthropic-api-key
```

On success, stdout contains the secret and nothing else — no trailing newline, no
JSON, no status line — and stderr is empty. On any failure, stdout is empty.

To test without displaying the secret:

```bash
touchseal get anthropic-api-key >/dev/null
```

### `delete`

```bash
touchseal delete anthropic-api-key
```

```text
Delete secret "anthropic-api-key"? [y/N]
```

The default is No. `SecItemDelete` does not itself require authentication, so
TouchSeal performs an authenticated read first and discards the value; deletion
therefore always costs a Touch ID approval.

`--yes` skips the typed confirmation only:

```bash
touchseal delete anthropic-api-key --yes
```

It does not skip Touch ID, and there is no flag that does.

### `exists`

```bash
if touchseal exists anthropic-api-key; then
    echo "TouchSeal is configured"
fi
```

Exits 0 if the secret exists and 3 if it does not. It never reads the secret,
never raises a Touch ID prompt, and writes nothing to stdout or stderr. The query
requests metadata only, with `kSecReturnData` deliberately absent, and sets
`interactionNotAllowed` so that macOS fails rather than prompts. If macOS
declines to answer without authentication, TouchSeal reports the item as
existing rather than weakening it.

There is no `list` command in v0.1: the set of secret names is itself metadata
worth withholding.

### `help` and `version`

```bash
touchseal help      # also --help, -h
touchseal version   # also --version
```

---

## Exit codes

| Code | Meaning |
| ---: | --- |
| 0 | Success |
| 1 | General error |
| 2 | Invalid arguments, including an invalid name |
| 3 | Secret not found |
| 4 | Secret already exists and replacement was declined |
| 5 | Authentication canceled |
| 6 | Touch ID unavailable |
| 7 | Authentication failed |
| 8 | Keychain error, including a missing entitlement |
| 9 | The two entries did not match |
| 10 | Confirmation declined |
| 11 | Invalid secret data |

All errors are written to stderr. `OSStatus` values are rendered with
`SecCopyErrorMessageString` and reported alongside the numeric status.

---

## Names and secrets

A name must be 1–128 Unicode characters with no line breaks, no NUL, no other
control characters, and no leading or trailing whitespace. Whitespace is rejected
rather than trimmed, so `key` and `key ` can never be confused. Interior spaces
are allowed but must be quoted in the shell. Put `--` before a name that begins
with `-`.

Valid: `anthropic-api-key`, `github-token`, `work/vpn/password`

A secret must be non-empty, valid UTF-8, and at most 8190 bytes. It is stored
byte-for-byte: nothing is trimmed, normalized, or appended. Binary secrets are
not supported in v0.1.

---

## Claude Code integration

Seal the key:

```bash
touchseal set anthropic-api-key
```

Create a wrapper script at `~/.local/bin/claude-anthropic-key`:

```sh
#!/bin/sh
set -eu

exec "$HOME/.local/bin/touchseal" get anthropic-api-key
```

A copy is provided at [`Examples/claude-anthropic-key`](Examples/claude-anthropic-key).

```bash
chmod 700 "$HOME/.local/bin/claude-anthropic-key"
```

Then configure Claude Code:

```json
{
  "apiKeyHelper": "/Users/USERNAME/.local/bin/claude-anthropic-key"
}
```

The wrapper must `exec` the tool and nothing else. Do not `export` the key, write
it to a temporary file, echo it back, or add debug output.

### Credential caching

These are two different things, and only the first is TouchSeal's to control:

1. **TouchSeal's own reuse behaviour.** Guaranteed: every `touchseal get`
   creates a fresh authentication context and requires a new Touch ID approval.

2. **Claude Code's credential caching.** Not guaranteed: Claude Code may cache
   the value returned by `apiKeyHelper` and reuse it for subsequent API
   requests without calling the helper again.

If you set `CLAUDE_CODE_API_KEY_HELPER_TTL_MS`, Claude Code may not call
TouchSeal at all within that window. One Touch ID approval therefore does not
correspond to one API request.

---

## Shell history

Sealing a key does nothing about copies your shell already recorded. A key that
was ever pasted into a command line is sitting in `~/.zsh_history` in plaintext,
and TouchSeal cannot reach it.

```bash
./Scripts/scrub-history.sh              # dry run: report matches, keys masked
./Scripts/scrub-history.sh --clean      # delete matching entries
./Scripts/scrub-history.sh --clean --redact   # keep entries, mask the key
```

It scans `$HISTFILE`, `~/.zsh_sessions/*.history`, and `~/.bash_history`, matches
per history entry rather than per line so multi-line commands survive intact, and
backs up every file it modifies to `<file>.bak.<timestamp>` at mode 0600. It
never prints an unmasked key and sends nothing anywhere.

A dry run exits 1 when it finds something, so it composes in a pre-commit hook or
a periodic check.

Two things the script cannot do for you: the key was on disk in plaintext, so
**rotate it**; and other open shells will write their in-memory history back on
exit, so close them or run `unset HISTFILE; exec zsh` in each.

Once a key is sealed, `touchseal set` keeps it out of history in the first place
— input is read from the terminal with echo disabled, and a secret is never
accepted as a command-line argument.

---

## Limitations

### No GUI session

Touch ID needs a graphical login session. Over SSH, or in any session without
WindowServer, `touchseal get` fails cleanly with a clear message rather than
hanging or emitting a partial secret. Secure input additionally requires a real
terminal and fails rather than reading from a redirected stdin.

### No Touch ID, no TouchSeal

Macs without Touch ID are not supported, and neither are Face ID devices.
TouchSeal checks that `LAContext.biometryType` is specifically `.touchID` and
refuses to proceed otherwise. It will not fall back to a weaker policy.

### Changing your fingerprints invalidates secrets

Adding or removing a fingerprint in System Settings invalidates every
`.biometryCurrentSet` item, including all TouchSeal secrets. They cannot be
recovered; seal them again.

macOS reports an invalidated item and a simply unrecognized finger with the same
status (`errSecAuthFailed`), so TouchSeal's error message names both
possibilities rather than guessing.

### Keychain operations are not transactional

Replacing a secret is a delete followed by an add. TouchSeal restores the old
value if the add fails, but a crash or power loss between the two steps can still
lose a secret. Keep a copy of anything you cannot regenerate.

---

## Threat model

TouchSeal protects the moment a secret leaves the Keychain. That is a real but
narrow guarantee. Specifically:

- Touch ID protects **release** of the secret, nothing after it.
- Once approved, the calling program has the plaintext secret and may copy,
  cache, log, or transmit it. That is inherent to handing it over.
- stdout is readable by the calling program. This is the intended design, not a
  flaw.
- TouchSeal cannot control how Claude Code holds the API key in memory, and
  Claude Code may cache it.
- TouchSeal does not verify that the caller is trustworthy.
- TouchSeal does not defend against root, or against an attacker with equivalent
  privileges.
- TouchSeal does not defend against an already fully compromised user session.
- Swift may create copies of secret data that cannot be reliably zeroed. TouchSeal
  keeps secrets in `Data` rather than `String` where it can, writes them straight
  to the output descriptor, and wipes its own input buffer with `memset_s`, but it
  makes no claim of guaranteed memory erasure.
- TouchSeal is not a sandbox, a permission system, or a complete secrets broker.

TouchSeal never logs secrets, writes them to files, puts them in arguments or
environment variables, copies them to the clipboard, or includes them in error
messages.

---

## Privacy

TouchSeal makes no network requests. It has no analytics, no telemetry, no crash
reporting, and no update check. It keeps no history of the commands you run and
collects no secret names. Secrets are stored only in the macOS Keychain.

---

## Uninstall

Delete each secret you sealed. Each deletion requires Touch ID, by design:

```bash
touchseal delete anthropic-api-key
```

TouchSeal deliberately provides no command that bulk-deletes items without
authentication.

Then remove the binary, the wrapper, and the build directory:

```bash
rm -f "$HOME/.local/bin/touchseal"
rm -f "$HOME/.local/bin/claude-anthropic-key"
rm -rf .build
```

Remove the `apiKeyHelper` entry from your Claude Code settings.

If you lost access to a secret before deleting it — for example after changing
your fingerprints — the leftover item is visible in Keychain Access under the
name `TouchSeal: <name>` and can be deleted there.

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). Security issues should be reported
privately; see [SECURITY.md](SECURITY.md). Never paste API keys, passwords, or
Keychain contents into an issue.

## License

[MIT](LICENSE).

---

TouchSeal is an independent open-source project and is not affiliated with
or endorsed by Apple Inc. or Anthropic PBC.

Apple, macOS, Touch ID, and Keychain are trademarks of Apple Inc.
Claude is a trademark of Anthropic PBC.
