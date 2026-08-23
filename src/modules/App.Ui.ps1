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

# $script:queueVerb dice QUALE coda sta girando ('Update', 'Install', 'Uninstall', 'Pin')
# oppure $null. Lo stato occupato e' globale, quindi senza questo una scheda non puo'
# distinguere la propria operazione da quella di un'altra — ed e' l'unico modo per offrire
# "Cancel" solo a chi l'ha avviata. Lo scrive Start-WinGetQueue.
# Si azzera PRIMA di chiamare gli handler, cosi' ognuno vede lo stato finale.
function Set-AppBusy([bool]$busy) {
    $script:isBusy = $busy
    if (-not $busy) { $script:queueVerb = $null }
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

# ------------------------------------------------------------------
# RICALCOLO DIFFERITO DEI CONTATORI DI UNA GRIGLIA
# ------------------------------------------------------------------
# Aggancia a una griglia il ricalcolo dei suoi contatori. Le tre schede avevano lo stesso
# blocco copiato con dentro il solo nome della funzione diverso: il prossimo inciampo
# sull'overload di BeginInvoke andrebbe corretto in tre punti.
# PERCHE' DIFFERITO: il binding della spunta e' UpdateSourceTrigger=PropertyChanged, ma il
# valore arriva sull'oggetto solo DOPO che il ToggleButton ha commutato, quindi il ricalcolo
# va rimandato a priorita' Background.
# PERCHE' PreviewMouseLeftButtonUp: evento tunneling, raggiunge la griglia prima che la
# CheckBox marchi l'evento come gestito -> contatori ed etichette si aggiornano al clic e non
# alla perdita di fuoco della cella.
# NB: BeginInvoke([action]{...}, 'Background') NON esiste come overload -> PowerShell risolve
# su BeginInvoke(Delegate, params Object[]) e passa 'Background' COME ARGOMENTO a un delegate
# senza parametri => TargetParameterCountException, che risale da ShowDialog(). Va usata la
# forma con la priorita' PER PRIMA e l'enum tipizzato.
# Il nome della funzione si INTERPOLA nel testo e l'handler nasce da [scriptblock]::Create: i
# parametri di questa funzione non esistono piu' quando l'evento scatta, e .GetNewClosure()
# non e' la via d'uscita — la closure crea un module scope dove $script: non e' piu' lo scope
# di questo script (vedi App.Jobs.ps1).
# $Target e non $Grid: un parametro chiamato $Grid coprirebbe il controllo omonimo.
function Register-GridRefresh($Target, [string]$RefreshFunction) {
    $handler = [scriptblock]::Create(
        "`$window.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [action]{ $RefreshFunction }) | Out-Null")
    $Target.Add_CellEditEnding($handler)
    $Target.Add_PreviewMouseLeftButtonUp($handler)
}

