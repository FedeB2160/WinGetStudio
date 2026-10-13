<#
    screenshots.ps1 — disegna le immagini del README (docs\images\*.png) dall'interfaccia vera:
    monta l'app come Test-Ui.ps1, in una finestra nascosta, con dati di esempio, e la rende in
    PNG nei due temi. Niente winget, niente rete.
    NON fa parte della build: l'output e' committato. Si rilancia quando l'interfaccia cambia:
        powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\src\screenshots.ps1
    Disegnate e non catturate: si rifanno uguali a ogni modifica, nei due temi, senza dati
    della macchina di chi le genera. Manca la cornice della finestra, che la disegna Windows.
#>
$ErrorActionPreference = 'Stop'
# WPF vuole un thread STA: powershell.exe 5.1 lo e', pwsh 7 solo con -STA.
if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') { throw 'Lanciare con powershell.exe (5.1) oppure pwsh -STA' }
Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase

$root = Split-Path -Parent $PSScriptRoot   # screenshots.ps1 sta in src\
$out  = Join-Path $root 'docs\images'
[void](New-Item -ItemType Directory -Path $out -Force)

# Montaggio come in Test-Ui.ps1: main.ps1 non si dot-sourcia (si rilancerebbe elevato), quindi
# si ripetono le sue due righe innocue e si caricano i moduli dalla stessa lista.
$mainText = Get-Content (Join-Path $root 'src\main.ps1') -Raw
$mm = [regex]::Match($mainText, "(?ms)^\s*\`$moduleNames\s*=\s*@\((.*?)^\)")
$moduleNames = @([regex]::Matches($mm.Groups[1].Value, "'([^']+)'") | ForEach-Object { $_.Groups[1].Value })
$AppVersion  = [regex]::Match($mainText, "\`$AppVersion\s*=\s*'([^']+)'").Groups[1].Value
$baseDir = Join-Path $root 'src'
function Resolve-Asset([string]$rel) {
    @((Join-Path $root $rel), (Join-Path $baseDir $rel)) | Where-Object { Test-Path $_ } | Select-Object -First 1
}
foreach ($m in $moduleNames) { . (Join-Path $root "src\modules\$m") }
function Get-WinGetPath { 'C:\winget-stub\winget.exe' }
Start-App -NoShow

# Area client della finestra (900x620 meno la cornice di Windows).
$W = 884; $H = 581

function New-Row($name, $id, $ver, $avail, $status = '', [bool]$sel = $false, [bool]$pin = $false) {
    [WgtRow]@{ Name = $name; Id = $id; Version = $ver; Available = $avail; Status = $status; Selected = $sel; Pinned = $pin }
}

# Disegna la finestra (e, se c'e', un popup centrato sopra) e salva il PNG.
# Esegue cio' che e' in coda sul dispatcher: in una finestra mai mostrata nessuno lo fa.
function Invoke-Pending {
    $script:frame = New-Object System.Windows.Threading.DispatcherFrame
    [void][System.Windows.Threading.Dispatcher]::CurrentDispatcher.BeginInvoke(
        [System.Windows.Threading.DispatcherPriority]::ContextIdle, [action]{ $script:frame.Continue = $false })
    [System.Windows.Threading.Dispatcher]::PushFrame($script:frame)
}

function Save-Shot([string]$file, $dialog = $null) {
    $content = $window.Content
    # Due passaggi di layout con il dispatcher svuotato in mezzo: il DataGrid distribuisce le
    # colonne a stella (2*, 1.2*) in un passaggio rimandato, e al primo le lascia strette.
    foreach ($pass in 1, 2) {
        $content.Measure((New-Object System.Windows.Size $W, $H))
        $content.Arrange((New-Object System.Windows.Rect 0, 0, $W, $H))
        $content.UpdateLayout()
        Invoke-Pending
    }
    $rtb = New-Object System.Windows.Media.Imaging.RenderTargetBitmap $W, $H, 96, 96, ([System.Windows.Media.PixelFormats]::Pbgra32)
    $bg = New-Object System.Windows.Media.DrawingVisual
    $dc = $bg.RenderOpen()
    $dc.DrawRectangle($window.Background, $null, (New-Object System.Windows.Rect 0, 0, $W, $H))
    $dc.Close()
    $rtb.Render($bg)
    $rtb.Render($content)
    if ($dialog) {
        # Il contenuto del popup, senza la sua cornice (la disegna Windows), al centro.
        $inner = $dialog.Content; $dialog.Content = $null
        $frame = New-Object System.Windows.Controls.Border
        $frame.Resources.MergedDictionaries.Add($window.Resources)
        $frame.Background      = $dialog.Background
        $frame.BorderBrush     = $window.FindResource('CtrlBorderBrush')
        $frame.BorderThickness = 1
        $frame.Width = 440
        $frame.Child = $inner
        $frame.Measure((New-Object System.Windows.Size $W, $H))
        $x = [math]::Round(($W - $frame.DesiredSize.Width) / 2); $y = [math]::Round(($H - $frame.DesiredSize.Height) / 2)
        $frame.Arrange((New-Object System.Windows.Rect $x, $y, $frame.DesiredSize.Width, $frame.DesiredSize.Height))
        $frame.UpdateLayout()
        $rtb.Render($frame)
    }
    $enc = New-Object System.Windows.Media.Imaging.PngBitmapEncoder
    $enc.Frames.Add([System.Windows.Media.Imaging.BitmapFrame]::Create($rtb))
    $fs = [IO.File]::Create((Join-Path $out $file))
    try { $enc.Save($fs) } finally { $fs.Close() }
    Write-Host "  $file"
}

