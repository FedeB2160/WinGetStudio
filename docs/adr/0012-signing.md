# ADR 0012 — Signing

- **Status:** Accepted
- **Date:** 2026-08-04 (v1.9.0; signing only with the published key since v1.10.2, `src\sign.ps1` since v1.11.0)
- **Depends on:** ADR 0001
- **Referenced by:** ADR 0013, ADR 0014, ADR 0016

## Context

An unsigned exe shows no publisher and cannot prove it is the file that was built. The app
downloads and runs new versions of itself (ADR 0013), and from v1.11.0 ships a setup that runs as
administrator (ADR 0014). There is no commercial certificate.

Up to v1.10.1 the build signed with the first valid code-signing certificate it found. A second
certificate with the same subject, `CN=WinGet Studio`, generated on another machine, cannot be told
apart by name, and would sign exes that the `.cer` published in the repository cannot verify.

## Decision

**Self-signed certificate, `CN=WinGet Studio`**, valid to 2031, with a DigiCert timestamp. Its public
half is committed as `assets\WinGetStudio-codesign.cer`; private keys never are (`.gitignore` blocks
`*.pfx`, `*.p12`, `*.snk`).

**Which certificate signs**, in `build.ps1`:

1. `$env:WINGETSTUDIO_CERT_THUMBPRINT` if set — the way to switch to a company or commercial
   certificate without editing the build;
2. otherwise **only** the certificate in `Cert:\CurrentUser\My` whose thumbprint matches
   `assets\WinGetStudio-codesign.cer`, valid and with its private key. Any other code-signing
   certificate is ignored, even one with the same subject.

**Never generate a replacement certificate to get a build through.** Without the key the build
**still succeeds**, unsigned, with a warning: signing needs a private key that not every machine has.

**One implementation of signing**, `src\sign.ps1 -Path <file> -Thumbprint <thumbprint>`
(`Set-AuthenticodeSignature`, SHA-256, timestamp server `http://timestamp.digicert.com`). `build.ps1`
calls it for the exe and hands it to Inno Setup as the `SignTool` for the setup and its uninstaller
(ADR 0014); there is no `signtool.exe` dependency. It exits non-zero when no signature was applied,
which stops Inno.

**Always timestamped when possible.** Without a timestamp a signature stops being valid the day the
certificate expires; with one it stays valid, because it proves the signature existed while the
certificate was good. If the server cannot be reached, it signs without and says so. Whether the
timestamp was applied is read from `TimeStamperCertificate`, not from `Status`, which is never `Valid`
for a self-signed certificate on a machine that does not trust it.

## Consequences

**Positive**
- Proves the exe has not been altered since the build, and shows a publisher name.
- Exe, setup and uninstaller are signed the same way by the same code.
- A commercial OV or EV certificate, or one from an internal PKI, plugs in through the environment
  variable without touching the build.

**To watch**
- **Windows does not trust it.** `Get-AuthenticodeSignature` reports `UnknownError` and SmartScreen
  says "unknown publisher", because the root is not among the trusted authorities. This is expected
  and does not mean the signature is missing. To trust it, import the `.cer` into *Trusted Root
  Certification Authorities* — per user with `Import-Certificate -CertStoreLocation
  Cert:\CurrentUser\Root`, or machine-wide by GPO — knowing that anything signed with it becomes
  trusted for whoever imports it.
- **Builds are not reproducible.** Compiling the same source twice gives two binaries identical in
  size but not in hash: ps2exe writes variable metadata into the PE, and each signature carries a fresh
  timestamp. A published asset cannot be validated by rebuilding and comparing hashes; what can be
  verified is the SHA-256 GitHub publishes with the asset (which the self-update checks) and the
  Authenticode signature.
- No signing key ever reaches CI: CI artifacts are unsigned test builds (ADR 0016). Releases are
  signed locally, on the machine that holds the key.

## Alternatives considered

1. **Sign with the first valid code-signing certificate found** — the previous rule, turned down in
   v1.10.2: a same-subject certificate generated elsewhere would sign exes the published `.cer` does
   not recognise.
2. **Generate a new certificate when the key is missing** — forbidden for the same reason; the build
   goes unsigned instead.
3. **A commercial OV or EV certificate** — the way to a signature trusted everywhere without importing
   anything; not adopted, but supported through `$env:WINGETSTUDIO_CERT_THUMBPRINT`.
4. **`signtool.exe` for the setup** — not used: `Set-AuthenticodeSignature` through `sign.ps1` needs no
   extra dependency.
