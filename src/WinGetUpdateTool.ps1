<#
    WinGetUpdateTool.ps1
    ---------------------
    Tool WPF standalone per gestire gli aggiornamenti winget con selezione a checkbox.
    - Richiede privilegi amministratore (self-elevation + manifest via ps2exe).
    - Esegue "winget upgrade" (con --include-unknown opzionale) e mostra i risultati in un DataGrid.
    - Aggiorna solo gli elementi selezionati, in modo asincrono (UI non bloccante).
    - Tema Chiaro / Scuro / Auto (segue il sistema), pulsante ciclico in alto a destra.

    La UI sta in ..\ui\*.xaml, non qui dentro: build.ps1 la inietta nell'exe al posto
    dei marcatori ###nome.xaml### piu' sotto, cosi' l'eseguibile resta un file solo.

    Compilazione: build.bat (oppure src\build.ps1) — vedi README.md
#>

# ------------------------------------------------------------------
# VERSIONE
# ------------------------------------------------------------------
# UNICA fonte di verita': finisce nel titolo della finestra come "[x.y.z]" e, letta
# da build.ps1 con questa stessa regex, nelle proprieta' dell'exe (scheda Dettagli).
# Aggiornarla qui e basta; Test-Ui.ps1 verifica che la regex la trovi ancora.
$AppVersion = '1.0.1'

