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

# Testo sorgente di una funzione, per i controlli che devono guardare COME e' scritta
# (es. che una conferma preceda un'operazione distruttiva).
function Get-FunctionSource([string]$name) {
    $a = [System.Management.Automation.Language.Parser]::ParseInput($injected, [ref]$null, [ref]$null)
    $fn = $a.Find({
        param($n)
        $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name
    }.GetNewClosure(), $true)
    if (-not $fn) { throw "funzione non trovata nel codice: $name" }
    return $fn.Extent.Text
}

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

# 10b) Intestazioni di colonna: nessuna vuota (le colonne strette erano nate con
# Header="" e non si capiva a cosa servissero) e tutte in MAIUSCOLO.
$colHeaders = @([regex]::Matches($uiText, '<DataGrid\w*Column[^>]*?Header="([^"]*)"') |
                ForEach-Object { $_.Groups[1].Value })
if ($colHeaders.Count -eq 0) { throw "nessuna colonna trovata in UI.xaml: regex da rivedere" }
$blank = @($colHeaders | Where-Object { -not $_.Trim() })
if ($blank.Count -gt 0) { throw "$($blank.Count) colonne senza intestazione in UI.xaml" }
$notUpper = @($colHeaders | Where-Object { $_ -cne $_.ToUpperInvariant() })
if ($notUpper.Count -gt 0) { throw "intestazioni di colonna non in maiuscolo: $($notUpper -join ', ')" }
# Il centraggio funziona solo se il template lega HorizontalAlignment a
# HorizontalContentAlignment: senza, lo stile non ha alcun effetto.
if ($uiText -notmatch 'HorizontalAlignment="\{TemplateBinding HorizontalContentAlignment\}"') {
    throw "il template dell'header ignora HorizontalContentAlignment: le intestazioni resterebbero a sinistra"
}
if ($uiText -notmatch '(?s)GridHeader.*?HorizontalContentAlignment"\s+Value="Center"') {
    throw "lo stile dell'header non centra piu' le intestazioni"
}
"OK header  $($colHeaders.Count) intestazioni, tutte non vuote, maiuscole e centrate"

# 10c) Ogni glifo usato in UI.xaml esiste nei font di sistema? Un codice sbagliato non
# da' errore: finisce a video come rettangolo vuoto (tofu) e si nota solo guardando.
# Si controllano entrambi i font perche' UI.xaml li elenca in cascata: Segoe Fluent Icons
# (Win11) con fallback Segoe MDL2 Assets (Win10).
$glyphCodes = @([regex]::Matches($uiText, '&#x([0-9A-Fa-f]{4});') |
                ForEach-Object { [Convert]::ToInt32($_.Groups[1].Value, 16) } | Sort-Object -Unique)
$iconFonts = @('C:\Windows\Fonts\SegoeIcons.ttf', 'C:\Windows\Fonts\segmdl2.ttf') | Where-Object { Test-Path $_ }
if ($glyphCodes.Count -eq 0) { throw "nessun glifo trovato in UI.xaml: regex da rivedere" }
if ($iconFonts.Count -eq 0) {
    "SKIP glyph   nessun font di icone di sistema trovato"
}
else {
    foreach ($f in $iconFonts) {
        $gt = New-Object System.Windows.Media.GlyphTypeface([Uri]$f)
        $missing = @($glyphCodes | Where-Object { -not $gt.CharacterToGlyphMap.ContainsKey($_) })
        if ($missing) { throw "$(Split-Path $f -Leaf) non ha i glifi: $(($missing | ForEach-Object { 'U+{0:X4}' -f $_ }) -join ', ')" }
    }
    "OK glyph   $($glyphCodes.Count) glifi presenti in $($iconFonts.Count) font di icone"
}

