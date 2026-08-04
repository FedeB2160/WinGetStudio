# WinGet Studio

Standalone Windows tool (WPF) for managing `winget` packages from a checkbox table: **update** what has a newer version, **install** something new by searching as you type, **list and uninstall** what is already there, **pin** what must not be touched, and **export/import** the whole package list to rebuild a machine. Automatic UAC elevation, non-blocking UI, light/dark theme, no branding.

The **UI and this documentation are in English**; the in-code comments are in Italian. User-facing strings live in `ui\UI.xaml` (labels, column headers) and in the `Write-Log` / `LogUI` / `MessageBox` calls under `src\modules\`.

## Layout

```
build.bat                       double click -> produces dist\WinGetStudio.exe
README.md
src\   main.ps1                 entry point: version, elevation, module loading, Start-App
       build.ps1                ps2exe compilation
   modules\
       WinGet.Exec.ps1          running winget: Invoke-WinGet, exit code mapping
       WinGet.Parse.ps1         reading winget's fixed-width tables
       App.Ui.ps1               shared helpers: Write-Log, global busy state
       App.Jobs.ps1             background runspaces: Start-BackgroundJob, Start-WinGetQueue
       App.Theme.ps1            Light / Dark / Auto theme
       App.Pins.ps1             pins: read, add, remove, flag the rows
       App.Backup.ps1           export / import of the package list
       App.Update.ps1           self-update from GitHub releases
       Tab.Updates.ps1          the Updates tab
       Tab.Install.ps1          the Install tab: search-as-you-type, scope, install
       Tab.Installed.ps1        the Installed tab: inventory, filter, uninstall
       App.Bootstrap.ps1        WgtRow, XAML loading, Start-App
ui\    UI.xaml                  window: layout and styles
       Theme.Light.xaml         light palette
       Theme.Dark.xaml          dark palette
assets\icon.ico                 app icon (embedded in the exe)
tests\ Test-Ui.ps1              headless check of code, XAML, themes and startup
       Test-InvokeWinGet.ps1    winget execution and table parsing
dist\  WinGetStudio.exe        build output (signed, gitignored)
```

`src\main.ps1` holds no logic: it elevates, loads the modules and calls `Start-App`. It exists as a separate file because ps2exe takes a single input file and the self-elevation has to run before anything else.

### How the modules reach the exe

ps2exe compiles **one** file, so `build.ps1` concatenates the modules in place of the `###MODULES###` marker in `main.ps1`. That marker is a **PowerShell comment line**: run as a `.ps1` it stays harmless and the modules are dot-sourced from disk instead, so you can edit one module and relaunch without recompiling. The module list is *not* duplicated in `build.ps1` — it is read from the `$moduleNames` array in `main.ps1` with a regex, so a new module cannot silently be left out of the exe.

Dot-sourcing creates no scope of its own, so the modules see each other's variables exactly as they do when concatenated. `Start-App` assigns the controls with `$script:` for the same reason: a plain `$Grid = ...` inside a function would be local, and every module reading `$Grid` would get `$null`.

The three `.xaml` files are **not** a runtime requirement either: `build.ps1` injects them the same way, and the exe stays a single file you can copy to another machine on its own. If a `.xaml` file *is* present on disk it wins over the embedded copy. Lookup order: `..\ui\<file>`, `<exe folder>\ui\<file>`, `<exe folder>\<file>`.

## Version

The version lives in **one** place, the `$AppVersion` constant at the top of `src\main.ps1`. From there it reaches:
- the **window title**, as `WinGet Studio [v1.7.0]` (the `v` is added when composing the title, so what reaches the exe properties stays a plain number);
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
Produces `dist\WinGetStudio.exe`. Double click → UAC prompt → same UI.

The build replaces the `###MODULES###` marker in `src\main.ps1` with the concatenated modules and the `###UI.xaml###`, `###Theme.Light.xaml###`, `###Theme.Dark.xaml###` markers with the file contents (modules first, since the XAML markers live inside `App.Bootstrap.ps1`), writes a temporary source to `%TEMP%` and hands that to ps2exe (`-requireAdmin` → UAC manifest, `-noConsole` → WPF window only, `-iconFile` → embedded icon). It fails with an explicit error if a marker is missing, a listed module is absent, or the exe is not rewritten.

## Automatic updates