# ------------------------------------------------------------------
# 1) SELF-ELEVATION (fallback al manifest UAC generato da ps2exe)
# ------------------------------------------------------------------
# Se lo script/exe non gira come amministratore, si rilancia elevato e termina.
$identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
$isAdmin   = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    try {
        # GetCommandLineArgs()[0] = host che esegue (powershell.exe oppure il .exe compilato)
        $exe = [Environment]::GetCommandLineArgs()[0]

        if ($exe -match '(?i)powershell(\.exe)?$|pwsh(\.exe)?$') {
            # Eseguito come .ps1 tramite PowerShell: rilancio passando il percorso dello script
            $scriptPath = $PSCommandPath
            Start-Process -FilePath $exe -Verb RunAs `
                -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
        }
        else {
            # Eseguito come .exe compilato: rilancio l'exe stesso elevato
            Start-Process -FilePath $exe -Verb RunAs
        }
    }
    catch {
        # L'utente ha annullato il prompt UAC (o errore): esci silenziosamente
    }
    exit
}

# ------------------------------------------------------------------
# Assembly WPF
# ------------------------------------------------------------------
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

# Output winget in UTF-8 (nomi con accenti/caratteri non-ASCII)
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

# ------------------------------------------------------------------
# Riga della griglia (INotifyPropertyChanged)
# ------------------------------------------------------------------
# PERCHE' NON UN PSCustomObject: le NoteProperty non notificano WPF, quindi ogni cambio
# di stato richiedeva $Grid.Items.Refresh(). Quel Refresh rigenera l'intera vista e
# riporta lo scroll in cima: durante l'aggiornamento veniva chiamato 3 volte per
# pacchetto, rendendo l'elenco di fatto non scorrevole. Con INotifyPropertyChanged si
# ridisegna la sola cella cambiata e lo scroll resta dov'e' l'utente.
# NB: i setter vanno invocati sul thread UI (nel runspace di update passano da UI{}).
if (-not ('WgtRow' -as [type])) {
    Add-Type -TypeDefinition @'
using System.ComponentModel;
public class WgtRow : INotifyPropertyChanged {
    public event PropertyChangedEventHandler PropertyChanged;
    private void P(string n) {
        PropertyChangedEventHandler h = PropertyChanged;
        if (h != null) h(this, new PropertyChangedEventArgs(n));
    }
    private bool _selected;
    private string _name = "", _version = "", _available = "", _id = "", _status = "", _detail = "";
    public bool Selected      { get { return _selected; }  set { _selected = value;  P("Selected"); } }
    public string Name        { get { return _name; }      set { _name = value;      P("Name"); } }
    public string Version     { get { return _version; }   set { _version = value;   P("Version"); } }
    public string Available   { get { return _available; } set { _available = value; P("Available"); } }
    public string Id          { get { return _id; }        set { _id = value;        P("Id"); } }
    public string Status      { get { return _status; }    set { _status = value;    P("Status"); } }
    public string StatusDetail{ get { return _detail; }    set { _detail = value;    P("StatusDetail"); } }
}
'@
}

# ------------------------------------------------------------------
# 2) CHECK: winget presente?
# ------------------------------------------------------------------
$wingetCmd = Get-Command winget -ErrorAction SilentlyContinue
if (-not $wingetCmd) {
    [System.Windows.MessageBox]::Show(
        "winget is not installed or not available in PATH.`n`n" +
        "Install 'App Installer' from the Microsoft Store (Windows 10/11) and try again.",
        "winget not found",
        [System.Windows.MessageBoxButton]::OK,
        [System.Windows.MessageBoxImage]::Error) | Out-Null
    exit 1
}

# ------------------------------------------------------------------
# 3) PARSING OUTPUT WINGET (punto critico)
# ------------------------------------------------------------------
# winget stampa una TABELLA A LARGHEZZA FISSA. I nomi contengono spazi, quindi
# NON si puo' fare split su spazi: si parsa per posizione delle colonne, ricavata
# dagli offset della riga di header.
function Get-WinGetUpgrades([bool]$IncludeUnknown = $false) {
    # --include-unknown: include pacchetti con versione installata sconosciuta (opzionale,
    #   la spunta in alto lo comanda: senza, winget elenca solo cio' di cui sa la versione)
    # --accept-source-agreements: evita prompt interattivi al primo uso della sorgente
    $wgArgs = @('upgrade', '--accept-source-agreements')
    if ($IncludeUnknown) { $wgArgs += '--include-unknown' }
    # -Width alto: senza console (exe -noConsole) o con finestra stretta Out-String
    # manderebbe a capo le righe alla larghezza dell'host, spezzando la tabella.
    $raw = & winget @wgArgs 2>&1 | Out-String -Width 4096

    # Normalizza in righe; winget usa \r di progresso -> tieni solo l'ultimo segmento
    $lines = $raw -split "`r`n|`n" | ForEach-Object { ($_ -split "`r")[-1] }

    # Estrae in sicurezza una sottostringa [start, end) gestendo righe corte.
    function Get-Field([string]$line, [int]$start, [int]$end) {
        if ($start -lt 0 -or $start -ge $line.Length) { return '' }
        if ($end -lt 0 -or $end -gt $line.Length) { $end = $line.Length }
        if ($end -le $start) { return '' }
        return $line.Substring($start, $end - $start).Trim()
    }

    # INDIPENDENTE DALLA LINGUA: winget localizza gli header (Nome/ID/Versione/...)
    # ma la riga separatore e' sempre una sequenza di trattini. La usiamo come ancora:
    # header = riga subito prima del separatore; dati = righe subito dopo.
    # MULTI-TABELLA: l'output puo' contenere PIU' tabelle — dopo gli upgrade normali
    # winget ne stampa una seconda per i pacchetti che richiedono targeting esplicito
    # ("...ma e' necessario un targeting esplicito per l'aggiornamento"), con larghezze
    # di colonna PROPRIE. Con una sola ancora fissa quella tabella veniva letta con gli
    # offset della prima: il suo header finiva in griglia come riga fantasma e i suoi
    # pacchetti (es. Discord) sparivano. Quindi si ri-ancora a ogni separatore.
    $results = New-Object System.Collections.ArrayList
    $oName = -1; $oId = -1; $oVer = -1; $oAvail = -1; $oEnd = -1

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ([string]::IsNullOrWhiteSpace($line)) { continue }

        # Separatore: apre una tabella, gli offset arrivano dalla riga di header sopra.
        if ($line.Trim() -match '^-{3,}$') {
            $oName = -1   # tabella inattesa fino a prova contraria
            $header = if ($i -gt 0) { $lines[$i - 1] } else { '' }

            # Offset di inizio colonna: posizioni nella riga header dove inizia un token
            # (carattere non-spazio preceduto da spazio o inizio riga). L'ORDINE delle
            # colonne e' fisso: Nome, Id, Versione, Disponibile, [Origine].
            $colStarts = New-Object System.Collections.ArrayList
            for ($c = 0; $c -lt $header.Length; $c++) {
                $isStart = ($header[$c] -ne ' ') -and ($c -eq 0 -or $header[$c-1] -eq ' ')
                if ($isStart) { [void]$colStarts.Add($c) }
            }
            if ($colStarts.Count -ge 4) {
                $oName = $colStarts[0]; $oId = $colStarts[1]
                $oVer  = $colStarts[2]; $oAvail = $colStarts[3]
                $oEnd  = if ($colStarts.Count -ge 5) { $colStarts[4] } else { -1 }  # inizio Origine o fine riga
            }
            continue
        }

        if ($oName -lt 0) { continue }   # fuori da una tabella riconosciuta
        # Riga di header (la prossima e' il separatore): non e' un dato.
        if ($i + 1 -lt $lines.Count -and $lines[$i + 1].Trim() -match '^-{3,}$') { continue }

        # Filtro riepilogo/prose localizzata ("N aggiornamenti disponibili.", la frase
        # sul targeting esplicito, ecc.): una riga dati rispetta la griglia, cioe' ogni
        # inizio colonna e' preceduto da almeno uno spazio di padding. Una frase no.
        # NB: NON si filtra sul numero di token separati da 2+ spazi — nella seconda
        # tabella le colonne sono strette e distano un solo spazio.
        $aligned = $true
        foreach ($o in @($oId, $oVer, $oAvail, $oEnd)) {
            if ($o -gt 0 -and $o -le $line.Length -and $line[$o - 1] -ne ' ') { $aligned = $false; break }
        }
        if (-not $aligned) { continue }

        $name      = Get-Field $line $oName  $oId
        $id        = Get-Field $line $oId    $oVer
        $version   = Get-Field $line $oVer   $oAvail
        $available = Get-Field $line $oAvail $oEnd

        if ([string]::IsNullOrWhiteSpace($id)) { continue }

        [void]$results.Add([WgtRow]@{
            Selected     = $false
            Name         = $name
            Version      = $version
            Available    = $available
            Id           = $id
        })
    }
    return $results
}

# Mappa l'exit code di winget in un token di stato: ok / warning / error.
function Get-UpdateStatus([int]$code) {
    if ($code -eq 0) { return 'ok' }
    # winget usa HRESULT (Int32 negativi). NB: un literal hex a 8 cifre in PowerShell
    # e' Int32 (0xFFFFFFFF = -1!), quindi si lavora in Int64 con suffisso L e si
    # normalizza al valore unsigned a 32 bit.
    $u = ([int64]$code) -band 0xFFFFFFFFL
    $benign = @(
        0x8A150108L,  # REBOOT_REQUIRED_TO_FINISH
        0x8A150109L,  # REBOOT_REQUIRED_FOR_INSTALL
        0x8A15010AL,  # REBOOT_INITIATED
        0x8A15010CL,  # ALREADY_INSTALLED
        3010L,        # ERROR_SUCCESS_REBOOT_REQUIRED
        1641L         # ERROR_SUCCESS_REBOOT_INITIATED
    )
    if ($benign -contains $u) { return 'warning' }
    return 'error'
    # ponytail: lista codici benigni tunabile; se ne emergono altri, aggiungere qui.
}

# Esegue winget e attende SOLO l'uscita del processo, catturando l'output SU FILE.
# PERCHE' NON '& winget ... | Out-String': la pipeline ritorna all'EOF della pipe di
# stdout, cioe' quando TUTTI i processi che possiedono quel handle lo chiudono. Gli
# installer silenziosi lanciati da winget ereditano il handle: se uno resta vivo (o si
# rilancia staccandosi) l'EOF non arriva mai e l'attesa e' infinita, anche a winget
# uscito e pacchetti installati. Con redirect su file + WaitForExit() il completamento
# dipende dal solo winget.
# NB: -Wait di Start-Process attende anche i DISCENDENTI, cioe' proprio cio' da cui
# stiamo scappando -> -PassThru + WaitForExit().
# $Tick viene invocato ogni 30s con i secondi trascorsi (log "elapsed"). Nessun
# timeout: gli installer lenti non vengono troncati.
function Invoke-WinGet([string]$exePath, [string]$argLine, [scriptblock]$Tick) {
    $outFile = Join-Path ([IO.Path]::GetTempPath()) "wgt_$([Guid]::NewGuid().ToString('N')).out"
    $errFile = [IO.Path]::ChangeExtension($outFile, 'err')
    try {
        # PERCHE' NON Start-Process -PassThru: il suo oggetto Process perde ExitCode se il
        # processo esce prima che il handle nativo sia stato letto (race vinta dai comandi
        # rapidi). ExitCode vuoto castato a int fa 0 -> Get-UpdateStatus dice 'ok' e un
        # fallimento risulta verde. Con Process.Start il handle e' nostro dall'inizio.
        # Il redirect su file lo fa cmd (/s /c + tutta la riga tra apici: cmd toglie solo
        # gli apici esterni e passa il resto verbatim), cosi' non ci sono pipe da svuotare
        # e l'attesa dipende dal solo processo.
        $psi = New-Object Diagnostics.ProcessStartInfo
        $psi.FileName        = 'cmd.exe'
        $psi.Arguments       = "/d /s /c `"`"$exePath`" $argLine >`"$outFile`" 2>`"$errFile`"`""
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow  = $true
        $p = [Diagnostics.Process]::Start($psi)
        $sw = [Diagnostics.Stopwatch]::StartNew()
        while (-not $p.WaitForExit(30000)) {
            if ($Tick) { & $Tick ([int]$sw.Elapsed.TotalSeconds) }
        }
        # -Encoding UTF8 OBBLIGATORIO: winget scrive UTF-8, ma Get-Content in
        # PowerShell 5.1 assume il codepage ANSI del sistema -> i messaggi localizzati
        # arrivavano a mojibake ("Ã¨ stata trovata una versione piÃ¹ recente").
        # NB: -Encoding UTF8 legge correttamente anche senza BOM.
        $text = [string](Get-Content $outFile -Raw -Encoding UTF8 -ErrorAction SilentlyContinue) +
                [string](Get-Content $errFile -Raw -Encoding UTF8 -ErrorAction SilentlyContinue)
        return [PSCustomObject]@{
            ExitCode = $p.ExitCode
            Output   = $text
            Seconds  = [int]$sw.Elapsed.TotalSeconds
        }
    }
    finally {
        foreach ($f in @($outFile, $errFile)) { Remove-Item $f -Force -ErrorAction SilentlyContinue }
    }
}