# 11) La versione e' una sola e arriva sia al titolo sia all'exe? build.ps1 la pesca
# dalla costante con una regex: se qualcuno la rinomina o la sposta, la build morirebbe
# (o l'exe uscirebbe senza versione) e il titolo mostrerebbe "[]" in silenzio.
$mv = [regex]::Match($mainText, "(?m)^\s*\`$AppVersion\s*=\s*'([\d.]+)'")
if (-not $mv.Success) { throw "costante `$AppVersion non trovata in src\main.ps1" }
if ($mv.Groups[1].Value -notmatch '^\d+\.\d+\.\d+$') { throw "versione non x.y.z: '$($mv.Groups[1].Value)'" }
# La versione non sta piu' nel titolo della finestra: e' una riga della scheda Settings.
if ($code -notmatch 'TxtVersion\.Text\s*=.*\$AppVersion') { throw "la versione non finisce nella scheda Settings" }
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
# Percorso di winget: quello REALE se c'e', altrimenti un finto che serve solo a non far
# aprire a Start-App la MessageBox "winget not found".
# Deve essere il vero percorso, perche' le code (update/install/uninstall/pin) lanciano
# $wingetPath tramite cmd: con un percorso finto cmd esce 1 con "Impossibile trovare il
# percorso specificato" e sembrerebbe un errore di winget.
$realWinget = (Get-Command winget -ErrorAction SilentlyContinue).Source
function Get-WinGetPath { if ($realWinget) { $realWinget } else { 'C:\winget-stub\winget.exe' } }
$AppVersion = $mv.Groups[1].Value
Start-App -NoShow

if (-not $script:window) { throw "Start-App non ha costruito la finestra" }
if ($TxtVersion.Text -notmatch [regex]::Escape($AppVersion)) { throw "la scheda Settings non mostra la versione: '$($TxtVersion.Text)'" }
# I moduli leggono i controlli senza prefisso: se lo scope e' sbagliato, $Grid e' $null
# e ItemsSource resta tale.
# NB: confronto con $null e non "-not", perche' una collezione VUOTA e' falsy in
# PowerShell — con -not il controllo fallirebbe anche ad aggancio riuscito.
if ($null -eq $Grid) { throw "i moduli non vedono `$Grid: controllo assegnato senza `$script:?" }
if ($null -eq $Grid.ItemsSource) { throw "Initialize-UpdatesTab non ha agganciato la collezione al DataGrid" }
if ($CmbTheme.Items.Count -ne 3) { throw "Initialize-Theme non ha riempito la tendina del tema: $($CmbTheme.Items.Count) voci" }
if ($CmbTheme.SelectedItem -notin @('Light', 'Dark', 'Auto')) { throw "tema selezionato inatteso: '$($CmbTheme.SelectedItem)'" }

# La schermata delle impostazioni: chiusa all'avvio, si apre e si richiude.
if ($SettingsPanel.Visibility -ne [System.Windows.Visibility]::Collapsed) { throw "le impostazioni sono aperte all'avvio" }
Show-Settings
if ($SettingsPanel.Visibility -ne [System.Windows.Visibility]::Visible) { throw "Show-Settings non apre il pannello" }
Hide-Settings
if ($SettingsPanel.Visibility -ne [System.Windows.Visibility]::Collapsed) { throw "Hide-Settings non chiude il pannello" }
# Esc non si puo' premere in un test headless: si verifica che l'aggancio ci sia.
$setSrc = Get-FunctionSource 'Initialize-Settings'
if ($setSrc -notmatch 'PreviewKeyDown') { throw "Esc non e' agganciato in tunneling sulla finestra" }
if ($setSrc -notmatch 'Key\]::Escape') { throw "Esc non chiude le impostazioni" }
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
# "DoEvents" WPF: i tick dei DispatcherTimer restano in coda finche' il dispatcher non
# la processa, e qui non c'e' nessuna finestra a farlo per noi. Torna $false su timeout.
function Wait-For([scriptblock]$Condition, [int]$Seconds = 30) {
    $deadline = (Get-Date).AddSeconds($Seconds)
    while (-not (& $Condition)) {
        if ((Get-Date) -gt $deadline) { return $false }
        # $script: e non una locale: il delegate non cattura le variabili locali (lo
        # stesso motivo per cui App.Jobs evita GetNewClosure sul suo Tick).
        $script:frame = New-Object System.Windows.Threading.DispatcherFrame
        [void][System.Windows.Threading.Dispatcher]::CurrentDispatcher.BeginInvoke(
            [System.Windows.Threading.DispatcherPriority]::Background, [action]{ $script:frame.Continue = $false })
        [System.Windows.Threading.Dispatcher]::PushFrame($script:frame)
        Start-Sleep -Milliseconds 50
    }
    return $true
}

