# ADR 0001 — One exe built from modules

- **Status:** Accepted
- **Date:** 2026-08-04
- **Depends on:** —
- **Referenced by:** ADR 0002 (the self-elevation lives in `main.ps1`), ADR 0008 (runspaces and dot-sourcing scope), ADR 0010 (the theme XAML is embedded), ADR 0012 (the build signs the exe), ADR 0013 (`$AppVersion` against the release tag), ADR 0016 (the tests re-do the injection)

## Context

WinGet Studio is distributed as a single executable you can copy to another machine on its
own. ps2exe, which turns the PowerShell into that exe, compiles exactly **one** input file.

Up to v1.0.0 the tool was one 744-line script. In v1.9.0 it became an entry point plus one
module per concern under `src\modules\`. That put two requirements in tension: the source is
now many files, the exe must still be one.

The UI is described in three XAML files (`ui\UI.xaml`, `ui\Theme.Light.xaml`,
`ui\Theme.Dark.xaml`) that have the same problem: they are easier to edit as files, and the exe
must not depend on them being shipped beside it.

## Decision

**`src\main.ps1` holds no logic**: it sets the version, elevates (ADR 0002), loads the modules
and calls `Start-App`. It is a separate file because ps2exe takes one input and the
self-elevation has to run before anything else.

**The build concatenates, running from source dot-sources.** `src\build.ps1` replaces the
`###MODULES###` marker in `main.ps1` with the concatenated modules, then the `###UI.xaml###`,
`###Theme.Light.xaml###` and `###Theme.Dark.xaml###` markers with the file contents — modules
first, since the XAML markers live inside `App.Bootstrap.ps1`. It writes the result to a
temporary source in `%TEMP%` and hands that to ps2exe (`-requireAdmin`, `-noConsole`,
`-iconFile`). Each marker is a **PowerShell comment line**, so running `main.ps1` directly leaves
it inert: `main.ps1` then sees that `Get-WinGetPath` (the first function of the first module) is
missing and dot-sources the modules from disk. A module can be edited and the app relaunched
with no rebuild.

**`$moduleNames` in `src\main.ps1` is the single module list.** `build.ps1` reads it with a
regex rather than keeping its own copy. The order matters only for file-level code (`Add-Type`,
variables); `App.Bootstrap.ps1` goes last as the orchestrator.

**`$AppVersion` in `src\main.ps1` is the single version.** `build.ps1` reads it with a regex and
passes it to ps2exe, so the exe properties (right click, Properties, Details) and the version the
app shows can never disagree. It must also match the git tag, which the self-update compares
against (ADR 0013).

**A XAML file on disk wins over the embedded copy.** Lookup order: `..\ui\<file>`,
`<exe folder>\ui\<file>`, `<exe folder>\<file>`. A UI tweak can be tried without recompiling;
without the files the exe still runs on its own.

**Dot-sourcing creates no scope**, so the modules see each other's variables exactly as they do
when concatenated. `Start-App` is a function, so it assigns the controls with `$script:` — a plain
`$Grid = ...` inside it would be local, and every module reading `$Grid` would get `$null`.

## Consequences

**Positive**
- One file to download, copy or install; no runtime dependency on the XAML or the modules.
- Edit a module or a XAML file, relaunch, no rebuild.
- A new module cannot silently be left out of the exe, and the version cannot drift between the
  exe metadata and the app.
- The build fails loudly instead of producing a wrong exe: a missing marker, a listed module
  that is absent, a missing or renamed `$AppVersion`, an exe that was not rewritten, or exe
  metadata that does not carry `$AppVersion` all throw. A XAML line starting with `'@` — the only
  way the injection into a here-string could break silently — is refused too.
- ps2exe is pinned to version 1.0.18, the same as CI, so a release exe cannot come out of a
  different compiler from the one that was checked (since v1.10.2).

**To watch**
- The exe loads code differently from the `.ps1`. A failure that only exists in the concatenated
  form would show up only on a double click, so `Test-Ui.ps1` re-does the injection and checks
  that the concatenated source parses and keeps every function (ADR 0016).
- A module missing from, or orphaned by, `$moduleNames` fails `Test-Ui.ps1`, which reads the
  array with the same regex as `build.ps1`.
- Tag and `$AppVersion` must agree at release time; a mismatch makes the app either keep
  proposing an update already installed or never propose one.
- The temporary source is written as UTF-8 with BOM: without it PowerShell 5.1 reads the
  source as ANSI and mangles accented letters.

## Alternatives considered

1. **Keep the module list in `build.ps1` too** — turned down: two copies diverge, and a new module
   ends up outside the exe without anyone noticing.
2. **Ship the XAML files next to the exe as a runtime requirement** — turned down: the exe must
   stay a single file that can be copied to another machine on its own. Files on disk are still
   honoured when present.
