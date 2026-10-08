# Graph Report - .  (2026-10-08)

## Corpus Check
- 27 files · ~62,286 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 339 nodes · 588 edges · 42 communities (31 shown, 11 thin omitted)
- Extraction: 75% EXTRACTED · 25% INFERRED · 0% AMBIGUOUS · INFERRED: 149 edges (avg confidence: 0.81)
- Token cost: 226,209 input · 0 output

## Community Hubs (Navigation)
- Export and Import
- Grid Rows, Themes and Layout ADRs
- Grid Row Bindings
- Bootstrap and XAML Loading
- Changelog and Release History
- Status Text Controls
- Project Guidance Files
- Busy State and Queue
- Running winget
- UI Test Suite
- Install Tab
- Preferences and Theme
- Process Docs and Core ADRs
- winget Table Parsing
- Background Jobs
- Spinners
- Tab Items
- Parser Tests and Fixtures
- Pin Context Menus
- Early winget Manifests
- Tooltip Border
- CI Workflow
- Settings Checkboxes
- Data Grids
- Progress Track Parts
- Text Boxes
- Settings Combo Boxes
- Header Grippers
- Release and Signing Process
- Dark Theme
- Light Theme
- About Table
- Check Mark Path
- ComboBox Popup
- Tab Content Host
- Progress Bar
- Main Tab Control
- ADR Template
- Manifest v1.9.0

## God Nodes (most connected - your core abstractions)
1. `Window` - 75 edges
2. `Write-Log()` - 18 edges
3. `Start-App()` - 16 edges
4. `Load-Upgrades()` - 13 edges
5. `TextBlock` - 13 edges
6. `DEVELOPMENT.md (procedures)` - 13 edges
7. `Start-WinGetQueue()` - 12 edges
8. `Load-Installed()` - 12 edges
9. `Button` - 12 edges
10. `README.md (user guide)` - 12 edges

## Surprising Connections (you probably didn't know these)
- `ADR 0003 Only one winget process at a time` --semantically_similar_to--> `Test-Ui.ps1 and Test-InvokeWinGet.ps1 suites`  [INFERRED] [semantically similar]
  docs/adr/0003-only-one-winget-process-at-a-time.md → DEVELOPMENT.md
- `Administrator rights requirement` --conceptually_related_to--> `ADR 0002 Always elevated`  [INFERRED]
  README.md → docs/adr/0002-always-elevated.md
- `v1.9.0 rename to WinGet Studio and three tabs` --conceptually_related_to--> `ADR 0001 One exe built from modules`  [INFERRED]
  CHANGELOG.md → docs/adr/0001-one-exe-built-from-modules.md
- `Get-LatestRelease()` --calls--> `Invoke-RestMethod()`  [INFERRED]
  src/modules/App.Update.ps1 → tests/Test-Ui.ps1
- `DEVELOPMENT.md (procedures)` --references--> `Windows CI workflow`  [EXTRACTED]
  DEVELOPMENT.md → .github/workflows/ci.yml

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Single-winget-process guard mechanism** — docs_adr_0003_only_one_winget_process_at_a_time_set_appbusy, docs_adr_0003_only_one_winget_process_at_a_time_test_winget_busy, docs_adr_0003_only_one_winget_process_at_a_time_start_winget_queue, docs_adr_0003_only_one_winget_process_at_a_time_queueverb, docs_adr_0003_only_one_winget_process_at_a_time_cooperative_cancel [EXTRACTED 1.00]
- **winget read pipeline (run, parse, result)** — docs_adr_0004_how_winget_is_run_invoke_winget_read, docs_adr_0006_parsing_winget_tables_by_column_position_get_winget_table, docs_adr_0005_reads_return_a_result_not_a_list_readers, docs_adr_0005_reads_return_a_result_not_a_list_result_object [EXTRACTED 1.00]
- **Runspace job machinery** — docs_adr_0008_background_work_in_runspaces_start_background_job, docs_adr_0008_background_work_in_runspaces_ui_helper, docs_adr_0008_background_work_in_runspaces_functions_vars, docs_adr_0008_background_work_in_runspaces_dispatcher_timer, docs_adr_0008_background_work_in_runspaces_stop_all_jobs [EXTRACTED 1.00]
- **Release chain: signing, installer, self-update, winget package** — docs_adr_0012_signing, docs_adr_0013_self_update, docs_adr_0014_installer_alongside_the_portable_exe, docs_adr_0015_winget_package_portable_then_inno [INFERRED 0.85]
- **winget manifest releases 1.10.1 to 1.10.3 (portable)** — winget_1_10_1_fedeb2160_wingetstudio, winget_1_10_2_fedeb2160_wingetstudio, winget_1_10_3_fedeb2160_wingetstudio [INFERRED 0.75]
- **WinGet Manifest v1.10.0** — winget_1_10_0_installer, winget_1_10_0_locale [EXTRACTED 1.00]
- **WinGet Manifest v1.9.0** — winget_1_9_0_installer, winget_1_9_0_locale [EXTRACTED 1.00]

## Communities (42 total, 11 thin omitted)

