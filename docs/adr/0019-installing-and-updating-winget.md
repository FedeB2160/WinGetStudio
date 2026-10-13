# ADR 0019 — Installing and updating winget

- **Status:** Accepted
- **Date:** 2026-10-13
- **Depends on:** ADR 0002, ADR 0003, ADR 0004, ADR 0008, ADR 0013

## Context

Up to v1.11.1, when `Get-WinGetPath` found no winget, `Start-App` showed a message box before the
window existed and the app exited. On Windows 10 1809+ and 11 with the Microsoft Store, App
Installer (the package that carries winget) ships with Windows, so this happens mostly:
- in Windows Sandbox, Windows LTSC and Windows Server, which have no Store;
- on a profile created moments ago, before the Store has registered App Installer;
- under UAC with an administrator account other than the signed-in one, whose profile never had
  App Installer registered.

When winget was there, the app said nothing about its version. The latest winget release on GitHub
ships `Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle` (about 217 MB) and
`DesktopAppInstaller_Dependencies.zip` (about 98 MB, one folder per architecture: VCLibs,
VCLibs.UWPDesktop, WindowsAppRuntime), each with a SHA-256 `digest`. From v1.28, App Installer's
package version equals winget's (App Installer 1.29.380.0 is winget v1.29.380). Before, App
Installer ran 15 minors ahead (1.27 was winget 1.12), and winget jumped from v1.12 to v1.28.

## Decision

**When winget is missing, the app opens anyway and offers to install it.**
- `Start-App` no longer exits. The first `ContentRendered` calls `Start-WinGetInstall -Missing`
  instead of the scan: the install can take minutes and needs the log and the progress bar.
- A Yes/No confirmation, **default No**, comes before anything else; No closes the app, as before.
- One background job, with the busy state raised:
  1. `Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe`,
     Microsoft's own fix for an App Installer that is on disk but not registered for the account.
     Seconds, no download.
  2. If winget is still missing, `Install-WinGetPackage` downloads both assets of the latest
     release, refuses an asset without a published SHA-256 **before** downloading it, checks the
     file, unpacks the dependencies of this Windows' architecture (`Get-WinGetDependency`) and runs
     `Add-AppxPackage -Path <bundle> -DependencyPath <deps>` for the current account. Everything
     sits in `%TEMP%\wgt_winget`, removed in a `finally` and swept at startup if the process died.
- On success the scan starts. On failure a message box gives the reason and points to the Store,
  the GitHub releases and *App execution aliases*. The window stays open with the busy state raised:
  the log holds the real cause (a dead job's error included), and closing would lose it.

**`Get-WinGetPath` falls back to the alias.** When `Get-Command` finds nothing, it tries
`%LOCALAPPDATA%\Microsoft\WindowsApps\winget.exe`: a PATH without WindowsApps is a known winget
problem, and without the fallback a freshly installed winget would be offered again at every start.

**The version shown is App Installer's, read from the package.** `Get-WinGetVersion` uses
`Get-AppxPackage`, not `winget --version`, so it starts no winget process and runs alongside the
scan (ADR 0003). Settings shows it as it is ("App Installer 1.29.380.0"), with no mapping for the old
numbering; compared with the latest tag it gives the right answer either way.

**Who updates App Installer.** `Test-StoreUpdatesWinGet` decides:
- **The Store**, when `Microsoft.WindowsStore` is registered for this account and no policy under
  `HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore` sets `RemoveWindowsStore=1` or `AutoDownload=2`.
  The Store updates App Installer on its own, by delta. Settings shows "Updated by the Microsoft
  Store" with a link to `ms-windows-store://downloadsandupdates`, and nothing goes to GitHub.
- **The app**, everywhere else. `Start-WinGetCheck` asks GitHub for the latest release
  (`Get-LatestRelease`, `Test-NewerVersion`, unchanged). When it is newer, an **Update to vX**
  button appears in Settings and the log says so. The button runs `Start-WinGetInstall`:
  the same confirmation with default No, `Test-WinGetBusy`, the same job without the registration step.

**The checks run in parallel with the scan.** `ContentRendered` starts `Start-UpdateCheck`,
`Load-Upgrades` and `Start-WinGetCheck` together; only `Load-Upgrades` starts winget. The
winget check honours **Check for updates at startup** for its GitHub call (the local version is
always read), and **Check for updates** checks both the app and winget.

**No forced shutdown.** `Add-AppxPackage` gets `-DeferRegistrationWhenPackagesAreInUse`: if an App
Installer process is running (winget in a terminal, its COM server), the new version is staged and
starts when they close. When the version read after the install is still older, the log says so.

## Consequences

**Positive**
- A machine without winget gets it from inside the app, with a confirmation and a checksum, instead
  of a dead end. The common cases (new profile, other admin account) take seconds.
- Machines without a Store see their winget age and can update it; machines with one are told the
  Store handles it and make no extra network call.
- No winget process is added: the version comes from the package, the latest release from GitHub.

**To watch**
- **The asset names are a contract with Microsoft.** A renamed asset breaks the install. The live
  suite checks both names and their checksums.
- **About 315 MB per install or update** from GitHub, where the Store would download a delta.
- **The registration is for the elevated account.** Under UAC with another administrator, winget
  is registered for that account: the app works, and per-user packages land in its profile (ADR
  0002, ADR 0018).
- Not verified beforehand: `Add-AppxPackage` on LTSC and Server 2019/2022, and on ARM64 Windows
  running the exe as x64. A failure there is a readable error.
- If winget is missing on a machine that has the Store (App Installer removed by hand), the app
  still downloads from GitHub rather than sending the user to the Store.

## Alternatives considered

1. **Only a link to the Store** — almost no code, but useless where there is no Store: Sandbox,
   LTSC, Server. Those are where winget is most often missing.
2. **`Repair-WinGetPackageManager`** (Microsoft.WinGet.Client, Microsoft's documented bootstrap) —
   it installs the NuGet provider and a PSGallery module for good, needs PSGallery to be reachable,
   and downloads the same 315 MB anyway.
3. **`winget --version`** — the exact winget number, but a winget process that must not overlap
   the scan (ADR 0003).
4. **Only the Updates tab** — App Installer already shows there as `Microsoft.AppInstaller` when the
   catalog has a newer version. It stays there, unchanged. But winget updating itself is the least
   reliable path, and it gives no version to look at.
5. **The GitHub button everywhere** — 315 MB to get a version the Store delivers by delta,
   and an update notice on every machine for something that updates itself.
6. **`-ForceApplicationShutdown` / `-ForceTargetApplicationShutdown`** — the first also closes the
   processes of apps using the dependencies, the second a winget the user has open in a terminal.
7. **`Add-AppxProvisionedPackage` for all users** — needs the license file and covers profiles the
   app never runs in; the app needs winget for the account it runs as.
