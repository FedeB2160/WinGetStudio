# WinGet Update Tool

Standalone Windows tool (WPF) that lists `winget` updates in a checkbox table and upgrades only the selected entries. Automatic UAC elevation, non-blocking UI, light/dark theme, no branding.

The **UI and this documentation are in English**; the in-code comments are in Italian. User-facing strings live in `ui\UI.xaml` (labels, column headers) and in the `Write-Log` / `LogUI` / `MessageBox` calls of `src\WinGetUpdateTool.ps1`.

## Layout

```
build.bat                    double click -> produces dist\WinGetUpdateTool.exe
README.md
src\   WinGetUpdateTool.ps1  main script (logic + winget)
       build.ps1             ps2exe compilation
ui\    UI.xaml               window: layout and styles
       Theme.Light.xaml      light palette
       Theme.Dark.xaml       dark palette
assets\icon.ico              app icon (embedded in the exe)
tests\ Test-Ui.ps1           headless check of XAML and themes
       Test-InvokeWinGet.ps1 winget execution tests
dist\  WinGetUpdateTool.exe  build output
```

The three `.xaml` files are **not** a runtime requirement: `build.ps1` injects them into the exe, which stays a single file you can copy to another machine on its own. If a `.xaml` file *is* present on disk it wins over the embedded copy — handy for tweaking the UI without recompiling. Lookup order: `..\ui\<file>`, `<exe folder>\ui\<file>`, `<exe folder>\<file>`.

## Requirements
- Windows 10/11 with **winget** (App Installer from the Microsoft Store).
- PowerShell 5.1+.
- The **ps2exe** module (only to compile): `Install-Module ps2exe -Scope CurrentUser`.

## Running without compiling
```powershell
powershell -ExecutionPolicy Bypass -File .\src\WinGetUpdateTool.ps1
```
The UAC prompt appears first, then the window opens with the update list.

## Compiling to .exe
Double click **`build.bat`**, or:
```powershell
powershell -ExecutionPolicy Bypass -File .\src\build.ps1
```
Produces `dist\WinGetUpdateTool.exe`. Double click → UAC prompt → same UI.

The build replaces the `###UI.xaml###`, `###Theme.Light.xaml###` and `###Theme.Dark.xaml###` markers in `src\WinGetUpdateTool.ps1` with the file contents, writes a temporary source to `%TEMP%` and hands that to ps2exe (`-requireAdmin` → UAC manifest, `-noConsole` → WPF window only, `-iconFile` → embedded icon). It fails with an explicit error if a marker is missing or the exe is not rewritten.

## Tests
```powershell
powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-Ui.ps1
powershell -ExecutionPolicy Bypass -File .\tests\Test-InvokeWinGet.ps1
```
- `Test-Ui.ps1` — headless, opens no windows: checks that the scripts parse, that `UI.xaml` loads with every expected `x:Name`, that both themes define the same keys, that every `DynamicResource` resolves, that the build markers are in place, that `WgtRow` raises `PropertyChanged`, and that the two grid-freeze regressions have not come back.
- `Test-InvokeWinGet.ps1` — exercises winget execution (wait bound to the process, exit code available, output read back as UTF-8) and parses a two-table fixture through the real `Get-WinGetUpgrades`; needs no admin rights and installs nothing.

## Usage
1. **Check for updates** (top left) — runs `winget upgrade` with a loading spinner; "N updates available" appears at the top. The progress bar resets: it belongs to the previous queue, not to the new list.
   - **Unknown** (checkbox right next to the button, **off by default**, with an explanatory tooltip) adds `--include-unknown`: without it, winget only lists packages whose installed version it can determine. It takes effect on the *next* search — toggling it does not start a scan by itself.
2. Tick the rows to upgrade, or use **Select all** (below the list). "M selected" appears next to it.
3. **Update** (below the list) — runs the upgrades in sequence, **one package at a time, by ID**; progress in the bar, per-row state in the **Result** column.
   - No timeout: slow installers are never cut off. During a long wait the log writes a line every 30s (`...name running for Ns`), so a stall is visible while it happens.
   - The table stays **scrollable** during the update: it goes read-only (ticks cannot be changed), not disabled.
   - "Select all" is enabled only with at least one entry; "Update" only with at least one selected.
