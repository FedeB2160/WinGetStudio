<#
    App.Ui.ps1 — helper di UI condivisi da tutte le schede.

    Caricato dal bootstrap (src\main.ps1): dot-source come .ps1,
    concatenato nell'exe al posto del marcatore ###MODULES###.
#>

# Riga di log con timestamp. $TxtLog e il log stesso sono condivisi da tutte le
# schede: vivono fuori dal TabControl, in fondo alla finestra.
function Write-Log([string]$msg) {
    $ts = (Get-Date).ToString('HH:mm:ss')
    $TxtLog.AppendText("[$ts] $msg`r`n")
    $TxtLog.ScrollToEnd()
}

# ------------------------------------------------------------------
# STATO "OCCUPATO" GLOBALE
# ------------------------------------------------------------------
# winget non e' affidabile in parallelo, quindi un'operazione in corso su una scheda
# deve spegnere i comandi di TUTTE le schede — non solo della sua.
# Ogni scheda registra il proprio handler in Initialize-*Tab invece di essere chiamata
# per nome da qui: cosi' aggiungere una scheda non richiede di toccare questo file.
$script:isBusy       = $false
$script:busyHandlers = New-Object System.Collections.ArrayList

function Register-BusyHandler([scriptblock]$handler) {
    [void]$script:busyHandlers.Add($handler)
}

function Set-AppBusy([bool]$busy) {
    $script:isBusy = $busy
    foreach ($h in $script:busyHandlers) { & $h $busy }
}

# Sta girando un processo winget? Comprende le RICERCHE, che di proposito NON alzano lo stato
# occupato — il typeahead deve restare fluido — ma sono comunque un processo winget. Chi sta
# per lanciarne un altro deve chiedere a questa, non a $script:isBusy: con il solo isBusy,
# digitare in Install e passare subito a Installed lanciava winget search e winget list
# insieme, ed e' con due processi in parallelo che un comando esce con exit 1.
# $script:searchInFlight vive in Tab.Install.ps1 e vale 0 finche' quel modulo non e' stato
# caricato; il confronto regge anche su $null.
function Test-WinGetBusy {
    return ($script:isBusy -or ($script:searchInFlight -gt 0))
}

