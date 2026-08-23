# Tabbed Settings and UI Improvements — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn the Settings overlay into a fourth tab pinned to the right of the strip, reorder the tabs alphabetically, and close the measured accessibility, concurrency and persistence gaps found in the 2026-08-04 review.

**Architecture:** WinGet Studio is a single-window WPF app written in PowerShell 5.1. `src\main.ps1` is the only entry point (self-elevation, then dot-sources `src\modules\*.ps1`); `src\build.ps1` concatenates those modules and inlines `ui\*.xaml` into one `.exe` via ps2exe. Controls are resolved once by name in `Start-App` and published into script scope so every module sees them without a prefix. All winget work happens in background runspaces, and every UI write from a runspace goes through `$window.Dispatcher`. This plan changes the tab structure first (because it *deletes* a module and simplifies three later tasks), then works outward from measured defects to polish.

**Tech Stack:** PowerShell 5.1, WPF (PresentationFramework), XAML loaded at runtime by `XamlReader`, ps2exe for packaging, two hand-rolled PowerShell test scripts under `tests\`. No runtime dependencies, no test framework.

## Global Constraints

Every task's requirements implicitly include this section. Most of these are enforced by the test suite, which will fail if they are broken.

- **PowerShell 5.1 only.** ps2exe compiles against it. No PowerShell 6+ syntax; specifically no `` `u{XXXX} `` escapes (they are not escapes in 5.1 and reach the screen as literal `u{...}`). Use `[char]0x2026` instead. Enforced by test 6.
- **In-code comments in Italian, all user-facing strings in English.** Stated in `DEVELOPMENT.md`. User-facing strings live in `ui\UI.xaml` and in the `Write-Log` / `LogUI` / `MessageBox` calls.
- **Colours come from the themes via `{DynamicResource ...}`, never `StaticResource`** — a `StaticResource` resolves once and would not follow a theme change.
- **`ui\Theme.Light.xaml` and `ui\Theme.Dark.xaml` must declare exactly the same keys.** Enforced by test 3; every `DynamicResource` used in `UI.xaml` must exist in both, enforced by test 4.
- **Contrast floors:** text ≥ 4.5:1, graphical elements (status glyphs, the progress fill) ≥ 3:1, measured against every background the element can sit on. Task 2 adds the test that enforces this.
- **Never `$Grid.IsEnabled = ...` and never `Items.Refresh()`.** A disabled `DataGrid` stops scrolling; `Items.Refresh()` regenerates the view and throws the scroll position back to the top. Use `IsReadOnly` and `INotifyPropertyChanged`. Enforced by test 9.
- **`Dispatcher.BeginInvoke` must be called priority-first**: `BeginInvoke([DispatcherPriority]::Background, [action]{...})`. The other argument order silently resolves to `BeginInvoke(Delegate, params Object[])` and throws `TargetParameterCountException` at dispatch. Enforced by `Test-InvokeWinGet.ps1` section 2.
- **Never `GetNewClosure()` on a scriptblock that touches `$script:`.** The closure creates a module scope in which `$script:` is no longer this script; `$script:jobs` came back `$null` and job cleanup died. Documented at `src\modules\App.Jobs.ps1:88`.
- **Controls are assigned with `$script:`** (`Set-Variable -Scope Script` in `Start-App`). A plain `$Grid = ...` inside a function is invisible to the modules and only fails once the window is open.
- **Column headers in the grids must be non-empty and UPPERCASE**, and the header template must bind `HorizontalAlignment` to `HorizontalContentAlignment`. Enforced by test 10b.
- **Every `&#xNNNN;` glyph in `UI.xaml` must exist in both `SegoeIcons.ttf` and `segmdl2.ttf`.** A wrong codepoint does not error, it renders as an empty box. Enforced by test 10c. `&#xE713;` (gear) is already verified.
- **One source of truth for the version:** `$AppVersion` in `src\main.ps1`, read by `build.ps1` with the regex `(?m)^\s*\$AppVersion\s*=\s*'([\d.]+)'`. Enforced by test 11.
- **One source of truth for the module list:** `$moduleNames` in `src\main.ps1`. `build.ps1` and the test suite both parse it. A module file on disk that is missing from the list fails test 1, and a listed file that does not exist also fails.
- **Never two winget processes at once.** Documented at `DEVELOPMENT.md:220`. Task 4 closes the one remaining hole in this invariant.

**How the work is committed.** All of it lands on one branch, `feature/v1.10.0`, and `main` stays on what is published.

- **One commit per task**, not per step. Each commit contains the code, the tests, the lines of `README.md` and `DEVELOPMENT.md` that the task invalidates, and one line under `## Unreleased` in `CHANGELOG.md`. Docs and code do not travel separately: a README describing yesterday's button is worse than no README.
- **Both suites must be green before the commit.** There is no CI, so this gate is manual and it is the only one there is.
- **Push after every commit** (`git push`, the first time with `-u origin feature/v1.10.0`). No batching: if the session dies, the work is already out.
- Commit messages follow the conventional style the history already uses (`feat(ui):`, `fix(winget):`, `refactor:`, `chore(release):`). Each task below carries its own.
- `git push` needs the credential helper that `gh auth setup-git` installs, with `gh` authenticated as **FedeB2160** — the account that owns the repo. Verify once with `gh api repos/FedeB2160/WinGetStudio --jq .permissions`: it must report `"push": true`.

**Running the tests** — there is no test selector; each script runs top to bottom and stops at the first failure:

```bash
powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-Ui.ps1
```

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-InvokeWinGet.ps1
```

`-STA` is mandatory for `Test-Ui.ps1` (WPF requires a single-threaded apartment). It takes 1-3 minutes: it calls winget for real (read-only), adds and removes a pin on `7zip.7zip` inside a `finally`, and makes one anonymous call to the GitHub API. Blocks that need winget print `SKIP` instead of failing when it is absent. It prints one `OK <name>` line per check and `TUTTO OK` at the end.

**Caveat that will bite you in Task 1 and after:** a `TabControl` only realises the content of the *selected* tab. Objects declared in `UI.xaml` always exist and are always reachable by `FindName`, so setting `.Text` or `.Items` on a control inside an unselected tab works fine. But anything that depends on **layout** — `ActualWidth`, `TranslatePoint`, `IsVisible` — returns zero or false until that tab is selected and `UpdateLayout()` has run. `Test-Ui.ps1` section 15 already selects the Install tab for exactly this reason.

**Decisions already taken** (do not revisit; they are the answers to the six open questions from the review):

| Decision | Value |
|---|---|
| Tab names | Unchanged: `Install`, `Installed`, `Updates`. winget's own vocabulary. |
| Tab selected at startup | `Updates`, via `IsSelected="True"` in XAML. Navigation order and default view are separate concerns. |
| Esc | Removed with the overlay. A tab is not modal. |
| Settings tab header | Gear glyph `&#xE713;` **plus** the word "Settings". The text supplies the accessible name. **Superseded by Task 21**, which gives every tab an icon and makes icon/text/both a user choice — the Settings tab stops being the special one. |
| `Unknown` / `MS Store` / `Scope` | Stay where they are, gain persistence. `Scope` must not move away from the `Install` button it modifies. |
| "Check for updates at startup" | On by default. Opt-out, matching today's behaviour. |
| Flags and pins during a queue | Disabled, and visibly so. The grid itself stays scrollable - never `IsEnabled` on a `DataGrid`. |
| Update button during a queue | It becomes **Cancel**; cancelling lets the package in flight finish and then stops. Only the Updates queue gets this - Install and Uninstall keep today's behaviour. |
| Update after an alteration | Locked until the next Check. Update, install, uninstall and import mark the list stale; pins do not. A cancelled queue locks too: telling the two cases apart costs more than it is worth. |
| Dark-theme scrollbars | Re-templated, in the same pass as the other measured dark-theme defects. Existing theme keys only, so no test changes. |
| C# migration | **Not now.** Anything that genuinely wants C# is compiled in-process with `Add-Type`, as `WgtRow` already is. Reconsider only on a second window, real async orchestration, or a need for unit tests - and then target .NET Framework 4.8, which keeps the 0.2 MB no-install exe. Never a C# host driving PowerShell: winget is a CLI, `Process.Start` is enough. |
| Claude Code note in About | One voluntary line. The AI Act's Article 50, applicable from 2 August 2026, covers AI systems interacting with people, machine-readable marking of synthetic content, biometric and emotion recognition, and deepfakes. This app contains no AI system and generates no content, so none of the four apply: the line is honesty, not compliance. |

---

## File Structure

| File | Responsibility | Change |
|---|---|---|
| `ui\UI.xaml` | window layout and control templates | Tab strip becomes a `DockPanel` items host; tabs reordered; Settings becomes a `TabItem`; gear button, overlay `Border` and settings title row removed; `GridSplitter` added; Settings body relaid out on a 2-column `Grid`; `ScrollBar` re-templated; ticks disabled while a grid is read-only; About rewritten |
| `ui\Theme.Light.xaml`, `ui\Theme.Dark.xaml` | colour palettes, identical key sets | new `AccentFgBrush`; Light `WarnBrush` corrected |
| `src\modules\App.Prefs.ps1` | **new.** Read and write user preferences under `HKCU:\Software\WinGetStudio` | created in Task 5 |
| `src\modules\App.Settings.ps1` | opening and closing the settings overlay | **deleted** in Task 1 |
| `src\modules\App.Ui.ps1` | shared helpers: log, global busy state | gains `Test-WinGetBusy` (Task 4) and `Register-GridRefresh` (Task 12) |
| `src\modules\App.Bootstrap.ps1` | `WgtRow`, XAML loading, `Start-App` | control list, initialisation calls, close-down cleanup, hyperlink handler |
| `src\modules\App.Theme.ps1` | Light / Dark / Auto | its inline registry access moves to `App.Prefs.ps1` |
| `src\modules\App.Jobs.ps1` | background runspaces and the winget queue | `Start-WinGetQueue` becomes the choke point for the busy state, publishes which queue is running, and gains cooperative cancellation |
| `src\modules\Tab.*.ps1` | one per tab | busy guards, preference persistence, deferred-refresh helper |
| `src\modules\App.Backup.ps1`, `App.Update.ps1` | export/import, self-update | busy guards; startup-check preference |
| `src\main.ps1` | entry point | `$moduleNames`, `$AppVersion` |
| `tests\Test-Ui.ps1` | headless UI and integration checks | settings block rewritten; tab selection by name; new checks for contrast, tab pinning, busy guard, preferences |
| `tests\Test-InvokeWinGet.ps1` | winget execution and table parsing | new check for unbalanced quotes |
| `README.md`, `DEVELOPMENT.md`, `CHANGELOG.md` | user and developer docs | updated by the task that invalidates them |

---

## Task 1: Settings becomes a tab pinned right, tabs reordered

`TabPanel` cannot right-align a single item. A `DockPanel` can, and it is legal as `IsItemsHost`: the three functional tabs take the default `Dock="Left"` and stack in declaration order, the Settings tab takes `Dock="Right"`, and the panel needs `LastChildFill="False"` — the same trick, with the same reason, that the current settings header already uses. Verified with a standalone probe on a 900x620 window: the three left tabs land at x=0.0/63.1/139.5 and Settings at x=805.4, and `SelectedContent` swaps correctly in both directions.

This task is a net removal of about 70 lines and one module.

**Files:**
- Modify: `ui\UI.xaml:223-249` (TabControl template), `ui\UI.xaml:537-826` (tab order, new Settings tab, gear button removed), `ui\UI.xaml:845-913` (overlay removed)
- Modify: `src\modules\App.Bootstrap.ps1:120-137` (control list), `:147-164` (initialisation)
- Modify: `src\main.ps1:81-95` (`$moduleNames`)
- Modify: `src\modules\Tab.Installed.ps1:175-182` (tab identity by object, not by header string)
- Delete: `src\modules\App.Settings.ps1`
- Test: `tests\Test-Ui.ps1` — replace lines 295-304, and lines 402 and 439
- Modify: `README.md:20`, `README.md:60-62`, `DEVELOPMENT.md:25`, `DEVELOPMENT.md:245`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: four named tabs — `$TabInstall`, `$TabInstalled`, `$TabUpdates`, `$TabSettings` — resolved into script scope by `Start-App` like every other control. Later tasks and tests select a tab with `$TabInstalled.IsSelected = $true`. `Show-Settings`, `Hide-Settings` and `Initialize-Settings` cease to exist.

- [ ] **Step 1: Write the failing test**

In `tests\Test-Ui.ps1`, delete the settings block at lines 295-304 (the four `SettingsPanel` visibility assertions, the `Show-Settings` / `Hide-Settings` calls, and the two `Get-FunctionSource 'Initialize-Settings'` checks for `PreviewKeyDown` and `Key]::Escape`). Replace it with:

```powershell
# La schermata delle impostazioni e' un TAB come gli altri, l'ultimo, fissato a destra:
# cosi' barra di avanzamento e log restano visibili anche mentre e' aperta, e non serve
# ne' un overlay con RowSpan/ZIndex ne' un tasto per chiuderla.
if ($TabMain.Items.Count -ne 4) { throw "attesi 4 tab, trovati $($TabMain.Items.Count)" }
if ($TabMain.Items[3] -ne $TabSettings) { throw "il tab Settings non e' l'ultimo" }
# Ordine alfabetico dei tre tab funzionali.
foreach ($pair in @(@(0, $TabInstall, 'Install'), @(1, $TabInstalled, 'Installed'), @(2, $TabUpdates, 'Updates'))) {
    if ($TabMain.Items[$pair[0]] -ne $pair[1]) { throw "il tab in posizione $($pair[0]) non e' $($pair[2])" }
    if ($pair[1].Header -ne $pair[2]) { throw "header inatteso in posizione $($pair[0]): '$($pair[1].Header)'" }
}
# Updates resta la vista di apertura: la scansione all'avvio popola proprio quella.
if (-not $TabUpdates.IsSelected) { throw "all'avvio deve essere selezionato Updates" }
# I controlli delle impostazioni vivono DENTRO il tab: se restassero fuori, tornerebbero
# a coprire il resto della finestra.
$p = $CmbTheme
while ($p -and $p -ne $TabSettings) { $p = [System.Windows.LogicalTreeHelper]::GetParent($p) }
if ($p -ne $TabSettings) { throw "la tendina del tema non e' dentro il tab Settings" }
"OK settab $($TabMain.Items.Count) tab, Settings ultimo, Updates selezionato all'avvio"
```

Then, still in `tests\Test-Ui.ps1`, replace the two index-based selections so a future reorder cannot silently break the suite. At line 402 replace `$tabMain.SelectedIndex = 1` with:

```powershell
$TabInstall.IsSelected = $true
```

and at line 439 replace `$tabMain.SelectedIndex = 2` with:

```powershell
$TabInstalled.IsSelected = $true
```

Finally add the layout assertion for the right pinning. Put it immediately after the existing spinner check of section 15 (after the line printing `OK spin`), because it needs the same `Measure`/`Arrange`/`UpdateLayout` that section already performs:

```powershell
# 15b) Il tab Settings e' fissato a DESTRA della striscia: un DockPanel come items host
# (TabPanel non sa allineare a destra un singolo item). Se qualcuno rimette TabPanel, il
# tab torna in fila subito dopo Updates e questo controllo se ne accorge.
$xUpdates  = $TabUpdates.TranslatePoint([System.Windows.Point]::new(0, 0), $window.Content).X
$xSettings = $TabSettings.TranslatePoint([System.Windows.Point]::new(0, 0), $window.Content).X
$rightOfUpdates = $xUpdates + $TabUpdates.ActualWidth
if ($TabSettings.ActualWidth -le 0) { throw "layout della striscia non calcolato: il tab Settings misura 0" }
if ($xSettings -lt $rightOfUpdates + 100) {
    throw "il tab Settings non e' fissato a destra (x=$([int]$xSettings), fine di Updates=$([int]$rightOfUpdates))"
}
"OK tabdock Settings fissato a destra (x=$([int]$xSettings) contro $([int]$rightOfUpdates) di Updates)"
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-Ui.ps1`

Expected: FAIL at the control-resolution stage, before the new block is even reached — `controllo richiesto dal codice ma assente da UI.xaml: TabInstall` is not yet possible either, since Step 3 has not added the names to the code. The first failure you will actually see is `Impossibile chiamare un metodo su un'espressione con valore null` or `il tab in posizione 0 non e' Install`, depending on how far the script gets. Any failure in this block is the expected state; do not try to make it pretty.

- [ ] **Step 3: Rework the tab strip template in `ui\UI.xaml`**

Replace the `TabPanel` line in the `TabControl` template (currently `ui\UI.xaml:235-236`) with:

```xml
                            <!-- DockPanel e non TabPanel: TabPanel dispone le linguette in
                                 fila e non sa fissarne una a destra. Con un DockPanel come
                                 items host i tre tab funzionali prendono il Dock di default
                                 (Left) e restano in ordine di dichiarazione, mentre il tab
                                 Settings dichiara Dock="Right".
                                 LastChildFill="False" e' OBBLIGATORIO: l'ultimo figlio di un
                                 DockPanel riempie lo spazio residuo IGNORANDO il proprio Dock,
                                 quindi senza questo il tab Settings si allargherebbe fino a
                                 coprire la striscia. Stesso inciampo dell'intestazione delle
                                 impostazioni di prima.
                                 Margin inferiore -1: il bordo basso della linguetta attiva
                                 copre quello alto del contenuto, cosi' i due si fondono. Sta
                                 sul PANNELLO, non sugli item, quindi il cambio non lo tocca. -->
                            <DockPanel Grid.Row="0" Panel.ZIndex="1" IsItemsHost="True"
                                       LastChildFill="False" Margin="0,0,0,-1" Background="Transparent"/>
```

- [ ] **Step 4: Reorder the tabs and name them**

In `ui\UI.xaml`, move the whole `<TabItem Header="Updates">` element (currently lines 539-622) so it comes *after* the `Installed` tab, giving the order Install, Installed, Updates. Add `x:Name` to all three and `IsSelected="True"` to Updates only:

```xml
                <TabItem x:Name="TabInstall" Header="Install">
```

```xml
                <TabItem x:Name="TabInstalled" Header="Installed">
```

```xml
                <!-- IsSelected: l'ordine dei tab e' alfabetico, ma la vista di apertura resta
                     Updates — la scansione lanciata da Add_ContentRendered popola proprio
                     questa, e aprire su un tab che nessuno guarda nasconderebbe il conteggio. -->
                <TabItem x:Name="TabUpdates" Header="Updates" IsSelected="True">
```

Do not touch anything inside the three tabs.

- [ ] **Step 5: Add the Settings tab and delete the overlay**

Delete the gear `Button` (currently `ui\UI.xaml:819-825`, the block with `x:Name="BtnSettings"`).

Then delete the whole `<Border x:Name="SettingsPanel">` element (currently `ui\UI.xaml:845-913`) and add, as the **last** child of the `TabControl`, right after the Updates tab:

```xml
                <!-- Impostazioni: un tab come gli altri, fissato a destra della striscia.
                     PERCHE' NON UN OVERLAY: sovrapposto a tutta la finestra copriva barra di
                     avanzamento e log, cioe' l'unico canale che dice come sta andando
                     un'operazione, e serviva una catena di RowSpan, ZIndex, fuoco e Esc per
                     comportarsi come una schermata. Da tab non serve niente di tutto questo.
                     L'header e' glifo + parola: il testo fa anche da nome accessibile, che un
                     header di sola icona non avrebbe (uno screen reader leggerebbe il
                     codepoint). E713 (Settings) esiste in entrambi i font di sistema —
                     Test-Ui.ps1 lo verifica.
                     Nessun Foreground esplicito sui due TextBlock: cosi' ereditano quello
                     della linguetta e seguono i trigger di selezione e hover. -->
                <TabItem x:Name="TabSettings" DockPanel.Dock="Right" Margin="2,0,0,0">
                    <TabItem.Header>
                        <StackPanel Orientation="Horizontal">
                            <TextBlock Text="&#xE713;" FontSize="13" Margin="0,0,7,0"
                                       FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets"
                                       VerticalAlignment="Center"/>
                            <TextBlock Text="Settings" VerticalAlignment="Center"/>
                        </StackPanel>
                    </TabItem.Header>
                    <!-- Impostazioni in colonna: sono pochi controlli e crescono in verticale.
                         ScrollViewer per non tagliarli a finestra piccola. -->
                    <ScrollViewer VerticalScrollBarVisibility="Auto">
                        <StackPanel>
                            <TextBlock Text="APPEARANCE" Style="{StaticResource SettingsHeader}"/>
                            <StackPanel Orientation="Horizontal" Margin="0,0,0,18">
                                <TextBlock Text="Theme" VerticalAlignment="Center" Width="120"
                                           Foreground="{DynamicResource FgBrush}"/>
                                <!-- Le voci le riempie App.Theme.ps1: sono gli stessi valori
                                     che finiscono nel registro (Light | Dark | Auto). -->
                                <ComboBox x:Name="CmbTheme" Width="180"/>
                                <TextBlock x:Name="TxtThemeHint" VerticalAlignment="Center" Margin="12,0,0,0"
                                           Foreground="{DynamicResource SubtleFgBrush}"/>
                            </StackPanel>

                            <TextBlock Text="UPDATES" Style="{StaticResource SettingsHeader}"/>
                            <StackPanel Orientation="Horizontal" Margin="0,0,0,8">
                                <TextBlock Text="Installed version" VerticalAlignment="Center" Width="120"
                                           Foreground="{DynamicResource FgBrush}"/>
                                <TextBlock x:Name="TxtVersion" VerticalAlignment="Center"
                                           FontWeight="SemiBold" Foreground="{DynamicResource FgBrush}"/>
                            </StackPanel>
                            <StackPanel Orientation="Horizontal" Margin="120,0,0,18">
                                <Button x:Name="BtnCheckUpdate" Content="Check for updates" Width="140" Height="26"/>
                                <!-- Compare solo quando una release e' piu' recente di questa. -->
                                <Button x:Name="BtnUpdateApp" Height="26" Padding="12,0" Margin="8,0,0,0"
                                        Visibility="Collapsed"
                                        Background="{DynamicResource AccentBrush}" Foreground="White"/>
                                <Control x:Name="UpdateSpinner" Width="20" Height="20" Style="{StaticResource Spinner}"
                                         Margin="10,0,0,0" Visibility="Collapsed"/>
                                <TextBlock x:Name="TxtUpdateStatus" VerticalAlignment="Center" Margin="12,0,0,0"
                                           Foreground="{DynamicResource SubtleFgBrush}"/>
                            </StackPanel>

                            <TextBlock Text="ABOUT" Style="{StaticResource SettingsHeader}"/>
                            <TextBlock Foreground="{DynamicResource SubtleFgBrush}" TextWrapping="Wrap"
                                       Text="A graphical front end for winget: update, install, uninstall, pin and export packages. Requires administrator rights, which it asks for at startup."/>
                        </StackPanel>
                    </ScrollViewer>
                </TabItem>
```

The body is the old overlay content with the `DockPanel` wrapper, the "Settings" title and the X button dropped: the tab supplies its own label, and there is nothing to close. `Foreground="White"` on `BtnUpdateApp` stays for now — Task 2 fixes it.

- [ ] **Step 6: Update the control list and the initialisation in `src\modules\App.Bootstrap.ps1`**

In the `foreach ($n in @(...))` list, remove `'BtnSettings'`, `'BtnCloseSettings'` and `'SettingsPanel'`, and add the four tab names. The last two lines of the list become:

```powershell
        'BtnSettings', 'BtnCloseSettings', 'SettingsPanel'
```

replaced by:

```powershell
        'TabInstall', 'TabInstalled', 'TabUpdates', 'TabSettings'
```

Then remove the `Initialize-Settings` call from the initialisation block:

```powershell
    Initialize-Theme
    Initialize-UpdatesTab
    Initialize-InstallTab
    Initialize-InstalledTab
    Initialize-Backup
    Initialize-Update
```

- [ ] **Step 7: Identify the Installed tab by object in `src\modules\Tab.Installed.ps1`**

Replace the header-string comparison at the end of `Initialize-InstalledTab`:

```powershell
    # Primo ingresso nella scheda: carica l'elenco da solo, cosi' non si paga l'attesa
    # all'avvio del programma chi non usa questa scheda.
    $TabMain.Add_SelectionChanged({
        param($s, $e)
        # Il DataGrid dentro la scheda rilancia SelectionChanged (righe selezionate): si
        # reagisce solo all'evento del TabControl stesso.
        if ($e.OriginalSource -ne $TabMain) { return }
        if ($script:installedLoaded) { return }
        # Confronto con l'OGGETTO e non con l'header: una rinomina della linguetta non deve
        # spegnere in silenzio il caricamento automatico.
        if ($TabMain.SelectedItem -eq $TabInstalled) { Load-Installed }
    })
```

- [ ] **Step 8: Delete the module and delist it**

```bash
git rm src/modules/App.Settings.ps1
```

In `src\main.ps1`, remove the `'App.Settings.ps1'` line from `$moduleNames`. The file must be deleted, not merely delisted: the suite fails on a module present in `src\modules\` but absent from `$moduleNames`, and fails the other way round too.

- [ ] **Step 9: Run the tests to verify they pass**

Run: `powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-Ui.ps1`

Expected: PASS, ending in `TUTTO OK`, including the new `OK settab` and `OK tabdock` lines and `OK mods 12 moduli elencati` (one fewer than before).

- [ ] **Step 10: Launch from source and look at it**

```bash
powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\src\main.ps1
```

The headless suite cannot see the tab strip. Check by eye: the strip reads `Install | Installed | Updates` on the left and the gear + `Settings` on the right; clicking Settings keeps the progress bar and the log on screen; the active tab's bottom border still merges into the content border; the selected and hover colours still work on all four tabs in **both** themes (switch theme from inside the Settings tab and watch the strip repaint).

- [ ] **Step 11: Update the docs**

In `DEVELOPMENT.md`, remove the `App.Settings.ps1` line from the layout listing (line 25). At line 245, extend the note about the shared progress bar and log:

```markdown
- The progress bar and the log live **outside** the `TabControl` so they stay visible from every tab — including the Settings tab, which is why Settings is a tab pinned to the right of the strip and not an overlay. `TabPanel` cannot right-align a single item, so the strip is a `DockPanel` used as `IsItemsHost`: the three functional tabs take the default `Dock="Left"`, Settings declares `Dock="Right"`, and `LastChildFill="False"` stops it from stretching across the strip.
```

In `README.md` at line 20, replace "The window has three tabs." with "The window has three tabs plus **Settings**, pinned to the right of the strip." In the `### Settings` section at lines 60-62, replace the gear-button-and-Esc sentence with "The **Settings** tab, at the right end of the tab strip, holds the theme, the version and the update controls. It is a tab like the others, so the progress bar and the log stay visible while you are in it."

- [ ] **Step 12: Commit**

```bash
git add ui/UI.xaml src/main.ps1 src/modules/App.Bootstrap.ps1 src/modules/Tab.Installed.ps1 tests/Test-Ui.ps1 README.md DEVELOPMENT.md
git commit -m "feat(ui): settings becomes a tab pinned right, tabs in alphabetical order"
```

---

## Task 2: Contrast defects

Two measured failures. The update button is the more serious: it only appears when an update actually exists, and in the dark theme its label sits at 2.01:1.

**Files:**
- Modify: `ui\Theme.Light.xaml`, `ui\Theme.Dark.xaml`
- Modify: `ui\UI.xaml` (the `BtnUpdateApp` element inside the Settings tab)
- Modify: `src\modules\App.Update.ps1:57` (comment typo)
- Test: `tests\Test-Ui.ps1` — new section after the existing theme checks

**Interfaces:**
- Consumes: the Settings tab from Task 1.
- Produces: theme key `AccentFgBrush` — the foreground to use on top of `AccentBrush`.

- [ ] **Step 1: Write the failing test**

In `tests\Test-Ui.ps1`, insert this immediately after the `OK ref` line of section 4:

```powershell
# 4b) Contrasto: le coppie che il tema promette leggibili lo sono davvero, in ENTRAMBI i
# temi. Il pulsante di aggiornamento aveva Foreground="White" cablato: bianco su
# AccentBrush fa 4.53:1 in Light ma 2.01:1 in Dark, cioe' illeggibile proprio sul pulsante
# piu' importante della schermata. Soglie WCAG: 4.5:1 per il testo, 3:1 per gli elementi
# grafici (i glifi di esito, il riempimento della barra).
function Get-Luminance([System.Windows.Media.Color]$c) {
    $ch = @($c.R, $c.G, $c.B) | ForEach-Object {
        $s = $_ / 255
        if ($s -le 0.03928) { $s / 12.92 } else { [Math]::Pow(($s + 0.055) / 1.055, 2.4) }
    }
    return 0.2126 * $ch[0] + 0.7152 * $ch[1] + 0.0722 * $ch[2]
}
function Get-Contrast($dict, [string]$fg, [string]$bg) {
    $lf = Get-Luminance $dict[$fg].Color
    $lb = Get-Luminance $dict[$bg].Color
    $hi = [Math]::Max($lf, $lb); $lo = [Math]::Min($lf, $lb)
    return [Math]::Round(($hi + 0.05) / ($lo + 0.05), 2)
}
# fg, bg, soglia. I glifi di esito stanno sia sulle righe normali sia su quelle alterne.
$pairs = @(
    @('FgBrush',        'BgBrush',       4.5), @('FgBrush',       'CtrlBgBrush',  4.5),
    @('SubtleFgBrush',  'BgBrush',       4.5), @('SubtleFgBrush', 'CtrlBgBrush',  4.5),
    @('AccentFgBrush',  'AccentBrush',   4.5),
    @('OkBrush',        'BgBrush',       3.0), @('OkBrush',       'RowAltBgBrush', 3.0),
    @('WarnBrush',      'BgBrush',       3.0), @('WarnBrush',     'RowAltBgBrush', 3.0),
    @('ErrBrush',       'BgBrush',       3.0), @('ErrBrush',      'RowAltBgBrush', 3.0),
    @('AccentBrush',    'BgBrush',       3.0)
)
foreach ($t in @{ Light = $light; Dark = $dark }.GetEnumerator()) {
    foreach ($p in $pairs) {
        $r = Get-Contrast $t.Value $p[0] $p[1]
        if ($r -lt $p[2]) { throw "$($t.Key): $($p[0]) su $($p[1]) fa ${r}:1, minimo $($p[2]):1" }
    }
}
"OK contr  $($pairs.Count) coppie sopra soglia nei due temi"

# Il pulsante di aggiornamento non deve tornare a un colore cablato: su AccentBrush ci va
# AccentFgBrush, che i due temi definiscono in modo diverso.
if ($uiTextEarly -match '(?s)x:Name="BtnUpdateApp".*?Foreground="White"') {
    throw "BtnUpdateApp ha ancora Foreground=White: 2.01:1 in Dark"
}
```

`$light` and `$dark` are already loaded by section 3. `$uiTextEarly` does not exist yet — add it right before the new block, since `$uiText` is only read much later at section 10:

```powershell
$uiTextEarly = Get-Content (Join-Path $root 'ui\UI.xaml') -Raw
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-Ui.ps1`

Expected: FAIL with `Impossibile indicizzare in un oggetto null` on the `AccentFgBrush` pair (the key does not exist yet). After Step 3 adds the key, re-running fails instead with `Light: WarnBrush su BgBrush fa 2.86:1, minimo 3:1` and then with `BtnUpdateApp ha ancora Foreground=White`.

- [ ] **Step 3: Add `AccentFgBrush` and fix the light warning colour**

In `ui\Theme.Light.xaml`, add the key and correct `WarnBrush`:

```xml
    <SolidColorBrush x:Key="WarnBrush"       Color="#8A6F00"/>  <!-- esito avviso -->
```

```xml
    <SolidColorBrush x:Key="AccentFgBrush"   Color="#FFFFFF"/>  <!-- testo sopra AccentBrush -->
```

`#B89500` su bianco faceva 2.86:1, sotto il 3:1 richiesto a un elemento grafico; `#8A6F00` fa 4.82:1 e resta ambra. White on `#0078D4` measures 4.53:1.

In `ui\Theme.Dark.xaml`, add the matching key — **not** white, which on the light-blue dark accent measures 2.01:1:

```xml
    <SolidColorBrush x:Key="AccentFgBrush"   Color="#00243A"/>  <!-- testo sopra AccentBrush: 7.97:1 su #4CC2FF -->
```

- [ ] **Step 4: Use the key on the button**

In `ui\UI.xaml`, in the `BtnUpdateApp` element inside the Settings tab:

```xml
                                <!-- Compare solo quando una release e' piu' recente di questa.
                                     Foreground dal tema e NON "White": l'accento scuro e'
                                     azzurro chiaro (#4CC2FF) e il bianco sopra faceva 2.01:1. -->
                                <Button x:Name="BtnUpdateApp" Height="26" Padding="12,0" Margin="8,0,0,0"
                                        Visibility="Collapsed"
                                        Background="{DynamicResource AccentBrush}"
                                        Foreground="{DynamicResource AccentFgBrush}"/>
```

- [ ] **Step 5: Fix the comment typo**

In `src\modules\App.Update.ps1:57`, `# I tag sono "v1.6.0": la v va togliesta per confrontare come versione.` becomes:

```powershell
            # I tag sono "v1.6.0": la v va tolta per confrontare come versione.
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-Ui.ps1`

Expected: PASS with `OK contr 12 coppie sopra soglia nei due temi`.

- [ ] **Step 7: Commit**

```bash
git add ui/Theme.Light.xaml ui/Theme.Dark.xaml ui/UI.xaml src/modules/App.Update.ps1 tests/Test-Ui.ps1
git commit -m "fix(ui): readable update button in dark theme, warning glyph above contrast floor"
```

---

## Task 3: Accessible names for the icon-only glyphs

The PIN and RESULT cells carry a private-use codepoint as their content, so a screen reader announces the codepoint instead of the meaning. After Task 1 the gear and close buttons are gone, so this is all that is left.

**Files:**
- Modify: `ui\UI.xaml` (the `ResultCell` and `PinCell` data templates, and the Settings tab header glyph)
- Test: `tests\Test-Ui.ps1` — new check next to the existing glyph check (10c)

- [ ] **Step 1: Write the failing test**

In `tests\Test-Ui.ps1`, add after the `OK glyph` block:

```powershell
# 10d) Ogni elemento che usa un font di icone dichiara la propria intenzione: un
# AutomationProperties.Name se il glifo PORTA informazione (uno screen reader leggerebbe
# altrimenti il codepoint), vuoto se e' decorativo e accanto c'e' gia' un testo che lo dice.
# NB: NON esiste AutomationProperties.AccessibilityView in WPF — e' di UWP, e usarla fa
# morire il caricamento dello XAML con "membro sconosciuto".
$iconTags = @([regex]::Matches($uiText, '<[^>]*FontFamily="Segoe Fluent Icons[^>]*>'))
if ($iconTags.Count -eq 0) { throw "nessun elemento con font di icone trovato: regex da rivedere" }
$unnamed = @($iconTags | Where-Object {
    $_.Value -notmatch 'AutomationProperties\.Name='
})
if ($unnamed.Count -gt 0) {
    throw "$($unnamed.Count) glifi senza nome accessibile ne' marca decorativa:`n$(($unnamed | ForEach-Object { $_.Value }) -join "`n")"
}
"OK a11y   $($iconTags.Count) elementi con font di icone, tutti nominati o marcati decorativi"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-Ui.ps1`

Expected: FAIL with `3 glifi senza nome accessibile ne' marca decorativa` (the result cell, the pin cell, and the Settings tab glyph).

- [ ] **Step 3: Name the status glyphs**

In `ui\UI.xaml`, in the `ResultCell` template, add a name to the glyph `TextBlock` and set it per state. The element becomes:

```xml
                <!-- Icone di stato dal set di sistema di Windows 11 (fallback a
                     Segoe MDL2 Assets su Win10): forme PIENE e distinte fra loro,
                     leggibili anche senza distinguere i colori. Niente FontWeight:
                     un icon font in Bold viene ingrassato per sintesi e sbava.
                     AutomationProperties.Name lo scrivono i DataTrigger insieme al glifo:
                     senza, uno screen reader leggerebbe il codepoint. -->
                <TextBlock x:Name="cellIcon" FontSize="16"
                           FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets"
                           AutomationProperties.Name="No result yet"
                           HorizontalAlignment="Center" VerticalAlignment="Center"
                           Visibility="Collapsed"/>
```

and each of the three state triggers gains one setter alongside the existing `Text` setter — for `ok`:

```xml
                    <Setter TargetName="cellIcon" Property="AutomationProperties.Name" Value="Succeeded"/>
```

for `error`:

```xml
                    <Setter TargetName="cellIcon" Property="AutomationProperties.Name" Value="Failed"/>
```

for `warning`:

```xml
                    <Setter TargetName="cellIcon" Property="AutomationProperties.Name" Value="Finished with a warning"/>
```

In the `PinCell` template, add to the `pinIcon` element:

```xml
                       AutomationProperties.Name="Pinned"
```

- [ ] **Step 4: Mark the tab glyph decorative**

The gear in the Settings tab header sits next to the word "Settings", so naming it too would make a screen reader say it twice. In `ui\UI.xaml`, in the Settings tab header:

```xml
                            <!-- Decorativo: la parola accanto e' gia' il nome accessibile del tab,
                                 quindi il glifo va tolto dall'albero di automazione invece di
                                 essere nominato una seconda volta. -->
                            <TextBlock Text="&#xE713;" FontSize="13" Margin="0,0,7,0"
                                       FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets"
                                       AutomationProperties.Name=""
                                       VerticalAlignment="Center"/>
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-Ui.ps1`

Expected: PASS with `OK a11y 3 elementi con font di icone, tutti nominati o marcati decorativi`.

- [ ] **Step 6: Commit**

```bash
git add ui/UI.xaml tests/Test-Ui.ps1
git commit -m "fix(a11y): accessible names on the status glyphs, gear marked decorative"
```

---

## Task 4: Close the winget concurrency hole

`Start-Search` deliberately does not raise the busy state — typing must stay responsive — but a search *is* a winget process. Meanwhile every other operation guards only on `$script:isBusy`. So: type three characters in Install, switch immediately to Installed, and `winget search` and `winget list` run at the same time. That is exactly the situation `DEVELOPMENT.md:220` documents as the cause of a `pin` command exiting 1.

The fix has one shared predicate and moves `Set-AppBusy $true` into `Start-WinGetQueue`, which is the single choke point every multi-package operation already passes through. That removes four scattered `Set-AppBusy $true` calls.

**Files:**
- Modify: `src\modules\App.Ui.ps1` (new `Test-WinGetBusy`)
- Modify: `src\modules\App.Jobs.ps1` (`Start-WinGetQueue` guards and takes the busy state)
- Modify: `src\modules\Tab.Updates.ps1` (`Load-Upgrades` guard, `Start-UpdateSelected` loses its `Set-AppBusy`)
- Modify: `src\modules\Tab.Install.ps1` (`Install-Rows` loses its `Set-AppBusy`)
- Modify: `src\modules\Tab.Installed.ps1` (`Load-Installed` guard, `Start-UninstallSelected` loses its `Set-AppBusy`)
- Modify: `src\modules\App.Pins.ps1` (`Set-PackagePin` loses its `Set-AppBusy`)
- Modify: `src\modules\App.Backup.ps1` (four guards)
- Modify: `src\modules\App.Bootstrap.ps1` (both timers stopped on close)
- Test: `tests\Test-Ui.ps1` — new section
- Modify: `DEVELOPMENT.md:220`

**Interfaces:**
- Consumes: `$script:isBusy` (`App.Ui.ps1`) and `$script:searchInFlight` (`Tab.Install.ps1`).
- Produces: `Test-WinGetBusy` → `[bool]`. True when any winget process is running, searches included. `Start-WinGetQueue` now raises the busy state itself and returns without starting anything if a winget process is already running; callers must **not** call `Set-AppBusy $true` before it.

- [ ] **Step 1: Write the failing test**

In `tests\Test-Ui.ps1`, add a new section after the `OK job` block of section 13:

```powershell
# 13b) Una ricerca in volo E' un processo winget, anche se non alza lo stato occupato (la
# digitazione deve restare fluida). Senza questo controllo, digitare in Install e passare
# subito a Installed lanciava due winget insieme — ed e' cosi' che un comando esce con
# exit 1. Il flag si forza a mano: far partire una ricerca vera renderebbe il test lento e
# dipendente dalla rete.
$script:searchInFlight = 1
try {
    if (-not (Test-WinGetBusy)) { throw "Test-WinGetBusy ignora le ricerche in volo" }

    $script:installedLoaded = $false
    Load-Installed
    if ($script:installedLoaded) { throw "Load-Installed e' partita con una ricerca in volo" }

    # La coda e' il punto di passaggio di update, install, uninstall e pin: se non si
    # difende lei, ognuno dei quattro deve ricordarselo.
    $wasBusy = $script:isBusy
    Start-WinGetQueue -Rows @([WgtRow]@{ Id = 'Test.Id'; Name = 'Test' }) -Verb 'Test' `
        -ArgsBuilder { param($r) '--version' }
    if ($script:isBusy -ne $wasBusy) { throw "Start-WinGetQueue ha preso lo stato occupato con una ricerca in volo" }
    if ($script:jobs.Count -ne 0) { throw "Start-WinGetQueue ha avviato un job con una ricerca in volo" }
}
finally {
    $script:searchInFlight = 0
    Stop-AllJobs
}
"OK busy   ricerca in volo: scansioni e coda winget si fermano"