4. **Columns can be resized** by dragging their border in the header (the window keeps a fixed width, so widening one column narrows the others).
5. The window can be **minimized** (`ResizeMode="CanMinimize"`): still a fixed size, but the title bar has the minimize button.

### Theme
The icon button in the top right **cycles** through three modes (the tooltip names the active one):

| Icon | Glyph | Mode | Behaviour |
|---|---|---|---|
| sun | `E706` | Light | always light |
| moon | `E708` | Dark | always dark |
| sun with a moon inside | `F08C` | Auto | follows Windows, even while the window is open (polled every 5s) |

- Icons come from the system set, present in both **Segoe Fluent Icons** (Win11) and **Segoe MDL2 Assets** (Win10).
- Glyphs must be written `[char]0xE706`, **not** `` "`u{E706}" ``: that escape only exists from PowerShell 6 on, and ps2exe compiles against 5.1, where it would stay the literal `u{E706}` (empty boxes). `Test-Ui.ps1` checks for this.
- The choice is remembered in `HKCU:\Software\WinGetUpdateTool`, value `Theme`.
- In Dark mode the title bar goes dark too (`DWMWA_USE_IMMERSIVE_DARK_MODE`, Windows 10 2004+ / 11; on earlier builds it stays light).
- **To change the colours** just edit `ui\Theme.Light.xaml` / `ui\Theme.Dark.xaml` and relaunch: they are two lists of `SolidColorBrush` with identical keys. Adding a key to only one file makes `Test-Ui.ps1` fail.
- `UI.xaml` references colours with `{DynamicResource ...}`: using `StaticResource` would break hot theme switching (it resolves once and never again).

### Status icons (Result column)
Icons from the system set (**Segoe Fluent Icons**, falling back to **Segoe MDL2 Assets** on Windows 10):
- spinner = update in progress
- solid green circle with a tick = completed (exit 0)
- solid yellow triangle = warning (benign codes: reboot required, already installed, ...)
- solid red circle with an X = error (hover for the code; full detail in the log)

## Notes
- If `winget` is missing → a clear error message at startup.
- If there is nothing to update → "No updates available".
- An error on one package does **not** stop the rest of the queue (per-row result).
- Updates run sequentially (winget is not reliable in parallel).
- winget is launched with its output redirected to a file and the wait bound to the process exit, not to the pipe: child installers that inherit stdout can no longer block the wait indefinitely. The `--disable-interactivity` flag matters because without a console (exe built with `-noConsole`) a prompt would hang the update forever. The process is started with `Process.Start` (with `cmd` performing the redirect) rather than `Start-Process -PassThru`, whose `Process` object loses `ExitCode` when the process exits before the native handle is cached — an empty `ExitCode` casts to `0`, which would paint a failure green.
- The output file is read back as **UTF-8**: winget writes UTF-8, while `Get-Content` on PowerShell 5.1 assumes the system ANSI codepage, which turned localized messages into mojibake.
- The upgrade list is parsed by **column position, one table at a time**: winget prints a second table for packages that need explicit targeting, with its own column widths. Columns are re-anchored at every separator row, and a data row is told apart from localized prose by its grid alignment — not by counting runs of two or more spaces, a heuristic that also dropped rows whose columns are exactly full.
- The checkbox uses a **custom `ControlTemplate`**: the system one (Aero2) fills the tick with a hardcoded `#FF212121` declared as a `StaticResource` inside the theme dictionary, so no external setter can reach it and in dark mode the tick was black on black. The template binds the tick to `FgBrush` and restores the hover border and disabled opacity that re-templating throws away.
- Column resizing lives in the `ControlTemplate` of `DataGridColumnHeader`: re-templating the header (which is necessary — the system `DataGridHeaderBorder` ignores `Background`) throws away the two `Thumb` elements `PART_LeftHeaderGripper` / `PART_RightHeaderGripper` that DataGrid hooks for the drag, and the columns silently become fixed, **with no error at all**. They have to be added back by hand under those exact names; `Test-Ui.ps1` verifies they are there.
- Table rows are instances of the `WgtRow` class (`INotifyPropertyChanged`, compiled with `Add-Type` at startup), not `PSCustomObject`: `NoteProperty` values do not notify WPF, which forced a `$Grid.Items.Refresh()` on every state change — and that regenerates the view and sends the scroll back to the top. `Test-Ui.ps1` checks both the event and the absence of `Items.Refresh()` / `$Grid.IsEnabled = ...` in the code.