$script:jobOut = $null
[void](Start-BackgroundJob -Vars @{ x = 21 } -Functions 'Get-UpdateStatus' `
    -Script { "$($x * 2)|$(Get-UpdateStatus 0)" } `
    -OnDone { param($r) $script:jobOut = "$r" })

if (-not (Wait-For { $null -ne $script:jobOut })) { throw "Start-BackgroundJob: OnDone non e' mai stato richiamato (30s)" }
if ($script:jobOut -ne '42|ok') { throw "Start-BackgroundJob: risultato inatteso '$($script:jobOut)' (atteso '42|ok')" }
if ($script:jobs.Count -ne 0) { throw "job non rimosso dalla lista: $($script:jobs.Count) ancora attivi" }
Stop-AllJobs
"OK job    runspace, -Vars, -Functions, OnDone sul thread UI e cleanup"

# 14) La ricerca della scheda Install: debounce, soglia dei 3 caratteri e scarto dei
# risultati superati. E' l'unica parte della suite che chiama winget davvero, ma solo in
# lettura e sul solo indice LOCALE (--source winget), quindi non tocca la rete.
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    "SKIP search  winget non presente su questa macchina"
}
else {
    # Sotto i 3 caratteri non deve partire nulla: solo il messaggio guida.
    $TxtSearch.Text = 'vl'
    if (-not (Wait-For { $script:searchInFlight -eq 0 } 3)) { throw "una ricerca e' partita con meno di 3 caratteri" }
    if ($TxtSearchEmpty.Visibility -ne [System.Windows.Visibility]::Visible) { throw "sotto la soglia deve comparire il messaggio guida" }

    # Query buona: la ricerca parte dopo il debounce e popola la griglia.
    $TxtSearch.Text = 'vlc'
    if (-not (Wait-For { $searchItems.Count -gt 0 } 60)) { throw "la ricerca di 'vlc' non ha prodotto risultati" }
    if (-not @($searchItems | Where-Object { $_.Id -eq 'VideoLAN.VLC' })) {
        throw "'vlc' non ha trovato VideoLAN.VLC: $(@($searchItems | ForEach-Object { $_.Id }) -join ', ')"
    }
    if ($GridSearch.Visibility -ne [System.Windows.Visibility]::Visible) { throw "con risultati la griglia deve essere visibile" }
    $found = $searchItems.Count

    # RISULTATI SUPERATI: si cambia query due volte di fila, cosi' il debounce annulla la
    # prima e in griglia devono finire SOLO i risultati dell'ultima.
    # Si attende un ID che solo l'ultima query puo' produrre: aspettare "una ricerca
    # finita" non basterebbe, entro i 350ms di debounce nessuna e' ancora partita e i
    # risultati vecchi sono ancora la' (di proposito: evita di sfarfallare a ogni tasto,
    # ed e' lo spinner a dire che si sta cercando).
    $TxtSearch.Text = 'firefox'
    $TxtSearch.Text = '7zip'
    if (-not (Wait-For { @($searchItems | Where-Object { $_.Id -eq '7zip.7zip' }).Count -gt 0 } 60)) {
        throw "la ricerca finale ('7zip') non ha prodotto i suoi risultati"
    }
    if (-not (Wait-For { $script:searchInFlight -eq 0 } 60)) { throw "una ricerca e' rimasta in volo" }
    $stale = @($searchItems | Where-Object { $_.Id -eq 'VideoLAN.VLC' -or $_.Id -like 'Mozilla.Firefox*' })
    if ($stale) { throw "in griglia sono rimasti risultati di una query superata: $(@($stale | ForEach-Object { $_.Id }) -join ', ')" }
    if ($SearchSpinner.Visibility -ne [System.Windows.Visibility]::Collapsed) { throw "a ricerche finite lo spinner deve essere spento" }
    Stop-AllJobs
    "OK search  soglia 3 caratteri, $found risultati per 'vlc', nessun risultato superato in griglia"
}