function Set-Log([string[]]$lines) {
    $TxtLog.Clear()
    foreach ($l in $lines) { $TxtLog.AppendText("$l`r`n") }
}

# ------------------------------------------------------------------
# Dati di esempio: una coda a meta', con tutti gli esiti della colonna Result e un pin.
$items.Clear()
foreach ($r in @(
    (New-Row '7-Zip'                 '7zip.7zip'                 '24.08'      '24.09'      'ok'       $true)
    (New-Row 'Git'                   'Git.Git'                   '2.46.0'     '2.47.0'     'ok'       $true)
    (New-Row 'Microsoft Visual Studio Code' 'Microsoft.VisualStudioCode' '1.94.0' '1.95.1' 'warning' $true)
    (New-Row 'Notepad++'             'Notepad++.Notepad++'       '8.6.9'      '8.7'        'error'    $true)
    (New-Row 'PowerToys'             'Microsoft.PowerToys'       '0.85.0'     '0.86.0'     'updating' $true)
    (New-Row 'VLC media player'      'VideoLAN.VLC'              '3.0.20'     '3.0.21'     ''         $true)
    (New-Row 'Python 3.12'           'Python.Python.3.12'        '3.12.6'     '3.12.7'     ''         $false $true)
    (New-Row 'Node.js LTS'           'OpenJS.NodeJS.LTS'         '20.17.0'    '20.18.0'    ''         $false)
)) { $items.Add($r) }
$TxtEmpty.Visibility = [System.Windows.Visibility]::Collapsed
$Grid.Visibility     = [System.Windows.Visibility]::Visible
Refresh-SelectionState
$Progress.IsIndeterminate = $false
$Progress.Maximum = 6; $Progress.Value = 4

$updateLog = @(
    '[10:41:02] Found 8 updates.'
    '[10:41:15] Starting update of 6 packages...'
    '[10:41:15] -> 7-Zip [7zip.7zip]'
    '[10:41:21]    OK: 7-Zip (6s)'
    '[10:41:21] -> Git [Git.Git]'
    '[10:41:48]    OK: Git (27s)'
    '[10:41:48] -> Microsoft Visual Studio Code [Microsoft.VisualStudioCode]'
    '[10:42:30]    WARNING (exit -1978335135): Microsoft Visual Studio Code'
    '[10:42:30] -> PowerToys [Microsoft.PowerToys]'
)

# Risultati di una ricerca, per la scheda Install.
$searchItems.Clear()
foreach ($r in @(
    (New-Row 'VLC media player'   'VideoLAN.VLC'          '' '3.0.21' '' $true)
    (New-Row 'VLC UWP'            '9NBLGGH4VVNH'          '' 'Unknown' '' $false)
    (New-Row 'VLC Nightly'        'VideoLAN.VLC.Nightly'  '' '4.0.0-dev' '' $false)
)) { $r.Version = $r.Available; $searchItems.Add($r) }

Write-Host "Immagini in $out"
foreach ($mode in 'Dark', 'Light') {
    $script:themeMode = $mode; Set-Theme
    $m = $mode.ToLowerInvariant()

    $TabUpdates.IsSelected = $true
    $Progress.Value = 4
    Set-Log $updateLog
    Save-Shot "updates-$m.png"

    # La barra e' condivisa: fuori da Updates non c'e' nessuna coda in corso.
    $Progress.Value = 0
    $TabInstall.IsSelected = $true
    $TxtSearch.Text = 'vlc'; $script:searchTimer.Stop()
    $TxtSearchEmpty.Visibility = [System.Windows.Visibility]::Collapsed
    $GridSearch.Visibility     = [System.Windows.Visibility]::Visible
    Refresh-InstallState
    Set-Log @('[10:43:05] Search ''vlc'': 3 results.')
    Save-Shot "install-$m.png"

    $TabSettings.IsSelected = $true
    $TxtVersion.Text = "v$AppVersion"
    $TxtWinGetVersion.Text = 'v1.29.380.0'
    $TxtWinGetStore.Visibility = [System.Windows.Visibility]::Visible
    Set-Log @('[10:40:58] winget is ready (App Installer 1.29.380.0).')
    Save-Shot "settings-$m.png"

    # Un popup a tema sopra la finestra oscurata.
    $Progress.Value = 4
    $TabUpdates.IsSelected = $true
    Set-Log $updateLog
    Set-DialogDim $true -Animate:$false
    $dlg = New-AppDialog -Text "Uninstall 2 packages?`n`n7-Zip`nVLC media player`n`nThis cannot be undone." -Title 'Confirm uninstall' `
        -Button ([System.Windows.MessageBoxButton]::YesNo) -Image ([System.Windows.MessageBoxImage]::Warning) `
        -Default ([System.Windows.MessageBoxResult]::No)
    Save-Shot "dialog-$m.png" $dlg
    Set-DialogDim $false -Animate:$false
}