### Community 0 - "Export and Import"
Cohesion: 0.14
Nodes (36): Get-ImportPackageCount(), Initialize-Backup(), Invoke-PackageExport(), Invoke-PackageImport(), Start-Export(), Start-Import(), Request-QueueCancel(), Start-BackgroundJob() (+28 more)

### Community 1 - "Grid Rows, Themes and Layout ADRs"
Cohesion: 0.07
Nodes (40): ADR 0009 Grid rows are WgtRow, WgtRow (INotifyPropertyChanged grid row class), ADR 0010 Themes, Measured contrast floors and surface step, Glyphs written as [char]0xE706 (PS 5.1), Re-templated controls (CheckBox, header, ComboBox, ScrollBar), Theme.Light/Dark dictionaries with DynamicResource, ADR 0011 Window layout (+32 more)

### Community 2 - "Grid Row Bindings"
Cohesion: 0.11
Nodes (26): ActualWidth, Available, Id, IsDropDownOpen, IsReadOnly, Name, Pinned, Selected (+18 more)

### Community 3 - "Bootstrap and XAML Loading"
Cohesion: 0.16
Nodes (18): Resolve-Asset(), Get-XamlText(), Initialize-TabHeaders(), Read-Xaml(), Set-TabHeaderStyle(), Start-App(), Clear-OldExe(), Get-InstallChannel() (+10 more)

### Community 4 - "Changelog and Release History"
Cohesion: 0.15
Nodes (17): CHANGELOG.md (version history), v1.0.0 WinGet Update Tool (withdrawn), v1.10.1 winget-portable self-replace fix, v1.11.0 installer release, v1.9.0 rename to WinGet Studio and three tabs, Four install channels (source, winget-portable, installed, portable), Test-ElevatedUserMismatch warning, README.md (user guide) (+9 more)

### Community 5 - "Status Text Controls"
Cohesion: 0.13
Nodes (15): StatusDetail, cellIcon, pinIcon, TxtAvailable, TxtEmpty, TxtInstalledCount, TxtInstalledEmpty, TxtInstalledInfo (+7 more)

### Community 6 - "Project Guidance Files"
Cohesion: 0.18
Nodes (13): CLAUDE.md (project guidance), graphify-out knowledge graph and manifest, Module roles (WinGet.Exec, Parse, App.Ui, Jobs, Prefs, Tab.*, Bootstrap), Glyphs as [char]0xE706, no backtick-u escape (PowerShell 5.1), Signing convention (never generate replacement cert), Themes via DynamicResource and re-templated controls, WgtRow (INotifyPropertyChanged grid row class), ADR 0001 One exe built from modules (+5 more)

### Community 7 - "Busy State and Queue"
Cohesion: 0.19
Nodes (13): v1.10.0 Settings/About tabs, Cancel, single winget choke point, ADR 0003 Only one winget process at a time, Cooperative cancel via synchronized hashtable, $script:queueVerb publishes running queue, Set-AppBusy and Register-BusyHandler, Start-WinGetQueue single choke point, Test-WinGetBusy (busy or search in flight), Failed pin read re-applies $script:lastPinIds (+5 more)

### Community 8 - "Running winget"
Cohesion: 0.17
Nodes (13): v1.10.3 UTF-8 first-scan and temp cleanup fixes, Issue #12 user-scope uninstall blocked when elevated (0x8A15007D), Clear-WinGetTempFiles startup sweep, --disable-interactivity on queue commands, Invoke-WinGet (cmd redirect to temp files, WaitForExit), Invoke-WinGetRead (direct Process.Start, UTF-8), Unbalanced-quote guard on cmd command lines, $wingetPath resolved once and passed via -Vars (+5 more)

### Community 9 - "UI Test Suite"
Cohesion: 0.18
Nodes (3): Get-Contrast(), Get-Luminance(), Invoke-RestMethod()

### Community 10 - "Install Tab"
Cohesion: 0.47
Nodes (9): Initialize-InstallTab(), Install-Rows(), Refresh-InstallState(), Set-InstallBusy(), Show-SearchMessage(), Start-InstallSelected(), Start-Search(), Test-ElevatedUserMismatch() (+1 more)

### Community 11 - "Preferences and Theme"
Cohesion: 0.42
Nodes (9): v1.10.2 read failures, blocking pins, CI, DEVELOPMENT.md (procedures), ADR 0002 Always elevated, ADR 0004 How winget is run, ADR 0005 Reads return a result, not a list, ADR 0006 Parsing winget tables by column position, ADR 0007 Pins are blocking, ADR 0008 Background work in runspaces (+1 more)

### Community 12 - "Process Docs and Core ADRs"
Cohesion: 0.43
Nodes (6): Get-Pref(), Set-Pref(), Initialize-Theme(), Set-Theme(), Set-TitleBarDark(), Test-SystemDark()

### Community 13 - "winget Table Parsing"
Cohesion: 0.52
Nodes (6): Get-Field(), Get-WinGetInstalled(), Get-WinGetSearch(), Get-WinGetTable(), Get-WinGetUpgrades(), Invoke-WinGetRead()

