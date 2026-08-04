# Graph Report - .  (2026-08-04)

## Corpus Check
- 24 files · ~27,508 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 225 nodes · 392 edges · 29 communities (20 shown, 9 thin omitted)
- Extraction: 79% EXTRACTED · 21% INFERRED · 0% AMBIGUOUS · INFERRED: 81 edges (avg confidence: 0.81)
- Token cost: 9,627 input · 2,263 output

## Community Hubs (Navigation)
- winget Parsing and Pinning
- XAML Data Bindings
- Module Architecture and Tests
- Release and Signing
- winget Execution and Backup
- Text Labels
- Bootstrap and XAML Loading
- Self-Update
- Theming and Settings Screen
- Spinner Controls
- Pin Context Menus
- Border Elements
- Data Grids
- Text Inputs
- Checkboxes
- Progress Bar Parts
- Column Resize Grippers
- Grid Responsiveness Rationale
- Dark Theme Palette
- Light Theme Palette
- Theme Dropdown
- Vector Marks
- Dropdown Popup
- Tab Content Host
- Progress Bar
- Tab Container

## God Nodes (most connected - your core abstractions)
1. `Window` - 69 edges
2. `Start-App()` - 15 edges
3. `Write-Log()` - 14 edges
4. `Button` - 14 edges
5. `TextBlock` - 13 edges
6. `Start-BackgroundJob()` - 12 edges
7. `Set-AppBusy()` - 12 edges
8. `Load-Upgrades()` - 12 edges
9. `Initialize-InstallTab()` - 10 edges
10. `Load-Installed()` - 10 edges

## Surprising Connections (you probably didn't know these)
- `Closure Scope Trap in Jobs` --rationale_for--> `Start-BackgroundJob()`  [EXTRACTED]
  DEVELOPMENT.md → src/modules/App.Jobs.ps1
- `Installer SHA-256 Pin` --semantically_similar_to--> `Automatic Updates`  [INFERRED] [semantically similar]
  winget/1.9.0/FedeB2160.WinGetStudio.installer.yaml → README.md
- `Esc via PreviewKeyDown` --rationale_for--> `Initialize-Settings()`  [EXTRACTED]
  DEVELOPMENT.md → src/modules/App.Settings.ps1
- `One winget Process at a Time` --references--> `Set-AppBusy()`  [EXTRACTED]
  DEVELOPMENT.md → src/modules/App.Ui.ps1
- `Closure Scope Trap in Jobs` --rationale_for--> `Start-SelfUpdate()`  [EXTRACTED]
  DEVELOPMENT.md → src/modules/App.Update.ps1

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Self-Update Chain** — readme_automatic_updates, development_code_signing, development_non_reproducible_builds, changelog_v100_removed, development_self_exclusion_from_updates [EXTRACTED 0.95]
- **Dark Mode Theming Effort** — development_retemplated_controls, development_dynamicresource_theming, development_header_gripper_loss, readme_settings_screen [EXTRACTED 0.95]
- **winget Output Parsing Hazards** — development_column_position_parsing, development_maxcolumns_guard, development_utf8_output_reading, development_exit_code_capture [EXTRACTED 0.95]

## Communities (29 total, 9 thin omitted)

### Community 0 - "winget Parsing and Pinning"
Cohesion: 0.14
Nodes (27): CollectionView Unroll Trap, Column Position Parsing, MaxColumns Guard for Spaced Headers, One winget Process at a Time, Package Pinning, Set-PackagePin(), Set-PinFlags(), Update-PinFlags() (+19 more)

### Community 1 - "XAML Data Bindings"
Cohesion: 0.11
Nodes (27): ActualWidth, Available, Id, IsDropDownOpen, Name, Pinned, Selected, Status (+19 more)

### Community 2 - "Module Architecture and Tests"
Cohesion: 0.16
Nodes (21): Module Architecture, MODULES Marker Injection, Script Scope for Controls, Test Suite, Guarded Uninstall, Hidden Selection Warning, Install Scope Auto User Machine, Install Tab (+13 more)

### Community 3 - "Release and Signing"
Cohesion: 0.12
Nodes (17): Release v1.9.0, Rename to WinGet Studio, Removed v1.0.0 Release, Code Signing, Non-Reproducible Builds, Publishing a Release, Self Exclusion from Update List, Self-Signed Certificate (+9 more)

### Community 4 - "winget Execution and Backup"
Cohesion: 0.26
Nodes (14): Exit Code Capture via Process Start, UTF-8 Output Reading, Export and Import Package List, Get-ImportPackageCount(), Initialize-Backup(), Invoke-PackageExport(), Invoke-PackageImport(), Start-Export() (+6 more)

