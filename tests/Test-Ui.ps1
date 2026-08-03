<#
    Test-Ui.ps1 — controllo headless di UI e temi (non apre finestre, non tocca winget).
    Uso: powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-Ui.ps1

    Serve per accorgersi subito se un ritocco a ui\*.xaml rompe qualcosa: XAML non
    valido, un x:Name rinominato, una chiave di colore presente in un tema e non
    nell'altro, un marcatore ###...### perso in src\WinGetUpdateTool.ps1.
#>
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

$xamlFiles = 'UI.xaml', 'Theme.Light.xaml', 'Theme.Dark.xaml'

# 1) Gli script parsano?
foreach ($f in 'src\WinGetUpdateTool.ps1', 'src\build.ps1', 'tests\Test-InvokeWinGet.ps1') {
    $errs = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile(
        (Join-Path $root $f), [ref]$null, [ref]$errs)
    if ($errs) { throw "$f : $($errs -join '; ')" }
    "OK parse  $f"
}

function Read-Xaml([string]$name) {
    $text = Get-Content (Join-Path $root "ui\$name") -Raw -Encoding UTF8
    [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader ([xml]$text)))
}

# 2) UI.xaml carica e i controlli cercati da FindName ci sono tutti?
$window = Read-Xaml 'UI.xaml'
"OK load   UI.xaml -> $($window.GetType().Name)"
$names = 'BtnRefresh', 'ChkUnknown', 'BtnToggleAll', 'BtnUpdate', 'BtnTheme', 'TxtAvailable',
         'TxtSelected', 'Grid', 'TxtEmpty', 'TopSpinner', 'Progress', 'TxtLog'
foreach ($n in $names) { if (-not $window.FindName($n)) { throw "controllo mancante: $n" } }
"OK names  $($names.Count) controlli trovati"

# 3) I due temi definiscono esattamente le stesse chiavi?
$light = Read-Xaml 'Theme.Light.xaml'
$dark  = Read-Xaml 'Theme.Dark.xaml'
$kl = @($light.Keys | Sort-Object)
$diff = Compare-Object $kl @($dark.Keys | Sort-Object)
if ($diff) { throw "chiavi diverse fra i due temi:`n$($diff | Out-String)" }
"OK temi   $($kl.Count) chiavi identiche nei due file"

# 4) Ogni DynamicResource di UI.xaml e' definito nei temi?
$used = [regex]::Matches((Get-Content (Join-Path $root 'ui\UI.xaml') -Raw),
                         'DynamicResource\s+(\w+)') |
        ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique
$missing = @($used | Where-Object { $kl -notcontains $_ })
if ($missing) { throw "chiavi referenziate ma assenti dai temi: $($missing -join ', ')" }
"OK ref    $($used.Count) chiavi referenziate, tutte definite"

# 5) Lo swap del dizionario ridipinge davvero (e' il meccanismo del cambio tema)?
$window.Resources.MergedDictionaries.Add($dark)
$bg = $window.Background.Color.ToString()
if ($bg -ne $dark['BgBrush'].Color.ToString()) { throw "swap dark non applicato: $bg" }
$window.Resources.MergedDictionaries.Clear()
$window.Resources.MergedDictionaries.Add($light)
$bg = $window.Background.Color.ToString()
if ($bg -ne $light['BgBrush'].Color.ToString()) { throw "swap light non applicato: $bg" }
"OK swap   dark -> light applicato via DynamicResource"

