# Existing WinGet Studio Bugs Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the reproduced Winget read failures and malformed import count, and remove brittle/unsafe assumptions from the live UI test.

**Architecture:** Make all Winget table reads carry explicit command status into the UI. Validate the export structure before counting. Keep the WPF integration test, but make its live behavior opt-in, its filter fixture deterministic, and its pin cleanup safe for pre-existing state.

**Tech Stack:** Windows PowerShell 5.1, WPF, existing PowerShell test scripts, Winget CLI.

**Spec:** `docs/superpowers/specs/2026-10-04-existing-bugs-design.md`

## Global Constraints

- Do not treat Winget command failure as an empty successful result.
- Preserve successful parsing, including localized tables and multi-table upgrade output.
- Do not clear existing pin state after a failed pin read or remove a pin that existed before the test.
- `Get-ImportPackageCount` returns `null` for malformed exports and an integer for valid exports.
- Tests must not require 7-Zip or another incidental package to be installed.
- `Test-Ui.ps1` uses live Winget and must require `-ConfirmLiveWinget` before starting the app.
- Keep PowerShell 5.1 compatibility and add no dependencies.
- Do not modify the installer/portable update design in this bug-only plan.

## Review Focus

- Winget exits nonzero after emitting diagnostic text that resembles a table; no rows may be returned as success.
- Empty/localized Winget output with exit code zero remains a valid empty result where appropriate.
- Pin-read failure must preserve displayed pin flags.
- A valid empty export returns zero; malformed source/package structures return `null`.
- UI filtering works with no 7-Zip installed and leaves the backing collection unchanged.
- A pre-existing pin survives the live test; cleanup only removes a pin the test attempted to add.
- Running `Test-Ui.ps1` without its opt-in fails before launching Winget or modifying state.

---

### Task 1: Make the UI test deterministic and safe

**Files:**
- Modify: `tests/Test-Ui.ps1`
- Modify: `DEVELOPMENT.md`

- [ ] **Step 1: Pin the filter behavior with deterministic rows**

Replace the hard-coded `7zip` inventory filter around the current lines 1126-1136 with two temporary `WgtRow` fixtures: one matching and one not matching. Assert that only the match is visible and both remain in the backing collection. Remove both fixtures in `finally`. Run the existing test before the code change and confirm the reported failure `il filtro '7zip' mostra 0 righe su 146` is eliminated by the fixture.

- [ ] **Step 2: Add a live-test opt-in before startup**

Add `param([switch]$ConfirmLiveWinget)` at the top of `Test-Ui.ps1`. Without the switch, exit nonzero before `Start-App -NoShow` and before any Winget process. With the switch, print a warning that the hidden WPF test performs live Winget reads/export and may temporarily change one pin.

- [ ] **Step 3: Protect pre-existing pin state**

Before the live pin cycle, skip if `7zip.7zip` is absent or already pinned. If initially unpinned, mark cleanup as required immediately before attempting `pin add`; in `finally`, remove only that target and verify it is absent. This also cleans up if Winget added the pin but the UI wait/assertion then failed.

- [ ] **Step 4: Correct the test documentation**

Change the `Test-Ui.ps1` header and `DEVELOPMENT.md` inventory entry from “headless check” to “hidden WPF integration test; uses live Winget; requires `-ConfirmLiveWinget`; temporary pin is restored.”

- [ ] **Step 5: Verify the guard, filter, and cleanup**

Run without opt-in: `powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-Ui.ps1`
Expected: a clear nonzero exit before `Start-App` or any Winget process.

Run with opt-in: `powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-Ui.ps1 -ConfirmLiveWinget`
Expected: filter assertions pass without 7-Zip; absent or pre-pinned target is skipped; a pin created by the test is removed in `finally`.

- [ ] **Step 6: Commit the deterministic/safe test change**

```powershell
git add tests/Test-Ui.ps1 DEVELOPMENT.md
git commit -m "test: make live UI integration deterministic and safe"
```

### Task 2: Propagate Winget read failures to the UI

**Files:**
- Modify: `src/modules/WinGet.Parse.ps1`
- Modify: `src/modules/Tab.Updates.ps1`
- Modify: `src/modules/Tab.Installed.ps1`
- Modify: `src/modules/Tab.Install.ps1`
- Modify: `src/modules/App.Pins.ps1`
- Test: `tests/Test-InvokeWinGet.ps1`
- Test: `tests/Test-Ui.ps1`

**Interfaces:**
- Add `Invoke-WinGetRead([string[]]$Arguments, [int]$MaxColumns = 0) -> PSCustomObject` in `WinGet.Parse.ps1`.
- Result fields: `Success: bool`, `Rows: object[]`, `ExitCode: int`, `Output: string`. Capture `$LASTEXITCODE` immediately after the native command. Parse rows only after success.
- `Get-WinGetSearch`, `Get-WinGetInstalled`, `Get-WinGetUpgrades`, and `Get-WinGetPins` return the same result shape. The first three map fields to `WgtRow`; pins return string IDs.
- UI callbacks show the failed command and exit code; they do not show no-results/no-updates/empty-inventory messages. Pin flags remain unchanged after a failed read.

