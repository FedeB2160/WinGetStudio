# Graph Report - .  (2026-10-08)

## Corpus Check
- 52 files · ~62,286 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 291 nodes · 509 edges · 36 communities (25 shown, 11 thin omitted)
- Extraction: 77% EXTRACTED · 23% INFERRED · 0% AMBIGUOUS · INFERRED: 117 edges (avg confidence: 0.8)
- Token cost: 199,247 input · 0 output

## Community Hubs (Navigation)
- Export and Import
- Project Rules and Core Decisions
- Layout, Signing and Release ADRs
- Grid Row Bindings
- Status Text Controls
- Self-Update and Install Channels
- UI Test Suite
- Bootstrap and XAML Loading
- Install Tab
- Preferences and Theme
- winget Table Parsing
- Spinners
- Tab Items
- Pin Context Menus
- Early winget Manifests
- Tooltip Border
- Settings Checkboxes
- Data Grids
- Progress Track Parts
- Text Boxes
- Settings Combo Boxes
- Header Grippers
- Manifest v1.10.0
- Dark Theme
- Light Theme
- About Table
- Check Mark Path
- ComboBox Popup
- Tab Content Host
- Progress Bar
- Main Tab Control
- Release v1.9.0
- Manifest v1.9.0

## God Nodes (most connected - your core abstractions)
1. `Window` - 75 edges
2. `Write-Log()` - 18 edges
3. `Start-App()` - 16 edges
4. `DEVELOPMENT.md (procedures)` - 14 edges
5. `Load-Upgrades()` - 13 edges
6. `TextBlock` - 13 edges
7. `Start-WinGetQueue()` - 12 edges
8. `Load-Installed()` - 12 edges
9. `Button` - 12 edges
10. `Start-BackgroundJob()` - 11 edges

## Surprising Connections (you probably didn't know these)
- `ADR 0003 Only one winget process at a time` --semantically_similar_to--> `Test-Ui.ps1 and Test-InvokeWinGet.ps1 suites`  [INFERRED] [semantically similar]
  docs/adr/0003-only-one-winget-process-at-a-time.md → DEVELOPMENT.md
- `Get-LatestRelease()` --calls--> `Invoke-RestMethod()`  [INFERRED]
  src/modules/App.Update.ps1 → tests/Test-Ui.ps1
- `CI build job (exe and setup, unsigned artifacts)` --references--> `Single exe via marker substitution (###MODULES### etc.)`  [INFERRED]
  .github/workflows/ci.yml → docs/adr/0001-one-exe-built-from-modules.md
- `winget manifest 1.10.1 installer (portable)` --references--> `ADR 0015 winget package: portable, then inno`  [INFERRED]
  winget/1.10.1/FedeB2160.WinGetStudio.installer.yaml → docs/adr/0015-winget-package-portable-then-inno.md
- `winget manifest 1.10.2 installer (portable)` --references--> `ADR 0015 winget package: portable, then inno`  [INFERRED]
  winget/1.10.2/FedeB2160.WinGetStudio.installer.yaml → docs/adr/0015-winget-package-portable-then-inno.md

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **How winget is run, parsed and serialised** — concept_invoke_winget_process_start, concept_read_result_object, concept_get_winget_table, concept_global_busy_state, concept_start_winget_queue_choke_point [INFERRED 0.85]
- **Theme system rules** — concept_dynamic_resource_themes, concept_retemplated_controls, concept_wcag_contrast_floors [EXTRACTED 1.00]
- **Single sources for build: modules, version, markers** — concept_modulenames_single_list, concept_appversion_single_version, concept_single_exe_markers_build [EXTRACTED 1.00]
- **Signed release pipeline: sign, installer, self-update, winget** — docs_adr_0012_signing, docs_adr_0013_self_update, docs_adr_0014_installer_alongside_the_portable_exe, docs_adr_0015_winget_package_portable_then_inno [INFERRED 0.85]
- **WinGet Manifest v1.10.0** — winget_1_10_0_installer, winget_1_10_0_locale [EXTRACTED 1.00]
- **WinGet Manifest v1.9.0** — winget_1_9_0_installer, winget_1_9_0_locale [EXTRACTED 1.00]

