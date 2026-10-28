<#
    Test-InvokeWinGet.ps1
    ---------------------
    Verifica eseguibile delle due cause radice corrette in main.ps1.
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

Write-Host "`n1c) File di output rimasti in %TEMP%" -ForegroundColor Cyan
# Un figlio staccato (sezione 1, e nella realta' un installer) tiene aperti i file di
# redirect: la pulizia di Invoke-WinGet fallisce e wgt_*.out/.err restano in %TEMP%. Li
# rimuove Clear-WinGetTempFiles all'avvio, quando nessuno li tiene piu'.
Invoke-Expression (Get-FunctionText 'Clear-WinGetTempFiles')
$tempDir = [IO.Path]::GetTempPath()
$stale = [IO.Path]::Combine($tempDir, "wgt_$([Guid]::NewGuid().ToString('N')).out")
$keep  = [IO.Path]::Combine($tempDir, "wgtkeep_$PID.txt")
[IO.File]::WriteAllText($stale, 'x'); [IO.File]::WriteAllText($keep, 'x')
# Anche le cartelle: quella del download di winget (300 MB) se il processo muore a meta'.
$staleDir = [IO.Path]::Combine($tempDir, "wgt_test_$PID")
[void][IO.Directory]::CreateDirectory([IO.Path]::Combine($staleDir, 'deps'))
[IO.File]::WriteAllText([IO.Path]::Combine($staleDir, 'deps\x.appx'), 'x')
Clear-WinGetTempFiles
Check "un wgt_*.out rimasto viene rimosso" (-not [IO.File]::Exists($stale))
Check "una cartella wgt_* rimasta viene rimossa col contenuto" (-not [IO.Directory]::Exists($staleDir))
Check "un file con un altro nome resta dov'e'" ([IO.File]::Exists($keep))
[IO.File]::Delete($keep)

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
        public bool Selected, Pinned; public string Name, Version, Available, Id, Source, Status, StatusDetail; }'
}
# Stub di winget: Invoke-WinGetRead avvia un ESEGUIBILE con Process.Start, quindi lo stub e'
# un .cmd vero, non una funzione. Stampa il file di fixture cosi' com'e' (byte per byte, come
# fa winget) ed esce col codice scelto da ogni sezione tramite Set-Stub.
$stubDir = Join-Path ([IO.Path]::GetTempPath()) "wgt-stub-$PID"
[void][IO.Directory]::CreateDirectory($stubDir)
$wingetPath = Join-Path $stubDir 'winget.cmd'
[IO.File]::WriteAllText($wingetPath, "@echo off`r`ntype `"%WGT_STUB_FIXTURE%`"`r`nexit /b %WGT_STUB_EXIT%`r`n")
$env:WGT_STUB_FIXTURE = Join-Path $stubDir 'fixture.txt'
# Il fixture si scrive in UTF-8 senza BOM: e' cio' che winget mette sulla pipe.
function Set-Stub([string]$Text, [int]$Exit = 0) {
    [IO.File]::WriteAllText($env:WGT_STUB_FIXTURE, $Text, (New-Object Text.UTF8Encoding $false))
    $env:WGT_STUB_EXIT = "$Exit"
}
# Get-WinGetTable e Invoke-WinGetRead servono perche' i lettori le chiamano.
Invoke-Expression (Get-FunctionText 'Get-WinGetTable')
Invoke-Expression (Get-FunctionText 'Invoke-WinGetRead')
Invoke-Expression (Get-FunctionText 'Get-WinGetUpgrades')

Set-Stub @'
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

$upgradeRead = Get-WinGetUpgrades $true
$rows = @($upgradeRead.Rows)
Check "upgrade con fixture riuscita (exit $($upgradeRead.ExitCode))" $upgradeRead.Success
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
Write-Host "`n6) Tabella con un'intestazione che contiene spazi (winget pin list)" -ForegroundColor Cyan
# "Tipo di pin" (in inglese "Pin type") viene letto come TRE colonne separate: i loro
# finti offset cadono in mezzo al testo delle righe dati, il controllo di allineamento le
# giudica disallineate e le scarta tutte. Senza -MaxColumns l'elenco dei pin risultava
# sempre vuoto, e il pin sembrava non funzionare mentre winget lo aveva creato.
$pinFixture = @'
Nome              Id           Versione Origine Tipo di pin
-----------------------------------------------------------
7-Zip 26.02 (x64) 7zip.7zip    26.02    winget  Pinning
VLC media player  VideoLAN.VLC 3.0.23   winget  Blocking
'@
$pr = @(Get-WinGetTable $pinFixture -MaxColumns 3)
Check "con -MaxColumns 3 le righe si leggono (trovate $($pr.Count) su 2)" ($pr.Count -eq 2) ($pr | ForEach-Object { $_[1] })
Check "ID corretti (7zip.7zip, VideoLAN.VLC)" `
      ($pr.Count -eq 2 -and $pr[0][1] -eq '7zip.7zip' -and $pr[1][1] -eq 'VideoLAN.VLC') `
      "($(@($pr | ForEach-Object { $_[1] }) -join ', '))"
