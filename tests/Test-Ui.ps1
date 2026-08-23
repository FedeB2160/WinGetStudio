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
# Solo le chiavi di COLORE: i temi definiscono pennelli, non tutto cio' che UI.xaml risolve
# dinamicamente. La visibilita' delle due parti dell'header dei tab, per esempio, vive nelle
# Resources della finestra e la scrive il codice.
# NB: si cattura la chiave INTERA e si filtra dopo. Con 'DynamicResource\s+(\w+Brush)' la
# chiave BorderBrush2 veniva troncata in "BorderBrush" — \w+ fa backtracking sulla cifra
# finale per far combaciare "Brush" — e il controllo denunciava una chiave inesistente.
$used = [regex]::Matches((Get-Content (Join-Path $root 'ui\UI.xaml') -Raw),
                         'DynamicResource\s+(\w+)') |
        ForEach-Object { $_.Groups[1].Value } |
        Where-Object { $_ -like '*Brush*' } | Sort-Object -Unique
$missing = @($used | Where-Object { $kl -notcontains $_ })
if ($missing) { throw "chiavi referenziate ma assenti dai temi: $($missing -join ', ')" }
"OK ref    $($used.Count) chiavi referenziate, tutte definite"

# 4b) Contrasto: le coppie che il tema promette leggibili lo sono davvero, in ENTRAMBI i
# temi. Il pulsante di aggiornamento aveva Foreground="White" cablato: bianco su
# AccentBrush fa 4.53:1 in Light ma 2.01:1 in Dark, cioe' illeggibile proprio sul pulsante
# piu' importante della schermata. Soglie WCAG: 4.5:1 per il testo, 3:1 per gli elementi
# grafici (i glifi di esito, il riempimento della barra).
$uiTextEarly = Get-Content (Join-Path $root 'ui\UI.xaml') -Raw
function Get-Luminance([System.Windows.Media.Color]$c) {
    $ch = @($c.R, $c.G, $c.B) | ForEach-Object {
        $s = $_ / 255
        if ($s -le 0.03928) { $s / 12.92 } else { [Math]::Pow(($s + 0.055) / 1.055, 2.4) }
    }
    return 0.2126 * $ch[0] + 0.7152 * $ch[1] + 0.0722 * $ch[2]
}
function Get-Contrast($dict, [string]$fg, [string]$bg) {
    $lf = Get-Luminance $dict[$fg].Color
    $lb = Get-Luminance $dict[$bg].Color
    $hi = [Math]::Max($lf, $lb); $lo = [Math]::Min($lf, $lb)
    return [Math]::Round(($hi + 0.05) / ($lo + 0.05), 2)
}
# fg, bg, soglia. I glifi di esito stanno sia sulle righe normali sia su quelle alterne.
$pairs = @(
    @('FgBrush',        'BgBrush',       4.5), @('FgBrush',       'CtrlBgBrush',   4.5),
    @('SubtleFgBrush',  'BgBrush',       4.5), @('SubtleFgBrush', 'CtrlBgBrush',   4.5),
    @('AccentFgBrush',  'AccentBrush',   4.5),
    @('OkBrush',        'BgBrush',       3.0), @('OkBrush',       'RowAltBgBrush', 3.0),
    @('WarnBrush',      'BgBrush',       3.0), @('WarnBrush',     'RowAltBgBrush', 3.0),
    @('ErrBrush',       'BgBrush',       3.0), @('ErrBrush',      'RowAltBgBrush', 3.0),
    @('AccentBrush',    'BgBrush',       3.0)
)
foreach ($t in @{ Light = $light; Dark = $dark }.GetEnumerator()) {
    foreach ($p in $pairs) {
        $r = Get-Contrast $t.Value $p[0] $p[1]
        if ($r -lt $p[2]) { throw "$($t.Key): $($p[0]) su $($p[1]) fa ${r}:1, minimo $($p[2]):1" }
    }
}
"OK contr  $($pairs.Count) coppie sopra soglia nei due temi"

# 4c) Separazione delle SUPERFICI e confine dei componenti. Il tema chiaro aveva
# CtrlBgBrush #FDFDFD su BgBrush #FFFFFF: uno scarto di luminanza dello 0,6%, cioe' nessuno,
# e l'unica cosa che definiva un pulsante era un filo #CCCCCC a 1.61:1 — che a controllo
# disabilitato, con Opacity 0.5, scendeva a ~1.31 e spariva del tutto.
# Le due soglie: il passo di superficie dice che un controllo si stacca dalla pagina, il
# bordo che il suo confine si vede. Sono le due strade per identificare un componente, e
# servono entrambe perche' nessuna delle due da sola regge in tutti i temi.
foreach ($t in @{ Light = $light; Dark = $dark }.GetEnumerator()) {
    $step = Get-Contrast $t.Value 'CtrlBgBrush' 'BgBrush'
    if ($step -lt 1.08) {
        throw "$($t.Key): la superficie dei controlli non si stacca dalla pagina ($step, minimo 1.08)"
    }
    foreach ($bg in 'BgBrush', 'CtrlBgBrush') {
        $b = Get-Contrast $t.Value 'CtrlBorderBrush' $bg
        if ($b -lt 2.3) { throw "$($t.Key): il bordo dei componenti su $bg fa ${b}:1, minimo 2.3" }
    }
}
# Il pulsante disabilitato non torni a sparire: niente Opacity nel suo trigger.
$btnStyle = [regex]::Match($uiTextEarly, '(?s)<Style TargetType="Button">.*?\r?\n        </Style>').Value
if (-not $btnStyle) { throw "stile del pulsante non trovato: regex da rivedere" }
if ($btnStyle -match '(?s)IsEnabled" Value="False">.*?Opacity') {
    throw "il pulsante disabilitato torna a essere sbiadito con Opacity: il bordo spariva"
}
"OK surf   superfici e confini distinguibili nei due temi, disabilitato ancora visibile"