# Percorso reale di winget (l'alias di esecuzione app va bene per Process.Start).
# Riusa il Get-Command del check iniziale.
$wingetPath = if ($wingetCmd.Source) { $wingetCmd.Source } else { 'winget' }

# ------------------------------------------------------------------
# 4) UI WPF — XAML in file esterni
# ------------------------------------------------------------------
# Cartella base: $PSScriptRoot e' vuoto nell'exe compilato con ps2exe,
# quindi si ripiega su PSCommandPath o sul percorso del processo.
$baseDir = if ($PSScriptRoot) { $PSScriptRoot }
           elseif ($PSCommandPath) { Split-Path -Parent $PSCommandPath }
           else { Split-Path -Parent ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }

# Copie embeddate dei file XAML: build.ps1 sostituisce i marcatori ###nome### col
# contenuto reale, cosi' l'exe resta un file solo. Eseguito come .ps1 i marcatori
# restano tali, ma non importa: i file su disco ci sono e hanno la precedenza.
$embeddedXaml = @{
    'UI.xaml' = @'
###UI.xaml###
'@
    'Theme.Light.xaml' = @'
###Theme.Light.xaml###
'@
    'Theme.Dark.xaml' = @'
###Theme.Dark.xaml###
'@
}

# Cerca un file di corredo in tre posti: nel layout del repo (lo script sta in src\,
# le risorse in ui\ e assets\ un livello sopra), accanto all'exe con la stessa
# struttura, oppure sciolto accanto all'exe. Torna $null se non c'e'.
function Resolve-Asset([string]$rel) {
    if (-not $baseDir) { return $null }
    $parent = Split-Path -Parent $baseDir
    $cand = @((Join-Path $baseDir $rel), (Join-Path $baseDir (Split-Path $rel -Leaf)))
    if ($parent) { $cand = @(Join-Path $parent $rel) + $cand }
    foreach ($p in $cand) { if (Test-Path $p) { return $p } }
    return $null
}

