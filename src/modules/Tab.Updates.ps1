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

# L'elenco rispecchia una fotografia della macchina scattata da Load-Upgrades. Appena qualcosa
# la altera — un aggiornamento, un'installazione, una disinstallazione, un import — le versioni
# a schermo non valgono piu', e ripremere Update rilancia winget su pacchetti gia' aggiornati:
# quelli escono con codice non-zero e si dipingono di ROSSO su righe che erano andate bene.
# Quindi il pulsante si blocca finche' non si rilegge.
# PERCHE' NON UNA RICARICA AUTOMATICA: cancellerebbe la colonna Result appena scritta, che e'
# il resoconto di com'e' andata.
# I PIN non entrano qui: bloccano gli aggiornamenti, non cambiano le versioni installate.
$script:listStale = $false

function Set-UpdatesStale {
    $script:listStale = $true
    Refresh-SelectionState
}

# Ricalcola stato pulsanti/etichette in base a elenco e selezione (req 2/3/4).
function Refresh-SelectionState {
    $total = $items.Count
    $sel   = @($items | Where-Object { $_.Selected }).Count

    # req3: "Seleziona tutto" attivo solo se c'e' almeno un elemento (e non occupato)
    $BtnToggleAll.IsEnabled = (-not $script:isBusy) -and ($total -gt 0)
    # req4: "Aggiorna" attivo solo se almeno uno selezionato. Ma mentre gira LA NOSTRA coda il
    # pulsante e' Cancel e deve restare premibile: Set-PinFlags richiama questa funzione a
    # stato ancora occupato, e senza la guardia spegneva il Cancel appena letti i pin.
    if ($script:queueVerb -ne 'Update') {
        $BtnUpdate.IsEnabled = (-not $script:isBusy) -and ($sel -gt 0) -and (-not $script:listStale)
    }

    # Allinea l'etichetta del toggle allo stato reale della selezione
    $script:allSelected   = ($total -gt 0 -and $sel -eq $total)
    $BtnToggleAll.Content = if ($script:allSelected) { "Deselect all" } else { "Select all" }

    # Due contatori: disponibili (top) e selezionati (action bar)
    $TxtAvailable.Text = if ($total -eq 0) { "" } elseif ($total -eq 1) { "1 update available" } else { "$total updates available" }
    # A lista vecchia il contatore dei selezionati cede il posto al motivo per cui Update e'
    # spento: un pulsante grigio senza spiegazione sembra un guasto.
    $TxtSelected.Text  = if ($script:listStale) { "list out of date - press Check" }
                         elseif ($sel -gt 0)    { "$sel selected" }
                         else                   { "" }
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
    # Pin e Unpin spenti durante un'operazione: winget e' occupato, e una voce accesa che
    # risponde "riprova fra un attimo" e' un rifiuto, non un blocco.
    $MenuPinUpdates.IsEnabled   = -not $busy
    $MenuUnpinUpdates.IsEnabled = -not $busy
    # Il pulsante Update diventa Cancel SOLO se la coda in corso e' la nostra: un export o
    # un'installazione dall'altra scheda alzano lo stesso stato occupato, e offrire di
    # annullarli da qui sarebbe una bugia.
    # Etichetta e tooltip si assegnano SEMPRE, non solo in un ramo: cosi' l'aspetto del
    # pulsante e' una funzione di (occupato, quale coda) e non dipende da come ci si e'
    # arrivati. Assegnandolo solo nel ramo a riposo restava "Cancel" a coda altrui avviata.
    $ourQueue = $busy -and ($script:queueVerb -eq 'Update')
    $BtnUpdate.Content = if ($ourQueue) { 'Cancel' } else { 'Update' }
    $BtnUpdate.ToolTip = if ($ourQueue) { 'Finish the package in progress, then stop without starting the others' } else { $null }

    if ($busy) {
        # Durante un'operazione la selezione non si tocca.
        $BtnToggleAll.IsEnabled = $false
        $BtnUpdate.IsEnabled    = $ourQueue
    }
    else {
        # A riposo lo stato dipende da elenco e selezione.
        Refresh-SelectionState
    }
}

