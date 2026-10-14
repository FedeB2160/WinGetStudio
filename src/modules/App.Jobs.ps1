<#
    App.Jobs.ps1 — lavoro in background: winget gira in un runspace separato, la UI
    resta reattiva.

    REGOLA: il codice che gira nel runspace NON puo' toccare i controlli direttamente.
    Ogni scrittura sulla UI passa da $window.Dispatcher.Invoke() (helper UI{} qui sotto).

    I runspace non condividono le funzioni del chiamante: si passa il CORPO della
    funzione e si ricrea la funzione dentro il runspace con Invoke-Expression. Funziona
    indipendentemente dal file in cui la funzione e' definita, quindi lo split in moduli
    non lo cambia.

    Caricato da src\main.ps1: dot-source come .ps1, concatenato nell'exe al posto
    del marcatore ###MODULES###.
#>

# Job attivi. Serve al cleanup alla chiusura della finestra: senza, un runspace o un
# timer vivo tiene in piedi il processo dopo che la finestra e' sparita. Una lista, non
# una coppia di variabili per operazione: le operazioni sono molte.
$script:jobs = New-Object System.Collections.ArrayList

# Annullamento COOPERATIVO della coda in corso. Una hashtable e non una variabile $script:
# perche' il runspace ha il proprio scope: una hashtable e' un tipo per RIFERIMENTO, quindi i
# due thread vedono lo stesso oggetto — lo stesso motivo per cui $rows funziona.
# NON si uccide il processo in corso: un installer interrotto a meta' lascia la macchina in
# uno stato che nessuno sa descrivere. Si finisce il pacchetto e non si parte col prossimo.
$script:queueCancel = $null

function Request-QueueCancel {
    if ($script:queueCancel) { $script:queueCancel.Requested = $true }
}