# La riproduzione del bug: senza il limite, l'intestazione con spazi fa perdere le righe.
$prNoLimit = @(Get-WinGetTable $pinFixture)
Check "senza -MaxColumns la tabella si perde (era il bug: $($prNoLimit.Count) righe)" ($prNoLimit.Count -lt 2)

# ------------------------------------------------------------------
Write-Host "`n6b) I lettori separano l'errore di winget dalla lista vuota" -ForegroundColor Cyan
Invoke-Expression (Get-FunctionText 'Get-WinGetSearch')
Invoke-Expression (Get-FunctionText 'Get-WinGetPins')
Invoke-Expression (Get-FunctionText 'Get-WinGetInstalled')
$readers = [ordered]@{
    search    = { Get-WinGetSearch 'fixture' }
    pins      = { Get-WinGetPins }
    installed = { Get-WinGetInstalled }
    upgrades  = { Get-WinGetUpgrades }
}
Set-Stub 'Failed to open source: test fixture' 1
foreach ($name in $readers.Keys) {
    $r = & $readers[$name]
    Check "$name con exit 1: errore, codice e diagnostica, zero righe" `
        ($r.Success -eq $false -and $r.ExitCode -eq 1 -and $r.Output -match 'test fixture' -and @($r.Rows).Count -eq 0)
}
# Una tabella stampata con exit non-zero non vale: le righe non si usano.
Set-Stub -Exit 1 @'
Name  Id      Version Available
-------------------------------
Foo   Foo.Foo 1.0     2.0
'@
$r = Get-WinGetUpgrades
Check "tabella con exit 1: nessuna riga" (-not $r.Success -and @($r.Rows).Count -eq 0)
# 0x8A150014 NO_APPLICATIONS_FOUND: vuoto valido per la ricerca, errore per gli altri.
Set-Stub 'Nessun pacchetto trovato con criteri di input corrispondenti.' -1978335212
$r = Get-WinGetSearch 'fixture'
Check "search senza corrispondenze: riuscita, vuota, codice preservato" ($r.Success -and $r.ExitCode -eq -1978335212 -and @($r.Rows).Count -eq 0)
foreach ($name in 'pins', 'installed', 'upgrades') {
    $r = & $readers[$name]
    Check "$name con NO_APPLICATIONS_FOUND: errore, non lista vuota" (-not $r.Success)
}
# Exit 0 e una frase al posto della tabella (es. "Nessun PIN configurato."): vuoto valido.
Set-Stub 'Nessun PIN configurato.'
foreach ($name in $readers.Keys) {
    $r = & $readers[$name]
    Check "$name con exit 0 senza tabella: riuscita e vuota" ($r.Success -and @($r.Rows).Count -eq 0)
}

Write-Host "`n6c) Una tabella di UNA riga resta una riga" -ForegroundColor Cyan
Set-Stub @'
Name     Id       Version
-------------------------
Only One Only.One 1.0
'@
$r = Get-WinGetSearch 'fixture'
Check "search con una riga (Id trovato '$(@($r.Rows)[0].Id)')" (@($r.Rows).Count -eq 1 -and @($r.Rows)[0].Id -eq 'Only.One')
Set-Stub @'
Name     Id       Version Source Pin type
-----------------------------------------
Only One Only.One 1.0     winget Blocking
'@
$r = Get-WinGetPins
Check "pin list con una riga (trovato '$(@($r.Rows) -join ',')')" (@($r.Rows).Count -eq 1 -and @($r.Rows)[0] -eq 'Only.One')