At startup the app asks GitHub for the latest release of `FedeB2160/WinGetStudio`. The repo is public, so **no token is involved** — one anonymous API call (the anonymous limit is 60/hour). If a newer version exists, an accent-coloured **Update to vX.Y.Z** button appears next to the theme button and a line goes into the log. Nothing else happens: no dialog on startup, no automatic download.

No release, no network, a non-numeric tag, or running from source instead of the exe: the check does nothing and says nothing. A missing update is not a fault.

**How it replaces itself, with no external updater:** on Windows a running executable cannot be overwritten, but it *can* be renamed. So the app renames itself to `.old`, writes the new exe in its place, restarts, and deletes the `.old` on the next launch.

Since this is the one place where the program runs code fetched from the internet, it is fenced in:
- **explicit confirmation**, No by default, showing the file name, size and download URL;
- the download is verified against the **SHA-256 published with the release** and discarded on mismatch — if a release carries no checksum, the dialog says so before you accept;
- if replacing the exe fails halfway, the `.old` is put back, so the app is never left without an executable;
- TLS 1.2 is set explicitly (PowerShell 5.1 still negotiates TLS 1.0, which GitHub refuses) and a User-Agent is sent (the API answers 403 without one).

The asset is found as the **first `.exe` in the release**, not by exact name, so releases published before the rename still work.

`Test-Ui.ps1` covers the version comparison (including `1.10.0 > 1.9.0`, which string comparison gets wrong), reads the real release from GitHub, and asserts that confirmation precedes the download and that the checksum is checked. It does **not** run a download — that would replace the exe under the test.

## Signing

`build.ps1` signs the exe after compiling. It picks the certificate in this order:

1. `$env:WINGETSTUDIO_CERT_THUMBPRINT` — set this to switch to a company or commercial certificate without editing the build;
2. otherwise the first valid code-signing certificate with a private key in `Cert:\CurrentUser\My`.

If it finds none the build **still succeeds**, printing a warning that the exe is unsigned — signing needs a private key that not every machine has.

The signature is **timestamped** (DigiCert). Without a timestamp a signature stops being valid the day the certificate expires; with one it stays valid forever, because it proves the signature existed while the certificate was still good. If the timestamp server cannot be reached the build signs anyway and says so.

### Current certificate: self-signed
The certificate in use is self-signed (`CN=WinGet Studio, O=EGICON`, valid to 2031). What that does and does not buy:

- **Does**: proves the exe has not been altered since the build, and shows a publisher name instead of nothing.
- **Does not**: make Windows trust it. `Get-AuthenticodeSignature` reports `UnknownError` and SmartScreen still says "unknown publisher", because the root is not among the trusted authorities. **This is expected and does not mean the signature is missing.**

To make it trusted, import the public certificate — `assets\WinGetStudio-codesign.cer`, no private key in it — into *Trusted Root Certification Authorities*: per user with `Import-Certificate -CertStoreLocation Cert:\CurrentUser\Root`, or machine-wide by GPO in a domain. Understand what you are doing first: anything signed with that certificate becomes trusted for whoever imports it.

For a signature trusted everywhere without importing anything, a certificate from the company PKI (already trusted domain-wide) or a commercial OV/EV certificate is needed. Both plug into the build through the environment variable above.

**Private keys never belong in the repo** — `.gitignore` blocks `*.pfx`, `*.p12` and `*.snk`. Only the public `.cer` is committed, and that one is meant to be shared.

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
1. **Check** (top left) — runs `winget upgrade` with a loading spinner; "N updates available" appears at the top. The progress bar resets: it belongs to the previous queue, not to the new list.
   - **Unknown** (checkbox right next to the button, **off by default**, with an explanatory tooltip) adds `--include-unknown`: without it, winget only lists packages whose installed version it can determine. It takes effect on the *next* search — toggling it does not start a scan by itself.
2. Tick the rows to upgrade, or use **Select all** (below the list). "M selected" appears next to it.
3. **Update** (below the list) — runs the upgrades in sequence, **one package at a time, by ID**; progress in the bar, per-row state in the **Result** column.
   - No timeout: slow installers are never cut off. During a long wait the log writes a line every 30s (`...name running for Ns`), so a stall is visible while it happens.
   - The table stays **scrollable** during the update: it goes read-only (ticks cannot be changed), not disabled.
   - "Select all" is enabled only with at least one entry; "Update" only with at least one selected.
