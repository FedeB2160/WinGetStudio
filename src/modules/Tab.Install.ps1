<#
    Tab.Install.ps1 — scheda Install: ricerca nel catalogo con suggerimenti mentre si
    digita, e installazione dei pacchetti scelti.

    Initialize-InstallTab va chiamata DOPO il FindName: aggancia i controlli, che
    prima non esistono.

    Caricato da src\main.ps1: dot-source come .ps1, concatenato nell'exe al posto
    del marcatore ###MODULES###.
#>

# Risultati della ricerca corrente
$searchItems = New-Object System.Collections.ObjectModel.ObservableCollection[object]

# Auto | User | Machine — vedi Update-ScopeButton per cosa significano
$script:installScope = 'Auto'
# Ricerche lanciate e non ancora rientrate: lo spinner si spegne solo quando sono zero,
# altrimenti un risultato vecchio che arriva tardi lo spegnerebbe mentre un altro gira.
$script:searchInFlight = 0
$script:scopeWarned    = $false

function Refresh-InstallState {
    $total = $searchItems.Count
    $sel   = @($searchItems | Where-Object { $_.Selected }).Count

    $BtnInstall.IsEnabled = (-not $script:isBusy) -and ($sel -gt 0)
    $TxtSearchInfo.Text =
        if ($sel -gt 0)     { "$sel selected" }
        elseif ($total -gt 0) { "$total result$(if ($total -ne 1) { 's' }) - tick the ones to install, or double click a row" }
        else                { "" }
}

# Stato occupato per i soli controlli di questa scheda: la chiama Set-AppBusy.
function Set-InstallBusy([bool]$busy) {
    $TxtSearch.IsEnabled = -not $busy
    $BtnSearch.IsEnabled = -not $busy
    $ChkStore.IsEnabled  = -not $busy
    $BtnScope.IsEnabled  = -not $busy
    # Come nella scheda Updates: IsReadOnly e non IsEnabled, cosi' l'elenco resta
    # scorrevole mentre l'installazione va avanti.
    if ($busy) { [void]$GridSearch.CommitEdit() }
    $GridSearch.IsReadOnly = $busy
    if ($busy) { $BtnInstall.IsEnabled = $false } else { Refresh-InstallState }
}

function Update-ScopeButton {
    $BtnScope.Content = "Scope: $($script:installScope)"
    $BtnScope.ToolTip = switch ($script:installScope) {
        'User'    { 'Install for the current user only (--scope user)' }
        'Machine' { 'Install for all users (--scope machine). Packages that only ship a per-user installer will fail' }
        default   { 'Let winget decide (no --scope flag), same as the Updates tab does' }
    }
}

# Mostra il messaggio al posto della griglia, o la griglia al posto del messaggio.
function Show-SearchMessage([string]$text) {
    $searchItems.Clear()
    $TxtSearchEmpty.Text       = $text
    $TxtSearchEmpty.Visibility = [System.Windows.Visibility]::Visible
    $GridSearch.Visibility     = [System.Windows.Visibility]::Collapsed
    Refresh-InstallState
}

# Cerca nel catalogo. $IncludeStore vale solo per le ricerche esplicite (Invio o
# pulsante): il Microsoft Store va in rete e non regge il ritmo della digitazione.
function Start-Search([bool]$IncludeStore = $false) {
    $q = $TxtSearch.Text.Trim()
    if ($q.Length -lt 3) {
        Show-SearchMessage 'Type at least 3 characters.'
        return
    }
    # Un'altra operazione winget e' in corso: non se ne lanciano due in parallelo.
    if ($script:isBusy) { return }

    $script:searchInFlight++
    $SearchSpinner.Visibility = [System.Windows.Visibility]::Visible

    # La query viaggia col risultato: quando rientra si confronta con quello che c'e'
    # ORA nel campo e, se l'utente ha continuato a digitare, il risultato vecchio si
    # butta. Senza questo, due ricerche che rientrano fuori ordine lascerebbero in
    # griglia i risultati della query precedente.
    [void](Start-BackgroundJob -Functions 'Get-WinGetTable', 'Get-WinGetSearch' `
        -Vars @{ q = $q; store = $IncludeStore } `
        -Script {
            [PSCustomObject]@{ Query = $q; Rows = @(Get-WinGetSearch $q $store) }
        } `
        -OnDone {
            param($result)
            $script:searchInFlight--
            if ($script:searchInFlight -le 0) {
                $script:searchInFlight = 0
                $SearchSpinner.Visibility = [System.Windows.Visibility]::Collapsed
            }

            $r = @($result)[0]
            if (-not $r) { return }                                  # job fallito: Start-BackgroundJob ha gia' loggato
            if ($r.Query -ne $TxtSearch.Text.Trim()) { return }      # risultato superato
            # Nel frattempo e' partita un'installazione: sostituire le righe ora farebbe
            # sparire dalla griglia proprio i pacchetti in corso, con il loro esito.
            if ($script:isBusy) { return }

            $searchItems.Clear()
            foreach ($p in $r.Rows) { if ($p) { $searchItems.Add($p) } }

            if ($searchItems.Count -eq 0) {
                Show-SearchMessage "No package matches '$($r.Query)'."
            }
            else {
                $TxtSearchEmpty.Visibility = [System.Windows.Visibility]::Collapsed
                $GridSearch.Visibility     = [System.Windows.Visibility]::Visible
                Refresh-InstallState
            }
        })
}

# Il tool gira sempre elevato. Se l'account elevato non e' quello della sessione
# interattiva, un pacchetto per-utente finisce nel profilo SBAGLIATO senza dire nulla.
function Test-ElevatedUserMismatch {
    try {
        $console = (Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).UserName
        $me = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        return ($console -and $me -and $console -ne $me)
    }
    catch { return $false }   # non si riesce a stabilirlo: meglio tacere che allarmare
}

function Install-Rows([object[]]$Rows) {
    if (-not $Rows -or $Rows.Count -eq 0) { return }

    # Avviso una volta per sessione, e solo se lo scope scelto puo' portare al problema.
    if (-not $script:scopeWarned -and $script:installScope -ne 'Machine' -and (Test-ElevatedUserMismatch)) {
        $script:scopeWarned = $true
        Write-Log "WARNING: running elevated as $([Security.Principal.WindowsIdentity]::GetCurrent().Name), not as the signed-in user."
        Write-Log "         Per-user packages will install into that profile. Use Scope: Machine to install for all users."
    }

    # Lo stato occupato lo prende Start-WinGetQueue, che e' anche il punto in cui si controlla
    # che non ci sia gia' un winget in corso.
    # Lo scope si calcola QUI e viaggia come variabile del runspace: -ArgsBuilder gira
    # dentro il runspace e non vedrebbe $script:installScope.
    $scopeArg = switch ($script:installScope) {
        'User'    { ' --scope user' }
        'Machine' { ' --scope machine' }
        default   { '' }
    }
    Start-WinGetQueue -Rows $Rows -Verb 'Install' -Vars @{ scopeArg = $scopeArg } -ArgsBuilder {
        param($r)
        # Match esatto sull'ID. --disable-interactivity e' obbligatorio: senza console
        # (exe -noConsole) un prompt di winget resterebbe in attesa per sempre.
        "install --id `"$($r.Id)`" -e --silent --disable-interactivity --accept-source-agreements --accept-package-agreements$scopeArg"
    } -OnDone {
        Set-AppBusy $false
        # L'elenco della scheda Updates e' stato calcolato prima di queste installazioni.
        Set-UpdatesStale
        Write-Log "The Updates list may be out of date now: press Check to rescan."
    }
}