# File su disco se presente (si ritocca la UI senza ricompilare), altrimenti la copia
# embeddata nell'exe.
function Get-XamlText([string]$name) {
    $p = Resolve-Asset "ui\$name"
    if ($p) { return (Get-Content $p -Raw -Encoding UTF8) }
    return $embeddedXaml[$name]
}

# Ritorna l'oggetto radice del file: Window per UI.xaml, ResourceDictionary per i temi.
function Read-Xaml([string]$name) {
    $text = Get-XamlText $name
    if ([string]::IsNullOrWhiteSpace($text) -or $text -match '^\s*###') {
        throw "XAML not available: $name"
    }
    [Windows.Markup.XamlReader]::Load(
        (New-Object System.Xml.XmlNodeReader ([xml]$text)))
}

$window = Read-Xaml 'UI.xaml'

# Versione in coda al titolo: il nome resta in UI.xaml con le altre stringhe visibili.
$window.Title = "$($window.Title) [$AppVersion]"

# Riferimenti ai controlli
$BtnRefresh   = $window.FindName('BtnRefresh')
$ChkUnknown   = $window.FindName('ChkUnknown')
$BtnToggleAll = $window.FindName('BtnToggleAll')
$BtnUpdate    = $window.FindName('BtnUpdate')
$TxtAvailable = $window.FindName('TxtAvailable')
$TxtSelected  = $window.FindName('TxtSelected')
$Grid         = $window.FindName('Grid')
$TxtEmpty     = $window.FindName('TxtEmpty')
$TopSpinner   = $window.FindName('TopSpinner')
$Progress     = $window.FindName('Progress')
$TxtLog       = $window.FindName('TxtLog')
$BtnTheme     = $window.FindName('BtnTheme')

# Icona finestra: come .exe (ps2exe -iconFile) l'icona e' gia' embeddata;
# come .ps1 in sviluppo carica assets\icon.ico se presente.
$iconPath = Resolve-Asset 'assets\icon.ico'
if ($iconPath) {
    try { $window.Icon = [Windows.Media.Imaging.BitmapFrame]::Create([Uri]$iconPath) } catch { }
}

