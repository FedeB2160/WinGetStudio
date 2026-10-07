# WinGet Studio 1.11.0 — installer alongside the portable exe — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:executing-plans (Native, recommended) or superpowers:subagent-driven-development. Steps use checkbox (`- [ ]`) syntax for tracking.

## Context

Issue https://github.com/FedeB2160/WinGetStudio/issues/3. The user wants four things the portable exe cannot give:
- a Start menu entry;
- uninstall from Windows Settings;
- machine-wide deployment;
- an installed program.

The design was reviewed section by section and approved on 2026-10-07. It corrects Codex's earlier spec:
- **Setup name:** the GitHub API sorts assets by name, so the setup is named `WinGetStudio_Setup.exe`. Older copies, which take the first `*.exe`, keep getting the portable.
- **Scope:** machine scope only.
- **Update channels:** four channels, with no supervisor process.
- **winget:** the migration is gated on a Sandbox test.

**Goal:** every release ships `WinGetStudio.exe` (portable, unchanged) and `WinGetStudio_Setup.exe` (Inno Setup). An installed copy updates itself through the setup.

**Architecture:**
- `installer\WinGetStudio.iss` is compiled by `src\build.ps1` after the signed exe.
- Signing moves into `src\sign.ps1`, shared by the exe, the setup and its uninstaller.
- `App.Update.ps1` gains `Get-InstallChannel` and selects the release asset by exact name per channel. The `installed` channel downloads the setup, requires its SHA-256 and runs it with `/SILENT /CLOSEAPPLICATIONS /relaunch=1`.

**Tech Stack:** Windows PowerShell 5.1, WPF, ps2exe 1.0.18, Inno Setup 6 (6.7.3 in CI), GitHub Actions `windows-2022`.

**Spec:** `docs/superpowers/specs/2026-10-07-installer-design.md` (branch `feature/v1.11.0`, commit f903a89).

## Global Constraints

- **AppId:** `{80A0A054-6278-4145-AD5A-2B3C4853019F}`, never to change. In the `.iss` it is written `{{80A0A054-6278-4145-AD5A-2B3C4853019F}`, because a single `{` opens an Inno constant.
- **Asset names:**
  - portable `WinGetStudio.exe`, setup `WinGetStudio_Setup.exe`;
  - the setup must sort after the portable (`OrdinalIgnoreCase`).
- **Install:**
  - machine scope only: `PrivilegesRequired=admin`, `DefaultDirName={autopf}\WinGet Studio`;
  - Start menu shortcut always; desktop shortcut as an unchecked task;
  - uninstall keeps `HKCU\Software\WinGetStudio`.
- **Self-update of the `installed` channel:** the SHA-256 digest is mandatory. The portable keeps today's warning when the digest is missing.
- **Code:**
  - PowerShell 5.1 only;
  - ASCII string literals in modules (they have no BOM);
  - in-code comments in Italian; UI text, docs, commits and PR text in English;
  - every function a runspace uses must be listed in `-Functions`.
