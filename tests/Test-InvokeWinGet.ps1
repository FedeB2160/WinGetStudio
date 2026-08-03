<#
    Test-InvokeWinGet.ps1
    ---------------------
    Verifica eseguibile delle due cause radice corrette in WinGetUpdateTool.ps1.
    Non serve admin, non installa nulla.

        powershell -ExecutionPolicy Bypass -File .\tests\Test-InvokeWinGet.ps1

    Esce 0 se tutto passa, 1 al primo assert fallito.
#>

$ErrorActionPreference = 'Stop'
$failures = 0
function Check([string]$what, [bool]$ok, [string]$detail = '') {
    if ($ok) { Write-Host "  OK   $what" -ForegroundColor Green }
    else     { Write-Host "  FAIL $what $detail" -ForegroundColor Red; $script:failures++ }
}

# Estrae le funzioni dal codice reale (via AST): il test gira sulla produzione, non su
# una copia che puo' divergere. La logica sta nei moduli, quindi si cerca in tutti i
# file dell'app — il bootstrap da solo non contiene piu' nessuna di queste funzioni.
$root    = Split-Path -Parent $PSScriptRoot
$srcFiles = @((Join-Path $root 'src\main.ps1')) +
            @(Get-ChildItem (Join-Path $root 'src\modules') -Filter *.ps1 -ErrorAction SilentlyContinue |
              ForEach-Object { $_.FullName })

# Ritorna il testo sorgente di una funzione, cercandola in tutti i file. Esce con
# errore chiaro se non c'e': una funzione rinominata deve fermare il test, non farlo
# passare per assenza di verifiche.
function Get-FunctionText([string]$name) {
    foreach ($f in $srcFiles) {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($f, [ref]$null, [ref]$null)
        $fn  = $ast.Find({
            param($n)
            $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name
        }.GetNewClosure(), $true)
        if ($fn) { return $fn.Extent.Text }
    }
    Write-Host "$name non trovata in src\ (bootstrap + moduli)" -ForegroundColor Red
    exit 1
}

Invoke-Expression (Get-FunctionText 'Invoke-WinGet')

# ------------------------------------------------------------------
Write-Host "`n1) Attesa legata al processo, non alla pipe" -ForegroundColor Cyan
# Un figlio staccato eredita il handle di stdout e resta vivo ~40s: con
# '& cmd | Out-String' la pipe non arriva a EOF e l'attesa sarebbe infinita
# (il bug degli spinner eterni). Invoke-WinGet deve ritornare all'uscita di cmd.
$sw = [Diagnostics.Stopwatch]::StartNew()
$r  = Invoke-WinGet 'cmd.exe' '/c start /b ping -n 40 127.0.0.1'
$sw.Stop()
$pingAlive = @(Get-Process -Name PING -ErrorAction SilentlyContinue).Count -gt 0

Check "ritorna senza aspettare il figlio ($([int]$sw.Elapsed.TotalSeconds)s)" ($sw.Elapsed.TotalSeconds -lt 15)
Check "exit code del processo padre disponibile (=$($r.ExitCode))" ($r.ExitCode -eq 0)
Check "il figlio era ancora vivo al ritorno" $pingAlive `
      "(se falso il test non prova nulla: il figlio e' morto troppo presto)"
Get-Process -Name PING -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

# ------------------------------------------------------------------
Write-Host "`n1b) Output riletto come UTF-8" -ForegroundColor Cyan
# winget scrive UTF-8; Get-Content senza -Encoding usa il codepage ANSI e i messaggi
# localizzati arrivavano a mojibake ("Ã¨" invece di "e' accentata").
# I caratteri sono espressi come codepoint: il test non dipende dall'encoding di questo file.
$accent = [string][char]0xC8 + [string][char]0xF9      # E maiuscola accentata + u accentata
$u = Invoke-WinGet 'powershell.exe' `
     '-NoProfile -Command "[Console]::OutputEncoding=[System.Text.Encoding]::UTF8; [Console]::Out.Write([string][char]0xC8 + [string][char]0xF9)"'
Check "accenti integri nell'output (attesi '$accent', letti '$($u.Output.Trim())')" ($u.Output.Contains($accent))
Check "nessun mojibake ('$([char]0xC3)' non presente)" (-not $u.Output.Contains([string][char]0xC3))

# ------------------------------------------------------------------
Write-Host "`n2) Overload di Dispatcher.BeginInvoke" -ForegroundColor Cyan
# BeginInvoke non ha overload (Delegate, DispatcherPriority): la forma con la stringa
# in seconda posizione passa 'Background' COME ARGOMENTO a un delegate senza parametri
# -> TargetParameterCountException a dispatch. Si riconosce dalla priorita' risolta.
Add-Type -AssemblyName WindowsBase
$d = [System.Windows.Threading.Dispatcher]::CurrentDispatcher
$bad  = $d.BeginInvoke([action]{ }, 'Background')
$good = $d.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [action]{ })
Check "forma buggata riconoscibile (Priority=$($bad.Priority), attesa Normal)" ($bad.Priority -eq 'Normal')
Check "forma corretta priority-first (Priority=$($good.Priority))" ($good.Priority -eq 'Background')

