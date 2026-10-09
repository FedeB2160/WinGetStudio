# Graph Report - .  (2026-10-09)

## Corpus Check
- 64 files · ~64,894 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 361 nodes · 590 edges · 42 communities (27 shown, 15 thin omitted)
- Extraction: 75% EXTRACTED · 25% INFERRED · 0% AMBIGUOUS · INFERRED: 148 edges (avg confidence: 0.8)
- Token cost: 104,087 input · 0 output

## Community Hubs (Navigation)
- Project Guidance and Conventions
- Backup Export and Import
- Grid Rows and Themes
- Changelog and Releases
- Grid Row Properties
- Bootstrap and XAML Loading
- Status Cells and Counters
- UI Test Helpers
- Install Tab
- Preferences and Theme
- WinGet Table Parsing
- Icon Generator
- Spinners
- Tab Items
- Pin Context Menus
- WinGet Manifests 1.9-1.10
- Border Templates
- Settings Checkboxes
- Data Grids
- Progress Bar Template
- Text Boxes
- Windows CI
- Combo Boxes
- Header Grippers
- Update Queue Cancel
- Tabs Layout Fixes
- Temp Files and UTF-8
- Single WinGet Process
- Dark Theme
- Light Theme
- About Table
- Checkbox Mark
- Combo Popup
- Tab Content Host
- Progress
- Main Tab Control
- ADR Template
- Manifest 1.10.0
- Manifest 1.9.0

## God Nodes (most connected - your core abstractions)
1. `Window` - 75 edges
2. `Write-Log()` - 18 edges
3. `Start-App()` - 16 edges
4. `Load-Upgrades()` - 13 edges
5. `TextBlock` - 13 edges
6. `Start-WinGetQueue()` - 12 edges
7. `Load-Installed()` - 12 edges
8. `Button` - 12 edges
9. `Start-BackgroundJob()` - 11 edges
10. `Set-AppBusy()` - 11 edges

## Surprising Connections (you probably didn't know these)
- `Defender Wacatac !ml false positive` --semantically_similar_to--> `v1.10.1: winget-portable copy must not self-replace`  [INFERRED] [semantically similar]
  README.md → CHANGELOG.md
- `Cooperative cancel of update queue` --semantically_similar_to--> `Update locked until next Check`  [INFERRED] [semantically similar]
  CHANGELOG.md → README.md
- `Get-LatestRelease()` --calls--> `Invoke-RestMethod()`  [INFERRED]
  src/modules/App.Update.ps1 → tests/Test-Ui.ps1
- `winget manifest 1.10.1 installer (portable)` --references--> `ADR 0015 winget package: portable, then inno`  [INFERRED]
  winget/1.10.1/FedeB2160.WinGetStudio.installer.yaml → docs/adr/0015-winget-package-portable-then-inno.md
- `winget manifest 1.10.2 installer (portable)` --references--> `ADR 0015 winget package: portable, then inno`  [INFERRED]
  winget/1.10.2/FedeB2160.WinGetStudio.installer.yaml → docs/adr/0015-winget-package-portable-then-inno.md

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **App icon pipeline: script, frames, detail levels, pixel snapping** — docs_adr_0017_app_icon_drawn_in_code_icon_ps1, docs_adr_0017_app_icon_drawn_in_code_fourteen_frames, docs_adr_0017_app_icon_drawn_in_code_levels_of_detail, docs_adr_0017_app_icon_drawn_in_code_pixel_snapping, docs_adr_0017_app_icon_drawn_in_code_icon_design [EXTRACTED 1.00]
- **Release flow: version, signing, assets, winget-pkgs** — development_single_version_source, development_signing_procedure, development_release_procedure, development_winget_pkgs_publishing, changelog_v1_11_0_installer [INFERRED 0.85]
- **Self-update behaviour per install channel** — readme_automatic_updates, changelog_v1_11_0_installer, changelog_winget_portable_self_replace_bug, development_release_procedure [INFERRED 0.85]
- **Single-winget-process guard mechanism** — docs_adr_0003_only_one_winget_process_at_a_time_set_appbusy, docs_adr_0003_only_one_winget_process_at_a_time_test_winget_busy, docs_adr_0003_only_one_winget_process_at_a_time_start_winget_queue, docs_adr_0003_only_one_winget_process_at_a_time_queueverb, docs_adr_0003_only_one_winget_process_at_a_time_cooperative_cancel [EXTRACTED 1.00]
- **winget read pipeline (run, parse, result)** — docs_adr_0004_how_winget_is_run_invoke_winget_read, docs_adr_0006_parsing_winget_tables_by_column_position_get_winget_table, docs_adr_0005_reads_return_a_result_not_a_list_readers, docs_adr_0005_reads_return_a_result_not_a_list_result_object [EXTRACTED 1.00]
- **Runspace job machinery** — docs_adr_0008_background_work_in_runspaces_start_background_job, docs_adr_0008_background_work_in_runspaces_ui_helper, docs_adr_0008_background_work_in_runspaces_functions_vars, docs_adr_0008_background_work_in_runspaces_dispatcher_timer, docs_adr_0008_background_work_in_runspaces_stop_all_jobs [EXTRACTED 1.00]
- **Release chain: signing, installer, self-update, winget package** — docs_adr_0012_signing, docs_adr_0013_self_update, docs_adr_0014_installer_alongside_the_portable_exe, docs_adr_0015_winget_package_portable_then_inno [INFERRED 0.85]
- **winget manifest releases 1.10.1 to 1.10.3 (portable)** — winget_1_10_1_fedeb2160_wingetstudio, winget_1_10_2_fedeb2160_wingetstudio, winget_1_10_3_fedeb2160_wingetstudio [INFERRED 0.75]
- **WinGet Manifest v1.10.0** — winget_1_10_0_installer, winget_1_10_0_locale [EXTRACTED 1.00]
- **WinGet Manifest v1.9.0** — winget_1_9_0_installer, winget_1_9_0_locale [EXTRACTED 1.00]