- [ ] **Step 1: Add failing simulated exit-code cases**

Extend `Test-InvokeWinGet.ps1`’s existing stub: set `$global:LASTEXITCODE = 1` and emit `Failed to open source: test fixture`. Assert all four read functions report failure, exit code 1, and diagnostic output. The current code reproduces the defect as zero rows for all four commands.

- [ ] **Step 2: Add UI failure-state assertions**

Use the existing hidden WPF harness to feed failed read results to update, installed, search, and pin callbacks. Assert error status is visible, no empty-success message appears, and previously set `Pinned` flags remain unchanged. Confirm these assertions fail before the callback changes.

- [ ] **Step 3: Implement the exit-aware read helper**

Keep native argument arrays. `Invoke-WinGetRead` runs Winget, snapshots exit status before another native command can overwrite it, captures diagnostic output, and parses only successful output. Preserve each reader’s current success-row contents.

- [ ] **Step 4: Update background jobs and consumers**

Pass `Invoke-WinGetRead` to each relevant runspace. Update all four reader consumers to handle `Success = $false`; `Update-PinFlags` calls `Set-PinFlags` only after successful retrieval.

- [ ] **Step 5: Run focused tests**

Run: `powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-InvokeWinGet.ps1`
Expected: existing table parser cases pass; each simulated exit-1 read returns an explicit error result.

Run: `powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-Ui.ps1 -ConfirmLiveWinget`
Expected: injected read failures are reported and never appear as successful empty states.

- [ ] **Step 6: Commit the Winget read-failure fix**

```powershell
git add src/modules/WinGet.Parse.ps1 src/modules/Tab.Updates.ps1 src/modules/Tab.Installed.ps1 src/modules/Tab.Install.ps1 src/modules/App.Pins.ps1 tests/Test-InvokeWinGet.ps1 tests/Test-Ui.ps1
git commit -m "fix: surface winget read command failures"
```

### Task 3: Reject malformed Winget export structures

**Files:**
- Modify: `src/modules/App.Backup.ps1`
- Test: `tests/Test-Ui.ps1`

**Interfaces:**
- Keep `Get-ImportPackageCount([string]$Path) -> int|null`.
- Return a count only for a valid `Sources`/`Packages` structure whose package entries contain a non-empty `PackageIdentifier`. A valid export with empty package arrays returns zero.
- Keep import preflight behavior: invalid input never reaches `Invoke-PackageImport`.

- [ ] **Step 1: Add failing JSON fixtures**

Cover one-package and empty valid exports. Reject malformed JSON, missing `Sources`, `Sources: [{}]`, missing/non-array `Packages`, and package entries without `PackageIdentifier`. The existing repro `{"Sources":[{}]}` must fail instead of returning 1.

- [ ] **Step 2: Run focused import assertions**

Run: `powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-Ui.ps1 -ConfirmLiveWinget`
Expected before the fix: `{"Sources":[{}]}` is counted as 1.

- [ ] **Step 3: Validate structure before counting**

Update `Get-ImportPackageCount` to reject invalid root/source/package shapes and unusable package identifiers. Keep its `try/catch` behavior for malformed JSON or missing files.

- [ ] **Step 4: Prove invalid files never launch import**

Use the existing import checks to assert invalid files are rejected before `Invoke-PackageImport`; valid empty and one-package fixtures return 0 and 1.

- [ ] **Step 5: Run the focused import suite**

Run: `powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-Ui.ps1 -ConfirmLiveWinget`
Expected: every malformed fixture returns `$null`, valid fixtures return their exact counts, and Winget is not invoked for invalid input.

- [ ] **Step 6: Commit the import validation fix**

```powershell
git add src/modules/App.Backup.ps1 tests/Test-Ui.ps1
git commit -m "fix: reject malformed winget export files"
```

### Task 4: Run the complete regression gate

**Files:**
- Verify: `tests/Test-InvokeWinGet.ps1`
- Verify: `tests/Test-Ui.ps1`

- [ ] **Step 1: Run both suites**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-InvokeWinGet.ps1
powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-Ui.ps1 -ConfirmLiveWinget
```

Expected: both finish successfully; no test requires 7-Zip. The live UI test reports its Winget usage and restores only a pin it added.

- [ ] **Step 2: Record elevation-dependent skips honestly**

The earlier non-elevated run skipped the Winget live portion. Run from an elevated session for live command coverage; if elevation is unavailable, report the live check as skipped, not passed. Do not install or uninstall packages.

- [ ] **Step 3: Review final repository state**

Run: `git status --short --branch`
Expected: only intended changes are present; each implementation commit includes its focused regression test.