# Il pulsante di aggiornamento non deve tornare a un colore cablato: su AccentBrush ci va
# AccentFgBrush, che i due temi definiscono in modo diverso.
if ($uiTextEarly -match '(?s)x:Name="BtnUpdateApp".*?Foreground="White"') {
    throw "BtnUpdateApp ha ancora Foreground=White: 2.01:1 in Dark"
}

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

# 10b-bis) Le voci del menu contestuale agiscono sulle righe EVIDENZIATE, non su quelle
# spuntate: se non lo dicono, si spunta una riga e poi non si capisce perche' il pin sia
# finito altrove. E' documentato nei commenti da sempre, ma il commento non lo legge nessuno
# col tasto destro premuto.
$menuHeaders = @([regex]::Matches($uiText, '<MenuItem[^>]*Header="([^"]*)"') | ForEach-Object { $_.Groups[1].Value })
if ($menuHeaders.Count -eq 0) { throw "nessuna voce di menu trovata: regex da rivedere" }
$vague = @($menuHeaders | Where-Object { $_ -notmatch 'highlighted' })
if ($vague.Count -gt 0) { throw "voci di menu che non dicono su cosa agiscono: $($vague -join ', ')" }
"OK menu   $($menuHeaders.Count) voci di menu dichiarano di agire sulle righe evidenziate"

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

# 10d) Barre di scorrimento: il template di sistema (Aero2) cabla colori chiari e ignora
# Background, quindi in Dark restavano BIANCHE — l'ultimo pezzo di finestra dipinto da
# Windows invece che dal tema. Si controlla che lo stile esista, che sostituisca il template
# (senza, i Setter di colore non arrivano da nessuna parte) e che non contenga colori
# cablati, che e' esattamente il difetto che si sta togliendo.
$sbStyle = $window.Resources[[System.Windows.Controls.Primitives.ScrollBar]]
if (-not $sbStyle) { throw "nessuno stile per ScrollBar: in Dark le barre restano bianche" }
if (@($sbStyle.Setters | Where-Object { $_.Property.Name -eq 'Template' }).Count -eq 0) {
    throw "lo stile della ScrollBar non ne sostituisce il template"
}
$sbText = [regex]::Match($uiText, '(?s)<Style TargetType="ScrollBar">.*?\r?\n        </Style>').Value
if (-not $sbText) { throw "stile ScrollBar non trovato nel testo di UI.xaml: regex da rivedere" }
if ($sbText -match '"#[0-9A-Fa-f]{6}"') { throw "colori cablati nello stile della ScrollBar: non seguirebbero il tema" }
if ($sbText -notmatch 'PART_Track') { throw "manca PART_Track: ScrollBar non saprebbe dove mettere il cursore" }
"OK scrbar ScrollBar ri-templata, nessun colore cablato"

