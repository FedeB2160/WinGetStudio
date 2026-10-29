# ADR 0025 — Version 2 talks to winget through its CLI first, and its COM API where it adds something

- **Status:** Accepted (for 2.0; amends ADR 0004, 0005, 0006 and 0021 there)
- **Date:** 2026-10-29
- **Depends on:** ADR 0003, ADR 0004, ADR 0005, ADR 0006, ADR 0021, ADR 0023, ADR 0024

## Context

1.x runs winget's CLI and reads its fixed-width tables by column position (ADR 0006). The rules that
made it reliable are paid for: UTF-8 decoding, never waiting on pipe EOF that an installer's child can
hold open, the real exit code, quoting without a shell, and (v1.13) refusing `%`, which `cmd` expands.

winget also has a COM API (`Microsoft.Management.Deployment`). Measured on 2026-10-29 from an
unelevated .NET 10 process with `Microsoft.WindowsPackageManager.ComInterop` 1.29.280:

- activation in 44-117 ms; 326 installed packages in 3.3 s (108 ARP, 122 MSIX, one "Unknown" version);
  the same 4 upgradable Ids as `winget upgrade --include-unknown`, and every COM Id present in
  `winget list`; structured metadata (publisher, licence, homepage, icons);
- installs with progress events: download percentage, then installing and post-install states;
- the projection requires the `windows10.0.26100` TFM;
- lists from the server do not expose `IIterable` to the proxy, so `foreach` fails and they are read by
  index;
- from an **elevated** process activation fails with `0x80040154`;
- no pins, export or import in the API.

## Decision

1. **`IWinGetBackend` in `WinGetStudio.Core`, with the CLI backend first.** 2.0 reaches parity with 1.x
   on the CLI alone, porting ADR 0004-0006 and 0021 with their tests.
2. **The CLI is started without `cmd`.** `CreateProcess` with inheritable file handles for stdout and
   stderr, waiting on the process alone: no pipe for a child installer to hold open (ADR 0004), and no
   `%` expansion to guard against. Arguments are an argument list, never a string for a shell. Ids are
   validated. `--no-progress` is passed when winget is 1.29 or later (it is accepted though `--help` does
   not list it); the `\r` filtering stays for older versions.
3. **The COM backend comes after parity** (plan phase 4), only when unelevated: reads with structured
   fields, details, icons, and installs, updates and uninstalls with per-row progress. If activation fails
   the CLI takes over. Lists are read by index.
4. **Always CLI:** pins, export, import, the elevated retry of ADR 0024, and the whole elevated mode.
5. **Exit codes** keep one table, the one fixed in v1.13 (`0x8A150109`, `0x8A15010B`, `0x8A15010D`, 3010
   and 1641 are warnings), mapped from the CLI exit code and from `InstallResult.ExtendedErrorCode` /
   `InstallerErrorCode` alike.

## Consequences

**Positive**
- Parity rests on code already proven in 1.x; the COM API adds progress and fields without becoming a
  single point of failure.
- No shell between the app and winget.

**To watch**
- Two backends to keep consistent: the same test fixtures run against both where they overlap.
- The ComInterop package version follows winget releases; `winget-cli#4377` (crash of elevated
  unpackaged callers through `winrtact.dll`) does not apply because elevated mode never uses COM.

## Alternatives considered

1. **COM only** — no pins, export or import, nothing when elevated.
2. **Pinget** (Devolutions' Rust rewrite of the winget client, used by UniGetUI) — a different engine
   from the one that installs, version 0.x, and a third-party binary run with the user's rights.
3. **The `Microsoft.WinGet.Client` PowerShell module** — the right bridge for PowerShell 5.1, pointless
   once the app is .NET.
