<#
    WinGet.Exec.ps1 — esecuzione di winget e lettura del suo esito.

    Qui vive tutto cio' che riguarda il LANCIARE winget; il parsing del suo output
    tabellare sta in WinGet.Parse.ps1.

    Caricato dal bootstrap (src\main.ps1): dot-source come .ps1,
    concatenato nell'exe al posto del marcatore ###MODULES###.
#>

# Percorso reale di winget, oppure $null se non c'e'. L'alias di esecuzione app va
# bene per Process.Start; il fallback al nome nudo serve se Source e' vuoto.
function Get-WinGetPath {
    $cmd = Get-Command winget -ErrorAction SilentlyContinue
    if ($cmd) {
        if ($cmd.Source) { return $cmd.Source }
        return 'winget'
    }
    # PATH senza WindowsApps (problema noto, winget-cli#210): l'alias c'e' lo stesso. Senza
    # questo, a winget appena installato l'app riproporrebbe l'installazione a ogni avvio.
    $alias = Join-Path $env:LOCALAPPDATA 'Microsoft\WindowsApps\winget.exe'
    if (Test-Path -LiteralPath $alias) { return $alias }
    return $null
}

# Mappa l'exit code di winget in un token di stato: ok / warning / error.
function Get-UpdateStatus([int]$code) {
    if ($code -eq 0) { return 'ok' }
    # winget usa HRESULT (Int32 negativi). NB: un literal hex a 8 cifre in PowerShell
    # e' Int32 (0xFFFFFFFF = -1!), quindi si lavora in Int64 con suffisso L e si
    # normalizza al valore unsigned a 32 bit.
    $u = ([int64]$code) -band 0xFFFFFFFFL
    # Nomi verificati con "winget error <codice>" (1.29.380). Fino alla 1.12.0 la lista era
    # sfasata di uno: 0x8A150108 (CONTACT_SUPPORT), 0x8A15010A (REBOOT_REQUIRED_FOR_INSTALL,
    # installazione NON riuscita) e 0x8A15010C (CANCELLED_BY_USER) sono errori veri.
    $benign = @(
        0x8A150109L,  # INSTALL_REBOOT_REQUIRED_TO_FINISH
        0x8A15010BL,  # INSTALL_REBOOT_INITIATED
        0x8A15010DL,  # INSTALL_ALREADY_INSTALLED
        3010L,        # ERROR_SUCCESS_REBOOT_REQUIRED
        1641L         # ERROR_SUCCESS_REBOOT_INITIATED
    )
    if ($benign -contains $u) { return 'warning' }
    return 'error'
    # ponytail: lista codici benigni tunabile; se ne emergono altri, aggiungere qui.
}

# Rimuove i file di output di Invoke-WinGet rimasti in %TEMP%. Invoke-WinGet li cancella da
# sola, ma un installer che lascia un processo figlio staccato li tiene aperti in quel momento
# e la cancellazione fallisce: senza questa pulizia all'avvio si accumulavano. Best effort: un
# file ancora in uso resta per il giro dopo. .NET e non Remove-Item, che su un %TEMP% in forma
# 8.3 (profilo col punto nel nome) puo' non risolvere il percorso.
function Clear-WinGetTempFiles {
    foreach ($f in [IO.Directory]::GetFiles([IO.Path]::GetTempPath(), 'wgt_*')) {
        try { [IO.File]::Delete($f) } catch { }
    }
    # Anche le cartelle: quella del download di winget (WinGet.Setup.ps1) pesa 300 MB se il
    # processo muore a meta'. In %SystemRoot%\Temp c'e' quella protetta dell'auto-aggiornamento
    # (New-UpdateDownloadDir, ADR 0022); senza elevazione quella cartella non si elenca, e la si salta.
    foreach ($root in [IO.Path]::GetTempPath(), (Join-Path $env:SystemRoot 'Temp')) {
        try { $dirs = [IO.Directory]::GetDirectories($root, 'wgt_*') } catch { continue }
        foreach ($d in $dirs) {
            try { [IO.Directory]::Delete($d, $true) } catch { }
        }
    }
}

