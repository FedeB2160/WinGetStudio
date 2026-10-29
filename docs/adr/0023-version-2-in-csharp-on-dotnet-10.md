# ADR 0023 — Version 2 is written in C# on .NET 10 WPF

- **Status:** Accepted (for 2.0; the 1.x line keeps ADR 0001, 0008 and 0009 until 2.0 replaces it)
- **Date:** 2026-10-29
- **Depends on:** ADR 0001, ADR 0008, ADR 0009, ADR 0010
- **Referenced by:** ADR 0024, ADR 0025, ADR 0026, ADR 0027

## Context

WinGet Studio 1.x is Windows PowerShell 5.1 compiled to one exe with ps2exe (ADR 0001). That runtime is
.NET Framework 4.8, which rules out what the next steps need:

- **The Fluent look.** WPF's Fluent theme (`ThemeMode`) exists only from .NET 9. On 4.8 it would have
  to be rebuilt by hand over the re-templated controls of ADR 0010.
- **winget's COM API.** Its projection (`Microsoft.WindowsPackageManager.ComInterop`) targets .NET 8+
  and `windows10.0.26100`; from PowerShell 5.1 the only route is the `Microsoft.WinGet.Client` module.
- **Startup.** The 1.x window takes over 10 s to open (commit `60fcb2b`): 1.5-2.5 s of app code, the
  rest is the ps2exe host and antivirus scanning of the embedded script.
- **Structure.** Background work in runspaces that re-create functions (ADR 0008), rows compiled with
  `Add-Type` (ADR 0009), and tests that are scripts of assertions (ADR 0016).

A prototype with the 1.x layout (2026-10-29) ran on .NET 10.0.14 with `ThemeMode` and no templates of
its own; published framework-dependent single-file it was 193 KB and drew its first frame in about
0.8 s, self-contained about 1.0 s.

## Decision

**Version 2.0 is a rewrite in C# on .NET 10 (LTS) WPF**, in a new folder `app/` on `main`, built with
ordinary pull requests and no long-lived branch:

```
app/WinGetStudio.sln
app/src/WinGetStudio.Core/   engine: running winget, parsing, exit codes, queue, pins, import/export,
                             self-update, preferences, history. No WPF.
app/src/WinGetStudio/        WPF app, MVVM with CommunityToolkit.Mvvm
app/tests/                   xUnit for Core; view-model and window smoke tests
```

- The 1.x keeps shipping from `src/` and gets fixes only, until 2.0 reaches parity with the README of
  1.x. At the switch `src/`, `ui/` and the PowerShell tests leave the tree (git history keeps them).
- Rules paid for in 1.x carry over as tests before code: one winget process at a time (ADR 0003),
  reads return a result, not a list (ADR 0005), column-position parsing for the CLI (ADR 0006),
  blocking pins (ADR 0007), the exit-code table, details as winget's text (ADR 0021).
- Preferences stay in `HKCU\Software\WinGetStudio` with the same value names, so 1.x settings carry
  over unchanged.
- Code comments in Italian and UI text in English, as in 1.x.

## Consequences

**Positive**
- Fluent theme, COM API, `async`/`await`, real unit tests.
- Startup about ten times faster; the ps2exe antivirus false positives go away with ps2exe.

**To watch**
- A rewrite of about 3,600 lines of PowerShell: every behaviour in the 1.x README is the exit criterion.
- Two products during the transition; the 1.x must not grow new features.
- `DEVELOPMENT.md`, `CLAUDE.md` and `AGENTS.md` describe 1.x until the switch.

## Alternatives considered

1. **Stay on PowerShell 5.1 and restyle by hand** — no runtime and a tiny exe, but Fluent, the COM API
   and the startup time stay out of reach.
2. **PowerShell 7 on .NET 10** — keeps the scripts and gets `ThemeMode`, but ps2exe does not support it,
   so no single exe, and `pwsh` is not part of Windows.
3. **WinUI 3 or Avalonia** — a rewrite either way, plus the Windows App SDK runtime (WinUI 3) or 20 MB of
   native libraries and cross-platform support winget does not need (Avalonia, the path UniGetUI took).
