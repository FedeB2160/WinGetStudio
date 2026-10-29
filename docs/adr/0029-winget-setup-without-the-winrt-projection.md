# ADR 0029 — Version 2 reads and installs winget without the WinRT projection

- **Status:** Accepted (for 2.0; amends ADR 0019 there)
- **Date:** 2026-10-29
- **Depends on:** ADR 0003, ADR 0019, ADR 0023, ADR 0025, ADR 0026

## Context

ADR 0019 reads the App Installer version with `Get-AppxPackage`, so that no winget process overlaps
the scan, and installs or registers App Installer with `Add-AppxPackage`. Both are PowerShell cmdlets
over the WinRT `Windows.Management.Deployment.PackageManager`.

From C# that API comes through the WinRT projection, which needs a versioned target framework
(`net10.0-windows10.0.x`) and adds `Microsoft.Windows.SDK.NET.dll`, tens of MB, to the
framework-dependent single-file exe that ADR 0026 measured at 193 KB. The phase 1 plan left that
change of target framework for the COM backend (ADR 0025), after measuring it.

2.0 also checks for the Store differently: it does not run as administrator (ADR 0024), so the
packages registered for *this* account are the signed-in user's.

## Decision

1. **The winget version comes from `winget --version`**, run through `WinGetCli` under the
   one-process lock (ADR 0003). The lock queues it after the startup scan instead of overlapping it,
   which is what ADR 0019 used the package read to avoid. The number is winget's own (`1.29.380`),
   the same numbering as the `microsoft/winget-cli` release tags it is compared with, so the old
   App Installer offset (1.27 = winget 1.12) never comes up. The same read already decides
   `--no-progress`.
2. **"Is the Store registered for this account"** is read from the per-user package repository,
   `HKCU\Software\Classes\Local Settings\Software\Microsoft\Windows\CurrentVersion\AppModel\Repository\Packages\Microsoft.WindowsStore_*`,
   with the same policy check as ADR 0019 (`RemoveWindowsStore=1`, `AutoDownload=2`).
3. **`Add-AppxPackage` runs in Windows PowerShell**, by full path
   (`%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -NonInteractive`), with
   the script in `-EncodedCommand`: no quoting on the command line. Paths go into the script as
   single-quoted PowerShell strings with every quote doubled, the typographic ones included, which
   PowerShell also treats as quotes: a user name such as `O'Brien` cannot close the string. Any error
   makes the script exit 1, and its message reaches the log. The registration step and the install
   step are the same two cmdlet calls as ADR 0019.
4. Everything else in ADR 0019 stands: confirmation with No by default, registration before any
   download, SHA-256 required before downloading, `%TEMP%\wgt_winget` removed in a `finally`,
   `-DeferRegistrationWhenPackagesAreInUse`, the window kept open on failure.

## Consequences

**Positive**
- The installed exe stays at about 200 KB; no new dependency.
- The version shown and the version compared are the same number.

**To watch**
- **PowerShell is a second process type** the app starts, next to winget. It never runs winget and
  is started like winget: no shell in between, arguments as a list (ADR 0025).
- The version read waits for any winget in progress; at startup Settings shows it after the scan.
- The per-user package repository is an implementation detail of Windows, not a documented API. If
  it moves, the app says the Store does not update winget and offers the GitHub button, which still
  works: wrong in the safe direction.
- When the COM backend brings the WinRT projection in (ADR 0025), `PackageManager` can replace
  points 2 and 3; measure the exe first, as planned.

## Alternatives considered

1. **The WinRT projection now** — the documented API, but tens of MB in every install for two calls
   made at most once per machine.
2. **Raw WinRT activation (`RoActivateInstance`) with hand-written interfaces** — no projection, but
   a lot of interop code for an async `AddPackageAsync` with progress.
3. **The App Installer version from the package folder name** — no process, but `%ProgramFiles%\WindowsApps`
   cannot be listed by a standard user.
4. **`pwsh`** — not part of Windows.
