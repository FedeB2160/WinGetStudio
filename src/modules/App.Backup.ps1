<#
    App.Backup.ps1 — export e import dell'elenco pacchetti: si salva su file JSON cosa
    c'e' su questa macchina e si reinstalla su un'altra.

    I due pulsanti stanno nella scheda Installed, ma l'operazione riguarda la macchina
    intera e non la selezione, quindi vive in un modulo suo.

    Caricato da src\main.ps1: dot-source come .ps1, concatenato nell'exe al posto
    del marcatore ###MODULES###.
#>

# Quanti pacchetti contiene un file di export. Struttura reale del JSON di winget:
#   Sources[] -> Packages[] -> PackageIdentifier
# Torna $null se il file non e' un export valido: meglio dirlo prima di lanciare winget.
function Get-ImportPackageCount([string]$Path) {
    try {
        $json = Get-Content $Path -Raw -Encoding UTF8 | ConvertFrom-Json
        if (-not $json.Sources) { return $null }
        $n = 0
        foreach ($s in $json.Sources) { $n += @($s.Packages).Count }
        return $n
    }
    catch { return $null }
}

# Scelta del file, poi l'azione. Sono separate perche' un dialog non si puo' pilotare da
# un test headless, mentre Invoke-PackageExport si.
function Start-Export {
    if (Test-WinGetBusy) { return }

    $dlg = New-Object Microsoft.Win32.SaveFileDialog
    $dlg.Title    = 'Export installed packages'
    $dlg.Filter   = 'Package list (*.json)|*.json|All files (*.*)|*.*'
    $dlg.FileName = "winget-packages-$((Get-Date).ToString('yyyy-MM-dd')).json"
    $dlg.InitialDirectory = [Environment]::GetFolderPath('Desktop')
    if ($dlg.ShowDialog() -ne $true) { return }
    Invoke-PackageExport $dlg.FileName
}

function Invoke-PackageExport([string]$file) {
    # Di nuovo: fra la scelta del file e qui puo' essere rientrata una ricerca.
    if (Test-WinGetBusy) { return }
    Set-AppBusy $true
    $InstalledSpinner.Visibility = [System.Windows.Visibility]::Visible
    Write-Log "Exporting the package list to $file ..."

    # Una sola invocazione, non una coda: e' un comando unico su tutta la macchina.
    # Niente --include-versions: fissare le versioni esatte rende l'import fragile
    # (una versione non piu' pubblicata lo fa fallire). Si esporta cosa e' installato,
    # l'import prende l'ultima versione disponibile.
    [void](Start-BackgroundJob -Functions 'Invoke-WinGet', 'Get-UpdateStatus' `
        -Vars @{ wingetPath = $wingetPath; outFile = $file } `
        -Script {
            $r = Invoke-WinGet $wingetPath "export -o `"$outFile`" --accept-source-agreements" `
                    { param($s) LogUI "   ...export running for ${s}s" }
            [PSCustomObject]@{ Status = Get-UpdateStatus $r.ExitCode; Code = $r.ExitCode; Output = $r.Output }
        } `
        -OnDone {
            param($result)
            $InstalledSpinner.Visibility = [System.Windows.Visibility]::Collapsed
            $r = @($result)[0]
            if ($r -and $r.Status -eq 'ok') {
                $n = Get-ImportPackageCount $file
                Write-Log "Export done: $(if ($null -ne $n) { "$n packages" } else { 'file written' })."
                # winget elenca a parte i pacchetti che nessuna sorgente conosce: non e'
                # un errore, ma l'utente deve sapere che non finiranno nel file.
                $skipped = @($r.Output -split "`r`n|`n" | Where-Object { $_ -match 'available from any source|disponibile in alcuna origine' }).Count
                if ($skipped -gt 0) { Write-Log "  $skipped installed packages are in no source and were left out." }
            }
            else {
                Write-Log "Export FAILED (exit $($r.Code))."
                foreach ($l in @($r.Output -split "`r`n|`n" | Where-Object { $_.Trim() } | Select-Object -Last 2)) {
                    Write-Log "   $($l.Trim())"
                }
            }
            Set-AppBusy $false
        })
}