# Carica/ricarica l'elenco upgrade in modo ASINCRONO (req 1): la scansione winget
# gira in un runspace separato cosi' l'overlay di caricamento resta animato.
function Load-Upgrades {
    # Non si scansiona sopra un altro winget: la scheda Install non alza lo stato occupato
    # mentre cerca, quindi il solo isBusy non basterebbe.
    if (Test-WinGetBusy) { return }
    # La lettura che si sta per fare E' la nuova fotografia: da qui il pulsante torna buono.
    $script:listStale = $false
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

    # Get-WinGetTable serve perche' gli altri due la chiamano: nel runspace vanno ricreate
    # tutte, altrimenti la scansione muore con "termine non riconosciuto".
    # I pin si leggono nello STESSO job, non in uno successivo: due processi winget
    # insieme si contendono lo store e il comando esce in errore.
    # [void]: Start-BackgroundJob torna il job, che altrimenti finirebbe sulla pipeline.
    [void](Start-BackgroundJob -Functions 'Get-WinGetTable', 'Get-WinGetUpgrades', 'Get-WinGetPins' `
        -Vars @{ incUnknown = [bool]$ChkUnknown.IsChecked } `
        -Script {
            [PSCustomObject]@{
                Rows = @(Get-WinGetUpgrades $incUnknown)
                Pins = @(Get-WinGetPins)
            }
        } `
        -OnDone {
            param($result)
            $TopSpinner.Visibility = [System.Windows.Visibility]::Collapsed
            $r = @($result)[0]
            if ($r) {
                $self = $false
                foreach ($u in $r.Rows) {
                    if (-not $u) { continue }
                    # L'app non si aggiorna da questa lista: winget non puo' sovrascrivere
                    # un eseguibile in esecuzione. Se ne occupa il pulsante nelle
                    # impostazioni, che si rinomina e riavvia.
                    if (Test-IsSelfPackage $u) { $self = $true; continue }
                    $items.Add($u)
                }
                if ($self) { Write-Log "An update for WinGet Studio itself is available: use the gear button." }
            }

            if ($items.Count -eq 0) {
                $TxtEmpty.Visibility = [System.Windows.Visibility]::Visible
                $Grid.Visibility     = [System.Windows.Visibility]::Collapsed
                Write-Log "No updates available."
            }
            else {
                $Grid.Visibility = [System.Windows.Visibility]::Visible
                Write-Log "Found $($items.Count) updates."
            }
            if ($r) { Set-PinFlags @($r.Pins) }
            Set-AppBusy $false
        })
}

# Aggiorna i pacchetti spuntati, uno per volta, per ID.
function Start-UpdateSelected {
    # I pinnati si escludono QUI e non solo disabilitando la spunta: una riga puo' essere
    # stata spuntata prima che il pin arrivasse, e "Select all" lavora sugli oggetti.
    $pinned = @($items | Where-Object { $_.Selected -and $_.Pinned })
    if ($pinned.Count -gt 0) {
        foreach ($p in $pinned) { $p.Selected = $false }
        Write-Log "Skipping $($pinned.Count) pinned package$(if ($pinned.Count -ne 1) { 's' }): remove the pin to update $(if ($pinned.Count -ne 1) { 'them' } else { 'it' })."
        Refresh-SelectionState
    }

    $selected = @($items | Where-Object { $_.Selected })
    if ($selected.Count -eq 0) {
        [System.Windows.MessageBox]::Show(
            "No items selected.", "WinGet Studio",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Information) | Out-Null
        return
    }

    # Lo stato occupato lo prende Start-WinGetQueue, che e' anche il punto in cui si controlla
    # che non ci sia gia' un winget in corso.
    Start-WinGetQueue -Rows $selected -Verb 'Update' -ArgsBuilder {
        param($r)
        # Aggiornamento silenzioso, match esatto sull'ID.
        # --disable-interactivity: senza console (exe -noConsole) un prompt di winget
        # resterebbe in attesa di input per sempre.
        "upgrade --id `"$($r.Id)`" --include-unknown -e --silent --disable-interactivity --accept-source-agreements --accept-package-agreements"
    } -OnDone {
        Set-AppBusy $false
        # L'elenco NON si ricarica da solo: cancellerebbe la colonna Result appena scritta,
        # che e' il resoconto di com'e' andata. Ma le versioni mostrate ora sono vecchie,
        # quindi Update si blocca fino al Check.
        Set-UpdatesStale
        Write-Log "The versions in this list are stale now: press Check to rescan."
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
        # I pinnati restano fuori: non sono aggiornabili, spuntarli sarebbe una promessa
        # che la coda non puo' mantenere.
        foreach ($it in $items) { if (-not $it.Pinned) { $it.Selected = $newState } }
        Refresh-SelectionState
    })

    # Lo stesso pulsante fa due cose: Update a riposo, Cancel mentre la nostra coda gira. Due
    # pulsanti separati avrebbero significato uno sempre spento, a occupare spazio per dire
    # niente.
    $BtnUpdate.Add_Click({
        if ($script:queueVerb -eq 'Update') {
            Request-QueueCancel
            $BtnUpdate.Content   = 'Cancelling...'
            $BtnUpdate.IsEnabled = $false
            Write-Log "Cancelling: the package in progress will finish, then the queue stops."
            return
        }
        Start-UpdateSelected
    })

    # Pin/Unpin dal menu contestuale, sulle righe EVIDENZIATE (non su quelle spuntate:
    # una riga pinnata ha la spunta disabilitata e non potrebbe piu' essere sbloccata).
    $MenuPinUpdates.Add_Click({   Set-PackagePin @($Grid.SelectedItems) $true })
    $MenuUnpinUpdates.Add_Click({ Set-PackagePin @($Grid.SelectedItems) $false })

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


