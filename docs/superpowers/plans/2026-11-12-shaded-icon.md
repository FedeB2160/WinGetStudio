# Shaded icon and animated tray icon Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Light from the top on every size of the app icon, the arrow centered at 16/20 px, and tray icons generated per state with an animated arrow while the app works.

**Architecture:** `src\icon.ps1` (PowerShell 5.1 + WPF, run by hand, output committed — ADR 0017) gains gradient brushes and a tray mode that writes `assets\tray\*.ico`. The 2.0 app (`app\src\WinGetStudio\TrayIcon.cs`) loads those files instead of recoloring the app icon, and cycles 13 frames with a `DispatcherTimer` while busy.

**Tech Stack:** Windows PowerShell 5.1 (WPF `DrawingVisual`), .NET 10 WPF + WinForms `NotifyIcon`, xUnit v3, `tests\Test-Ui.ps1`.

**Spec:** `docs/superpowers/specs/2026-11-12-shaded-icon-design.md`

## Global Constraints

- Base colors unchanged: lid `#EDBE80`, left side `#D9A15C`, right side `#BF853F`, tape `#F7E2BC`, tape side `#DDB57A`, ink `#5A3A1A`, badge `#0078D4`, arrow `#FFFFFF`.
- Box ramp (every box brush, ink included): +42% (mix with white) at the box top `$top` → the base color at 42/77 → −35% (mix with black) at the box bottom `$y2 + $v`. Vertical, absolute coordinates.
- Badge ramp: +42% at `$by - R·k` → base at 42/70 → −28% at `$by + R·k`. The arrow is never shaded.
- Small tier (16–20 px) arrow: `A1 = 2`, `A2 = 2.5` (today 3 and 1.5): 1 grid unit lower.
- Tray states: Idle `#0078D4`/`#FFFFFF`, Updates `#13A10E`/`#FFFFFF`, Errors `#E81123`/`#FFFFFF`, Busy `#FFB900`/`#1A1A1A` (badge/arrow).
- Tray files: `assets\tray\idle.ico`, `updates.ico`, `errors.ico`, `busy-01.ico` … `busy-13.ico`; each with frames 16, 20, 24, 32 px, PNG-compressed like `icon.ico`. `busy-01` is the still busy icon.
- Animation: 13 frames per cycle, `TimeSpan.FromSeconds(1.0 / 13)` per frame, only while `TrayDot.Busy` and `SystemParameters.ClientAreaAnimation`.
- `icon.ps1` must keep running under `powershell.exe` 5.1 STA; build geometry by hand, never with `-f` on decimals (Italian culture writes `1,5`).
- Code comments in Italian; ADRs, DEVELOPMENT.md, CHANGELOG in English. No new dependencies.
- Generated files are never edited by hand: change `icon.ps1`, rerun it, commit its output.

## Review Focus

- Display scale 125/150/200%: `SmallIconSize` is 20/24/32 → the tray file must hold that exact frame (Task 3 test loads every size).
- Windows animation effects off → still yellow icon, no timer (Task 3 `Animates` test).
- Busy ends mid-cycle → the timer stops and the new state's icon shows at once; no later tick overwrites it (Task 3, `Update` stops the timer before setting the icon).
- Tooltip-only changes while busy (the view model raises `PropertyChanged` for `ToolTip` too) must not restart the cycle from frame 1 (Task 3, start only when the timer is not running).
- Yellow badge: the dark arrow on the lighter top of the badge stays readable (Task 2, visual check against the mockup).

---

### Task 1: Shading and the lower arrow in the app icon

**Files:**
- Modify: `src/icon.ps1` (brushes at lines 48–55, tier 1 at line 34, drawing in `New-IconPng` lines 81–152)
- Regenerate: `assets/icon.ico`, `assets/icon/icon-*.png`
- Test: `tests/Test-Ui.ps1` (new section 11c after 11b, line ~456)

**Interfaces:**
- Produces: `New-Ramp([string]$hex, [double]$y0, [double]$y1, [double]$up, [double]$down)` → frozen `LinearGradientBrush` (`MappingMode Absolute`, `StartPoint (0,$y0)`, `EndPoint (0,$y1)`, stops at 0 / `$up/($up+$down)` / 1). Task 2 uses it for the state badges.