function Start-InstallSelected {
    $sel = @($searchItems | Where-Object { $_.Selected })
    if ($sel.Count -eq 0) {
        [System.Windows.MessageBox]::Show(
            "No packages selected.", "WinGet Studio",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Information) | Out-Null
        return
    }
    Install-Rows $sel
}

function Initialize-InstallTab {
    $GridSearch.ItemsSource = $searchItems
    $GridSearch.Visibility  = [System.Windows.Visibility]::Collapsed
    Register-BusyHandler { param($busy) Set-InstallBusy $busy }

    # Le due scelte della scheda si rileggono dalle preferenze: prima si perdevano a ogni
    # avvio. Lo Scope resta accanto al pulsante Install che lo usa, non in Settings.
    $ChkStore.IsChecked = [bool][int](Get-Pref 'IncludeStore' 0)
    $ChkStore.Add_Click({ Set-Pref 'IncludeStore' ([int][bool]$ChkStore.IsChecked) })
    $saved = [string](Get-Pref 'InstallScope' 'Auto')
    if ($saved -in @('Auto', 'User', 'Machine')) { $script:installScope = $saved }
    Update-ScopeButton

    # Suggerimenti mentre si digita: il timer riparte a ogni tasto e la ricerca scatta
    # solo dopo una pausa, altrimenti si lancerebbe un processo winget per lettera.
    # 350ms: una ricerca sull'indice locale ne impiega ~450, quindi i risultati arrivano
    # sotto il secondo dall'ultimo tasto.
    $script:searchTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:searchTimer.Interval = [TimeSpan]::FromMilliseconds(350)
    $script:searchTimer.Add_Tick({
        $script:searchTimer.Stop()
        Start-Search $false          # il typeahead non interroga mai il Microsoft Store
    })

    $TxtSearch.Add_TextChanged({
        $script:searchTimer.Stop()
        if ($TxtSearch.Text.Trim().Length -ge 3) { $script:searchTimer.Start() }
        else { Show-SearchMessage 'Type a package name to search the winget catalog.' }
    })

    # Invio: ricerca subito, includendo il Microsoft Store se la spunta e' attiva.
    $TxtSearch.Add_KeyDown({
        param($s, $e)
        if ($e.Key -eq [System.Windows.Input.Key]::Return) {
            $script:searchTimer.Stop()
            Start-Search ([bool]$ChkStore.IsChecked)
            $e.Handled = $true
        }
    })
    $BtnSearch.Add_Click({
        $script:searchTimer.Stop()
        Start-Search ([bool]$ChkStore.IsChecked)
    })

    $BtnScope.Add_Click({
        $script:installScope = switch ($script:installScope) {
            'Auto'    { 'User' }
            'User'    { 'Machine' }
            default   { 'Auto' }
        }
        Update-ScopeButton
        Set-Pref 'InstallScope' $script:installScope
    })

    $BtnInstall.Add_Click({ Start-InstallSelected })

    # Doppio clic su una riga: installa quel pacchetto, senza passare dalle spunte.
    $GridSearch.Add_MouseDoubleClick({
        if ($script:isBusy) { return }
        $row = $GridSearch.SelectedItem
        if ($row) { Install-Rows @($row) }
    })

    Register-GridRefresh $GridSearch 'Refresh-InstallState'
}

