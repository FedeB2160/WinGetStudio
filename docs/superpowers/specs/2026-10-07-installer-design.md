# Installer alongside the portable exe — design

**Date:** 2026-10-07 · **Target version:** 1.11.0 · **Issue:** https://github.com/FedeB2160/WinGetStudio/issues/3

## Why

WinGet Studio ships as one portable exe. The user wants four things the portable cannot give: a Start menu entry, uninstall from Windows Settings, machine-wide deployment an IT department can script, and the feel of an installed program. DEVELOPMENT.md ("No shortcuts") had turned an installer down as a way of chasing two icons; with uninstall and enterprise deployment on the list it is now a product choice, which is the condition that section set for revisiting it.

The starting point was a spec written with Codex (`docs/superpowers/specs/2026-10-04-dual-distribution-design.md` on branch `codex/bugfixes-1.10.2-ci`). Reviewed against the code and the platforms, it had to change in these places:

- **Asset order.** The GitHub API returns release assets sorted by name, case-insensitive, not in upload order (checked on winget-cli, PowerShell and Inno Setup releases: ids not monotonic, names sorted). Copies up to 1.10.x update from the *first* `*.exe`; a setup named `WinGetStudio-Setup.exe` sorts before `WinGetStudio.exe` and would replace them with the installer. Uploading the portable first does not help, and neither does a staged rollout, since users skip versions.
- **winget migration.** winget refuses to upgrade a `portable` install to an `inno` one ("different install technology", `ManifestComparator.cpp` `IsInstallerCompatibleWith`). `UpgradeBehavior: uninstallPrevious` alone does not get past that check.
- **Scope.** The app always runs elevated, so a per-user install updated by an elevated process lands in the administrator's profile when that is not the signed-in user. Machine scope only.
- **Supervisor, origin marker, separate winget channel.** Not needed: Inno closes and relaunches the app itself, and a single "installed" channel serves manual and winget installs alike.

## Decisions