## Communities (36 total, 11 thin omitted)

### Community 0 - "Export and Import"
Cohesion: 0.14
Nodes (36): Get-ImportPackageCount(), Initialize-Backup(), Invoke-PackageExport(), Invoke-PackageImport(), Start-Export(), Start-Import(), Request-QueueCancel(), Start-BackgroundJob() (+28 more)

### Community 1 - "Project Rules and Core Decisions"
Cohesion: 0.08
Nodes (36): Always-elevated app (requireAdministrator), $AppVersion single version (matches git tag), Blocking pin (winget pin add --blocking), GetNewClosure scope trap ($script: lost), Antivirus (Wacatac) false positive on ps2exe exe, Theme dictionaries with DynamicResource and same keys, Get-WinGetTable column-position parser (-MaxColumns), Global busy state (Set-AppBusy, Test-WinGetBusy) (+28 more)

### Community 2 - "Layout, Signing and Release ADRs"
Cohesion: 0.08
Nodes (34): ADR 0011 Window layout, Read-only grids during operation, Settings and About as tabs (not overlay), Tooltip never on container without own tooltips, ADR 0012 Signing, Signing certificate selection rule (thumbprint match only), Self-signed CN=WinGet Studio certificate, src/sign.ps1 single signing implementation (+26 more)

### Community 3 - "Grid Row Bindings"
Cohesion: 0.11
Nodes (26): ActualWidth, Available, Id, IsDropDownOpen, IsReadOnly, Name, Pinned, Selected (+18 more)

### Community 4 - "Status Text Controls"
Cohesion: 0.13
Nodes (15): StatusDetail, cellIcon, pinIcon, TxtAvailable, TxtEmpty, TxtInstalledCount, TxtInstalledEmpty, TxtInstalledInfo (+7 more)

### Community 5 - "Self-Update and Install Channels"
Cohesion: 0.32
Nodes (10): Clear-OldExe(), Get-InstallChannel(), Get-LatestRelease(), Get-RunningExePath(), Initialize-Update(), Start-SelfUpdate(), Start-UpdateCheck(), Test-IsSelfPackage() (+2 more)

### Community 6 - "UI Test Suite"
Cohesion: 0.18
Nodes (3): Get-Contrast(), Get-Luminance(), Invoke-RestMethod()

### Community 7 - "Bootstrap and XAML Loading"
Cohesion: 0.31
Nodes (8): Resolve-Asset(), Get-XamlText(), Initialize-TabHeaders(), Read-Xaml(), Set-TabHeaderStyle(), Start-App(), Clear-WinGetTempFiles(), Get-WinGetPath()

### Community 8 - "Install Tab"
Cohesion: 0.47
Nodes (9): Initialize-InstallTab(), Install-Rows(), Refresh-InstallState(), Set-InstallBusy(), Show-SearchMessage(), Start-InstallSelected(), Start-Search(), Test-ElevatedUserMismatch() (+1 more)

### Community 9 - "Preferences and Theme"
Cohesion: 0.43
Nodes (6): Get-Pref(), Set-Pref(), Initialize-Theme(), Set-Theme(), Set-TitleBarDark(), Test-SystemDark()

### Community 10 - "winget Table Parsing"
Cohesion: 0.52
Nodes (6): Get-Field(), Get-WinGetInstalled(), Get-WinGetSearch(), Get-WinGetTable(), Get-WinGetUpgrades(), Invoke-WinGetRead()

### Community 11 - "Spinners"
Cohesion: 0.33
Nodes (6): cellSpinner, InstalledSpinner, SearchSpinner, TopSpinner, UpdateSpinner, Control