## Communities (42 total, 15 thin omitted)

### Community 0 - "Project Guidance and Conventions"
Cohesion: 0.05
Nodes (54): CLAUDE.md (project guidance), graphify-out knowledge graph and manifest, Four install channels (source, winget-portable, installed, portable), Module roles (WinGet.Exec, Parse, App.Ui, Jobs, Prefs, Tab.*, Bootstrap), Glyphs as [char]0xE706, no backtick-u escape (PowerShell 5.1), Signing convention (never generate replacement cert), Test scripts Test-Ui.ps1 and Test-InvokeWinGet.ps1, Themes via DynamicResource and re-templated controls (+46 more)

### Community 1 - "Backup Export and Import"
Cohesion: 0.14
Nodes (36): Get-ImportPackageCount(), Initialize-Backup(), Invoke-PackageExport(), Invoke-PackageImport(), Start-Export(), Start-Import(), Request-QueueCancel(), Start-BackgroundJob() (+28 more)

### Community 2 - "Grid Rows and Themes"
Cohesion: 0.07
Nodes (40): ADR 0009 Grid rows are WgtRow, WgtRow (INotifyPropertyChanged grid row class), ADR 0010 Themes, Measured contrast floors and surface step, Glyphs written as [char]0xE706 (PS 5.1), Re-templated controls (CheckBox, header, ComboBox, ScrollBar), Theme.Light/Dark dictionaries with DynamicResource, ADR 0011 Window layout (+32 more)

### Community 3 - "Changelog and Releases"
Cohesion: 0.08
Nodes (29): v1.10.2: blocking pins, Theme contrast measured by tests, Unreleased: new app icon, v1.9.0: renamed from WinGet Update Tool, v1.11.0: installer alongside portable exe, v1.10.2: winget failure is not an empty list, v1.10.1: winget-portable copy must not self-replace, ADR index and rule (+21 more)

### Community 4 - "Grid Row Properties"
Cohesion: 0.11
Nodes (26): ActualWidth, Available, Id, IsDropDownOpen, IsReadOnly, Name, Pinned, Selected (+18 more)

### Community 5 - "Bootstrap and XAML Loading"
Cohesion: 0.16
Nodes (18): Resolve-Asset(), Get-XamlText(), Initialize-TabHeaders(), Read-Xaml(), Set-TabHeaderStyle(), Start-App(), Clear-OldExe(), Get-InstallChannel() (+10 more)

### Community 6 - "Status Cells and Counters"
Cohesion: 0.13
Nodes (15): StatusDetail, cellIcon, pinIcon, TxtAvailable, TxtEmpty, TxtInstalledCount, TxtInstalledEmpty, TxtInstalledInfo (+7 more)

### Community 7 - "UI Test Helpers"
Cohesion: 0.18
Nodes (3): Get-Contrast(), Get-Luminance(), Invoke-RestMethod()

### Community 8 - "Install Tab"
Cohesion: 0.47
Nodes (9): Initialize-InstallTab(), Install-Rows(), Refresh-InstallState(), Set-InstallBusy(), Show-SearchMessage(), Start-InstallSelected(), Start-Search(), Test-ElevatedUserMismatch() (+1 more)

### Community 9 - "Preferences and Theme"
Cohesion: 0.43
Nodes (6): Get-Pref(), Set-Pref(), Initialize-Theme(), Set-Theme(), Set-TitleBarDark(), Test-SystemDark()