Write-Host "`n6f) Sorgente di ogni riga" -ForegroundColor Cyan
# La sorgente serve a installare dalla riga scelta (--source) e a leggerne i dettagli dal
# catalogo giusto. La ricerca interroga UNA sorgente per volta, quindi la sorgente di ogni riga
# e' quella interrogata, non una colonna da indovinare. Con MS Store sono due ricerche: dalla
# 1.29 winget non porta piu' in cima i risultati dello Store, e con un --count unico una parola
# comune ("spotify": 33 winget, 1 Store) lo lasciava fuori.
# Stub a due voci: per --source msstore stampa store.txt ed esce con WGT_STORE_EXIT.
Invoke-Expression (Get-FunctionText 'Get-WinGetOutputTail')
$storeFixture = Join-Path $stubDir 'store.txt'
$searchStub = Join-Path $stubDir 'search.cmd'
[IO.File]::WriteAllText($searchStub, "@echo off`r`necho %* | %SystemRoot%\System32\findstr.exe /c:msstore >nul && (type `"$storeFixture`" & exit /b %WGT_STORE_EXIT%)`r`ntype `"%WGT_STUB_FIXTURE%`"`r`nexit /b %WGT_STUB_EXIT%`r`n")
function Set-StoreStub([string]$Text, [int]$Exit = 0) {
    [IO.File]::WriteAllText($storeFixture, $Text, (New-Object Text.UTF8Encoding $false))
    $env:WGT_STORE_EXIT = "$Exit"
}
Set-Stub @'
Nome    Id             Versione Corrispondenza
----------------------------------------------
7-Zip   7zip.7zip      26.04    Moniker: 7zip
NanaZip M2Team.NanaZip 7.0.1843 Tag: 7zip
'@
Set-StoreStub @'
Nome                         Id           Versione
--------------------------------------------------
Spotify - Music and Podcasts 9NCBCSZSJRSB Unknown
'@
$savedPath = $wingetPath; $wingetPath = $searchStub
$r = @((Get-WinGetSearch 'fixture' $false).Rows)
Check "senza Store: solo winget ($(@($r | ForEach-Object { "$($_.Id)@$($_.Source)" }) -join ','))" ($r.Count -eq 2 -and @($r | Where-Object { $_.Source -ne 'winget' }).Count -eq 0)
$s = Get-WinGetSearch 'fixture' $true
$r = @($s.Rows)
Check "con lo Store: winget poi msstore ($(@($r | ForEach-Object { "$($_.Id)@$($_.Source)" }) -join ','))" `
      ($s.Success -and $r.Count -eq 3 -and $r[0].Source -eq 'winget' -and $r[2].Id -eq '9NCBCSZSJRSB' -and $r[2].Source -eq 'msstore')
# Store che non risponde: restano i risultati winget, e il perche' finisce nell'output (la
# scheda Install mette nel log le righe che nominano msstore).
Set-StoreStub 'Impossibile aprire la sorgente.' 1
$s = Get-WinGetSearch 'fixture' $true
Check "Store giu': ricerca riuscita con i soli winget, avviso su msstore" ($s.Success -and @($s.Rows).Count -eq 2 -and $s.Output -match 'msstore.*Impossibile aprire')
Set-StoreStub 'Nessun pacchetto trovato.' -1978335212
$s = Get-WinGetSearch 'fixture' $true
Check "Store senza corrispondenze: nessun avviso" ($s.Success -and @($s.Rows).Count -eq 2 -and $s.Output -notmatch 'msstore')
# Nessun winget ma lo Store si: i risultati dello Store si vedono.
Set-Stub 'Nessun pacchetto trovato.' -1978335212
Set-StoreStub @'
Nome    Id           Versione
-----------------------------
Spotify 9NCBCSZSJRSB Unknown
'@
$s = Get-WinGetSearch 'fixture' $true
Check "solo lo Store trova: riuscita, una riga msstore" ($s.Success -and @($s.Rows).Count -eq 1 -and @($s.Rows)[0].Source -eq 'msstore')
$wingetPath = $savedPath
# list: Disponibile compare solo se qualcosa ha un aggiornamento, quindi la sorgente e'
# l'ultima colonna, non la quarta. Le righe ARP non ne hanno.
Set-Stub @'
Nome           Id                             Versione     Disponibile Origine
------------------------------------------------------------------------------
1Password      AgileBits.1Password            > 8.12.36.40             winget
Android Studio ARP\Machine\X64\Android Studio 2026.1
7-Zip          7zip.7zip                      26.03        26.04       winget
'@
$r = @((Get-WinGetInstalled).Rows)
Check "list a 5 colonne: sorgente dall'ultima ($(@($r | ForEach-Object { "'$($_.Source)'" }) -join ','))" `
      ($r.Count -eq 3 -and $r[0].Source -eq 'winget' -and -not $r[1].Source -and $r[2].Source -eq 'winget')
Set-Stub @'
Nome  Id        Versione Disponibile Origine
--------------------------------------------
7-Zip 7zip.7zip 26.03    26.04       winget
'@
$r = @((Get-WinGetUpgrades).Rows)
Check "upgrade: sorgente winget ('$($r[0].Source)')" ($r.Count -eq 1 -and $r[0].Source -eq 'winget')

Write-Host "`n6g) Dettagli di un pacchetto: il testo di winget, comandi giusti" -ForegroundColor Cyan
# Le etichette di show e list --details sono tradotte ("Editore:", "Licenza:"): l'app mostra il
# testo cosi' com'e' (ADR 0021). Qui si verifica quali comandi partono, con lo stub che ristampa
# i propri argomenti.
Invoke-Expression (Get-FunctionText 'Get-WinGetDetails')
$argsStub = Join-Path $stubDir 'args.cmd'
[IO.File]::WriteAllText($argsStub, "@echo off`r`necho %*`r`n")
$savedPath = $wingetPath; $wingetPath = $argsStub
$d = Get-WinGetDetails 'Pkg.Id' 'winget' $true
$wingetPath = $savedPath
Check "installato con sorgente: list --details e show --source ($($d -replace "`r?`n", ' / '))" `
      ($d -match 'list --id Pkg\.Id -e --details' -and $d -match 'show --id Pkg\.Id -e --source winget' -and
       $d.IndexOf('list --id') -lt $d.IndexOf('show --id'))
$wingetPath = $argsStub
$d = Get-WinGetDetails 'ARP\Machine\X64\Foo' '' $true
$wingetPath = $savedPath
Check "installato senza sorgente (ARP): solo list --details" ($d -match 'list --id' -and $d -notmatch 'show --id')
$wingetPath = $argsStub
$d = Get-WinGetDetails '9NCBCSZSJRSB' 'msstore' $false
$wingetPath = $savedPath
Check "dal catalogo: solo show --source msstore" ($d -match 'show --id 9NCBCSZSJRSB -e --source msstore' -and $d -notmatch 'list --id')
# Spinner e frame \r di winget piu' vecchi: resta l'ultimo segmento, l'indentazione si tiene.
Set-Stub "  -`r  \`rTrovato 7-Zip [7zip.7zip]`r`nVersione: 26.04`r`nTag:`r`n  zip`r`n"
$d = Get-WinGetDetails '7zip.7zip' 'winget' $false
Check "testo pulito, indentazione intatta" ($d -match '(?m)^Trovato 7-Zip' -and $d -match '(?m)^  zip$' -and $d -notmatch '(?m)^\s*[-\\|/]\s*$')

Write-Host "`n6d) Coda dell'output per log e messaggi" -ForegroundColor Cyan
Invoke-Expression (Get-FunctionText 'Get-WinGetOutputTail')
$tail = @(Get-WinGetOutputTail "  -`r  |`rSorgente aperta`r`n`r`nErrore X`r`nLog: C:\x.log`r`n" 2)
Check "ultime due righe significative ($($tail -join ' | '))" ($tail.Count -eq 2 -and $tail[0] -eq 'Errore X' -and $tail[1] -eq 'Log: C:\x.log')
$tail = @(Get-WinGetOutputTail "  -`r  |`rSolo questa`r`n" 2)
Check "frame \r ridotti all'ultimo segmento ($($tail -join ' | '))" ($tail.Count -eq 1 -and $tail[0] -eq 'Solo questa')