# Esegue $Script in un runspace STA e richiama $OnDone sul thread UI a lavoro finito,
# passandogli i risultati.
#   -Vars      variabili da rendere visibili dentro il runspace
#   -Functions nomi di funzioni di cui passare il corpo (i runspace non le ereditano)
#   -OnDone    scriptblock sul thread UI: param($result)
# Il completamento si scopre con un DispatcherTimer, non con un evento: il callback di
# BeginInvoke arriverebbe su un thread non-UI, dove toccare i controlli lancia.
function Start-BackgroundJob {
    param(
        [Parameter(Mandatory)][scriptblock]$Script,
        [hashtable]$Vars = @{},
        [string[]]$Functions = @(),
        [scriptblock]$OnDone
    )

    $fnBodies = @{}
    foreach ($n in $Functions) {
        $f = Get-Item "function:$n" -ErrorAction SilentlyContinue
        if (-not $f) { throw "Start-BackgroundJob: funzione inesistente '$n'" }
        $fnBodies[$n] = $f.ScriptBlock.ToString()
    }

    $rs = [RunspaceFactory]::CreateRunspace()
    $rs.ApartmentState = 'STA'
    $rs.ThreadOptions  = 'ReuseThread'
    $rs.Open()
    $rs.SessionStateProxy.SetVariable('__fnBodies', $fnBodies)
    # window e txtLog vanno in OGNI job: sono cio' che serve a UI{} e LogUI{} definite
    # nel prologo, che ogni job puo' voler usare per scrivere nel log mentre lavora.
    $rs.SessionStateProxy.SetVariable('window', $window)
    $rs.SessionStateProxy.SetVariable('txtLog', $TxtLog)
    foreach ($kv in $Vars.GetEnumerator()) { $rs.SessionStateProxy.SetVariable($kv.Key, $kv.Value) }

    $ps = [PowerShell]::Create()
    $ps.Runspace = $rs
    # Prologo + corpo come TESTO: uno scriptblock creato qui resterebbe legato a questo
    # runspace, e invocarlo dentro l'altro non lo eseguirebbe la'.
    $prologue = @'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }
foreach ($__kv in $__fnBodies.GetEnumerator()) {
    Invoke-Expression "function $($__kv.Key) { $($__kv.Value) }"
}
# Il codice del runspace NON puo' toccare i controlli: ogni scrittura sulla UI passa da
# qui. Definite per tutti i job, non copiate in ognuno che serve.
# [void]: questo overload di Invoke torna object, e senza il cast ogni UI{} e ogni LogUI
# scriveva un $null nell'output del job. Il job di installazione di winget tornava cosi'
# [$null, risultato] e dentro le sue funzioni i $null si mescolavano ai valori raccolti.
function UI([scriptblock]$action) {
    [void]$window.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::Background, [action]$action)
}
function LogUI([string]$m) {
    $ts = (Get-Date).ToString('HH:mm:ss')
    UI { $txtLog.AppendText("[$ts] $m`r`n"); $txtLog.ScrollToEnd() }
}
'@
    [void]$ps.AddScript($prologue + "`r`n" + $Script.ToString())

    $job = [PSCustomObject]@{
        Runspace   = $rs
        PowerShell = $ps
        Handle     = $ps.BeginInvoke()
        Timer      = New-Object System.Windows.Threading.DispatcherTimer
        OnDone     = $OnDone
    }
    [void]$script:jobs.Add($job)

    $job.Timer.Interval = [TimeSpan]::FromMilliseconds(200)
    # Il job si ritrova dal SENDER (il timer che ha generato il tick), non da una
    # variabile catturata.
    # PERCHE' NON .GetNewClosure(): la closure crea un module scope proprio, dentro il
    # quale $script: NON e' piu' lo scope di questo script — $script:jobs risultava
    # $null e il cleanup moriva con "impossibile chiamare un metodo su null", lasciando
    # il job appeso per sempre. Le variabili LOCALI non sarebbero visibili senza
    # closure, quindi tutto quello che serve al tick vive nell'oggetto $job.
    $job.Timer.Add_Tick({
        param($s, $e)
        $j = @($script:jobs | Where-Object { $_.Timer -eq $s })[0]
        if (-not $j) { $s.Stop(); return }   # job gia' chiuso da Stop-AllJobs
        if (-not $j.Handle.IsCompleted) { return }
        $j.Timer.Stop()

        $result = @()
        try {
            $result = @($j.PowerShell.EndInvoke($j.Handle))
            # Un errore che non interrompe lo script (es. "termine non riconosciuto" per una
            # funzione mancante in -Functions) finisce nello stream Error, non in EndInvoke:
            # senza questa riga il job tornava vuoto senza lasciare traccia nel log.
            foreach ($err in $j.PowerShell.Streams.Error) { Write-Log "ERROR in background job: $($err.Exception.Message)" }
            # Un job fermato o fallito senza un record d'errore non deve sparire nel nulla: si dice
            # almeno in che stato si e' fermato. Completed senza output e' normale (le code).
            $st = $j.PowerShell.InvocationStateInfo
            if ($st.State -ne 'Completed') {
                Write-Log "ERROR in background job: it ended in state $($st.State)$(if ($st.Reason) { ": $($st.Reason.Message)" })."
            }
        }
        catch { Write-Log "ERROR in background job: $($_.Exception.Message)" }
        finally {
            $j.PowerShell.Dispose()
            $j.Runspace.Close()
            $j.Runspace.Dispose()
            [void]$script:jobs.Remove($j)
        }
        # Fuori dal try: il ripristino della UI deve avvenire anche se il job e' morto.
        if ($j.OnDone) { & $j.OnDone $result }
    })
    $job.Timer.Start()
    return $job
}

# Ferma e chiude tutti i job in corso. Chiamata dalla chiusura della finestra.
function Stop-AllJobs {
    foreach ($job in @($script:jobs)) {
        try { $job.Timer.Stop() } catch { }
        try { $job.Runspace.Dispose() } catch { }
    }
    $script:jobs.Clear()
}