# 15) Lo spinner della ricerca non deve rubare spazio al campo comparendo: sta in coda
# alla riga, dopo la spunta MS Store. Quando era agganciato a destra del DockPanel, ogni
# ricerca restringeva il campo di 20px e lo riallargava al termine.
# Il TabControl realizza solo il contenuto della scheda attiva: senza selezionare
# Install, i suoi controlli misurano 0 e il confronto non proverebbe nulla.
$tabMain.SelectedIndex = 1
$window.Content.Measure([System.Windows.Size]::new(900, 620))
$window.Content.Arrange([System.Windows.Rect]::new(0, 0, 900, 620))
$window.Content.UpdateLayout()
$wBefore = $TxtSearch.ActualWidth
$xStoreBefore = $ChkStore.TranslatePoint([System.Windows.Point]::new(0, 0), $window.Content).X
if ($wBefore -le 0) { throw "layout non calcolato: ActualWidth del campo di ricerca e' $wBefore" }
$SearchSpinner.Visibility = [System.Windows.Visibility]::Visible
$window.Content.UpdateLayout()
$wAfter = $TxtSearch.ActualWidth
$xStoreAfter = $ChkStore.TranslatePoint([System.Windows.Point]::new(0, 0), $window.Content).X
$SearchSpinner.Visibility = [System.Windows.Visibility]::Collapsed
if ($wAfter -ne $wBefore) { throw "lo spinner ha ristretto il campo di ricerca: $wBefore -> $wAfter" }
if ($xStoreAfter -ne $xStoreBefore) { throw "lo spinner ha spostato la spunta MS Store: $xStoreBefore -> $xStoreAfter" }
"OK spin   lo spinner compare senza muovere campo di ricerca ne' spunta (campo $([int]$wBefore)px)"

# 16) La disinstallazione DEVE restare dietro una conferma, e la conferma deve venire
# prima di mettere qualcosa in coda. E' l'unica operazione irreversibile del programma:
# il controllo e' statico perche' una MessageBox headless bloccherebbe la suite.
$uninstallSrc = Get-FunctionSource 'Start-UninstallSelected'
$posConfirm = $uninstallSrc.IndexOf('MessageBox')
$posQueue   = $uninstallSrc.IndexOf('Start-WinGetQueue')
if ($posConfirm -lt 0) { throw "Start-UninstallSelected non chiede conferma" }
if ($posQueue -lt 0)   { throw "Start-UninstallSelected non mette nulla in coda" }
if ($posConfirm -gt $posQueue) { throw "la conferma arriva DOPO l'avvio della coda di disinstallazione" }
if ($uninstallSrc -notmatch 'MessageBoxResult\]::No') { throw "la conferma non ha No come pulsante predefinito" }
if ($uninstallSrc -notmatch 'MessageBoxButton\]::YesNo') { throw "la conferma non e' una scelta Yes/No" }
"OK confirm disinstallazione dietro conferma Yes/No con default No, prima della coda"

