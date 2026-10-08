# ADR 0015 — winget package: portable, then inno

- **Status:** Accepted
- **Date:** 2026-08-04 (v1.9.0, as `portable`; `inno` since v1.11.0, rehearsed in Windows Sandbox on 2026-10-07)
- **Depends on:** ADR 0002, ADR 0013, ADR 0014

## Context

WinGet Studio is published in the community repository `microsoft/winget-pkgs` as
`FedeB2160.WinGetStudio`. From 1.9.0 to 1.10.3 the only release asset was the portable exe; from
1.11.0 there is a setup too (ADR 0014), and existing winget users had to be moved onto it.

winget does not make that move easy. It refuses to upgrade a `portable` install to an `inno` one
("different install technology", `ManifestComparator.cpp`, `IsInstallerCompatibleWith`), and
`UpgradeBehavior: uninstallPrevious` alone does not get past that check.

## Decision

**1.9.0 to 1.10.3: `InstallerType: portable`.** A bare executable that winget copies into its own
package folder and aliases on the PATH, with `Architecture: x86` and `ElevationRequirement:
elevatesSelf` — the exe's `requireAdministrator` manifest elevates it at startup (ADR 0002), so the
install needs no privileges and running it does. The alias is left to winget, which derives
`WinGetStudio` from the file name.

**From 1.11.0: `InstallerType: inno`**, pointing at `WinGetStudio_Setup.exe`. The migration rests on
four fields:

- **`UpgradeBehavior: uninstallPrevious`**, so the portable copy is removed before the setup runs.
- **`AppsAndFeaturesEntries` with two items**: `{80A0A054-6278-4145-AD5A-2B3C4853019F}_is1` as `inno`
  (new installs), and the portable's uninstall key `FedeB2160.WinGetStudio_Microsoft.Winget.Source_8wekyb3d8bbwe`
  as `portable`. winget filters out installers whose type does not match what is installed, unless an
  entry here declares that type; this is the item that lets the comparator accept the upgrade. winget
  names a portable's `HKCU` uninstall key `<PackageIdentifier>_<SourceIdentifier>`; the exact name was
  confirmed in the Sandbox before the manifest was final.
- **`ProductCode` as the `_is1` key**, which is how winget finds the installed copy afterwards.
- **No `Scope`.** On upgrade winget's `InstalledScopeFilter` rejects an installer whose declared scope
  differs from the installed one. A portable is installed per user, so `Scope: machine` failed with
  *No applicable installer found* in the rehearsal; an undeclared scope passes the filter. The setup is
  machine-only regardless, through `PrivilegesRequired=admin`.

Also: **`Architecture: x86`** — the Inno setup is a 32-bit program; the exe it installs is AnyCPU and
runs 64-bit on x64. **`ElevationRequirement: elevatesSelf`** — the setup asks for elevation itself, so
winget needs no elevated prompt to start it.

**The gate before submitting was a Sandbox rehearsal.** On 2026-10-07, with winget 1.29.380 in Windows
Sandbox: 1.10.2 installed from the winget source, then `winget upgrade --manifest` to a 1.11.0 inno test
setup served by a local HTTP server. Checked: no duplicate copy, the old alias gone, Start menu and
Settings entries present, `winget list` showing the new version, `winget upgrade` not offering it again.
Had it failed, the package would have stayed `portable` and the installer shipped only on GitHub.

**Manifests are kept in `winget\<version>\`** — three files, as the community repository requires — so
they are reviewed and versioned with the code; `winget validate --manifest .\winget\<version>` runs the
same validator as the moderators. The pull request copies that folder to
`manifests\f\FedeB2160\WinGetStudio\<version>\`.

## Consequences

**Positive**
- `winget upgrade FedeB2160.WinGetStudio` moves a 1.10.x portable to the installed form: the exe, the
  `WinGetStudio` alias and its uninstall entry are removed and the setup installed, with a UAC prompt
  and a Start menu entry.
- From then on the copy is in the `installed` channel and can update itself or be updated by winget
  (ADR 0013).

**To watch**
- **`wingetcreate update` does not submit the local folder.** It downloads the last published manifest,
  bumps version, URL, hash and date, and submits that: everything version-specific is lost, comments
  included, and `ReleaseNotes` is dropped — the validator then fails with `Missing property
  ReleaseNotes`, so the block has to be added back on the fork branch. It also invents a
  `Documentations` entry pointing at the repository wiki, which has no pages. The local folder is the
  source of the text, not of the submission: after the pull request is open, copy back what was
  actually submitted.
- `PortableCommandAlias` (portable manifests) is rejected by the validator as an unknown field. The
  alias winget makes is a symbolic link in `%LOCALAPPDATA%\Microsoft\WinGet\Links`, which needs
  administrator rights or Developer Mode: from an ordinary prompt winget reports the alias as added but
  the link is not there. The pull request's sandbox is elevated, so it does not see this.
- `Commands` was declared in the locale manifest sent for 1.9.0 but is absent from the published 1.9.0,
  so it is gone from later versions; it only feeds searching by command.
- Every YAML value with a `:` inside must be quoted — `ShortDescription` is the one that bites.
- Installing from a local manifest needs `winget settings --enable LocalManifestFiles` from an elevated
  prompt.

## Alternatives considered

1. **Stay `portable`** — the fallback had the Sandbox rehearsal failed; not needed.
2. **`UpgradeBehavior: uninstallPrevious` alone** — does not pass `IsInstallerCompatibleWith`.
3. **`Scope: machine`** — failed the rehearsal with *No applicable installer found*.
4. **A separate winget update channel** — not needed: one `installed` channel serves manual and winget
   installs alike (ADR 0013).