# Esegue winget su ogni riga in SEQUENZA (winget non e' affidabile in parallelo),
# scrivendo l'esito nella riga stessa e l'avanzamento nella barra condivisa.
# Un errore su un pacchetto NON interrompe la coda.
#   -Rows        righe WgtRow su cui lavorare (aggiornate per riferimento)
#   -ArgsBuilder param($row) -> riga di argomenti per winget
#   -Verb        parola usata nei messaggi di log ("Update", "Install", ...)
#   -Vars        variabili extra visibili dentro il runspace, quindi anche dentro
#                -ArgsBuilder: e' cosi' che l'install passa lo --scope scelto, senza
#                doverlo interpolare nel testo dello scriptblock
#   -OnDone      scriptblock sul thread UI a coda finita
function Start-WinGetQueue {
    param(
        [Parameter(Mandatory)][object[]]$Rows,
        [Parameter(Mandatory)][scriptblock]$ArgsBuilder,
        [string]$Verb = 'Update',
        [hashtable]$Vars = @{},
        [scriptblock]$OnDone
    )

    # UNICO punto di passaggio di update, install, uninstall e pin: lo stato occupato lo
    # prende lei, cosi' i chiamanti non possono dimenticarselo, e il controllo contro un
    # winget gia' in corso (ricerche comprese) vive in un posto solo invece che in quattro.
    if (Test-WinGetBusy) {
        Write-Log "Another winget operation is still running: try again in a moment."
        return
    }
    # PRIMA di Set-AppBusy, e l'ordine e' vincolante: Set-AppBusy chiama subito gli handler
    # delle schede, e quelli leggono queueVerb per decidere se l'operazione e' la loro — con
    # l'assegnazione dopo, il pulsante Update della scheda Updates non diventava mai Cancel.
    # Nuova hashtable a ogni coda: una richiesta di annullamento arrivata fra due code non si
    # trascina sulla successiva.
    $script:queueVerb   = $Verb
    $script:queueCancel = [hashtable]::Synchronized(@{ Requested = $false })
    # Per Retry failed: la stessa coda si puo' rilanciare sulle sole righe fallite.
    $script:lastQueue   = @{ Verb = $Verb; Rows = $Rows; ArgsBuilder = $ArgsBuilder; Vars = $Vars; OnDone = $OnDone }

    Set-AppBusy $true

    # Azzera eventuali esiti precedenti sulle righe in coda
    foreach ($item in $Rows) { $item.Status = ''; $item.StatusDetail = '' }

    # Determinata, e in modo esplicito: la coda sa quanti pacchetti ha, e una scansione
    # appena finita puo' aver lasciato la barra indeterminata.
    $Progress.IsIndeterminate = $false
    $Progress.Value   = 0
    $Progress.Maximum = $Rows.Count
    Write-Log "Starting $($Verb.ToLower()) of $($Rows.Count) packages..."

    # window e txtLog li passa Start-BackgroundJob a tutti i job: qui non si ripetono.
    $jobVars = @{
        rows       = $Rows
        cancel     = $script:queueCancel
        progress   = $Progress
        wingetPath = $wingetPath
        verb       = $Verb
        # Come le funzioni: il corpo come testo, ricreato dentro il runspace.
        argsFnBody = $ArgsBuilder.ToString()
    }
    # Le variabili del chiamante NON sovrascrivono quelle della coda: un nome ripetuto
    # sarebbe un errore da segnalare, non da risolvere in silenzio.
    foreach ($kv in $Vars.GetEnumerator()) {
        if ($jobVars.ContainsKey($kv.Key)) { throw "Start-WinGetQueue: -Vars usa un nome riservato '$($kv.Key)'" }
        $jobVars[$kv.Key] = $kv.Value
    }

    # [void]: il job non deve finire sulla pipeline del chiamante.
    [void](Start-BackgroundJob -OnDone $OnDone -Functions 'Get-UpdateStatus', 'Invoke-WinGet', 'Get-WinGetOutputTail', 'Invoke-UnelevatedTask', 'Test-ElevatedUserMismatch', 'Get-QueueSummary' -Vars $jobVars -Script {
        Invoke-Expression "function Get-WinGetArgs { $argsFnBody }"

        $done    = 0
        $stopped = $false
        foreach ($item in $rows) {
            # Annullamento: si controlla PRIMA di partire col pacchetto, mai a meta'.
            if ($cancel.Requested) { $stopped = $true; break }
            $id   = $item.Id
            $name = $item.Name
            UI { $item.Status = 'updating'; $item.StatusDetail = 'In progress...' }
            LogUI "-> $name [$id]"
            try {
                $argLine = Get-WinGetArgs $item
                $tick    = { param($s) LogUI "   ...$name running for ${s}s" }
                $r = Invoke-WinGet $wingetPath $argLine $tick
                # 0x8A15007D: winget rifiuta di disinstallare (o riparare) un pacchetto per-utente
                # da amministratore, ed e' un blocco voluto (issue #12). Si ripete la stessa riga
                # come QUESTO account senza elevazione (ADR 0018): i pacchetti per-utente in
                # elenco sono i suoi. Se l'account elevato non e' quello della sessione non ha
                # dove girare, e ripetere come l'utente della sessione colpirebbe un altro
                # profilo: lo si dice e basta.
                if ($r.ExitCode -eq -1978335107) {
                    $me = [Security.Principal.WindowsIdentity]::GetCurrent().Name
                    if (Test-ElevatedUserMismatch) {
                        LogUI "   winget refuses this as administrator, and the package belongs to $me, which is not the signed-in user: sign in as $me to $($verb.ToLower()) it."
                    }
                    else {
                        LogUI "   winget refuses this as administrator: retrying without elevation..."
                        $r = Invoke-WinGet $wingetPath $argLine $tick -Unelevated
                    }
                }
                $code  = $r.ExitCode
                $token = Get-UpdateStatus $code

                UI { $item.Status = $token; $item.StatusDetail = "exit $code" }
                switch ($token) {
                    'ok'      { LogUI "   OK: $name ($($r.Seconds)s)" }
                    'warning' { LogUI "   WARNING (exit $code): $name" }
                    default {
                        LogUI "   ERROR (exit $code): $name"
                        # Ultime DUE righe significative dell'output winget: quando
                        # l'installer fallisce, winget stampa il percorso del suo log
                        # DOPO il messaggio d'errore, quindi l'ultima riga da sola
                        # riportava solo il path e nascondeva la causa (Get-WinGetOutputTail).
                        foreach ($l in (Get-WinGetOutputTail $r.Output 2)) { LogUI "      $l" }
                    }
                }
            }
            catch {
                # Errore sul singolo pacchetto: NON interrompe la coda
                $msg = $_.Exception.Message
                UI { $item.Status = 'error'; $item.StatusDetail = $msg }
                LogUI "   EXCEPTION: $msg"
            }
            finally {
                $done++
                UI { $progress.Value = $done }
            }
        }
        if ($stopped) { LogUI "$verb cancelled after $done of $($rows.Count) packages; the rest were left untouched: $(Get-QueueSummary $rows)." }
        else          { LogUI "$verb complete: $(Get-QueueSummary $rows)." }
    })
}