# Ultime righe significative di un output winget, per log e messaggi: la causa di un errore
# sta in fondo (quando un installer fallisce winget stampa il percorso del suo log DOPO il
# messaggio, quindi l'ultima riga da sola non basta). Dei segmenti di avanzamento separati
# da \r resta l'ultimo, come in Get-WinGetTable; le righe vuote si scartano.
function Get-WinGetOutputTail([string]$Text, [int]$Count = 2) {
    @($Text -split "`r`n|`n" | ForEach-Object { ($_ -split "`r")[-1].Trim() } | Where-Object { $_ } | Select-Object -Last $Count)
}

# Esegue winget e attende SOLO l'uscita del processo, catturando l'output SU FILE.
# PERCHE' NON '& winget ... | Out-String': la pipeline ritorna all'EOF della pipe di
# stdout, cioe' quando TUTTI i processi che possiedono quel handle lo chiudono. Gli
# installer silenziosi lanciati da winget ereditano il handle: se uno resta vivo (o si
# rilancia staccandosi) l'EOF non arriva mai e l'attesa e' infinita, anche a winget
# uscito e pacchetti installati. Con redirect su file + WaitForExit() il completamento
# dipende dal solo winget.
# NB: -Wait di Start-Process attende anche i DISCENDENTI, cioe' proprio cio' da cui
# stiamo scappando -> -PassThru + WaitForExit().
# $Tick viene invocato ogni 30s con i secondi trascorsi (log "elapsed"). Nessun
# timeout: gli installer lenti non vengono troncati.
# -Unelevated: la stessa riga gira come questo account SENZA elevazione, tramite
# Invoke-UnelevatedTask (ADR 0018). File di output e percorso di winget restano validi: sono
# dello stesso account.
function Invoke-WinGet([string]$exePath, [string]$argLine, [scriptblock]$Tick, [switch]$Unelevated) {
    # La riga finisce dentro cmd per CONCATENAZIONE, e ogni chiamante interpola l'Id del
    # pacchetto fra apici (--id "$($r.Id)"). Con un numero DISPARI di apici doppi il comando
    # che cmd vede non e' quello che intendevamo, e cmd lo esegue lo stesso: meglio fermarsi.
    # Gli Id vengono dal catalogo winget e dal registro ARP, dove il nome lo scrive
    # l'installer — cioe' una terza parte — e questo processo gira elevato.
    if ((($argLine.ToCharArray() | Where-Object { $_ -eq '"' }).Count % 2) -ne 0) {
        throw "winget arguments have unbalanced quotes, refusing to run: $argLine"
    }
    # Stesso motivo per '%': cmd espande %VAR% anche fra apici, e lo fa DOPO il conteggio qui
    # sopra. Un processo non elevato puo' creare una voce ARP per utente con %X% nel nome e una
    # variabile d'ambiente utente X con apici e '&': disinstallarla da qui eseguirebbe il resto
    # da amministratore. Un Id o un percorso con '%' e' raro: si rifiuta, come fa UniGetUI.
    # Per !VAR! c'e' /v:off piu' sotto: l'espansione ritardata si accende anche da HKCU.
    if ($argLine.Contains('%')) {
        throw "winget arguments contain '%', which cmd would expand, refusing to run: $argLine"
    }
    $outFile = Join-Path ([IO.Path]::GetTempPath()) "wgt_$([Guid]::NewGuid().ToString('N')).out"
    $errFile = [IO.Path]::ChangeExtension($outFile, 'err')
    try {
        # PERCHE' NON Start-Process -PassThru: il suo oggetto Process perde ExitCode se il
        # processo esce prima che il handle nativo sia stato letto (race vinta dai comandi
        # rapidi). ExitCode vuoto castato a int fa 0 -> Get-UpdateStatus dice 'ok' e un
        # fallimento risulta verde. Con Process.Start il handle e' nostro dall'inizio.
        # Il redirect su file lo fa cmd (/s /c + tutta la riga tra apici: cmd toglie solo
        # gli apici esterni e passa il resto verbatim), cosi' non ci sono pipe da svuotare
        # e l'attesa dipende dal solo processo.
        # /v:off: DelayedExpansion=1 in HKCU\Software\Microsoft\Command Processor lo puo' mettere
        # un processo non elevato, e allora cmd espanderebbe anche !VAR!. L'opzione vince sul registro.
        $run = "`"$exePath`" $argLine >`"$outFile`" 2>`"$errFile`""
        $sw = [Diagnostics.Stopwatch]::StartNew()
        if ($Unelevated) {
            # L'attivita' apre una finestra console nella sessione: il titolo dice di chi e'.
            $code = Invoke-UnelevatedTask "/d /v:off /s /c `"title WinGet Studio & $run`"" $Tick
        }
        else {
            $psi = New-Object Diagnostics.ProcessStartInfo
            $psi.FileName        = 'cmd.exe'
            $psi.Arguments       = "/d /v:off /s /c `"$run`""
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow  = $true
            $p = [Diagnostics.Process]::Start($psi)
            while (-not $p.WaitForExit(30000)) {
                if ($Tick) { & $Tick ([int]$sw.Elapsed.TotalSeconds) }
            }
            $code = $p.ExitCode
        }
        # -Encoding UTF8 OBBLIGATORIO: winget scrive UTF-8, ma Get-Content in
        # PowerShell 5.1 assume il codepage ANSI del sistema -> i messaggi localizzati
        # arrivavano a mojibake ("Ã¨ stata trovata una versione piÃ¹ recente").
        # NB: -Encoding UTF8 legge correttamente anche senza BOM.
        $text = [string](Get-Content $outFile -Raw -Encoding UTF8 -ErrorAction SilentlyContinue) +
                [string](Get-Content $errFile -Raw -Encoding UTF8 -ErrorAction SilentlyContinue)
        return [PSCustomObject]@{
            ExitCode = $code
            Output   = $text
            Seconds  = [int]$sw.Elapsed.TotalSeconds
        }
    }
    finally {
        foreach ($f in @($outFile, $errFile)) { Remove-Item $f -Force -ErrorAction SilentlyContinue }
    }
}