### Community 5 - "Text Labels"
Cohesion: 0.14
Nodes (14): cellIcon, pinIcon, TxtAvailable, TxtEmpty, TxtInstalledCount, TxtInstalledEmpty, TxtInstalledInfo, TxtSearchEmpty (+6 more)

### Community 6 - "Bootstrap and XAML Loading"
Cohesion: 0.27
Nodes (10): Resolve-Asset(), Get-XamlText(), Read-Xaml(), Start-App(), Stop-AllJobs(), Initialize-Theme(), Set-Theme(), Set-TitleBarDark() (+2 more)

### Community 7 - "Self-Update"
Cohesion: 0.38
Nodes (9): Closure Scope Trap in Jobs, Clear-OldExe(), Get-LatestRelease(), Get-RunningExePath(), Initialize-Update(), Start-SelfUpdate(), Start-UpdateCheck(), Test-IsSelfPackage() (+1 more)

### Community 8 - "Theming and Settings Screen"
Cohesion: 0.24
Nodes (9): DockPanel LastChildFill Trap, DynamicResource Theming, Esc via PreviewKeyDown, Header Gripper Loss on Re-Template, Re-Templated Controls for Dark Mode, Settings Screen, Hide-Settings(), Initialize-Settings() (+1 more)

### Community 10 - "Spinner Controls"
Cohesion: 0.33
Nodes (6): cellSpinner, InstalledSpinner, SearchSpinner, TopSpinner, UpdateSpinner, Control

### Community 11 - "Pin Context Menus"
Cohesion: 0.40
Nodes (5): MenuPinInstalled, MenuPinUpdates, MenuUnpinInstalled, MenuUnpinUpdates, MenuItem

### Community 13 - "Border Elements"
Cohesion: 0.50
Nodes (4): bd, Box, SettingsPanel, Border

### Community 14 - "Data Grids"
Cohesion: 0.50
Nodes (4): Grid, GridInstalled, GridSearch, DataGrid

### Community 15 - "Text Inputs"
Cohesion: 0.50
Nodes (4): TxtFilter, TxtLog, TxtSearch, TextBox

### Community 16 - "Checkboxes"
Cohesion: 0.67
Nodes (3): ChkStore, ChkUnknown, CheckBox

### Community 17 - "Progress Bar Parts"
Cohesion: 0.67
Nodes (3): PART_Indicator, PART_Track, Rectangle

### Community 18 - "Column Resize Grippers"
Cohesion: 0.67
Nodes (3): PART_LeftHeaderGripper, PART_RightHeaderGripper, Thumb

## Knowledge Gaps
- **22 isolated node(s):** `ResourceDictionary`, `ResourceDictionary`, `Path`, `ContentPresenter`, `StatusDetail` (+17 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **9 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `Window` connect `XAML Data Bindings` to `Text Labels`, `Spinner Controls`, `Pin Context Menus`, `Border Elements`, `Data Grids`, `Text Inputs`, `Checkboxes`, `Progress Bar Parts`, `Column Resize Grippers`, `Theme Dropdown`, `Vector Marks`, `Dropdown Popup`, `Tab Content Host`, `Progress Bar`, `Tab Container`?**
  _High betweenness centrality (0.137) - this node is a cross-community bridge._
- **Why does `Start-App()` connect `Bootstrap and XAML Loading` to `winget Parsing and Pinning`, `Module Architecture and Tests`, `winget Execution and Backup`, `Self-Update`, `Theming and Settings Screen`?**
  _High betweenness centrality (0.084) - this node is a cross-community bridge._
- **Why does `Automatic Updates` connect `Release and Signing` to `Theming and Settings Screen`, `Self-Update`?**
  _High betweenness centrality (0.070) - this node is a cross-community bridge._
- **Are the 13 inferred relationships involving `Start-App()` (e.g. with `Resolve-Asset()` and `Initialize-Backup()`) actually correct?**
  _`Start-App()` has 13 INFERRED edges - model-reasoned connections that need verification._
- **Are the 13 inferred relationships involving `Write-Log()` (e.g. with `Invoke-PackageExport()` and `Invoke-PackageImport()`) actually correct?**
  _`Write-Log()` has 13 INFERRED edges - model-reasoned connections that need verification._
- **What connects `ResourceDictionary`, `ResourceDictionary`, `Path` to the rest of the system?**
  _22 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `winget Parsing and Pinning` be split into smaller, more focused modules?**
  _Cohesion score 0.1431451612903226 - nodes in this community are weakly interconnected._