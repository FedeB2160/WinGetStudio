# WinGet Update Tool

Standalone Windows tool (WPF) that lists `winget` updates in a checkbox table and upgrades only the selected entries. Automatic UAC elevation, non-blocking UI, light/dark theme, no branding.

The **UI and this documentation are in English**; the in-code comments are in Italian. User-facing strings live in `ui\UI.xaml` (labels, column headers) and in the `Write-Log` / `LogUI` / `MessageBox` calls of `src\WinGetUpdateTool.ps1`.

## Layout

```
build.bat                       double click -> produces dist\WinGetUpdateTool.exe
README.md
src\   main.ps1                 entry point: version, elevation, module loading, Start-App
       build.ps1                ps2exe compilation
   modules\
       WinGet.Exec.ps1          running winget: Invoke-WinGet, exit code mapping
       WinGet.Parse.ps1         reading winget's fixed-width tables
       App.Ui.ps1               helpers shared by every tab (Write-Log)
       App.Jobs.ps1             background runspaces: Start-BackgroundJob, Start-WinGetQueue
       App.Theme.ps1            Light / Dark / Auto theme
       Tab.Updates.ps1          the Updates tab
       App.Bootstrap.ps1        WgtRow, XAML loading, Start-App
ui\    UI.xaml                  window: layout and styles
       Theme.Light.xaml         light palette
       Theme.Dark.xaml          dark palette
assets\icon.ico                 app icon (embedded in the exe)
tests\ Test-Ui.ps1              headless check of code, XAML, themes and startup
       Test-InvokeWinGet.ps1    winget execution and table parsing
dist\  WinGetUpdateTool.exe     build output
```

`src\main.ps1` holds no logic: it elevates, loads the modules and calls `Start-App`. It exists as a separate file because ps2exe takes a single input file and the self-elevation has to run before anything else.

### How the modules reach the exe

ps2exe compiles **one** file, so `build.ps1` concatenates the modules in place of the `###MODULES###` marker in `main.ps1`. That marker is a **PowerShell comment line**: run as a `.ps1` it stays harmless and the modules are dot-sourced from disk instead, so you can edit one module and relaunch without recompiling. The module list is *not* duplicated in `build.ps1` — it is read from the `$moduleNames` array in `main.ps1` with a regex, so a new module cannot silently be left out of the exe.

Dot-sourcing creates no scope of its own, so the modules see each other's variables exactly as they do when concatenated. `Start-App` assigns the controls with `$script:` for the same reason: a plain `$Grid = ...` inside a function would be local, and every module reading `$Grid` would get `$null`.

The three `.xaml` files are **not** a runtime requirement either: `build.ps1` injects them the same way, and the exe stays a single file you can copy to another machine on its own. If a `.xaml` file *is* present on disk it wins over the embedded copy. Lookup order: `..\ui\<file>`, `<exe folder>\ui\<file>`, `<exe folder>\<file>`.

## Version

The version lives in **one** place, the `$AppVersion` constant at the top of `src\main.ps1`. From there it reaches:
- the **window title**, as `WinGet Update Tool [1.1.0]`;
- the **exe properties** (right click → Properties → Details): `build.ps1` reads the constant with a regex and passes it to ps2exe, so the two can never disagree. A missing or renamed constant fails the build instead of producing an unversioned exe.

Bump it there and rebuild — `Test-Ui.ps1` checks that the constant is still found, that it is `x.y.z`, that it reaches the title and that `build.ps1` still forwards it.

## Requirements
- Windows 10/11 with **winget** (App Installer from the Microsoft Store).
- PowerShell 5.1+.
- The **ps2exe** module (only to compile): `Install-Module ps2exe -Scope CurrentUser`.

## Running without compiling
```powershell
powershell -ExecutionPolicy Bypass -File .\src\main.ps1
```
The UAC prompt appears first, then the window opens with the update list.

## Compiling to .exe
Double click **`build.bat`**, or:
```powershell
powershell -ExecutionPolicy Bypass -File .\src\build.ps1
```
Produces `dist\WinGetUpdateTool.exe`. Double click → UAC prompt → same UI.

The build replaces the `###MODULES###` marker in `src\main.ps1` with the concatenated modules and the `###UI.xaml###`, `###Theme.Light.xaml###`, `###Theme.Dark.xaml###` markers with the file contents (modules first, since the XAML markers live inside `App.Bootstrap.ps1`), writes a temporary source to `%TEMP%` and hands that to ps2exe (`-requireAdmin` → UAC manifest, `-noConsole` → WPF window only, `-iconFile` → embedded icon). It fails with an explicit error if a marker is missing, a listed module is absent, or the exe is not rewritten.

## Tests
```powershell
powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-Ui.ps1
powershell -ExecutionPolicy Bypass -File .\tests\Test-InvokeWinGet.ps1
```
- `Test-Ui.ps1` — headless, opens no windows: checks that every file parses, that no module is missing from (or orphaned by) `$moduleNames`, that `UI.xaml` provides every control the code asks for, that both themes define the same keys, that every `DynamicResource` resolves, that the build markers are in place, that `WgtRow` raises `PropertyChanged`, and that the two grid-freeze regressions have not come back. Two checks matter especially after the split:
  - it re-does the module injection and verifies the **concatenated** source parses and keeps every function — the exe loads code a different way from the `.ps1`, and a failure there would otherwise only show up on a double click;
  - it calls `Start-App -NoShow`, which builds the window without displaying it, then verifies the modules actually *see* the controls and that `Start-BackgroundJob` completes, returns its result and unhooks itself. These catch scope and closure bugs that every static check happily passes.