# 10e) Ogni elemento che usa un font di icone dichiara un AutomationProperties.Name: il
# contenuto di quei TextBlock e' un codepoint dell'area a uso privato, e senza un nome uno
# screen reader legge quello. Vuoto se il glifo e' decorativo e accanto c'e' gia' il testo
# che lo dice; il valore giusto se il glifo PORTA l'informazione, come nella colonna RESULT
# (li' lo scrivono i DataTrigger insieme al glifo).
# NB: NON esiste AutomationProperties.AccessibilityView in WPF — e' una proprieta' di UWP, e
# usarla fa morire il caricamento dello XAML con "membro sconosciuto".
$iconTags = @([regex]::Matches($uiText, '<[^>]*FontFamily="Segoe Fluent Icons[^>]*>'))
if ($iconTags.Count -eq 0) { throw "nessun elemento con font di icone trovato: regex da rivedere" }
$unnamed = @($iconTags | Where-Object { $_.Value -notmatch 'AutomationProperties\.Name=' })
if ($unnamed.Count -gt 0) {
    throw "$($unnamed.Count) glifi senza AutomationProperties.Name:`n$(($unnamed | ForEach-Object { $_.Value }) -join "`n")"
}
"OK a11y   $($iconTags.Count) elementi con font di icone, tutti con un nome accessibile"

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
# "System" e non "Auto": dice che segue il sistema invece di lasciarlo indovinare. Un vecchio
# "Auto" nel registro non e' fra i tre e ripiega sul default, che e' System — stesso
# comportamento, nessuna perdita per chi aggiorna.
if ($CmbTheme.SelectedItem -notin @('Light', 'Dark', 'System')) { throw "tema selezionato inatteso: '$($CmbTheme.SelectedItem)'" }
if ($CmbTheme.Items -contains 'Auto') { throw "la tendina del tema offre ancora 'Auto'" }

# La schermata delle impostazioni e' un TAB come gli altri, l'ultimo, fissato a destra:
# cosi' barra di avanzamento e log restano visibili anche mentre e' aperta, e non servono
# ne' un overlay con RowSpan/ZIndex, ne' un tasto per chiuderla, ne' Esc.
if ($TabMain.Items.Count -ne 5) { throw "attesi 5 tab, trovati $($TabMain.Items.Count)" }
# ORDINE DI DICHIARAZIONE E POSIZIONE NON COINCIDONO: in un DockPanel il primo figlio con
# Dock="Right" prende il bordo destro e il successivo si mette alla sua sinistra. About e'
# dichiarato prima di Settings proprio perche' e' lui a stare piu' a destra — la verifica
# della posizione vera e' nella sezione 15b, che ha il layout calcolato.
if ($TabMain.Items[3] -ne $TabAbout)    { throw "il quarto tab dichiarato non e' About" }
if ($TabMain.Items[4] -ne $TabSettings) { throw "il quinto tab dichiarato non e' Settings" }
# Ordine alfabetico dei tre tab funzionali.
foreach ($pair in @(@(0, $TabInstall, 'Install'), @(1, $TabInstalled, 'Installed'), @(2, $TabUpdates, 'Updates'))) {
    if ($TabMain.Items[$pair[0]] -ne $pair[1]) { throw "il tab in posizione $($pair[0]) non e' $($pair[2])" }
    if ($pair[1].Header -ne $pair[2]) { throw "header inatteso in posizione $($pair[0]): '$($pair[1].Header)'" }
}
# Updates resta la vista di apertura: la scansione all'avvio popola proprio quella.
if (-not $TabUpdates.IsSelected) { throw "all'avvio deve essere selezionato Updates" }
# I controlli delle impostazioni vivono DENTRO il tab: se restassero fuori, tornerebbero a
# coprire il resto della finestra.
$p = $CmbTheme
while ($p -and $p -ne $TabSettings) { $p = [System.Windows.LogicalTreeHelper]::GetParent($p) }
if ($p -ne $TabSettings) { throw "la tendina del tema non e' dentro il tab Settings" }
# E la descrizione dell'app vive nel tab About, non piu' in fondo alle impostazioni.
if ($TabAbout.Content -isnot [System.Windows.Controls.ScrollViewer]) { throw "il tab About e' vuoto" }
$aboutText = $TabAbout.Content.Content
if ($aboutText -isnot [System.Windows.Controls.TextBlock]) { throw "il tab About non contiene il testo" }
if ($aboutText.Text -notmatch 'front end for') { throw "il tab About non contiene la descrizione" }
"OK settab $($TabMain.Items.Count) tab, Settings ultimo, Updates selezionato all'avvio"

# Ogni tab ha la sua icona e un tooltip, e cosa la striscia mostra e' una scelta:
# Icon | Text | Icon + Text. Il glifo sta in Tag, la parola resta Header — cosi' Header
# continua a fare da nome accessibile e i controlli sull'ordine dei tab restano validi.
foreach ($t in $TabMain.Items) {
    if (-not $t.Tag)     { throw "il tab '$($t.Header)' non ha un glifo in Tag" }
    if (-not $t.ToolTip) { throw "il tab '$($t.Header)' non ha un tooltip" }
    $n = [System.Windows.Automation.AutomationProperties]::GetName($t)
    if (-not $n) { throw "il tab '$($t.Header)' non ha un nome accessibile: in modalita' Icon non annuncerebbe niente" }
}
# Le tre modalita' cambiano davvero cosa e' visibile.
foreach ($case in @(@('Icon', 'Visible', 'Collapsed'), @('Text', 'Collapsed', 'Visible'),
                    @('Icon + Text', 'Visible', 'Visible'))) {
    Set-TabHeaderStyle $case[0]
    if ("$($window.Resources['TabIconVis'])" -ne $case[1]) { throw "modalita' '$($case[0])': icona $($window.Resources['TabIconVis']), attesa $($case[1])" }
    if ("$($window.Resources['TabTextVis'])" -ne $case[2]) { throw "modalita' '$($case[0])': testo $($window.Resources['TabTextVis']), atteso $($case[2])" }
}
Set-TabHeaderStyle 'Icon + Text'
if ($CmbTabStyle.Items.Count -ne 3) { throw "la tendina della striscia non ha tre voci: $($CmbTabStyle.Items.Count)" }
# La modalita' ripristinata all'avvio e la striscia devono raccontare la stessa cosa: la
# tendina dice una modalita' valida e le due visibilita' sono quelle di QUELLA modalita'.
# Senza questo, una preferenza scritta di sorpresa aprirebbe l'app in una modalita' che la
# tendina non mostra, e nessuno se ne accorgerebbe.
$restored = [string]$CmbTabStyle.SelectedItem
if ($restored -notin @('Icon', 'Text', 'Icon + Text')) { throw "modalita' ripristinata inattesa: '$restored'" }
Set-TabHeaderStyle $restored
$attesaIcona = if ($restored -eq 'Text') { 'Collapsed' } else { 'Visible' }
$attesaTesto = if ($restored -eq 'Icon') { 'Collapsed' } else { 'Visible' }
if ("$($window.Resources['TabIconVis'])" -ne $attesaIcona -or "$($window.Resources['TabTextVis'])" -ne $attesaTesto) {
    throw "la striscia non corrisponde alla modalita' '$restored'"
}
$initSrc = Get-FunctionSource 'Initialize-TabHeaders'
if ($initSrc -notmatch "Get-Pref\s+'TabHeaderStyle'") { throw "la modalita' non si rilegge dalle preferenze" }
if ($initSrc -notmatch "Set-Pref\s+'TabHeaderStyle'") { throw "la modalita' non si salva" }
"OK tabicon 4 tab con icona, tooltip e nome accessibile; tre modalita' di visualizzazione"

# Mentre una coda gira, spunte e pin non devono essere DISPONIBILI, ma la UI resta viva: la
# griglia si scorre, il log si legge. Prima le spunte erano bloccate (IsReadOnly) ma
# sembravano ancora cliccabili, e le voci Pin restavano accese per poi rifiutare.
Set-AppBusy $true
foreach ($m in $MenuPinUpdates, $MenuUnpinUpdates, $MenuPinInstalled, $MenuUnpinInstalled) {
    if ($m.IsEnabled) { throw "una voce di pin resta attiva durante un'operazione" }
}
if (-not $Grid.IsReadOnly) { throw "le spunte restano modificabili durante un'operazione" }
# Le griglie NON si disabilitano: disabilitate non rispondono piu' a rotellina, scrollbar e
# tastiera, ed e' la regressione che il controllo 9 esiste per impedire.
foreach ($g in $Grid, $GridSearch, $GridInstalled) {
    if (-not $g.IsEnabled) { throw "una griglia e' stata disabilitata: non si scorrerebbe piu'" }
}
Set-AppBusy $false
foreach ($m in $MenuPinUpdates, $MenuUnpinUpdates, $MenuPinInstalled, $MenuUnpinInstalled) {
    if (-not $m.IsEnabled) { throw "a operazione finita una voce di pin resta spenta" }
}
if ($Grid.IsReadOnly) { throw "a operazione finita le spunte restano bloccate" }

# E la spunta deve anche VEDERSI spenta: il trigger sta negli stili, non nel codice, cosi'
# vale per tutte e tre le griglie senza ripeterlo scheda per scheda. Fuori da una griglia
# (Unknown, MS Store) l'antenato non esiste, il binding torna null e non succede niente.
foreach ($st in 'ThemedCheckBox', 'PinnableCheckBox') {
    $blk = [regex]::Match($uiTextEarly, "(?s)x:Key=`"$st`".*?\r?\n        </Style>").Value
    if (-not $blk) { throw "stile $st non trovato in UI.xaml" }
    if ($blk -notmatch 'IsReadOnly, RelativeSource=\{RelativeSource AncestorType=DataGrid\}') {
        throw "lo stile $st non spegne la spunta quando la griglia e' in sola lettura"
    }
}
"OK lockrow spunte e pin spenti durante la coda, griglie ancora vive"
# Le funzioni delle schede girano senza esplodere sui controlli?
Write-Log 'test'
if ($TxtLog.Text -notmatch 'test') { throw "Write-Log non scrive nel TextBox del log" }
# Log e barra di avanzamento sono condivisi da tutte le schede: devono stare FUORI dal
# TabControl. Se finissero dentro una scheda, cambiando scheda sparirebbero.
# LogicalTreeHelper e non VisualTreeHelper: il visual tree non esiste senza rendering.
$tabMain = $window.FindName('TabMain')
if (-not $tabMain) { throw "TabControl 'TabMain' assente da UI.xaml" }
# Il log era alto 140px fissi e non si poteva restringere. Ora c'e' una maniglia, e le due
# righe che tocca hanno un minimo: senza, il trascinamento le schiaccia a zero e il log (o
# l'elenco) sparisce senza che si capisca come farlo tornare.
if ($null -eq $LogSplitter) { throw "manca la maniglia di ridimensionamento del log" }
$mainRows = $window.Content.RowDefinitions
$logRow = $mainRows[[System.Windows.Controls.Grid]::GetRow($TxtLog)]
if ($logRow.MinHeight -le 0) { throw "la riga del log non ha un'altezza minima" }
if ($mainRows[0].MinHeight -le 0) { throw "la riga delle schede non ha un'altezza minima" }
if ([System.Windows.Controls.Grid]::GetRow($LogSplitter) -ge [System.Windows.Controls.Grid]::GetRow($TxtLog)) {
    throw "la maniglia non sta sopra il log"
}