# ------------------------------------------------------------------
# 4b) TEMA: Light / Dark / Auto
# ------------------------------------------------------------------
# I colori stanno in Theme.Light.xaml / Theme.Dark.xaml e vengono montati in
# Resources.MergedDictionaries: UI.xaml li referenzia con DynamicResource, quindi
# lo swap del dizionario ridipinge la finestra senza ricrearla.
$themeKey = 'HKCU:\Software\WinGetUpdateTool'
$script:themeMode = 'Auto'   # Auto | Light | Dark
try {
    $saved = (Get-ItemProperty -Path $themeKey -Name Theme -ErrorAction Stop).Theme
    if ($saved -in @('Auto', 'Light', 'Dark')) { $script:themeMode = $saved }
} catch { }

# Tema di sistema: AppsUseLightTheme = 0 -> scuro. Assente su Win10 vecchi -> chiaro.
function Test-SystemDark {
    try {
        (Get-ItemPropertyValue -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize' `
                               -Name 'AppsUseLightTheme' -ErrorAction Stop) -eq 0
    } catch { $false }
}

$script:dwmReady = $false
function Set-TitleBarDark([bool]$dark) {
    # Senza questo la barra titolo resta bianca in Dark-Mode (la disegna Windows, non WPF).
    if (-not $dark -and -not $script:dwmReady) { return }   # gia' chiara: niente da fare
    if (-not $script:dwmReady) {
        # Add-Type -MemberDefinition compila C# al volo (~1s): si paga solo al primo
        # passaggio in Dark-Mode, non a ogni avvio.
        Add-Type -Namespace Dwm -Name Api -MemberDefinition @'
[DllImport("dwmapi.dll")]
public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int val, int size);
'@
        $script:dwmReady = $true
    }
    $hwnd = (New-Object Windows.Interop.WindowInteropHelper $window).Handle
    if ($hwnd -eq [IntPtr]::Zero) { return }   # finestra non ancora mostrata
    $v = [int]$dark
    # DWMWA_USE_IMMERSIVE_DARK_MODE = 20 (Win10 2004+ / Win11). Su build precedenti
    # l'attributo non esiste: la chiamata torna errore e la barra resta chiara.
    [void][Dwm.Api]::DwmSetWindowAttribute($hwnd, 20, [ref]$v, 4)
}

function Set-Theme {
    $dark = switch ($script:themeMode) {
        'Dark'  { $true }
        'Light' { $false }
        default { Test-SystemDark }
    }
    $window.Resources.MergedDictionaries.Clear()
    $window.Resources.MergedDictionaries.Add(
        (Read-Xaml $(if ($dark) { 'Theme.Dark.xaml' } else { 'Theme.Light.xaml' })))
    Set-TitleBarDark $dark

    # Icone dal set di sistema: E706 sole, E708 luna, F08C sole con la luna dentro
    # (il "mix" per Auto). Presenti sia in Segoe Fluent Icons sia in Segoe MDL2 Assets.
    # NB: [char]0x.... e non "`u{....}" — l'escape `u esiste solo da PowerShell 6, e
    # ps2exe compila contro 5.1: la stringa resterebbe il letterale "u{E706}" (tofu).
    $glyph, $tip = switch ($script:themeMode) {
        'Light' { [char]0xE706, 'Theme: Light' }
        'Dark'  { [char]0xE708, 'Theme: Dark' }
        default { [char]0xF08C, 'Theme: Auto (follows the system)' }
    }
    $BtnTheme.Content = $glyph
    $BtnTheme.ToolTip = $tip
}

$BtnTheme.Add_Click({
    $script:themeMode = switch ($script:themeMode) {
        'Light' { 'Dark' }
        'Dark'  { 'Auto' }
        default { 'Light' }
    }
    try {
        if (-not (Test-Path $themeKey)) { New-Item -Path $themeKey -Force | Out-Null }
        Set-ItemProperty -Path $themeKey -Name Theme -Value $script:themeMode
    } catch { }   # scelta non persistita: non e' un motivo per non applicare il tema
    Set-Theme
})

# In Auto: segue il tema di sistema a caldo.
# ponytail: poll a 5s invece di SystemEvents.UserPreferenceChanged — l'evento arriva su un
# thread non-UI e va deiscritto a mano, altrimenti il processo non esce. Se servisse
# reattivita' istantanea, passare all'evento con unsubscribe in Add_Closed.
$script:lastSysDark = Test-SystemDark
$script:themeTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:themeTimer.Interval = [TimeSpan]::FromSeconds(5)
$script:themeTimer.Add_Tick({
    if ($script:themeMode -ne 'Auto') { return }
    $d = Test-SystemDark
    if ($d -ne $script:lastSysDark) { $script:lastSysDark = $d; Set-Theme }
})
$script:themeTimer.Start()

Set-Theme