| Topic | Decision |
| --- | --- |
| Artifacts | `WinGetStudio.exe` (portable, unchanged, kept for good) and `WinGetStudio_Setup.exe` (Inno) in every release |
| Installer tool | Inno Setup 6 (installed locally; 6.7.3 on winget and Chocolatey) |
| Scope | Machine only, `PrivilegesRequired=admin`, `{autopf}\WinGet Studio` (Program Files (x86): the Inno setup is x86) |
| AppId | `{80A0A054-6278-4145-AD5A-2B3C4853019F}`, never to change |
| Shortcuts | Start menu always; desktop as an installer task, unchecked by default |
| Uninstall | Removes program and shortcuts; **keeps** `HKCU\Software\WinGetStudio` |
| winget package | Moves to `inno` with a tested migration; falls back to `portable` if the Sandbox test fails |
| Setup verification on self-update | SHA-256 digest **required** (the portable keeps today's warning when there is none) |

## Design

### 1. Artifacts and names

`WinGetStudio_Setup.exe` sorts after `WinGetStudio.exe` (`.` before `_`), so every older copy keeps taking the portable from any future release. GitHub does not document the ordering, so the release procedure checks it after every publish: the first `*.exe` the API returns must be `WinGetStudio.exe`. New versions select their asset by exact name (section 4).

### 2. The installer (`installer\WinGetStudio.iss`)

- `AppId` as above, `AppName=WinGet Studio`, `AppPublisher=FedeB2160`, `AppVersion` passed in by `build.ps1` from `$AppVersion`; the source exe path is passed in too.
- `PrivilegesRequired=admin`, `DefaultDirName={autopf}\WinGet Studio`.
- `[Icons]`: Start menu entry; `[Tasks]` `desktopicon` with `Flags: unchecked`.
- `CloseApplications=yes`: Inno closes a running WinGet Studio through the Restart Manager before replacing the exe.
- `[Run]`:
  - a `postinstall skipifsilent` entry, "Launch WinGet Studio", for interactive installs;
  - a `nowait` entry with `Check: ShouldRelaunch` for the self-update, where `ShouldRelaunch` (three lines of `[Code]`) is true when the command line carries `/relaunch=1`;
  - a silent winget install relaunches nothing.
- Signing: setup and uninstaller (`SignTool`, `SignedUninstaller=yes`), through `Set-AuthenticodeSignature` with the same certificate and timestamp server `build.ps1` uses for the exe. No `signtool.exe` dependency.
- Uninstall removes `{app}` and the shortcuts and leaves the preferences: a reinstall finds the theme and settings, and the uninstaller runs elevated, so it could only reach the administrator's `HKCU` anyway.

### 3. Install channel (`Get-InstallChannel`, `App.Update.ps1`)

Checked in this order:

| Channel | Detected by | Update |
| --- | --- | --- |
| `source` | `Get-RunningExePath` returns `$null` | none ("use git"), as today |
| `winget-portable` | `Test-IsWinGetPortable` (exe under `\Microsoft\WinGet\Packages\`) | message "use `winget upgrade`", as today |
| `installed` | exe folder equals `InstallLocation` of `HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{AppId}_is1` | through the setup (section 4) |
| `portable` | anything else | rename and restart, as today |

The x86 setup writes that key in the 32-bit view (`WOW6432Node`), but the ps2exe exe is AnyCPU and runs as a 64-bit process, whose `HKLM:\SOFTWARE` reads the 64-bit view. The function therefore opens the `Registry32` view explicitly. The first version relied on a redirection that never happens; the final review caught it. The function takes the exe path and the install location as parameters, defaulting to the real values, so the test can cover the four channels without touching the registry.

### 4. Update flow

`Get-LatestRelease` receives the asset name for the channel (`WinGetStudio.exe` for `portable`, `WinGetStudio_Setup.exe` for `installed`) and matches it exactly. If the release lacks it, no update is offered; a manual check says why.

`installed`, after the usual confirmation:
1. Download the setup to `%TEMP%` (path built with `[IO.Path]::Combine`).
2. Verify the SHA-256 digest GitHub publishes. Missing or mismatched: abort and delete the file — the next step runs an installer with administrator rights.
3. Start it with `/SILENT /CLOSEAPPLICATIONS /relaunch=1 /LOG="<temp>\WinGetStudio-update.log"`, write the log path to the app log, close the window. The app is already elevated, so no second UAC prompt.
4. On failure the `/SILENT` wizard shows the error and the app is not relaunched; the details are in the log.

`portable`: today's flow unchanged apart from choosing the asset by name. Tooltips and the confirmation name the file that will be downloaded and what happens next.

### 5. winget manifest and migration

- `InstallerType: inno`, `Scope: machine`, `ElevationRequirement: elevatesSelf`, `InstallerUrl` → `WinGetStudio_Setup.exe` with its hash.
- `UpgradeBehavior: uninstallPrevious`.
- `AppsAndFeaturesEntries`, two items:
  - `ProductCode: '{80A0A054-6278-4145-AD5A-2B3C4853019F}_is1'`, `InstallerType: inno` (new installs);
  - the ProductCode winget uses for the existing portable install, `InstallerType: portable`. This is the item that lets the comparator accept the upgrade from portable. winget names a portable's `HKCU` uninstall key `<PackageIdentifier>_<SourceIdentifier>`, i.e. `FedeB2160.WinGetStudio_Microsoft.Winget.Source_8wekyb3d8bbwe`; the Sandbox test reads the real key name before the manifest is final.
- A 1.10.x winget user running `winget upgrade` gets the portable removed (exe, alias, `HKCU` entry) and the setup installed, with a UAC prompt. Manually downloaded 1.10.x copies stay portable.
- **Gate before submitting**: in Windows Sandbox, with winget-pkgs' `Tools\SandboxTest.ps1` (the Sandbox has no winget of its own): install 1.10.x from the published portable manifest, `winget upgrade` with the new manifest, then check no duplicate copy, old alias gone, Start menu entry and Settings entry present, `winget list` shows the new version, `winget upgrade` does not offer it again. If this fails, the winget package stays portable and the installer ships only on GitHub.

### 6. Build and CI

- `build.ps1`, after compiling and signing the exe: look for `ISCC.exe` (`${env:ProgramFiles(x86)}\Inno Setup 6\`, then `PATH`), run it with the version and the exe path, producing `dist\WinGetStudio_Setup.exe`. With the published certificate available, pass the signing command; otherwise build unsigned with a warning, like the exe. Extend the version check to the setup's `FileVersion`.
- No Inno installed: build the exe, warn `setup not built: winget install JRSoftware.InnoSetup`, still succeed — developers are not forced to install it. Releases need both files, which CI and the release procedure enforce.
- CI `build` job: `choco install innosetup --version=6.7.3 -y` before `build.ps1`; the artifact holds both files and fails when either is missing.

### 7. Tests and documentation

Tests:
- `Test-Ui.ps1`, offline:
  - `Get-InstallChannel` on its four channels;
  - `Get-LatestRelease` choosing by name from an asset list where the setup sorts first;
  - the `installed` channel refusing an asset with no digest;
  - the setup name consistent across `.iss`, `App.Update.ps1`, CI and DEVELOPMENT.md, and sorting after `WinGetStudio.exe`;
  - the `.iss` `AppId` being a GUID.
- `-Live`: the existing release test finds the portable asset in the real release.
- By hand, in Sandbox or a VM, never on the everyday install:
  - install, Start menu, launch, uninstall from Settings with the preferences kept;
  - the migration in section 5;
  - running the setup with `/SILENT /CLOSEAPPLICATIONS /relaunch=1` while the app is open, which must close and reopen it.

**Known limit:** the full "find release → download → install" path of the `installed` channel can only run once a newer release exists; download and verification are shared with the portable path and already tested.

Documentation:
- DEVELOPMENT.md:
  - "No shortcuts" becomes the record of this decision, dated, with its reasons;
  - update the signing, publishing (two files, order check), winget-pkgs and self-update sections, and add `installer\WinGetStudio.iss` to the tree.
- README: the install section (setup recommended, portable, winget), uninstall from Settings and what it keeps, how each form updates.
- CLAUDE.md: `build.ps1` also builds the setup when Inno is present; the four channels in one line.
- CHANGELOG: one line under `## Unreleased`.

## Out of scope

Per-user installs; an MSI; changing the portable's own update flow beyond choosing the asset by name; requiring a digest for the portable; removing the portable.