Write-Host "`n6e) Output di winget letto come UTF-8, argomenti senza shell" -ForegroundColor Cyan
# winget scrive sempre UTF-8 (Core.cpp). La vecchia lettura "& winget | Out-String" decodificava
# con la code page della console: nell'exe senza console il primo job storpiava le accentate.
$accented = 'Non ' + [char]0x00E8 + ' stato trovato alcun pacchetto.'
Set-Stub $accented -1978335212
$r = Get-WinGetSearch 'fixture'
Check "lettera accentata intatta ('$(($r.Output -split "`r?`n")[0])')" ($r.Output -match [regex]::Escape($accented))
# Gli argomenti arrivano come array e si quotano per CreateProcess: lo stub li ristampa cosi'
# come li riceve. "x&y" quotato non viene eseguito nemmeno da un .cmd.
$argsStub = Join-Path $stubDir 'args.cmd'
[IO.File]::WriteAllText($argsStub, "@echo off`r`necho %*`r`n")
$savedPath = $wingetPath; $wingetPath = $argsStub
$r = Invoke-WinGetRead -Arguments @('search', 'a b', 'say "hi"', 'x&y')
$wingetPath = $savedPath
Check "argomenti quotati ($($r.Output.Trim()))" ($r.Output.Trim() -eq 'search "a b" "say \"hi\"" "x&y"')