# Collezione dati (ObservableCollection per binding checkbox bidirezionale)
$items = New-Object System.Collections.ObjectModel.ObservableCollection[object]
$Grid.ItemsSource = $items

# Stato condiviso tra UI e runspace
$script:allSelected = $false
$script:isBusy      = $false

# --- Helper UI ---
function Write-Log([string]$msg) {
    $ts = (Get-Date).ToString('HH:mm:ss')
    $TxtLog.AppendText("[$ts] $msg`r`n")
    $TxtLog.ScrollToEnd()
}

# Ricalcola stato pulsanti/etichette in base a elenco e selezione (req 2/3/4).
function Refresh-SelectionState {
    $total = $items.Count
    $sel   = @($items | Where-Object { $_.Selected }).Count

    # req3: "Seleziona tutto" attivo solo se c'e' almeno un elemento (e non occupato)
    $BtnToggleAll.IsEnabled = (-not $script:isBusy) -and ($total -gt 0)
    # req4: "Aggiorna" attivo solo se almeno uno selezionato
    $BtnUpdate.IsEnabled    = (-not $script:isBusy) -and ($sel -gt 0)

    # Allinea l'etichetta del toggle allo stato reale della selezione
    $script:allSelected   = ($total -gt 0 -and $sel -eq $total)
    $BtnToggleAll.Content = if ($script:allSelected) { "Deselect all" } else { "Select all" }

    # Due contatori: disponibili (top) e selezionati (action bar)
    $TxtAvailable.Text = if ($total -eq 0) { "" } elseif ($total -eq 1) { "1 update available" } else { "$total updates available" }
    $TxtSelected.Text  = if ($sel -gt 0) { "$sel selected" } else { "" }
}

function Set-BusyState([bool]$busy) {
    $script:isBusy = $busy
    $BtnRefresh.IsEnabled = -not $busy
    $ChkUnknown.IsEnabled = -not $busy
    # Sola lettura, NON IsEnabled=$false: un DataGrid disabilitato non risponde piu' a
    # rotellina, scrollbar e tastiera -> durante l'update l'elenco sembrava congelato.
    # IsReadOnly blocca solo l'edit delle checkbox, che e' l'unica cosa da impedire.
    if ($busy) { [void]$Grid.CommitEdit() }
    $Grid.IsReadOnly = $busy
    if ($busy) {
        # Durante un'operazione i pulsanti selezione/aggiorna sono sempre spenti
        $BtnToggleAll.IsEnabled = $false
        $BtnUpdate.IsEnabled    = $false
    }
    else {
        # A riposo lo stato dipende da elenco e selezione
        Refresh-SelectionState
    }
}

# Carica/ricarica l'elenco upgrade in modo ASINCRONO (req 1): la scansione winget
# gira in un runspace separato cosi' l'overlay di caricamento resta animato.
function Load-Upgrades {
    Set-BusyState $true
    Write-Log "Searching for updates..."
    $items.Clear()
    $TxtEmpty.Visibility     = [System.Windows.Visibility]::Collapsed
    $Grid.Visibility         = [System.Windows.Visibility]::Collapsed
    $TopSpinner.Visibility   = [System.Windows.Visibility]::Visible
    # Azzera la barra: appartiene alla coda di aggiornamento precedente, non al nuovo elenco
    $Progress.Value   = 0
    $Progress.Maximum = 100
    Refresh-SelectionState

    # Passa il codice del parser al runspace (i runspace non condividono le funzioni)
    $fnBody = ${function:Get-WinGetUpgrades}.ToString()
    $incUnknown = [bool]$ChkUnknown.IsChecked

    # NB: le variabili condivise col Tick devono stare in scope $script: perche'
    # gli scriptblock degli eventi non catturano le variabili LOCALI di funzione.
    $script:scanRs = [RunspaceFactory]::CreateRunspace()
    $script:scanRs.ApartmentState = 'STA'
    $script:scanRs.ThreadOptions  = 'ReuseThread'
    $script:scanRs.Open()
    $script:scanRs.SessionStateProxy.SetVariable('fnBody', $fnBody)
    $script:scanRs.SessionStateProxy.SetVariable('incUnknown', $incUnknown)

    $script:scanPs = [PowerShell]::Create()
    $script:scanPs.Runspace = $script:scanRs
    [void]$script:scanPs.AddScript({
        try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
        Invoke-Expression "function Get-WinGetUpgrades { $fnBody }"
        Get-WinGetUpgrades $incUnknown   # niente virgola: gli elementi devono scorrere singoli sulla pipeline
    })

    # Poll di completamento sul thread UI: popola la griglia e ripristina lo stato
    $script:scanHandle = $script:scanPs.BeginInvoke()
    $script:scanTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:scanTimer.Interval = [TimeSpan]::FromMilliseconds(200)
    $script:scanTimer.Add_Tick({
        if (-not $script:scanHandle.IsCompleted) { return }
        $script:scanTimer.Stop()

        $result = @()
        try { $result = @($script:scanPs.EndInvoke($script:scanHandle)) }
        catch { Write-Log "ERROR while searching: $($_.Exception.Message)" }
        $script:scanPs.Dispose(); $script:scanRs.Close(); $script:scanRs.Dispose()
        $script:scanPs = $null; $script:scanRs = $null

        $TopSpinner.Visibility   = [System.Windows.Visibility]::Collapsed
        foreach ($u in $result) { if ($u) { $items.Add($u) } }

        if ($items.Count -eq 0) {
            $TxtEmpty.Visibility = [System.Windows.Visibility]::Visible
            $Grid.Visibility     = [System.Windows.Visibility]::Collapsed
            Write-Log "No updates available."
        }
        else {
            $Grid.Visibility = [System.Windows.Visibility]::Visible
            Write-Log "Found $($items.Count) updates."
        }
        Set-BusyState $false
    })
    $script:scanTimer.Start()
}