# Esito di una coda in una riga, contato dalle righe stesse: "5 ok, 1 with warnings, 2 failed,
# 3 not run". Warning = riavvio richiesto o gia' installato (Get-UpdateStatus); not run = mai
# partiti, cioe' annullati. I conteggi a zero non si scrivono.
function Get-QueueSummary([object[]]$Rows) {
    $parts = foreach ($p in @(@('ok', 'ok'), @('warning', 'with warnings'), @('error', 'failed'), @('', 'not run'))) {
        $n = @($Rows | Where-Object { "$($_.Status)" -eq $p[0] }).Count
        if ($n -gt 0) { "$n $($p[1])" }
    }
    @($parts) -join ', '
}

# Esito delle righe per ID, da riportare sulla lista riletta a coda finita: la ricarica crea
# righe NUOVE, e senza questo la colonna Result e Retry failed sparirebbero (issue #24).
function Get-RowOutcome([object[]]$Rows) {
    $map = @{}
    foreach ($r in $Rows) { if ($r.Status -and $r.Status -ne 'updating') { $map[$r.Id] = @($r.Status, $r.StatusDetail) } }
    $map
}

function Set-RowOutcome([object[]]$Rows, [hashtable]$Outcome) {
    if (-not $Outcome) { return }
    foreach ($r in $Rows) {
        $o = $Outcome[$r.Id]
        if ($o) { $r.Status = $o[0]; $r.StatusDetail = $o[1] }
    }
}

