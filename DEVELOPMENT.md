# Development

Everything a change to this codebase needs: layout, build, tests, and the decisions that are not obvious from the code. For what the app does and how to use it, see [README.md](README.md).

The **UI and the documentation are in English**; the in-code comments are in Italian. User-facing strings live in `ui\UI.xaml` (labels, column headers) and in the `Write-Log` / `LogUI` / `MessageBox` calls under `src\modules\`.

## Layout

```
build.bat                       double click -> produces dist\WinGetStudio.exe
README.md                       what the app does (first page on GitHub)
DEVELOPMENT.md                  this file
CHANGELOG.md                    version history
src\   main.ps1                 entry point: version, elevation, module loading, Start-App
       build.ps1                ps2exe compilation and signing
   modules\
       WinGet.Exec.ps1          running winget: Invoke-WinGet, exit code mapping
       WinGet.Parse.ps1         reading winget's fixed-width tables
       App.Ui.ps1               shared helpers: Write-Log, global busy state
       App.Jobs.ps1             background runspaces: Start-BackgroundJob, Start-WinGetQueue
       App.Theme.ps1            Light / Dark / Auto theme
       App.Pins.ps1             pins: read, add, remove, flag the rows
       App.Backup.ps1           export / import of the package list
       App.Update.ps1           self-update from GitHub releases
       App.Settings.ps1         the settings screen: open and close
       Tab.Updates.ps1          the Updates tab
       Tab.Install.ps1          the Install tab: search-as-you-type, scope, install
       Tab.Installed.ps1        the Installed tab: inventory, filter, uninstall
       App.Bootstrap.ps1        WgtRow, XAML loading, Start-App
ui\    UI.xaml                  window: layout and styles
       Theme.Light.xaml         light palette
       Theme.Dark.xaml          dark palette
assets\icon.ico                 app icon (embedded in the exe)
       WinGetStudio-codesign.cer  public signing certificate (no private key)
tests\ Test-Ui.ps1              headless check of code, XAML, themes and startup
       Test-InvokeWinGet.ps1    winget execution and table parsing
dist\  WinGetStudio.exe         build output (signed, gitignored)
```

`src\main.ps1` holds no logic: it elevates, loads the modules and calls `Start-App`. It exists as a separate file because ps2exe takes a single input file and the self-elevation has to run before anything else.

### How the modules reach the exe

ps2exe compiles **one** file, so `build.ps1` concatenates the modules in place of the `###MODULES###` marker in `main.ps1`. That marker is a **PowerShell comment line**: run as a `.ps1` it stays harmless and the modules are dot-sourced from disk instead, so you can edit one module and relaunch without recompiling. The module list is *not* duplicated in `build.ps1` — it is read from the `$moduleNames` array in `main.ps1` with a regex, so a new module cannot silently be left out of the exe.

Dot-sourcing creates no scope of its own, so the modules see each other's variables exactly as they do when concatenated. `Start-App` assigns the controls with `$script:` for the same reason: a plain `$Grid = ...` inside a function would be local, and every module reading `$Grid` would get `$null`.

The three `.xaml` files are **not** a runtime requirement either: `build.ps1` injects them the same way, and the exe stays a single file you can copy to another machine on its own. If a `.xaml` file *is* present on disk it wins over the embedded copy. Lookup order: `..\ui\<file>`, `<exe folder>\ui\<file>`, `<exe folder>\<file>`.

## Version

The version lives in **one** place, the `$AppVersion` constant at the top of `src\main.ps1`. From there it reaches:
- the **settings screen** (`Installed version`);
- the **exe properties** (right click → Properties → Details): `build.ps1` reads the constant with a regex and passes it to ps2exe, so the two can never disagree. A missing or renamed constant fails the build instead of producing an unversioned exe.

Bump it there and rebuild — `Test-Ui.ps1` checks that the constant is still found, that it is `x.y.z`, that it reaches the settings screen and that `build.ps1` still forwards it.