# ------------------------------------------------------------------
# 5) AGGIORNAMENTO ASINCRONO (runspace in background)
# ------------------------------------------------------------------
# Esegue winget per ogni elemento selezionato in SEQUENZA (winget non e'
# affidabile in parallelo). La UI resta reattiva: il lavoro pesante gira in un
# runspace separato e aggiorna la UI via $window.Dispatcher.Invoke().
function Start-UpdateSelected {
    $selected = @($items | Where-Object { $_.Selected })
    if ($selected.Count -eq 0) {
        [System.Windows.MessageBox]::Show(
            "No items selected.", "WinGet Update Tool",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Information) | Out-Null
        return
    }

    # Azzera eventuali esiti precedenti sulle righe da aggiornare
    foreach ($item in $selected) { $item.Status = ''; $item.StatusDetail = '' }

    Set-BusyState $true
    $Progress.Value = 0
    $Progress.Maximum = $selected.Count
    Write-Log "Starting update of $($selected.Count) packages..."

    # Passa gli oggetti riga al runspace (aggiornati per riferimento).
    # Scope $script: per lo stesso motivo di Load-Upgrades (Tick non vede le locali).
    $script:updRs = [RunspaceFactory]::CreateRunspace()
    $script:updRs.ApartmentState = 'STA'
    $script:updRs.ThreadOptions  = 'ReuseThread'
    $script:updRs.Open()
    $script:updRs.SessionStateProxy.SetVariable('window',   $window)
    $script:updRs.SessionStateProxy.SetVariable('selected', $selected)
    $script:updRs.SessionStateProxy.SetVariable('progress', $Progress)
    $script:updRs.SessionStateProxy.SetVariable('txtLog',   $TxtLog)
    $script:updRs.SessionStateProxy.SetVariable('wingetPath', $wingetPath)
    # Passa il corpo delle funzioni (i runspace non condividono le funzioni)
    $script:updRs.SessionStateProxy.SetVariable('statusFnBody', ${function:Get-UpdateStatus}.ToString())
    $script:updRs.SessionStateProxy.SetVariable('wingetFnBody', ${function:Invoke-WinGet}.ToString())

    $script:updPs = [PowerShell]::Create()
    $script:updPs.Runspace = $script:updRs

    [void]$script:updPs.AddScript({
        Invoke-Expression "function Get-UpdateStatus { $statusFnBody }"
        Invoke-Expression "function Invoke-WinGet { $wingetFnBody }"

        # Helper per aggiornare la UI dal thread di lavoro
        function UI([scriptblock]$action) {
            $window.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::Background, [action]$action)
        }
        function LogUI([string]$m) {
            $ts = (Get-Date).ToString('HH:mm:ss')
            UI { $txtLog.AppendText("[$ts] $m`r`n"); $txtLog.ScrollToEnd() }
        }

        $done = 0
        foreach ($item in $selected) {
            $id   = $item.Id
            $name = $item.Name
            UI { $item.Status = 'updating'; $item.StatusDetail = 'In progress...' }
            LogUI "-> $name [$id]"
            try {
                # Aggiornamento silenzioso, match esatto sull'ID.
                # --disable-interactivity: senza console (exe -noConsole) un prompt di
                # winget resterebbe in attesa di input per sempre.
                $r = Invoke-WinGet $wingetPath `
                        "upgrade --id `"$id`" --include-unknown -e --silent --disable-interactivity --accept-source-agreements --accept-package-agreements" `
                        { param($s) LogUI "   ...$name running for ${s}s" }
                $code  = $r.ExitCode
                $token = Get-UpdateStatus $code

                UI { $item.Status = $token; $item.StatusDetail = "exit $code" }
                switch ($token) {
                    'ok'      { LogUI "   OK: $name ($($r.Seconds)s)" }
                    'warning' { LogUI "   WARNING (exit $code): $name" }
                    default {
                        LogUI "   ERROR (exit $code): $name"
                        # Ultime DUE righe significative dell'output winget: quando
                        # l'installer fallisce, winget stampa il percorso del suo log
                        # DOPO il messaggio d'errore, quindi l'ultima riga da sola
                        # riportava solo il path e nascondeva la causa.
                        $tail = @($r.Output -split "`r`n|`n" | Where-Object { $_.Trim() } | Select-Object -Last 2)
                        foreach ($l in $tail) { LogUI "      $($l.Trim())" }
                    }
                }
            }
            catch {
                # Errore sul singolo pacchetto: NON interrompe la coda
                $msg = $_.Exception.Message
                UI { $item.Status = 'error'; $item.StatusDetail = $msg }
                LogUI "   EXCEPTION: $msg"
            }
            finally {
                $done++
                UI { $progress.Value = $done }
            }
        }
        LogUI "Update complete ($done/$($selected.Count))."
    })

    # Callback a fine runspace: riabilita la UI e pulisce
    $script:updHandle = $script:updPs.BeginInvoke()
    $script:updTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:updTimer.Interval = [TimeSpan]::FromMilliseconds(300)
    $script:updTimer.Add_Tick({
        if (-not $script:updHandle.IsCompleted) { return }
        $script:updTimer.Stop()
        try { $script:updPs.EndInvoke($script:updHandle) } catch { }
        $script:updPs.Dispose()
        $script:updRs.Close()
        $script:updRs.Dispose()
        $script:updPs = $null; $script:updRs = $null
        Set-BusyState $false
    })
    $script:updTimer.Start()
}

