<#
    Tab.Updates.ps1 — scheda Updates: elenco degli upgrade disponibili, selezione a
    checkbox, avvio della coda di aggiornamento.

    Initialize-UpdatesTab va chiamata DOPO il FindName: aggancia i controlli, che
    prima non esistono.

    Caricato da src\main.ps1: dot-source come .ps1, concatenato nell'exe al posto
    del marcatore ###MODULES###.
#>

# Collezione dati (ObservableCollection per binding checkbox bidirezionale)
$items = New-Object System.Collections.ObjectModel.ObservableCollection[object]

$script:allSelected = $false

# Ricalcola stato pulsanti/etichette in base a elenco e selezione (req 2/3/4).
function Refresh-SelectionState {
    $total = $items.Count
    $sel   = @($items | Where-Object { $_.Selected }).Count

    # req3: "Seleziona tutto" attivo solo se c'e' almeno un elemento (e non occupato)
    $BtnToggleAll.IsEnabled = (-not $script:isBusy) -and ($total -gt 0)
    # req4: "Aggiorna" attivo solo se almeno uno selezionato
    $BtnUpdate.IsEnabled    = (-not $script:isBusy) -and ($sel -gt 0)

    # Allinea l'etichetta del toggle allo stato reale della selezione
    $script:allSelected   = ($total -gt 0 -and $sel -eq $total)
    $BtnToggleAll.Content = if ($script:allSelected) { "Deselect all" } else { "Select all" }

    # Due contatori: disponibili (top) e selezionati (action bar)
    $TxtAvailable.Text = if ($total -eq 0) { "" } elseif ($total -eq 1) { "1 update available" } else { "$total updates available" }
    $TxtSelected.Text  = if ($sel -gt 0) { "$sel selected" } else { "" }
}

# Applica lo stato occupato ai soli controlli di QUESTA scheda. La chiama Set-AppBusy
# (App.Ui.ps1) per tutte le schede insieme: un update in corso deve spegnere anche i
# comandi della scheda Install, perche' winget in parallelo non e' affidabile.
function Set-UpdatesBusy([bool]$busy) {
    $BtnRefresh.IsEnabled = -not $busy
    $ChkUnknown.IsEnabled = -not $busy
    # Sola lettura, NON IsEnabled=$false: un DataGrid disabilitato non risponde piu' a
    # rotellina, scrollbar e tastiera -> durante l'update l'elenco sembrava congelato.
    # IsReadOnly blocca solo l'edit delle checkbox, che e' l'unica cosa da impedire.
    if ($busy) { [void]$Grid.CommitEdit() }
    $Grid.IsReadOnly = $busy
    if ($busy) {
        # Durante un'operazione i pulsanti selezione/aggiorna sono sempre spenti
        $BtnToggleAll.IsEnabled = $false
        $BtnUpdate.IsEnabled    = $false
    }
    else {
        # A riposo lo stato dipende da elenco e selezione
        Refresh-SelectionState
    }
}

