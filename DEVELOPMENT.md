# Development

Everything a change to this codebase needs: layout, build, tests, and the decisions that are not obvious from the code. For what the app does and how to use it, see [README.md](README.md).

The **UI and the documentation are in English**; the in-code comments are in Italian. User-facing strings live in `ui\UI.xaml` (labels, column headers) and in the `Write-Log` / `LogUI` / `MessageBox` calls under `src\modules\`.

Two rules for on-screen prose, which the About tab is the only place long enough to break:

- **One sentence per line, each short enough to fit.** Where free prose wraps, it is automatic wrapping that splits a sentence and leaves a stub on the next line; an explicit `<LineBreak/>` between sentences reads as a list instead. At a very narrow window wrapping comes back regardless.
- **A list of term-and-description belongs in a borderless grid, not in prose.** The About tab holds its five features in a two-column `Grid` named `AboutTable`: names in an `Auto` column, so it is exactly as wide as the longest one and every description starts at the same offset, and descriptions in a `*` column that takes the rest. Inside a cell wrapping is *fine* — the text re-indents under its own description rather than under the name, which is precisely what the prose version could not do. `Test-Ui.ps1` measures the two alignments and that the description column really does grow with the window.
- **No em dashes in UI text.** A colon separates a term from its description without leaving a long stroke in the middle of the line. `Test-Ui.ps1` fails on one outside a comment — Italian comments use them freely, and should.

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
       App.Prefs.ps1            user preferences under HKCU: Get-Pref / Set-Pref
       App.Jobs.ps1             background runspaces: Start-BackgroundJob, Start-WinGetQueue
       App.Theme.ps1            Light / Dark / System theme
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
       WinGetStudio-codesign.cer  public signing certificate (no private key)
tests\ Test-Ui.ps1              headless check of code, XAML, themes and startup
       Test-InvokeWinGet.ps1    winget execution and table parsing
dist\  WinGetStudio.exe         build output (signed, gitignored)
winget\1.9.0\                   winget-pkgs manifests for the published version
graphify-out\                   knowledge graph (report, graph.json and graph.html committed)
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

`CN=WinGet Studio`, valid to 2031. What that does and does not buy:

- **Does**: proves the exe has not been altered since the build, and shows a publisher name instead of nothing.
- **Does not**: make Windows trust it. `Get-AuthenticodeSignature` reports `UnknownError` and SmartScreen still says "unknown publisher", because the root is not among the trusted authorities. **This is expected and does not mean the signature is missing.**

To make it trusted, import the public certificate — `assets\WinGetStudio-codesign.cer`, no private key in it — into *Trusted Root Certification Authorities*: per user with `Import-Certificate -CertStoreLocation Cert:\CurrentUser\Root`, or machine-wide by GPO in a domain. Understand what you are doing first: anything signed with that certificate becomes trusted for whoever imports it.

For a signature trusted everywhere without importing anything, a commercial OV or EV certificate is needed (in a managed domain, one from the internal PKI would do as well). Both plug into the build through the environment variable above.

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

## Publishing to winget-pkgs

Manifests live in `winget\<version>\` — three files, as the community repository requires. They are kept here so they can be reviewed and versioned with the code; the pull request is a copy of that folder.

Validate before opening anything (this is the same validator the moderators run):

```powershell
winget validate --manifest .\winget\1.9.0
```

To install from them locally first, winget needs a feature enabled from an elevated prompt — `winget settings --enable LocalManifestFiles` — then `winget install --manifest .\winget\1.9.0`. Not strictly needed: the winget-pkgs CI installs and uninstalls the package in a sandbox on every pull request.

**Opening the pull request**

1. Fork `microsoft/winget-pkgs`.
2. Copy the folder to `manifests\f\FedeB2160\WinGetStudio\<version>\` (first letter of the publisher, then publisher, package, version).
3. Commit, push, open the PR against `master`. The title convention is `New version: FedeB2160.WinGetStudio version 1.9.0`.
4. Automated validation runs first (schema, URL reachable, hash, sandbox install). A human moderator then reviews it; the first submission of a new package takes longer than later updates.

`wingetcreate update FedeB2160.WinGetStudio --version 1.10.0 --urls <url> --submit` does all of this in one command for subsequent versions, once the package exists in the repository.

**Notes on the manifest**

- `InstallerType: portable` — the asset is a bare executable, so winget copies it and puts an alias on the PATH rather than running an installer.
- `Architecture: x86` — that is what ps2exe produces by default; it runs on x64 through WOW64.
- `ElevationRequirement: elevatesSelf` — the exe carries a `requireAdministrator` manifest, so *installing* needs no privileges while *running* asks for them.
- `PortableCommandAlias` is rejected by the validator as an unknown field, so the alias is left to winget (derived from the file name) and `Commands` is declared in the locale manifest instead.
- Every value with a `:` inside must be quoted, or the YAML parser fails — `ShortDescription` is the one that bites.

**Once the package is in the repository**, WinGet Studio will appear in its own Updates tab. Upgrading it from there cannot work — the file is in use — so it needs excluding from that list, or routing to the self-update path, which does the rename dance.

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

## Knowledge graph

`graphify-out\` holds a knowledge graph of this repository: 225 nodes and 392 edges over the code (extracted from the AST) plus the concepts and rationale from the documentation, grouped into 29 communities.

Three files are **committed**, because they are the durable value:

- `GRAPH_REPORT.md` — the readable report: communities, god nodes, surprising connections, suggested questions, and the audit trail of what was extracted versus inferred;
- `graph.json` — the graph itself, which is what answers queries without rebuilding anything;
- `graph.html` — the interactive graph, self-contained: clone the repo, open the file, no tooling required.

Everything else is gitignored, being either regenerable or specific to one machine: the Obsidian vault (257 notes, one per node), `cache\` (extraction cache), `manifest.json` (file mtimes and hashes for incremental runs), `cost.json` (token counter), `.graphify_python` and `.graphify_root` (paths on this PC), and `2026-08-03\` (a leftover snapshot from an earlier run — safe to delete).

Note that `graph.html` is ~190 KB and is rewritten in full on every rebuild, so each refresh lands as a large diff. That is the price of having the graph browsable straight from the repo; if the history ever gets uncomfortable, ignoring it again costs one line and one command to regenerate.

To regenerate the ignored vault, or the HTML after a rebuild:

```powershell
graphify export obsidian
graphify export html
```

To refresh the graph after changing the code — re-extracts only what changed:

```
/graphify . --update --obsidian
```

To ask the graph something instead of grepping:

```powershell
graphify query "how does the self-update replace the running exe?"
```

The graph is worth having here because the *why* behind this codebase is spread across code comments, this file and the changelog. Asking the graph crosses those boundaries: the pinning feature, for instance, connects to the parser guard for spaced headers, to the "one winget process at a time" rule, and to the test that removes the pin in a `finally` — three files and two documents that no single grep would bring together.

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
- **Cancelling a queue is cooperative.** `Start-WinGetQueue` shares a synchronized hashtable with its runspace and checks `Requested` at the top of each iteration, so the package in flight always finishes: killing an installer halfway leaves the machine in a state nobody can describe. A hashtable and not a `$script:` variable because the runspace has its own scope — a hashtable is a reference type, so both threads see the same object, the same reason `$rows` works. A fresh one per queue, so a request that arrives between two queues does not carry over.
- **`$script:queueVerb` publishes which queue is running**, because the busy state is global and a tab otherwise has no way to tell its own operation from another tab's. It is what lets the Updates button offer *Cancel* only for the update queue, and `Set-AppBusy $false` clears it *before* calling the handlers so each one sees the final state. The button's label is assigned on every call, not inside one branch: its appearance is a function of (busy, which queue) and must not depend on how it got there. The mechanism is generic — wiring it to Install or Uninstall is a few lines each — and only the Updates queue uses it today.
- **Every winget invocation goes through the path resolved once at startup**, `$wingetPath`, passed into each runspace through `-Vars`. `& winget` resolves the *name* on every call and depends on PATH and on the app execution alias, which under an elevated account other than the interactive one may not be there. Four read commands used to do that while the five write paths did not, which is the setup for a baffling failure: forget one `-Vars` entry and the variable is `$null` inside the runspace, the read comes back empty, and it looks like winget found nothing. The suite checks both halves.
- **Unbalanced quotes are refused, not run.** The command line handed to `cmd` is built by concatenation and each caller interpolates the package Id between quotes. An Id containing a double quote would produce a command that means something else, and cmd would run it — in an elevated process, with a name written by whoever authored the installer, since ARP display names end up as Ids. An odd number of quotes throws instead. It does **not** cover `%VAR%` expansion, which is a different problem; the guard should not be believed complete.
- **A search is the exception that nearly broke that rule.** It must not raise the busy state or typing would stall, so it counts itself in `$script:searchInFlight` — and everything that is about to run winget asks **`Test-WinGetBusy`**, which covers both. Asking `$script:isBusy` alone was the hole: typing three characters in Install and switching straight to Installed ran `winget search` and `winget list` at the same time. `Start-WinGetQueue` is the single choke point for the four queue operations — it takes the busy state itself, so no caller can forget to, and it refuses rather than starting a second process. The paths that call winget without going through the queue guard themselves: both scans, and export and import twice each, because the file dialog gives a pending search time to come back. `Start-SelfUpdate` guards too: it ends by replacing the executable and closing the window. `Start-UpdateCheck` deliberately does not — it only talks to GitHub.

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
- **ScrollBar** — same hardcoded light colours, and the last control in the window still painted by Windows rather than by the theme: in dark mode every scrollbar stayed white. The replacement is track plus thumb with no arrow buttons, which is what Windows 11 draws anyway. Two things it must keep: the `Track` named `PART_Track`, which ScrollBar uses to place the thumb (rename it and the bar stops working, with no error), and the two transparent `RepeatButton`s inside the track, which are what makes clicking the empty part of the track page up or down. The `Orientation` trigger swaps the axes for the horizontal bar; if paging on that one ever goes the wrong way, name the two repeat buttons and swap their commands to `PageLeftCommand` / `PageRightCommand` there.

Colours are referenced with `{DynamicResource ...}` everywhere: `StaticResource` resolves once and would not follow a theme change. `Test-Ui.ps1` fails if a key exists in only one of the two theme files.

**A control needs either a surface step or a visible border, and the light theme had neither.** `BgBrush` was `#FFFFFF` and `CtrlBgBrush` `#FDFDFD` — a 0.6% luminance step, which is to say none — so the only thing defining a button, a text box, the log or a tab was a `#CCCCCC` hairline at 1.61:1, and the disabled state's `Opacity 0.5` took that down to ~1.31 and erased it. The page is grey now (`#F3F3F3`) with white controls on it, which is how Windows 11 does it, and the border that marks an **interactive** control is its own key: `CtrlBorderBrush`, `#8A8A8A` in light (3.11:1 on the page, 3.45:1 on the control, so over the 3:1 WCAG 1.4.11 asks of anything that identifies a component). `BorderBrush2` keeps the old light value for **grid lines only** — at the same strength as the control borders the grid turns into a spreadsheet. In dark, `CtrlBorderBrush` is `#666666`: 2.84:1, under the 3:1 floor on purpose, because on a dark ground the surface step does the work and a 3:1 outline is heavier than anything Windows 11 draws — but still three times the `#3D3D3D` it replaces. `Test-Ui.ps1` measures the surface step and both border pairs in each theme, and fails if the disabled trigger goes back to using `Opacity`.