# 6) Niente sintassi PowerShell 6+ nello script: ps2exe compila contro 5.1, dove
# "`u{E706}" non e' un escape e finisce a video come "u{E706}" (rettangoli tofu).
$scriptPath = Join-Path $root 'src\WinGetUpdateTool.ps1'
$code = Get-Content $scriptPath -Raw -Encoding UTF8
# Solo codice, non commenti (il commento esplicativo cita la forma sbagliata).
$bad = @(Get-Content $scriptPath | Where-Object { $_ -notmatch '^\s*#' -and $_ -match '`u\{' })
if ($bad) { throw "escape ``u{...} (PowerShell 6+), usare [char]0x....:`n$($bad -join "`n")" }
"OK 5.1    nessun escape ``u{...} nel codice"

# 7) build.ps1 riuscira' a iniettare gli XAML nell'exe?
foreach ($f in $xamlFiles) {
    if ($code -notmatch [regex]::Escape("###$f###")) { throw "marcatore ###$f### assente" }
    $t = (Get-Content (Join-Path $root "ui\$f") -Raw -Encoding UTF8).TrimEnd()
    # Una riga che inizia con '@ chiuderebbe l'here-string dell'embedding.
    if ($t -match "(?m)^'@") { throw "$f contiene una riga che inizia con '@" }
}
"OK build  $($xamlFiles.Count) marcatori presenti, nessun XAML rompe l'here-string"

# 8) Le righe notificano WPF da sole? Senza INotifyPropertyChanged servirebbe
# $Grid.Items.Refresh() a ogni cambio di stato: quello rigenera la vista e riporta lo
# scroll in cima, cioe' il blocco dell'elenco durante l'aggiornamento.
$cs = [regex]::Match($code, "(?s)Add-Type -TypeDefinition @'\r?\n(.*?)\r?\n'@").Groups[1].Value
if (-not $cs) { throw "definizione C# di WgtRow non trovata nello script" }
if (-not ('WgtRow' -as [type])) { Add-Type -TypeDefinition $cs }
$fired = New-Object System.Collections.ArrayList
$row = [WgtRow]@{ Name = 'Test'; Id = 'Test.Id' }
$row.add_PropertyChanged({ param($s, $e) [void]$fired.Add($e.PropertyName) })
$row.Status = 'updating'
$row.Selected = $true
if ("$fired" -ne 'Status Selected') { throw "PropertyChanged non emesso come atteso: '$fired'" }
"OK notify  WgtRow emette PropertyChanged ($fired)"

# 9) Nessuno rimette a posto le due regressioni: griglia disabilitata (non si scrolla
# piu') o Items.Refresh() a ogni riga (scroll rimandato in cima).
$regress = @(Get-Content $scriptPath | Where-Object {
    $_ -notmatch '^\s*#' -and ($_ -match '\$Grid\.IsEnabled\s*=' -or $_ -match 'Items\.Refresh\(\)')
})
if ($regress) { throw "griglia bloccata durante l'update:`n$($regress -join "`n")" }
"OK scroll  nessun Grid.IsEnabled=/Items.Refresh() nel codice"

# 10) Colonne ridimensionabili? Il template custom dell'header sostituisce quello di
# sistema e con esso i due Thumb che DataGrid aggancia per trascinare il bordo: senza
# i nomi PART_*HeaderGripper esatti le colonne tornano fisse, in silenzio.
$uiText = Get-Content (Join-Path $root 'ui\UI.xaml') -Raw
foreach ($g in 'PART_LeftHeaderGripper', 'PART_RightHeaderGripper') {
    if ($uiText -notmatch [regex]::Escape($g)) { throw "gripper $g assente dal template dell'header" }
}
"OK resize  entrambi i gripper presenti nel template dell'header"

# 11) La versione e' una sola e arriva sia al titolo sia all'exe? build.ps1 la pesca
# dalla costante con una regex: se qualcuno la rinomina o la sposta, la build morirebbe
# (o l'exe uscirebbe senza versione) e il titolo mostrerebbe "[]" in silenzio.
$mv = [regex]::Match($code, "(?m)^\s*\`$AppVersion\s*=\s*'([\d.]+)'")
if (-not $mv.Success) { throw "costante `$AppVersion non trovata in src\WinGetUpdateTool.ps1" }
if ($mv.Groups[1].Value -notmatch '^\d+\.\d+\.\d+$') { throw "versione non x.y.z: '$($mv.Groups[1].Value)'" }
if ($code -notmatch '\$window\.Title\s*=.*\$AppVersion') { throw "la versione non finisce nel titolo della finestra" }
$buildText = Get-Content (Join-Path $root 'src\build.ps1') -Raw -Encoding UTF8
if ($buildText -notmatch '(?m)^\s*version\s*=\s*\$version') { throw "build.ps1 non passa la versione a ps2exe" }
"OK ver    versione $($mv.Groups[1].Value) nel titolo e nelle proprieta' dell'exe"

Write-Host "`nTUTTO OK" -ForegroundColor Green