# Solo codice, non commenti (il commento esplicativo cita la forma sbagliata).
# Su tutti i file: la chiamata vive in Tab.Updates.ps1, non nel bootstrap.
$badCalls = @(foreach ($f in $srcFiles) {
    Get-Content $f | Where-Object { $_ -notmatch '^\s*#' -and $_ -match 'BeginInvoke\(\[action\]' }
})
Check "nessun BeginInvoke([action]...) nel codice dell'app" ($badCalls.Count -eq 0) $badCalls

# ------------------------------------------------------------------
Write-Host "`n3) Smoke test su winget" -ForegroundColor Cyan
$wg = Get-Command winget -ErrorAction SilentlyContinue
if (-not $wg) { Write-Host "  SKIP winget non presente" -ForegroundColor Yellow }
else {
    $v = Invoke-WinGet $wg.Source '--version'
    Check "winget --version exit 0 (=$($v.ExitCode))" ($v.ExitCode -eq 0)
    Check "output catturato ('$($v.Output.Trim())')" (-not [string]::IsNullOrWhiteSpace($v.Output))
}

# ------------------------------------------------------------------
Write-Host "`n4) Parsing di un output winget con DUE tabelle" -ForegroundColor Cyan
# winget stampa una seconda tabella per i pacchetti che richiedono targeting esplicito,
# con larghezze di colonna proprie (colonne a un solo spazio di distanza). Con una sola
# ancora il suo header finiva in griglia come riga fantasma e i suoi pacchetti sparivano.
# Riga della griglia: al parser serve solo un tipo con le proprieta' assegnabili.
if (-not ('WgtRow' -as [type])) {
    Add-Type -TypeDefinition 'public class WgtRow {
        public bool Selected, Pinned; public string Name, Version, Available, Id, Status, StatusDetail; }'
}
# Stub di winget: il parser fa "& winget @wgArgs", quindi una funzione con questo nome
# ha la precedenza sull'eseguibile e nessuna modifica al codice di produzione serve.
function winget { $fixture }
# Get-WinGetTable serve perche' Get-WinGetUpgrades la chiama.
Invoke-Expression (Get-FunctionText 'Get-WinGetTable')
Invoke-Expression (Get-FunctionText 'Get-WinGetUpgrades')

$fixture = @'
Nome                                  Id                                        Versione       Disponibile    Origine
---------------------------------------------------------------------------------------------------------------------
Claude                                Anthropic.Claude                          1.24012.1.0    1.24012.9      winget
Google Chrome                         Google.Chrome.EXE                         150.0.7871.187 151.0.7922.72  winget
MEGAsync                              Mega.MEGASync                             < 6.5.0.2      6.5.0.2        winget
Visual Studio Community 2026 Insiders Microsoft.VisualStudio.Community.Insiders 18.9.12020.428 18.9.12023.133 winget
4 aggiornamenti disponibili.

Per i pacchetti seguenti e' disponibile un aggiornamento, ma e' necessario un targeting esplicito per l'aggiornamento:
Nome    Id              Versione Disponibile Origine
----------------------------------------------------
Discord Discord.Discord 1.0.9249 1.0.9250    winget
'@

$rows = @(Get-WinGetUpgrades $true)
$ids  = @($rows | ForEach-Object { $_.Id })
Check "5 pacchetti (4 + 1 a targeting esplicito), trovati $($rows.Count)" ($rows.Count -eq 5) ($ids -join ', ')
Check "nessuna riga fantasma dall'header della 2a tabella" (@($rows | Where-Object { $_.Id -eq 'Id' -or $_.Name -eq 'Nome' }).Count -eq 0)
Check "nessuna riga dalla frase di riepilogo/prose" (@($rows | Where-Object { $_.Name -like '*aggiornament*' }).Count -eq 0)