foreach ($shared in @{ TxtLog = $TxtLog; Progress = $Progress }.GetEnumerator()) {
    $p = $shared.Value
    while ($p) {
        if ($p -eq $tabMain) { throw "$($shared.Key) e' dentro il TabControl: non sarebbe piu' condiviso fra le schede" }
        $p = [System.Windows.LogicalTreeHelper]::GetParent($p)
    }
}
Refresh-SelectionState
if ($BtnUpdate.IsEnabled) { throw "con la lista vuota il pulsante Update deve restare spento" }

# La barra va in indeterminato durante una SCANSIONE, che non ha un avanzamento da mostrare:
# ferma a zero sembrava un'operazione bloccata. La coda invece sa quanti pacchetti ha, quindi
# la rimette determinata — anche subito dopo una scansione.
foreach ($fn in 'Load-Upgrades', 'Load-Installed', 'Invoke-PackageExport', 'Invoke-PackageImport') {
    if ((Get-FunctionSource $fn) -notmatch 'IsIndeterminate\s*=\s*\$true') {
        throw "$fn non mette la barra in indeterminato: durante la scansione resta ferma a zero"
    }
}
if ((Get-FunctionSource 'Start-WinGetQueue') -notmatch 'IsIndeterminate\s*=\s*\$false') {
    throw "Start-WinGetQueue non riporta la barra a determinata"
}
foreach ($t in @($script:themeTimer)) { if ($t) { $t.Stop() } }
"OK start  finestra montata, controlli visibili ai moduli, log e selezione funzionanti"

# 12b) Le preferenze: scritte e rilette dal registro, e un valore assente torna il default
# invece di far esplodere l'avvio. Si scrive un nome di prova e si cancella subito: la chiave
# e' la stessa dell'app, quindi non si toccano i valori veri dell'utente.
$probe = "TestProbe$PID"
try {
    if ($null -ne (Get-Pref $probe $null)) { throw "il nome di prova esisteva gia': $probe" }
    if ((Get-Pref $probe 'fallback') -ne 'fallback') { throw "un valore assente non torna il default" }
    Set-Pref $probe 42
    if ((Get-Pref $probe 0) -ne 42) { throw "Set-Pref/Get-Pref non fanno il giro: $(Get-Pref $probe 0)" }
}
finally {
    Remove-ItemProperty -Path $PrefsKey -Name $probe -ErrorAction SilentlyContinue
}
# I tre toggle che si perdevano a ogni avvio ora si rileggono e si risalvano. Controllo
# statico: farli girare davvero vorrebbe dire sporcare le preferenze di chi esegue i test.
foreach ($pair in @(@('Initialize-UpdatesTab', 'IncludeUnknown'),
                    @('Initialize-InstallTab', 'IncludeStore'),
                    @('Initialize-InstallTab', 'InstallScope'),
                    @('Initialize-Theme',      'Theme'))) {
    $src = Get-FunctionSource $pair[0]
    if ($src -notmatch "Get-Pref\s+'$($pair[1])'") { throw "$($pair[0]) non rilegge la preferenza $($pair[1])" }
    if ($src -notmatch "Set-Pref\s+'$($pair[1])'") { throw "$($pair[0]) non salva la preferenza $($pair[1])" }
}
# La spunta Unknown cambia COSA c'e' nell'elenco: deve anche ricaricarlo, altrimenti bisogna
# premere Check per capire cosa ha fatto.
if ((Get-FunctionSource 'Initialize-UpdatesTab') -notmatch '(?s)ChkUnknown\.Add_Click[\s\S]{0,300}Load-Upgrades') {
    throw "la spunta Unknown non ricarica l'elenco"
}
"OK prefs  giro completo su registro, 4 preferenze lette e salvate, Unknown ricarica"