function Start-Import {
    if (Test-WinGetBusy) { return }

    $dlg = New-Object Microsoft.Win32.OpenFileDialog
    $dlg.Title  = 'Import packages from a list'
    $dlg.Filter = 'Package list (*.json)|*.json|All files (*.*)|*.*'
    $dlg.InitialDirectory = [Environment]::GetFolderPath('Desktop')
    if ($dlg.ShowDialog() -ne $true) { return }
    $file = $dlg.FileName

    $count = Get-ImportPackageCount $file
    if ($null -eq $count) {
        [System.Windows.MessageBox]::Show(
            "This file is not a winget package list.`n`n$file",
            "Cannot import", [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error) | Out-Null
        return
    }

    # CONFERMA: l'import installa software senza altre domande. Il conteggio viene dal
    # file, non da una stima, e il default e' No.
    $answer = [System.Windows.MessageBox]::Show(
        "Install $count package$(if ($count -ne 1) { 's' }) from this list?`n`n$file`n`n" +
        "Packages already installed are skipped or upgraded. Packages no longer available " +
        "in any source are ignored rather than failing the whole import.",
        "Confirm import",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Warning,
        [System.Windows.MessageBoxResult]::No)
    if ($answer -ne [System.Windows.MessageBoxResult]::Yes) {
        Write-Log "Import cancelled."
        return
    }
    Invoke-PackageImport $file $count
}

function Invoke-PackageImport([string]$file, [int]$count) {
    if (Test-WinGetBusy) { return }
    Set-AppBusy $true
    $InstalledSpinner.Visibility = [System.Windows.Visibility]::Visible
    Write-Log "Importing $count packages from $file ..."

    # Una sola invocazione lunga, non una coda per pacchetto: e' winget a scorrere la
    # lista, quindi non c'e' un esito per riga da mostrare. Il Tick da 30s serve a
    # rendere visibile che sta ancora lavorando.
    # --ignore-unavailable: senza, un solo pacchetto non piu' pubblicato fa fallire tutto.
    # --disable-interactivity: senza console un prompt bloccherebbe per sempre.
    [void](Start-BackgroundJob -Functions 'Invoke-WinGet', 'Get-UpdateStatus' `
        -Vars @{ wingetPath = $wingetPath; inFile = $file } `
        -Script {
            $r = Invoke-WinGet $wingetPath ("import -i `"$inFile`" --ignore-unavailable " +
                    "--accept-source-agreements --accept-package-agreements --disable-interactivity") `
                    { param($s) LogUI "   ...import running for ${s}s" }
            [PSCustomObject]@{ Status = Get-UpdateStatus $r.ExitCode; Code = $r.ExitCode; Output = $r.Output; Seconds = $r.Seconds }
        } `
        -OnDone {
            param($result)
            $InstalledSpinner.Visibility = [System.Windows.Visibility]::Collapsed
            $r = @($result)[0]
            switch ($r.Status) {
                'ok'      { Write-Log "Import done ($($r.Seconds)s)." }
                'warning' { Write-Log "Import finished with warnings (exit $($r.Code)): a reboot may be required." }
                default {
                    Write-Log "Import FAILED (exit $($r.Code))."
                    foreach ($l in @($r.Output -split "`r`n|`n" | Where-Object { $_.Trim() } | Select-Object -Last 3)) {
                        Write-Log "   $($l.Trim())"
                    }
                }
            }
            Write-Log "Press Refresh to rebuild the installed list."
            Set-AppBusy $false
            # L'import ha installato software: l'elenco degli aggiornamenti e' di prima.
            Set-UpdatesStale
        })
}

function Initialize-Backup {
    $BtnExport.Add_Click({ Start-Export })
    $BtnImport.Add_Click({ Start-Import })
    Register-BusyHandler {
        param($busy)
        $BtnExport.IsEnabled = -not $busy
        $BtnImport.IsEnabled = -not $busy
    }
}
