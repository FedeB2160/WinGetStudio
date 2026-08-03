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
        try { $result = @($j.PowerShell.EndInvoke($j.Handle)) }
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

    # Azzera eventuali esiti precedenti sulle righe in coda
    foreach ($item in $Rows) { $item.Status = ''; $item.StatusDetail = '' }

    $Progress.Value   = 0
    $Progress.Maximum = $Rows.Count
    Write-Log "Starting $($Verb.ToLower()) of $($Rows.Count) packages..."

    $jobVars = @{
        window     = $window
        rows       = $Rows
        progress   = $Progress
        txtLog     = $TxtLog
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
    [void](Start-BackgroundJob -OnDone $OnDone -Functions 'Get-UpdateStatus', 'Invoke-WinGet' -Vars $jobVars -Script {
        Invoke-Expression "function Get-WinGetArgs { $argsFnBody }"

        # Helper per aggiornare la UI dal thread di lavoro
        function UI([scriptblock]$action) {
            $window.Dispatcher.Invoke([System.Windows.Threading.DispatcherPriority]::Background, [action]$action)
        }
        function LogUI([string]$m) {
            $ts = (Get-Date).ToString('HH:mm:ss')
            UI { $txtLog.AppendText("[$ts] $m`r`n"); $txtLog.ScrollToEnd() }
        }

        $done = 0
        foreach ($item in $rows) {
            $id   = $item.Id
            $name = $item.Name
            UI { $item.Status = 'updating'; $item.StatusDetail = 'In progress...' }
            LogUI "-> $name [$id]"
            try {
                $r = Invoke-WinGet $wingetPath (Get-WinGetArgs $item) `
                        { param($s) LogUI "   ...$name running for ${s}s" }
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
                        # riportava solo il path e nascondeva la causa.
                        $tail = @($r.Output -split "`r`n|`n" | Where-Object { $_.Trim() } | Select-Object -Last 2)
                        foreach ($l in $tail) { LogUI "      $($l.Trim())" }
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
        LogUI "$verb complete ($done/$($rows.Count))."
    })
}