- [ ] **Step 1: Write the failing check** in `tests\Test-Ui.ps1`, section 11c, reading `assets\icon\icon-16.png` with `System.Drawing.Bitmap`:
  - pixel (8,2) (lid, near the top): `B -gt 148` (flat today: `0x80`);
  - pixel (4,12) (left side, near the bottom): `B -lt 82` (flat today: `0x5C`);
  - pixel (11,13) (arrow shaft after the move): `R -ge 240` (today `0x92`, the tip);
  - pixel (11,8) (badge above the arrow): `R -lt 120` (today `0xAF`, the shaft's cap).
  On failure: `throw "assets\icon\icon-16.png non sfumata o freccia non abbassata: rilanciare src\icon.ps1"`; on success print `OK icon   sfumatura e freccia a 16 px`.
- [ ] **Step 2: Run it to see it fail**
  Run: `powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-Ui.ps1`
  Expected: the 11c throw.
- [ ] **Step 3: Implement** in `src\icon.ps1`: `New-Ramp`; inside `New-IconPng` build the box brushes with `New-Ramp <color> $top ($y2 + $v) 0.42 0.35` and the badge brush with `New-Ramp '#0078D4' ($by - $t.R * $k) ($by + $t.R * $k) 0.42 0.28`, replacing the global `$lid`, `$leftSide`, `$rightSide`, `$tape`, `$tapeSide`, `$ink`, `$blue` brushes (the stamp's pen too); tier 1 `A1 = 2; A2 = 2.5`. White = mix toward `#FFFFFF`, black = toward `#000000`, per channel, rounded.
- [ ] **Step 4: Regenerate and run the check**
  Run: `powershell -NoProfile -ExecutionPolicy Bypass -File .\src\icon.ps1` then the Test-Ui command above.
  Expected: `Scritti … (14 dimensioni) e 9 PNG`, then `OK icon   14 dimensioni` and `OK icon   sfumatura e freccia a 16 px`, script ends without errors.
- [ ] **Step 5: Visual check** of `assets\icon\icon-16.png`, `-24`, `-48`, `-256` against `app-icon-gradient-v6.html` (spec, Mockups): same light, arrow centered at 16. Report any visible difference instead of tuning values.
- [ ] **Step 6: Commit** `src/icon.ps1`, `assets/icon.ico`, `assets/icon/`, `tests/Test-Ui.ps1`, plus the spec and this plan if not yet committed: `feat(icon): light from the top on every size; arrow centered at 16 and 20 px`.

### Task 2: Tray icons generated per state, with the busy animation frames

**Files:**
- Modify: `src/icon.ps1`
- Create (generated): `assets/tray/idle.ico`, `updates.ico`, `errors.ico`, `busy-01.ico` … `busy-13.ico`
- Test: `tests/Test-Ui.ps1` (section 11d)

**Interfaces:**
- Consumes: `New-Ramp` (Task 1).
- Produces: `New-IconPng([int]$size, [string]$badge = '#0078D4', [string]$arrow = '#FFFFFF', [int]$frame = 0)`; `Write-Ico([string]$path, [int[]]$sizes, [hashtable]$pngBySize)` (the current inline `.ico` writer, moved into a function and used for `icon.ico` too). Task 3 relies on the file names and sizes in Global Constraints.

- [ ] **Step 1: Write the failing check** in `tests\Test-Ui.ps1`, section 11d: for each of the 16 names, `assets\tray\<name>.ico` exists and its frame sizes (read as in 11b) are exactly `16, 20, 24, 32`; and the bytes of `busy-01.ico` differ from `busy-02.ico`. Throw `"assets\tray\<name>.ico mancante o senza 16/20/24/32: rilanciare src\icon.ps1"`; print `OK tray   16 icone, 4 dimensioni`.
- [ ] **Step 2: Run it to see it fail** (same Test-Ui command). Expected: the 11d throw.
- [ ] **Step 3: Implement** in `src\icon.ps1`:
  - `New-IconPng` takes the badge and arrow colors (badge through `New-Ramp`) and `$frame`.
  - Frame `n`: period `$p = Snap(26 / 9 * $t.R * $k)` (13 at 16 px); offset `$d = Snap($n * $p / 13)`. Draw the arrow twice, translated by `$d` and `$d - $p`, inside `PushClip` of the badge's `EllipseGeometry`. Frame 0 draws exactly the still icon.
  - After the app icon, write the three still states and `busy-01` … `busy-13` (frames 0–12, `#FFB900`/`#1A1A1A`) to `assets\tray\` with `Write-Ico`, sizes `16, 20, 24, 32`.
  - Update the script's header comment: it also writes `assets\tray\`.
- [ ] **Step 4: Regenerate and run the checks** (icon.ps1, then Test-Ui). Expected: also `OK tray   16 icone, 4 dimensioni`; `git diff --stat assets/icon.ico assets/icon` empty (the app icon is unchanged by this task).
- [ ] **Step 5: Visual check** of the 16 px frames of `busy-01`…`busy-13` against `tray-busy-animation-v7.html` (the strip of 13 frames) and of the still states against `tray-icon-zero-gradient-v5.html`, last card. On yellow, the dark arrow must stay readable at the badge's light top.
- [ ] **Step 6: Commit** `src/icon.ps1`, `assets/tray/`, `tests/Test-Ui.ps1`: `feat(icon): tray icons per state and 13 busy frames, generated`.

### Task 3: The tray loads the generated icons and animates while busy

**Files:**
- Modify: `app/src/WinGetStudio/TrayIcon.cs` (`DrawIcons`, `Recolor`, `Update`, `Dispose`, `DestroyIcon` P/Invoke)
- Modify: `app/src/WinGetStudio/WinGetStudio.csproj:21-22` (the `icon.ico` resource and its comment)
- Create: `app/tests/WinGetStudio.Tests/TrayIconTests.cs`

**Interfaces:**
- Consumes: the files and sizes of Task 2.
- Produces (all `internal`, in `TrayIcon`):
  - `const int BusyFrames = 13;`
  - `static Drawing.Icon LoadIcon(string name, int size)`: `pack://application:,,,/WinGetStudio;component/Assets/tray/{name}.ico`, opened with `new Drawing.Icon(stream, size, size)`.
  - `static bool Animates(TrayDot dot, bool animationsOn)`: true only for `Busy` with animations on.

- [ ] **Step 1: Write the failing tests** in `TrayIconTests.cs`:
  - `[Theory] [InlineData(16)] [InlineData(20)] [InlineData(24)] [InlineData(32)] public void EveryTrayIconHasTheSize(int size)`: for `idle`, `updates`, `errors`, `busy-01`…`busy-13`: `using var i = TrayIcon.LoadIcon(name, size); Assert.Equal(size, i.Width);`
  - `[Theory]` over the 4 `TrayDot` values × `true`/`false`: `Assert.Equal(dot == TrayDot.Busy && on, TrayIcon.Animates(dot, on));`
  If the `pack:` scheme is not registered in the test process, touch `System.IO.Packaging.PackUriHelper.UriSchemePack` in the class constructor (never `new Application()`: `WindowSmokeTests` owns the process's only one).
- [ ] **Step 2: Run to see them fail**
  Run: `dotnet test --solution app\WinGetStudio.sln`
  Expected: build error, `LoadIcon` / `Animates` not defined.
- [ ] **Step 3: Implement**:
  - csproj: replace the `icon.ico` resource with `<Resource Include="..\..\..\assets\tray\*.ico" Link="Assets\tray\%(Filename)%(Extension)" />`, comment in Italian (the tray icons, generated by `src\icon.ps1`, ADR 0030).
  - `TrayIcon`: load at `SmallIconSize.Width` the three still icons and the 13 busy frames (`_icons[TrayDot.Busy]` is frame 1); delete `DrawIcons`, `Recolor` and `DestroyIcon` (icons from a stream own their handle: `Dispose` is enough).
  - A second `DispatcherTimer` `_spin`, interval `TimeSpan.FromSeconds(1.0 / BusyFrames)`; its tick advances `_frame` modulo 13 and sets `_icon.Icon`.
  - `Update()`: if `Animates(_vm.Tray.Dot, SystemParameters.ClientAreaAnimation)`, start `_spin` from frame 0 only when it is not already running; otherwise `_spin.Stop()` first, then set `_icons[dot]`. Tooltip handling unchanged.
  - `Dispose()`: stop `_spin`, dispose every icon.
- [ ] **Step 4: Run the tests**
  Run: `dotnet test --solution app\WinGetStudio.sln`
  Expected: all pass, including the 4 + 8 new cases.
- [ ] **Step 5: Commit** `TrayIcon.cs`, `WinGetStudio.csproj`, `TrayIconTests.cs`: `feat(app): tray icons from assets\tray, arrow animated while working`.

### Task 4: Documentation, cleanup, full verification

**Files:**
- Modify: `docs/adr/0017-app-icon-drawn-in-code.md`, `docs/adr/0030-notification-area-icon.md`, `DEVELOPMENT.md` (file list line 42–43, *Icon* section lines 87–101), `CHANGELOG.md` (*Unreleased*)
- Delete: `docs/superpowers/specs/2026-11-12-shaded-icon-design.md`, `docs/superpowers/plans/2026-11-12-shaded-icon.md`

- [ ] **Step 1: ADR 0017**: add *Amended 2026-11-12*: light from the top (the two ramps, values from Global Constraints), why (grainy next to Teams and Outlook at 16 px; redraws turned down), the small-tier arrow moved 1 unit down, the tray icons now drawn here too; add `assets\tray\` to *To watch* → generated files; add the new Test-Ui checks to the Decision.
- [ ] **Step 2: ADR 0030**: amend point 2, dated 2026-11-12, in the style of the R23 amendment: the state icons are generated by `src\icon.ps1` (`assets\tray\`, 16–32 px), no recoloring (why: a shaded badge); busy animates 13 frames per second unless Windows' animation effects are off; frame 1 is the still icon. Update the *Consequences* line about the shell side being checked by hand (the animation too).
- [ ] **Step 3: DEVELOPMENT.md**: file list gains `assets\tray\*.ico  tray icons per state and 13 busy frames, generated by src\icon.ps1`; the *Icon* section says the script also writes `assets\tray\`, and that `Test-Ui.ps1` checks the 16 px shading and the tray files.
- [ ] **Step 4: CHANGELOG** *Unreleased*, one bullet: `- **New icon**: the same box and badge, with light from the top, as Windows' own icons have; at 16 px the arrow sits in the middle of the badge.`
- [ ] **Step 5: Delete** the spec and this plan (CLAUDE.md: a spec goes once its decisions are in an ADR).
- [ ] **Step 6: Full verification**
  Run: `dotnet test --solution app\WinGetStudio.sln`; `powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-Ui.ps1`; `powershell -ExecutionPolicy Bypass -File .\tests\Test-InvokeWinGet.ps1`.
  Expected: all green.
- [ ] **Step 7: Commit**: `docs: shaded icon and animated tray in ADR 0017 and 0030; drop the spec`.

### Task 5: Hand-over (the orchestrating session, not the implementer)

- [ ] **Step 1:** Show the user the tray in the real app: run the 2.0 app, start a scan, watch the animation; with *Animation effects* off in Windows the icon stays still. The user checks; nothing is pushed before their ok.
- [ ] **Step 2:** With the user's ok: push the branch (`git -c credential.helper= -c "credential.helper=!gh auth git-credential" push -u origin <branch>`) and open the PR; bind it with the ccd_pr tools.
- [ ] **Step 3:** After the PR is merged, start a dedicated session (the user asked for it, 2026-11-12) to **release v1.13.0** of the 1.x following DEVELOPMENT.md's release procedure, so it ships the new icon: `$AppVersion` 1.13.0 in `src\main.ps1`, CHANGELOG *Unreleased* → `v1.13.0`, signed build with the real key (the one matching `assets\WinGetStudio-codesign.cer`, never a regenerated certificate), tag, GitHub release, `winget\1.13.0` manifests and the winget-pkgs PR. Commit, push and PRs there only with the user's ok.