4. **Columns can be resized** by dragging their border in the header.

### Install tab
Type in the search box and results appear as you type — no autocomplete popup: the results grid *is* the suggestion list, so you also see version and ID before choosing.

1. **Type at least 3 characters.** The search fires ~350ms after you stop typing, not on every keystroke, and only against `--source winget` — the local index, ~0.4s. A 2-letter query returns over a thousand rows, hence both the threshold and the 25-result cap.
2. **MS Store** (checkbox next to **Search**, off by default) also searches the Microsoft Store. It applies only to an explicit search (**Enter** or the **Search** button), never to the as-you-type one: msstore goes online and takes ~5s. The search spinner sits at the end of that row, after the checkbox, so appearing and disappearing never resizes the search box — `Test-Ui.ps1` asserts it.
3. **Scope** (next to **Install**, below the results) cycles `Auto` → `User` → `Machine`. `Auto` passes no flag and behaves like the Updates tab; `Machine` passes `--scope machine` (all users); `User` passes `--scope user`. It is a cycling button rather than a combo box because a `ComboBox` template has to be rewritten from scratch to survive dark mode, while a button does not.
   - The tool always runs elevated. If the elevated account is **not** the signed-in user, per-user packages would land in the wrong profile — the log warns about it once, and only when the chosen scope can actually cause it.
4. Tick rows and press **Install**, or **double click a row** to install just that one. Installs run through the same sequential queue as updates, so the per-row Result column and the log work the same way.

While the search is still typing-in-progress the grid keeps showing the previous results on purpose — clearing on every keystroke would flicker — and the spinner is what tells you a search is running. Results that come back after you have already typed something else are discarded: they carry their own query and it is compared against what is in the box. `Test-Ui.ps1` covers this with a real winget search.

Only one winget operation runs at a time (winget is not reliable in parallel), so an update in progress greys out the Install tab's controls too, and vice versa. Each tab registers a handler with `Set-AppBusy`.

### Installed tab
The inventory of what is on the machine, and where you remove it.

1. The list **loads by itself the first time you open the tab**, not at startup: `winget list` takes a couple of seconds and returns everything (340 packages on the development machine), so nobody who never opens this tab pays for it. **Refresh** rebuilds it.
2. The **filter box** narrows the list locally — it does not call winget again. It matches name *and* ID, case-insensitively.
3. Tick rows and press **Uninstall**.

The list includes packages that were **not** installed through winget: their ID looks like `ARP\Machine\X64\Android Studio` — with spaces inside it, which is legitimate — and their Source column is empty. They uninstall by ID like any other.

Uninstalling is the only irreversible thing this tool does, so it is guarded:
- a **Yes/No confirmation** listing the actual package names, with **No as the default button** — a stray Enter cannot remove anything;
- the filter **hides** rows without deselecting them, so a package could be queued while off screen. Both the counter line (`2 selected (1 hidden by the filter)`) and the confirmation dialog say so explicitly.
- `Test-Ui.ps1` asserts the confirmation exists, is Yes/No, defaults to No, and comes *before* anything is queued.

After an uninstall the list is **not** rebuilt automatically: that would wipe the Result column, which is the record of what actually happened. Press Refresh when you have read it.

### Export / Import (Installed tab)
**Export...** and **Import...** sit on the right of the Installed action bar, away from Uninstall: they work on the whole machine, not on the selected rows.

- **Export** writes the installed packages to a `.json` file (`winget export`). On the development machine that is **88 packages out of 340 installed** — the rest are in no source, so winget cannot record them; the log says how many were left out. Deliberately **without** `--include-versions`: pinning exact versions makes the import fail as soon as one of them is no longer published, and the point of the file is to rebuild a machine, not to freeze it.
- **Import** reads such a file and installs what is missing (`winget import`). Always with **`--ignore-unavailable`**: without it a single package that is no longer published aborts the whole import.

Import installs software, so it is guarded like uninstall: a Yes/No dialog, **No by default**, stating how many packages the file contains — a count read from the file, not an estimate. A file that is not a winget export is rejected *before* winget is called, otherwise the user would get an unintelligible error from winget instead.

