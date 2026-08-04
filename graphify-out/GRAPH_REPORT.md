# Graph Report - C:\Users\f.borghi\Claude\Projects\Varie\WinGetTool  (2026-08-03)

## Corpus Check
- cluster-only mode — file stats not available

## Summary
- 143 nodes · 250 edges · 24 communities (18 shown, 6 thin omitted)
- Extraction: 80% EXTRACTED · 20% INFERRED · 0% AMBIGUOUS · INFERRED: 51 edges (avg confidence: 0.8)
- Token cost: 666 input · 98 output

## Graph Freshness
- Built from commit: `90df6ffd`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- Background Job Management
- UI Data Models
- Application Initialization and Theming
- Installation Tab Logic
- UI Button Controls
- WinGet Data Parsing
- Loading Spinner Controls
- Context Menu Items
- DataGrid
- TextBox
- bd
- ChkStore
- PART_Indicator
- PART_LeftHeaderGripper
- Theme.Dark.xaml
- Theme.Light.xaml
- Mark
- PART_SelectedContentHost
- Progress
- TabMain

## God Nodes (most connected - your core abstractions)
1. `Window` - 55 edges
2. `Start-App()` - 11 edges
3. `Initialize-InstallTab()` - 10 edges
4. `Load-Upgrades()` - 10 edges
5. `TextBlock` - 10 edges
6. `Start-WinGetQueue()` - 9 edges
7. `Write-Log()` - 9 edges
8. `Load-Installed()` - 9 edges
9. `Initialize-InstalledTab()` - 9 edges
10. `Button` - 9 edges

## Surprising Connections (you probably didn't know these)
- `Start-WinGetQueue()` --calls--> `Get-UpdateStatus()`  [INFERRED]
  src/modules/App.Jobs.ps1 → src/modules/WinGet.Exec.ps1
- `Start-WinGetQueue()` --calls--> `Invoke-WinGet()`  [INFERRED]
  src/modules/App.Jobs.ps1 → src/modules/WinGet.Exec.ps1
- `Start-App()` --calls--> `Stop-AllJobs()`  [INFERRED]
  src/modules/App.Bootstrap.ps1 → src/modules/App.Jobs.ps1
- `Start-App()` --calls--> `Initialize-InstallTab()`  [INFERRED]
  src/modules/App.Bootstrap.ps1 → src/modules/Tab.Install.ps1
- `Start-App()` --calls--> `Initialize-InstalledTab()`  [INFERRED]
  src/modules/App.Bootstrap.ps1 → src/modules/Tab.Installed.ps1

## Import Cycles
- None detected.

## Communities (24 total, 6 thin omitted)

### Community 0 - "Background Job Management"
Cohesion: 0.24
Nodes (19): Start-BackgroundJob(), Start-WinGetQueue(), Set-PackagePin(), Set-PinFlags(), Update-PinFlags(), Register-BusyHandler(), Set-AppBusy(), Write-Log() (+11 more)

### Community 1 - "UI Data Models"
Cohesion: 0.13
Nodes (21): Available, Id, Name, Pinned, Selected, Status, StatusDetail, Text (+13 more)

### Community 2 - "Application Initialization and Theming"
Cohesion: 0.20
Nodes (12): Resolve-Asset(), Get-XamlText(), Read-Xaml(), Start-App(), Stop-AllJobs(), Initialize-Theme(), Set-Theme(), Set-TitleBarDark() (+4 more)

### Community 3 - "Installation Tab Logic"
Cohesion: 0.49
Nodes (9): Initialize-InstallTab(), Install-Rows(), Refresh-InstallState(), Set-InstallBusy(), Show-SearchMessage(), Start-InstallSelected(), Start-Search(), Test-ElevatedUserMismatch() (+1 more)

### Community 4 - "UI Button Controls"
Cohesion: 0.20
Nodes (10): BtnInstall, BtnRefresh, BtnRefreshInstalled, BtnScope, BtnSearch, BtnTheme, BtnToggleAll, BtnUninstall (+2 more)

### Community 5 - "WinGet Data Parsing"
Cohesion: 0.52
Nodes (6): Get-Field(), Get-WinGetInstalled(), Get-WinGetPins(), Get-WinGetSearch(), Get-WinGetTable(), Get-WinGetUpgrades()

### Community 7 - "Loading Spinner Controls"
Cohesion: 0.40
Nodes (5): cellSpinner, InstalledSpinner, SearchSpinner, TopSpinner, Control

### Community 8 - "Context Menu Items"
Cohesion: 0.40
Nodes (5): MenuPinInstalled, MenuPinUpdates, MenuUnpinInstalled, MenuUnpinUpdates, MenuItem

### Community 10 - "DataGrid"
Cohesion: 0.50
Nodes (4): Grid, GridInstalled, GridSearch, DataGrid

### Community 11 - "TextBox"
Cohesion: 0.50
Nodes (4): TxtFilter, TxtLog, TxtSearch, TextBox

### Community 12 - "bd"
Cohesion: 0.67
Nodes (3): bd, Box, Border

### Community 13 - "ChkStore"
Cohesion: 0.67
Nodes (3): ChkStore, ChkUnknown, CheckBox

### Community 14 - "PART_Indicator"
Cohesion: 0.67
Nodes (3): PART_Indicator, PART_Track, Rectangle

### Community 15 - "PART_LeftHeaderGripper"
Cohesion: 0.67
Nodes (3): PART_LeftHeaderGripper, PART_RightHeaderGripper, Thumb

## Knowledge Gaps
- **15 isolated node(s):** `ResourceDictionary`, `ResourceDictionary`, `Path`, `ContentPresenter`, `StatusDetail` (+10 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **6 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Window` connect `UI Data Models` to `UI Button Controls`, `Loading Spinner Controls`, `Context Menu Items`, `DataGrid`, `TextBox`, `bd`, `ChkStore`, `PART_Indicator`, `PART_LeftHeaderGripper`, `Mark`, `PART_SelectedContentHost`, `Progress`, `TabMain`?**
  _High betweenness centrality (0.225) - this node is a cross-community bridge._
- **Why does `Start-App()` connect `Application Initialization and Theming` to `Background Job Management`, `Installation Tab Logic`?**
  _High betweenness centrality (0.063) - this node is a cross-community bridge._
- **Why does `Load-Upgrades()` connect `Background Job Management` to `Application Initialization and Theming`, `WinGet Data Parsing`?**
  _High betweenness centrality (0.027) - this node is a cross-community bridge._
- **Are the 9 inferred relationships involving `Start-App()` (e.g. with `Resolve-Asset()` and `Stop-AllJobs()`) actually correct?**
  _`Start-App()` has 9 INFERRED edges - model-reasoned connections that need verification._
- **Are the 2 inferred relationships involving `Initialize-InstallTab()` (e.g. with `Start-App()` and `Register-BusyHandler()`) actually correct?**
  _`Initialize-InstallTab()` has 2 INFERRED edges - model-reasoned connections that need verification._
- **Are the 7 inferred relationships involving `Load-Upgrades()` (e.g. with `Start-App()` and `Start-BackgroundJob()`) actually correct?**
  _`Load-Upgrades()` has 7 INFERRED edges - model-reasoned connections that need verification._
- **What connects `ResourceDictionary`, `ResourceDictionary`, `Path` to the rest of the system?**
  _15 weakly-connected nodes found - possible documentation gaps or missing edges._