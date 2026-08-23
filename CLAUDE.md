# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

WinGet Studio is a WPF front end for `winget`, written in PowerShell 5.1 and compiled to a single self-elevating `.exe` with ps2exe.

## Commands

```powershell
# Run from source (UAC prompt first; self-update disabled in this mode)
powershell -ExecutionPolicy Bypass -File .\src\main.ps1

# Build dist\WinGetStudio.exe (also: double click build.bat). Installs ps2exe if missing.
powershell -ExecutionPolicy Bypass -File .\src\build.ps1

# Tests — two standalone scripts, no framework, no runner
powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-Ui.ps1
powershell -ExecutionPolicy Bypass -File .\tests\Test-InvokeWinGet.ps1

# winget manifests
winget validate --manifest .\winget\1.9.0
```

`Test-Ui.ps1` requires `-STA` (WPF), touches winget read-only, and runs one real pin cycle on `7zip.7zip`. There is no single-test selector: each script is one file of sequential assertions — comment out or run the file.

## Architecture

**Single file at runtime, modules on disk.** ps2exe compiles exactly one input file, so `src\build.ps1` substitutes markers in `src\main.ps1`: `###MODULES###` becomes the concatenated `src\modules\*.ps1`, and `###UI.xaml###` / `###Theme.Light.xaml###` / `###Theme.Dark.xaml###` (which live inside `App.Bootstrap.ps1`) become the XAML contents. The markers are PowerShell comment lines, so running `main.ps1` directly leaves them inert and the modules are dot-sourced from disk instead — edit a module, relaunch, no rebuild.

Consequences that constrain edits:

- **`$moduleNames` in `src\main.ps1` is the single module list.** `build.ps1` reads it with a regex; a new module not listed there is silently absent from the exe. `Test-Ui.ps1` fails on a module missing from, or orphaned by, that array.
- **`$AppVersion` in `src\main.ps1` is the single version.** `build.ps1` reads it with a regex for the exe metadata; it must also match the git tag, since the self-update compares them.
- Dot-sourcing creates no scope, so modules see each other's variables exactly as when concatenated. `Start-App` (in `App.Bootstrap.ps1`) is a function, so it assigns controls with `$script:` — a plain `$Grid = ...` would be local and every module would read `$null`.
- The three `.xaml` files are embedded but a file on disk wins: lookup order `..\ui\<file>`, `<exe folder>\ui\<file>`, `<exe folder>\<file>`.

**Module roles.** `WinGet.Exec.ps1` runs winget; `WinGet.Parse.ps1` reads its fixed-width tables; `App.Ui.ps1` holds `Write-Log` and the global busy state; `App.Jobs.ps1` the background runspaces; then theme, pins, backup, self-update, settings; `Tab.*.ps1` one per tab; `App.Bootstrap.ps1` last, as the orchestrator (`WgtRow`, XAML loading, `Start-App`).

**Background work.** Runspace code cannot touch controls — every UI write goes through the `UI{}` helper (`$window.Dispatcher.Invoke`). Runspaces do not inherit functions: pass their names to `Start-BackgroundJob -Functions` and the body is recreated inside. Pass state through the job object, never a `GetNewClosure()` capture — a closure gets its own module scope where `$script:` no longer refers to the script.

**Only ever one winget process at a time.** Two concurrent invocations make one fail with exit 1. Scans read pins inside the same job; after a pin/unpin the busy state is released by the pin re-read, which is the last step. Busy state is global — each tab registers a handler with `Set-AppBusy`.

**Grid rows are `WgtRow`**, a class compiled with `Add-Type` implementing `INotifyPropertyChanged`, not `PSCustomObject` — `NoteProperty` values do not notify WPF and forced a `$Grid.Items.Refresh()` that reset the scroll position.

**Themes.** Colours are always `{DynamicResource ...}`; `StaticResource` resolves once and would not follow a theme change. Both theme files must define the same keys — `Test-Ui.ps1` fails otherwise. Several controls (CheckBox, DataGridColumnHeader, ContextMenu/MenuItem, ComboBox) are fully re-templated because Aero2 hardcodes light colours; the re-templated header must keep the `PART_LeftHeaderGripper` / `PART_RightHeaderGripper` thumbs or column resizing breaks with no error.

Glyphs must be written `[char]0xE706`, never `` "`u{E706}" `` — that escape needs PowerShell 6 and ps2exe targets 5.1.

**[DEVELOPMENT.md](DEVELOPMENT.md) carries the full rationale** — parser quirks, WPF traps, layout choices, signing, release and winget-pkgs publishing. Read the relevant section before changing parsing, the job machinery or the themes: most of those oddities are bugs already paid for once.

## Conventions

- **UI text and documentation in English; in-code comments in Italian.** User-facing strings live in `ui\UI.xaml` and in the `Write-Log` / `LogUI` / `MessageBox` calls under `src\modules\`.
- Signing: `build.ps1` picks `$env:WINGETSTUDIO_CERT_THUMBPRINT` if set, else the first code-signing certificate in `Cert:\CurrentUser\My`; it still succeeds unsigned. Private keys (`*.pfx`, `*.p12`, `*.snk`) are gitignored — only the public `.cer` is committed.
- `graphify-out\` holds a knowledge graph of this repo; `graphify query "..."` answers *why* questions that span code, DEVELOPMENT.md and the changelog. Only `GRAPH_REPORT.md`, `graph.json` and `graph.html` are committed.
