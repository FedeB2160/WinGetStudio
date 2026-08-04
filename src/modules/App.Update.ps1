<#
    App.Update.ps1 — aggiornamento automatico dell'applicazione dalle release GitHub.

    Il repo e' pubblico, quindi l'API si interroga SENZA token (60 richieste/ora per IP,
    e qui se ne usa una sola all'avvio).

    COME SI SOSTITUISCE DA SOLO: su Windows un eseguibile in esecuzione non puo' essere
    sovrascritto, ma PUO' essere rinominato. Quindi si rinomina in ".old", si scrive il
    nuovo al suo posto, si riavvia, e al giro dopo si cancella il ".old". Nessun
    programma di aggiornamento esterno.

    Caricato da src\main.ps1: dot-source come .ps1, concatenato nell'exe al posto
    del marcatore ###MODULES###.
#>

$UpdateRepo = 'FedeB2160/WinGetStudio'

# Release piu' recente, o $null se non c'e' rete, non ci sono release, o la risposta non
# ha un asset .exe. Nessun errore a video: un aggiornamento non trovato non e' un guasto.
# Gira in un runspace, quindi non tocca la UI.
function Get-LatestRelease([string]$Repo) {
    try {
        # TLS 1.2 esplicito: PowerShell 5.1 negozia ancora TLS 1.0 per default e GitHub
        # lo rifiuta, quindi senza questa riga la chiamata fallisce sempre.
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        # User-Agent obbligatorio: l'API di GitHub risponde 403 alle richieste che non ne
        # hanno uno.
        $r = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" `
                -Headers @{ 'User-Agent' = 'WinGetStudio'; 'Accept' = 'application/vnd.github+json' } `
                -TimeoutSec 15
        if (-not $r.tag_name) { return $null }

        # Si cerca il primo asset .exe invece di un nome preciso: le release vecchie
        # portano ancora il nome di prima del rename.
        $asset = @($r.assets | Where-Object { $_.name -like '*.exe' })[0]
        if (-not $asset) { return $null }

        return [PSCustomObject]@{
            Tag    = $r.tag_name
            # I tag sono "v1.6.0": la v va togliesta per confrontare come versione.
            Version = ($r.tag_name -replace '^[vV]', '')
            Name   = $asset.name
            Url    = $asset.browser_download_url
            Size   = $asset.size
            # digest = "sha256:abc..." quando GitHub lo espone; serve a verificare il file
            # scaricato prima di eseguirlo.
            Sha256 = if ($asset.digest -match '^sha256:(.+)$') { $Matches[1] } else { $null }
        }
    }
    catch { return $null }
}

# $Latest e' piu' recente di $Current? Confronto per componenti numeriche, non per
# stringa: "1.10.0" -gt "1.9.0" e' FALSO da stringa e vero da versione.
function Test-NewerVersion([string]$Latest, [string]$Current) {
    try {
        $l = [version]($Latest -replace '^[vV]', '')
        $c = [version]($Current -replace '^[vV]', '')
        return $l -gt $c
    }
    catch { return $false }   # tag non numerico (es. "nightly"): non si propone nulla
}

# Percorso dell'eseguibile in esecuzione, o $null se stiamo girando come .ps1.
# L'auto-update ha senso solo per l'exe: da sorgente ci si aggiorna con git.
function Get-RunningExePath {
    $exe = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    if ($exe -match '(?i)\\(powershell|pwsh)\.exe$') { return $null }
    return $exe
}

# Rimuove il ".old" lasciato dall'aggiornamento precedente. Best effort: se il file e'
# ancora in uso si riprovera' al prossimo avvio.
function Clear-OldExe {
    $exe = Get-RunningExePath
    if (-not $exe) { return }
    Remove-Item "$exe.old" -Force -ErrorAction SilentlyContinue
}

# Controlla in background se esiste una versione piu' recente e, se c'e', mostra il
# pulsante di aggiornamento. Silenzioso in ogni altro caso.
#   -Manual: controllo chiesto dal pulsante "Check for updates". Riferisce SEMPRE l'esito
#            (anche "sei aggiornato" o "non raggiungibile"), mentre il controllo
#            automatico all'avvio tace se non c'e' nulla da dire.
function Start-UpdateCheck([switch]$Manual) {
    if (-not (Get-RunningExePath)) {
        if ($Manual) { $TxtUpdateStatus.Text = 'Updates apply to the compiled exe only; from source use git.' }
        return
    }
    if ($script:isBusy) { return }

    if ($Manual) {
        $TxtUpdateStatus.Text        = 'Checking...'
        $UpdateSpinner.Visibility    = [System.Windows.Visibility]::Visible
        $BtnCheckUpdate.IsEnabled    = $false
    }
    # $script: e NON una locale: OnDone gira sul thread UI e non vede le variabili locali
    # di questa funzione. Con "$manual" locale il controllo manuale non riportava nulla.
    $script:manualCheck = [bool]$Manual

    [void](Start-BackgroundJob -Functions 'Get-LatestRelease' `
        -Vars @{ repo = $UpdateRepo } `
        -Script { Get-LatestRelease $repo } `
        -OnDone {
            param($result)
            $manual = $script:manualCheck
            $UpdateSpinner.Visibility = [System.Windows.Visibility]::Collapsed
            $BtnCheckUpdate.IsEnabled = -not $script:isBusy
            $rel = @($result)[0]

            if (-not $rel) {
                # Nessuna release, nessuna rete, nessun asset: all'avvio si tace.
                if ($manual) { $TxtUpdateStatus.Text = 'No release found (or GitHub not reachable).' }
                return
            }
            if (-not (Test-NewerVersion $rel.Version $AppVersion)) {
                if ($manual) { $TxtUpdateStatus.Text = "Up to date (latest published is $($rel.Tag))." }
                return
            }

            $script:pendingUpdate = $rel
            $BtnUpdateApp.Content    = "Update to $($rel.Tag)"
            $BtnUpdateApp.ToolTip    = "Download $($rel.Name) ($([int]($rel.Size / 1024)) KB) from GitHub and restart"
            $BtnUpdateApp.Visibility = [System.Windows.Visibility]::Visible
            $TxtUpdateStatus.Text    = "$($rel.Tag) is available."
            Write-Log "Version $($rel.Tag) is available (you have v$AppVersion)."
        })
}

# Scarica, verifica e sostituisce. Chiamata dal pulsante, dopo conferma.
function Start-SelfUpdate {
    $rel = $script:pendingUpdate
    if (-not $rel -or $script:isBusy) { return }
    $exe = Get-RunningExePath
    if (-not $exe) { return }

    $answer = [System.Windows.MessageBox]::Show(
        "Download $($rel.Tag) and restart WinGet Studio?`n`n" +
        "$($rel.Name) - $([int]($rel.Size / 1024)) KB`nFrom: $($rel.Url)`n`n" +
        $(if ($rel.Sha256) { "The download is verified against the SHA-256 published with the release." }
          else { "WARNING: this release publishes no checksum, so the download cannot be verified." }),
        "Update WinGet Studio",
        [System.Windows.MessageBoxButton]::YesNo,
        [System.Windows.MessageBoxImage]::Question,
        [System.Windows.MessageBoxResult]::No)
    if ($answer -ne [System.Windows.MessageBoxResult]::Yes) { return }

    Set-AppBusy $true
    Write-Log "Downloading $($rel.Name) ..."
    $tmp = Join-Path ([IO.Path]::GetTempPath()) "WinGetStudio-$($rel.Tag).exe"

    # OnDone gira sul thread UI e NON vede le variabili locali di questa funzione: con
    # $exe, $tmp e $rel locali arrivavano vuote, e l'aggiornamento moriva su
    # "Remove-Item: Path e' null" e "Start-Process: FilePath e' null".
    # Stesso inciampo di scope documentato per i job in DEVELOPMENT.md.
    $script:updExe = $exe
    $script:updTmp = $tmp
    $script:updRel = $rel

    [void](Start-BackgroundJob -Vars @{ url = $rel.Url; dest = $tmp; expected = $rel.Sha256 } `
        -Script {
            try {
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing `
                    -Headers @{ 'User-Agent' = 'WinGetStudio' } -TimeoutSec 300
                $hash = (Get-FileHash $dest -Algorithm SHA256).Hash
                # Il confronto e' il presidio principale: si sta per ESEGUIRE questo file.
                # Senza checksum pubblicato non si puo' verificare, e lo si dice.
                $okHash = (-not $expected) -or ($hash -eq $expected.ToUpperInvariant())
                [PSCustomObject]@{ Ok = $okHash; Hash = $hash; Verified = [bool]$expected }
            }
            catch { [PSCustomObject]@{ Ok = $false; Error = $_.Exception.Message } }
        } `
        -OnDone {
            param($result)
            $exe = $script:updExe
            $tmp = $script:updTmp
            $rel = $script:updRel
            $d = @($result)[0]
            if (-not $d -or -not $d.Ok) {
                Write-Log "Update FAILED: $(if ($d.Error) { $d.Error } else { 'checksum mismatch, the download was discarded' })."
                if ($tmp) { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
                Set-AppBusy $false
                return
            }
            Write-Log $(if ($d.Verified) { "Download verified (SHA-256 matches)." } else { "Download complete (no checksum to verify against)." })

            try {
                # Il file in esecuzione non si sovrascrive, ma si rinomina: dopo lo
                # spostamento il suo percorso e' libero per il file nuovo.
                Move-Item -LiteralPath $exe -Destination "$exe.old" -Force
                Move-Item -LiteralPath $tmp -Destination $exe -Force
            }
            catch {
                Write-Log "Update FAILED while replacing the executable: $($_.Exception.Message)"
                # Se il rename e' andato ma la copia no, l'app resta senza eseguibile:
                # si rimette a posto quello vecchio.
                if (-not (Test-Path $exe) -and (Test-Path "$exe.old")) {
                    Move-Item -LiteralPath "$exe.old" -Destination $exe -Force -ErrorAction SilentlyContinue
                }
                Set-AppBusy $false
                return
            }

            Write-Log "Updated to $($rel.Tag). Restarting..."
            # Il nuovo exe ha il manifest requireAdministrator: parte con il suo prompt UAC.
            Start-Process -FilePath $exe -ErrorAction SilentlyContinue
            $window.Close()
        })
}

function Initialize-Update {
    Clear-OldExe                     # pulisce il residuo dell'aggiornamento precedente
    # La versione sta qui, non nel titolo della finestra.
    $TxtVersion.Text = "v$AppVersion"
    $BtnUpdateApp.Add_Click({ Start-SelfUpdate })
    $BtnCheckUpdate.Add_Click({ Start-UpdateCheck -Manual })
    Register-BusyHandler {
        param($busy)
        $BtnUpdateApp.IsEnabled   = -not $busy
        $BtnCheckUpdate.IsEnabled = -not $busy
    }
}