- `Test-InvokeWinGet.ps1` — exercises winget execution (wait bound to the process, exit code available, output read back as UTF-8) and parses three fixtures through the real code: the two-table `upgrade` output, a 3-column `search` result, and a 4-column `list` where the fourth column is *Source* and the version carries a `>` prefix. Needs no admin rights and installs nothing.

## Usage

The window is a **TabControl**, one tab per area of work. The **progress bar and the log sit outside the tabs**, at the bottom: they belong to whatever operation is running, whichever tab you are looking at, so you can start an update and switch tab without losing sight of it. The theme button stays in the top right, outside the tabs, because it applies to the whole window. `Test-Ui.ps1` fails if the log or the progress bar ever ends up inside a tab.

The window is **resizable** (`ResizeMode="CanResize"`, minimum 760x520): with more than one tab a fixed 900x620 was too tight. The log keeps a fixed height, so enlarging the window grows the table.

### Updates tab
1. **Check for updates** (top left) — runs `winget upgrade` with a loading spinner; "N updates available" appears at the top. The progress bar resets: it belongs to the previous queue, not to the new list.
   - **Unknown** (checkbox right next to the button, **off by default**, with an explanatory tooltip) adds `--include-unknown`: without it, winget only lists packages whose installed version it can determine. It takes effect on the *next* search — toggling it does not start a scan by itself.
2. Tick the rows to upgrade, or use **Select all** (below the list). "M selected" appears next to it.
3. **Update** (below the list) — runs the upgrades in sequence, **one package at a time, by ID**; progress in the bar, per-row state in the **Result** column.
   - No timeout: slow installers are never cut off. During a long wait the log writes a line every 30s (`...name running for Ns`), so a stall is visible while it happens.
   - The table stays **scrollable** during the update: it goes read-only (ticks cannot be changed), not disabled.
   - "Select all" is enabled only with at least one entry; "Update" only with at least one selected.
4. **Columns can be resized** by dragging their border in the header.

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
- The upgrade list is parsed by **column position, one table at a time** (`Get-WinGetTable`): winget prints a second table for packages that need explicit targeting, with its own column widths. Columns are re-anchored at every separator row, and a data row is told apart from localized prose by its grid alignment — not by counting runs of two or more spaces, a heuristic that also dropped rows whose columns are exactly full.
- `Get-WinGetTable` returns the **raw fields per row**, and each caller maps them, because the meaning of the columns changes with the command: the 4th is *Available* in `upgrade`, *Match* in `search`, *Source* in `list`. The count varies even within one command — `search vlc` has a Match column, `search ab --count 5` does not. Only the first three (Name, Id, Version) are the same everywhere, and they are all `search` and `list` need. The table is accepted from **3** columns up: `winget list --source winget` prints exactly three, and the old threshold of four discarded it silently.
- Background jobs pass what they need through the **job object**, not through a `GetNewClosure()` capture. A closure gets its own module scope, and inside it `$script:` no longer refers to the script — `$script:jobs` came back `$null` and the cleanup died on `.Remove()`, leaving the job polling forever. The tick finds its job from the sender (the timer that raised it) instead. `Test-Ui.ps1` covers this.
- `TabControl` and `TabItem` are re-templated for the same reason as the buttons and the grid header: the system template (Aero2) paints hardcoded light gradients and ignores `Background`, so in dark mode the tabs would be white with white text on them. The active tab is filled with `BgBrush`, the same colour as the content area, and the header panel carries a `-1` bottom margin so the tab's lower border covers the content's upper one and the two read as one surface.
- The checkbox uses a **custom `ControlTemplate`**: the system one (Aero2) fills the tick with a hardcoded `#FF212121` declared as a `StaticResource` inside the theme dictionary, so no external setter can reach it and in dark mode the tick was black on black. The template binds the tick to `FgBrush` and restores the hover border and disabled opacity that re-templating throws away.
- Column resizing lives in the `ControlTemplate` of `DataGridColumnHeader`: re-templating the header (which is necessary — the system `DataGridHeaderBorder` ignores `Background`) throws away the two `Thumb` elements `PART_LeftHeaderGripper` / `PART_RightHeaderGripper` that DataGrid hooks for the drag, and the columns silently become fixed, **with no error at all**. They have to be added back by hand under those exact names; `Test-Ui.ps1` verifies they are there.
- Table rows are instances of the `WgtRow` class (`INotifyPropertyChanged`, compiled with `Add-Type` at startup), not `PSCustomObject`: `NoteProperty` values do not notify WPF, which forced a `$Grid.Items.Refresh()` on every state change — and that regenerates the view and sends the scroll back to the top. `Test-Ui.ps1` checks both the event and the absence of `Items.Refresh()` / `$Grid.IsEnabled = ...` in the code.
