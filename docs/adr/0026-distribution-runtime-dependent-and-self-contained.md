# ADR 0026 — Version 2 ships a runtime-dependent installer and a self-contained portable exe

- **Status:** Accepted (for 2.0; amends ADR 0013, 0014 and 0015 there)
- **Date:** 2026-10-29
- **Depends on:** ADR 0012, ADR 0013, ADR 0014, ADR 0015, ADR 0022, ADR 0023, ADR 0024

## Context

1.x ships two assets per release, `WinGetStudio_Setup.exe` (Inno, all users, ADR 0014) and the portable
`WinGetStudio.exe`, both signed with the key of `assets\WinGetStudio-codesign.cer` (ADR 0012); every
copy in the field updates itself only to files signed with that key (ADR 0022).

Measured on 2026-10-29 with the .NET 10 prototype (win-x64, signed with the project key):

| Publish | Size | First frame |
|---|---:|---|
| single-file, framework-dependent | 193 KB | about 0.8 s (1.8 s first run) |
| single-file, self-contained, compressed, native libraries extracted | 64.9 MB | about 1.0 s (2.3 s first run, extracting 7.9 MB to `%TEMP%\.net`) |

- `src\sign.ps1` signs both, with a timestamp; both still run.
- The **1.x self-update check** (`Get-UpdateSignerTrust` and `Test-UpdateSignature` from
  `App.Update.ps1`, run unchanged) **accepts both** (`WinVerifyTrust` `0x800B0109`, the self-signed
  root) and rejects a copy with one byte changed (`0x80096010`).
- The .NET install registry key (`WOW6432Node\dotnet\Setup\InstalledVersions\x64\sharedfx\Microsoft.WindowsDesktop.App`)
  still lists runtime versions that were removed; the folder
  `%ProgramFiles%\dotnet\shared\Microsoft.WindowsDesktop.App\10.*` reflects what is installed.
- `Microsoft.DotNet.DesktopRuntime.10` is a winget package.

## Decision

1. **Same asset names, same signing key.** 1.x users move to 2.0 through the self-update they already
   have, in both channels; winget users through `winget upgrade`.
2. **Installer: framework-dependent single-file** in Program Files, for all users. The setup checks the
   runtime folder (not the registry) and, if .NET 10 Desktop Runtime x64 is missing, installs it with
   `winget install Microsoft.DotNet.DesktopRuntime.10` (winget checks the manifest hash); fallback, the
   official installer from `https://aka.ms/dotnet/10.0/windowsdesktop-runtime-win-x64.exe`, run only if
   its Authenticode signature is Microsoft's. The app is started after setup with `runasoriginaluser`,
   now that it is `asInvoker` (ADR 0024).
3. **winget package:** the Inno installer, with `Dependencies: PackageDependencies:
   Microsoft.DotNet.DesktopRuntime.10`.
4. **Portable: self-contained, compressed single-file.** Its elevated restart (ADR 0024) must not load
   native libraries from a user-writable folder: it sets the extraction folder to a protected location,
   or the elevated restart is offered only in the installed channel. Decided while porting, with a test.
5. **win-x64 only** in 2.0; win-arm64 later if asked. The SDK is pinned with `global.json`.

## Consequences

**Positive**
- The installed app is 200 KB and patched with the shared runtime by Windows Update / winget.
- The portable stays one file with no prerequisites, as today.

**To watch**
- The portable grows from 353 KB to about 65 MB and carries its own runtime: each .NET security patch
  needs a WinGet Studio release for portable users.
- The setup now has a prerequisite step; it must work silently, because the 1.x self-update runs it
  with `/SILENT`.

## Alternatives considered

1. **Self-contained everywhere** — no prerequisite, but 65 MB for every install and the runtime patched
   only by our releases.
2. **Framework-dependent everywhere** — a 200 KB portable that does not start on machines without the
   runtime, which is where a portable is most often used.
