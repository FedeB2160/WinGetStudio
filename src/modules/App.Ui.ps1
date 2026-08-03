<#
    App.Ui.ps1 — helper di UI condivisi da tutte le schede.

    Caricato dal bootstrap (src\WinGetUpdateTool.ps1): dot-source come .ps1,
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