# Carica/ricarica l'elenco upgrade in modo ASINCRONO (req 1): la scansione winget
# gira in un runspace separato cosi' l'overlay di caricamento resta animato.
function Load-Upgrades {
    Set-AppBusy $true
    Write-Log "Searching for updates..."
    $items.Clear()
    $TxtEmpty.Visibility     = [System.Windows.Visibility]::Collapsed
    $Grid.Visibility         = [System.Windows.Visibility]::Collapsed
    $TopSpinner.Visibility   = [System.Windows.Visibility]::Visible
    # Azzera la barra: appartiene alla coda di aggiornamento precedente, non al nuovo elenco
    $Progress.Value   = 0
    $Progress.Maximum = 100
    Refresh-SelectionState

    # Get-WinGetTable serve perche' Get-WinGetUpgrades la chiama: nel runspace vanno
    # ricreate entrambe, altrimenti la scansione muore con "termine non riconosciuto".
    # [void]: Start-BackgroundJob torna il job, che altrimenti finirebbe sulla pipeline.
    [void](Start-BackgroundJob -Functions 'Get-WinGetTable', 'Get-WinGetUpgrades' `
        -Vars @{ incUnknown = [bool]$ChkUnknown.IsChecked } `
        -Script {
            Get-WinGetUpgrades $incUnknown   # niente virgola: gli elementi devono scorrere singoli sulla pipeline
        } `
        -OnDone {
            param($result)
            $TopSpinner.Visibility = [System.Windows.Visibility]::Collapsed
            foreach ($u in $result) { if ($u) { $items.Add($u) } }

            if ($items.Count -eq 0) {
                $TxtEmpty.Visibility = [System.Windows.Visibility]::Visible
                $Grid.Visibility     = [System.Windows.Visibility]::Collapsed
                Write-Log "No updates available."
            }
            else {
                $Grid.Visibility = [System.Windows.Visibility]::Visible
                Write-Log "Found $($items.Count) updates."
            }
            Set-AppBusy $false
        })
}

# Aggiorna i pacchetti spuntati, uno per volta, per ID.
function Start-UpdateSelected {
    $selected = @($items | Where-Object { $_.Selected })
    if ($selected.Count -eq 0) {
        [System.Windows.MessageBox]::Show(
            "No items selected.", "WinGet Update Tool",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Information) | Out-Null
        return
    }

    Set-AppBusy $true
    Start-WinGetQueue -Rows $selected -Verb 'Update' -ArgsBuilder {
        param($r)
        # Aggiornamento silenzioso, match esatto sull'ID.
        # --disable-interactivity: senza console (exe -noConsole) un prompt di winget
        # resterebbe in attesa di input per sempre.
        "upgrade --id `"$($r.Id)`" --include-unknown -e --silent --disable-interactivity --accept-source-agreements --accept-package-agreements"
    } -OnDone {
        Set-AppBusy $false
    }
}

function Initialize-UpdatesTab {
    $Grid.ItemsSource = $items
    Register-BusyHandler { param($busy) Set-UpdatesBusy $busy }

    $BtnRefresh.Add_Click({ Load-Upgrades })

    $BtnToggleAll.Add_Click({
        # Riallinea $script:allSelected allo stato REALE: il refresh differito di una spunta
        # manuale gira a priorita' Background, quindi dopo questo Click. Senza il ricalcolo
        # il pulsante agisce sulla cache vecchia (es. deseleziona con 4/5 selezionati).
        Refresh-SelectionState
        $newState = -not $script:allSelected
        # Chiude un'eventuale transazione di edit aperta, altrimenti il DataGrid al termine
        # dell'edit riscrive sulla riga il valore che aveva prima del clic sul pulsante.
        [void]$Grid.CommitEdit()
        foreach ($it in $items) { $it.Selected = $newState }
        Refresh-SelectionState
    })

    $BtnUpdate.Add_Click({ Start-UpdateSelected })

    # Aggiorna stato pulsanti/contatore quando l'utente spunta/despunta manualmente.
    # Il binding e' UpdateSourceTrigger=PropertyChanged, ma il valore arriva sull'oggetto solo
    # DOPO che il ToggleButton ha commutato: il ricalcolo va rimandato a priorita' Background.
    # NB: BeginInvoke([action]{...}, 'Background') NON esiste come overload -> PowerShell
    # risolve su BeginInvoke(Delegate, params Object[]) e passa 'Background' COME ARGOMENTO a
    # un delegate senza parametri => TargetParameterCountException, che risale da ShowDialog().
    # Va usata la forma con la priorita' PER PRIMA e l'enum tipizzato.
    $queueSelectionRefresh = {
        $window.Dispatcher.BeginInvoke(
            [System.Windows.Threading.DispatcherPriority]::Background,
            [action]{ Refresh-SelectionState }) | Out-Null
    }
    $Grid.Add_CellEditEnding($queueSelectionRefresh)
    # PreviewMouseLeftButtonUp: evento tunneling, raggiunge la griglia prima che il CheckBox
    # marchi l'evento come gestito -> contatore e label si aggiornano al click, non alla
    # perdita di focus della cella.
    $Grid.Add_PreviewMouseLeftButtonUp($queueSelectionRefresh)
}

