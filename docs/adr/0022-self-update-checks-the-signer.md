# ADR 0022 — Self-update checks the signer and downloads to a protected folder

- **Status:** Accepted
- **Date:** 2026-10-21 (unreleased)
- **Depends on:** ADR 0002, ADR 0004, ADR 0012, ADR 0013

## Context

The self-update (ADR 0013) downloads a new exe or setup from the latest GitHub release and runs it
elevated (ADR 0002). Up to v1.12.0 the only check was the SHA-256 `digest` GitHub publishes with the
asset, and the file waited for its turn in the user's `%TEMP%`. Comparing the code with UniGetUI, which
checks both the hash and the signer's thumbprint of what it downloads, showed two gaps:

- **The digest comes through the same channel as the file.** Whoever can replace a release asset —
  a compromised GitHub account or token — can publish the matching digest with it. The `portable`
  channel went further and downloaded a release with no digest at all, after a warning.
- **`%TEMP%` belongs to the non-elevated user.** Any process the user runs without elevation has Full
  Control there, so it can replace the verified file before the elevated app runs it. An ACL on a
  folder of our own does not close this inside `%TEMP%`: Full Control on the parent includes
  `FILE_DELETE_CHILD`, which is enough to rename our folder away and put another one with the same
  name, and a file of its choosing, in its place between the check and the run.

The signing key is the one thing an attacker on GitHub does not have: releases are signed locally, on
the machine that holds it, and it never reaches GitHub or CI (ADR 0012, ADR 0016).

## Decision

**Every channel checks the Authenticode signer**, after the hash, inside the download job:
`Get-AuthenticodeSignature` on the file, then `Test-UpdateSignature` (`App.Update.ps1`). It accepts
the file only when **both** hold:

- the status is `Valid` (the `.cer` was imported into the trusted roots) or `UnknownError` (it was not:
  the self-signed root is untrusted, ADR 0012). `NotSigned`, `HashMismatch`, `NotTrusted` and every
  other status are refused;
- the signer's thumbprint is `$UpdateSignerThumbprint`, the thumbprint of
  `assets\WinGetStudio-codesign.cer`, written into the module because the exe does not carry the
  `.cer`. `Test-Ui.ps1` fails if the two differ.

`UnknownError` is also PowerShell's catch-all status (a file that cannot carry a signature returns it,
with no signer), which is why it is never accepted without the thumbprint. The `installed` channel
still refuses a release with no digest; the `portable` one now has the signature to fall back on, and
the confirmation says the download is checked against the signature only.

**The download goes to `%SystemRoot%\Temp\wgt_update_<guid>`** (`New-UpdateDownloadDir`), created
in one call with its own protected ACL — inheritance off, Full Control for Administrators
(`S-1-5-32-544`) and SYSTEM (`S-1-5-18`), and an `OWNER RIGHTS` (`S-1-3-4`) entry with read and
execute only. In `Windows\Temp` standard users can create their own entries but cannot list the
folder, nor rename or delete what they do not own, so the folder cannot be swapped; the protected ACL
stops them adding files to it, which the inherited `Windows\Temp` ACL would allow. `OWNER RIGHTS`
covers the case where the owner is the user rather than the Administrators group: without it the
owner keeps an implicit right to rewrite the ACL.

**The portable exe is copied into place, not moved.** On the same volume a moved file keeps the ACL it
was created with, so the new exe would be readable by administrators only, and a non-elevated Explorer
could no longer start it. A copy takes the ACL of the destination folder.

**`Clear-WinGetTempFiles` sweeps `wgt_*` folders in `%SystemRoot%\Temp` as well** as in `%TEMP%`
(ADR 0004), at the next startup — the one the update itself triggers. Without elevation that folder
cannot be listed, and the sweep skips it.

## Consequences

**Positive**
- A replaced asset with a matching digest is still refused: it would have to be signed with the
  private key.
- The file that was verified is the file that runs.
- The `portable` channel no longer runs an unverified download.

**To watch**
- **Every release must be signed with the key of `assets\WinGetStudio-codesign.cer`.** An unsigned
  build (made on a machine without the key, ADR 0012), or one signed through
  `$env:WINGETSTUDIO_CERT_THUMBPRINT` with another certificate, is refused by every copy in the field.
- **Changing certificate takes two releases**: first one, signed with the old key, that accepts both
  thumbprints; then the ones signed with the new key. A copy that accepts only the old thumbprint can
  never update past the switch on its own.
- `Test-Ui.ps1` checks the signature rule on fake signatures and on `cmd.exe` (signed by Microsoft);
  the signed exe in `dist\` is checked only where it exists, which is never in CI. The full update
  path is still tested by hand (ADR 0016).
- The Inno Setup log (`%TEMP%\WinGetStudio-update.log`) stays in the user's `%TEMP%`.

## Alternatives considered

1. **A protected folder inside `%TEMP%`** — turned down: Full Control on the parent lets a
   non-elevated process rename the folder and plant another between the check and the run.
2. **Holding the file open from the check to the run** — turned down: the `portable` channel must move
   or copy the file into place, which the open handle would have to allow, and the handle would have to
   travel from the job to the UI thread; more code for what the folder location already gives.
3. **The digest alone** — the previous rule: it does not survive a compromised release channel.
4. **Accepting `Valid` only** — turned down: on every machine that has not imported the `.cer`, which
   is almost all of them, our own releases would be refused.