$chrome = $rows | Where-Object { $_.Id -eq 'Google.Chrome.EXE' }
Check "colonne allineate sulla 1a tabella (Chrome 150.0.7871.187 -> 151.0.7922.72)" `
      ($chrome -and $chrome.Name -eq 'Google Chrome' -and $chrome.Version -eq '150.0.7871.187' -and $chrome.Available -eq '151.0.7922.72') `
      "($($chrome.Name)|$($chrome.Version)|$($chrome.Available))"

$vs = $rows | Where-Object { $_.Id -eq 'Microsoft.VisualStudio.Community.Insiders' }
Check "nome lungo non troncato (Visual Studio Community 2026 Insiders)" `
      ($vs -and $vs.Name -eq 'Visual Studio Community 2026 Insiders') "($($vs.Name))"

$dc = $rows | Where-Object { $_.Id -eq 'Discord.Discord' }
Check "pacchetto della 2a tabella presente e parsato (Discord 1.0.9249 -> 1.0.9250)" `
      ($dc -and $dc.Name -eq 'Discord' -and $dc.Version -eq '1.0.9249' -and $dc.Available -eq '1.0.9250') `
      "($($dc.Name)|$($dc.Version)|$($dc.Available))"

# ------------------------------------------------------------------
Write-Host "`n5) Tabelle di search e list (3 e 4 colonne)" -ForegroundColor Cyan
# Il numero di colonne varia col comando E col risultato: "winget list --source winget"
# ne ha 3, "search vlc" 5, "search ab --count 5" 3. Con la vecchia soglia a 4 colonne le
# tabelle a 3 venivano scartate in silenzio. Le prime tre colonne (Nome|Id|Versione)
# sono le uniche affidabili, ed e' tutto cio' che servira' a Install e Installed.

# search troncato: 3 colonne, piu' la riga di prosa che winget aggiunge in coda.
$searchFixture = @'
Nome        Id                      Versione
--------------------------------------------
Robo 3T     3TSoftwareLabs.Robo3T   1.4.4
Studio 3T   3TSoftwareLabs.Studio3T 2026.12.0
<voci aggiuntive troncate a causa del limite dei risultati>
'@
$sr = @(Get-WinGetTable $searchFixture)
Check "3 colonne: 2 righe lette (trovate $($sr.Count))" ($sr.Count -eq 2) ($sr | ForEach-Object { $_ -join '|' })
Check "prosa di troncamento scartata" (@($sr | Where-Object { $_[0] -like '<voci*' }).Count -eq 0)
Check "campi corretti (Studio 3T | 3TSoftwareLabs.Studio3T | 2026.12.0)" `
      ($sr.Count -eq 2 -and $sr[1][0] -eq 'Studio 3T' -and $sr[1][1] -eq '3TSoftwareLabs.Studio3T' -and $sr[1][2] -eq '2026.12.0') `
      "($($sr[1] -join '|'))"

# list: 4 colonne dove la QUARTA e' Origine, non Disponibile come in upgrade. La
# versione puo' avere il prefisso "> " (upgrade disponibile), che resta nel campo:
# chi lo mostra lo togliera'.
$listFixture = @'
Nome              Id                   Versione       Origine
-------------------------------------------------------------
1Password         AgileBits.1Password  > 8.12.30.21   winget
7-Zip 26.02 (x64) 7zip.7zip            26.02          winget
'@
$lr = @(Get-WinGetTable $listFixture)
Check "4 colonne: 2 righe lette (trovate $($lr.Count))" ($lr.Count -eq 2) ($lr | ForEach-Object { $_ -join '|' })
Check "nome con spazi e parentesi non troncato (7-Zip 26.02 (x64))" `
      ($lr.Count -eq 2 -and $lr[1][0] -eq '7-Zip 26.02 (x64)') "($($lr[1][0]))"
Check "prefisso '>' preservato nella versione (> 8.12.30.21)" `
      ($lr.Count -ge 1 -and $lr[0][2] -eq '> 8.12.30.21') "($($lr[0][2]))"
Check "la 4a colonna di list e' Origine (winget), non una versione disponibile" `
      ($lr.Count -ge 1 -and $lr[0][3] -eq 'winget') "($($lr[0][3]))"

# ------------------------------------------------------------------
if ($failures -eq 0) { Write-Host "`nTutti i test passati.`n" -ForegroundColor Green; exit 0 }
Write-Host "`n$failures test falliti.`n" -ForegroundColor Red
exit 1