## Running from source

```powershell
powershell -ExecutionPolicy Bypass -File .\src\main.ps1
```

The UAC prompt appears first, then the window. Self-update is disabled in this mode (there is no exe to replace).

## Compiling

Double click **`build.bat`**, or:

```powershell
powershell -ExecutionPolicy Bypass -File .\src\build.ps1
```

Needs the **ps2exe** module (`Install-Module ps2exe -Scope CurrentUser`); the build installs it if missing.

It replaces `###MODULES###` with the concatenated modules and the `###UI.xaml###`, `###Theme.Light.xaml###`, `###Theme.Dark.xaml###` markers with the file contents — modules first, since the XAML markers live inside `App.Bootstrap.ps1` — writes a temporary source to `%TEMP%` and hands that to ps2exe (`-requireAdmin` → UAC manifest, `-noConsole` → WPF window only, `-iconFile` → embedded icon). It fails with an explicit error if a marker is missing, a listed module is absent, or the exe is not rewritten.

## Signing

`build.ps1` signs the exe after compiling, choosing the certificate in this order:

1. `$env:WINGETSTUDIO_CERT_THUMBPRINT` — set this to switch to a company or commercial certificate without editing the build;
2. otherwise the first valid code-signing certificate with a private key in `Cert:\CurrentUser\My`.

If it finds none the build **still succeeds**, printing a warning that the exe is unsigned — signing needs a private key that not every machine has.

The signature is **timestamped** (DigiCert). Without a timestamp a signature stops being valid the day the certificate expires; with one it stays valid, because it proves the signature existed while the certificate was still good. If the timestamp server cannot be reached the build signs anyway and says so.

### The current certificate is self-signed

`CN=WinGet Studio, O=EGICON`, valid to 2031. What that does and does not buy:

- **Does**: proves the exe has not been altered since the build, and shows a publisher name instead of nothing.
- **Does not**: make Windows trust it. `Get-AuthenticodeSignature` reports `UnknownError` and SmartScreen still says "unknown publisher", because the root is not among the trusted authorities. **This is expected and does not mean the signature is missing.**

To make it trusted, import the public certificate — `assets\WinGetStudio-codesign.cer`, no private key in it — into *Trusted Root Certification Authorities*: per user with `Import-Certificate -CertStoreLocation Cert:\CurrentUser\Root`, or machine-wide by GPO in a domain. Understand what you are doing first: anything signed with that certificate becomes trusted for whoever imports it.

For a signature trusted everywhere without importing anything, a certificate from the company PKI (already trusted domain-wide) or a commercial OV/EV certificate is needed. Both plug into the build through the environment variable above.

**Private keys never belong in the repo** — `.gitignore` blocks `*.pfx`, `*.p12` and `*.snk`. Only the public `.cer` is committed, and that one is meant to be shared.

## Publishing a release

The update check reads the **latest** release of the repo, so publishing one is what makes an update reachable.

1. Bump `$AppVersion` in `src\main.ps1` and rebuild — the build signs the exe.
2. Update `CHANGELOG.md`, commit, push.
3. Tag: `git tag v1.9.0 && git push origin v1.9.0`.
4. On GitHub → **Releases** → *Draft a new release*, pick the tag, paste the changelog entry, and attach `dist\WinGetStudio.exe` as an asset.
5. Publish. GitHub computes the SHA-256 of the asset by itself, and that is what the app verifies the download against.

**Tag and `$AppVersion` must agree**: the app compares the tag (`v1.9.0`) with its own constant, so a mismatch means it either keeps proposing an update already installed, or never proposes one.

**Builds are not reproducible.** Compiling the same source twice produces two different binaries — ps2exe writes variable metadata into the PE and each signature carries a fresh timestamp — identical in size but not in hash. So a published asset **cannot** be validated by rebuilding and comparing hashes; what is verifiable is the SHA-256 GitHub publishes with the asset (which is what the app checks on download) and the Authenticode signature.