### Community 10 - "WinGet Table Parsing"
Cohesion: 0.52
Nodes (6): Get-Field(), Get-WinGetInstalled(), Get-WinGetSearch(), Get-WinGetTable(), Get-WinGetUpgrades(), Invoke-WinGetRead()

### Community 11 - "Icon Generator"
Cohesion: 0.53
Nodes (4): New-IconPng(), New-Pen(), New-Shape(), Snap()

### Community 12 - "Spinners"
Cohesion: 0.33
Nodes (6): cellSpinner, InstalledSpinner, SearchSpinner, TopSpinner, UpdateSpinner, Control

### Community 13 - "Tab Items"
Cohesion: 0.33
Nodes (6): TabAbout, TabInstall, TabInstalled, TabSettings, TabUpdates, TabItem

### Community 14 - "Pin Context Menus"
Cohesion: 0.40
Nodes (5): MenuPinInstalled, MenuPinUpdates, MenuUnpinInstalled, MenuUnpinUpdates, MenuItem

### Community 15 - "WinGet Manifests 1.9-1.10"
Cohesion: 0.40
Nodes (4): WinGetStudio Installer v1.10.0, WinGetStudio Locale v1.10.0, WinGetStudio Installer v1.9.0, WinGetStudio Locale v1.9.0

### Community 16 - "Border Templates"
Cohesion: 0.50
Nodes (4): (AutomationProperties.HelpText), bd, Box, Border

### Community 18 - "Settings Checkboxes"
Cohesion: 0.50
Nodes (4): ChkAutoCheck, ChkStore, ChkUnknown, CheckBox

### Community 19 - "Data Grids"
Cohesion: 0.50
Nodes (4): Grid, GridInstalled, GridSearch, DataGrid

### Community 20 - "Progress Bar Template"
Cohesion: 0.50
Nodes (4): PART_Indicator, PART_Track, Rectangle, Track

### Community 21 - "Text Boxes"
Cohesion: 0.50
Nodes (4): TxtFilter, TxtLog, TxtSearch, TextBox

### Community 22 - "Windows CI"
Cohesion: 0.67
Nodes (3): Windows CI workflow, CI build job (exe and setup, unsigned artifacts), CI tests job (PS 5.1 and WPF, offline)

### Community 23 - "Combo Boxes"
Cohesion: 0.67
Nodes (3): CmbTabStyle, CmbTheme, ComboBox

### Community 24 - "Header Grippers"
Cohesion: 0.67
Nodes (3): PART_LeftHeaderGripper, PART_RightHeaderGripper, Thumb

## Knowledge Gaps
- **75 isolated node(s):** `ResourceDictionary`, `ResourceDictionary`, `WinGet Manifest v1.10.0`, `WinGet Manifest v1.9.0`, `WinGetStudio Locale v1.10.0` (+70 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **15 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Window` connect `Grid Row Properties` to `Checkbox Mark`, `Combo Popup`, `Tab Content Host`, `Progress`, `Main Tab Control`, `Status Cells and Counters`, `Spinners`, `Tab Items`, `Pin Context Menus`, `Border Templates`, `Settings Checkboxes`, `Data Grids`, `Progress Bar Template`, `Text Boxes`, `Combo Boxes`, `Header Grippers`, `About Table`?**
  _High betweenness centrality (0.068) - this node is a cross-community bridge._
- **Why does `Start-App()` connect `Bootstrap and XAML Loading` to `Install Tab`, `Backup Export and Import`?**
  _High betweenness centrality (0.030) - this node is a cross-community bridge._
- **Why does `CLAUDE.md (project guidance)` connect `Project Guidance and Conventions` to `Changelog and Releases`?**
  _High betweenness centrality (0.023) - this node is a cross-community bridge._
- **Are the 17 inferred relationships involving `Write-Log()` (e.g. with `Invoke-PackageExport()` and `Invoke-PackageImport()`) actually correct?**
  _`Write-Log()` has 17 INFERRED edges - model-reasoned connections that need verification._
- **Are the 13 inferred relationships involving `Start-App()` (e.g. with `Resolve-Asset()` and `Initialize-Backup()`) actually correct?**
  _`Start-App()` has 13 INFERRED edges - model-reasoned connections that need verification._
- **Are the 10 inferred relationships involving `Load-Upgrades()` (e.g. with `Start-App()` and `Start-BackgroundJob()`) actually correct?**
  _`Load-Upgrades()` has 10 INFERRED edges - model-reasoned connections that need verification._
- **What connects `ResourceDictionary`, `ResourceDictionary`, `WinGet Manifest v1.10.0` to the rest of the system?**
  _75 weakly-connected nodes found - possible documentation gaps or missing edges._