Write-Host "`n7) Argomenti con apici sbilanciati" -ForegroundColor Cyan
# La riga di comando si costruisce per concatenazione e la esegue cmd: un Id che contenesse
# un apice doppio produrrebbe un comando malformato, che cmd eseguirebbe comunque. Gli Id
# vengono dal catalogo e dal registro ARP, dove il nome lo scrive l'installer, e questo
# processo gira elevato: meglio fermarsi con un errore chiaro.
$threw = $false
try { Invoke-WinGet 'cmd.exe' '/c echo "sbilanciato' } catch { $threw = $true }
Check "apici sbilanciati rifiutati invece di eseguiti" $threw
# E il caso normale non deve rompersi: gli apici bilanciati passano.
$ok = Invoke-WinGet 'cmd.exe' '/c echo "bilanciato"'
Check "apici bilanciati eseguiti (output '$($ok.Output.Trim())')" ($ok.Output -match 'bilanciato')
# '%': cmd espande %VAR% anche fra apici e DOPO il conteggio degli apici. Con questa variabile
# un "echo" diventerebbe due comandi; la riga si rifiuta prima di arrivare a cmd.
$env:WGT_PCT_PROBE = 'x" & echo INIETTATO & rem "'
$threw = $false; $msg = ''
try { Invoke-WinGet 'cmd.exe' '/c echo "%WGT_PCT_PROBE%"' } catch { $threw = $true; $msg = $_.Exception.Message }
Check "'%' rifiutato invece di espanso da cmd ($msg)" ($threw -and $msg -match "contain '%'")
# !VAR!: l'espansione ritardata si accende anche da HKCU, quindi la si spegne sulla riga di cmd.
Check "cmd con /v:off in entrambi i percorsi" (([regex]::Matches((Get-FunctionText 'Invoke-WinGet'), '/d /v:off /s /c')).Count -eq 2)