# 13c) Entrambi i timer si fermano alla chiusura: uno che resta vivo tiene in piedi il
# processo dopo che la finestra e' sparita.
$startSrc = Get-FunctionSource 'Start-App'
foreach ($t in 'themeTimer', 'searchTimer') {
    if ($startSrc -notmatch "Add_Closed[\s\S]*$t") { throw "Add_Closed non ferma `$script:$t" }
}
"OK timers themeTimer e searchTimer fermati in Add_Closed"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-Ui.ps1`

Expected: FAIL with `Il termine 'Test-WinGetBusy' non è riconosciuto`.

- [ ] **Step 3: Add the shared predicate in `src\modules\App.Ui.ps1`**

Append to the busy-state section, after `Set-AppBusy`:

```powershell
# Sta girando un processo winget? Comprende le RICERCHE, che di proposito non alzano lo
# stato occupato — il typeahead deve restare fluido — ma sono comunque un processo winget.
# winget non e' affidabile in parallelo: e' con due processi insieme che un comando esce
# con exit 1. $script:searchInFlight vive in Tab.Install.ps1 e vale 0 finche' quel modulo
# non e' caricato; il confronto regge anche su $null.
function Test-WinGetBusy {
    return ($script:isBusy -or ($script:searchInFlight -gt 0))
}
```

- [ ] **Step 4: Make the queue the choke point in `src\modules\App.Jobs.ps1`**

In `Start-WinGetQueue`, insert the guard and the busy state before the row reset. The block that currently reads

```powershell
    # Azzera eventuali esiti precedenti sulle righe in coda
    foreach ($item in $Rows) { $item.Status = ''; $item.StatusDetail = '' }
```

becomes:

```powershell
    # UNICO punto di passaggio di update, install, uninstall e pin: lo stato occupato lo
    # prende lei, cosi' i chiamanti non possono dimenticarselo e il controllo contro un
    # winget gia' in corso (ricerche comprese) vive in un posto solo.
    if (Test-WinGetBusy) {
        Write-Log "Another winget operation is still running: try again in a moment."
        return
    }
    Set-AppBusy $true

    # Azzera eventuali esiti precedenti sulle righe in coda
    foreach ($item in $Rows) { $item.Status = ''; $item.StatusDetail = '' }
```

- [ ] **Step 5: Remove the four now-duplicated `Set-AppBusy $true` calls**

In `src\modules\Tab.Updates.ps1`, in `Start-UpdateSelected`, delete the `Set-AppBusy $true` line above `Start-WinGetQueue`. Same in `src\modules\Tab.Install.ps1` in `Install-Rows`, in `src\modules\Tab.Installed.ps1` in `Start-UninstallSelected`, and in `src\modules\App.Pins.ps1` in `Set-PackagePin`. Leave every `Set-AppBusy $false` exactly where it is: those still release the state.

In `App.Pins.ps1`, adjust the comment that explained the old order:

```powershell
    # Lo stato occupato lo prende Start-WinGetQueue. Non si sblocca nel suo OnDone:
    # Update-PinFlags lancia un altro winget e deve restare dentro lo stato occupato, quindi
    # lo sblocco lo fa lei alla fine.
