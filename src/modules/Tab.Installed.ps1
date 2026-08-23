<#
    Tab.Installed.ps1 — scheda Installed: inventario dei pacchetti presenti sulla
    macchina e disinstallazione di quelli scelti.

    Initialize-InstalledTab va chiamata DOPO il FindName: aggancia i controlli, che
    prima non esistono.

    Caricato da src\main.ps1: dot-source come .ps1, concatenato nell'exe al posto
    del marcatore ###MODULES###.
#>

$installedItems = New-Object System.Collections.ObjectModel.ObservableCollection[object]

# L'elenco costa un paio di secondi di winget: si carica alla prima apertura della
# scheda, non all'avvio del programma.
$script:installedLoaded = $false

# Vista filtrata della collezione: e' quella che il DataGrid mostra. Il filtro e' locale,
# non richiama winget. La si tiene in una variabile e NON la si restituisce da una
# funzione: una CollectionView e' enumerabile, e PowerShell restituirebbe i suoi elementi
# al posto dell'oggetto, lasciando senza la proprieta' Filter.
$script:installedView = $null

function Refresh-InstalledState {
    $total = $installedItems.Count
    $sel   = @($installedItems | Where-Object { $_.Selected }).Count
    $shown = @($script:installedView).Count

    $BtnUninstall.IsEnabled = (-not $script:isBusy) -and ($sel -gt 0)

    $TxtInstalledCount.Text =
        if ($total -eq 0)      { "" }
        elseif ($shown -ne $total) { "$shown of $total installed" }
        else                   { "$total installed" }

    # Un selezionato nascosto dal filtro verrebbe disinstallato senza essere a schermo:
    # va detto qui, non solo nella finestra di conferma.
    $hidden = @($installedItems | Where-Object { $_.Selected -and -not (Test-InstalledMatch $_) }).Count
    $TxtInstalledInfo.Text =
        if ($sel -eq 0)     { "" }
        elseif ($hidden -gt 0) { "$sel selected ($hidden hidden by the filter)" }
        else                { "$sel selected" }
}

# Stato occupato per i soli controlli di questa scheda: la chiama Set-AppBusy.
function Set-InstalledBusy([bool]$busy) {
    $BtnRefreshInstalled.IsEnabled = -not $busy
    $TxtFilter.IsEnabled           = -not $busy
    if ($busy) { [void]$GridInstalled.CommitEdit() }
    $GridInstalled.IsReadOnly = $busy
    if ($busy) { $BtnUninstall.IsEnabled = $false } else { Refresh-InstalledState }
}

# Una riga passa il filtro? Confronto su nome e ID, senza distinzione di maiuscole.
function Test-InstalledMatch($row) {
    $f = $TxtFilter.Text.Trim()
    if (-not $f) { return $true }
    return ($row.Name -like "*$f*") -or ($row.Id -like "*$f*")
}

function Load-Installed {
    # Non si scansiona sopra un altro winget. Test-WinGetBusy e non isBusy: una ricerca in
    # volo nella scheda Install non alza lo stato occupato, ed e' proprio entrando qui dal
    # typeahead che partivano due winget insieme.
    if (Test-WinGetBusy) { return }
    Set-AppBusy $true
    $script:installedLoaded = $true
    Write-Log "Listing installed packages..."
    $installedItems.Clear()
    $TxtInstalledEmpty.Visibility = [System.Windows.Visibility]::Collapsed
    $GridInstalled.Visibility     = [System.Windows.Visibility]::Collapsed
    $InstalledSpinner.Visibility  = [System.Windows.Visibility]::Visible
    Refresh-InstalledState

    # I pin si leggono nello STESSO job dell'inventario: due winget in parallelo si
    # contendono lo store e uno dei due esce in errore.
    [void](Start-BackgroundJob -Functions 'Get-WinGetTable', 'Get-WinGetInstalled', 'Get-WinGetPins' `
        -Script {
            [PSCustomObject]@{
                Rows = @(Get-WinGetInstalled)
                Pins = @(Get-WinGetPins)
            }
        } `
        -OnDone {
            param($result)
            $InstalledSpinner.Visibility = [System.Windows.Visibility]::Collapsed
            $r = @($result)[0]
            if ($r) { foreach ($p in $r.Rows) { if ($p) { $installedItems.Add($p) } } }

            if ($installedItems.Count -eq 0) {
                $TxtInstalledEmpty.Text       = "No installed package found."
                $TxtInstalledEmpty.Visibility = [System.Windows.Visibility]::Visible
                Write-Log "No installed package found."
            }
            else {
                $TxtInstalledEmpty.Visibility = [System.Windows.Visibility]::Collapsed
                $GridInstalled.Visibility     = [System.Windows.Visibility]::Visible
                Write-Log "Found $($installedItems.Count) installed packages."
            }
            if ($r) { Set-PinFlags @($r.Pins) }
            Set-AppBusy $false
        })
}

