<#
    Test-Ui.ps1 — controllo headless di UI e temi (non apre finestre, non tocca winget).
    Uso: powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-Ui.ps1

    Serve per accorgersi subito se un ritocco a ui\*.xaml rompe qualcosa: XAML non
    valido, un x:Name rinominato, una chiave di colore presente in un tema e non
    nell'altro, un marcatore ###...### perso, un modulo che non entra nell'exe.
#>
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

$xamlFiles = 'UI.xaml', 'Theme.Light.xaml', 'Theme.Dark.xaml'

# La logica sta nei moduli, non nell'entry point: la lista si legge da $moduleNames con
# la STESSA regex di build.ps1, cosi' un modulo aggiunto entra automaticamente nei
# controlli e un errore di regex si vede qui invece che a build fallita.
$mainPath = Join-Path $root 'src\main.ps1'
$mainText = Get-Content $mainPath -Raw -Encoding UTF8
$mm = [regex]::Match($mainText, "(?ms)^\s*\`$moduleNames\s*=\s*@\((.*?)^\)")
if (-not $mm.Success) { throw "array `$moduleNames non trovato in src\main.ps1 (build.ps1 usa la stessa regex)" }
$moduleNames = @([regex]::Matches($mm.Groups[1].Value, "'([^']+)'") | ForEach-Object { $_.Groups[1].Value })
if ($moduleNames.Count -eq 0) { throw "`$moduleNames e' vuoto" }
foreach ($m in $moduleNames) {
    if (-not (Test-Path (Join-Path $root "src\modules\$m"))) { throw "modulo elencato ma assente: $m" }
}
# Un modulo scritto ma dimenticato nella lista non finirebbe nell'exe: nessun errore,
# solo funzioni mancanti a runtime.
$onDisk = @(Get-ChildItem (Join-Path $root 'src\modules') -Filter *.ps1 | ForEach-Object { $_.Name })
$orphan = @($onDisk | Where-Object { $moduleNames -notcontains $_ })
if ($orphan) { throw "moduli presenti in src\modules\ ma assenti da `$moduleNames: $($orphan -join ', ')" }
"OK mods   $($moduleNames.Count) moduli elencati, presenti e nessuno orfano"

# Tutti i file PowerShell del progetto: i controlli sul codice devono guardare i moduli,
# non solo l'entry point, altrimenti dopo lo split non verificano piu' nulla.
$psFiles = @('src\main.ps1') +
           @($moduleNames | ForEach-Object { "src\modules\$_" }) +
           @('src\build.ps1', 'tests\Test-InvokeWinGet.ps1')
# Solo il codice dell'app (entry point e moduli): build e test hanno regole proprie.
$appFiles = @($psFiles | Where-Object { $_ -notmatch 'build\.ps1|Test-' })

# Il codice come lo vedra' ps2exe: l'exe carica i moduli CONCATENATI, non dot-sourced,
# e i marcatori XAML vivono dentro un modulo. I controlli sul contenuto girano su
# questo testo, non sul solo main.ps1, che da solo non contiene quasi nulla.
$injected = $mainText.Replace('###MODULES###', (($moduleNames | ForEach-Object {
    (Get-Content (Join-Path $root "src\modules\$_") -Raw -Encoding UTF8).TrimEnd()
}) -join "`r`n"))

