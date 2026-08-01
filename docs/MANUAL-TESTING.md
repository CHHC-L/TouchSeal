# Manual acceptance tests

CI cannot cover TouchSeal's most important behaviour: it has no Touch ID sensor,
no GUI session, and no code-signing identity. These checks must be run by hand on
a Mac with Touch ID.

Record the macOS version (`sw_vers`) and how the binary was signed
(`codesign -dv --entitlements - "$(which touchseal)"`) alongside your results.

Use a throwaway name such as `touchseal-selftest`, not a real API key.

---

## 0. Prerequisites

```bash
swift build -c release
./Scripts/sign.sh "Apple Development: you@example.com (XXXXXXXXXX)"
```

Without a signing identity, step 1 fails with `errSecMissingEntitlement` and
exit code 8. That is the expected, documented behaviour — see "Code signing" in
the README — but it blocks every check below it.

---

## 1. Seal a secret

```bash
touchseal set touchseal-selftest
```

- [ ] Nothing is echoed while typing.
- [ ] The secret is requested twice.
- [ ] stdout is empty (`touchseal set … >/tmp/out` leaves `/tmp/out` empty).
- [ ] `Secret "touchseal-selftest" sealed.` appears on stderr.
- [ ] The item appears in Keychain Access as `TouchSeal: touchseal-selftest`.
- [ ] Keychain Access does not display the secret in plaintext.

## 2. Mismatched entries

Enter two different values.

- [ ] Nothing is stored.
- [ ] Exit code is 9.

## 3. First read

```bash
touchseal get touchseal-selftest >/dev/null
```

- [ ] A Touch ID prompt appears.
- [ ] The prompt reads `TouchSeal wants to release secret "touchseal-selftest"`.
- [ ] Only one prompt appears, not two.
- [ ] No "Use Password…" or other fallback option is offered.
- [ ] Exit code is 0 after a successful touch.
- [ ] The secret is not displayed in the terminal.

## 4. Consecutive reads

```bash
touchseal get touchseal-selftest >/dev/null
touchseal get touchseal-selftest >/dev/null
```

- [ ] Touch ID is requested both times.
- [ ] The first approval does not authorize the second run.

## 5. No trailing newline

```bash
touchseal get touchseal-selftest | xxd | tail -1
```

- [ ] The final byte is the last byte of the secret, not `0a`.

## 6. Cancel

Dismiss the Touch ID prompt.

- [ ] stdout is empty.
- [ ] stderr reads `touchseal: Authentication was canceled.`
- [ ] Exit code is 5.

## 7. Unenrolled finger

Use a finger that is not enrolled, three times.

- [ ] No secret is returned.
- [ ] It does not fall back to the login password.
- [ ] It ends in an authentication failure, exit code 7.

## 8. Existence check

```bash
touchseal exists touchseal-selftest;  echo "present: $?"
touchseal exists touchseal-absent-xyz; echo "absent: $?"
```

- [ ] No Touch ID prompt in either case.
- [ ] Exit codes are 0 and 3.
- [ ] Both stdout and stderr are empty in both cases.

## 9. Replacement

```bash
touchseal set touchseal-selftest
```

- [ ] It asks `Secret "touchseal-selftest" already exists. Replace it? [y/N]`.
- [ ] Pressing Return alone declines; exit code is 4 and the old value survives.
- [ ] Answering `y` requires Touch ID **before** asking for the new value.
- [ ] Canceling that Touch ID leaves the old secret readable.
- [ ] After a successful replacement, `get` returns the new value.
- [ ] stderr reads `Secret "touchseal-selftest" resealed.`

## 10. No GUI session

From another machine, over SSH:

```bash
touchseal get touchseal-selftest
```

- [ ] It fails quickly rather than hanging.
- [ ] No secret is printed.
- [ ] The error names the missing GUI session.

Also confirm secure input refuses a redirected stdin:

```bash
echo secret | touchseal set touchseal-selftest2
```

- [ ] It fails rather than reading the piped value.

## 11. Delete

```bash
touchseal delete touchseal-selftest
```

- [ ] Touch ID is requested before the confirmation.
- [ ] Pressing Return alone declines; exit code is 10 and the secret survives.
- [ ] Answering `y` deletes it; stdout stays empty.
- [ ] `touchseal exists touchseal-selftest` then exits 3.
- [ ] `touchseal delete … --yes` still requires Touch ID.
- [ ] Canceling Touch ID with `--yes` deletes nothing.

## 12. Fingerprint set change

This invalidates every `.biometryCurrentSet` item on the Mac, including any real
secrets you have sealed. Do it deliberately.

1. Seal a throwaway secret.
2. Add or remove a fingerprint in System Settings.
3. Read the secret again.

- [ ] The old item can no longer be read.
- [ ] The error mentions the changed fingerprints.
- [ ] TouchSeal does not create a replacement item with weaker protection.

## 13. Claude Code

With the wrapper script and `apiKeyHelper` configured:

```bash
claude -p 'Reply with exactly: OK'
```

- [ ] Touch ID appears when Claude Code calls the helper.
- [ ] Claude Code receives the key after approval.
- [ ] The helper's stdout carries no extra text.
- [ ] Canceling Touch ID gives Claude Code nothing, not a partial key.

## 14. Rebuild and re-sign

```bash
swift build -c release && ./Scripts/sign.sh "<same identity>"
touchseal get touchseal-selftest >/dev/null
```

- [ ] Previously sealed secrets are still readable after a rebuild.

Then record the outcome in the README if it differs from what is documented
there.
