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