# 12d) Il ricalcolo differito dei contatori era copiato in tutte e tre le schede col solo
# nome della funzione diverso. Vive in un posto solo: se una scheda tornasse a scriverselo a
# mano, il prossimo inciampo sull'overload di BeginInvoke andrebbe corretto in tre punti.
foreach ($f in 'Tab.Updates.ps1', 'Tab.Install.ps1', 'Tab.Installed.ps1') {
    $t = Get-Content (Join-Path $root "src\modules\$f") -Raw
    if ($t -notmatch 'Register-GridRefresh') { throw "$f non usa Register-GridRefresh" }
    if ($t -match 'Dispatcher\.BeginInvoke') { throw "$f richiama ancora il dispatcher a mano" }
}
# Il collante non deve essere una closure: GetNewClosure crea un module scope dove $script:
# non e' piu' questo script (la trappola documentata in App.Jobs.ps1).
$regSrc = Get-FunctionSource 'Register-GridRefresh'
if ($regSrc -match 'GetNewClosure') { throw "Register-GridRefresh usa GetNewClosure: `$script: non funzionerebbe piu'" }
if ($regSrc -notmatch '\[scriptblock\]::Create') { throw "Register-GridRefresh non costruisce l'handler da testo" }
# E deve funzionare davvero: il contatore si aggiorna.
$items.Clear()
$items.Add([WgtRow]@{ Id = 'A.A'; Name = 'A'; Selected = $true })
$TxtSelected.Text = 'stantio'
Refresh-SelectionState
if ($TxtSelected.Text -ne '1 selected') { throw "il ricalcolo non aggiorna il contatore: '$($TxtSelected.Text)'" }
$items.Clear()
Refresh-SelectionState
"OK defer  ricalcolo differito condiviso dalle tre schede"

# 12c) Il corpo delle impostazioni sta su una griglia a due colonne. I 120 magici erano un
# allineamento a mano: se un'etichetta cresce, la riga sotto non la segue.
# Sul markup SENZA COMMENTI: il commento che spiega la modifica cita il margine di prima, ed
# e' giusto che lo faccia — non deve far fallire il controllo.
$uiMarkup = [regex]::Replace($uiTextEarly, '(?s)<!--.*?-->', '')
if ($uiMarkup -match 'Margin="120,') { throw "il corpo delle impostazioni usa ancora i margini magici da 120" }
# ABOUT deve dire COSA fa il programma e DOVE si segnala un problema, non una riga generica.
if ($uiTextEarly -notmatch 'NavigateUri="https://github\.com/') { throw "ABOUT non ha link a github.com" }
if ($uiTextEarly -notmatch 'WinGetStudio/issues') { throw "ABOUT non dice dove segnalare un bug" }
foreach ($w in 'Updates', 'Install', 'Installed', 'Pin', 'Export / Import') {
    if ($uiTextEarly -notmatch "<Bold>$([regex]::Escape($w))</Bold>") { throw "ABOUT non elenca la funzione $w" }
}
if ($uiTextEarly -notmatch 'Claude Code') { throw "manca la nota sullo strumento con cui e' stato scritto" }
if ($uiTextEarly -notmatch 'github\.com/FedeB2160"') { throw "ABOUT non dice chi ha fatto il progetto" }
# I link aprono il browser: WPF non lo fa da solo, serve un handler.
if ((Get-FunctionSource 'Start-App') -notmatch 'RequestNavigateEvent') {
    throw "nessun handler per i link: cliccarli non aprirebbe nulla"
}
# Il controllo all'avvio si puo' spegnere: con la spunta giu' non deve partire NESSUN job,
# cioe' nessuna chiamata a GitHub. Il pulsante Check resta sempre disponibile.
Stop-AllJobs
$ChkAutoCheck.IsChecked = $false
Start-UpdateCheck
if ($script:jobs.Count -ne 0) { throw "con la spunta giu' il controllo automatico e' partito comunque" }
$ChkAutoCheck.IsChecked = $true
"OK settgs griglia a due colonne, ABOUT completo con link, controllo all'avvio spegnibile"

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