### Community 12 - "Tab Items"
Cohesion: 0.33
Nodes (6): TabAbout, TabInstall, TabInstalled, TabSettings, TabUpdates, TabItem

### Community 13 - "Pin Context Menus"
Cohesion: 0.40
Nodes (5): MenuPinInstalled, MenuPinUpdates, MenuUnpinInstalled, MenuUnpinUpdates, MenuItem

### Community 14 - "Early winget Manifests"
Cohesion: 0.40
Nodes (4): WinGetStudio Installer v1.10.0, WinGetStudio Locale v1.10.0, WinGetStudio Installer v1.9.0, WinGetStudio Locale v1.9.0

### Community 15 - "Tooltip Border"
Cohesion: 0.50
Nodes (4): (AutomationProperties.HelpText), bd, Box, Border

### Community 17 - "Settings Checkboxes"
Cohesion: 0.50
Nodes (4): ChkAutoCheck, ChkStore, ChkUnknown, CheckBox

### Community 18 - "Data Grids"
Cohesion: 0.50
Nodes (4): Grid, GridInstalled, GridSearch, DataGrid

### Community 19 - "Progress Track Parts"
Cohesion: 0.50
Nodes (4): PART_Indicator, PART_Track, Rectangle, Track

### Community 20 - "Text Boxes"
Cohesion: 0.50
Nodes (4): TxtFilter, TxtLog, TxtSearch, TextBox

### Community 21 - "Settings Combo Boxes"
Cohesion: 0.67
Nodes (3): CmbTabStyle, CmbTheme, ComboBox

### Community 22 - "Header Grippers"
Cohesion: 0.67
Nodes (3): PART_LeftHeaderGripper, PART_RightHeaderGripper, Thumb

## Knowledge Gaps
- **41 isolated node(s):** `ResourceDictionary`, `ResourceDictionary`, `v1.10.0`, `v1.9.0`, `WinGet Manifest v1.10.0` (+36 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **11 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Window` connect `Grid Row Bindings` to `Status Text Controls`, `Spinners`, `Tab Items`, `Pin Context Menus`, `Tooltip Border`, `Settings Checkboxes`, `Data Grids`, `Progress Track Parts`, `Text Boxes`, `Settings Combo Boxes`, `Header Grippers`, `About Table`, `Check Mark Path`, `ComboBox Popup`, `Tab Content Host`, `Progress Bar`, `Main Tab Control`?**
  _High betweenness centrality (0.105) - this node is a cross-community bridge._
- **Why does `Start-App()` connect `Bootstrap and XAML Loading` to `Export and Import`, `Install Tab`, `Self-Update and Install Channels`?**
  _High betweenness centrality (0.047) - this node is a cross-community bridge._
- **Why does `Start-UpdateCheck()` connect `Self-Update and Install Channels` to `Export and Import`, `Bootstrap and XAML Loading`?**
  _High betweenness centrality (0.029) - this node is a cross-community bridge._
- **Are the 17 inferred relationships involving `Write-Log()` (e.g. with `Invoke-PackageExport()` and `Invoke-PackageImport()`) actually correct?**
  _`Write-Log()` has 17 INFERRED edges - model-reasoned connections that need verification._
- **Are the 13 inferred relationships involving `Start-App()` (e.g. with `Resolve-Asset()` and `Initialize-Backup()`) actually correct?**
  _`Start-App()` has 13 INFERRED edges - model-reasoned connections that need verification._
- **Are the 10 inferred relationships involving `Load-Upgrades()` (e.g. with `Start-App()` and `Start-BackgroundJob()`) actually correct?**
  _`Load-Upgrades()` has 10 INFERRED edges - model-reasoned connections that need verification._
- **What connects `ResourceDictionary`, `ResourceDictionary`, `v1.10.0` to the rest of the system?**
  _41 weakly-connected nodes found - possible documentation gaps or missing edges._