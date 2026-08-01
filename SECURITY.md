# Security Policy

## Never put secrets in a public report

Before you file anything, please make sure it contains no real secret material.

**Do not include:**

- API keys, tokens, passwords, or any other real secret — not even expired or
  revoked ones
- Keychain item contents, or exports from Keychain Access
- Logs, terminal transcripts, or screen recordings that captured a secret
- Crash reports or `sysdiagnose` archives that may contain process memory

If you need to show a value, replace it with an obvious placeholder such as
`sk-ant-REDACTED`. TouchSeal deliberately never logs secrets or includes them in
error messages, so a report should not need one.

## Reporting a vulnerability

Please report security issues **privately**, not in a public issue.

Use GitHub's private vulnerability reporting:

1. Go to https://github.com/CHHC-L/TouchSeal/security/advisories
2. Choose **Report a vulnerability**

Please include:

- The macOS version and build (`sw_vers`)
- The TouchSeal version (`touchseal version`)
- How the binary was signed (`codesign -dv --entitlements - "$(which touchseal)"`)
- What you expected to happen, and what happened instead
- Reproduction steps, with secrets redacted

You can expect an initial response within 7 days. If a fix is warranted, the
advisory will credit you unless you prefer otherwise.

## Supported versions

| Version | Supported |
| --- | --- |
| 0.1.x | Yes |
| < 0.1 | No |

TouchSeal is pre-1.0. Only the latest release receives security fixes.

## Scope

In scope:

- Releasing a secret without a Touch ID approval
- Any secret material reaching stdout on a failure path, a log, a file, an
  argument list, an environment variable, or the clipboard
- Weakening the documented access control (`.biometryCurrentSet` with
  `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`)
- Reading or modifying Keychain items outside TouchSeal's service namespace
- Any network request made by TouchSeal — it should make none

Out of scope, because they are documented properties of the design rather than
defects. See the threat model in [README.md](README.md):

- A calling program copying, caching, or leaking a secret after you approved its
  release
- Attacks by root, or by an attacker with equivalent privileges
- An already fully compromised user session
- Claude Code caching the value returned by `apiKeyHelper`
- The absence of caller verification — TouchSeal does not check the parent
  process, path, or code signature
- Swift runtime copies of secret data that cannot be reliably zeroed
- `errSecMissingEntitlement` on an ad-hoc signed binary; this is a macOS
  restriction, documented under "Code signing" in the README

## No bounty programme

TouchSeal is an unfunded open-source project and offers no monetary reward for
security reports. Reports are still very welcome, and will be handled seriously.