# 13b) Una ricerca in volo E' un processo winget, anche se di proposito non alza lo stato
# occupato (la digitazione deve restare fluida). Senza questo controllo, digitare in Install
# e passare subito a Installed lanciava due winget insieme — ed e' cosi' che un comando
# esce con exit 1. Il flag si forza a mano: far partire una ricerca vera renderebbe il test
# lento e dipendente dalla rete.
$script:searchInFlight = 1
try {
    if (-not (Test-WinGetBusy)) { throw "Test-WinGetBusy ignora le ricerche in volo" }

    $script:installedLoaded = $false
    Load-Installed
    if ($script:installedLoaded) { throw "Load-Installed e' partita con una ricerca in volo" }

    # La coda e' il punto di passaggio di update, install, uninstall e pin: se non si difende
    # lei, ognuno dei quattro deve ricordarselo, e prima o poi uno se lo dimentica.
    $wasBusy = $script:isBusy
    Start-WinGetQueue -Rows @([WgtRow]@{ Id = 'Test.Id'; Name = 'Test' }) -Verb 'Test' `
        -ArgsBuilder { param($r) '--version' }
    if ($script:isBusy -ne $wasBusy) { throw "Start-WinGetQueue ha preso lo stato occupato con una ricerca in volo" }
    if ($script:jobs.Count -ne 0) { throw "Start-WinGetQueue ha avviato un job con una ricerca in volo" }
}
finally {
    $script:searchInFlight = 0
    Stop-AllJobs
}
"OK busy   ricerca in volo: scansioni e coda winget si fermano"

# 13c) Entrambi i timer si fermano alla chiusura: uno che resta vivo tiene in piedi il
# processo dopo che la finestra e' sparita, ed e' la ragione per cui il primo era stato
# fermato — quindi vale anche per il secondo.
# F5 ricarica la scheda attiva, Ctrl+F porta al campo di ricerca. Non si possono premere
# tasti in un test headless: si verifica che l'aggancio ci sia e che sia in tunneling sulla
# FINESTRA, perche' il tasto arriva prima al controllo che ha il fuoco — e un DataGrid usa F5
# e Ctrl+F per conto suo.
$startSrc = Get-FunctionSource 'Start-App'
if ($startSrc -notmatch 'Add_PreviewKeyDown') { throw "le scorciatoie non sono agganciate in tunneling sulla finestra" }
foreach ($k in 'Key\]::F5', 'Key\]::F\b', 'ModifierKeys\]::Control') {
    if ($startSrc -notmatch $k) { throw "scorciatoia mancante o agganciata diversamente: $k" }
}

foreach ($t in 'themeTimer', 'searchTimer') {
    if ($startSrc -notmatch "Add_Closed[\s\S]*$t") { throw "Add_Closed non ferma `$script:$t" }
}
"OK timers themeTimer e searchTimer fermati in Add_Closed"

# 13d) Il pulsante Update diventa Cancel mentre gira LA NOSTRA coda, e torna Update quando lo
# stato occupato si libera. Con la coda di un'altra scheda resta spento: annullare
# un'installazione dal pulsante degli aggiornamenti non vorrebbe dire niente.
$script:queueVerb = 'Update'
Set-AppBusy $true
if ($BtnUpdate.Content -ne 'Cancel') { throw "durante l'update il pulsante non diventa Cancel: '$($BtnUpdate.Content)'" }
if (-not $BtnUpdate.IsEnabled) { throw "il pulsante Cancel e' spento" }
# Set-PinFlags richiama Refresh-SelectionState mentre lo stato e' ANCORA occupato: era il
# primo modo in cui questo si rompeva, spegnendo il Cancel appena letti i pin.
Refresh-SelectionState
if (-not $BtnUpdate.IsEnabled) { throw "un ricalcolo della selezione ha spento il Cancel" }
$script:queueVerb = 'Install'
Set-AppBusy $true
if ($BtnUpdate.Content -eq 'Cancel') { throw "il pulsante mostra Cancel per una coda che non e' la sua" }
Set-AppBusy $false
if ($BtnUpdate.Content -ne 'Update') { throw "a coda finita il pulsante non torna Update: '$($BtnUpdate.Content)'" }
if ($null -ne $script:queueVerb) { throw "Set-AppBusy `$false non azzera il verbo della coda" }
"OK cancel  Update <-> Cancel legati alla coda in corso"