function Start-UninstallSelected {
    $sel = @($installedItems | Where-Object { $_.Selected })
    if ($sel.Count -eq 0) { return }

    # CONFERMA OBBLIGATORIA: la disinstallazione non si annulla. L'elenco riporta i nomi
    # REALI in coda, compresi quelli che il filtro sta nascondendo — altrimenti si
    # potrebbe rimuovere un pacchetto che non e' nemmeno a schermo.
    $shownNames = @($sel | Select-Object -First 12 | ForEach-Object { "  - $($_.Name)" })
    $more = if ($sel.Count -gt 12) { "`n  ... and $($sel.Count - 12) more" } else { '' }
    $hidden = @($sel | Where-Object { -not (Test-InstalledMatch $_) }).Count
    $hiddenNote = if ($hidden -gt 0) { "`n`n$hidden of them are currently hidden by the filter." } else { '' }

    $answer = [System.Windows.MessageBox]::Show(
        "Uninstall $($sel.Count) package$(if ($sel.Count -ne 1) { 's' })?`n`n" +
        ($shownNames -join "`n") + $more + $hiddenNote +
        "`n`nThis cannot be undone.",
        "Confirm uninstall",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Warning,
        # Default su No: un Invio distratto non deve disinstallare nulla.
        [System.Windows.MessageBoxResult]::No)
    if ($answer -ne [System.Windows.MessageBoxResult]::Yes) {
        Write-Log "Uninstall cancelled."
        return
    }

    # Lo stato occupato lo prende Start-WinGetQueue, che e' anche il punto in cui si controlla
    # che non ci sia gia' un winget in corso.
    Start-WinGetQueue -Rows $sel -Verb 'Uninstall' -ArgsBuilder {
        param($r)
        # Match esatto sull'ID: vale anche per i pacchetti non installati con winget, il
        # cui ID e' del tipo "ARP\Machine\X64\Nome Prodotto" e contiene spazi.
        # --disable-interactivity: senza console un prompt bloccherebbe per sempre.
        "uninstall --id `"$($r.Id)`" -e --silent --disable-interactivity --accept-source-agreements"
    } -OnDone {
        Set-AppBusy $false
        # L'elenco non viene ricaricato da solo: cancellerebbe la colonna Result appena
        # scritta, che e' il resoconto di cosa e' andato come.
        Write-Log "Uninstall finished: press Refresh to rebuild the list."
    }
}

function Initialize-InstalledTab {
    $GridInstalled.ItemsSource = $installedItems
    $GridInstalled.Visibility  = [System.Windows.Visibility]::Collapsed
    Register-BusyHandler { param($busy) Set-InstalledBusy $busy }

    # Filtro locale sulla vista: le righe escluse restano nella collezione (e quindi
    # eventualmente selezionate), non vengono buttate.
    $script:installedView = [System.Windows.Data.CollectionViewSource]::GetDefaultView($installedItems)
    $script:installedView.Filter = { param($row) Test-InstalledMatch $row }

    $TxtFilter.Add_TextChanged({
        $script:installedView.Refresh()
        Refresh-InstalledState
    })

    $BtnRefreshInstalled.Add_Click({ Load-Installed })
    $BtnUninstall.Add_Click({ Start-UninstallSelected })

    # Pin/Unpin sulle righe evidenziate, come nella scheda Updates.
    $MenuPinInstalled.Add_Click({   Set-PackagePin @($GridInstalled.SelectedItems) $true })
    $MenuUnpinInstalled.Add_Click({ Set-PackagePin @($GridInstalled.SelectedItems) $false })

    $queueInstalledRefresh = {
        $window.Dispatcher.BeginInvoke(
            [System.Windows.Threading.DispatcherPriority]::Background,
            [action]{ Refresh-InstalledState }) | Out-Null
    }
    $GridInstalled.Add_CellEditEnding($queueInstalledRefresh)
    $GridInstalled.Add_PreviewMouseLeftButtonUp($queueInstalledRefresh)

    # Primo ingresso nella scheda: carica l'elenco da solo, cosi' non si paga l'attesa
    # all'avvio del programma chi non usa questa scheda.
    $TabMain.Add_SelectionChanged({
        param($s, $e)
        # Il DataGrid dentro la scheda rilancia SelectionChanged (righe selezionate): si
        # reagisce solo all'evento del TabControl stesso.
        if ($e.OriginalSource -ne $TabMain) { return }
        if ($script:installedLoaded) { return }
        # Confronto con l'OGGETTO e non con l'header: una rinomina della linguetta non deve
        # spegnere in silenzio il caricamento automatico, e l'header del tab Settings non e'
        # nemmeno una stringa (glifo + parola).
        if ($TabMain.SelectedItem -eq $TabInstalled) { Load-Installed }
    })
}