# 17) Elenco installati e filtro locale. Tocca winget in lettura (winget list).
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    "SKIP list    winget non presente su questa macchina"
}
else {
    # Il caricamento parte da solo al PRIMO ingresso nella scheda: non si chiama la
    # funzione a mano, si cambia scheda come farebbe l'utente.
    if ($script:installedLoaded) { throw "l'elenco risulta gia' caricato prima di aprire la scheda" }
    $tabMain.SelectedIndex = 2
    if (-not (Wait-For { $installedItems.Count -gt 0 -and -not $script:isBusy } 120)) {
        throw "aprendo la scheda Installed l'elenco non si e' caricato"
    }
    $total = $installedItems.Count

    # ...e non deve ripartire ogni volta che si tocca la griglia: l'evento del DataGrid
    # bubbla fino al TabControl, e senza il controllo sull'originatore rilancerebbe una
    # scansione a ogni clic su una riga.
    $GridInstalled.SelectedIndex = 0
    Start-Sleep -Milliseconds 300
    if ($script:isBusy) { throw "selezionare una riga ha riavviato il caricamento dell'elenco" }

    # Il filtro nasconde righe senza toglierle dalla collezione.
    $TxtFilter.Text = '7zip'
    $shown = @($script:installedView).Count
    if ($installedItems.Count -ne $total) { throw "il filtro ha rimosso righe dalla collezione invece di nasconderle" }
    if ($shown -ge $total -or $shown -eq 0) { throw "il filtro '7zip' mostra $shown righe su $total" }
    foreach ($r in @($script:installedView)) {
        if ($r.Name -notlike '*7zip*' -and $r.Id -notlike '*7zip*') { throw "il filtro ha lasciato passare '$($r.Name)'" }
    }

    # PUNTO CRITICO: una riga selezionata e poi nascosta dal filtro resta in coda per la
    # disinstallazione. Deve essere dichiarato a schermo, non solo nella conferma.
    $victim = @($installedItems | Where-Object { $_.Name -notlike '*7zip*' -and $_.Id -notlike '*7zip*' })[0]
    $victim.Selected = $true
    Refresh-InstalledState
    if ($TxtInstalledInfo.Text -notmatch 'hidden by the filter') {
        throw "un pacchetto selezionato ma nascosto dal filtro non viene segnalato: '$($TxtInstalledInfo.Text)'"
    }
    $victim.Selected = $false
    $TxtFilter.Text = ''
    Refresh-InstalledState
    Stop-AllJobs
    "OK list    $total pacchetti installati, filtro locale e avviso sui selezionati nascosti"
}