- **Versioning and commits:**
  - `$AppVersion` stays `1.10.3` until Task 6, and new changelog lines go under `## Unreleased`;
  - one commit per task, both suites green before each commit, push after each commit;
  - commits end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`;
  - PR descriptions end with `🤖 Generated with [Claude Code](https://claude.com/claude-code)`.
- **Signing:** only with the key that matches `assets\WinGetStudio-codesign.cer` (thumbprint `139AD24E…`, this PC). `gh` must act as FedeB2160, the active account.
- **Commands:** run them from the repo root.
  - `powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-Ui.ps1 [-Live]`
  - `powershell -ExecutionPolicy Bypass -File .\tests\Test-InvokeWinGet.ps1`
  - `powershell -ExecutionPolicy Bypass -File .\src\build.ps1`

## Review Focus

1. The exe sits in the install folder, but with different letter case or a missing trailing backslash: it must still be the `installed` channel. Test in Task 2.
2. A release that lacks the asset of the running channel: no update is offered, and a manual check says why. Test in Task 3.
3. The setup cannot be started (antivirus, file gone): the app must not close, and it must log why. Static test in Task 3.
4. A copy up to 1.10.x checking a release that has two `.exe` assets: it must still get the portable. Sort test in Task 1.
5. A developer machine without Inno Setup: `build.ps1` still produces the signed exe, warns and exits 0. Static test in Task 1, plus one manual run with a bogus ISCC path in Task 1.

## Branch and flow

- Work on `feature/v1.11.0`; it already holds the spec. Before Task 1 run `git switch feature/v1.11.0 && git merge --ff-only main` to bring in 1.10.3.
- Copy this plan to `docs/superpowers/plans/2026-10-07-installer.md` in Task 1's commit. It is deleted in Task 6.
- After Task 4, open a **draft** PR `feature/v1.11.0` → `main` so the CI runs. The merge happens only at release (Task 6), because `main` stays on what is published.

---

### Task 1: Inno script, shared signing script, build step

**Files:**
- Create: `installer\WinGetStudio.iss`, `src\sign.ps1`
- Modify: `src\build.ps1` (signing block, end of file), `tests\Test-Ui.ps1` (new section 7e), `DEVELOPMENT.md` (Layout, Compiling, Signing), `CLAUDE.md` (build comment), `CHANGELOG.md`

**Interfaces — produces:**
- `src\sign.ps1 -Path <file> -Thumbprint <thumbprint>`: exit 0 means signed, it throws otherwise.
- `dist\WinGetStudio_Setup.exe`, whose `FileVersion` and `ProductVersion` equal `$AppVersion`.

- [ ] **Step 1: failing static checks.** In `tests\Test-Ui.ps1`, after section 7d, add:

```powershell
# 7e) Lo script dell'installer: identita', scope, collegamenti, rilancio e firma come nella
# spec. Il nome del setup deve venire DOPO quello del portable nell'ordine con cui GitHub
# elenca gli asset (per nome, senza maiuscole): le copie fino alla 1.10.x prendono il primo .exe.
$issPath = Join-Path $root 'installer\WinGetStudio.iss'
if (-not (Test-Path -LiteralPath $issPath)) { throw "manca installer\WinGetStudio.iss" }
$iss = Get-Content -LiteralPath $issPath -Raw
foreach ($needle in 'AppId={{80A0A054-6278-4145-AD5A-2B3C4853019F}', 'PrivilegesRequired=admin',
                    'DefaultDirName={autopf}\WinGet Studio', 'OutputBaseFilename=WinGetStudio_Setup',
                    '{autoprograms}\WinGet Studio', 'Flags: unchecked', 'CloseApplications=yes',
                    'SignedUninstaller=yes', 'Check: ShouldRelaunch', "{param:relaunch|0}") {
    if (-not $iss.Contains($needle)) { throw "WinGetStudio.iss: manca '$needle'" }
}
if ($iss -match 'HKCU\\Software\\WinGetStudio|\[UninstallDelete\]') { throw "la disinstallazione non deve toccare le preferenze" }
if ([string]::Compare('WinGetStudio.exe', 'WinGetStudio_Setup.exe', [StringComparison]::OrdinalIgnoreCase) -ge 0) {
    throw "il setup verrebbe elencato prima del portable"
}
$buildText2 = Get-Content (Join-Path $root 'src\build.ps1') -Raw
if ($buildText2 -notmatch 'ISCC\.exe' -or $buildText2 -notmatch 'setup not built') { throw "build.ps1 non compila il setup o non avvisa se manca Inno" }
if ($buildText2 -notmatch 'sign\.ps1') { throw "build.ps1 non firma tramite sign.ps1" }
"OK setup   script Inno coerente con la spec, setup elencato dopo il portable"
```

- [ ] **Step 2:** run the offline UI suite. Expected: FAIL `manca installer\WinGetStudio.iss`.

- [ ] **Step 3: `src\sign.ps1`.** It holds the signing logic now inline in `build.ps1`, moved without changes:

```powershell
<#
    sign.ps1 — firma un file con il certificato indicato, con marca temporale se il server
    risponde. Lo usano build.ps1 per l'exe e Inno Setup (SignTool) per setup e disinstallatore:
    una sola implementazione della firma per tre file.
    Esce con errore se la firma non e' stata applicata (Inno si ferma su exit code non zero).
#>
param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Thumbprint)
$ErrorActionPreference = 'Stop'
$cert = Get-ChildItem Cert:\CurrentUser\My, Cert:\LocalMachine\My -CodeSigningCert -ErrorAction SilentlyContinue |
        Where-Object { $_.Thumbprint -eq $Thumbprint } | Select-Object -First 1
if (-not $cert) { throw "Certificato $Thumbprint non trovato negli archivi personali" }

# -TimestampServer: senza marca temporale la firma diventa invalida alla scadenza del
# certificato; con la marca resta valida per sempre. Richiede rete.
$sig = Set-AuthenticodeSignature -LiteralPath $Path -Certificate $cert -HashAlgorithm SHA256 `
           -TimestampServer 'http://timestamp.digicert.com' -ErrorAction SilentlyContinue
# Il timestamp si verifica guardando il TIMESTAMP, non lo Status: con un self-signed lo Status
# non sara' mai 'Valid' su una macchina che non lo considera fidato.
if ($sig -and -not $sig.TimeStamperCertificate) {
    Write-Host "Marca temporale non applicata (server non raggiungibile): la firma scadra' col certificato." -ForegroundColor Yellow
    $sig = Set-AuthenticodeSignature -LiteralPath $Path -Certificate $cert -HashAlgorithm SHA256
}
if (-not $sig -or -not $sig.SignerCertificate) { throw "Firma non applicata a $Path" }
$stamp = if ($sig.TimeStamperCertificate) { ', con marca temporale' } else { '' }
Write-Host "Firmato $(Split-Path $Path -Leaf): $($cert.Subject)$stamp" -ForegroundColor Cyan
# 'UnknownError' con un self-signed e' NORMALE: la firma c'e', la radice non e' fidata qui.
if ($sig.Status -ne 'Valid') { Write-Host "  Catena non fidata su questa macchina (normale con un self-signed): $($sig.Status)" -ForegroundColor Yellow }
```

- [ ] **Step 4: `src\build.ps1`.**
  - Keep the certificate selection unchanged.
  - Replace the whole `else { … Set-AuthenticodeSignature … }` signing branch with:

```powershell
else {
    & (Join-Path $PSScriptRoot 'sign.ps1') -Path $out -Thumbprint $signCert.Thumbprint
}
```

  - Before the final `Write-Host "`nFatto…"`, add:

```powershell
# ------------------------------------------------------------------
# INSTALLER (Inno Setup 6)
# ------------------------------------------------------------------
# Lo stesso exe, gia' firmato, impacchettato in WinGetStudio_Setup.exe. Senza Inno la build
# NON fallisce: chi sviluppa compila l'exe senza installare altro. Il rilascio richiede
# entrambi i file, e lo fanno valere la CI e la procedura di DEVELOPMENT.md.
$iscc = @("${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe", (Get-Command ISCC.exe -ErrorAction SilentlyContinue).Source) |
        Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
if (-not $iscc) {
    Write-Host "`nATTENZIONE: setup not built (Inno Setup 6 assente): winget install JRSoftware.InnoSetup" -ForegroundColor Yellow
}
else {
    $isccArgs = @("/DAppVersion=$version", "/DSourceExe=$out", "/O$(Split-Path $out)", '/Q')
    # $q e $f li sostituisce Inno: apice e nome (quotato) del file da firmare.
    if ($signCert) {
        $isccArgs += '/DSIGN'
        $isccArgs += "/Swgsign=powershell.exe -NoProfile -ExecutionPolicy Bypass -File `$q$(Join-Path $PSScriptRoot 'sign.ps1')`$q -Thumbprint $($signCert.Thumbprint) -Path `$f"
    }
    & $iscc @isccArgs (Join-Path $root 'installer\WinGetStudio.iss')
    if ($LASTEXITCODE -ne 0) { throw "ISCC fallito (exit $LASTEXITCODE)" }
    $setup = Join-Path (Split-Path $out) 'WinGetStudio_Setup.exe'
    $svi = (Get-Item -LiteralPath $setup).VersionInfo
    if ([version]$svi.FileVersion -ne [version]$version -or [version]$svi.ProductVersion -ne [version]$version) {
        throw "Versione del setup $($svi.FileVersion)/$($svi.ProductVersion), attesa $version"
    }
    Write-Host "Setup: $setup" -ForegroundColor Green
}
```

- [ ] **Step 5: `installer\WinGetStudio.iss`.**

```ini
; WinGetStudio.iss — installer per macchina dello stesso exe portable (Inno Setup 6).
; Lo compila src\build.ps1: AppVersion, SourceExe e (se c'e' la chiave) SIGN arrivano da li'.
; AppId NON va mai cambiato: e' la chiave _is1 con cui l'app si riconosce installata
; (Get-InstallChannel) e con cui winget correla il pacchetto.

#ifndef AppVersion
  #error AppVersion non definita: compilare con src\build.ps1
#endif

[Setup]
AppId={{80A0A054-6278-4145-AD5A-2B3C4853019F}
AppName=WinGet Studio
AppVersion={#AppVersion}
AppPublisher=FedeB2160
AppPublisherURL=https://github.com/FedeB2160/WinGetStudio
VersionInfoVersion={#AppVersion}
VersionInfoTextVersion={#AppVersion}
VersionInfoProductTextVersion={#AppVersion}
; Solo per macchina: l'app gira sempre elevata, e un'installazione per utente aggiornata da
; un processo elevato finirebbe nel profilo dell'amministratore.
PrivilegesRequired=admin
DefaultDirName={autopf}\WinGet Studio
DisableProgramGroupPage=yes
OutputBaseFilename=WinGetStudio_Setup
SetupIconFile=..\assets\icon.ico
UninstallDisplayIcon={app}\WinGetStudio.exe
WizardStyle=modern
; Se l'app e' aperta (aggiornamento dall'app stessa) Inno la chiude prima di sostituire l'exe.
CloseApplications=yes
RestartApplications=no
; Senza chiave (niente /DSIGN) il setup esce non firmato, come l'exe.
#ifdef SIGN
SignTool=wgsign
SignedUninstaller=yes
#endif

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceExe}"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\WinGet Studio"; Filename: "{app}\WinGetStudio.exe"
Name: "{autodesktop}\WinGet Studio"; Filename: "{app}\WinGetStudio.exe"; Tasks: desktopicon

[Run]
; Installazione a mano: casella "Launch" a fine wizard.
Filename: "{app}\WinGetStudio.exe"; Description: "{cm:LaunchProgram,WinGet Studio}"; Flags: nowait postinstall skipifsilent
; Aggiornamento dall'app: la riapre solo se lanciato con /relaunch=1. winget non lo passa.
Filename: "{app}\WinGetStudio.exe"; Flags: nowait; Check: ShouldRelaunch

[Code]
function ShouldRelaunch: Boolean;
begin
  Result := ExpandConstant('{param:relaunch|0}') = '1';
end;
```

The preferences are kept on uninstall by having no `[UninstallDelete]` and no `[Registry]` section, which the test checks.

`SignedUninstaller=yes` stays inside `#ifdef SIGN` because it needs a `SignTool`. The test reads the text of the file, so it finds the directive either way.

- [ ] **Step 6:** run the offline UI suite and `Test-InvokeWinGet.ps1`. Expected: PASS, including `OK setup`.

- [ ] **Step 7: build for real.**
  - Run `powershell -ExecutionPolicy Bypass -File .\src\build.ps1`. Expected:
    - "Firmato WinGetStudio.exe";
    - ISCC signs the setup and its uninstaller, i.e. two "Firmato" lines from `sign.ps1` during compilation;
    - "Setup: …\dist\WinGetStudio_Setup.exe".
  - Check that both files carry thumbprint `139AD24E…`:

```powershell
'WinGetStudio.exe','WinGetStudio_Setup.exe' | ForEach-Object { $s = Get-AuthenticodeSignature (Join-Path .\dist $_); "$_ $($s.SignerCertificate.Thumbprint) $((Get-Item (Join-Path .\dist $_)).VersionInfo.FileVersion)" }
```

  - Expected: both `139AD24E…` and `1.10.3`.

- [ ] **Step 8: no-Inno path (Review Focus 5).**
  - Temporarily rename the ISCC lookup's first path to a nonexistent folder in a scratch copy of `build.ps1` under the scratchpad, or set `${env:ProgramFiles(x86)}` to a scratch folder in a child `powershell -Command`, then run the build.
  - Expected: the exe is built and signed, the "setup not built" warning appears, exit 0.
  - Do not commit the scratch change.

- [ ] **Step 9: docs.**
  - DEVELOPMENT.md:
    - Layout: add `src\sign.ps1  signing (exe, setup, uninstaller)` and `installer\WinGetStudio.iss  Inno Setup script → dist\WinGetStudio_Setup.exe`.
    - Compiling: add a paragraph. After the exe, `build.ps1` compiles `installer\WinGetStudio.iss` with Inno Setup 6, passing version and exe path. Without Inno it warns "setup not built" and still succeeds.
    - Signing: `src\sign.ps1` signs the exe, and through Inno's `SignTool` also the setup and its uninstaller, with the same certificate.
  - CLAUDE.md build comment: "…checks the exe version metadata; builds dist\WinGetStudio_Setup.exe too when Inno Setup 6 is installed."
  - CHANGELOG `## Unreleased` (create the heading above `## v1.10.3`): `- Releases also ship an installer, WinGetStudio_Setup.exe: Start menu entry, uninstall from Windows Settings, machine-wide install.`

- [ ] **Step 10: commit and push.**
  - Copy this plan to `docs/superpowers/plans/2026-10-07-installer.md`.
  - Commit "feat: Inno Setup installer built next to the exe; signing in one script", then push.

---

### Task 2: Install channel detection

**Files:** modify `src\modules\App.Update.ps1`, `tests\Test-Ui.ps1` (section 20), `DEVELOPMENT.md`, `CLAUDE.md`

**Interfaces — produces:**
- `$InnoAppId = '{80A0A054-6278-4145-AD5A-2B3C4853019F}'` and `$SetupAssetName = 'WinGetStudio_Setup.exe'`, module-level in `App.Update.ps1`.
- `Get-InstalledLocation` returns `[string]` or `$null`.
- `Get-InstallChannel([string]$ExePath = (Get-RunningExePath), [string]$InstallLocation = (Get-InstalledLocation))` returns `'source' | 'winget-portable' | 'installed' | 'portable'`.
- `Test-IsWinGetPortable` becomes `(Get-InstallChannel) -eq 'winget-portable'`, so its callers and existing test are unchanged.

- [ ] **Step 1: failing test.** In section 20, after the `Test-NewerVersion` checks, add:

```powershell
# Canale d'installazione: deciso da percorso dell'exe e InstallLocation della voce _is1,
# passati come parametri (nessun registro nel test). Maiuscole e "\" finale non contano.
$il = 'C:\Program Files (x86)\WinGet Studio\'
$channelCases = @(
    @{ Exe = $null;                                              Loc = $il;  Want = 'source' }
    @{ Exe = 'C:\Users\x\AppData\Local\Microsoft\WinGet\Packages\FedeB2160.WinGetStudio_Microsoft.Winget.Source_8wekyb3d8bbwe\WinGetStudio.exe'; Loc = $il; Want = 'winget-portable' }
    @{ Exe = 'C:\Program Files (x86)\WinGet Studio\WinGetStudio.exe'; Loc = $il;  Want = 'installed' }
    @{ Exe = 'C:\PROGRAM FILES (X86)\WINGET STUDIO\WinGetStudio.exe'; Loc = 'C:\Program Files (x86)\WinGet Studio'; Want = 'installed' }
    @{ Exe = 'D:\Tools\WinGetStudio.exe';                        Loc = $il;  Want = 'portable' }
    @{ Exe = 'D:\Tools\WinGetStudio.exe';                        Loc = $null; Want = 'portable' }
)
foreach ($c in $channelCases) {
    $got = Get-InstallChannel -ExePath $c.Exe -InstallLocation $c.Loc
    if ($got -ne $c.Want) { throw "Get-InstallChannel '$($c.Exe)' / '$($c.Loc)': '$got', atteso '$($c.Want)'" }
}
"OK channel i quattro canali d'installazione riconosciuti"
```

- [ ] **Step 2:** run the offline UI suite. Expected: FAIL "Get-InstallChannel" is not recognized.

- [ ] **Step 3: implement** in `App.Update.ps1`.
  - After `$SelfPackageId`, add:

```powershell
# Identita' dell'installer (installer\WinGetStudio.iss): la voce di disinstallazione e'
# HKLM\...\Uninstall\<AppId>_is1. L'app e' x86, quindi Windows rimanda la lettura a
# WOW6432Node, dove scrive un installer x86: nessun caso speciale.
$InnoAppId      = '{80A0A054-6278-4145-AD5A-2B3C4853019F}'
$SetupAssetName = 'WinGetStudio_Setup.exe'
```

  - Replace `Test-IsWinGetPortable`'s body with `return (Get-InstallChannel) -eq 'winget-portable'`, keep its comment, and add before it:

```powershell
# Cartella in cui l'installer ha messo l'app, o $null se non e' installata.
function Get-InstalledLocation {
    $key = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$($InnoAppId)_is1"
    try { return (Get-ItemProperty -LiteralPath $key -ErrorAction Stop).InstallLocation } catch { return $null }
}

# Come e' arrivata qui questa copia, quindi come si aggiorna:
#   source          da .ps1: niente auto-update, si usa git
#   winget-portable pacchetto portable di winget: si aggiorna solo con winget
#   installed       installata col setup (a mano o da winget): si aggiorna col setup
#   portable        exe copiato a mano: si rinomina e si sostituisce
# Parametri con i valori veri come default: il test passa percorsi finti.
function Get-InstallChannel([string]$ExePath = (Get-RunningExePath), [string]$InstallLocation = (Get-InstalledLocation)) {
    if (-not $ExePath) { return 'source' }
    if ($ExePath -like '*\Microsoft\WinGet\Packages\*') { return 'winget-portable' }
    if ($InstallLocation -and
        [IO.Path]::GetDirectoryName($ExePath).TrimEnd('\') -ieq $InstallLocation.TrimEnd('\')) { return 'installed' }
    return 'portable'
}
```

- [ ] **Step 4:** run both suites. Expected: PASS, including `OK channel` and the existing `OK winget` check, which still overrides `Get-RunningExePath`.

- [ ] **Step 5: docs.**
  - DEVELOPMENT.md: in the "Installed from winget, the self-update has to stand down" section, add the four channels and their update paths in the table form of the spec, section 3.
  - CLAUDE.md, Module roles: "…self-update (four install channels: source, winget-portable, installed, portable — `Get-InstallChannel`)…".

- [ ] **Step 6:** commit "feat: tell installed, portable and winget copies apart", then push.

---

### Task 3: Release asset by name and the installed update flow

**Files:** modify `src\modules\App.Update.ps1` (`Get-LatestRelease`, `Start-UpdateCheck`, `Start-SelfUpdate`), `tests\Test-Ui.ps1` (section 20), `README.md` (Automatic updates), `CHANGELOG.md`

**Interfaces:**
- **Consumes:** `Get-InstallChannel`, `$SetupAssetName` (Task 2) and `Clear-WinGetTempFiles` (existing, `WinGet.Exec.ps1`), which sweeps `wgt_*` from `%TEMP%` at startup.
- **Produces:**
  - `Get-LatestRelease([string]$Repo, [string]$AssetName = 'WinGetStudio.exe')` returns `{Tag, Version, Name, Url, Size, Sha256}`. `Url` is `$null` when the release lacks that asset, and `$null` overall when there is no release or no network.
  - `$script:updateChannel`, set by `Start-UpdateCheck` and read by `Start-SelfUpdate`.

- [ ] **Step 1: failing tests.** In section 20, after `OK channel`, add:

```powershell
# Asset scelto per NOME: GitHub elenca per nome, e qui il setup arriva per primo apposta.
function Invoke-RestMethod {
    [PSCustomObject]@{ tag_name = 'v9.9.9'; assets = @(
        [PSCustomObject]@{ name = 'WinGetStudio_Setup.exe'; browser_download_url = 'https://github.com/x/setup'; size = 4096; digest = 'sha256:AA' }
        [PSCustomObject]@{ name = 'WinGetStudio.exe';       browser_download_url = 'https://github.com/x/exe';   size = 2048; digest = 'sha256:BB' }
    ) }
}
try {
    $relP = Get-LatestRelease 'x/y' 'WinGetStudio.exe'
    $relS = Get-LatestRelease 'x/y' $SetupAssetName
    $relM = Get-LatestRelease 'x/y' 'Missing.exe'
}
finally { Remove-Item function:Invoke-RestMethod }
if ($relP.Url -ne 'https://github.com/x/exe' -or $relP.Sha256 -ne 'BB') { throw "portable: asset sbagliato ($($relP.Url))" }
if ($relS.Url -ne 'https://github.com/x/setup' -or $relS.Sha256 -ne 'AA') { throw "installed: asset sbagliato ($($relS.Url))" }
if (-not $relM -or $relM.Tag -ne 'v9.9.9' -or $relM.Url) { throw "asset mancante: serve la release senza Url, non `$null" }

# Canale installed: digest obbligatorio PRIMA della conferma, setup avviato con rilancio,
# file temporaneo col prefisso wgt_ (lo spazza Clear-WinGetTempFiles), e se l'avvio fallisce
# la finestra NON si chiude.
$updSrc = Get-FunctionSource 'Start-SelfUpdate'
$refuse = $updSrc.IndexOf('-not $rel.Sha256')
if ($refuse -lt 0 -or $refuse -gt $updSrc.IndexOf('MessageBox')) { throw "installed: il digest mancante non e' rifiutato prima della conferma" }
if ($updSrc -notmatch '/SILENT /CLOSEAPPLICATIONS /relaunch=1') { throw "il setup non viene avviato con /SILENT /CLOSEAPPLICATIONS /relaunch=1" }
if ($updSrc -notmatch '"wgt_') { throw "il setup scaricato non ha il prefisso wgt_: resterebbe in %TEMP%" }
if ($updSrc -notmatch '(?s)Start-Process -FilePath \$tmp[^\r\n]*-ErrorAction Stop.*?catch.*?Set-AppBusy \$false.*?return') {
    throw "se il setup non parte, l'app deve restare aperta e dirlo"
}
if ((Get-FunctionSource 'Start-UpdateCheck') -notmatch 'Get-InstallChannel') { throw "Start-UpdateCheck non sceglie l'asset per canale" }
"OK assets  asset per nome e canale; setup verificato, rilancio, uscita pulita se non parte"
```

  Also change the live check `if ($rel.Name -notlike '*.exe')` to `if ($rel.Name -ne 'WinGetStudio.exe')`, since the live call uses the default asset name.

- [ ] **Step 2:** run the offline UI suite. Expected: FAIL at the asset checks.

- [ ] **Step 3: `Get-LatestRelease`.** Signature `function Get-LatestRelease([string]$Repo, [string]$AssetName = 'WinGetStudio.exe')`. Replace the "primo asset .exe" block and the return with:

```powershell
        # Asset per NOME esatto, mai per posizione: GitHub elenca gli asset per nome, e dalla
        # 1.11.0 una release ha due .exe. Senza l'asset del proprio canale si torna la release
        # con Url vuoto, cosi' il controllo manuale puo' dire perche' non propone nulla.
        $asset = @($r.assets | Where-Object { $_.name -eq $AssetName })[0]
        return [PSCustomObject]@{
            Tag     = $r.tag_name
            Version = ($r.tag_name -replace '^[vV]', '')
            Name    = $AssetName
            Url     = if ($asset) { $asset.browser_download_url } else { $null }
            Size    = if ($asset) { $asset.size } else { 0 }
            Sha256  = if ($asset -and $asset.digest -match '^sha256:(.+)$') { $Matches[1] } else { $null }
        }
```

  Also update its comment, which currently says "o la risposta non ha un asset .exe".

- [ ] **Step 4: `Start-UpdateCheck`.**
  - Replace the two guards at the top with:

```powershell
    $channel = Get-InstallChannel
    if ($channel -eq 'source') {
        if ($Manual) { $TxtUpdateStatus.Text = 'Updates apply to the compiled exe only; from source use git.' }
        return
    }
    if ($channel -eq 'winget-portable') {
        if ($Manual) { $TxtUpdateStatus.Text = "Installed with winget: update with 'winget upgrade $SelfPackageId'." }
        return
    }
```

  - Before the job, set:

```powershell
    $script:updateChannel = $channel
    $asset = if ($channel -eq 'installed') { $SetupAssetName } else { 'WinGetStudio.exe' }
```

  - Change the job call to `-Vars @{ repo = $UpdateRepo; asset = $asset } -Script { Get-LatestRelease $repo $asset }`.
  - In `OnDone`, after the "Up to date" check, add:

```powershell
            if (-not $rel.Url) {
                if ($manual) { $TxtUpdateStatus.Text = "$($rel.Tag) is out, but without $($rel.Name): nothing to update with." }
                return
            }
```

  - Set the button tooltip by channel:

```powershell
            $BtnUpdateApp.ToolTip = if ($script:updateChannel -eq 'installed') {
                "Download the installer $($rel.Name) ($([int]($rel.Size / 1024)) KB): WinGet Studio closes, updates and reopens"
            } else { "Download $($rel.Name) ($([int]($rel.Size / 1024)) KB) from GitHub and restart" }
```

- [ ] **Step 5: `Start-SelfUpdate`.**
  - Right after the existing guard line, add:

```powershell
    # Il setup si esegue con privilegi di amministratore: senza digest non si scarica nemmeno.
    $installed = $script:updateChannel -eq 'installed'
    if ($installed -and -not $rel.Sha256) {
        Write-Log "Update refused: $($rel.Tag) publishes no checksum for $($rel.Name), and the installer would run as administrator."
        return
    }
```

  - Make the MessageBox first line channel-aware: `$(if ($installed) { "Download the $($rel.Tag) installer and update WinGet Studio? It closes, updates and reopens.`n`n" } else { "Download $($rel.Tag) and restart WinGet Studio?`n`n" })`, keeping the rest of the message.
  - Set the temp path with `$tmp = if ($installed) { [IO.Path]::Combine([IO.Path]::GetTempPath(), "wgt_$($rel.Tag)_$($rel.Name)") } else { Join-Path ([IO.Path]::GetTempPath()) "WinGetStudio-$($rel.Tag).exe" }`, and add `$script:updInstalled = $installed` next to the other `$script:upd*`.
  - In `OnDone`, after the "Download verified" log line, insert:

```powershell
            if ($script:updInstalled) {
                # Il setup chiude l'app (Restart Manager), sostituisce i file e la riapre. Gia'
                # elevati: nessun secondo UAC. Il file resta in %TEMP% e lo spazza
                # Clear-WinGetTempFiles al prossimo avvio (prefisso wgt_).
                $log = [IO.Path]::Combine([IO.Path]::GetTempPath(), 'WinGetStudio-update.log')
                Write-Log "Running $($rel.Name); if the update fails, its log is $log"
                try {
                    Start-Process -FilePath $tmp -ArgumentList "/SILENT /CLOSEAPPLICATIONS /relaunch=1 `"/LOG=$log`"" -ErrorAction Stop
                }
                catch {
                    Write-Log "Update FAILED: the installer did not start: $($_.Exception.Message)"
                    Set-AppBusy $false
                    return
                }
                $window.Close()
                return
            }
```

  Everything after it, the portable rename, is unchanged.

- [ ] **Step 6:** run both suites offline, then `-Live`. Expected: PASS, with `OK assets`, `OK rel` naming `WinGetStudio.exe`, and the manual check reporting an outcome.

- [ ] **Step 7: docs.**
  - README `## Automatic updates`, second sentence becomes: "…the file is verified against the checksum published with the release. A copy installed with the setup then runs the new installer, which closes WinGet Studio, updates it and reopens it; a portable copy replaces itself and restarts; a copy installed with winget is updated with `winget upgrade FedeB2160.WinGetStudio`."
  - CHANGELOG: `- A copy installed with the setup updates itself through the installer; the installer download is refused when the release publishes no checksum.`

- [ ] **Step 8:** commit "feat: pick the release asset by name; update installed copies through the setup", then push.

---

### Task 4: CI builds the setup; release procedure; the decision record

**Files:** modify `.github/workflows/ci.yml`, `DEVELOPMENT.md` (Tests, Publishing a release, "No shortcuts"), `README.md` (Getting it), `CHANGELOG.md`

- [ ] **Step 1: CI.**
  - In the `build` job, before "Compile", add a step:

```yaml
      - name: Install Inno Setup 6.7.3
        run: choco install innosetup --version=6.7.3 -y --no-progress
```

  - Make the upload `path` both files:

```yaml
          path: |
            dist/WinGetStudio.exe
            dist/WinGetStudio_Setup.exe
```

  - Rename the step to "Upload unsigned test builds".

- [ ] **Step 2: Test-Ui name consistency.** In section 7e, add:

```powershell
$ciText = Get-Content (Join-Path $root '.github\workflows\ci.yml') -Raw
$devText = Get-Content (Join-Path $root 'DEVELOPMENT.md') -Raw -Encoding UTF8
if ($ciText -notmatch 'dist/WinGetStudio_Setup\.exe' -or $ciText -notmatch 'innosetup') { throw "la CI non compila o non carica il setup" }
if ($devText -notmatch 'WinGetStudio_Setup\.exe') { throw "la procedura di rilascio non nomina il setup" }
```

  Run the suite. Expected: FAIL on DEVELOPMENT.md until step 3 is done, then PASS.

- [ ] **Step 3: DEVELOPMENT.md.**
  - **Publishing a release:**
    - steps 4–5 attach **both** `dist\WinGetStudio.exe` and `dist\WinGetStudio_Setup.exe`, and the `gh release create` example lists both;
    - add the order check:

```powershell
gh api repos/FedeB2160/WinGetStudio/releases/latest --jq '[.assets[] | select(.name | endswith(".exe"))][0].name'
```

      It must print `WinGetStudio.exe`, because copies up to 1.10.x take the first `.exe`.
    - Replace "The asset is found as the first `.exe`…" with the by-name rule.
  - **"No shortcuts…"** becomes "**Shortcuts and the installer**": a dated record (2026-10-07) saying the earlier refusal stood until it became a product choice, and that it did (Start menu, uninstall from Settings, enterprise deployment). Keep the winget-cli#2299 links and point to the spec.
  - **Tests:** the CI paragraph says the build job installs Inno Setup 6.7.3 and uploads both files.

- [ ] **Step 4: README "Getting it."** The first paragraph becomes:
  - **Installer (recommended):** download `WinGetStudio_Setup.exe` from the latest release. It installs for all users, adds a Start menu entry (desktop optional), shows up in Windows Settings to uninstall, and keeps your preferences if you uninstall.
  - **Portable:** `WinGetStudio.exe` runs from anywhere and installs nothing.
  - The winget paragraph stays as is until Task 6, when the package switches to the installer.

- [ ] **Step 5:**
  - Run both suites.
  - Commit "ci: build and upload the setup; release procedure for two assets" and push.
  - Open a draft PR `feature/v1.11.0` → `main` with a body summarizing Tasks 1–4 and linking issue #3 and the spec, ending with the 🤖 line.
  - Bind it with the app's PR tools.
  - Expected: CI green, and the artifact holds both files.

---

### Task 5: Manual verification in Windows Sandbox (needs the user)

Prerequisite, done by the user: the Windows feature "Windows Sandbox" is enabled (admin and reboot), or a disposable VM is available. **Never on the everyday install.**

- [ ] **Step 1:** copy `dist\WinGetStudio_Setup.exe` from the Task 4 build into the Sandbox.
- [ ] **Step 2: install interactively.**
  - The Start menu entry "WinGet Studio" works.
  - The desktop checkbox is unchecked.
  - The app starts with UAC.
  - Settings > Apps lists "WinGet Studio", publisher FedeB2160, version 1.10.3.
- [ ] **Step 3: update path while the app is open.** Run `WinGetStudio_Setup.exe /SILENT /CLOSEAPPLICATIONS /relaunch=1 "/LOG=%TEMP%\wgs.log"`. Expected: the app closes, files are replaced, the app reopens. Without `/relaunch=1` it must not reopen.
- [ ] **Step 4: channel check.** In the installed app, Settings > Check for updates answers "Up to date (latest published is v1.10.3)". It must not offer the portable, which proves the `installed` channel and the setup asset name.
- [ ] **Step 5: uninstall from Settings.**
  - Program and shortcuts are gone.
  - `HKCU\Software\WinGetStudio` is still there.
- [ ] **Step 6: winget migration rehearsal.** Use winget-pkgs `Tools\SandboxTest.ps1`, which installs winget in the Sandbox.
  1. Install 1.10.3 from the published portable manifest.
  2. Read the real portable uninstall key name under `HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall` to confirm `FedeB2160.WinGetStudio_Microsoft.Winget.Source_8wekyb3d8bbwe`.
  3. Build a local 1.11.0 manifest from Task 6 step 3 with that name.
  4. Run `winget upgrade --manifest`.
  5. Check:
     - one copy only;
     - the `WinGetStudio` alias is gone;
     - the Start menu entry and Settings entry are there;
     - `winget list FedeB2160.WinGetStudio` shows the new version;
     - `winget upgrade` does not offer it again.
- [ ] **Step 7: record the outcome** in the PR and in the ledger. If the migration fails, Task 6 keeps the winget manifest `portable` (decided fallback), and the README winget paragraph stays as is.

---

### Task 6: Release 1.11.0 (only on the user's explicit OK, on this PC)

- [ ] **Step 1: prepare the release on `feature/v1.11.0`.**
  - `$AppVersion = '1.11.0'`.
  - Promote `## Unreleased` into a narrative `## v1.11.0` entry.
  - Delete `docs/superpowers/plans/2026-10-07-installer.md`.
  - Run both suites and `-Live`.
  - Run `build.ps1`: both files signed with `139AD24E…`, both at version `1.11.0`.
- [ ] **Step 2: merge, tag, publish.**
  - Mark the PR ready and merge it after CI.
  - Tag `v1.11.0`.
  - `gh release create v1.11.0 --title v1.11.0 --notes-file <notes> dist\WinGetStudio.exe dist\WinGetStudio_Setup.exe`
  - Run the order check from Task 4; it must print `WinGetStudio.exe`.
  - Check both digests against the local SHA-256 values.
- [ ] **Step 3: winget manifest `winget\1.11.0`.**
  - If Task 5 succeeded: `InstallerType: inno`, **no `Scope`** (see spec §5: winget rejects a scope that differs from the installed per-user portable), `ElevationRequirement: elevatesSelf`, `UpgradeBehavior: uninstallPrevious`, `InstallerUrl` → setup, its hash.
  - `AppsAndFeaturesEntries`:
    - `ProductCode: '{80A0A054-6278-4145-AD5A-2B3C4853019F}_is1'` with `InstallerType: inno`;
    - the confirmed portable key with `InstallerType: portable`.
  - Otherwise: a portable manifest as for 1.10.3.
  - Run `winget validate`.
  - Update README's winget paragraph: the Start menu entry and Settings now apply. Commit.
- [ ] **Step 4: winget-pkgs.**
  - The user runs `winget install --manifest .\winget\1.11.0` as admin (with `LocalManifestFiles` enabled).
  - Submit with `wingetcreate submit`.
  - Set the PR description in the usual style: release type, what changed and **why the installer type changes**, the migration and how it was tested, CI, validation, signing, checklist.
- [ ] **Step 5:** close issue #3 with links to the spec, the PR and the release. Then delete the branch.

## Verification (end to end)

1. Each code task: both suites green offline before its commit. Tasks 3 and 6: also green with `-Live`.
2. Task 1: the real build signs `WinGetStudio.exe`, `WinGetStudio_Setup.exe` and the uninstaller with `139AD24E…`, at version `$AppVersion`. A build without Inno still succeeds with the warning.
3. Task 4: CI green on the draft PR, and the artifact holds both files.
4. Task 5: every checkbox in Sandbox or a VM, migration included, before any winget submission.
5. Task 6: after publishing, the API order check prints `WinGetStudio.exe` and the digests match.

**Execution: Native recommended** (as for the last two plans). Tasks 2 and 3 share `App.Update.ps1`, and Tasks 5 and 6 need the user; one fresh reviewer runs on the whole branch before the draft PR is marked ready.