# 13e) CICLO COMPLETO di una coda, simulato su 5 righe finte che lanciano "winget --version":
# rapido, innocuo, e nessun pacchetto della macchina viene toccato. Prova le quattro cose che
# a mano si vedrebbero solo con aggiornamenti veri da installare:
#   1. mentre la coda gira: Update e' Cancel e premibile, le spunte sono bloccate, le voci
#      di pin spente, e le griglie ancora vive;
#   2. il pulsante premuto DAVVERO (RaiseEvent sul Click, non la funzione chiamata a mano)
#      passa a "Cancelling..." e si spegne;
#   3. il pacchetto IN VOLO arriva al suo esito e gli altri non partono — si aspetta che il
#      primo sia davvero partito prima di annullare, altrimenti la richiesta batte la coda e
#      questo pezzo non verrebbe provato;
#   4. a coda finita il pulsante torna Update ma resta bloccato, e il perche' e' a schermo.
if (-not (Get-Command winget -ErrorAction SilentlyContinue)) {
    "SKIP queue  winget non presente su questa macchina"
}
else {
    # Righe finte spuntate, e poi si chiama la funzione VERA del pulsante Update: cosi' passano
    # per il percorso reale — ArgsBuilder, OnDone, marcatura della lista — invece di una coda
    # costruita a mano dal test, che proverebbe solo il test.
    # Gli ID non esistono in nessun catalogo, quindi winget esce con "nessun pacchetto trovato"
    # senza toccare la macchina: e' l'esito che serve, il codice di uscita non conta.
    $probeRows = @(1..5 | ForEach-Object { [WgtRow]@{ Id = "WinGetStudio.Probe.$_"; Name = "Probe $_"; Selected = $true } })
    $items.Clear()
    foreach ($r in $probeRows) { $items.Add($r) }
    $script:listStale = $false
    Refresh-SelectionState
    $TxtLog.Clear()

    Start-UpdateSelected

    # 1) stato durante la coda
    if ($BtnUpdate.Content -ne 'Cancel') { throw "coda in corso: il pulsante e' '$($BtnUpdate.Content)', atteso Cancel" }
    if (-not $BtnUpdate.IsEnabled) { throw "coda in corso: il Cancel e' spento" }
    if (-not $Grid.IsReadOnly) { throw "coda in corso: le spunte sono ancora modificabili" }
    if ($MenuPinUpdates.IsEnabled) { throw "coda in corso: la voce Pin e' ancora attiva" }
    if (-not $Grid.IsEnabled) { throw "coda in corso: la griglia e' stata disabilitata" }
    if ($BtnToggleAll.IsEnabled) { throw "coda in corso: Select all e' ancora premibile" }

    # 2-3) si annulla premendo il pulsante, dopo che il primo pacchetto e' partito
    if (-not (Wait-For { $probeRows[0].Status } 60)) { throw "il primo pacchetto non e' mai partito" }
    $BtnUpdate.RaiseEvent(
        (New-Object System.Windows.RoutedEventArgs([System.Windows.Controls.Primitives.ButtonBase]::ClickEvent)))
    if ($BtnUpdate.Content -ne 'Cancelling...') { throw "premuto Cancel, il pulsante dice '$($BtnUpdate.Content)'" }
    if ($BtnUpdate.IsEnabled) { throw "premuto Cancel, il pulsante e' ancora premibile" }

    if (-not (Wait-For { -not $script:isBusy } 120)) { throw "la coda annullata non e' terminata" }
    if ($probeRows[0].Status -eq 'updating') { throw "il pacchetto in volo e' rimasto 'updating': non ha finito" }
    if (-not $probeRows[0].Status) { throw "il pacchetto in volo non e' arrivato a un esito" }
    $ran = @($probeRows | Where-Object { $_.Status }).Count
    if ($ran -ge 5) { throw "l'annullamento non ha fermato la coda: eseguiti $ran su 5" }
    if ($TxtLog.Text -notmatch 'cancelled') { throw "l'annullamento non e' finito nel log" }

    # 4) a coda finita: pulsante di nuovo Update, ma bloccato fino al Check
    if ($BtnUpdate.Content -ne 'Update') { throw "a coda finita il pulsante dice '$($BtnUpdate.Content)'" }
    if ($BtnUpdate.IsEnabled) { throw "a coda finita Update non e' bloccato: la lista e' vecchia" }
    if ($TxtSelected.Text -notmatch 'press Check') { throw "non viene detto perche' Update e' bloccato: '$($TxtSelected.Text)'" }
    if (-not $BtnRefresh.IsEnabled) { throw "Check deve restare attivo: e' l'unico modo per sbloccare" }
    if ($MenuPinUpdates.IsEnabled -ne $true) { throw "a coda finita la voce Pin resta spenta" }
    if ($Grid.IsReadOnly) { throw "a coda finita le spunte restano bloccate" }

    $items.Clear()
    $script:listStale = $false
    Refresh-SelectionState
    Stop-AllJobs
    "OK queue   ciclo coda: Cancel premuto, in volo finito a $ran/5, Update bloccato fino al Check"
}

# 13f) Dopo un'alterazione della macchina il pulsante Update si blocca fino al Check:
# ripremerlo rilanciava winget su pacchetti gia' aggiornati, che escono con codice non-zero
# e finivano in griglia come X ROSSE su righe andate a buon fine.
$items.Clear()
$items.Add([WgtRow]@{ Id = 'A.A'; Name = 'A'; Selected = $true })
$script:listStale = $false
Refresh-SelectionState
if (-not $BtnUpdate.IsEnabled) { throw "con una riga selezionata e la lista fresca Update deve essere attivo" }

Set-UpdatesStale
if ($BtnUpdate.IsEnabled) { throw "dopo un'alterazione Update deve restare bloccato" }
if ($TxtSelected.Text -notmatch 'press Check') { throw "non viene detto PERCHE' Update e' bloccato: '$($TxtSelected.Text)'" }
if (-not $BtnRefresh.IsEnabled) { throw "Check deve restare attivo: e' l'unico modo per sbloccare" }

# I pin NON marcano la lista: bloccano gli aggiornamenti, non cambiano le versioni installate.
$script:listStale = $false
Set-PinFlags @('A.A')
if ($script:listStale) { throw "un pin ha marcato la lista come vecchia" }
$items.Clear()
$script:listStale = $false
Refresh-SelectionState

# Le quattro code che alterano la macchina lo dichiarano, e solo il Check sblocca.
foreach ($fn in 'Start-UpdateSelected', 'Install-Rows', 'Start-UninstallSelected', 'Invoke-PackageImport') {
    if ((Get-FunctionSource $fn) -notmatch 'Set-UpdatesStale') { throw "$fn non marca la lista come vecchia" }
}
if ((Get-FunctionSource 'Load-Upgrades') -notmatch 'listStale\s*=\s*\$false') { throw "Load-Upgrades non sblocca il pulsante" }
"OK stale   Update bloccato dopo un'alterazione, sbloccato solo dal Check"

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
$TabInstall.IsSelected = $true
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

# 15b) Il tab Settings e' fissato a DESTRA della striscia: un DockPanel come items host
# (TabPanel non sa allineare a destra un singolo item). Se qualcuno rimette TabPanel, il tab
# torna in fila subito dopo Updates e questo controllo se ne accorge.
# Serve il layout gia' calcolato, quindi sta qui e non nella sezione 12.
$xUpdates  = $TabUpdates.TranslatePoint([System.Windows.Point]::new(0, 0), $window.Content).X
$xSettings = $TabSettings.TranslatePoint([System.Windows.Point]::new(0, 0), $window.Content).X
$rightOfUpdates = $xUpdates + $TabUpdates.ActualWidth
if ($TabSettings.ActualWidth -le 0) { throw "layout della striscia non calcolato: il tab Settings misura 0" }
if ($xSettings -lt $rightOfUpdates + 100) {
    throw "il tab Settings non e' fissato a destra (x=$([int]$xSettings), fine di Updates=$([int]$rightOfUpdates))"
}
$xAbout = $TabAbout.TranslatePoint([System.Windows.Point]::new(0, 0), $window.Content).X
if ($xAbout -lt $xSettings) { throw "About non e' a destra di Settings (About $([int]$xAbout), Settings $([int]$xSettings))" }
"OK tabdock Settings e About a destra (x=$([int]$xSettings) e $([int]$xAbout) contro $([int]$rightOfUpdates) di Updates)"

