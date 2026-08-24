# Graph Report - C:/Users/f.borghi/Claude/Projects/Varie/WinGetStudio  (2026-08-24)

## Corpus Check
- 30 files · ~42,861 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 212 nodes · 389 edges · 36 communities (20 shown, 16 thin omitted)
- Extraction: 73% EXTRACTED · 27% INFERRED · 0% AMBIGUOUS · INFERRED: 104 edges (avg confidence: 0.8)
- Token cost: 23,142 input · 2,887 output

## Community Hubs (Navigation)
- WPF Data Bindings
- Backup and Background Jobs
- Startup and Preferences
- Pins and Installed Tab
- Toolbar Buttons
- Install Tab
- UI Test Suite
- Progress Spinners
- Tab Strip
- Pin Context Menu
- winget Manifests
- Settings Checkboxes
- Package Grids
- Progress Bar Template
- Text Inputs
- Project Overview
- Border Elements
- Settings Dropdowns
- Column Resize Grippers
- Release 1.10.0
- Dark Theme
- Light Theme
- About Table
- Checkbox Glyph
- ComboBox Popup
- Tab Content Host
- Progress Bar
- Tab Control
- Release 1.9.0
- Architecture Notes
- Module Injection
- Single winget Process
- Development Layout
- Manifest 1.9.0

## God Nodes (most connected - your core abstractions)
1. `Window` - 76 edges
2. `Start-App()` - 17 edges
3. `Write-Log()` - 16 edges
4. `Initialize-UpdatesTab()` - 13 edges
5. `TextBlock` - 13 edges
6. `Initialize-InstallTab()` - 12 edges
7. `Load-Upgrades()` - 12 edges
8. `Button` - 12 edges
9. `Start-BackgroundJob()` - 11 edges
10. `Start-WinGetQueue()` - 11 edges

## Surprising Connections (you probably didn't know these)
- `Start-App()` --calls--> `Stop-AllJobs()`  [INFERRED]
  src/modules/App.Bootstrap.ps1 → src/modules/App.Jobs.ps1
- `Load-Upgrades()` --calls--> `Test-IsSelfPackage()`  [INFERRED]
  src/modules/Tab.Updates.ps1 → src/modules/App.Update.ps1
- `Start-App()` --calls--> `Initialize-Backup()`  [INFERRED]
  src/modules/App.Bootstrap.ps1 → src/modules/App.Backup.ps1
- `Start-App()` --calls--> `Write-Log()`  [INFERRED]
  src/modules/App.Bootstrap.ps1 → src/modules/App.Ui.ps1
- `Start-App()` --calls--> `Initialize-InstallTab()`  [INFERRED]
  src/modules/App.Bootstrap.ps1 → src/modules/Tab.Install.ps1

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **WinGet Manifest v1.10.0** — winget_1_10_0_installer, winget_1_10_0_locale [EXTRACTED 1.00]
- **WinGet Manifest v1.9.0** — winget_1_9_0_installer, winget_1_9_0_locale [EXTRACTED 1.00]

## Communities (36 total, 16 thin omitted)

### Community 0 - "WPF Data Bindings"
Cohesion: 0.10
Nodes (28): ActualWidth, Available, Id, IsDropDownOpen, IsReadOnly, Name, Pinned, Selected (+20 more)

### Community 1 - "Backup and Background Jobs"
Cohesion: 0.20
Nodes (23): Get-ImportPackageCount(), Initialize-Backup(), Invoke-PackageExport(), Invoke-PackageImport(), Start-Export(), Start-Import(), Request-QueueCancel(), Start-BackgroundJob() (+15 more)

### Community 2 - "Startup and Preferences"
Cohesion: 0.16
Nodes (20): Resolve-Asset(), Get-XamlText(), Initialize-TabHeaders(), Read-Xaml(), Set-TabHeaderStyle(), Start-App(), Get-Pref(), Set-Pref() (+12 more)

### Community 3 - "Pins and Installed Tab"
Cohesion: 0.22
Nodes (16): Set-PackagePin(), Set-PinFlags(), Update-PinFlags(), Register-GridRefresh(), Initialize-InstalledTab(), Load-Installed(), Refresh-InstalledState(), Set-InstalledBusy() (+8 more)

### Community 4 - "Toolbar Buttons"
Cohesion: 0.15
Nodes (13): BtnCheckUpdate, BtnExport, BtnImport, BtnInstall, BtnRefresh, BtnRefreshInstalled, BtnScope, BtnSearch (+5 more)

