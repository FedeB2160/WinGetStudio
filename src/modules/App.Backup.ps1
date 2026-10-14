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
# Torna $null se il file non ha quella forma: meglio dirlo prima di lanciare winget. Lo schema
# completo lo valida winget stesso all'import.
# -LiteralPath: con -Path un nome con [ ] e' un wildcard, e un export valido risultava non valido.
# [Management.Automation.PSCustomObject] per esteso: [PSCustomObject] e' l'acceleratore di
# [psobject] e accetterebbe anche un array (radice "[...]").
# Packages assente: @($null).Count fa 1, ed era cosi' che {"Sources":[{}]} contava un pacchetto.
function Get-ImportPackageCount([string]$Path) {
    try {
        $json = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($json -isnot [Management.Automation.PSCustomObject] -or $json.Sources -isnot [array]) { return $null }
        $n = 0
        foreach ($s in $json.Sources) {
            if ($s.Packages -isnot [array]) { return $null }
            $n += $s.Packages.Count
        }
        return $n
    }
    catch { return $null }
}

# Pacchetti di un file di export per l'anteprima dell'import: una riga spuntata per pacchetto,
# nell'ordine del file (New-ImportSubset sceglie per posizione: lo stesso ID puo' stare in due
# sorgenti). Json e' il file letto, da cui si costruisce il file ridotto. Stored conta i
# pacchetti con proprieta' oltre le quattro note: winget 1.29 ci salva --custom/--override e
# all'import le riapplica, e lo si dice senza doverne conoscere i nomi.
# $null se il file non ha la forma Sources[] -> Packages[] (la stessa regola del conteggio).
function Get-ImportPackages([string]$Path) {
    if ($null -eq (Get-ImportPackageCount $Path)) { return $null }
    $json = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    $known = 'PackageIdentifier', 'Version', 'Channel', 'Scope'
    $rows = New-Object System.Collections.ArrayList
    $stored = 0
    foreach ($s in $json.Sources) {
        foreach ($p in $s.Packages) {
            [void]$rows.Add([WgtRow]@{ Selected = $true; Name = $p.PackageIdentifier; Id = $p.PackageIdentifier
                                       Version = "$($p.Version)"; Source = "$($s.SourceDetails.Name)" })
            if (@($p.PSObject.Properties.Name | Where-Object { $_ -notin $known }).Count) { $stored++ }
        }
    }
    [PSCustomObject]@{ Json = $json; Rows = $rows.ToArray(); Stored = $stored }
}

# Il file di export ridotto ai pacchetti in posizione $Keep (ordine di Get-ImportPackages), come
# testo JSON. Gli oggetto-pacchetto restano QUELLI letti, con tutto cio' che contengono; radice
# e sorgenti si copiano (il file letto non cambia) e una sorgente rimasta vuota si toglie.
# -Depth 10: il default di ConvertTo-Json in PowerShell 5.1 e' 2 e troncherebbe i pacchetti.
function New-ImportSubset([object]$Json, [int[]]$Keep) {
    $i = 0
    $sources = foreach ($s in $Json.Sources) {
        $kept = @(foreach ($p in $s.Packages) { if ($Keep -contains $i) { $p }; $i++ })
        if ($kept.Count -gt 0) {
            $copy = $s.PSObject.Copy()
            $copy.Packages = $kept
            $copy
        }
    }
    $root = $Json.PSObject.Copy()
    $root.Sources = @($sources)
    $root | ConvertTo-Json -Depth 10
}