# 18) Ciclo completo del pin su un pacchetto reale: pin add -> winget lo elenca -> il
# flag sulla riga si accende -> pin remove -> si spegne. E' l'unico test che MODIFICA lo
# stato della macchina, quindi il pin viene rimosso in ogni caso dal finally, anche se
# un'asserzione fallisce a meta'.
$pinTarget = @($installedItems | Where-Object { $_.Id -eq '7zip.7zip' })[0]
if (-not $pinTarget) {
    "SKIP pin     7zip.7zip non installato: nessun bersaglio sicuro per il test"
}
else {
    try {
        Set-PackagePin @($pinTarget) $true
        if (-not (Wait-For { -not $script:isBusy -and $pinTarget.Pinned } 90)) {
            # Le ultime righe del log riportano l'output di winget: senza, un errore qui
            # direbbe solo "exit 1" e non perche'.
            $tail = @($TxtLog.Text -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -Last 8)
            throw "dopo il pin la riga non risulta pinnata (Status: $($pinTarget.Status) $($pinTarget.StatusDetail))`nLog:`n$($tail -join "`n")"
        }
        if (((winget pin list 2>&1 | Out-String) -notmatch '7zip\.7zip')) {
            throw "winget non elenca il pin che abbiamo appena aggiunto"
        }

        Set-PackagePin @($pinTarget) $false
        if (-not (Wait-For { -not $script:isBusy -and -not $pinTarget.Pinned } 90)) {
            throw "dopo la rimozione la riga risulta ancora pinnata"
        }
        if (((winget pin list 2>&1 | Out-String) -match '7zip\.7zip')) {
            throw "il pin e' ancora presente in winget dopo la rimozione"
        }
        "OK pin     pin add/list/remove su 7zip.7zip, flag della riga allineato a winget"
    }
    finally {
        # Rete di sicurezza: un pin dimenticato bloccherebbe in silenzio gli
        # aggiornamenti di quel pacchetto.
        [void](winget pin remove --id 7zip.7zip -e 2>&1)
        Stop-AllJobs
    }
}

# 19) Export reale su file temporaneo, e conteggio del file di import.
# L'import NON si esegue: installerebbe software. Di quello si verifica solo che resti
# dietro una conferma, come per la disinstallazione.
$importSrc = Get-FunctionSource 'Start-Import'
$posConfirm = $importSrc.IndexOf('MessageBox')
$posRun     = $importSrc.IndexOf('Invoke-PackageImport')
if ($posConfirm -lt 0 -or $posRun -lt 0) { throw "Start-Import non chiede conferma o non avvia nulla" }
if ($posConfirm -gt $posRun) { throw "la conferma di import arriva DOPO l'avvio" }
if ($importSrc -notmatch 'MessageBoxResult\]::No') { throw "la conferma di import non ha No come default" }
if ((Get-FunctionSource 'Invoke-PackageImport') -notmatch '--ignore-unavailable') {
    throw "manca --ignore-unavailable: un solo pacchetto non piu' pubblicato farebbe fallire tutto l'import"
}

if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    "SKIP export  winget non presente su questa macchina"
}
else {
    $expFile = Join-Path ([IO.Path]::GetTempPath()) "wgt-test-export-$PID.json"
    try {
        Invoke-PackageExport $expFile
        if (-not (Wait-For { -not $script:isBusy } 180)) { throw "l'export non e' terminato" }
        if (-not (Test-Path $expFile)) { throw "l'export non ha scritto il file" }
        $n = Get-ImportPackageCount $expFile
        if ($null -eq $n -or $n -le 0) { throw "il file esportato non contiene pacchetti leggibili (conteggio: $n)" }

        # Un file che non e' un export winget deve essere riconosciuto PRIMA di lanciare
        # winget, altrimenti l'utente vedrebbe un errore incomprensibile.
        $bad = Join-Path ([IO.Path]::GetTempPath()) "wgt-test-bad-$PID.json"
        '{ "hello": "world" }' | Set-Content $bad -Encoding UTF8
        if ($null -ne (Get-ImportPackageCount $bad)) { throw "un JSON senza Sources viene accettato come lista pacchetti" }
        if ($null -ne (Get-ImportPackageCount (Join-Path ([IO.Path]::GetTempPath()) "manca-$PID.json"))) { throw "un file inesistente viene accettato" }
        Remove-Item $bad -Force -ErrorAction SilentlyContinue
        "OK export  export reale di $n pacchetti, file non validi riconosciuti"
    }
    finally {
        Remove-Item $expFile -Force -ErrorAction SilentlyContinue
        Stop-AllJobs
    }
}

# 20) Auto-update. Il download e la sostituzione NON si eseguono: rimpiazzerebbero
# l'eseguibile in uso. Si verificano il confronto fra versioni, la lettura della release
# da GitHub e i presidi di sicurezza attorno al download.
# L'app deve tenersi FUORI dalla propria lista di aggiornamenti: winget non puo'
# sovrascrivere un eseguibile in esecuzione, quindi da quella lista fallirebbe sempre.
if (-not (Test-IsSelfPackage ([WgtRow]@{ Id = 'FedeB2160.WinGetStudio' }))) { throw "il pacchetto proprio non viene riconosciuto" }
# Forma con cui winget lo registra quando e' installato da un manifest locale, osservata
# installandolo davvero: l'uguaglianza secca non la prendeva.
if (-not (Test-IsSelfPackage ([WgtRow]@{ Id = 'ARP\User\X64\FedeB2160.WinGetStudio__DefaultSource' }))) { throw "la forma ARP del pacchetto proprio non viene riconosciuta" }
if (Test-IsSelfPackage ([WgtRow]@{ Id = 'VideoLAN.VLC' }))                  { throw "un altro pacchetto viene scambiato per il proprio" }
if (Test-IsSelfPackage ([WgtRow]@{ Id = '' }))                              { throw "un ID vuoto viene scambiato per il proprio pacchetto" }
if (Test-IsSelfPackage $null)                                              { throw "una riga nulla viene scambiata per il proprio pacchetto" }
if ((Get-FunctionSource 'Load-Upgrades') -notmatch 'Test-IsSelfPackage') { throw "Load-Upgrades non filtra il pacchetto proprio" }

if (-not (Test-NewerVersion '1.7.0' '1.6.0'))   { throw "1.7.0 dovrebbe essere piu' recente di 1.6.0" }
if (-not (Test-NewerVersion 'v1.10.0' '1.9.0')) { throw "1.10.0 e' piu' recente di 1.9.0: confronto fatto da stringa invece che da versione" }
if (Test-NewerVersion '1.6.0' '1.6.0')          { throw "la stessa versione non e' un aggiornamento" }
if (Test-NewerVersion '1.5.0' '1.6.0')          { throw "una versione precedente non e' un aggiornamento" }
if (Test-NewerVersion 'nightly' '1.6.0')        { throw "un tag non numerico non deve proporre nulla" }

# Il download e' l'unico punto in cui il programma ESEGUE codice preso da internet:
# la conferma deve precederlo e il checksum deve essere confrontato.
$updSrc = Get-FunctionSource 'Start-SelfUpdate'
if ($updSrc.IndexOf('MessageBox') -lt 0) { throw "Start-SelfUpdate non chiede conferma" }
if ($updSrc.IndexOf('MessageBox') -gt $updSrc.IndexOf('Invoke-WebRequest')) { throw "la conferma arriva DOPO il download" }
if ($updSrc -notmatch 'MessageBoxResult\]::No') { throw "la conferma di aggiornamento non ha No come default" }
if ($updSrc -notmatch 'Get-FileHash.*SHA256|SHA256') { throw "il file scaricato non viene verificato con SHA-256" }
if ($updSrc -notmatch 'Tls12') { throw "manca TLS 1.2: PowerShell 5.1 negozia TLS 1.0 e GitHub rifiuta" }
$getRelSrc = Get-FunctionSource 'Get-LatestRelease'
if ($getRelSrc -notmatch "User-Agent") { throw "manca lo User-Agent: l'API di GitHub risponde 403 senza" }

# Chiamata reale all'API pubblica (una richiesta, limite anonimo 60/ora).
$rel = Get-LatestRelease 'FedeB2160/WinGetStudio'
if (-not $rel) {
    "SKIP rel     nessuna release con asset .exe pubblicata (o rete assente)"
}
else {
    if ($rel.Version -notmatch '^\d+\.\d+') { throw "versione della release non numerica: '$($rel.Version)'" }
    if ($rel.Url -notmatch '^https://github\.com/') { throw "URL di download non su github.com: $($rel.Url)" }
    if ($rel.Name -notlike '*.exe') { throw "l'asset scelto non e' un .exe: $($rel.Name)" }
    "OK rel     release $($rel.Tag) letta da GitHub: $($rel.Name), $([int]($rel.Size/1024)) KB, checksum $(if ($rel.Sha256) { 'presente' } else { 'ASSENTE' })"

    # Il controllo manuale deve SEMPRE riferire un esito. Serve eseguirlo davvero: il
    # flag che lo distingue da quello automatico passava per una variabile locale, che
    # dentro OnDone e' vuota, quindi non riportava nulla e nessun controllo statico lo
    # vedeva. Lo stesso scope sbagliato rendeva impossibile l'aggiornamento vero e
    # proprio ($exe e $tmp nulli).
    # Girando da sorgente il controllo si fermerebbe subito ("da sorgente usa git") e non
    # attraverserebbe il job: si finge di essere l'exe compilato, cosi' il percorso vero
    # viene esercitato. Nessun rischio: Start-SelfUpdate non viene mai chiamata.
    function Get-RunningExePath { Join-Path $root 'dist\WinGetStudio.exe' }
    $TxtUpdateStatus.Text = ''
    Start-UpdateCheck -Manual
    if (-not (Wait-For { $TxtUpdateStatus.Text -and $TxtUpdateStatus.Text -ne 'Checking...' } 60)) {
        throw "il controllo manuale non ha riportato alcun esito (TxtUpdateStatus: '$($TxtUpdateStatus.Text)')"
    }
    if ($UpdateSpinner.Visibility -ne [System.Windows.Visibility]::Collapsed) { throw "a controllo finito lo spinner resta acceso" }
    if (-not $BtnCheckUpdate.IsEnabled) { throw "a controllo finito il pulsante resta disabilitato" }
    "OK check   controllo manuale: '$($TxtUpdateStatus.Text)'"

    # Le variabili che servono a OnDone devono essere in scope $script:, non locali.
    $selfSrc = Get-FunctionSource 'Start-SelfUpdate'
    foreach ($v in 'updExe', 'updTmp', 'updRel') {
        if ($selfSrc -notmatch "script:$v") { throw "Start-SelfUpdate non passa `$$v a OnDone via `$script:" }
    }
    Stop-AllJobs
}

Write-Host "`nTUTTO OK" -ForegroundColor Green