The asset is found as the **first `.exe` in the release**, not by exact name, so renaming the exe does not break older or newer releases.

`gh release create` would do steps 4-5 from the command line, but the `gh` account on this machine has no push rights on the repo, which belongs to another account — the same reason `git push` works while `gh` does not. Either use the web UI or re-authenticate `gh` as the repo owner.

## Tests

```powershell
powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-Ui.ps1
powershell -ExecutionPolicy Bypass -File .\tests\Test-InvokeWinGet.ps1
```

`Test-InvokeWinGet.ps1` needs no admin rights and installs nothing. `Test-Ui.ps1` opens no windows, but it does touch winget for real in read-only ways (search, list, export) and runs one full pin cycle on `7zip.7zip`, removing the pin in a `finally` so a mid-test failure cannot leave a package silently blocked.

**`Test-Ui.ps1`** checks that every file parses, that no module is missing from (or orphaned by) `$moduleNames`, that `UI.xaml` provides every control the code asks for, that both themes define the same keys, that every `DynamicResource` resolves, that column headers are non-empty, uppercase and centred, that every `&#x....;` glyph exists in both system icon fonts, and that the two grid-freeze regressions have not come back. Four checks are worth knowing about, because they catch what static analysis cannot:

- it re-does the module injection and verifies the **concatenated** source parses and keeps every function — the exe loads code a different way from the `.ps1`, and a failure there would otherwise only show up on a double click;
- it calls `Start-App -NoShow`, which builds the window without displaying it, then verifies the modules actually *see* the controls and that `Start-BackgroundJob` completes, returns its result and unhooks itself — these catch scope and closure bugs that every static check happily passes;
- it drives the **real** search-as-you-type against winget, including the case where a slower earlier query returns after a newer one;
- it asserts that the confirmations for uninstall and for the self-update come *before* anything is queued or downloaded, are Yes/No, and default to No.

**`Test-InvokeWinGet.ps1`** exercises winget execution (wait bound to the process, exit code available, output read back as UTF-8) and parses four fixtures through the real code: the two-table `upgrade` output, a 3-column `search` result, a 4-column `list` where the fourth column is *Source* and the version carries a `>` prefix, and a `pin list` whose last header contains spaces.

## Design notes

Things that look odd until you know why. Most of them are bugs that were paid for once.

### Parsing winget

- The tables are parsed by **column position, one table at a time** (`Get-WinGetTable`): winget prints a second table for packages needing explicit targeting, with its own column widths. Columns are re-anchored at every separator row, and a data row is told apart from localized prose by its grid alignment — not by counting runs of two or more spaces, a heuristic that also dropped rows whose columns are exactly full.
- `Get-WinGetTable` returns the **raw fields per row** and each caller maps them, because the meaning of the columns changes with the command: the 4th is *Available* in `upgrade`, *Match* in `search`, *Source* in `list`. The count varies even within one command — `search vlc` has a Match column, `search ab --count 5` does not. Only the first three (Name, Id, Version) are the same everywhere. Tables are accepted from **3** columns up: `winget list --source winget` prints exactly three, and the old threshold of four discarded it silently.
- **`-MaxColumns` exists because of a localized header with spaces.** `winget pin list` ends with "Tipo di pin" ("Pin type"); column detection counts header tokens, so it saw three phantom columns whose offsets fall mid-text in the data rows, judged every row misaligned and dropped them all — the pin list came back empty while winget had created the pin.

### Running winget