Both run as a **single long winget invocation**, not as a per-package queue: it is winget that walks the list, so there is no per-row result to show. The log gets a line every 30s while it works, and the spinner stays on.

`Test-Ui.ps1` performs a **real export** to a temp file and checks the package count, plus that invalid files are rejected. It does **not** run an import — that would install software. The dialogs are separated from the actions (`Invoke-PackageExport` / `Invoke-PackageImport`) precisely so the actions can be tested without a dialog to click.

### Pinning (both grids)
A pin tells winget to leave a package alone until the pin is removed — the answer to "this one keeps reappearing and I do not want it touched".

**Right click a row** in Updates or Installed: *Pin (block upgrades)* / *Remove pin*. It acts on the **highlighted** rows, not the ticked ones, and deliberately so: a pinned row has its checkbox disabled, so with ticks you could never unpin anything.

A pinned row shows a pin glyph and is left out of updates in three places, not one: the checkbox is disabled, **Select all** skips it, and `Start-UpdateSelected` unticks it and says so in the log. Only the last of the three actually protects the queue — `Select all` works on the objects, not on the UI — the other two are there so the state is visible.

In the Installed tab the checkbox stays enabled on pinned packages: a pin blocks **upgrades**, not uninstallation.

Two things worth knowing, both learned the hard way:
- `winget pin list` ends with the localized header **"Tipo di pin"** ("Pin type"), which *contains spaces*. Column detection counts header tokens, so it saw three phantom columns whose offsets fall in the middle of the data rows, judged every row misaligned and dropped them all — the pin list came back empty while winget had happily created the pin. Hence `Get-WinGetTable -MaxColumns`, and a fixture in `Test-InvokeWinGet.ps1` that reproduces the bug.
- **Never two winget processes at once.** Reading the pins used to run *after* the busy state was released, so a click on Update in that window ran a second winget and one of the two failed with exit 1. The scans now read the pins inside the same job, and after a pin/unpin the busy state is released by the pin re-read, which is the last step.

`Test-Ui.ps1` runs the whole pin cycle against real winget on `7zip.7zip` and removes the pin in a `finally`, so a failure mid-test cannot leave a package silently blocked.

### Settings screen
The **gear button in the top-right corner** opens it; the **X** or **Esc** closes it. Everything that is not a package operation lives here.

- **Theme** — a dropdown with `Light` / `Dark` / `Auto`. In `Auto` the line next to it says which of the two it is currently following, so the choice explains what you see. The list entries *are* the values written to the registry, so there is no label-to-value table to keep in sync.
- **Installed version** and **Check for updates** — the version is shown here rather than in the window title. The manual check always reports an outcome ("Up to date", "vX is available", "No release found"), while the automatic one at startup stays silent unless there is something to say.

The `ComboBox` is fully re-templated, like the context menu and the checkbox before it: the system one (Aero2) hardcodes a light background and would stay white in dark mode. WPF needs a `ToggleButton` bound to `IsDropDownOpen` and a `Popup` named `PART_Popup`; here the ToggleButton is transparent and sits *over* the border, so it catches clicks across the whole control without nesting one template inside another.

It is a panel overlaid on the whole window, **not a second Window**: the theme colours live in the main window's `MergedDictionaries`, so a separate Window would have to be wired to those dictionaries and re-wired on every theme change, plus owner, modality and placement. An opaque overlay is the same thing on screen and follows the theme by itself.

The old cycling theme button that used to sit in that corner is gone: cramped, and it never explained what it did.

### Theme (how it works)
The icon button in the top right **cycles** through three modes (the tooltip names the active one):

| Icon | Glyph | Mode | Behaviour |
|---|---|---|---|
| sun | `E706` | Light | always light |
| moon | `E708` | Dark | always dark |
| sun with a moon inside | `F08C` | Auto | follows Windows, even while the window is open (polled every 5s) |

- Icons come from the system set, present in both **Segoe Fluent Icons** (Win11) and **Segoe MDL2 Assets** (Win10).
- Glyphs must be written `[char]0xE706`, **not** `` "`u{E706}" ``: that escape only exists from PowerShell 6 on, and ps2exe compiles against 5.1, where it would stay the literal `u{E706}` (empty boxes). `Test-Ui.ps1` checks for this.
- The choice is remembered in `HKCU:\Software\WinGetStudio`, value `Theme`.
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