**A colour hardcoded in `UI.xaml` is a colour that only works in one theme.** The *Update to vX.Y.Z* button carried `Foreground="White"`, which reads fine on the light theme's accent (`#0078D4`, 4.53:1) and measures **2.01:1** on the dark theme's (`#4CC2FF`) — unreadable, on the one button that only appears when there is something important to say. The foreground is a theme key now (`AccentFgBrush`), and `Test-Ui.ps1` measures every foreground/background pair in both themes against the WCAG floors: 4.5:1 for text, 3:1 for graphical elements such as the status glyphs and the progress fill. The light theme's warning colour failed the same check at 2.86:1 and was darkened. Adding a colour means adding it to both theme files and, if anything sits on top of it, adding the pair to that check.

### Layout choices

- The progress bar and the log live **outside** the `TabControl` so they stay visible from every tab — including from Settings, which is why Settings is a tab pinned to the right of the strip and not an overlay. It used to be a `Border` with `Grid.RowSpan="4"` covering the whole window, which hid exactly the part that reports how an operation is going, and needed a chain of `ZIndex`, focus and Esc handling to behave like a screen. As a tab it needs none of that, and it is **not** a second Window: the theme brushes live in the main window's `MergedDictionaries`, so a separate Window would have to be wired to those dictionaries and re-wired on every theme change, plus owner, modality and placement.
- **`TabPanel` cannot right-align a single item**, so the tab strip is a `DockPanel` used as `IsItemsHost`: the three functional tabs take the default `Dock="Left"` and stay in declaration order, `TabSettings` declares `Dock="Right"`, and `LastChildFill="False"` stops it from stretching across the strip — the same trap, with the same fix, as any other `DockPanel` whose last child must respect its own `Dock`. The `Margin="0,0,0,-1"` seam between the active tab and the content border sits on the panel, not on the items, so the swap does not touch it.
- The tabs are in alphabetical order (**Install | Installed | Updates**) but **Updates is the view the app opens on**, via `IsSelected="True"`: the startup scan fills that list, and opening on a tab nobody is looking at would hide the update count. Navigation order and default view are separate concerns.
- **The tab headers are one `HeaderTemplate`**, not four hand-built headers: the glyph comes from each tab's `Tag` through `RelativeSource AncestorType=TabItem`, and `Header` stays the plain string, which is both the accessible name and what the tab-order checks rely on. What the strip shows — icon, name, or both — is two `Visibility` values in the window's own `Resources`, read with `DynamicResource`, so rewriting them repaints the strip without rebuilding anything. `Set-Theme` does not disturb them: it clears `MergedDictionaries`, not the window's own resources. Because of those two non-colour keys, the check that every `DynamicResource` exists in both themes only looks at keys containing `Brush`.
  - The gap between icon and word is a **symmetric** margin on the icon (`4,0,4,0`), which is the only form that centres correctly in every mode. On the word it leaves the word off-centre in *Text* mode; asymmetric on the icon it leaves the glyph off-centre in *Icon* mode, because a margin outlives the element it was meant to separate from. A trigger cannot fix it — a `DataTrigger`'s `Binding` does not accept a `DynamicResource` — and neither can a `Thickness` held as a resource and rewritten from PowerShell: layout then fails with `InvalidCastException` on the first measure pass. Symmetric needs none of that.
  - The header panel carries `MinHeight=16`. Without it the strip **shrank by 2px** in *Icon* mode: the glyph's line box is shorter than the text's, and with the word collapsed only the glyph was left to set the height. 16 is what the text occupies on its own, so the strip is 29px in all three modes.
  - **Declaration order and position do not match on the right.** In a `DockPanel` the *first* child with `Dock=Right` takes the right edge and the next sits to its left, so `TabAbout` is declared before `TabSettings` precisely because it is the one further right — and the negative right margin that keeps the last tab flush with the frame lives on About.
  - In *Icon* mode a tab has no text, so each `TabItem` carries `AutomationProperties.Name`: without it the tab would announce nothing.
- The lazy load of the Installed tab compares `SelectedItem` with **the `TabInstalled` object**, not with its header string: the Settings tab's header is not even a string (glyph plus word), and a rename must not silently switch the automatic load off.
- The search spinner sits at the **end** of its row: docked right it took 20px off the search box every time a search ran, and gave them back afterwards.
- During an operation the grids go **read-only, not disabled**: a disabled `DataGrid` stops responding to wheel, scrollbar and keyboard, so the list looked frozen.