- winget is launched with its output redirected to a file and the wait bound to the process exit, not to the pipe: child installers that inherit stdout can no longer block the wait indefinitely. `--disable-interactivity` matters because without a console (`-noConsole`) a prompt would hang forever. The process is started with `Process.Start` (with `cmd` doing the redirect) rather than `Start-Process -PassThru`, whose `Process` object loses `ExitCode` when the process exits before the native handle is cached — an empty `ExitCode` casts to `0`, which would paint a failure green.
- The output file is read back as **UTF-8**: winget writes UTF-8, while `Get-Content` on PowerShell 5.1 assumes the system ANSI codepage, which turned localized messages into mojibake.
- **Never two winget processes at once.** Reading the pins used to run *after* the busy state was released, so a click on Update in that window ran a second winget and one of the two failed with exit 1. The scans read the pins inside the same job, and after a pin/unpin the busy state is released by the pin re-read, which is the last step. Busy state is global: each tab registers a handler with `Set-AppBusy`.

### PowerShell and WPF traps

- Background jobs pass what they need through the **job object**, not through a `GetNewClosure()` capture. A closure gets its own module scope, and inside it `$script:` no longer refers to the script — `$script:jobs` came back `$null` and the cleanup died on `.Remove()`, leaving the job polling forever. The tick finds its job from the sender instead.
- A `CollectionView` is enumerable, so **returning one from a function** makes PowerShell unroll it into its items and the caller gets no `Filter` property. The Installed tab holds its view in a variable.
- Table rows are instances of the `WgtRow` class (`INotifyPropertyChanged`, compiled with `Add-Type` at startup), not `PSCustomObject`: `NoteProperty` values do not notify WPF, which forced a `$Grid.Items.Refresh()` on every state change — and that regenerates the view and sends the scroll back to the top.
- Glyphs must be written `[char]0xE706`, **not** `` "`u{E706}" ``: that escape only exists from PowerShell 6 on, and ps2exe compiles against 5.1, where it would stay the literal `u{E706}`.
- The **last child of a `DockPanel` fills the remaining space ignoring its own `Dock`** — the settings close button ended up centred until `LastChildFill="False"`.
- **Esc** is caught with `PreviewKeyDown` on the window: after a click inside the settings panel the focus belongs to a control, and a handler on the panel would never see the key.
- The header template must bind `HorizontalAlignment` to `HorizontalContentAlignment`, otherwise centring a column header has no effect at all.

### Controls that had to be re-templated

The system theme (Aero2) hardcodes light colours in places no external setter can reach, so in dark mode these had to be rebuilt from scratch:

- **CheckBox** — the tick is filled with `#FF212121` declared as a `StaticResource` inside the theme dictionary, so in dark mode it was black on black.
- **DataGridColumnHeader** — `DataGridHeaderBorder` ignores `Background`. Re-templating it throws away the two `Thumb` elements `PART_LeftHeaderGripper` / `PART_RightHeaderGripper` that DataGrid hooks for column resizing, and the columns silently become fixed **with no error at all**; they have to be added back under those exact names. `Test-Ui.ps1` verifies they are there.
- **ContextMenu / MenuItem** — light background, black text, blue highlight.
- **ComboBox** — the most involved: WPF requires a `ToggleButton` bound to `IsDropDownOpen` and a `Popup` named `PART_Popup`. Here the ToggleButton is transparent and sits *over* the border, so it catches clicks across the whole control without nesting one template inside another.

Colours are referenced with `{DynamicResource ...}` everywhere: `StaticResource` resolves once and would not follow a theme change. `Test-Ui.ps1` fails if a key exists in only one of the two theme files.

### Layout choices

- The progress bar and the log live **outside** the `TabControl` so they stay visible from every tab.
- The settings screen is a panel overlaid on the whole window, **not a second Window**: the theme brushes live in the main window's `MergedDictionaries`, so a separate Window would have to be wired to those dictionaries and re-wired on every theme change, plus owner, modality and placement.
- The search spinner sits at the **end** of its row: docked right it took 20px off the search box every time a search ran, and gave them back afterwards.
- During an operation the grids go **read-only, not disabled**: a disabled `DataGrid` stops responding to wheel, scrollbar and keyboard, so the list looked frozen.