# Esegue cmd.exe con $Arguments come QUESTO account ma SENZA elevazione, e ne torna l'exit
# code. Serve dove winget rifiuta di lavorare da amministratore (0x8A15007D, ADR 0018).
# Un'attivita' pianificata e' il modo documentato di avere un token non elevato da un processo
# elevato senza chiedere password: LogonType Interactive la fa girare nella sessione gia'
# aperta dall'account, RunLevel Limited col token filtrato. Se l'account non ha una sessione
# aperta l'attivita' non parte, e dopo 30 s si esce con un errore che lo dice.
# cmd.exe e non conhost o powershell nascosti: conhost restituisce sempre 0 invece dell'exit
# code, e le finestre nascoste con trucchi sono cio' che gli antivirus aziendali segnalano.
# Il prezzo e' una finestra console visibile finche' winget lavora.
# $Tick come in Invoke-WinGet: ogni 30 s, con i secondi trascorsi.
function Invoke-UnelevatedTask([string]$Arguments, [scriptblock]$Tick) {
    $name = "WinGetStudio_$([Guid]::NewGuid().ToString('N'))"
    try {
        $me = [Security.Principal.WindowsIdentity]::GetCurrent().Name
        # Senza le due opzioni di batteria, su un portatile scollegato l'attivita' non parte.
        $task = New-ScheduledTask `
            -Action    (New-ScheduledTaskAction -Execute 'cmd.exe' -Argument $Arguments) `
            -Principal (New-ScheduledTaskPrincipal -UserId $me -LogonType Interactive -RunLevel Limited) `
            -Settings  (New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero))
        [void](Register-ScheduledTask -TaskName $name -InputObject $task -ErrorAction Stop)
        Start-ScheduledTask -TaskName $name -ErrorAction Stop
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $nextTick = 30
        while ($true) {
            Start-Sleep -Milliseconds 500
            $t = Get-ScheduledTask -TaskName $name -ErrorAction Stop
            $result = ($t | Get-ScheduledTaskInfo -ErrorAction Stop).LastTaskResult
            # 0x41301 = in corso, 0x41303 = non ancora partita; altrimenti e' l'exit code di cmd.
            if ($t.State -ne 'Running' -and $t.State -ne 'Queued' -and $result -notin 0x41301, 0x41303) { break }
            $s = [int]$sw.Elapsed.TotalSeconds
            if ($result -eq 0x41303 -and $s -ge 30) { throw "the unelevated task did not start within 30 seconds: $me has no open session to run it in" }
            if ($Tick -and $s -ge $nextTick) { & $Tick $s; $nextTick += 30 }
        }
        # LastTaskResult e' un UInt32, winget esce con HRESULT negativi (0x8A15007D = -1978335107).
        $code = [int64]$result
        if ($code -gt [int]::MaxValue) { $code -= 4294967296 }
        return [int]$code
    }
    finally {
        Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction SilentlyContinue
    }
}