# 1) Gli script parsano?
foreach ($f in $psFiles) {
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
# La lista NON si ripete qui: si legge dal foreach di Start-App, cosi' un controllo
# aggiunto al codice viene verificato senza toccare il test (e uno rimosso dalla UI ma
# non dal codice fa fallire subito, invece che a finestra aperta).
$mn = [regex]::Match($injected, '(?ms)foreach \(\$n in @\((.*?)\)\)')
if (-not $mn.Success) { throw "lista dei controlli non trovata in App.Bootstrap.ps1 (foreach `$n in @(...))" }
$names = @([regex]::Matches($mn.Groups[1].Value, "'([^']+)'") | ForEach-Object { $_.Groups[1].Value })
if ($names.Count -eq 0) { throw "lista dei controlli vuota" }
foreach ($n in $names) { if (-not $window.FindName($n)) { throw "controllo richiesto dal codice ma assente da UI.xaml: $n" } }
"OK names  $($names.Count) controlli richiesti dal codice, tutti in UI.xaml"

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

# 6) Niente sintassi PowerShell 6+ nel codice: ps2exe compila contro 5.1, dove
# "`u{E706}" non e' un escape e finisce a video come "u{E706}" (rettangoli tofu).
# NB: i glifi del tema vivono in App.Theme.ps1, quindi il controllo deve guardare i
# moduli — sul solo entry point non proverebbe piu' nulla.
$code = $injected
foreach ($f in $appFiles) {
    # Solo codice, non commenti (il commento esplicativo cita la forma sbagliata).
    $bad = @(Get-Content (Join-Path $root $f) | Where-Object { $_ -notmatch '^\s*#' -and $_ -match '`u\{' })
    if ($bad) { throw "$f : escape ``u{...} (PowerShell 6+), usare [char]0x....:`n$($bad -join "`n")" }
}
"OK 5.1    nessun escape ``u{...} in $($appFiles.Count) file"

# 7) build.ps1 riuscira' a iniettare XAML e moduli nell'exe?
foreach ($f in $xamlFiles) {
    if ($code -notmatch [regex]::Escape("###$f###")) { throw "marcatore ###$f### assente" }
    $t = (Get-Content (Join-Path $root "ui\$f") -Raw -Encoding UTF8).TrimEnd()
    # Una riga che inizia con '@ chiuderebbe l'here-string dell'embedding.
    if ($t -match "(?m)^'@") { throw "$f contiene una riga che inizia con '@" }
}
# Senza questo marcatore l'exe uscirebbe SENZA la logica: il bootstrap da solo compila,
# e il fallimento si vedrebbe solo lanciando l'eseguibile.
if ($code -notmatch [regex]::Escape('###MODULES###')) { throw "marcatore ###MODULES### assente" }
"OK build  $($xamlFiles.Count) marcatori XAML + ###MODULES###, nessun XAML rompe l'here-string"

# 7b) Il bootstrap e i moduli combaciano? Una funzione rinominata in un modulo non da'
# errore di parsing: il bootstrap morirebbe a runtime con "termine non riconosciuto".
$defined = @(foreach ($f in $appFiles) {
    $a = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root $f), [ref]$null, [ref]$null)
    $a.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) |
        ForEach-Object { $_.Name }
})
# Start-App e le Initialize-* invocate a inizio riga, piu' la sentinella del fallback.
# La sentinella si cerca nel solo main.ps1: altrove Get-Command interroga winget, che
# e' un eseguibile e non una funzione di nessun modulo.
$needed = @([regex]::Matches($code, '(?m)^\s*(Start-App|Initialize-\w+)') | ForEach-Object { $_.Groups[1].Value }) +
          @([regex]::Matches($mainText, 'Get-Command\s+([\w-]+)') | ForEach-Object { $_.Groups[1].Value })
$undef = @($needed | Sort-Object -Unique | Where-Object { $defined -notcontains $_ })
if ($undef) { throw "l'app chiama funzioni che nessun modulo definisce: $($undef -join ', ')" }
"OK link   $(@($needed | Sort-Object -Unique).Count) funzioni richieste dall'avvio, tutte definite"

# 7c) Il file che ps2exe ricevera' e' valido? L'exe segue un percorso di caricamento
# DIVERSO dal .ps1 (codice concatenato invece di dot-source) e un errore la' si
# vedrebbe solo al doppio clic.
$errs = $null
[void][System.Management.Automation.Language.Parser]::ParseInput($injected, [ref]$null, [ref]$errs)
if ($errs) { throw "il codice concatenato per l'exe non parsa:`n$($errs -join '; ')" }
foreach ($fn in $defined | Sort-Object -Unique) {
    if ($injected -notmatch "(?m)^\s*function\s+$([regex]::Escape($fn))\b") {
        throw "funzione persa nella concatenazione per l'exe: $fn"
    }
}
# La sentinella del fallback dot-source deve essere definita PRIMA del suo controllo,
# altrimenti nell'exe il ramo scatta e cerca su disco moduli che non ci sono.
$posDef   = $injected.IndexOf("function Get-WinGetPath")
$posCheck = $injected.IndexOf("Get-Command Get-WinGetPath")
if ($posDef -lt 0 -or $posCheck -lt 0 -or $posDef -gt $posCheck) {
    throw "nell'exe la sentinella Get-WinGetPath non precede il controllo di fallback"
}
"OK exe    codice concatenato valido, $(@($defined | Sort-Object -Unique).Count) funzioni presenti"

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
# Anche qui su tutti i file: la griglia la maneggia Tab.Updates.ps1.
$regress = @(foreach ($f in $appFiles) {
    Get-Content (Join-Path $root $f) | Where-Object {
        $_ -notmatch '^\s*#' -and ($_ -match '\$Grid\.IsEnabled\s*=' -or $_ -match 'Items\.Refresh\(\)')
    }
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
$mv = [regex]::Match($mainText, "(?m)^\s*\`$AppVersion\s*=\s*'([\d.]+)'")
if (-not $mv.Success) { throw "costante `$AppVersion non trovata in src\main.ps1" }
if ($mv.Groups[1].Value -notmatch '^\d+\.\d+\.\d+$') { throw "versione non x.y.z: '$($mv.Groups[1].Value)'" }
if ($code -notmatch '(?m)window\.Title\s*=.*\$AppVersion') { throw "la versione non finisce nel titolo della finestra" }
$buildText = Get-Content (Join-Path $root 'src\build.ps1') -Raw -Encoding UTF8
if ($buildText -notmatch '(?m)^\s*version\s*=\s*\$version') { throw "build.ps1 non passa la versione a ps2exe" }
"OK ver    versione $($mv.Groups[1].Value) nel titolo e nelle proprieta' dell'exe"

# 12) L'app si monta davvero? Carica i moduli come fa main.ps1 e chiama Start-App
# -NoShow: nessuna finestra a schermo, ma finestra costruita, controlli risolti e
# schede agganciate. E' l'unico controllo che vede gli errori di SCOPE: se un controllo
# venisse assegnato senza $script:, i moduli non lo vedrebbero e il resto della suite
# passerebbe comunque.
# main.ps1 non si puo' dot-sourciare: la sua self-elevation rilancerebbe il processo.
# Si replicano solo le due righe innocue che servono ai moduli.
$baseDir = Join-Path $root 'src'
function Resolve-Asset([string]$rel) {
    @((Join-Path $root $rel), (Join-Path $baseDir $rel)) | Where-Object { Test-Path $_ } | Select-Object -First 1
}
foreach ($m in $moduleNames) { . (Join-Path $root "src\modules\$m") }
# Stub: il test non deve dipendere da winget installato ne' aprire la MessageBox
# d'errore se manca.
function Get-WinGetPath { 'C:\winget-stub\winget.exe' }
$AppVersion = $mv.Groups[1].Value
Start-App -NoShow

if (-not $script:window) { throw "Start-App non ha costruito la finestra" }
if ($script:window.Title -notmatch [regex]::Escape("[$AppVersion]")) { throw "titolo senza versione: $($script:window.Title)" }
# I moduli leggono i controlli senza prefisso: se lo scope e' sbagliato, $Grid e' $null
# e ItemsSource resta tale.
# NB: confronto con $null e non "-not", perche' una collezione VUOTA e' falsy in
# PowerShell — con -not il controllo fallirebbe anche ad aggancio riuscito.
if ($null -eq $Grid) { throw "i moduli non vedono `$Grid: controllo assegnato senza `$script:?" }
if ($null -eq $Grid.ItemsSource) { throw "Initialize-UpdatesTab non ha agganciato la collezione al DataGrid" }
if ($null -eq $BtnTheme.Content) { throw "Initialize-Theme non ha scritto il glifo: i moduli non vedono `$BtnTheme" }
# Le funzioni delle schede girano senza esplodere sui controlli?
Write-Log 'test'
if ($TxtLog.Text -notmatch 'test') { throw "Write-Log non scrive nel TextBox del log" }
# Log e barra di avanzamento sono condivisi da tutte le schede: devono stare FUORI dal
# TabControl. Se finissero dentro una scheda, cambiando scheda sparirebbero.
# LogicalTreeHelper e non VisualTreeHelper: il visual tree non esiste senza rendering.
$tabMain = $window.FindName('TabMain')
if (-not $tabMain) { throw "TabControl 'TabMain' assente da UI.xaml" }
foreach ($shared in @{ TxtLog = $TxtLog; Progress = $Progress }.GetEnumerator()) {
    $p = $shared.Value
    while ($p) {
        if ($p -eq $tabMain) { throw "$($shared.Key) e' dentro il TabControl: non sarebbe piu' condiviso fra le schede" }
        $p = [System.Windows.LogicalTreeHelper]::GetParent($p)
    }
}
Refresh-SelectionState
if ($BtnUpdate.IsEnabled) { throw "con la lista vuota il pulsante Update deve restare spento" }
foreach ($t in @($script:themeTimer)) { if ($t) { $t.Stop() } }
"OK start  finestra montata, controlli visibili ai moduli, log e selezione funzionanti"

# 13) Start-BackgroundJob regge? Ci passeranno tutte le operazioni winget. Si verifica
# in un colpo: le -Vars arrivano nel runspace, le -Functions vengono ricreate la'
# dentro (senza, muoiono con "termine non riconosciuto"), OnDone gira sul thread UI col
# risultato, e il job si sgancia dalla lista invece di restare a tenere vivo il processo.
$script:jobOut = $null
[void](Start-BackgroundJob -Vars @{ x = 21 } -Functions 'Get-UpdateStatus' `
    -Script { "$($x * 2)|$(Get-UpdateStatus 0)" } `
    -OnDone { param($r) $script:jobOut = "$r" })

# "DoEvents" WPF: il tick di un DispatcherTimer resta in coda finche' il dispatcher non
# la processa, e qui non c'e' nessuna finestra a farlo gestire.
$deadline = (Get-Date).AddSeconds(30)
while ($null -eq $script:jobOut -and (Get-Date) -lt $deadline) {
    # $script: e non una locale: il delegate non cattura le variabili locali (lo stesso
    # motivo per cui Start-BackgroundJob usa GetNewClosure sul suo Tick).
    $script:frame = New-Object System.Windows.Threading.DispatcherFrame
    [void][System.Windows.Threading.Dispatcher]::CurrentDispatcher.BeginInvoke(
        [System.Windows.Threading.DispatcherPriority]::Background, [action]{ $script:frame.Continue = $false })
    [System.Windows.Threading.Dispatcher]::PushFrame($script:frame)
    Start-Sleep -Milliseconds 50
}
if ($null -eq $script:jobOut) { throw "Start-BackgroundJob: OnDone non e' mai stato richiamato (30s)" }
if ($script:jobOut -ne '42|ok') { throw "Start-BackgroundJob: risultato inatteso '$($script:jobOut)' (atteso '42|ok')" }
if ($script:jobs.Count -ne 0) { throw "job non rimosso dalla lista: $($script:jobs.Count) ancora attivi" }
Stop-AllJobs
"OK job    runspace, -Vars, -Functions, OnDone sul thread UI e cleanup"

Write-Host "`nTUTTO OK" -ForegroundColor Green