```

- [ ] **Step 6: Guard the four paths that call winget without going through the queue**

In `src\modules\Tab.Updates.ps1`, `Load-Upgrades` currently has no guard at all — it is reached from the Check button (disabled while busy) and from `Add_ContentRendered`. Add as its first line:

```powershell
function Load-Upgrades {
    if (Test-WinGetBusy) { return }
    Set-AppBusy $true
```

In `src\modules\Tab.Installed.ps1`, `Load-Installed`:

```powershell
function Load-Installed {
    if (Test-WinGetBusy) { return }
    Set-AppBusy $true
```

In `src\modules\App.Backup.ps1`, replace `if ($script:isBusy) { return }` with `if (Test-WinGetBusy) { return }` in `Start-Export` and in `Start-Import`, and add the same line as the first statement of `Invoke-PackageExport` and `Invoke-PackageImport` — the file dialog is modal for the user but not for a search that is already in flight, so the check has to happen again after it closes:

```powershell
function Invoke-PackageExport([string]$file) {
    # Di nuovo: fra la scelta del file e qui puo' essere rientrata una ricerca.
    if (Test-WinGetBusy) { return }
    Set-AppBusy $true
```

```powershell
function Invoke-PackageImport([string]$file, [int]$count) {
    if (Test-WinGetBusy) { return }
    Set-AppBusy $true
```

Leave `Start-Search`'s own `if ($script:isBusy) { return }` alone: a search on top of another search is the intended behaviour, handled by `searchInFlight` and the stale-result check.

Leave `Start-UpdateCheck`'s `if ($script:isBusy) { return }` alone too: it calls GitHub, not winget.

- [ ] **Step 7: Stop both timers on close in `src\modules\App.Bootstrap.ps1`**

Replace the `Add_Closed` body:

```powershell
    # Alla chiusura: ferma i timer e chiudi i job pendenti, cosi' il processo termina
    # davvero (niente thread in background lasciati vivi).
    $script:window.Add_Closed({
        Stop-AllJobs
        foreach ($t in $script:themeTimer, $script:searchTimer) {
            if ($t) { try { $t.Stop() } catch { } }
        }
    })
```

- [ ] **Step 8: Run the tests to verify they pass**

Run: `powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-Ui.ps1`

Expected: PASS with `OK busy` and `OK timers`. Section 17 must still print `OK list`, and section 18 `OK pin` — those two exercise the paths whose `Set-AppBusy` just moved, so if the state handling broke they will hang until their timeout and then fail with `dopo il pin la riga non risulta pinnata`.

- [ ] **Step 9: Verify by hand, because this is a timing bug**

```bash
powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\src\main.ps1
```

Go to Install, type `vlc`, and while the spinner is still turning switch to Installed. The inventory must **not** start loading mid-search; click Refresh once the search has landed and it loads normally. Then, in Updates, tick a package and press Update: the queue must start (proving Step 4 did not leave everything permanently blocked).

- [ ] **Step 10: Update `DEVELOPMENT.md:220`**

Extend the existing bullet:

```markdown
- **Never two winget processes at once.** Reading the pins used to run *after* the busy state was released, so a click on Update in that window ran a second winget and one of the two failed with exit 1. The scans read the pins inside the same job, and after a pin/unpin the busy state is released by the pin re-read, which is the last step. Busy state is global: each tab registers a handler with `Set-AppBusy`. A **search** is the exception that nearly broke the rule: it must not raise the busy state or typing would stall, so it counts itself in `$script:searchInFlight` and everything else asks `Test-WinGetBusy`, which covers both. `Start-WinGetQueue` is the single choke point — it takes the busy state itself, so no caller can forget to.
```

- [ ] **Step 11: Commit**

```bash
git add src/modules/App.Ui.ps1 src/modules/App.Jobs.ps1 src/modules/Tab.Updates.ps1 src/modules/Tab.Install.ps1 src/modules/Tab.Installed.ps1 src/modules/App.Pins.ps1 src/modules/App.Backup.ps1 src/modules/App.Bootstrap.ps1 tests/Test-Ui.ps1 DEVELOPMENT.md
git commit -m "fix(winget): a search in flight blocks scans and queues, one busy choke point"
```

---

## Task 5: Persist the three toggles

`Unknown`, `MS Store` and `Scope` reset at every launch while the theme persists. The registry key already exists; what is missing is a place to put the read and write so `App.Theme.ps1` stops owning it alone. Per the decision above the three controls **stay where they are** — `Scope` in particular must remain next to the `Install` button it modifies.

Toggling `Unknown` also rescans, because a checkbox that changes what a list contains should change the list.

**Files:**
- Create: `src\modules\App.Prefs.ps1`
- Modify: `src\main.ps1` (`$moduleNames`)
- Modify: `src\modules\App.Theme.ps1` (use the new helpers)
- Modify: `src\modules\Tab.Updates.ps1` (`Unknown`), `src\modules\Tab.Install.ps1` (`MS Store`, `Scope`)
- Modify: `DEVELOPMENT.md:18-28` (layout listing)
- Test: `tests\Test-Ui.ps1` — new section

**Interfaces:**
- Consumes: nothing.
- Produces:
  - `Get-Pref([string]$Name, $Default)` → the stored value, or `$Default` when absent or unreadable.
  - `Set-Pref([string]$Name, $Value)` → best effort, silent on failure.
  - `$PrefsKey` = `'HKCU:\Software\WinGetStudio'`.
  - Value names in use: `Theme` (string, pre-existing — do not rename or users lose their theme), `IncludeUnknown`, `IncludeStore`, `InstallScope`. Booleans are stored as `0`/`1` integers.

- [ ] **Step 1: Write the failing test**

In `tests\Test-Ui.ps1`, add a new section just before section 13:

```powershell
# 12b) Le preferenze: scritte e rilette dal registro, e un valore assente torna il default
# invece di far esplodere l'avvio. Si scrive un nome di prova e si cancella subito: la
# chiave e' la stessa dell'app, quindi non si toccano i valori veri.
$probe = "TestProbe$PID"
try {
    if ($null -ne (Get-Pref $probe $null)) { throw "il nome di prova esisteva gia': $probe" }
    if ((Get-Pref $probe 'fallback') -ne 'fallback') { throw "un valore assente non torna il default" }
    Set-Pref $probe 42
    if ((Get-Pref $probe 0) -ne 42) { throw "Set-Pref/Get-Pref non fanno il giro: $(Get-Pref $probe 0)" }
}
finally {
    Remove-ItemProperty -Path $PrefsKey -Name $probe -ErrorAction SilentlyContinue
}
# I tre toggle che si perdevano a ogni avvio ora si rileggono. Controllo statico: farli
# girare davvero vorrebbe dire sporcare le preferenze dell'utente che esegue i test.
foreach ($pair in @(@('Initialize-UpdatesTab', 'IncludeUnknown'),
                    @('Initialize-InstallTab', 'IncludeStore'),
                    @('Initialize-InstallTab', 'InstallScope'),
                    @('Initialize-Theme',      'Theme'))) {
    $src = Get-FunctionSource $pair[0]
    if ($src -notmatch "Get-Pref\s+'$($pair[1])'") { throw "$($pair[0]) non rilegge la preferenza $($pair[1])" }
    if ($src -notmatch "Set-Pref\s+'$($pair[1])'") { throw "$($pair[0]) non salva la preferenza $($pair[1])" }
}
"OK prefs  giro completo su registro e 4 preferenze lette e salvate"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-Ui.ps1`

Expected: FAIL with `Il termine 'Get-Pref' non è riconosciuto`.

- [ ] **Step 3: Create `src\modules\App.Prefs.ps1`**

```powershell
<#
    App.Prefs.ps1 — preferenze dell'utente in HKCU.

    Un posto solo per leggere e scrivere le scelte che devono sopravvivere alla chiusura.
    Prima la chiave viveva dentro App.Theme.ps1 e solo il tema persisteva, mentre le altre
    tre scelte dell'utente (Unknown, MS Store, Scope) si perdevano a ogni avvio.

    Il registro NON e' un requisito: se non si riesce a leggere si usa il default, se non si
    riesce a scrivere la scelta vale per questa sessione. Una preferenza non persistita non
    e' un motivo per rifiutare la scelta, ne' per fermare l'avvio.

    I booleani si salvano come 0/1: Set-ItemProperty su un [bool] scrive una stringa
    "True"/"False", che poi va riconvertita a mano in ogni punto di lettura.

    Caricato da src\main.ps1: dot-source come .ps1, concatenato nell'exe al posto
    del marcatore ###MODULES###.
#>

$PrefsKey = 'HKCU:\Software\WinGetStudio'

# Valore salvato, oppure $Default se non c'e' o non si legge.
function Get-Pref([string]$Name, $Default) {
    try { return (Get-ItemProperty -Path $PrefsKey -Name $Name -ErrorAction Stop).$Name }
    catch { return $Default }
}

# Salva, best effort.
function Set-Pref([string]$Name, $Value) {
    try {
        if (-not (Test-Path $PrefsKey)) { New-Item -Path $PrefsKey -Force | Out-Null }
        Set-ItemProperty -Path $PrefsKey -Name $Name -Value $Value
    }
    catch { }
}
```

In `src\main.ps1`, add the module to `$moduleNames` right after `'App.Ui.ps1'` — the order only matters for file-level code, and this file has one variable assignment:

```powershell
    'App.Ui.ps1'
    'App.Prefs.ps1'
```

- [ ] **Step 4: Move the theme's registry access onto the helpers**

In `src\modules\App.Theme.ps1`, delete the `$themeKey` line at the top and replace the read in `Initialize-Theme`:

```powershell
function Initialize-Theme {
    # Auto | Light | Dark. Un valore fuori dai tre (registro modificato a mano) torna ad Auto.
    $saved = [string](Get-Pref 'Theme' 'Auto')
    $script:themeMode = if ($saved -in @('Auto', 'Light', 'Dark')) { $saved } else { 'Auto' }
```

and the write inside the `SelectionChanged` handler:

```powershell
    $CmbTheme.Add_SelectionChanged({
        $chosen = [string]$CmbTheme.SelectedItem
        if (-not $chosen -or $chosen -eq $script:themeMode) { return }
        $script:themeMode = $chosen
        Set-Pref 'Theme' $script:themeMode
        Set-Theme
    })
```

The value name stays `Theme`: renaming it would reset every existing user's choice.

- [ ] **Step 5: Persist `Unknown` and rescan on toggle**

In `src\modules\Tab.Updates.ps1`, in `Initialize-UpdatesTab`, after the `$BtnRefresh.Add_Click` line:

```powershell
    # La spunta comanda --include-unknown. Si rilegge dalle preferenze e si risalva a ogni
    # cambio; e ricarica subito, perche' una spunta che cambia COSA c'e' nell'elenco senza
    # cambiare l'elenco costringe a premere Check per capire cosa ha fatto.
    $ChkUnknown.IsChecked = [bool][int](Get-Pref 'IncludeUnknown' 0)
    $ChkUnknown.Add_Click({
        Set-Pref 'IncludeUnknown' ([int][bool]$ChkUnknown.IsChecked)
        Load-Upgrades
    })
```

`Add_Click` and not `Add_Checked`/`Add_Unchecked`: one handler for both directions, and it fires after `IsChecked` has flipped. Setting `IsChecked` here happens before the handler is attached, so it does not trigger a scan at startup.

- [ ] **Step 6: Persist `MS Store` and `Scope`**

In `src\modules\Tab.Install.ps1`, in `Initialize-InstallTab`, replace the `Update-ScopeButton` call with the restore of both preferences:

```powershell
    # Le due scelte della scheda si rileggono dalle preferenze: prima si perdevano a ogni
    # avvio. Lo Scope resta accanto al pulsante Install che lo usa, non in Settings.
    $ChkStore.IsChecked = [bool][int](Get-Pref 'IncludeStore' 0)
    $saved = [string](Get-Pref 'InstallScope' 'Auto')
    if ($saved -in @('Auto', 'User', 'Machine')) { $script:installScope = $saved }
    Update-ScopeButton
```

Then add the save to the two handlers:

```powershell
    $ChkStore.Add_Click({ Set-Pref 'IncludeStore' ([int][bool]$ChkStore.IsChecked) })
```

and in the existing `$BtnScope.Add_Click` handler, after `Update-ScopeButton`:

```powershell
    $BtnScope.Add_Click({
        $script:installScope = switch ($script:installScope) {
            'Auto'    { 'User' }
            'User'    { 'Machine' }
            default   { 'Auto' }
        }
        Update-ScopeButton
        Set-Pref 'InstallScope' $script:installScope
    })
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-Ui.ps1`

Expected: PASS with `OK prefs` and `OK mods 13 moduli elencati`.

- [ ] **Step 8: Verify persistence by hand**

```bash
powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\src\main.ps1
```

Tick `Unknown` (the list must rescan immediately), tick `MS Store`, click `Scope` until it says `Machine`, close the app, reopen it: all three come back as you left them. Then check the theme still survives a restart — that is the value name you must not have renamed.

- [ ] **Step 9: Update the layout listing in `DEVELOPMENT.md`**

Add the new module after `App.Ui.ps1`:

```
       App.Prefs.ps1            user preferences under HKCU: Get-Pref / Set-Pref
```

- [ ] **Step 10: Commit**

```bash
git add src/modules/App.Prefs.ps1 src/main.ps1 src/modules/App.Theme.ps1 src/modules/Tab.Updates.ps1 src/modules/Tab.Install.ps1 tests/Test-Ui.ps1 DEVELOPMENT.md
git commit -m "feat(settings): persist the unknown, store and scope choices across launches"
```

---

## Task 6: Make the startup update check optional

Every launch calls `api.github.com` with no opt-out and no notice. The checkbox goes on by default, so nothing changes for anyone who does not touch it.

**Files:**
- Modify: `ui\UI.xaml` (new checkbox in the Settings tab, UPDATES section)
- Modify: `src\modules\App.Bootstrap.ps1` (control list)
- Modify: `src\modules\App.Update.ps1` (`Start-UpdateCheck`, `Initialize-Update`)
- Test: `tests\Test-Ui.ps1` — extend the update section
- Modify: `README.md` (Settings section)

**Interfaces:**
- Consumes: `Get-Pref` / `Set-Pref` from Task 5.
- Produces: control `$ChkAutoCheck`; preference `CheckAtStartup` (`0`/`1`, default `1`).

- [ ] **Step 1: Write the failing test**

In `tests\Test-Ui.ps1`, inside section 20 (the auto-update block), add right before the `Stop-AllJobs` at the end of the `else` branch:

```powershell
    # Il controllo all'avvio si puo' spegnere: con la spunta giu' non deve partire NESSUN
    # job, cioe' nessuna chiamata a GitHub. Il controllo manuale resta sempre disponibile.
    Stop-AllJobs
    $ChkAutoCheck.IsChecked = $false
    Start-UpdateCheck
    if ($script:jobs.Count -ne 0) { throw "con la spunta giu' il controllo automatico e' partito comunque" }
    $ChkAutoCheck.IsChecked = $true
    Start-UpdateCheck
    if ($script:jobs.Count -eq 0) { throw "con la spunta su il controllo automatico non parte" }
    "OK autochk il controllo all'avvio si spegne dalla spunta"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-Ui.ps1`

Expected: FAIL with `Impossibile chiamare un metodo su un'espressione con valore null` on `$ChkAutoCheck`.

- [ ] **Step 3: Add the checkbox to `ui\UI.xaml`**

In the Settings tab, UPDATES section, between the version row and the button row:

```xml
                            <!-- Il controllo all'avvio e' una chiamata anonima all'API di GitHub.
                                 Acceso di default (e' il comportamento di sempre), ma si spegne:
                                 un programma che va in rete da solo deve almeno dirlo e lasciare
                                 la scelta. Il pulsante Check qui sotto resta sempre attivo. -->
                            <CheckBox x:Name="ChkAutoCheck" IsChecked="True"
                                      Margin="120,0,0,10" HorizontalAlignment="Left"
                                      Content="Check for updates at startup"
                                      Style="{StaticResource ThemedCheckBox}"
                                      ToolTip="One anonymous call to the GitHub API when the app starts. Turn it off to go online only when you press Check for updates"
                                      Foreground="{DynamicResource FgBrush}"/>
```

Add `'ChkAutoCheck'` to the control list in `src\modules\App.Bootstrap.ps1`, next to the other update controls:

```powershell
        'CmbTheme', 'TxtThemeHint', 'TxtVersion', 'BtnCheckUpdate', 'BtnUpdateApp',
        'UpdateSpinner', 'TxtUpdateStatus', 'ChkAutoCheck',
```

- [ ] **Step 4: Honour the preference in `src\modules\App.Update.ps1`**

In `Start-UpdateCheck`, add the check after the exe test and before the busy test:

```powershell
function Start-UpdateCheck([switch]$Manual) {
    if (-not (Get-RunningExePath)) {
        if ($Manual) { $TxtUpdateStatus.Text = 'Updates apply to the compiled exe only; from source use git.' }
        return
    }
    # Il controllo AUTOMATICO si puo' spegnere; quello chiesto dal pulsante no — chi lo
    # premette lo sta chiedendo adesso.
    if (-not $Manual -and -not $ChkAutoCheck.IsChecked) { return }
    if ($script:isBusy) { return }
```

In `Initialize-Update`, restore and save the preference:

```powershell
function Initialize-Update {
    Clear-OldExe                     # pulisce il residuo dell'aggiornamento precedente
    # La versione sta qui, non nel titolo della finestra.
    $TxtVersion.Text = "v$AppVersion"
    $ChkAutoCheck.IsChecked = [bool][int](Get-Pref 'CheckAtStartup' 1)
    $ChkAutoCheck.Add_Click({ Set-Pref 'CheckAtStartup' ([int][bool]$ChkAutoCheck.IsChecked) })
    $BtnUpdateApp.Add_Click({ Start-SelfUpdate })
    $BtnCheckUpdate.Add_Click({ Start-UpdateCheck -Manual })
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-Ui.ps1`

Expected: PASS with `OK autochk`. If GitHub is unreachable the whole block prints `SKIP rel` instead — in that case verify on a connected machine before committing.

- [ ] **Step 6: Update `README.md`**

In the `### Settings` section, add after the sentence describing the tab: "**Check for updates at startup** is on by default and can be turned off; the **Check for updates** button always works regardless."

- [ ] **Step 7: Commit**

```bash
git add ui/UI.xaml src/modules/App.Bootstrap.ps1 src/modules/App.Update.ps1 tests/Test-Ui.ps1 README.md
git commit -m "feat(settings): the startup update check can be turned off"
```

---

## Task 7: Settings layout on a grid, and a real About section

Labels currently use `Width="120"` and the rows below compensate with `Margin="120,0,0,..."`. If a label grows, the alignment breaks silently. A two-column `Grid` removes every one of those 120s. While in there, the section titles get the weight of section titles rather than of the labels they introduce, and ABOUT gets links.

**Known limitation to accept deliberately:** the app runs elevated, so a link opened with `Start-Process` inherits that elevation and the browser starts as administrator. Avoiding it means launching through the interactive user's shell, which is a lot of machinery for three links. The comment in the code says so; if it ever matters, the fix is to drop the links and show the URLs as selectable text.

**Files:**
- Modify: `ui\UI.xaml` (Settings tab body, `SettingsHeader` style)
- Modify: `src\modules\App.Bootstrap.ps1` (`Start-App`: one hyperlink handler)
- Test: `tests\Test-Ui.ps1` — extend the settings section from Task 1

- [ ] **Step 1: Write the failing test**

In `tests\Test-Ui.ps1`, append to the settings block added in Task 1:

```powershell
# I 120 magici erano un allineamento a mano: se un'etichetta cresce, la riga sotto non la
# segue. Le impostazioni stanno su una Grid a due colonne.
if ($uiTextEarly -match 'Margin="120,') { throw "il corpo delle impostazioni usa ancora i margini magici da 120" }
# I link della scheda Settings aprono il browser: WPF non lo fa da solo, serve un handler.
if ($uiTextEarly -notmatch 'NavigateUri="https://github\.com/') { throw "ABOUT non ha link a github.com" }
# ABOUT deve dire COSA fa il programma e DOVE si segnala un problema, non una riga generica.
if ($uiTextEarly -notmatch 'WinGetStudio/issues') { throw "ABOUT non dice dove segnalare un bug" }
foreach ($w in 'Updates', 'Install', 'Installed', 'Pin', 'Export / Import') {
    if ($uiTextEarly -notmatch "<Bold>$([regex]::Escape($w))</Bold>") { throw "ABOUT non elenca la funzione $w" }
}
if ($uiTextEarly -notmatch 'Claude Code') { throw "manca la nota sullo strumento con cui e' stato scritto" }
if ((Get-FunctionSource 'Start-App') -notmatch 'RequestNavigateEvent') {
    throw "nessun handler per i link: cliccarli non aprirebbe nulla"
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-Ui.ps1`

Expected: FAIL with `il corpo delle impostazioni usa ancora i margini magici da 120`.

- [ ] **Step 3: Restyle the section titles**

In `ui\UI.xaml`, in `Window.Resources`:

```xml
        <!-- Titolo di sezione nella scheda Settings: piu' piccolo e in tono minore delle
             etichette che introduce. Con lo stesso peso del testo sotto non separava niente. -->
        <Style x:Key="SettingsHeader" TargetType="TextBlock">
            <Setter Property="FontSize" Value="11"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Foreground" Value="{DynamicResource SubtleFgBrush}"/>
            <Setter Property="Margin" Value="0,0,0,8"/>
        </Style>
```

- [ ] **Step 4: Put the Settings body on a two-column grid**

Replace the whole `<StackPanel>` inside the Settings tab's `ScrollViewer` with:

```xml
                        <!-- Due colonne: etichette a larghezza automatica, controlli elastici.
                             Prima le etichette avevano Width="120" e le righe sotto un
                             Margin="120,0,0,0" per fingere l'allineamento: un'etichetta piu'
                             lunga rompeva tutto in silenzio. -->
                        <Grid>
                            <Grid.ColumnDefinitions>
                                <ColumnDefinition Width="Auto" MinWidth="120"/>
                                <ColumnDefinition Width="*"/>
                            </Grid.ColumnDefinitions>
                            <Grid.RowDefinitions>
                                <RowDefinition Height="Auto"/>   <!-- 0 APPEARANCE -->
                                <RowDefinition Height="Auto"/>   <!-- 1 tema -->
                                <RowDefinition Height="Auto"/>   <!-- 2 UPDATES -->
                                <RowDefinition Height="Auto"/>   <!-- 3 versione -->
                                <RowDefinition Height="Auto"/>   <!-- 4 spunta avvio -->
                                <RowDefinition Height="Auto"/>   <!-- 5 pulsanti -->
                                <RowDefinition Height="Auto"/>   <!-- 6 ABOUT -->
                                <RowDefinition Height="Auto"/>   <!-- 7 descrizione e link -->
                            </Grid.RowDefinitions>

                            <TextBlock Grid.Row="0" Grid.ColumnSpan="2" Text="APPEARANCE"
                                       Style="{StaticResource SettingsHeader}"/>
                            <TextBlock Grid.Row="1" Grid.Column="0" Text="Theme" Margin="0,0,12,18"
                                       VerticalAlignment="Center" Foreground="{DynamicResource FgBrush}"/>
                            <StackPanel Grid.Row="1" Grid.Column="1" Orientation="Horizontal" Margin="0,0,0,18">
                                <!-- Le voci le riempie App.Theme.ps1: sono gli stessi valori
                                     che finiscono nel registro (Light | Dark | Auto). -->
                                <ComboBox x:Name="CmbTheme" Width="180"/>
                                <TextBlock x:Name="TxtThemeHint" VerticalAlignment="Center" Margin="12,0,0,0"
                                           Foreground="{DynamicResource SubtleFgBrush}"/>
                            </StackPanel>

                            <TextBlock Grid.Row="2" Grid.ColumnSpan="2" Text="UPDATES"
                                       Style="{StaticResource SettingsHeader}"/>
                            <TextBlock Grid.Row="3" Grid.Column="0" Text="Installed version" Margin="0,0,12,8"
                                       VerticalAlignment="Center" Foreground="{DynamicResource FgBrush}"/>
                            <TextBlock Grid.Row="3" Grid.Column="1" x:Name="TxtVersion" Margin="0,0,0,8"
                                       VerticalAlignment="Center" FontWeight="SemiBold"
                                       Foreground="{DynamicResource FgBrush}"/>
                            <!-- Il controllo all'avvio e' una chiamata anonima all'API di GitHub.
                                 Acceso di default (e' il comportamento di sempre), ma si spegne. -->
                            <CheckBox Grid.Row="4" Grid.Column="1" x:Name="ChkAutoCheck" IsChecked="True"
                                      Margin="0,0,0,10" HorizontalAlignment="Left"
                                      Content="Check for updates at startup"
                                      Style="{StaticResource ThemedCheckBox}"
                                      ToolTip="One anonymous call to the GitHub API when the app starts. Turn it off to go online only when you press Check for updates"
                                      Foreground="{DynamicResource FgBrush}"/>
                            <StackPanel Grid.Row="5" Grid.Column="1" Orientation="Horizontal" Margin="0,0,0,18">
                                <Button x:Name="BtnCheckUpdate" Content="Check for updates" Width="140" Height="26"/>
                                <!-- Compare solo quando una release e' piu' recente di questa.
                                     Foreground dal tema e NON "White": l'accento scuro e'
                                     azzurro chiaro (#4CC2FF) e il bianco sopra faceva 2.01:1. -->
                                <Button x:Name="BtnUpdateApp" Height="26" Padding="12,0" Margin="8,0,0,0"
                                        Visibility="Collapsed"
                                        Background="{DynamicResource AccentBrush}"
                                        Foreground="{DynamicResource AccentFgBrush}"/>
                                <Control x:Name="UpdateSpinner" Width="20" Height="20" Style="{StaticResource Spinner}"
                                         Margin="10,0,0,0" Visibility="Collapsed"/>
                                <TextBlock x:Name="TxtUpdateStatus" VerticalAlignment="Center" Margin="12,0,0,0"
                                           Foreground="{DynamicResource SubtleFgBrush}"/>
                            </StackPanel>

                            <TextBlock Grid.Row="6" Grid.ColumnSpan="2" Text="ABOUT"
                                       Style="{StaticResource SettingsHeader}"/>
                            <!-- Descrizione vera: le cinque funzioni per nome e dove segnalare un
                                 problema. Prima era una riga che non diceva quasi niente, e non
                                 c'era modo di capire dove finiscono le segnalazioni.
                                 La nota finale su Claude Code e' volontaria: l'articolo 50
                                 dell'AI Act riguarda i sistemi AI e i contenuti generati, non gli
                                 strumenti con cui si scrive il codice, e questo programma non
                                 contiene nessun sistema AI. Sta qui perche' e' vero. -->
                            <TextBlock Grid.Row="7" Grid.ColumnSpan="2" TextWrapping="Wrap"
                                       Foreground="{DynamicResource SubtleFgBrush}">
                                WinGet Studio is a desktop front end for <Bold>winget</Bold>, the Windows package manager.<LineBreak/>
                                <LineBreak/>
                                <Bold>Updates</Bold> &#8212; list what has a newer version and upgrade the packages you tick, one at a time, with a per-row result. A running queue can be cancelled: the package in progress finishes, the rest are left alone.<LineBreak/>
                                <Bold>Install</Bold> &#8212; search the winget catalogue as you type, optionally the Microsoft Store, and pick the install scope.<LineBreak/>
                                <Bold>Installed</Bold> &#8212; the inventory of the machine, with a local filter, and uninstall behind a confirmation.<LineBreak/>
                                <Bold>Pin</Bold> &#8212; block a package from being upgraded, from either list, until you remove the pin.<LineBreak/>
                                <Bold>Export / Import</Bold> &#8212; save the package list to a .json file and rebuild a machine from it.<LineBreak/>
                                <LineBreak/>
                                It runs elevated, because installing and removing software requires it. No telemetry.<LineBreak/>
                                <LineBreak/>
                                Found a bug, or have an idea?
                                <!-- I link li apre l'handler in Start-App. -->
                                <Hyperlink NavigateUri="https://github.com/FedeB2160/WinGetStudio/issues"
                                           Foreground="{DynamicResource AccentBrush}">Open an issue on GitHub</Hyperlink>.<LineBreak/>
                                <Hyperlink NavigateUri="https://github.com/FedeB2160/WinGetStudio"
                                           Foreground="{DynamicResource AccentBrush}">Source code</Hyperlink> &#183;
                                <Hyperlink NavigateUri="https://github.com/FedeB2160/WinGetStudio/releases"
                                           Foreground="{DynamicResource AccentBrush}">Release notes</Hyperlink> &#183;
                                <Hyperlink NavigateUri="https://github.com/FedeB2160/WinGetStudio/blob/main/LICENSE"
                                           Foreground="{DynamicResource AccentBrush}">MIT licence</Hyperlink><LineBreak/>
                                <LineBreak/>
                                <Italic>Built with the help of Claude Code (Anthropic).</Italic>
                            </TextBlock>
                        </Grid>
```

- [ ] **Step 5: Hook the links once, in `src\modules\App.Bootstrap.ps1`**

In `Start-App`, after the icon block and before the `Initialize-*` calls:

```powershell
    # I link della scheda Settings: WPF non apre il browser da solo. Un solo handler sulla
    # finestra invece di uno per link, cosi' un link nuovo non richiede codice nuovo.
    # NB: l'app gira elevata, quindi il browser eredita l'elevazione. Aprirlo come utente
    # interattivo richiederebbe una ShellExecute impersonata: se diventa un problema, i
    # link diventano testo selezionabile.
    $script:window.AddHandler(
        [System.Windows.Documents.Hyperlink]::RequestNavigateEvent,
        [System.Windows.Navigation.RequestNavigateEventHandler]{
            param($s, $e)
            try { Start-Process $e.Uri.AbsoluteUri } catch { Write-Log "Could not open $($e.Uri): $($_.Exception.Message)" }
            $e.Handled = $true
        })
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-Ui.ps1`

Expected: PASS. The theme dropdown and version assertions from earlier sections must still pass — they read properties, not layout, so the reparenting does not affect them.

- [ ] **Step 7: Look at it in both themes**

```bash
powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\src\main.ps1
```

Open Settings: the two columns line up, the section titles read as titles rather than as labels, and the three links are visible and clickable in Light and Dark. Shrink the window until the `ScrollViewer` kicks in and check nothing is clipped.

- [ ] **Step 8: Commit**

```bash
git add ui/UI.xaml src/modules/App.Bootstrap.ps1 tests/Test-Ui.ps1
git commit -m "refactor(settings): two-column grid, subdued section titles, links in about"
```

---

## Task 8: Indeterminate progress during scans

The bar sits at zero for the whole of a scan whose length nobody knows, with only a 20px spinner moving. `IsIndeterminate` is what WPF has for exactly this.

**Files:**
- Modify: `src\modules\Tab.Updates.ps1`, `src\modules\Tab.Installed.ps1`, `src\modules\App.Backup.ps1`, `src\modules\App.Jobs.ps1`
- Test: `tests\Test-Ui.ps1` — one assertion inside the existing Installed integration block

- [ ] **Step 1: Write the failing test**

In `tests\Test-Ui.ps1`, in section 17, immediately after the `Wait-For` that waits for the inventory to load:

```powershell
    # A scansione finita la barra torna determinata: se restasse indeterminata continuerebbe
    # a scorrere per sempre, dicendo che qualcosa sta girando quando niente gira.
    if ($Progress.IsIndeterminate) { throw "a caricamento finito la barra e' ancora indeterminata" }
```

and add a static check next to it, since the indeterminate state itself only exists mid-scan:

```powershell
    foreach ($fn in 'Load-Upgrades', 'Load-Installed') {
        if ((Get-FunctionSource $fn) -notmatch 'IsIndeterminate\s*=\s*\$true') {
            throw "$fn non mette la barra in indeterminato: durante la scansione resta ferma a zero"
        }
    }
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-Ui.ps1`

Expected: FAIL with `Load-Upgrades non mette la barra in indeterminato`. If winget is missing the section prints `SKIP list` and proves nothing — run it on a machine with winget.

- [ ] **Step 3: Set the state around each scan**

In `src\modules\Tab.Updates.ps1`, in `Load-Upgrades`, replace the two progress lines:

```powershell
    # Barra indeterminata: la scansione non ha un avanzamento da mostrare, e una barra ferma
    # a zero sembra un'operazione bloccata. I valori tornano alla coda di aggiornamento.
    $Progress.IsIndeterminate = $true
    $Progress.Value   = 0
    $Progress.Maximum = 100
```

and in the `OnDone`, as its first line:

```powershell
            $Progress.IsIndeterminate = $false
```

In `src\modules\Tab.Installed.ps1`, in `Load-Installed`, after the spinner line:

```powershell
    $Progress.IsIndeterminate = $true
```

and in its `OnDone`, next to the spinner being collapsed:

```powershell
            $Progress.IsIndeterminate = $false
```

Do the same in `src\modules\App.Backup.ps1` for `Invoke-PackageExport` and `Invoke-PackageImport`: `$true` next to `$InstalledSpinner.Visibility = ...Visible`, `$false` next to `...Collapsed`.

In `src\modules\App.Jobs.ps1`, in `Start-WinGetQueue`, make the determinate state explicit — the queue does know how many packages it has:

```powershell
    $Progress.IsIndeterminate = $false
    $Progress.Value   = 0
    $Progress.Maximum = $Rows.Count
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-Ui.ps1`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add src/modules/Tab.Updates.ps1 src/modules/Tab.Installed.ps1 src/modules/App.Backup.ps1 src/modules/App.Jobs.ps1 tests/Test-Ui.ps1
git commit -m "feat(ui): indeterminate progress while scanning, determinate for queues"
```

---

## Task 9: Make the log resizable — WITHDRAWN

**Implemented and reverted on the user's call.** The GridSplitter worked, but making both rows elastic left an empty band between the tab frame and the progress bar, and the log is a service panel that is fine where it is.  now asserts the opposite: the log row has a fixed height and the tab row is the only elastic one, so this does not get re-attempted by accident.

The original task, for the record:

140 fixed pixels, 23% of a 620px window, with no way to reclaim them. A `GridSplitter` is a native control and needs no logic.

**Files:**
- Modify: `ui\UI.xaml` (main grid rows)
- Modify: `src\modules\App.Bootstrap.ps1` (control list)
- Test: `tests\Test-Ui.ps1` — extend the shared-controls section

- [ ] **Step 1: Write the failing test**

In `tests\Test-Ui.ps1`, after the existing loop that proves `TxtLog` and `Progress` live outside the `TabControl`:

```powershell
# Il log era alto 140px fissi e non si poteva restringere. Ora c'e' una maniglia, e la riga
# ha un minimo: senza MinHeight il trascinamento puo' schiacciarla a zero e il log
# sparirebbe senza che si capisca come farlo tornare.
if ($null -eq $LogSplitter) { throw "manca la maniglia di ridimensionamento del log" }
$logRow = $window.Content.RowDefinitions[[System.Windows.Controls.Grid]::GetRow($TxtLog)]
if ($logRow.MinHeight -le 0) { throw "la riga del log non ha un'altezza minima" }
"OK split  log ridimensionabile, minimo $([int]$logRow.MinHeight)px"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-Ui.ps1`

Expected: FAIL with `manca la maniglia di ridimensionamento del log`.

- [ ] **Step 3: Add the splitter row**

In `ui\UI.xaml`, replace the main grid's `RowDefinitions` and the two rows below the progress bar. The definitions become:

```xml
        <Grid.RowDefinitions>
            <RowDefinition Height="*" MinHeight="200"/>   <!-- 0 schede -->
            <RowDefinition Height="Auto"/>                <!-- 1 progress -->
            <RowDefinition Height="Auto"/>                <!-- 2 maniglia -->
            <RowDefinition Height="Auto"/>                <!-- 3 log label -->
            <RowDefinition Height="140" MinHeight="60"/>  <!-- 4 log -->
        </Grid.RowDefinitions>
```

Insert the splitter, and bump the two rows after it:

```xml
        <!-- Maniglia fra le schede e il log: il log era alto 140px fissi, cioe' quasi un
             quarto della finestra, e chi guarda l'elenco non lo puo' recuperare. Un
             GridSplitter e' nativo e non richiede codice.
             ResizeBehavior PreviousAndNext: trascina la riga sopra e quella sotto, non le
             altre. Lo sfondo e' il colore dei bordi: a schermo e' un separatore, che si
             scopre trascinabile passandoci sopra (il cursore diventa SizeNS). -->
        <GridSplitter x:Name="LogSplitter" Grid.Row="2" Height="4"
                      HorizontalAlignment="Stretch" VerticalAlignment="Center"
                      ResizeDirection="Rows" ResizeBehavior="PreviousAndNext"
                      Background="{DynamicResource BorderBrush2}"
                      ShowsPreview="True"/>

        <TextBlock Grid.Row="3" Text="Log:" Margin="0,4,0,2" FontWeight="Bold"
                   Foreground="{DynamicResource FgBrush}"/>

        <!-- Log (condiviso da tutte le schede) -->
        <TextBox x:Name="TxtLog" Grid.Row="4"
```

Add `'LogSplitter'` to the control list in `src\modules\App.Bootstrap.ps1` — the test reaches it through the script scope:

```powershell
        'BtnExport', 'BtnImport', 'LogSplitter',
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-Ui.ps1`

Expected: PASS with `OK split log ridimensionabile, minimo 60px`.

- [ ] **Step 5: Drag it**

```bash
powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\src\main.ps1
```

Drag the separator up and down: the log shrinks to 60px and no further, the tab area never goes below 200px, and the separator is visible in both themes.

- [ ] **Step 6: Commit**

```bash
git add ui/UI.xaml src/modules/App.Bootstrap.ps1 tests/Test-Ui.ps1
git commit -m "feat(ui): the log pane is resizable"
```

---

## Task 10: Clarify what the context menu acts on

**The "say the list is stale" half of this task shipped with Task 18**, whose locked Update button needed exactly that sentence to explain itself — the log line and its assertion are already in place, so only the context menu part is left here.

The checkbox column drives the action bar while row highlighting drives the context menu — true, documented in the comments, and invisible on screen.

**Files:**
- Modify: `ui\UI.xaml` (four context menu headers)
- Test: `tests\Test-Ui.ps1` — one static assertion

- [ ] **Step 1: Write the failing test**

In `tests\Test-Ui.ps1`, next to the settings block:

```powershell
# Dopo un aggiornamento le versioni in elenco sono vecchie: Install e Uninstall lo dicono,
# Update non lo diceva e l'elenco sembrava semplicemente sbagliato.
if ((Get-FunctionSource 'Start-UpdateSelected') -notmatch 'press Check') {
    throw "a coda finita nessuno dice che l'elenco e' da rileggere"
}
# Le voci del menu contestuale agiscono sulle righe EVIDENZIATE, non su quelle spuntate:
# se non lo dicono, l'utente spunta e poi si chiede perche' il pin sia andato altrove.
$menuHeaders = @([regex]::Matches($uiText, '<MenuItem[^>]*Header="([^"]*)"') | ForEach-Object { $_.Groups[1].Value })
if ($menuHeaders.Count -eq 0) { throw "nessuna voce di menu trovata: regex da rivedere" }
$vague = @($menuHeaders | Where-Object { $_ -notmatch 'highlighted' })
if ($vague.Count -gt 0) { throw "voci di menu che non dicono su cosa agiscono: $($vague -join ', ')" }
"OK menu   $($menuHeaders.Count) voci di menu dichiarano di agire sulle righe evidenziate"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-Ui.ps1`

Expected: FAIL with `a coda finita nessuno dice che l'elenco e' da rileggere`.

- [ ] **Step 3: Log the staleness**

In `src\modules\Tab.Updates.ps1`, in `Start-UpdateSelected`, the `OnDone` becomes:

```powershell
    } -OnDone {
        Set-AppBusy $false
        # L'elenco NON si ricarica da solo: cancellerebbe la colonna Result appena scritta,
        # che e' il resoconto di com'e' andata. Ma le versioni mostrate ora sono vecchie, e
        # senza dirlo l'elenco sembra semplicemente sbagliato.
        Write-Log "The versions in this list are stale now: press Check to rescan."
    }
```

- [ ] **Step 4: Name what the menu acts on**

In `ui\UI.xaml`, in both context menus, the four headers become:

```xml
                                    <MenuItem x:Name="MenuPinUpdates"   Header="Pin highlighted (block upgrades)"/>
                                    <MenuItem x:Name="MenuUnpinUpdates" Header="Remove pin from highlighted"/>
```

```xml
                                    <MenuItem x:Name="MenuPinInstalled"   Header="Pin highlighted (block upgrades)"/>
                                    <MenuItem x:Name="MenuUnpinInstalled" Header="Remove pin from highlighted"/>
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-Ui.ps1`

Expected: PASS with `OK menu 4 voci di menu dichiarano di agire sulle righe evidenziate`.

- [ ] **Step 6: Commit**

```bash
git add src/modules/Tab.Updates.ps1 ui/UI.xaml tests/Test-Ui.ps1
git commit -m "feat(ui): say the updates list is stale, name what the context menu acts on"
```

---

## Task 11: F5 and Ctrl+F

Two shortcuts, on the window, dispatching by active tab. Access keys on the buttons are **skipped**: every control is already reachable with Tab, and `_Select all` would split the label between XAML and the code that rewrites it. Add them if someone asks.

**Files:**
- Modify: `src\modules\App.Bootstrap.ps1` (`Start-App`)
- Test: `tests\Test-Ui.ps1`

- [ ] **Step 1: Write the failing test**

In `tests\Test-Ui.ps1`, next to the settings block:

```powershell
# F5 ricarica la scheda attiva, Ctrl+F porta al campo di ricerca. Non si possono premere
# tasti in un test headless: si verifica che l'aggancio ci sia e che sia in tunneling sulla
# FINESTRA, perche' il tasto arriva prima al controllo che ha il fuoco (una griglia usa F5
# e Ctrl+F per suo conto).
$startSrc = Get-FunctionSource 'Start-App'
if ($startSrc -notmatch 'Add_PreviewKeyDown') { throw "le scorciatoie non sono agganciate in tunneling sulla finestra" }
foreach ($k in 'F5', 'Key\]::F\b', 'Control') {
    if ($startSrc -notmatch $k) { throw "scorciatoia mancante o agganciata diversamente: $k" }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-Ui.ps1`

Expected: FAIL with `le scorciatoie non sono agganciate in tunneling sulla finestra`.

- [ ] **Step 3: Add the handler in `src\modules\App.Bootstrap.ps1`**

In `Start-App`, after the hyperlink handler from Task 7:

```powershell
    # Scorciatoie. PreviewKeyDown sulla FINESTRA e non sui controlli: in tunneling la
    # finestra vede il tasto per prima, mentre un DataGrid con il fuoco si mangerebbe F5 e
    # Ctrl+F per suo conto. Il tab attivo decide cosa ricaricare: una scorciatoia che agisce
    # su una scheda che non si sta guardando sorprende.
    $script:window.Add_PreviewKeyDown({
        param($s, $e)
        if ($e.Key -eq [System.Windows.Input.Key]::F5) {
            if     ($TabMain.SelectedItem -eq $TabUpdates)   { Load-Upgrades;  $e.Handled = $true }
            elseif ($TabMain.SelectedItem -eq $TabInstalled) { Load-Installed; $e.Handled = $true }
        }
        elseif ($e.Key -eq [System.Windows.Input.Key]::F -and
                ($e.KeyboardDevice.Modifiers -band [System.Windows.Input.ModifierKeys]::Control)) {
            $TabInstall.IsSelected = $true
            [void]$TxtSearch.Focus()
            $e.Handled = $true
        }
    })
```

`Load-Upgrades` and `Load-Installed` already refuse to run while winget is busy (Task 4), so the shortcut needs no guard of its own.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-Ui.ps1`

Expected: PASS.

- [ ] **Step 5: Press the keys**

```bash
powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\src\main.ps1
```

F5 in Updates rescans; F5 in Installed reloads; F5 in Install and in Settings does nothing. Ctrl+F from any tab lands on the Install tab with the caret in the search box. Press F5 during a scan: nothing should stack up.

- [ ] **Step 6: Document and commit**

Add to the `### Settings` area of `README.md`: "**F5** rescans the active tab, **Ctrl+F** jumps to the search box."

```bash
git add src/modules/App.Bootstrap.ps1 tests/Test-Ui.ps1 README.md
git commit -m "feat(ui): F5 rescans the active tab, Ctrl+F focuses the search box"
```

---

## Task 12: Deduplicate the deferred refresh, drop trailing blank lines

The same five-line dispatcher-defer block appears in all three tabs with only the function name changing. The helper must build its handler with `[scriptblock]::Create` and **not** `GetNewClosure()`: a closure creates a module scope in which `$script:` is no longer this script, which is the trap documented in `App.Jobs.ps1:88`. It also cannot capture the helper's own parameters, because the handler runs long after the helper returned — so the function name is interpolated into the text instead.

**Files:**
- Modify: `src\modules\App.Ui.ps1` (new `Register-GridRefresh`)
- Modify: `src\modules\Tab.Updates.ps1`, `src\modules\Tab.Install.ps1`, `src\modules\Tab.Installed.ps1`
- Test: `tests\Test-Ui.ps1`

**Interfaces:**
- Consumes: `$window` from `Start-App`.
- Produces: `Register-GridRefresh($Target, [string]$RefreshFunction)` — attaches one handler to both `CellEditEnding` and `PreviewMouseLeftButtonUp` on `$Target`, calling `$RefreshFunction` at `Background` priority. The parameter is named `$Target`, **not** `$Grid`, which would shadow the control of that name.

- [ ] **Step 1: Write the failing test**

In `tests\Test-Ui.ps1`, add before section 13:

```powershell
# 12c) Il ricalcolo differito dei contatori era copiato in tutte e tre le schede. Vive in un
# posto solo, e le tre schede lo usano: se una tornasse a scriverselo a mano, il prossimo
# inciampo sull'overload di BeginInvoke andrebbe corretto in tre punti.
foreach ($f in 'Tab.Updates.ps1', 'Tab.Install.ps1', 'Tab.Installed.ps1') {
    $t = Get-Content (Join-Path $root "src\modules\$f") -Raw
    if ($t -notmatch 'Register-GridRefresh') { throw "$f non usa Register-GridRefresh" }
    if ($t -match 'Dispatcher\.BeginInvoke') { throw "$f richiama ancora il dispatcher a mano" }
}
# Il collante non deve essere una closure: GetNewClosure crea un module scope dove $script:
# non e' piu' questo script (la trappola documentata in App.Jobs.ps1).
$regSrc = Get-FunctionSource 'Register-GridRefresh'
if ($regSrc -match 'GetNewClosure') { throw "Register-GridRefresh usa GetNewClosure: `$script: non funzionerebbe piu'" }
if ($regSrc -notmatch '\[scriptblock\]::Create') { throw "Register-GridRefresh non costruisce l'handler da testo" }
# E deve funzionare davvero: dopo il click finto il contatore si aggiorna.
$items.Clear()
$items.Add([WgtRow]@{ Id = 'A.A'; Name = 'A'; Selected = $true })
$TxtSelected.Text = 'stale'
Refresh-SelectionState
if ($TxtSelected.Text -ne '1 selected') { throw "il ricalcolo non aggiorna il contatore: '$($TxtSelected.Text)'" }
$items.Clear()
Refresh-SelectionState
"OK defer  ricalcolo differito condiviso dalle tre schede"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-Ui.ps1`

Expected: FAIL with `Tab.Updates.ps1 non usa Register-GridRefresh`.

- [ ] **Step 3: Add the helper to `src\modules\App.Ui.ps1`**

```powershell
# Aggancia a una griglia il ricalcolo differito dei suoi contatori.
# PERCHE' DIFFERITO: il binding della spunta e' UpdateSourceTrigger=PropertyChanged, ma il
# valore arriva sull'oggetto solo DOPO che il ToggleButton ha commutato, quindi il ricalcolo
# va rimandato a priorita' Background.
# PERCHE' PreviewMouseLeftButtonUp: evento tunneling, raggiunge la griglia prima che la
# CheckBox marchi l'evento come gestito -> contatore e etichette si aggiornano al click e
# non alla perdita di fuoco della cella.
# NB: BeginInvoke([action]{...}, 'Background') NON esiste come overload -> PowerShell
# risolve su BeginInvoke(Delegate, params Object[]) e passa 'Background' COME ARGOMENTO a un
# delegate senza parametri => TargetParameterCountException, che risale da ShowDialog().
# Va usata la forma con la priorita' PER PRIMA e l'enum tipizzato.
# Il nome della funzione si INTERPOLA nel testo e l'handler nasce da
# [scriptblock]::Create: i parametri di questa funzione non esistono piu' quando l'evento
# scatta, e .GetNewClosure() non e' la via d'uscita — la closure crea un module scope dove
# $script: non e' piu' lo scope di questo script (vedi App.Jobs.ps1).
# $Target e non $Grid: un parametro chiamato $Grid coprirebbe il controllo omonimo.
function Register-GridRefresh($Target, [string]$RefreshFunction) {
    $handler = [scriptblock]::Create(
        "`$window.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [action]{ $RefreshFunction }) | Out-Null")
    $Target.Add_CellEditEnding($handler)
    $Target.Add_PreviewMouseLeftButtonUp($handler)
}
```

- [ ] **Step 4: Use it in the three tabs**

In `src\modules\Tab.Updates.ps1`, replace the whole `$queueSelectionRefresh` block and its two `Add_*` calls at the end of `Initialize-UpdatesTab` with:

```powershell
    Register-GridRefresh $Grid 'Refresh-SelectionState'
```

In `src\modules\Tab.Install.ps1`, replace `$queueInstallRefresh` and its two calls with:

```powershell
    Register-GridRefresh $GridSearch 'Refresh-InstallState'
```

In `src\modules\Tab.Installed.ps1`, replace `$queueInstalledRefresh` and its two calls with:

```powershell
    Register-GridRefresh $GridInstalled 'Refresh-InstalledState'
```

- [ ] **Step 5: Strip the trailing blank lines**

Remove the runs of blank lines at the end of `src\main.ps1` (15), `src\modules\App.Bootstrap.ps1` (4), `ui\UI.xaml` (5), `src\build.ps1` (2), `tests\Test-InvokeWinGet.ps1` (1) and any others you meet — leave exactly one newline at end of file. `build.ps1` already `TrimEnd()`s modules and XAML before injecting them, so this changes nothing in the exe; it is tidiness only.

- [ ] **Step 6: Run both test scripts to verify they pass**

Run: `powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-Ui.ps1`

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-InvokeWinGet.ps1`

Expected: both PASS. `Test-InvokeWinGet.ps1` matters here: its section 2 fails on any `BeginInvoke([action]` left in the app code, which is precisely the form the helper must avoid.

- [ ] **Step 7: Click some checkboxes**

```bash
powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\src\main.ps1
```

In each of the three grids, tick and untick rows: the "N selected" counter and the button states must react on the click, not on leaving the cell. Then press Select all with a partial selection — that path depends on the deferred recalculation running *after* the click.

- [ ] **Step 8: Commit**

```bash
git add src/modules/App.Ui.ps1 src/modules/Tab.Updates.ps1 src/modules/Tab.Install.ps1 src/modules/Tab.Installed.ps1 src/main.ps1 src/modules/App.Bootstrap.ps1 ui/UI.xaml src/build.ps1 tests/Test-Ui.ps1 tests/Test-InvokeWinGet.ps1
git commit -m "refactor: one deferred grid refresh for all three tabs"
```

---

## Task 13: Consistency and hardening (optional)

Two low-severity items from the review. Neither is user-visible; do them when convenient.

**Files:**
- Modify: `src\modules\WinGet.Parse.ps1`, `src\modules\Tab.Updates.ps1`, `src\modules\Tab.Install.ps1`, `src\modules\Tab.Installed.ps1`, `src\modules\App.Pins.ps1`
- Modify: `src\modules\WinGet.Exec.ps1`
- Test: `tests\Test-InvokeWinGet.ps1`

- [ ] **Step 1: Write the failing test**

In `tests\Test-InvokeWinGet.ps1`, add a new section before the final tally:

```powershell
# ------------------------------------------------------------------
Write-Host "`n7) Argomenti con apici sbilanciati" -ForegroundColor Cyan
# La riga di comando si costruisce per concatenazione e la esegue cmd: un Id che contiene un
# apice doppio produrrebbe un comando malformato, eseguito comunque. Gli Id vengono dal
# catalogo e dal registro, quindi non e' mai accaduto — ma se accade, meglio un errore
# chiaro di un comando a caso.
$threw = $false
try { Invoke-WinGet 'cmd.exe' '/c echo "sbilanciato' } catch { $threw = $true }
Check "apici sbilanciati rifiutati invece di eseguiti" $threw
# E il caso normale non deve rompersi: gli apici bilanciati passano.
$ok = Invoke-WinGet 'cmd.exe' '/c echo "bilanciato"'
Check "apici bilanciati eseguiti (output '$($ok.Output.Trim())')" ($ok.Output -match 'bilanciato')
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-InvokeWinGet.ps1`

Expected: FAIL with `FAIL apici sbilanciati rifiutati invece di eseguiti`.

- [ ] **Step 3: Reject unbalanced quotes in `src\modules\WinGet.Exec.ps1`**

In `Invoke-WinGet`, as the first statement:

```powershell
function Invoke-WinGet([string]$exePath, [string]$argLine, [scriptblock]$Tick) {
    # La riga finisce dentro cmd per concatenazione: con un numero DISPARI di apici doppi il
    # comando che cmd vede non e' quello che intendevamo, e verrebbe eseguito comunque.
    # Nessun Id del catalogo o del registro contiene apici, quindi qui non ci si arriva —
    # ma se ci si arriva, un errore e' meglio di un comando a caso eseguito da amministratore.
    if ((($argLine.ToCharArray() | Where-Object { $_ -eq '"' }).Count % 2) -ne 0) {
        throw "winget arguments have unbalanced quotes, refusing to run: $argLine"
    }
```

`Start-WinGetQueue` already catches per-row exceptions and marks that row `error` without stopping the queue, so a rejected row degrades exactly as any other failure.

- [ ] **Step 4: Use `$wingetPath` in the read functions**

In `src\modules\WinGet.Parse.ps1`, replace `& winget` with `& $wingetPath` in all four functions — `Get-WinGetSearch`, `Get-WinGetPins`, `Get-WinGetInstalled`, `Get-WinGetUpgrades`. For example:

```powershell
    $raw = & $wingetPath @wgArgs 2>&1 | Out-String -Width 4096
```

Update the comment at the top of `Get-WinGetSearch` to say where the variable comes from:

```powershell
# $wingetPath arriva dalle -Vars del job: come tutto il resto del runspace, non si affida al
# PATH: Get-WinGetPath ha gia' risolto il percorso reale una volta all'avvio.
```

Then add it to the `-Vars` of every job that calls one of those four functions:

- `src\modules\Tab.Updates.ps1`, in `Load-Upgrades`: `-Vars @{ incUnknown = [bool]$ChkUnknown.IsChecked; wingetPath = $wingetPath }`
- `src\modules\Tab.Installed.ps1`, in `Load-Installed`: add `-Vars @{ wingetPath = $wingetPath }` (the job currently passes none)
- `src\modules\Tab.Install.ps1`, in `Start-Search`: `-Vars @{ q = $q; store = $IncludeStore; wingetPath = $wingetPath }`
- `src\modules\App.Pins.ps1`, in `Update-PinFlags`: add `-Vars @{ wingetPath = $wingetPath }`

In `tests\Test-InvokeWinGet.ps1` section 4, the winget stub is a *function* named `winget`. `& $wingetPath` still resolves it as long as the variable holds the bare command name, so add next to the stub:

```powershell
# Stub di winget: il parser fa "& $wingetPath", e con il nome nudo la risoluzione del comando
# trova questa funzione prima dell'eseguibile. Nessuna modifica al codice di produzione.
$wingetPath = 'winget'
function winget { $fixture }
```

- [ ] **Step 5: Run both test scripts to verify they pass**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-InvokeWinGet.ps1`

Run: `powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-Ui.ps1`

Expected: both PASS. `Test-Ui.ps1` sections 14, 17 and 18 are the ones that would break if a `-Vars` entry was forgotten — they call the four read functions inside real runspaces, and a missing `$wingetPath` there fails with an empty result rather than an error, so watch for `la ricerca di 'vlc' non ha prodotto risultati`.

- [ ] **Step 6: Commit**

```bash
git add src/modules/WinGet.Exec.ps1 src/modules/WinGet.Parse.ps1 src/modules/Tab.Updates.ps1 src/modules/Tab.Install.ps1 src/modules/Tab.Installed.ps1 src/modules/App.Pins.ps1 tests/Test-InvokeWinGet.ps1
git commit -m "fix(winget): resolved path in the read commands, reject unbalanced quotes"
```

---

## Task 14: Release 1.10.0

Do this only once every task you intend to ship has landed and both test scripts are green.

Three hard dependencies make the release mandatory rather than optional, and worth stating before touching anything: the published winget manifest points at `releases/download/v1.9.0/WinGetStudio.exe` and pins its SHA-256, so the asset cannot move; the app's own update check reads `releases/latest` and verifies the download against the digest GitHub publishes with the asset; and the package is live in `microsoft/winget-pkgs`, so a version that never gets a release leaves those users behind. Task 19 closes that last one.

**Pre-condition:** `gh` authenticated as **FedeB2160**.

```bash
gh api repos/FedeB2160/WinGetStudio --jq .permissions
```

Must report `"push": true`. The account that was active before this work (`FedeB-Egi`) has `push: false` on this repo, and every write through `gh` answers 403 with an error that blames the token's `workflow` scope and sends you the wrong way.

**Files:**
- Modify: `src\main.ps1:22` (`$AppVersion`)
- Modify: `CHANGELOG.md`

- [ ] **Step 1: Bump the version**

In `src\main.ps1`:

```powershell
$AppVersion = '1.10.0'
```

This is the only place the version exists: `build.ps1` reads it with a regex and passes it to ps2exe, and the Settings tab shows it. Test 11 checks the shape `x.y.z` and that `build.ps1` still forwards it.

- [ ] **Step 2: Run the tests**

Run: `powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-Ui.ps1`

Expected: PASS, including `OK ver versione 1.10.0`. Note that `Test-NewerVersion 'v1.10.0' '1.9.0'` is already asserted in section 20 — the version you just set is the one that comparison was written for.

- [ ] **Step 3: Promote `## Unreleased` into the release entry**

Every task added one line under `## Unreleased` as it landed. Now those lines become prose, and `## Unreleased` disappears. Do not write this from memory: read the section first and check that every line has a home below, and that nothing below claims something no line accounts for.

The result, at the top of `CHANGELOG.md` under the `# Changelog` heading, in the narrative style the file already uses (what changed and why, never a list of commits):

```markdown
## v1.10.0

### Settings is a tab, and the tabs are in order

The gear button and its full-window overlay are gone. **Settings** is now a tab pinned to the right of the strip, so the progress bar and the log stay visible while you are in it — the overlay used to cover exactly the part of the window that tells you how an operation is going. Esc is gone with it: a tab has nothing to close.

The three functional tabs are in alphabetical order, **Install | Installed | Updates**. Updates is still the view the app opens on, since that is what the startup scan fills.

### Your choices are remembered

**Unknown**, **MS Store** and **Scope** used to reset at every launch. They persist now, next to the theme under `HKCU:\Software\WinGetStudio`. Ticking **Unknown** also rescans immediately instead of waiting for the next Check.

The startup check for new releases can be turned off: **Check for updates at startup**, in Settings, on by default. The manual button always works.

### Readable in the dark

The **Update to vX.Y.Z** button had white text hardcoded on the accent colour, which in the dark theme measured 2.01:1 — below the 4.5:1 minimum, on the most important button of the screen. The foreground now comes from the theme. The light theme's warning colour was also under the threshold for a graphical element and has been darkened. The test suite now measures every foreground/background pair in both themes and fails below the floor.

### Fixed: two winget processes at once

Typing in **Install** and switching straight to **Installed** could run `winget search` and `winget list` at the same time, which is how a winget command ends up failing with exit 1. A search now counts as winget work like everything else, and `Start-WinGetQueue` is the single place that takes the busy state.

### Updates you can stop, and a list that stops lying

While a queue runs the **ticks and the pin entries are disabled** rather than merely refusing to work, and the grid still scrolls - the list was never frozen, it only looked available when it was not.

**Update** turns into **Cancel** while its own queue runs. Cancelling lets the package in flight finish and then stops: nothing is killed halfway through an installer, and the packages that never ran keep their tick and an empty result.

After an update, an install, an uninstall or an import, **Update locks until the next Check**. Pressing it again used to re-run winget on packages that were already current, which exits non-zero and painted a red cross over rows that had in fact succeeded. Pins do not lock it: a pin blocks upgrades, it does not change installed versions.

### Smaller things

- The **scrollbars follow the theme**: in the dark theme they used to stay white, the last piece of the window the system still painted its own way.
- The **log pane can be resized** with a handle instead of being stuck at 140px.
- The progress bar goes **indeterminate during a scan** rather than sitting at zero.
- After an update the log says the listed versions are stale and to press Check.
- **F5** rescans the active tab, **Ctrl+F** jumps to the search box.
- Context menu entries say they act on the **highlighted** rows, not the ticked ones.
- Status glyphs carry accessible names, so a screen reader announces "Failed" rather than a codepoint.
- **About** now says what the app actually does, links to the source, the release notes, the licence and where to report a bug, and notes that it was built with the help of Claude Code.
```

Trim this to the tasks you actually shipped.

- [ ] **Step 4: Commit and push**

```bash
git add src/main.ps1 CHANGELOG.md
git commit -m "chore(release): 1.10.0"
```

```bash
git push
```

- [ ] **Step 5: Build and check the exe**

```bash
.\build.bat
```

Expected: `Moduli iniettati: ...` listing 13 modules (`App.Prefs.ps1` present, `App.Settings.ps1` absent), then `Fatto: ...\dist\WinGetStudio.exe (versione 1.10.0)`. Run the exe: it elevates, the tab strip is right, and the Settings tab shows `v1.10.0`. The exe follows a different loading path from the `.ps1` (concatenated modules instead of dot-sourcing), so this is not a formality.

- [ ] **Step 6: Merge into `main` and tag**

The tag must sit on what is published, so the branch merges first.

```bash
git switch main && git merge --no-ff feature/v1.10.0 && git push
```

```bash
git tag v1.10.0 && git push origin v1.10.0
```

**The tag and `$AppVersion` must agree.** The app compares its own constant with the tag: a mismatch means it either keeps offering an update that is already installed, or never offers one at all.

- [ ] **Step 7: Publish the release**

Extract the `## v1.10.0` section into a temporary file for the notes, then:

```bash
gh release create v1.10.0 dist/WinGetStudio.exe --title "WinGet Studio v1.10.0" --notes-file <estratto>
```

```bash
gh release view v1.10.0
```

Expected: the release exists, not a draft, with `WinGetStudio.exe` attached. GitHub computes the asset's SHA-256 itself, and that digest is what the app verifies a download against — **builds are not reproducible**, so recompiling and comparing hashes proves nothing. What is verifiable is that digest and the Authenticode signature.

- [ ] **Step 8: Prove the update chain works**

The one check that cannot be faked: take the **v1.9.0** exe, run it, and let it find v1.10.0.

Expected: the Settings tab shows an **Update to v1.10.0** button, the confirmation names the file and its size, the download is reported as verified against the SHA-256, and the app restarts as v1.10.0. Nothing else in the suite exercises release → check → download → verify → replace end to end.

---

## Task 15: Scrollbars that follow the theme

The last control the system still paints its own way. Like `CheckBox`, `DataGridColumnHeader` and `ComboBox`, the Aero2 `ScrollBar` template hardcodes light colours and ignores `Background`, so in the dark theme every scrollbar stays white: the three grids, the log, and the settings `ScrollViewer`.

A minimal template — track plus thumb, no arrow buttons, which Windows 11 no longer draws either — using the theme keys that already exist. **No new theme keys**, so tests 3 and 4 need no changes.

**Files:**
- Modify: `ui\UI.xaml` (`Window.Resources`)
- Test: `tests\Test-Ui.ps1` — next to the other template checks

- [ ] **Step 1: Write the failing test**

In `tests\Test-Ui.ps1`, add after the `OK a11y` block of section 10d:

```powershell
# 10f) Barre di scorrimento: il template di sistema (Aero2) cabla colori chiari e ignora
# Background, quindi in Dark restavano BIANCHE — l'ultimo pezzo di finestra dipinto da
# Windows invece che dal tema. Si controlla che lo stile esista, che sostituisca il
# template (senza, i Setter di colore non arrivano da nessuna parte) e che non contenga
# colori cablati, che e' esattamente il difetto che stiamo togliendo.
$sbStyle = $window.Resources[[System.Windows.Controls.Primitives.ScrollBar]]
if (-not $sbStyle) { throw "nessuno stile per ScrollBar: in Dark le barre restano bianche" }
if (@($sbStyle.Setters | Where-Object { $_.Property.Name -eq 'Template' }).Count -eq 0) {
    throw "lo stile della ScrollBar non ne sostituisce il template"
}
$sbText = [regex]::Match($uiText, '(?s)<Style TargetType="ScrollBar">.*?</Style>\s*$|(?s)<Style TargetType="ScrollBar">.*?\n        </Style>').Value
if (-not $sbText) { throw "stile ScrollBar non trovato nel testo di UI.xaml: regex da rivedere" }
if ($sbText -match '"#[0-9A-Fa-f]{6}"') { throw "colori cablati nello stile della ScrollBar: non seguirebbero il tema" }
if ($sbText -notmatch 'PART_Track') { throw "manca PART_Track: ScrollBar non saprebbe dove mettere il cursore" }
"OK scroll  ScrollBar ri-templata, nessun colore cablato"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-Ui.ps1`

Expected: FAIL with `nessuno stile per ScrollBar: in Dark le barre restano bianche`.

- [ ] **Step 3: Add the thumb and the scrollbar template**

In `ui\UI.xaml`, in `Window.Resources`, after the `ProgressBar` style:

```xml
        <!-- Cursore della barra di scorrimento: un rettangolo arrotondato che schiarisce
             sotto il mouse e mentre si trascina. Margin 2: lascia un filo di traccia
             visibile ai lati, come fa Windows 11. -->
        <Style x:Key="ScrollThumb" TargetType="Thumb">
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="Thumb">
                        <Border x:Name="bd" CornerRadius="4" Margin="2"
                                Background="{DynamicResource BorderBrush2}"/>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="bd" Property="Background" Value="{DynamicResource SubtleFgBrush}"/>
                            </Trigger>
                            <Trigger Property="IsDragging" Value="True">
                                <Setter TargetName="bd" Property="Background" Value="{DynamicResource SubtleFgBrush}"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>

        <!-- Barra di scorrimento. Come CheckBox, header e ComboBox: il template di sistema
             (Aero2) cabla colori chiari e ignora Background, quindi in Dark-Mode le barre
             restavano BIANCHE, ed erano l'ultimo pezzo della finestra a non seguire il tema.
             Template minimo: traccia + cursore, senza i pulsanti freccia (Windows 11 non li
             disegna piu'). I due RepeatButton dentro il Track restano, trasparenti: sono
             loro che fanno avanzare di una pagina quando si clicca nel vuoto della traccia,
             e senza di loro quel clic non farebbe nulla.
             PART_Track e' il nome che ScrollBar cerca per calcolare la posizione del cursore:
             rinominarlo blocca la barra senza alcun errore.
             IsDirectionReversed="True" e' la forma VERTICALE (valore che cresce verso il
             basso); il trigger su Orientation lo toglie e scambia gli assi. -->
        <Style TargetType="ScrollBar">
            <Setter Property="Background" Value="{DynamicResource CtrlBgBrush}"/>
            <Setter Property="Width" Value="12"/>
            <Setter Property="MinWidth" Value="12"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ScrollBar">
                        <Border Background="{TemplateBinding Background}">
                            <Track x:Name="PART_Track" IsDirectionReversed="True">
                                <Track.DecreaseRepeatButton>
                                    <RepeatButton Command="ScrollBar.PageUpCommand" Focusable="False">
                                        <RepeatButton.Template>
                                            <ControlTemplate TargetType="RepeatButton">
                                                <Border Background="Transparent"/>
                                            </ControlTemplate>
                                        </RepeatButton.Template>
                                    </RepeatButton>
                                </Track.DecreaseRepeatButton>
                                <Track.Thumb>
                                    <Thumb Style="{StaticResource ScrollThumb}"/>
                                </Track.Thumb>
                                <Track.IncreaseRepeatButton>
                                    <RepeatButton Command="ScrollBar.PageDownCommand" Focusable="False">
                                        <RepeatButton.Template>
                                            <ControlTemplate TargetType="RepeatButton">
                                                <Border Background="Transparent"/>
                                            </ControlTemplate>
                                        </RepeatButton.Template>
                                    </RepeatButton>
                                </Track.IncreaseRepeatButton>
                            </Track>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="Orientation" Value="Horizontal">
                                <Setter Property="Width"     Value="Auto"/>
                                <Setter Property="MinWidth"  Value="0"/>
                                <Setter Property="Height"    Value="12"/>
                                <Setter Property="MinHeight" Value="12"/>
                                <Setter TargetName="PART_Track" Property="IsDirectionReversed" Value="False"/>
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-Ui.ps1`

Expected: PASS with `OK scroll ScrollBar ri-templata, nessun colore cablato`.

- [ ] **Step 5: Look at every scrollbar, in both themes**

```bash
powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\src\main.ps1
```

Four places to check, in Light **and** Dark: the Updates grid with enough rows to scroll, the log (which has a **horizontal** bar too, since it is `TextWrapping="NoWrap"`), the Installed grid, and the settings `ScrollViewer` with the window made short.

Then check three behaviours that a template swap can silently break:
1. **Dragging the thumb** scrolls, and the thumb tracks the mouse.
2. **Clicking the empty part of the track** pages in the direction you clicked. On the *horizontal* bar this is the one thing to watch: if it pages the wrong way, give the two `RepeatButton`s an `x:Name` and swap their commands to `ScrollBar.PageLeftCommand` / `ScrollBar.PageRightCommand` inside the `Orientation` trigger.
3. **The mouse wheel** still scrolls the grids — that comes from `ScrollViewer`, not from this template, so it should be untouched.

One thing this template does not reach: the little square where a horizontal and a vertical bar meet inside a `DataGrid` comes from the `ScrollViewer` template, not the `ScrollBar`. Look at it; if it stays light, it is one extra `Rectangle` fill and a separate decision, not part of this task.

- [ ] **Step 6: Commit**

```bash
git add ui/UI.xaml tests/Test-Ui.ps1
git commit -m "fix(theme): scrollbars follow the theme instead of staying white in dark"
```

---

## Task 16: Ticks and pins unavailable while a queue runs

Half of this already works and half only looks like it does. `$Grid.IsReadOnly = $busy` really does stop the ticks from being edited, but the checkboxes still *look* clickable, and the Pin entries in the context menu stay enabled — after Task 4 they answer "Another winget operation is still running", which is a refusal, not a block.

The grid itself must stay enabled: a disabled `DataGrid` stops responding to the wheel, the scrollbar and the keyboard, which is the regression test 9 exists to prevent.

**Files:**
- Modify: `ui\UI.xaml` (`ThemedCheckBox` and `PinnableCheckBox` styles)
- Modify: `src\modules\Tab.Updates.ps1` (`Set-UpdatesBusy`), `src\modules\Tab.Installed.ps1` (`Set-InstalledBusy`)
- Test: `tests\Test-Ui.ps1`

- [ ] **Step 1: Write the failing test**

In `tests\Test-Ui.ps1`, add after the settings block from Task 1:

```powershell
# Mentre una coda gira, spunte e pin non devono essere DISPONIBILI, ma la UI resta viva: la
# griglia si scorre, il log si legge. Prima le spunte erano bloccate (IsReadOnly) ma
# sembravano cliccabili, e le voci Pin restavano accese per poi rifiutare.
Set-AppBusy $true
foreach ($m in $MenuPinUpdates, $MenuUnpinUpdates, $MenuPinInstalled, $MenuUnpinInstalled) {
    if ($m.IsEnabled) { throw "una voce di pin resta attiva durante un'operazione" }
}
if (-not $Grid.IsReadOnly) { throw "le spunte restano modificabili durante un'operazione" }
# La griglia NON si disabilita: disabilitata non risponde piu' a rotellina, scrollbar e
# tastiera, ed e' la regressione che il controllo 9 esiste per impedire.
foreach ($g in $Grid, $GridSearch, $GridInstalled) {
    if (-not $g.IsEnabled) { throw "una griglia e' stata disabilitata: non si scorrerebbe piu'" }
}
Set-AppBusy $false
foreach ($m in $MenuPinUpdates, $MenuUnpinUpdates, $MenuPinInstalled, $MenuUnpinInstalled) {
    if (-not $m.IsEnabled) { throw "a operazione finita una voce di pin resta spenta" }
}
if ($Grid.IsReadOnly) { throw "a operazione finita le spunte restano bloccate" }

# E la spunta deve anche VEDERSI spenta: il trigger sta negli stili, non nel codice, cosi'
# vale per tutte e tre le griglie senza ripeterlo per scheda.
foreach ($st in 'ThemedCheckBox', 'PinnableCheckBox') {
    $blk = [regex]::Match($uiText, "(?s)x:Key=`"$st`".*?</Style>").Value
    if (-not $blk) { throw "stile $st non trovato in UI.xaml" }
    if ($blk -notmatch 'IsReadOnly, RelativeSource=\{RelativeSource AncestorType=DataGrid\}') {
        throw "lo stile $st non spegne la spunta quando la griglia e' in sola lettura"
    }
}
"OK lockrow spunte e pin spenti durante la coda, griglie ancora vive"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-Ui.ps1`

Expected: FAIL with `una voce di pin resta attiva durante un'operazione`.

- [ ] **Step 3: Grey the ticks out from the style**

In `ui\UI.xaml`, add a trigger to the `ThemedCheckBox` style — it has no `Style.Triggers` yet, so add the block just before `</Style>`:

```xml
            <Style.Triggers>
                <!-- Griglia in sola lettura = coda in corso: la spunta e' gia' bloccata da
                     IsReadOnly, ma senza questo continua a SEMBRARE cliccabile. Il trigger
                     sta nello stile e non nel codice, cosi' vale per tutte e tre le griglie.
                     Fuori da una griglia (Unknown, MS Store, Check at startup) l'antenato non
                     esiste, il binding torna null, e non succede niente. -->
                <DataTrigger Binding="{Binding IsReadOnly, RelativeSource={RelativeSource AncestorType=DataGrid}}" Value="True">
                    <Setter Property="IsEnabled" Value="False"/>
                </DataTrigger>
            </Style.Triggers>
```

Add the **same** trigger to `PinnableCheckBox`, next to its existing `Pinned` trigger:

```xml
            <Style.Triggers>
                <DataTrigger Binding="{Binding Pinned}" Value="True">
                    <Setter Property="IsEnabled" Value="False"/>
                </DataTrigger>
                <!-- Ripetuto e non ereditato: BasedOn porta con se' i Setter, e sui Trigger
                     preferisco non affidarmi all'ereditarieta' per una cosa che si nota solo
                     guardando lo schermo. Tre righe, zero dubbi. -->
                <DataTrigger Binding="{Binding IsReadOnly, RelativeSource={RelativeSource AncestorType=DataGrid}}" Value="True">
                    <Setter Property="IsEnabled" Value="False"/>
                </DataTrigger>
            </Style.Triggers>
```

- [ ] **Step 4: Disable the pin entries in the busy handlers**

In `src\modules\Tab.Updates.ps1`, in `Set-UpdatesBusy`, after the `IsReadOnly` line:

```powershell
    # Pin e Unpin spenti durante un'operazione: winget e' occupato, e una voce accesa che
    # risponde "riprova fra un attimo" e' un rifiuto, non un blocco.
    $MenuPinUpdates.IsEnabled   = -not $busy
    $MenuUnpinUpdates.IsEnabled = -not $busy
```

In `src\modules\Tab.Installed.ps1`, in `Set-InstalledBusy`, the same for its two entries:

```powershell
    $MenuPinInstalled.IsEnabled   = -not $busy
    $MenuUnpinInstalled.IsEnabled = -not $busy
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-Ui.ps1`

Expected: PASS with `OK lockrow`.

- [ ] **Step 6: Watch it during a real queue**

```bash
powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\src\main.ps1
```

Tick one package and press Update. While it runs: the ticks are visibly greyed, right-clicking a row shows both Pin entries greyed, and the list **still scrolls** with the wheel and the scrollbar. Check the same in the Installed tab during an uninstall.

- [ ] **Step 7: Commit**

```bash
git add ui/UI.xaml src/modules/Tab.Updates.ps1 src/modules/Tab.Installed.ps1 tests/Test-Ui.ps1
git commit -m "feat(ui): ticks and pins disabled while a queue runs, grid stays scrollable"
```

---

## Task 17: Update becomes Cancel

The queue runs in a runspace, so cancellation is **cooperative**: a flag both threads can see, read at the top of each iteration. The package in flight always finishes — nothing gets killed halfway through an installer.

Which queue is running also has to be published, because the busy state is global: an export, or an install started from another tab, raises the same `isBusy`, and offering "Cancel" on the Updates button for someone else's queue would be a lie.

**Files:**
- Modify: `src\modules\App.Jobs.ps1` (`Start-WinGetQueue`, new `Request-QueueCancel`)
- Modify: `src\modules\App.Ui.ps1` (`Set-AppBusy` clears the published verb)
- Modify: `src\modules\Tab.Updates.ps1` (`Set-UpdatesBusy`, `Refresh-SelectionState`, the button handler)
- Test: `tests\Test-Ui.ps1`
- Modify: `DEVELOPMENT.md`

**Interfaces:**
- Consumes: `Set-AppBusy` and the busy-handler registry from `App.Ui.ps1`; the choke point from Task 4.
- Produces:
  - `$script:queueVerb` — the `-Verb` of the queue currently running, or `$null`. Set by `Start-WinGetQueue` after its guard, cleared by `Set-AppBusy $false` **before** the handlers run, so a handler sees the final state.
  - `Request-QueueCancel` — asks the running queue to stop after the current package. Safe to call when nothing is running.

- [ ] **Step 1: Write the failing test**

In `tests\Test-Ui.ps1`, add after the `OK timers` block of section 13c — it needs `Wait-For`, which section 13 defines:

```powershell
# 13d) Il pulsante Update diventa Cancel mentre gira LA NOSTRA coda, e torna Update quando
# lo stato occupato si libera. Con la coda di un'altra scheda resta spento: annullare
# un'installazione dal pulsante degli aggiornamenti non vorrebbe dire niente.
$script:queueVerb = 'Update'
Set-AppBusy $true
if ($BtnUpdate.Content -ne 'Cancel') { throw "durante l'update il pulsante non diventa Cancel: '$($BtnUpdate.Content)'" }
if (-not $BtnUpdate.IsEnabled) { throw "il pulsante Cancel e' spento" }
# Set-PinFlags richiama Refresh-SelectionState mentre lo stato e' ANCORA occupato: era il
# primo modo in cui questo si rompeva, spegnendo il Cancel appena letti i pin.
Refresh-SelectionState
if (-not $BtnUpdate.IsEnabled) { throw "un ricalcolo della selezione ha spento il Cancel" }
$script:queueVerb = 'Install'
Set-AppBusy $true
if ($BtnUpdate.Content -eq 'Cancel') { throw "il pulsante mostra Cancel per una coda che non e' la sua" }
Set-AppBusy $false
if ($BtnUpdate.Content -ne 'Update') { throw "a coda finita il pulsante non torna Update: '$($BtnUpdate.Content)'" }
if ($null -ne $script:queueVerb) { throw "Set-AppBusy `$false non azzera il verbo della coda" }
"OK cancel  Update <-> Cancel legati alla coda in corso"

# 13e) L'annullamento vero, su una coda finta di 5 righe che lanciano "--version": rapido e
# innocuo. Si annulla subito dopo l'avvio, quindi il primo pacchetto e' in volo e gli altri
# non partono. NB: e' una corsa vinta con ampio margine (una winget --version costa ~0.3s,
# la richiesta arriva in millisecondi), ma per questo l'asserzione e' "meno di 5" e non un
# numero esatto.
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    "SKIP cancel2 winget non presente su questa macchina"
}
else {
    $probeRows = @(1..5 | ForEach-Object { [WgtRow]@{ Id = "Probe.$_"; Name = "Probe $_" } })
    $TxtLog.Clear()
    Start-WinGetQueue -Rows $probeRows -Verb 'Update' `
        -ArgsBuilder { param($r) '--version' } -OnDone { Set-AppBusy $false }
    Request-QueueCancel
    if (-not (Wait-For { -not $script:isBusy } 90)) { throw "la coda annullata non e' terminata" }
    $ran = @($probeRows | Where-Object { $_.Status }).Count
    if ($ran -ge 5) { throw "l'annullamento non ha fermato la coda: eseguiti $ran su 5" }
    if ($TxtLog.Text -notmatch 'cancelled') { throw "l'annullamento non e' finito nel log" }
    Stop-AllJobs
    "OK cancel2 coda fermata dopo $ran pacchetti su 5"
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-Ui.ps1`

Expected: FAIL with `durante l'update il pulsante non diventa Cancel: 'Update'`.

- [ ] **Step 3: Publish which queue is running, and clear it in `Set-AppBusy`**

In `src\modules\App.Ui.ps1`, `Set-AppBusy` becomes:

```powershell
# $script:queueVerb dice QUALE coda sta girando ('Update', 'Install', 'Uninstall', 'Pin')
# oppure $null. Lo stato occupato e' globale, quindi senza questo una scheda non puo'
# distinguere la propria operazione da quella di un'altra — ed e' l'unico modo per offrire
# "Cancel" solo su chi lo ha avviato.
# Si azzera PRIMA di chiamare gli handler, cosi' ognuno vede lo stato finale.
function Set-AppBusy([bool]$busy) {
    $script:isBusy = $busy
    if (-not $busy) { $script:queueVerb = $null }
    foreach ($h in $script:busyHandlers) { & $h $busy }
}
```

- [ ] **Step 4: Add cancellation to `src\modules\App.Jobs.ps1`**

Near the top, next to `$script:jobs`:

```powershell
# Annullamento COOPERATIVO della coda in corso. Una hashtable e non una variabile $script:
# perche' il runspace ha il proprio scope: una hashtable e' un tipo per RIFERIMENTO, quindi
# i due thread vedono lo stesso oggetto — lo stesso motivo per cui $rows funziona.
# Synchronized: l'accesso e' un bool letto una volta per pacchetto, ma costa nulla.
# NON si uccide il processo in corso: un installer interrotto a metà lascia la macchina in
# uno stato che nessuno sa descrivere. Si finisce il pacchetto e non si parte col prossimo.
$script:queueCancel = $null

function Request-QueueCancel {
    if ($script:queueCancel) { $script:queueCancel.Requested = $true }
}
```

In `Start-WinGetQueue`, right after the busy guard and `Set-AppBusy $true` from Task 4:

```powershell
    # Quale coda sta girando: lo leggono gli handler dello stato occupato.
    $script:queueVerb   = $Verb
    $script:queueCancel = [hashtable]::Synchronized(@{ Requested = $false })
```

Add it to the job variables, next to `rows`:

```powershell
        cancel     = $script:queueCancel
```

And in the runspace body, wrap the loop:

```powershell
        $done    = 0
        $stopped = $false
        foreach ($item in $rows) {
            # Annullamento: si controlla PRIMA di partire col pacchetto, mai a metà.
            if ($cancel.Requested) { $stopped = $true; break }
            $id   = $item.Id
            $name = $item.Name
```

and replace the final log line:

```powershell
        if ($stopped) { LogUI "$verb cancelled after $done of $($rows.Count) packages; the rest were left untouched." }
        else          { LogUI "$verb complete ($done/$($rows.Count))." }
```

- [ ] **Step 5: Turn the button into Cancel in `src\modules\Tab.Updates.ps1`**

In `Set-UpdatesBusy`, the busy branch becomes:

```powershell
    if ($busy) {
        # Durante un'operazione la selezione non si tocca.
        $BtnToggleAll.IsEnabled = $false
        # Il pulsante Update diventa Cancel SOLO se la coda in corso e' la nostra: un export
        # o un'installazione dall'altra scheda alzano lo stesso stato occupato, e offrire di
        # annullarli da qui sarebbe una bugia.
        if ($script:queueVerb -eq 'Update') {
            $BtnUpdate.Content   = 'Cancel'
            $BtnUpdate.ToolTip   = 'Finish the package in progress, then stop without starting the others'
            $BtnUpdate.IsEnabled = $true
        }
        else {
            $BtnUpdate.IsEnabled = $false
        }
    }
    else {
        # A riposo il pulsante torna quello che era; lo stato dipende da elenco e selezione.
        $BtnUpdate.Content = 'Update'
        $BtnUpdate.ToolTip = $null
        Refresh-SelectionState
    }
```

In `Refresh-SelectionState`, guard the line that would switch the Cancel off:

```powershell
    # req4: "Aggiorna" attivo solo se almeno uno selezionato. Ma mentre gira LA NOSTRA coda
    # il pulsante e' Cancel e deve restare premibile: Set-PinFlags richiama questa funzione
    # a stato ancora occupato, e senza la guardia spegneva il Cancel.
    if ($script:queueVerb -ne 'Update') {
        $BtnUpdate.IsEnabled = (-not $script:isBusy) -and ($sel -gt 0)
    }
```

In `Initialize-UpdatesTab`, the handler dispatches on the same flag:

```powershell
    # Lo stesso pulsante fa due cose: Update a riposo, Cancel mentre la nostra coda gira.
    # Due pulsanti separati avrebbero significato uno sempre spento, occupando spazio per
    # dire niente.
    $BtnUpdate.Add_Click({
        if ($script:queueVerb -eq 'Update') {
            Request-QueueCancel
            $BtnUpdate.Content   = 'Cancelling...'
            $BtnUpdate.IsEnabled = $false
            Write-Log "Cancelling: the package in progress will finish, then the queue stops."
            return
        }
        Start-UpdateSelected
    })
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-Ui.ps1`

Expected: PASS with `OK cancel` and `OK cancel2`. Section 18 (the real pin cycle) is the one to watch: it goes through `Start-WinGetQueue` with `-Verb 'Pin'`, so if the published verb leaked the Updates button would try to offer Cancel for a pin.

- [ ] **Step 7: Cancel a real queue**

```bash
powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\src\main.ps1
```

Tick three or four packages and press Update. The button reads **Cancel**; press it during the second package. Expect: the log says it is cancelling, the package in progress runs to its own result, the remaining rows keep their tick and an empty RESULT, and the button ends up back at **Update**. Then start another queue and let it finish normally: the button must return to Update there too.

- [ ] **Step 8: Document it**

In `README.md`, in the Updates section, add after the sentence describing the update queue: "A running queue can be stopped: while it runs the **Update** button reads **Cancel**, and pressing it lets the package in progress finish before stopping, so nothing is interrupted halfway through an installer."

In `DEVELOPMENT.md`, next to the note about the busy state:

```markdown
- **Cancelling a queue is cooperative.** `Start-WinGetQueue` shares a synchronized hashtable with its runspace and checks `Requested` at the top of each iteration, so the package in flight always finishes: killing an installer halfway leaves the machine in a state nobody can describe. `$script:queueVerb` publishes which queue is running, because the busy state is global and a tab has no other way to tell its own operation from another tab's — it is what lets the Updates button offer *Cancel* only for the update queue. The mechanism is generic; wiring it to Install or Uninstall is six lines each, and only the Updates queue uses it today.
```

- [ ] **Step 9: Commit**

```bash
git add src/modules/App.Jobs.ps1 src/modules/App.Ui.ps1 src/modules/Tab.Updates.ps1 tests/Test-Ui.ps1 DEVELOPMENT.md
git commit -m "feat(updates): Update turns into Cancel, stopping after the current package"
```

---

## Task 18: Update locks until the next Check

The list mirrors a snapshot taken by `Load-Upgrades`. As soon as anything alters the machine, the versions on screen are wrong, and pressing Update again re-runs winget on packages that are already current: winget exits non-zero, `Get-UpdateStatus` maps that to `error`, and a **red cross lands on rows that actually succeeded**. That is the defect this closes.

Auto-refreshing instead was rejected for a reason already paid for: it would wipe the RESULT column, which is the report of what just happened.

**Files:**
- Modify: `src\modules\Tab.Updates.ps1` (the flag, `Set-UpdatesStale`, `Refresh-SelectionState`, `Load-Upgrades`)
- Modify: `src\modules\Tab.Install.ps1` (`Install-Rows` OnDone), `src\modules\Tab.Installed.ps1` (`Start-UninstallSelected` OnDone), `src\modules\App.Backup.ps1` (`Invoke-PackageImport` OnDone)
- Test: `tests\Test-Ui.ps1`

**Interfaces:**
- Consumes: `$script:queueVerb` from Task 17.
- Produces: `Set-UpdatesStale` — marks the Updates list as no longer trustworthy and refreshes the button state. Called by every queue that alters the machine. Cleared only by `Load-Upgrades`.

- [ ] **Step 1: Write the failing test**

In `tests\Test-Ui.ps1`, add after the `OK cancel` block:

```powershell
# Dopo un'alterazione della macchina il pulsante Update si blocca fino al Check: ripremerlo
# rilanciava winget su pacchetti gia' aggiornati, che escono con codice non-zero e finivano
# in griglia come X ROSSE su righe andate a buon fine.
$items.Clear()
$items.Add([WgtRow]@{ Id = 'A.A'; Name = 'A'; Selected = $true })
$script:listStale = $false
Refresh-SelectionState
if (-not $BtnUpdate.IsEnabled) { throw "con una riga selezionata e la lista fresca Update deve essere attivo" }

Set-UpdatesStale
if ($BtnUpdate.IsEnabled) { throw "dopo un'alterazione Update deve restare bloccato" }
if ($TxtSelected.Text -notmatch 'press Check') { throw "non viene detto PERCHE' Update e' bloccato: '$($TxtSelected.Text)'" }
if (-not $BtnRefresh.IsEnabled) { throw "Check deve restare attivo: e' l'unico modo per sbloccare" }

# I pin NON marcano la lista: bloccano gli aggiornamenti, non cambiano le versioni installate.
$script:listStale = $false
Set-PinFlags @('A.A')
if ($script:listStale) { throw "un pin ha marcato la lista come vecchia" }
$items.Clear()
$script:listStale = $false
Refresh-SelectionState

# Le quattro code che alterano la macchina lo dichiarano, e solo il Check sblocca.
foreach ($fn in 'Start-UpdateSelected', 'Install-Rows', 'Start-UninstallSelected', 'Invoke-PackageImport') {
    if ((Get-FunctionSource $fn) -notmatch 'Set-UpdatesStale') { throw "$fn non marca la lista come vecchia" }
}
if ((Get-FunctionSource 'Load-Upgrades') -notmatch 'listStale\s*=\s*\$false') { throw "Load-Upgrades non sblocca il pulsante" }
"OK stale   Update bloccato dopo un'alterazione, sbloccato solo dal Check"
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-Ui.ps1`

Expected: FAIL with `Il termine 'Set-UpdatesStale' non è riconosciuto`.

- [ ] **Step 3: Add the flag in `src\modules\Tab.Updates.ps1`**

Next to `$script:allSelected`:

```powershell
# L'elenco rispecchia una fotografia della macchina scattata da Load-Upgrades. Appena
# qualcosa la altera — un aggiornamento, un'installazione, una disinstallazione, un import —
# le versioni a schermo non valgono piu', e ripremere Update rilancia winget su pacchetti
# gia' aggiornati: quelli escono con codice non-zero e si dipingono di ROSSO su righe che
# erano andate bene. Quindi il pulsante si blocca finche' non si rilegge.
# PERCHE' NON UNA RICARICA AUTOMATICA: cancellerebbe la colonna Result appena scritta, che
# e' il resoconto di com'e' andata.
# I PIN non entrano qui: bloccano gli aggiornamenti, non cambiano le versioni installate.
$script:listStale = $false

function Set-UpdatesStale {
    $script:listStale = $true
    Refresh-SelectionState
}
```

In `Refresh-SelectionState`, extend the guarded line from Task 17 and the counter:

```powershell
    if ($script:queueVerb -ne 'Update') {
        $BtnUpdate.IsEnabled = (-not $script:isBusy) -and ($sel -gt 0) -and (-not $script:listStale)
    }
```

```powershell
    # Due contatori: disponibili (top) e selezionati (action bar). A lista vecchia il secondo
    # cede il posto al motivo per cui Update e' spento: un pulsante grigio senza spiegazione
    # sembra un guasto.
    $TxtAvailable.Text = if ($total -eq 0) { "" } elseif ($total -eq 1) { "1 update available" } else { "$total updates available" }
    $TxtSelected.Text  = if ($script:listStale) { "list out of date - press Check" }
                         elseif ($sel -gt 0)    { "$sel selected" }
                         else                   { "" }
```

In `Load-Upgrades`, clear it right after the busy guard:

```powershell
function Load-Upgrades {
    if (Test-WinGetBusy) { return }
    # La lettura che si sta per fare E' la nuova fotografia: da qui il pulsante torna buono.
    $script:listStale = $false
    Set-AppBusy $true
```

- [ ] **Step 4: Declare the alteration from all four queues**

In `src\modules\Tab.Updates.ps1`, in `Start-UpdateSelected`, the `OnDone` becomes:

```powershell
    } -OnDone {
        Set-AppBusy $false
        # L'elenco NON si ricarica da solo: cancellerebbe la colonna Result appena scritta.
        # Ma le versioni mostrate ora sono vecchie, quindi Update si blocca fino al Check.
        Set-UpdatesStale
        Write-Log "The versions in this list are stale now: press Check to rescan."
    }
```

In `src\modules\Tab.Install.ps1`, in `Install-Rows`:

```powershell
    } -OnDone {
        Set-AppBusy $false
        Set-UpdatesStale
        # L'elenco della scheda Updates e' stato calcolato prima di queste installazioni.
        Write-Log "The Updates list may be out of date now: press Check to rescan."
    }
```

In `src\modules\Tab.Installed.ps1`, in `Start-UninstallSelected`:

```powershell
    } -OnDone {
        Set-AppBusy $false
        Set-UpdatesStale
        # L'elenco non viene ricaricato da solo: cancellerebbe la colonna Result appena
        # scritta, che e' il resoconto di cosa e' andato come.
        Write-Log "Uninstall finished: press Refresh to rebuild the list."
    }
```

In `src\modules\App.Backup.ps1`, in `Invoke-PackageImport`, before `Set-AppBusy $false`:

```powershell
            Write-Log "Press Refresh to rebuild the installed list."
            Set-AppBusy $false
            Set-UpdatesStale
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-Ui.ps1`

Expected: PASS with `OK stale`. Watch section 12's `Refresh-SelectionState` assertion (`con la lista vuota il pulsante Update deve restare spento`) — it must still pass, and it will, since an empty list disables the button for its own reason.

- [ ] **Step 6: Try the loop that used to paint red**

```bash
powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\src\main.ps1
```

Update one package and let it finish. Expect: the row keeps its green tick, **Update** is greyed, the label reads `list out of date - press Check`, and **Check** is live. Press Check: the list is rebuilt, the updated package is gone from it, and Update works again. Then do the same from the Install tab — installing something must lock the Updates button too. Finally pin a package: that must **not** lock it.

- [ ] **Step 7: Document it**

In `README.md`, in the Updates section: "After an update, an install, an uninstall or an import, **Update** is greyed until you press **Check** again. The versions on screen describe the machine as it was before, and running the queue on them would report failures for packages that had in fact succeeded."

- [ ] **Step 8: Commit**

```bash
git add src/modules/Tab.Updates.ps1 src/modules/Tab.Install.ps1 src/modules/Tab.Installed.ps1 src/modules/App.Backup.ps1 tests/Test-Ui.ps1 README.md
git commit -m "fix(updates): lock Update after any alteration until the next check"
```

```bash
git push
```

---

## Task 19: the winget manifest for 1.10.0

The package is live in `microsoft/winget-pkgs` at `manifests/f/FedeB2160/WinGetStudio/1.9.0`, so a version that gets a GitHub release but never reaches the community repository leaves every winget user on the old one. Three files, a validator run, a submission.

No code and no unit tests here: `winget validate` is the test, and the winget-pkgs CI installs and uninstalls the package in a sandbox on the pull request.

**Files:**
- Create: `winget\1.10.0\FedeB2160.WinGetStudio.yaml`, `…installer.yaml`, `…locale.en-US.yaml`

- [ ] **Step 1: Read the digest off the published release**

```bash
gh api repos/FedeB2160/WinGetStudio/releases/tags/v1.10.0 --jq '.assets[] | select(.name=="WinGetStudio.exe") | {name, size, digest}'
```

Take the hash from **the published asset**, never from a local `Get-FileHash` of your own build: builds are not reproducible, so the exe on your disk and the exe in the release are different bytes with the same size. Getting this wrong fails the winget-pkgs CI with a hash mismatch, after the PR is already open.

The API returns `sha256:<hex minuscolo>`; the manifest wants the bare hex, and the 1.9.0 manifest writes it uppercase — keep that.

- [ ] **Step 2: Create the three manifests**

Copy `winget\1.9.0\*` to `winget\1.10.0\` and change, and only change:

- all three files: `PackageVersion: 1.10.0`
- `…installer.yaml`: `InstallerUrl` (`…/download/v1.10.0/WinGetStudio.exe`), `InstallerSha256`, `ReleaseDate`
- `…locale.en-US.yaml`: `ReleaseNotes` (a short summary of the `## v1.10.0` changelog entry, not the whole thing) and `ReleaseNotesUrl` (`…/releases/tag/v1.10.0`)

Leave `InstallerType: portable`, `Architecture: x86` and `ElevationRequirement: elevatesSelf` alone. The installer type is what a later version changes, deliberately and with its own plan — see the note at the end of this file.

- [ ] **Step 3: Validate**

```bash
winget validate --manifest .\winget\1.10.0
```

Expected: `Manifest validation succeeded.` This is the same validator the moderators run. A `:` inside an unquoted YAML value is the usual way this fails — `ShortDescription` is quoted in 1.9.0 for exactly that reason.

- [ ] **Step 4: Install from the manifests locally (optional but cheap)**

```bash
winget settings --enable LocalManifestFiles
```

```bash
winget install --manifest .\winget\1.10.0
```

The first command needs an elevated prompt. This proves the URL resolves and the hash matches before a human moderator ever looks at it.

- [ ] **Step 5: Submit**

```bash
wingetcreate update FedeB2160.WinGetStudio --version 1.10.0 --urls https://github.com/FedeB2160/WinGetStudio/releases/download/v1.10.0/WinGetStudio.exe --submit
```

`wingetcreate` carries its own GitHub authentication and works through a personal fork, so it does not care which account `gh` is authenticated as. It forks `microsoft/winget-pkgs`, writes `manifests\f\FedeB2160\WinGetStudio\1.10.0\`, and opens the pull request with the conventional title `New version: FedeB2160.WinGetStudio version 1.10.0`. Automated validation runs first; a moderator reviews after. Updates to an existing package go through faster than the first submission did.

- [ ] **Step 6: Commit the manifests**

They stay in this repo as the versioned, reviewable copy of what was submitted — the pull request is a copy of that folder, not the other way round.

```bash
git add winget/1.10.0
git commit -m "chore(winget): manifests for 1.10.0"
```

```bash
git push
```

---

## Task 20: close the plan

Everything below happens on `main`: Task 14 merged the branch before tagging.

- [ ] **Step 1: Verify the whole thing, once, together**

```bash
powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-Ui.ps1
```

```bash
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-InvokeWinGet.ps1
```

Then the things no suite can see:

- The app from source: `powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\src\main.ps1` — tab strip right, Settings on the right, both themes, scrollbars following the theme.
- The compiled exe: it elevates, shows `v1.10.0`, and the Settings tab reports being up to date.
- The release chain: already proved in Task 14 Step 8, from the v1.9.0 exe.
- The winget submission: the pull request from Task 19 exists and its automated validation is green.

Read the `## v1.10.0` changelog entry against the ten decisions in this plan's header. Anything the changelog claims that the app does not do, or the app does that nothing documents, is a finding — fix it before Step 3, not after.

- [ ] **Step 2: Write the rule down where it survives**

In `DEVELOPMENT.md`, after *Publishing a release*:

```markdown
## Working on a plan

A multi-step change is planned in `docs\superpowers\plans\<date>-<topic>.md`, committed alongside the work so the reasoning travels with the diffs. One branch, one commit per task, both test suites green before each commit, the `README.md` and `DEVELOPMENT.md` lines the task invalidates in that same commit, a line under `## Unreleased` in the changelog, and a push after every commit.

**The plan file is deleted when the plan is done** — once every task is executed, both suites are green, and the result matches what the plan established. It is a working document: git history keeps every version of it, and what deserves to outlive it has already been written into the changelog, this file and the README.
```

- [ ] **Step 3: Delete the plan**

```bash
git rm docs/superpowers/plans/2026-08-04-tabbed-settings-and-ui-improvements.md
```

```bash
git add DEVELOPMENT.md && git commit -m "docs: record the plan workflow, remove the executed plan"
```

```bash
git push
```

Nothing is lost: `git log -- docs/superpowers/plans/` still tells the whole story, and the durable part now lives in the changelog, `DEVELOPMENT.md` and the `README.md`.

- [ ] **Step 4: Tidy the branch**

```bash
git branch -d feature/v1.10.0 && git push origin --delete feature/v1.10.0
```

---

## Task 21: an icon per tab, and a choice of what the strip shows

Task 1 gave the Settings tab a glyph plus a word while the other three carry bare text, which makes it look like a different kind of thing rather than the last tab. Every tab gets an icon, and the strip's appearance becomes a preference: **Icon**, **Text**, or **Icon + Text** (the default, and what the app does today).

Glyphs, all verified present in **both** `SegoeIcons.ttf` (Win11) and `segmdl2.ttf` (Win10), so none of them can land on screen as an empty box:

| Tab | Glyph | Name |
|---|---|---|
| Install | `&#xE896;` | Download — the tab's outcome is installing; search is the means |
| Installed | `&#xE71D;` | AllApps — the inventory of the machine |
| Updates | `&#xE777;` | UpdateRestore — literally the update icon |
| Settings | `&#xE713;` | Settings, already in use |

**Design.** `Header` stays the plain string on every tab, so it remains the accessible name and the existing header assertions keep working. The glyph goes in `Tag`, and one `HeaderTemplate` on the `TabItem` style renders both: the glyph bound to `Tag` through `RelativeSource AncestorType=TabItem`, the word bound to the header itself. That way there is one template rather than four hand-built headers, and adding a fifth tab means adding two attributes.

The mode drives two `Visibility` values held as window resources, which the template reads with `{DynamicResource}` — so switching mode repaints the strip without rebuilding anything. That needs one adjustment to the suite: check 4 currently requires **every** `DynamicResource` key in `UI.xaml` to exist in both theme files, which would reject a non-colour key. It exists to catch a missing colour, so it narrows to keys ending in `Brush`.

**Accessibility.** In **Icon** mode the header has no text, so the tab would announce nothing. `AutomationProperties.Name` on each `TabItem`, bound to its own `Header`, keeps the name regardless of what is drawn — and keeps Task 3's rule satisfied without exempting anything.

**Files:**
- Modify: `ui\UI.xaml` (`TabItem` style gains a `HeaderTemplate`; four tabs gain `Tag`, `ToolTip` and `AutomationProperties.Name`; the Settings tab loses its hand-built header; two visibility resources)
- Modify: `src\modules\App.Theme.ps1` or a new `Initialize-TabHeaders` in `App.Bootstrap.ps1` — see step 4
- Modify: `ui\UI.xaml` Settings body (a `ComboBox` under APPEARANCE)
- Modify: `src\modules\App.Bootstrap.ps1` (control list)
- Test: `tests\Test-Ui.ps1`

**Interfaces:**
- Consumes: `Get-Pref` / `Set-Pref` from Task 5.
- Produces: preference `TabHeaderStyle` with values `Icon`, `Text`, `Icon + Text` (default). `Set-TabHeaderStyle([string]$mode)` writes the two window resources and is the only thing that decides what the strip shows.

- [ ] **Step 1: Write the failing test**

In `tests\Test-Ui.ps1`, after the `OK settab` block:

```powershell
# Ogni tab ha la sua icona e un tooltip, e cosa la striscia mostra e' una scelta:
# Icon | Text | Icon + Text. Il glifo sta in Tag, la parola resta Header — cosi' Header
# continua a fare da nome accessibile e i controlli sull'ordine dei tab restano validi.
foreach ($t in $TabMain.Items) {
    if (-not $t.Tag)     { throw "il tab '$($t.Header)' non ha un glifo in Tag" }
    if (-not $t.ToolTip) { throw "il tab '$($t.Header)' non ha un tooltip" }
    $n = [System.Windows.Automation.AutomationProperties]::GetName($t)
    if (-not $n) { throw "il tab '$($t.Header)' non ha un nome accessibile: in modalita' Icon non annuncerebbe niente" }
}
# Le tre modalita' cambiano davvero cosa e' visibile.
foreach ($case in @(@('Icon', 'Visible', 'Collapsed'), @('Text', 'Collapsed', 'Visible'),
                    @('Icon + Text', 'Visible', 'Visible'))) {
    Set-TabHeaderStyle $case[0]
    if ("$($window.Resources['TabIconVis'])" -ne $case[1]) { throw "modalita' '$($case[0])': icona $($window.Resources['TabIconVis']), attesa $($case[1])" }
    if ("$($window.Resources['TabTextVis'])" -ne $case[2]) { throw "modalita' '$($case[0])': testo $($window.Resources['TabTextVis']), atteso $($case[2])" }
}
Set-TabHeaderStyle 'Icon + Text'
if ($CmbTabStyle.Items.Count -ne 3) { throw "la tendina della striscia non ha tre voci: $($CmbTabStyle.Items.Count)" }
$initSrc = Get-FunctionSource 'Initialize-TabHeaders'
if ($initSrc -notmatch "Get-Pref\s+'TabHeaderStyle'") { throw "la modalita' non si rilegge dalle preferenze" }
if ($initSrc -notmatch "Set-Pref\s+'TabHeaderStyle'") { throw "la modalita' non si salva" }
"OK tabicon 4 tab con icona, tooltip e nome accessibile; tre modalita' di visualizzazione"
```

- [ ] **Step 2: Run it and watch it fail**

Run: `powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-Ui.ps1`

Expected: FAIL with `il tab 'Install' non ha un glifo in Tag`.

- [ ] **Step 3: Narrow check 4 to the colour keys**

In `tests\Test-Ui.ps1`, section 4, the key list becomes colour-only — the check exists to catch a colour defined in one theme and not the other, and a `Visibility` held as a window resource is not that:

```powershell
# Solo le chiavi di COLORE: i temi definiscono pennelli, non tutto cio' che UI.xaml
# risolve dinamicamente (la visibilita' delle parti dell'header dei tab, per esempio,
# vive nelle Resources della finestra e la scrive il codice).
$used = [regex]::Matches((Get-Content (Join-Path $root 'ui\UI.xaml') -Raw),
                         'DynamicResource\s+(\w+Brush)') |
        ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
```

- [ ] **Step 4: Build the header template and the switch**

In `ui\UI.xaml`, add the two defaults to `Window.Resources` (the code overwrites them at startup, these are what the designer and a bare `XamlReader.Load` see):

```xml
        <!-- Cosa mostra la striscia dei tab: le scrive Set-TabHeaderStyle, qui ci sono i
             valori di partenza (Icon + Text). Sono Visibility e non colori, quindi NON
             stanno nei file di tema — il controllo sulle chiavi guarda solo i *Brush. -->
        <Visibility x:Key="TabIconVis">Visible</Visibility>
        <Visibility x:Key="TabTextVis">Visible</Visibility>
```

`Visibility` needs the system namespace mapping on the root element:

```xml
        xmlns:sys="clr-namespace:System;assembly=mscorlib"
```

and the two resources become `<Visibility>` from `System.Windows`, which the default XAML namespace already provides — no extra mapping is needed for `Visibility` itself; the `sys` mapping is only required if a plain `String` or `Double` resource is ever added.

Then, in the `TabItem` style, a `HeaderTemplate` replacing the plain `ContentSource="Header"` rendering:

```xml
            <Setter Property="HeaderTemplate">
                <Setter.Value>
                    <DataTemplate>
                        <StackPanel Orientation="Horizontal">
                            <!-- Il glifo viene da Tag della linguetta: un solo template per
                                 tutti i tab, e aggiungerne uno costa due attributi.
                                 AutomationProperties.Name="" perche' il nome lo porta la
                                 linguetta stessa: qui il glifo e' decorativo. -->
                            <TextBlock Text="{Binding Tag, RelativeSource={RelativeSource AncestorType=TabItem}}"
                                       FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets"
                                       FontSize="14" VerticalAlignment="Center"
                                       AutomationProperties.Name=""
                                       Visibility="{DynamicResource TabIconVis}"/>
                            <!-- Margine sinistro solo quando c'e' anche l'icona: in modalita'
                                 Text la parola resterebbe spostata di 7px. -->
                            <TextBlock Text="{Binding}" VerticalAlignment="Center"
                                       Visibility="{DynamicResource TabTextVis}">
                                <TextBlock.Style>
                                    <Style TargetType="TextBlock">
                                        <Setter Property="Margin" Value="7,0,0,0"/>
                                        <Style.Triggers>
                                            <DataTrigger Binding="{DynamicResource TabIconVis}" Value="Collapsed">
                                                <Setter Property="Margin" Value="0"/>
                                            </DataTrigger>
                                        </Style.Triggers>
                                    </Style>
                                </TextBlock.Style>
                            </TextBlock>
                        </StackPanel>
                    </DataTemplate>
                </Setter.Value>
            </Setter>
```

The four tabs then carry the glyph, the tooltip and the accessible name, and the Settings tab drops the hand-built `TabItem.Header` block Task 1 gave it:

```xml
                <TabItem x:Name="TabInstall" Header="Install" Tag="&#xE896;"
                         AutomationProperties.Name="Install"
                         ToolTip="Search the winget catalogue as you type and install what you pick"/>
```

```xml
                <TabItem x:Name="TabInstalled" Header="Installed" Tag="&#xE71D;"
                         AutomationProperties.Name="Installed"
                         ToolTip="Everything installed on this machine: filter it, pin it, uninstall it"/>
```

```xml
                <TabItem x:Name="TabUpdates" Header="Updates" Tag="&#xE777;" IsSelected="True"
                         AutomationProperties.Name="Updates"
                         ToolTip="Packages with a newer version available, and the queue that updates them"/>
```

```xml
                <TabItem x:Name="TabSettings" Header="Settings" Tag="&#xE713;" DockPanel.Dock="Right" Margin="0,0,-2,0"
                         AutomationProperties.Name="Settings"
                         ToolTip="Theme, tab strip, version and updates"/>
```

- [ ] **Step 5: The switch and its preference**

A new `Initialize-TabHeaders` in `src\modules\App.Bootstrap.ps1`, called from `Start-App` next to the other `Initialize-*`:

```powershell
# Cosa mostra la striscia dei tab. Due Visibility nelle Resources della finestra invece di
# otto controlli nominati: il template dell'header le legge con DynamicResource, quindi
# riscriverle ridisegna la striscia senza ricostruire niente.
$script:tabStyles = @('Icon', 'Text', 'Icon + Text')

function Set-TabHeaderStyle([string]$mode) {
    $window.Resources['TabIconVis'] = if ($mode -eq 'Text') { [System.Windows.Visibility]::Collapsed } else { [System.Windows.Visibility]::Visible }
    $window.Resources['TabTextVis'] = if ($mode -eq 'Icon') { [System.Windows.Visibility]::Collapsed } else { [System.Windows.Visibility]::Visible }
}

function Initialize-TabHeaders {
    $saved = [string](Get-Pref 'TabHeaderStyle' 'Icon + Text')
    if ($saved -notin $script:tabStyles) { $saved = 'Icon + Text' }
    foreach ($m in $script:tabStyles) { [void]$CmbTabStyle.Items.Add($m) }
    $CmbTabStyle.SelectedItem = $saved
    Set-TabHeaderStyle $saved
    # NB: SelectedItem si imposta PRIMA di agganciare l'handler, altrimenti la scelta
    # ripristinata verrebbe risalvata a ogni avvio.
    $CmbTabStyle.Add_SelectionChanged({
        $chosen = [string]$CmbTabStyle.SelectedItem
        if (-not $chosen) { return }
        Set-TabHeaderStyle $chosen
        Set-Pref 'TabHeaderStyle' $chosen
    })
}
```

- [ ] **Step 6: The control in Settings**

In the APPEARANCE section, a row under Theme — same two-column grid Task 7 introduces:

```xml
                            <TextBlock Grid.Row="2" Grid.Column="0" Text="Tab strip" Margin="0,0,12,18"
                                       VerticalAlignment="Center" Foreground="{DynamicResource FgBrush}"/>
                            <ComboBox Grid.Row="2" Grid.Column="1" x:Name="CmbTabStyle" Width="180"
                                      HorizontalAlignment="Left" Margin="0,0,0,18"
                                      ToolTip="What the tabs show: the icon, the name, or both"/>
```

Add `'CmbTabStyle'` to the control list in `Start-App`. If Task 7 has not landed yet, put the row in the existing `StackPanel` instead and let Task 7 move it.

- [ ] **Step 7: Run the tests**

Run: `powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-Ui.ps1`

Expected: PASS with `OK tabicon`. Watch `OK settab` and `OK tabedge` too: the header template changes how wide each tab is, and `OK tabedge` measures the last one against the frame.

- [ ] **Step 8: Look at the three modes**

```bash
powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\src\main.ps1
```

Switch between Icon, Text and Icon + Text in Settings. In **Icon** mode check the tabs are still wide enough to click comfortably and the Settings tab stays flush with the frame; in **Text** mode check the word is not left with the icon's 7px gap; hover each tab for its tooltip. Then restart and confirm the choice came back.

- [ ] **Step 9: Docs and commit**

`README.md`, in the Settings section: "**Tab strip** chooses whether the tabs show their icon, their name, or both."

`DEVELOPMENT.md`, next to the re-templated controls: the header is one `HeaderTemplate` reading the glyph from each tab's `Tag`, the mode is two `Visibility` values in the window's resources read with `DynamicResource`, and `AutomationProperties.Name` on the `TabItem` is what keeps icon-only mode announceable. Note that check 4 only looks at `*Brush` keys for this reason.

```bash
git add ui/UI.xaml src/modules/App.Bootstrap.ps1 tests/Test-Ui.ps1 README.md DEVELOPMENT.md CHANGELOG.md
git commit -m "feat(ui): an icon per tab, with icon/text/both as a preference"
```

```bash
git push
```

---

## Execution order

0. **Setup, once.** `git switch -c feature/v1.10.0`; commit `CLAUDE.md` and `docs/` so the plan travels with the work; `git push -u origin feature/v1.10.0`. Confirm `gh api repos/FedeB2160/WinGetStudio --jq .permissions` reports `"push": true` — without it neither the push nor the release will work, and finding out at Task 14 is the wrong time.
1. **Task 1** — tab structure. First, always: it deletes a module, and Tasks 2, 6 and 7 all edit XAML that it moves.
2. **Task 2, Task 15, Task 3** — the measured defects: contrast, white scrollbars, accessible names. Self-contained, no behaviour change.
3. **Task 4** — the winget concurrency hole. Needs a real run, not just the suite, and everything in step 4 depends on its choke point.
4. **Task 16, Task 17, Task 18** — in this order. All three touch `Set-UpdatesBusy` and `Refresh-SelectionState`; 18 reads the `$script:queueVerb` that 17 introduces.
5. **Task 5, Task 6, Task 7, Task 21** — in this order: `Get-Pref` first, then the checkbox that uses it, then the layout that absorbs the checkbox and rewrites About, then the tab icons and their preference, which need both `Get-Pref` and that layout.
6. **Task 8, 9, 10, 11, 12** — polish and cleanup, any order.
7. **Task 13** — consistency and hardening. Optional.
8. **Task 14** — release: version, changelog promotion, merge into `main`, tag, GitHub release, and the end-to-end proof that a v1.9.0 install updates itself to it.
9. **Task 19** — the winget manifest, so the community package follows the release rather than lagging a version behind it.
10. **Task 20** — verification against the decisions, the workflow rule into `DEVELOPMENT.md`, the plan file deleted, the branch tidied.

Stopping early is fine, and the cut lines are these: **1 through 4** fix something measured or broken. **16 through 18** are the behaviour that was asked for. **5 onward** is improvement rather than repair. **14, 19 and 20** are one unit — shipping a release without the manifest update leaves winget users behind, and deleting the plan before the verification of Task 20 throws away the only checklist that says whether the result matches what was decided.

## Self-review notes

- **Coverage.** Every finding from the 2026-08-04 review maps to a task: T1→Task 1, T2→Task 1, A1/A2/A5→Task 2, A3→removed by Task 1, A4→Task 3, B1/B2/B3→Task 4, B4/B5→Task 13, C1→Task 5, C2→Task 6, C3→removed by Task 1, C4/C5→Task 7, D1→Task 8, D2→Task 9, D3→landed in Task 18 (the “press Check” line is what explains the locked button, so it belongs with it), D5→Task 10, D4→Task 5 (folded into the `Unknown` handler, where the rescan belongs), D6→Task 11, E1/E2→Task 12. The additions requested on 2026-08-23 map to: About copy→Task 7, white scrollbars→Task 15, flags and pins during a queue→Task 16, Update/Cancel→Task 17, stale lock→Task 18. The tail of the cycle: Task 19 brings the winget manifest along behind the release, and Task 20 checks the result against the decisions, records the workflow rule in DEVELOPMENT.md, and deletes this file.
- **Names used consistently across tasks.** `Test-WinGetBusy` (Task 4), `Get-Pref` / `Set-Pref` / `$PrefsKey` (Task 5), `Register-GridRefresh($Target, $RefreshFunction)` (Task 12), controls `$TabInstall` / `$TabInstalled` / `$TabUpdates` / `$TabSettings` (Task 1), `$ChkAutoCheck` (Task 6), `$LogSplitter` (Task 9), theme key `AccentFgBrush` (Task 2).
- **Ordering constraints that are real.** Task 1 must come first: it deletes a module and removes the need for A3 and C3, and Tasks 2, 6 and 7 all edit XAML that Task 1 moves. Task 5 must precede Task 6 (`Get-Pref` / `Set-Pref`) and Task 7 (which absorbs the checkbox Task 6 adds — if you do Task 7 before Task 6, add the checkbox there instead). Task 4 should precede Task 11, whose F5 relies on `Load-*` refusing to stack. Tasks 8-13 are independent of each other.
- **Deliberately not planned.** An opening animation for the settings view, a configurable accent colour, grid virtualisation (`DataGrid` does it already), access keys on buttons, and the 44px minimum touch target (a mobile guideline; this is a mouse-and-keyboard desktop app).
