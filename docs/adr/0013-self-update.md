# ADR 0013 — Self-update

- **Status:** Accepted
- **Date:** 2026-08-04 (v1.9.0; the winget-portable guard came in v1.10.1, the four install channels in v1.11.0)
- **Depends on:** ADR 0001, ADR 0002, ADR 0003, ADR 0012
- **Referenced by:** ADR 0014, ADR 0015

## Context

Since v1.9.0 the app checks GitHub for newer releases and, when the user confirms, installs them
itself. On Windows a running executable cannot be overwritten, but it can be renamed.

Over time copies of the app arrived on machines in four different ways, and the way one updates
depends on how it got there. The hard lesson was winget: a winget `portable` package is a file winget
owns. It copies the exe into `%LOCALAPPDATA%\Microsoft\WinGet\Packages\<id>\`, records its SHA-256 in
the uninstall entry under `HKCU`, and expects to find exactly that back. The self-update broke all
three assumptions at once: the hash no longer matched, so winget refused to upgrade or uninstall
without `--force`; the `.old` left beside it was a file winget had not installed, so it would not
clear the directory; and the uninstall entry still named the old version, so `winget install`
answered that the package was already there. A 1.9.0 install that pressed Update ended as an app that
no longer started and could not be reinstalled.

## Decision

**Source of truth: the latest GitHub release** of `FedeB2160/WinGetStudio`, read with **one anonymous
API call** at startup (`releases/latest`, no token; the limit is 60 requests per hour per IP). The call
sets TLS 1.2 explicitly — PowerShell 5.1 still negotiates TLS 1.0 by default and GitHub refuses it — and
sends a `User-Agent`, without which the API answers 403. The tag (`v1.11.0`) is compared with
`$AppVersion` (ADR 0001) as a `[version]`, not as a string: `"1.10.0" -gt "1.9.0"` is false as text.
The startup check can be turned off in Settings (**Check for updates at startup**, on by default, since
v1.10.0: a program going online by itself should say so and leave the choice); a manual check always
reports its outcome.

**The install channel decides how a copy updates.** `Get-InstallChannel` (`App.Update.ps1`), checked in
this order:

| Channel | How it is recognised | How it updates |
|---|---|---|
| `source` | no running exe: `main.ps1` from a checkout | not at all; use git |
| `winget-portable` | exe under `\Microsoft\WinGet\Packages\` | only `winget upgrade FedeB2160.WinGetStudio` |
| `installed` | exe folder equals `InstallLocation` of `HKLM\...\Uninstall\{80A0A054-6278-4145-AD5A-2B3C4853019F}_is1` in the **32-bit** registry view, ignoring case and a trailing `\` | downloads `WinGetStudio_Setup.exe` and runs it silently |
| `portable` | anything else | downloads `WinGetStudio.exe`, renames itself, restarts |

- **`winget-portable` stands down** (v1.10.1): the update button never appears, a manual check says to
  use `winget upgrade`, and `Start-SelfUpdate` returns without touching anything. The test is path
  matching, not a registry lookup: the path *is* what winget guarantees about a portable install, and
  the check runs on the UI thread at every check.
- **`installed` compares folders** rather than asking whether an uninstall entry exists: a portable
  copy on a machine that also has the setup installed is still portable, and must not run the setup
  over a different folder. The key is opened through `RegistryKey.OpenBaseKey('LocalMachine',
  'Registry32')`: the setup is x86, but the ps2exe exe is AnyCPU and runs 64-bit, so a plain `HKLM:\`
  read looks in the 64-bit view, never finds the key, and the installed copy would replace itself as
  if it were portable. The first version relied on a redirection that never happens; the final review
  of the installer work caught it.

**The asset is chosen by exact name** for the channel (since v1.11.0), never by position. A release
missing that file offers no update, and a manual check says which file is missing.

**Verification.** GitHub publishes a SHA-256 `digest` per asset, and the download is checked against
it before anything runs. The `installed` channel **refuses** a release with no digest — the setup
runs as administrator. The `portable` channel downloads anyway but says, in the confirmation, that the
file cannot be verified. The confirmation is Yes/No, defaults to No, names the file, size and URL, and
comes before anything is downloaded.

**Replacing the running exe (`portable`).** Rename the running exe to `.old`, move the download into
its place, start it (its `requireAdministrator` manifest brings its own UAC prompt, ADR 0002) and close
the window. If the rename succeeded and the move did not, the `.old` is put back. `Clear-OldExe`
removes the `.old` at the next startup, best effort. No external updater.

**Running the setup (`installed`).** Download to `%TEMP%` as `wgt_<tag>_WinGetStudio_Setup.exe`, then
start it with `/SILENT /CLOSEAPPLICATIONS /relaunch=1 /LOG="<temp>\WinGetStudio-update.log"`, log the
log path, close the window. The app is already elevated, so there is no second UAC prompt. Inno closes
the app, replaces it and relaunches it (ADR 0014); on failure the wizard shows the error and the app is
not relaunched. The setup file is swept by `Clear-WinGetTempFiles` at the next launch (ADR 0004).

**`Start-SelfUpdate` asks `Test-WinGetBusy`** (ADR 0003): it ends by replacing the executable and
closing the window, which must not happen while a runspace is inside winget.

**The app keeps itself out of its own Updates list.** winget cannot overwrite a running executable, so
ticking WinGet Studio in Updates would always fail. `Test-IsSelfPackage` matches by containment, not
equality: from the catalogue the Id is `FedeB2160.WinGetStudio`, from a local manifest winget records
`ARP\User\X64\FedeB2160.WinGetStudio__DefaultSource`.

## Consequences

**Positive**
- One button updates a portable or installed copy; nothing else to install or run.
- A download is verified before it runs, and an installer is never run unverified.
- A winget-owned copy is left to winget, so the package stays consistent.
- The `installed` path was verified end to end in Windows Sandbox on 2026-10-08:
  - a 1.10.9 test setup found v1.11.0;
  - it downloaded `WinGetStudio_Setup.exe` to `%TEMP%\wgt_v1.11.0_WinGetStudio_Setup.exe` and verified it;
  - it ran the setup with `/SILENT /CLOSEAPPLICATIONS /relaunch=1`;
  - it came back as 1.11.0, with the uninstall entry at 1.11.0 and no `wgt_` file left behind.

**To watch**
- **Tag and `$AppVersion` must agree**, or the app keeps proposing an update already installed or
  never proposes one.
- **The latest release is what every copy sees.** v1.0.0 was removed from GitHub after the rename: it
  carried the pre-rename binary, and the update check would have offered users a downgrade.
- **Copies up to 1.10.x take the first `.exe`** the API lists. The API sorts assets by name, so the
  portable must sort first; the release procedure checks it after every publish (ADR 0014).
- `OnDone` does not see the locals of `Start-SelfUpdate`; paths and release travel in `$script:` variables.
  With them local, the update died on "Path is null" (ADR 0008).
- The full "find release, download, install" path of the `installed` channel could only run once a
  release newer than 1.11.0 exists; download and verification are shared with the portable path and
  already tested.
- Recovering a machine already broken by a pre-1.10.1 self-update of a winget portable:
  `winget uninstall --force`, then remove the package directory, the `Links` alias and the `HKCU`
  uninstall key by hand, then install again.

## Alternatives considered

1. **An external updater program** — not used: the rename dance needs none.
2. **First `*.exe` asset of the release** — the rule up to 1.10.x, replaced by exact names when releases
   started carrying two executables.
3. **Detect a winget portable through the registry** — turned down for path matching, which is what
   winget guarantees and is cheap enough for the UI thread.
4. **"Is there an uninstall entry?" for `installed`** — turned down: it would misclassify a portable copy
   on a machine that also has the setup.
5. **A supervisor process, an origin marker, a separate winget channel for installed copies** — proposed
   in the earlier dual-distribution spec and dropped: Inno closes and relaunches the app itself, and one
   `installed` channel serves manual and winget installs alike.
