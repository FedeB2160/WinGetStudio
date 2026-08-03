<#
    WinGet.Exec.ps1 — esecuzione di winget e lettura del suo esito.

    Qui vive tutto cio' che riguarda il LANCIARE winget; il parsing del suo output
    tabellare sta in WinGet.Parse.ps1.

    Caricato dal bootstrap (src\WinGetUpdateTool.ps1): dot-source come .ps1,
    concatenato nell'exe al posto del marcatore ###MODULES###.
#>

# Percorso reale di winget, oppure $null se non c'e'. L'alias di esecuzione app va
# bene per Process.Start; il fallback al nome nudo serve se Source e' vuoto.
function Get-WinGetPath {
    $cmd = Get-Command winget -ErrorAction SilentlyContinue
    if (-not $cmd) { return $null }
    if ($cmd.Source) { return $cmd.Source }
    return 'winget'
}

# Mappa l'exit code di winget in un token di stato: ok / warning / error.
function Get-UpdateStatus([int]$code) {
    if ($code -eq 0) { return 'ok' }
    # winget usa HRESULT (Int32 negativi). NB: un literal hex a 8 cifre in PowerShell
    # e' Int32 (0xFFFFFFFF = -1!), quindi si lavora in Int64 con suffisso L e si
    # normalizza al valore unsigned a 32 bit.
    $u = ([int64]$code) -band 0xFFFFFFFFL
    $benign = @(
        0x8A150108L,  # REBOOT_REQUIRED_TO_FINISH
        0x8A150109L,  # REBOOT_REQUIRED_FOR_INSTALL
        0x8A15010AL,  # REBOOT_INITIATED
        0x8A15010CL,  # ALREADY_INSTALLED
        3010L,        # ERROR_SUCCESS_REBOOT_REQUIRED
        1641L         # ERROR_SUCCESS_REBOOT_INITIATED
    )
    if ($benign -contains $u) { return 'warning' }
    return 'error'
    # ponytail: lista codici benigni tunabile; se ne emergono altri, aggiungere qui.
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
function Invoke-WinGet([string]$exePath, [string]$argLine, [scriptblock]$Tick) {
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
        $psi = New-Object Diagnostics.ProcessStartInfo
        $psi.FileName        = 'cmd.exe'
        $psi.Arguments       = "/d /s /c `"`"$exePath`" $argLine >`"$outFile`" 2>`"$errFile`"`""
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow  = $true
        $p = [Diagnostics.Process]::Start($psi)
        $sw = [Diagnostics.Stopwatch]::StartNew()
        while (-not $p.WaitForExit(30000)) {
            if ($Tick) { & $Tick ([int]$sw.Elapsed.TotalSeconds) }
        }
        # -Encoding UTF8 OBBLIGATORIO: winget scrive UTF-8, ma Get-Content in
        # PowerShell 5.1 assume il codepage ANSI del sistema -> i messaggi localizzati
        # arrivavano a mojibake ("Ã¨ stata trovata una versione piÃ¹ recente").
        # NB: -Encoding UTF8 legge correttamente anche senza BOM.
        $text = [string](Get-Content $outFile -Raw -Encoding UTF8 -ErrorAction SilentlyContinue) +
                [string](Get-Content $errFile -Raw -Encoding UTF8 -ErrorAction SilentlyContinue)
        return [PSCustomObject]@{
            ExitCode = $p.ExitCode
            Output   = $text
            Seconds  = [int]$sw.Elapsed.TotalSeconds
        }
    }
    finally {
        foreach ($f in @($outFile, $errFile)) { Remove-Item $f -Force -ErrorAction SilentlyContinue }
    }
}