# ------------------------------------------------------------------
# Event handlers
# ------------------------------------------------------------------
$BtnRefresh.Add_Click({ Load-Upgrades })

$BtnToggleAll.Add_Click({
    # Riallinea $script:allSelected allo stato REALE: il refresh differito di una spunta
    # manuale gira a priorita' Background, quindi dopo questo Click. Senza il ricalcolo
    # il pulsante agisce sulla cache vecchia (es. deseleziona con 4/5 selezionati).
    Refresh-SelectionState
    $newState = -not $script:allSelected
    # Chiude un'eventuale transazione di edit aperta, altrimenti il DataGrid al termine
    # dell'edit riscrive sulla riga il valore che aveva prima del clic sul pulsante.
    [void]$Grid.CommitEdit()
    foreach ($it in $items) { $it.Selected = $newState }
    Refresh-SelectionState
})

$BtnUpdate.Add_Click({ Start-UpdateSelected })

# Aggiorna stato pulsanti/contatore quando l'utente spunta/despunta manualmente.
# Il binding e' UpdateSourceTrigger=PropertyChanged, ma il valore arriva sull'oggetto solo
# DOPO che il ToggleButton ha commutato: il ricalcolo va rimandato a priorita' Background.
# NB: BeginInvoke([action]{...}, 'Background') NON esiste come overload -> PowerShell
# risolve su BeginInvoke(Delegate, params Object[]) e passa 'Background' COME ARGOMENTO a
# un delegate senza parametri => TargetParameterCountException, che risale da ShowDialog().
# Va usata la forma con la priorita' PER PRIMA e l'enum tipizzato.
$queueSelectionRefresh = {
    $window.Dispatcher.BeginInvoke(
        [System.Windows.Threading.DispatcherPriority]::Background,
        [action]{ Refresh-SelectionState }) | Out-Null
}
$Grid.Add_CellEditEnding($queueSelectionRefresh)
# PreviewMouseLeftButtonUp: evento tunneling, raggiunge la griglia prima che il CheckBox
# marchi l'evento come gestito -> contatore e label si aggiornano al click, non alla
# perdita di focus della cella.
$Grid.Add_PreviewMouseLeftButtonUp($queueSelectionRefresh)

# Alla chiusura: ferma timer e chiudi eventuali runspace pendenti, cosi' il
# processo termina davvero (niente thread in background lasciati vivi).
$window.Add_Closed({
    foreach ($t in @($script:scanTimer, $script:updTimer, $script:themeTimer)) { if ($t) { try { $t.Stop() } catch { } } }
    foreach ($r in @($script:scanRs, $script:updRs))       { if ($r) { try { $r.Dispose() } catch { } } }
})

# Carica gli upgrade all'apertura. Secondo Set-Theme: al primo giro la finestra non aveva
# ancora un HWND, quindi la barra titolo non era stata colorata.
$window.Add_ContentRendered({ Set-Theme; Load-Upgrades })

# ------------------------------------------------------------------
# Mostra la finestra
# ------------------------------------------------------------------
$window.ShowDialog() | Out-Null
