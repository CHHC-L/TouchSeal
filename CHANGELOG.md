# Changelog

All notable changes to TouchSeal are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-08-01

First release.

### Added

- `set`, `get`, `delete`, `exists`, `help`, and `version` commands.
- Keychain storage as generic password items in the fixed service namespace
  `io.github.chhc-l.touchseal.secret`, protected with `.biometryCurrentSet` and
  `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
- A fresh `LAContext` per read, with
  `touchIDAuthenticationAllowableReuseDuration = 0`, so every `get` requires a
  new Touch ID approval.
- A check that `LAContext.biometryType` is specifically `.touchID`; TouchSeal
  refuses to run on Face ID or non-biometric Macs rather than weakening its
  policy.
- Secure terminal input via `readpassphrase(3)`, requiring a real tty, with the
  secret entered twice and never echoed.
- Authenticated replacement of an existing secret, with restore of the previous
  value if the new one cannot be stored.
- Authenticated deletion; `--yes` skips the typed confirmation but never Touch ID.
- Silent existence checks that request metadata only and raise no prompt.
- Strict stream separation: on a successful `get`, stdout carries the secret and
  nothing else, with no trailing newline; everything else goes to stderr.
- Stable exit codes 0–11.
- Error mapping for `OSStatus` and `LAError`, including an actionable message for
  `errSecMissingEntitlement`.
- 84 unit tests covering parsing, name and secret validation, UTF-8 handling,
  error mapping, exit codes, and stream separation, with no Keychain, Touch ID,
  or network access.
- `Scripts/sign.sh` and `Resources/touchseal.entitlements` for signing with an
  Apple-issued identity.
- Documentation of measured macOS code-signing behaviour, the threat model, and
  Claude Code integration including its credential caching.

### Known limitations

- Creating Touch ID-protected items requires a code-signing identity; an ad-hoc
  signature fails with `errSecMissingEntitlement` (-34018). See "Code signing"
  in the README.
- Changing the enrolled fingerprint set permanently invalidates existing secrets.
- Keychain operations are not transactional; replacement is a delete followed by
  an add.
- Text secrets only, up to 8190 bytes. Binary secrets are not supported.

[Unreleased]: https://github.com/CHHC-L/TouchSeal/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/CHHC-L/TouchSeal/releases/tag/v0.1.0