### Community 5 - "Install Tab"
Cohesion: 0.47
Nodes (9): Initialize-InstallTab(), Install-Rows(), Refresh-InstallState(), Set-InstallBusy(), Show-SearchMessage(), Start-InstallSelected(), Start-Search(), Test-ElevatedUserMismatch() (+1 more)

### Community 7 - "Progress Spinners"
Cohesion: 0.33
Nodes (6): cellSpinner, InstalledSpinner, SearchSpinner, TopSpinner, UpdateSpinner, Control

### Community 8 - "Tab Strip"
Cohesion: 0.33
Nodes (6): TabAbout, TabInstall, TabInstalled, TabSettings, TabUpdates, TabItem

### Community 9 - "Pin Context Menu"
Cohesion: 0.40
Nodes (5): MenuPinInstalled, MenuPinUpdates, MenuUnpinInstalled, MenuUnpinUpdates, MenuItem

### Community 10 - "winget Manifests"
Cohesion: 0.40
Nodes (4): WinGetStudio Installer v1.10.0, WinGetStudio Locale v1.10.0, WinGetStudio Installer v1.9.0, WinGetStudio Locale v1.9.0

### Community 12 - "Settings Checkboxes"
Cohesion: 0.50
Nodes (4): ChkAutoCheck, ChkStore, ChkUnknown, CheckBox

### Community 13 - "Package Grids"
Cohesion: 0.50
Nodes (4): Grid, GridInstalled, GridSearch, DataGrid

### Community 14 - "Progress Bar Template"
Cohesion: 0.50
Nodes (4): PART_Indicator, PART_Track, Rectangle, Track

### Community 15 - "Text Inputs"
Cohesion: 0.50
Nodes (4): TxtFilter, TxtLog, TxtSearch, TextBox

### Community 16 - "Project Overview"
Cohesion: 0.67
Nodes (3): GitHub API, WinGet Studio README, winget

### Community 17 - "Border Elements"
Cohesion: 0.67
Nodes (3): bd, Box, Border

### Community 18 - "Settings Dropdowns"
Cohesion: 0.67
Nodes (3): CmbTabStyle, CmbTheme, ComboBox

### Community 19 - "Column Resize Grippers"
Cohesion: 0.67
Nodes (3): PART_LeftHeaderGripper, PART_RightHeaderGripper, Thumb

## Knowledge Gaps
- **34 isolated node(s):** `ResourceDictionary`, `ResourceDictionary`, `Path`, `IsReadOnly`, `ContentPresenter` (+29 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **16 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Window` connect `WPF Data Bindings` to `Toolbar Buttons`, `Progress Spinners`, `Tab Strip`, `Pin Context Menu`, `Settings Checkboxes`, `Package Grids`, `Progress Bar Template`, `Text Inputs`, `Border Elements`, `Settings Dropdowns`, `Column Resize Grippers`, `About Table`, `Checkbox Glyph`, `ComboBox Popup`, `Tab Content Host`, `Progress Bar`, `Tab Control`?**
  _High betweenness centrality (0.194) - this node is a cross-community bridge._
- **Why does `Start-App()` connect `Startup and Preferences` to `Backup and Background Jobs`, `Pins and Installed Tab`, `Install Tab`?**
  _High betweenness centrality (0.051) - this node is a cross-community bridge._
- **Why does `Write-Log()` connect `Backup and Background Jobs` to `Startup and Preferences`, `Pins and Installed Tab`, `Install Tab`?**
  _High betweenness centrality (0.020) - this node is a cross-community bridge._
- **Are the 14 inferred relationships involving `Start-App()` (e.g. with `Resolve-Asset()` and `Initialize-Backup()`) actually correct?**
  _`Start-App()` has 14 INFERRED edges - model-reasoned connections that need verification._
- **Are the 15 inferred relationships involving `Write-Log()` (e.g. with `Invoke-PackageExport()` and `Invoke-PackageImport()`) actually correct?**
  _`Write-Log()` has 15 INFERRED edges - model-reasoned connections that need verification._
- **Are the 8 inferred relationships involving `Initialize-UpdatesTab()` (e.g. with `Start-App()` and `Request-QueueCancel()`) actually correct?**
  _`Initialize-UpdatesTab()` has 8 INFERRED edges - model-reasoned connections that need verification._
- **What connects `ResourceDictionary`, `ResourceDictionary`, `Path` to the rest of the system?**
  _34 weakly-connected nodes found - possible documentation gaps or missing edges._