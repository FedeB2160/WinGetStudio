# ADR 0014 — Installer alongside the portable exe

- **Status:** Accepted
- **Date:** 2026-10-07 (v1.11.0; [issue #3](https://github.com/FedeB2160/WinGetStudio/issues/3))
- **Depends on:** ADR 0002, ADR 0012, ADR 0013
- **Referenced by:** ADR 0015, ADR 0016

## Context

Up to 1.10.3 WinGet Studio shipped only as one portable exe. Four things were asked for that a portable
cannot give: a Start menu entry, uninstall from Windows Settings, machine-wide deployment an IT
department can script, and the feel of an installed program.

**This supersedes an earlier refusal.** Installing from winget puts nothing on the desktop or in the
Start menu, and no manifest field changes that: the 1.12.0 installer schema does not contain the word
`shortcut`, and shortcuts exist only because a package's *installer* creates them. The request is
[winget-cli#2299](https://github.com/microsoft/winget-cli/issues/2299), open since July 2022, with
[#4185](https://github.com/microsoft/winget-cli/issues/4185) and
[#3314](https://github.com/microsoft/winget-cli/issues/3314) asking the same. Two workarounds were turned
down then (see *Alternatives*), and the decision was to stand until #2299 closed, **or until moving to
a real installer type became a product choice rather than a way of chasing two icons**. On 2026-10-07,
with uninstall from Settings and enterprise deployment on the list, it became one.

The starting point was a spec written with Codex (`2026-10-04-dual-distribution-design.md`, on branch
`codex/bugfixes-1.10.2-ci`). Reviewed against the code and the platforms, it changed on asset order,
the winget migration (ADR 0015), scope, and the supervisor it proposed (ADR 0013).

## Decision

**Every release ships two files**: `WinGetStudio.exe`, the portable, unchanged and kept for good, and
`WinGetStudio_Setup.exe`, built with **Inno Setup 6** from `installer\WinGetStudio.iss`.

**The name `WinGetStudio_Setup.exe` is load-bearing.** The GitHub API returns release assets sorted
by name, case-insensitive, not in upload order (checked on the winget-cli, PowerShell and Inno Setup
releases). Copies up to 1.10.x update from the *first* `*.exe` (ADR 0013). `WinGetStudio-Setup.exe`
would sort first (`-` before `.`) and replace them with the installer; `_` sorts after `.`. Uploading
the portable first does not help, and neither does a staged rollout, since users skip versions.
GitHub does not document the ordering, so the release procedure checks it after every publish:

```powershell
gh api repos/FedeB2160/WinGetStudio/releases/latest --jq '[.assets[] | select(.name | endswith(".exe"))][0].name'
```

It must print `WinGetStudio.exe`.

**The setup (`WinGetStudio.iss`):**

- **Machine scope only**: `PrivilegesRequired=admin`, `DefaultDirName={autopf}\WinGet Studio` (Program
  Files (x86), since the setup is x86). The app always runs elevated (ADR 0002), so a per-user install
  updated by an elevated process would land in the administrator's profile when that is not the
  signed-in user.
- **`AppId={80A0A054-6278-4145-AD5A-2B3C4853019F}` never changes**: it is the `_is1` key by which the app
  recognises itself as installed (`Get-InstallChannel`) and winget correlates the package.
- `AppVersion` and the source exe path are passed in by `build.ps1` from `$AppVersion` (ADR 0001); the
  script refuses to compile without them.
- **Start menu entry always; desktop shortcut as a task, unchecked by default.**
- **`UninstallDisplayName=WinGet Studio`**, the same name as the portable; Inno's default is "WinGet Studio
  version X". winget correlates by ProductCode, not by name.
- **`CloseApplications=yes`**, `RestartApplications=no`: Inno closes a running WinGet Studio through the
  Restart Manager before replacing the exe.
- **Two `[Run]` entries.** A `postinstall skipifsilent` "Launch WinGet Studio" checkbox for interactive
  installs, with `runascurrentuser`: by default `postinstall` runs as the original, unelevated user, and
  the `requireAdministrator` exe failed with error 740. A `nowait` entry with `Check: ShouldRelaunch`
  for the self-update, true when the command line carries `/relaunch=1`. winget does not pass it, so a
  silent winget install relaunches nothing.
- **Signed with the same certificate**, setup and uninstaller (`SignTool` plus `SignedUninstaller=yes`),
  through `src\sign.ps1` (ADR 0012). Without the key the setup comes out unsigned, like the exe.
- **Uninstall keeps `HKCU\Software\WinGetStudio`**: a reinstall finds theme and settings, and the
  uninstaller runs elevated, so it could only reach the administrator's `HKCU` anyway.

**Building.** After signing the exe, `build.ps1` looks for `ISCC.exe` under `Program Files (x86)\Inno
Setup 6` and then on the `PATH`, compiles the setup, and checks that its `FileVersion` and
`ProductVersion` equal `$AppVersion`. **Without Inno the build still succeeds and warns** `setup not
built: winget install JRSoftware.InnoSetup`, so a developer can work on the exe without installing
anything else. A release needs both files, which CI and the release procedure enforce.

**CI** installs Inno Setup **6.7.1**, the newest on Chocolatey (releases are built locally with **6.7.3**),
and a dedicated step fails the build job when either executable is missing: `upload-artifact`'s
`if-no-files-found` fails only when *no* file matches, so the exe alone would otherwise pass.

## Consequences

**Positive**
- A Start menu entry, an entry in Windows Settings, a machine-wide install that can be scripted.
- The portable is untouched for those who want one file.
- Older copies keep updating to the portable, never to the installer.
- An installed copy updates through its own setup, verified and without a second UAC prompt (ADR 0013).

**To watch**
- The asset order check after every release; a rename of either file breaks the older copies.
- Never change `AppId`.
- Local and CI Inno versions differ (6.7.3 and 6.7.1).
- Manual 1.10.x copies stay portable; only winget users are migrated (ADR 0015).
- Tested by hand, in Sandbox or a VM and never on the everyday install: install, Start menu, launch,
  uninstall with preferences kept, and running the setup with `/SILENT /CLOSEAPPLICATIONS /relaunch=1`
  while the app is open, which must close and reopen it.

## Alternatives considered

1. **No installer, no shortcuts** — the stance up to 1.10.3, waiting on winget-cli#2299. Superseded
   here, for the reasons in *Context*.
2. **The app writes the `.lnk` itself on first run** — about forty lines, but the shortcut appears only
   after the app has been started once, which is not what installing a program feels like; and it would
   have to write into the all-users Start menu, since the app elevates and `%APPDATA%` may belong to a
   different administrator than the person at the keyboard.
3. **The app as its own installer** (`InstallerType: exe` plus a silent switch that copies it into
   Program Files and registers it) — removes the first run, but hands over the uninstall path, the ARP
   entry, upgrading over a previous version and failure rollbacks, which an installer compiler does for
   free and without mistakes. Avoiding Inno Setup would cost more code than using it.
4. **`WinGetStudio-Setup.exe`**, or uploading the portable first, or a staged rollout — none keeps the
   portable first in the API's order.
5. **Per-user installs; an MSI; removing the portable** — out of scope.