# Griglia dell'anteprima: spunta, ID, sorgente, versione (se il file la fissa). Stili e colori
# della finestra principale, come le altre griglie; alta al massimo 260px e scorrevole.
function New-ImportPreviewGrid($Rows) {
    $g = New-Object System.Windows.Controls.DataGrid
    $g.AutoGenerateColumns = $false
    $g.CanUserAddRows      = $false
    $g.HeadersVisibility   = [System.Windows.Controls.DataGridHeadersVisibility]::Column
    $g.GridLinesVisibility = [System.Windows.Controls.DataGridGridLinesVisibility]::Horizontal
    $g.MaxHeight = 260
    $g.Margin    = New-Object System.Windows.Thickness 0, 12, 0, 0
    $g.ColumnHeaderStyle = $window.FindResource('GridHeader')
    $g.CellStyle         = $window.FindResource('GridCell')
    foreach ($p in @(@('Background', 'BgBrush'), @('Foreground', 'FgBrush'), @('BorderBrush', 'CtrlBorderBrush'),
                     @('RowBackground', 'BgBrush'), @('AlternatingRowBackground', 'RowAltBgBrush'),
                     @('HorizontalGridLinesBrush', 'BorderBrush2'))) {
        $g.SetResourceReference([System.Windows.Controls.DataGrid]::($p[0] + 'Property'), $p[1])
    }
    $sel = New-Object System.Windows.Controls.DataGridCheckBoxColumn
    $sel.Header  = 'SEL.'
    $sel.Width   = 46
    $sel.Binding = New-Object System.Windows.Data.Binding 'Selected'
    $sel.Binding.Mode = [System.Windows.Data.BindingMode]::TwoWay
    $sel.Binding.UpdateSourceTrigger = [System.Windows.Data.UpdateSourceTrigger]::PropertyChanged
    $sel.ElementStyle        = $window.FindResource('ThemedCheckBox')
    $sel.EditingElementStyle = $window.FindResource('ThemedCheckBox')
    [void]$g.Columns.Add($sel)
    # Larghezze FISSE: il popup prende la misura del contenuto (SizeToContent), e li' una colonna
    # a '*' non ha spazio da dividere e collassa a zero. 46+200+80+80 sta nella colonna del testo del popup (520 meno icona e margini).
    foreach ($c in @(@('ID', 'Id', '200'), @('SOURCE', 'Source', '80'), @('VERSION', 'Version', '80'))) {
        $col = New-Object System.Windows.Controls.DataGridTextColumn
        $col.Header     = $c[0]
        $col.Binding    = New-Object System.Windows.Data.Binding $c[1]
        $col.IsReadOnly = $true
        $col.Width      = [System.Windows.Controls.DataGridLength]$c[2]
        [void]$g.Columns.Add($col)
    }
    $g.ItemsSource = $Rows
    $g
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
    $Progress.IsIndeterminate    = $true
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
            $Progress.IsIndeterminate    = $false
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
                foreach ($l in (Get-WinGetOutputTail $r.Output 2)) { Write-Log "   $l" }
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

    $pkgs  = Get-ImportPackages $file
    $count = if ($pkgs) { @($pkgs.Rows).Count } else { 0 }
    # 0 come $null: un export senza pacchetti non ha niente da installare, e winget lo
    # rifiuterebbe dopo la conferma.
    if (-not $count) {
        Show-AppDialog -Text "This file is not a winget package list, or it lists no packages.`n`n$file" `
            -Title 'Cannot import' -Button ([System.Windows.MessageBoxButton]::OK) `
            -Image ([System.Windows.MessageBoxImage]::Error) | Out-Null
        return
    }

    # CONFERMA con ANTEPRIMA: l'import installa software senza altre domande. La griglia mostra
    # cosa c'e' nel file, tutto spuntato; si toglie la spunta a cio' che non si vuole. Il
    # default resta No.
    $rows = New-Object System.Collections.ObjectModel.ObservableCollection[object]
    foreach ($r in $pkgs.Rows) { $rows.Add($r) }
    $storedNote = if ($pkgs.Stored -gt 0) {
        "`n`n$($pkgs.Stored) package$(if ($pkgs.Stored -ne 1) { 's carry' } else { ' carries' }) installer arguments saved at export; winget applies them again."
    } else { '' }
    $answer = Show-AppDialog -Text ("Install the ticked packages from this list?`n$file`n`n" +
        "Untick what you do not want. Packages already installed are skipped or upgraded; packages " +
        "no longer available in any source are ignored rather than failing the whole import." + $storedNote) `
        -Title 'Confirm import' `
        -Button ([System.Windows.MessageBoxButton]::YesNo) `
        -Image ([System.Windows.MessageBoxImage]::Warning) `
        -Default ([System.Windows.MessageBoxResult]::No) `
        -Content (New-ImportPreviewGrid $rows)
    if ($answer -ne [System.Windows.MessageBoxResult]::Yes) {
        Write-Log "Import cancelled."
        return
    }
    $keep = @(for ($i = 0; $i -lt $rows.Count; $i++) { if ($rows[$i].Selected) { $i } })
    if ($keep.Count -eq 0) {
        Write-Log "Import cancelled: no package was ticked."
        return
    }
    # Tutto spuntato: si importa il file com'e'. Altrimenti un file ridotto in %TEMP%, col prefisso
    # wgt_ che Clear-WinGetTempFiles spazza al prossimo avvio; UTF-8 senza BOM, come lo scrive winget.
    if ($keep.Count -lt $rows.Count) {
        $sub = [IO.Path]::Combine([IO.Path]::GetTempPath(), "wgt_import_$([Guid]::NewGuid().ToString('N')).json")
        [IO.File]::WriteAllText($sub, (New-ImportSubset $pkgs.Json $keep), (New-Object Text.UTF8Encoding $false))
        Write-Log "Importing $($keep.Count) of the $count packages in $file."
        $file = $sub
    }
    Invoke-PackageImport $file $keep.Count
}

function Invoke-PackageImport([string]$file, [int]$count) {
    if (Test-WinGetBusy) { return }
    Set-AppBusy $true
    $InstalledSpinner.Visibility = [System.Windows.Visibility]::Visible
    $Progress.IsIndeterminate    = $true
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
            $Progress.IsIndeterminate    = $false
            $r = @($result)[0]
            switch ($r.Status) {
                'ok'      { Write-Log "Import done ($($r.Seconds)s)." }
                'warning' { Write-Log "Import finished with warnings (exit $($r.Code)): a reboot may be required." }
                default {
                    Write-Log "Import FAILED (exit $($r.Code))."
                    foreach ($l in (Get-WinGetOutputTail $r.Output 3)) { Write-Log "   $l" }
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