# 15c) E il suo bordo VISIBILE combacia col bordo del riquadro sotto. Non e' pignoleria: il
# template della linguetta tiene 2px di stacco a destra per separarla dalla successiva, e
# sull'ultima a destra quei 2px la lasciavano disallineata di 2px dal riquadro. Il margine
# destro negativo li recupera; se qualcuno lo toglie, questo controllo se ne accorge.
$sbd = [System.Windows.Media.VisualTreeHelper]::GetChild($TabAbout, 0)
$rightBorder = $sbd.TranslatePoint([System.Windows.Point]::new(0, 0), $window.Content).X + $sbd.ActualWidth
$rightFrame  = $TabMain.TranslatePoint([System.Windows.Point]::new(0, 0), $window.Content).X + $TabMain.ActualWidth
if ([Math]::Abs($rightBorder - $rightFrame) -gt 0.5) {
    throw "il bordo dell'ultimo tab non combacia col riquadro: $([int]$rightBorder) contro $([int]$rightFrame)"
}
"OK tabedge bordo dell'ultimo tab (About) allineato al riquadro ($([int]$rightFrame)px)"

# 15e) Le tre modalita' della striscia non devono cambiarne l'ALTEZZA, e in sola icona il
# glifo deve stare al centro della linguetta.
# Erano due difetti distinti dello stesso pezzo: senza MinHeight la linguetta si accorciava
# di 2px passando a sola icona (il riquadro di riga del glifo e' piu' basso di quello del
# testo, e con la parola collassata restava solo lui), e il margine di stacco lasciato fisso
# sull'icona sopravviveva alla parola e spostava il glifo 3,5px a sinistra.
# Si misura contro il centro del BORDO VISIBILE, non del TabItem: il template tiene 2px di
# stacco a destra di ogni linguetta, quindi il centro dei due non coincide di 1px — e vale
# per il testo esattamente come per l'icona.
$heights = @{}
foreach ($mode in 'Icon + Text', 'Text', 'Icon') {
    Set-TabHeaderStyle $mode
    $window.Content.UpdateLayout()
    $heights[$mode] = [Math]::Round($TabInstall.ActualHeight, 1)
}
if (@($heights.Values | Sort-Object -Unique).Count -ne 1) {
    throw "la striscia cambia altezza fra le modalita': $(($heights.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', ')"
}

Set-TabHeaderStyle 'Icon'
$window.Content.UpdateLayout()
$bd = [System.Windows.Media.VisualTreeHelper]::GetChild($TabInstall, 0)
$glyph = $null
$queue = New-Object System.Collections.Queue
$queue.Enqueue($TabInstall)
while ($queue.Count -gt 0) {
    $n = $queue.Dequeue()
    for ($i = 0; $i -lt [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($n); $i++) {
        $c = [System.Windows.Media.VisualTreeHelper]::GetChild($n, $i)
        if ($c -is [System.Windows.Controls.TextBlock] -and $c.Visibility -eq 'Visible') { $glyph = $c }
        $queue.Enqueue($c)
    }
}
if (-not $glyph) { throw "in modalita' solo icona non si trova il glifo nella linguetta" }
$cGlyph  = $glyph.TranslatePoint([System.Windows.Point]::new(0, 0), $bd).X + $glyph.ActualWidth / 2
$cBorder = $bd.ActualWidth / 2
if ([Math]::Abs($cGlyph - $cBorder) -gt 0.6) {
    throw "in sola icona il glifo non e' centrato: centro glifo $([Math]::Round($cGlyph,1)), centro linguetta $([Math]::Round($cBorder,1))"
}
Set-TabHeaderStyle 'Icon + Text'
$window.Content.UpdateLayout()
"OK tabsize altezza uguale nelle tre modalita' ($($heights['Icon'])px), glifo centrato in sola icona"

# 15d) ...e sotto di lui il riquadro non deve avere un angolo arrotondato. Con un tab fissato
# a destra, la curva in alto a destra del riquadro affiorava sotto la linguetta come uno
# scalino. Entrambi gli angoli superiori sono quadrati perche' su entrambi i lati della
# striscia c'e' una linguetta.
$tplGrid = [System.Windows.Media.VisualTreeHelper]::GetChild($TabMain, 0)
$frame = $null
for ($i = 0; $i -lt [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($tplGrid); $i++) {
    $ch = [System.Windows.Media.VisualTreeHelper]::GetChild($tplGrid, $i)
    if ($ch -is [System.Windows.Controls.Border]) { $frame = $ch; break }
}
if (-not $frame) { throw "riquadro del contenuto non trovato nel template del TabControl" }
if ($frame.CornerRadius.TopRight -ne 0) {
    throw "il riquadro ha l'angolo in alto a destra arrotondato ($($frame.CornerRadius.TopRight)): affiora sotto il tab Settings"
}
if ($frame.CornerRadius.TopLeft -ne 0) {
    throw "il riquadro ha l'angolo in alto a sinistra arrotondato: affiora sotto il primo tab"
}
"OK tabjoin angoli superiori del riquadro quadrati sotto le linguette"

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
    $TabInstalled.IsSelected = $true
    if (-not (Wait-For { $installedItems.Count -gt 0 -and -not $script:isBusy } 120)) {
        throw "aprendo la scheda Installed l'elenco non si e' caricato"
    }
    $total = $installedItems.Count
    # A scansione finita la barra torna determinata: se restasse indeterminata continuerebbe a
    # scorrere per sempre, dicendo che qualcosa sta girando quando niente gira.
    if ($Progress.IsIndeterminate) { throw "a caricamento finito la barra e' ancora indeterminata" }

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