### Community 14 - "Background Jobs"
Cohesion: 0.33
Nodes (6): Dot-sourcing creates no scope; Start-App uses $script:, GetNewClosure scope trap, DispatcherTimer 200 ms completion polling, Start-BackgroundJob (STA runspace, OnDone on UI thread), Stop-AllJobs and $script:jobs tracking, UI{} Dispatcher.Invoke helper and LogUI

### Community 15 - "Spinners"
Cohesion: 0.33
Nodes (6): cellSpinner, InstalledSpinner, SearchSpinner, TopSpinner, UpdateSpinner, Control

### Community 16 - "Tab Items"
Cohesion: 0.33
Nodes (6): TabAbout, TabInstall, TabInstalled, TabSettings, TabUpdates, TabItem

### Community 17 - "Parser Tests and Fixtures"
Cohesion: 0.40
Nodes (5): Test scripts Test-Ui.ps1 and Test-InvokeWinGet.ps1, Four parser fixtures in Test-InvokeWinGet.ps1, Get-WinGetTable positional parser, -MaxColumns parameter, Tables accepted from three columns up

### Community 18 - "Pin Context Menus"
Cohesion: 0.40
Nodes (5): MenuPinInstalled, MenuPinUpdates, MenuUnpinInstalled, MenuUnpinUpdates, MenuItem

### Community 19 - "Early winget Manifests"
Cohesion: 0.40
Nodes (4): WinGetStudio Installer v1.10.0, WinGetStudio Locale v1.10.0, WinGetStudio Installer v1.9.0, WinGetStudio Locale v1.9.0

### Community 20 - "Tooltip Border"
Cohesion: 0.50
Nodes (4): (AutomationProperties.HelpText), bd, Box, Border

### Community 21 - "CI Workflow"
Cohesion: 0.50
Nodes (4): Test-Ui.ps1 and Test-InvokeWinGet.ps1 suites, Windows CI workflow, CI build job (exe and setup, unsigned artifacts), CI tests job (PS 5.1 and WPF, offline)

### Community 23 - "Settings Checkboxes"
Cohesion: 0.50
Nodes (4): ChkAutoCheck, ChkStore, ChkUnknown, CheckBox

### Community 24 - "Data Grids"
Cohesion: 0.50
Nodes (4): Grid, GridInstalled, GridSearch, DataGrid

### Community 25 - "Progress Track Parts"
Cohesion: 0.50
Nodes (4): PART_Indicator, PART_Track, Rectangle, Track

### Community 26 - "Text Boxes"
Cohesion: 0.50
Nodes (4): TxtFilter, TxtLog, TxtSearch, TextBox

### Community 27 - "Settings Combo Boxes"
Cohesion: 0.67
Nodes (3): CmbTabStyle, CmbTheme, ComboBox

### Community 28 - "Header Grippers"
Cohesion: 0.67
Nodes (3): PART_LeftHeaderGripper, PART_RightHeaderGripper, Thumb

## Knowledge Gaps
- **61 isolated node(s):** `ResourceDictionary`, `ResourceDictionary`, `WinGet Manifest v1.10.0`, `WinGet Manifest v1.9.0`, `WinGetStudio Locale v1.10.0` (+56 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **11 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Window` connect `Grid Row Bindings` to `About Table`, `Check Mark Path`, `ComboBox Popup`, `Tab Content Host`, `Progress Bar`, `Status Text Controls`, `Main Tab Control`, `Spinners`, `Tab Items`, `Pin Context Menus`, `Tooltip Border`, `Settings Checkboxes`, `Data Grids`, `Progress Track Parts`, `Text Boxes`, `Settings Combo Boxes`, `Header Grippers`?**
  _High betweenness centrality (0.077) - this node is a cross-community bridge._
- **Why does `DEVELOPMENT.md (procedures)` connect `Preferences and Theme` to `Grid Rows, Themes and Layout ADRs`, `Changelog and Release History`, `Project Guidance Files`, `Busy State and Queue`, `CI Workflow`?**
  _High betweenness centrality (0.070) - this node is a cross-community bridge._
- **Why does `ADR 0010 Themes` connect `Grid Rows, Themes and Layout ADRs` to `Preferences and Theme`?**
  _High betweenness centrality (0.052) - this node is a cross-community bridge._
- **Are the 17 inferred relationships involving `Write-Log()` (e.g. with `Invoke-PackageExport()` and `Invoke-PackageImport()`) actually correct?**
  _`Write-Log()` has 17 INFERRED edges - model-reasoned connections that need verification._
- **Are the 13 inferred relationships involving `Start-App()` (e.g. with `Resolve-Asset()` and `Initialize-Backup()`) actually correct?**
  _`Start-App()` has 13 INFERRED edges - model-reasoned connections that need verification._
- **Are the 10 inferred relationships involving `Load-Upgrades()` (e.g. with `Start-App()` and `Start-BackgroundJob()`) actually correct?**
  _`Load-Upgrades()` has 10 INFERRED edges - model-reasoned connections that need verification._
- **What connects `ResourceDictionary`, `ResourceDictionary`, `WinGet Manifest v1.10.0` to the rest of the system?**
  _61 weakly-connected nodes found - possible documentation gaps or missing edges._