Write-Host "`n8) Stesso comando senza elevazione" -ForegroundColor Cyan
# winget rifiuta alcune operazioni da amministratore (0x8A15007D) e la coda le ripete come
# questo account senza elevazione, con un'attivita' pianificata (ADR 0018). L'attivita' vera
# la prova Test-Ui -Live; qui una Invoke-UnelevatedTask finta esegue la riga con cmd in modo
# sincrono, e si verifica che Invoke-WinGet le passi lo stesso comando, legga l'output e torni
# l'exit code come nel percorso normale.
$script:taskArgs = $null
function Invoke-UnelevatedTask([string]$Arguments, [scriptblock]$Tick) {
    $script:taskArgs = $Arguments
    $psi = New-Object Diagnostics.ProcessStartInfo 'cmd.exe', $Arguments
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow  = $true
    $p = [Diagnostics.Process]::Start($psi)
    $p.WaitForExit()
    $p.ExitCode
}
$null = Invoke-WinGet 'cmd.exe' '/c echo diretto'
Check "senza -Unelevated l'attivita' non entra in gioco" ($null -eq $script:taskArgs)
$u = Invoke-WinGet 'cmd.exe' '/c echo senza-elevazione' -Unelevated
Check "con -Unelevated la stessa riga passa dall'attivita', col titolo della finestra ($script:taskArgs)" `
      ($script:taskArgs -match '^/d /v:off /s /c "title WinGet Studio & "cmd\.exe" /c echo senza-elevazione >".+\.out" 2>".+\.err""$')
Check "output letto dai file come nel percorso normale ('$($u.Output.Trim())')" ($u.Output.Trim() -eq 'senza-elevazione')
$e = Invoke-WinGet 'cmd.exe' '/c exit -1978335107' -Unelevated
Check "exit code negativo intatto (=$($e.ExitCode))" ($e.ExitCode -eq -1978335107)
$threw = $false
try { Invoke-WinGet 'cmd.exe' '/c echo "sbilanciato' -Unelevated } catch { $threw = $true }
Check "la guardia sugli apici vale anche senza elevazione" $threw
# Qui l'attivita' finta c'e': se la guardia mancasse il comando girerebbe, non fallirebbe per altro.
$script:taskArgs = $null; $threw = $false; $msg = ''
try { Invoke-WinGet 'cmd.exe' '/c echo "%WGT_PCT_PROBE%"' -Unelevated } catch { $threw = $true; $msg = $_.Exception.Message }
Check "'%' rifiutato anche senza elevazione, prima dell'attivita'" ($threw -and $msg -match "contain '%'" -and $null -eq $script:taskArgs)
Remove-Item Env:\WGT_PCT_PROBE

# L'attivita' vera: token filtrato (RunLevel Limited) nella sessione gia' aperta (Interactive),
# avviabile anche a batteria, e cancellata comunque, anche quando winget fallisce.
$taskSrc = Get-FunctionText 'Invoke-UnelevatedTask'
Check "LogonType Interactive e RunLevel Limited" ($taskSrc -match '-LogonType Interactive' -and $taskSrc -match '-RunLevel Limited')
Check "avviabile e non fermata a batteria" ($taskSrc -match 'AllowStartIfOnBatteries' -and $taskSrc -match 'DontStopIfGoingOnBatteries')
Check "Unregister-ScheduledTask in un finally" ($taskSrc -match '(?s)finally\s*\{[^}]*Unregister-ScheduledTask')

Write-Host "`n9) Esito dai codici d'uscita" -ForegroundColor Cyan
# Nomi da "winget error <codice>" (1.29.380). La lista era sfasata di uno: un'installazione non
# riuscita o annullata risultava un avviso, e un "gia' installato" un errore. I literal esadecimali
# a 8 cifre sono Int32 negativi, cioe' proprio l'exit code che winget restituisce.
Invoke-Expression (Get-FunctionText 'Get-UpdateStatus')
$codes = @(
    @(0,          'ok',      'successo'),
    @(0x8A150109, 'warning', 'INSTALL_REBOOT_REQUIRED_TO_FINISH'),
    @(0x8A15010B, 'warning', 'INSTALL_REBOOT_INITIATED'),
    @(0x8A15010D, 'warning', 'INSTALL_ALREADY_INSTALLED'),
    @(3010,       'warning', 'ERROR_SUCCESS_REBOOT_REQUIRED'),
    @(1641,       'warning', 'ERROR_SUCCESS_REBOOT_INITIATED'),
    @(0x8A150108, 'error',   'INSTALL_CONTACT_SUPPORT'),
    @(0x8A15010A, 'error',   'INSTALL_REBOOT_REQUIRED_FOR_INSTALL (installazione non riuscita)'),
    @(0x8A15010C, 'error',   'INSTALL_CANCELLED_BY_USER')
)
foreach ($c in $codes) {
    $got = Get-UpdateStatus $c[0]
    Check ("{0} -> {1} ({2}, letto '{3}')" -f $c[2], $c[1], ('0x{0:X8}' -f $c[0]), $got) ($got -eq $c[1])
}

# ------------------------------------------------------------------
Remove-Item -LiteralPath $stubDir -Recurse -Force -ErrorAction SilentlyContinue
if ($failures -eq 0) { Write-Host "`nTutti i test passati.`n" -ForegroundColor Green; exit 0 }
Write-Host "`n$failures test falliti.`n" -ForegroundColor Red
exit 1