# Righe da ripetere in un elenco: quelle con un ID fallito nell'ultima coda e l'esito ancora
# 'error'. Per ID e non per oggetto: dopo la ricarica automatica le righe sono nuove, con
# l'esito riportato da Set-RowOutcome. Una riga sparita dall'elenco (un aggiornamento riuscito
# in un secondo momento, un pacchetto rimosso) non c'e' piu' da ripetere.
function Get-RetryRows($Collection) {
    $q = $script:lastQueue
    if (-not $q) { return @() }
    $failed = @($q.Rows | Where-Object { $_.Status -eq 'error' } | ForEach-Object { $_.Id })
    if (-not $failed.Count) { return @() }
    @($Collection | Where-Object { $_.Status -eq 'error' -and $failed -contains $_.Id })
}

# Un Retry failed per scheda, in alto a destra: visibile solo dove c'e' qualcosa da ripetere,
# spento mentre winget lavora. Lo richiama Set-AppBusy (registrato in Start-App).
function Update-RetryButton {
    foreach ($pair in @(@($BtnRetryUpdates, $items), @($BtnRetryInstall, $searchItems), @($BtnRetryInstalled, $installedItems))) {
        $n = @(Get-RetryRows $pair[1]).Count
        $pair[0].Content    = "Retry failed ($n)"
        $pair[0].Visibility = if ($n -gt 0) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
        $pair[0].IsEnabled  = -not $script:isBusy
    }
}

# Ripete l'ultima coda sulle sole righe fallite dell'elenco, con gli stessi argomenti, variabili
# e OnDone (quindi anche la ricarica a coda finita). Il blocco "lista vecchia" della scheda
# Updates NON si applica: esiste perche' ripetere righe RIUSCITE dipingerebbe errori falsi, e qui
# si ripetono solo le fallite, che non hanno cambiato nulla. Conferma con No predefinito: puo'
# essere una disinstallazione.
function Start-RetryFailed($Collection) {
    $q = $script:lastQueue
    $rows = @(Get-RetryRows $Collection)
    if ($rows.Count -eq 0) { return }
    $names = @($rows | Select-Object -First 12 | ForEach-Object { "  - $($_.Name)" }) -join "`n"
    $more  = if ($rows.Count -gt 12) { "`n  ... and $($rows.Count - 12) more" } else { '' }
    $answer = Show-AppDialog -Text ("Retry the $($q.Verb.ToLower()) of $($rows.Count) package$(if ($rows.Count -ne 1) { 's' }) that failed?`n`n" + $names + $more) `
        -Title 'Retry failed' `
        -Button ([System.Windows.MessageBoxButton]::YesNo) `
        -Image ([System.Windows.MessageBoxImage]::Question) `
        -Default ([System.Windows.MessageBoxResult]::No)
    if ($answer -ne [System.Windows.MessageBoxResult]::Yes) { return }
    Start-WinGetQueue -Rows $rows -Verb $q.Verb -ArgsBuilder $q.ArgsBuilder -Vars $q.Vars -OnDone $q.OnDone
}
