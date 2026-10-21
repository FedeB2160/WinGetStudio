<#
    App.Update.ps1 — aggiornamento automatico dell'applicazione dalle release GitHub.

    Il repo e' pubblico, quindi l'API si interroga SENZA token (60 richieste/ora per IP:
    all'avvio una per l'app, e una per winget dove non lo aggiorna lo Store, WinGet.Setup.ps1).

    COME SI SOSTITUISCE DA SOLO: su Windows un eseguibile in esecuzione non puo' essere
    sovrascritto, ma PUO' essere rinominato. Quindi si rinomina in ".old", si scrive il
    nuovo al suo posto, si riavvia, e al giro dopo si cancella il ".old". Nessun
    programma di aggiornamento esterno.

    Caricato da src\main.ps1: dot-source come .ps1, concatenato nell'exe al posto
    del marcatore ###MODULES###.
#>

$UpdateRepo = 'FedeB2160/WinGetStudio'

# ID con cui l'app e' pubblicata nel catalogo winget. Serve a TENERSI FUORI dalla propria
# lista di aggiornamenti: winget non puo' sovrascrivere un eseguibile in esecuzione,
# quindi spuntarsi nella scheda Updates fallirebbe sempre. Ci si aggiorna dal pulsante
# nelle impostazioni, che si rinomina e riavvia.
$SelfPackageId = 'FedeB2160.WinGetStudio'

# Identita' dell'installer (installer\WinGetStudio.iss): la voce di disinstallazione e'
# HKLM\...\Uninstall\<AppId>_is1, nella vista a 32 bit (WOW6432Node) perche' il setup e' x86.
$InnoAppId      = '{80A0A054-6278-4145-AD5A-2B3C4853019F}'
$SetupAssetName = 'WinGetStudio_Setup.exe'

# Thumbprint del certificato di assets\WinGetStudio-codesign.cer (ADR 0012): un aggiornamento
# firmato da altri non si esegue (ADR 0022). Scritto qui perche' nell'exe il .cer non c'e';
# Test-Ui verifica che coincida con quello del file.
$UpdateSignerThumbprint = '139AD24ECA430A310495641A8FBBA66D305FA57D'

# Il file e' firmato con la NOSTRA chiave? $Signature e' il risultato di Get-AuthenticodeSignature.
# Valid dove il .cer e' stato importato fra le radici attendibili, UnknownError altrove (radice
# self-signed, ADR 0012): entrambi vanno, ma solo col nostro firmatario. UnknownError e' anche lo
# stato di ripiego di PowerShell, e senza il thumbprint non dimostrerebbe nulla: un file non
# firmabile, per esempio, torna UnknownError senza firmatario. NotSigned, HashMismatch e il resto no.
function Test-UpdateSignature($Signature, [string]$Thumbprint) {
    return ("$($Signature.Status)" -in 'Valid', 'UnknownError') -and
           [bool]$Thumbprint -and $Signature.SignerCertificate.Thumbprint -eq $Thumbprint
}

# Cartella nuova per il download, che solo Administrators e SYSTEM possono scrivere (ADR 0022).
# In %SystemRoot%\Temp e non in %TEMP%: li' l'utente ha il controllo completo della cartella padre,
# quindi un suo processo non elevato potrebbe rinominare la nostra e metterne un'altra al suo posto
# fra la verifica e l'avvio. In Windows\Temp gli utenti creano ma non elencano, non rinominano e
# non cancellano cio' che non e' loro. Creata gia' con l'ACL, senza ereditare quella di Windows\Temp
# (che lascia agli utenti aggiungere file). OWNER RIGHTS: se il proprietario fosse l'utente e non
# Administrators, non avrebbe il WRITE_DAC implicito per riaprirsela. Prefisso wgt_: la spazza
# Clear-WinGetTempFiles. $Parent e' un parametro per il test, che gira senza elevazione.
function New-UpdateDownloadDir([string]$Parent = (Join-Path $env:SystemRoot 'Temp')) {
    $dir = Join-Path $Parent "wgt_update_$([Guid]::NewGuid().ToString('N'))"
    $acl = New-Object Security.AccessControl.DirectorySecurity
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($r in @(@('S-1-5-32-544', 'FullControl'), @('S-1-5-18', 'FullControl'), @('S-1-3-4', 'ReadAndExecute'))) {
        $acl.AddAccessRule((New-Object Security.AccessControl.FileSystemAccessRule (
            (New-Object Security.Principal.SecurityIdentifier $r[0]), $r[1], 'ContainerInherit, ObjectInherit', 'None', 'Allow')))
    }
    [void][IO.Directory]::CreateDirectory($dir, $acl)
    return $dir
}

function Test-IsSelfPackage($row) {
    if ($null -eq $row -or -not $row.Id) { return $false }
    # Confronto per CONTENUTO e non per uguaglianza: installato dal catalogo l'ID e'
    # "FedeB2160.WinGetStudio", ma installato da un manifest locale winget lo registra
    # come "ARP\User\X64\FedeB2160.WinGetStudio__DefaultSource".
    return $row.Id -like "*$SelfPackageId*"
}

# Release piu' recente, o $null se non c'e' rete o non ci sono release. Se la release non
# ha l'asset $AssetName torna comunque, con Url vuoto. Nessun errore a video: un
# aggiornamento non trovato non e' un guasto. Gira in un runspace, quindi non tocca la UI.
function Get-LatestRelease([string]$Repo, [string]$AssetName = 'WinGetStudio.exe') {
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

        # Asset per NOME esatto, mai per posizione: GitHub elenca gli asset per nome, e dalla
        # 1.11.0 una release ha due .exe. Senza l'asset del proprio canale si torna la release
        # con Url vuoto, cosi' il controllo manuale puo' dire perche' non propone nulla.
        $asset = @($r.assets | Where-Object { $_.name -eq $AssetName })[0]
        return [PSCustomObject]@{
            Tag     = $r.tag_name
            # I tag sono "v1.6.0": la v va tolta per confrontare come versione.
            Version = ($r.tag_name -replace '^[vV]', '')
            Name    = $AssetName
            Url     = if ($asset) { $asset.browser_download_url } else { $null }
            Size    = if ($asset) { $asset.size } else { 0 }
            # digest = "sha256:abc..." quando GitHub lo espone; serve a verificare il file
            # scaricato prima di eseguirlo.
            Sha256  = if ($asset -and $asset.digest -match '^sha256:(.+)$') { $Matches[1] } else { $null }
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

# Installato da winget come pacchetto "portable"? Allora l'exe sta dentro la cartella che
# winget gestisce, e sostituirlo da soli rompe l'installazione: winget ha registrato lo
# SHA256 del file, quindi dopo un auto-update considera il pacchetto modificato e rifiuta
# upgrade e uninstall senza --force; il ".old" lasciato accanto gli impedisce di ripulire
# la cartella, perche' non e' un file che ha installato lui; e la voce di uninstall continua
# a dichiarare la versione vecchia, cosi' un "winget install" risponde gia-presente.
# Risultato: l'app non si avvia piu' e non si reinstalla. In questo caso l'aggiornamento
# spetta a winget, non a noi.
function Test-IsWinGetPortable {
    return (Get-InstallChannel) -eq 'winget-portable'
}

# Cartella in cui l'installer ha messo l'app, o $null se non e' installata.
# Vista Registry32 esplicita: l'exe di ps2exe e' AnyCPU e gira a 64 bit, quindi HKLM:\ leggerebbe
# la vista a 64 bit, dove la voce del setup x86 non c'e'; la copia installata si crederebbe
# portable e si sostituirebbe da sola. Registry32 va bene anche da un processo a 32 bit.
function Get-InstalledLocation {
    try {
        $hklm = [Microsoft.Win32.RegistryKey]::OpenBaseKey('LocalMachine', 'Registry32')
        $k = $hklm.OpenSubKey("SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\$($InnoAppId)_is1")
        if (-not $k) { return $null }
        try { return $k.GetValue('InstallLocation') } finally { $k.Close(); $hklm.Close() }
    }
    catch { return $null }
}

# Come e' arrivata qui questa copia, quindi come si aggiorna:
#   source          da .ps1: niente auto-update, si usa git
#   winget-portable pacchetto portable di winget: si aggiorna solo con winget
#   installed       installata col setup (a mano o da winget): si aggiorna col setup
#   portable        exe copiato a mano: si rinomina e si sostituisce
# Parametri con i valori veri come default: il test passa percorsi finti.
function Get-InstallChannel([string]$ExePath = (Get-RunningExePath), [string]$InstallLocation = (Get-InstalledLocation)) {
    if (-not $ExePath) { return 'source' }
    if ($ExePath -like '*\Microsoft\WinGet\Packages\*') { return 'winget-portable' }
    if ($InstallLocation -and
        [IO.Path]::GetDirectoryName($ExePath).TrimEnd('\') -ieq $InstallLocation.TrimEnd('\')) { return 'installed' }
    return 'portable'
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
    $channel = Get-InstallChannel
    if ($channel -eq 'source') {
        if ($Manual) { $TxtUpdateStatus.Text = 'Updates apply to the compiled exe only; from source use git.' }
        return
    }
    # Non si propone nulla: il pulsante di aggiornamento non deve nemmeno comparire.
    if ($channel -eq 'winget-portable') {
        if ($Manual) { $TxtUpdateStatus.Text = "Installed with winget: update with 'winget upgrade $SelfPackageId'." }
        return
    }
    # Il controllo AUTOMATICO si puo' spegnere; quello chiesto dal pulsante no — chi lo premette
    # lo sta chiedendo adesso.
    if (-not $Manual -and -not $ChkAutoCheck.IsChecked) { return }
    # Nessuna guardia sullo stato occupato: si parla solo con GitHub, e all'avvio Load-Upgrades
    # lo alza nello stesso handler, quindi una guardia qui faceva tacere il controllo SEMPRE
    # (dalla v1.9.0). Il pulsante resta spento finche' la scansione non finisce (handler busy).

    if ($Manual) {
        $TxtUpdateStatus.Text        = 'Checking...'
        $UpdateSpinner.Visibility    = [System.Windows.Visibility]::Visible
        $BtnCheckUpdate.IsEnabled    = $false
    }
    # $script: e NON una locale: OnDone gira sul thread UI e non vede le variabili locali
    # di questa funzione. Con "$manual" locale il controllo manuale non riportava nulla.
    $script:manualCheck = [bool]$Manual
    # Il canale decide quale file scaricare; Start-SelfUpdate lo rilegge da qui.
    $script:updateChannel = $channel
    $asset = if ($channel -eq 'installed') { $SetupAssetName } else { 'WinGetStudio.exe' }

    [void](Start-BackgroundJob -Functions 'Get-LatestRelease' `
        -Vars @{ repo = $UpdateRepo; asset = $asset } `
        -Script { Get-LatestRelease $repo $asset } `
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
            if (-not $rel.Url) {
                if ($manual) { $TxtUpdateStatus.Text = "$($rel.Tag) is out, but without $($rel.Name): nothing to update with." }
                return
            }

            $script:pendingUpdate = $rel
            $BtnUpdateApp.Content    = "Update to $($rel.Tag)"
            $BtnUpdateApp.ToolTip    = if ($script:updateChannel -eq 'installed') {
                "Download the installer $($rel.Name) ($([int]($rel.Size / 1024)) KB): WinGet Studio closes, updates and reopens"
            } else { "Download $($rel.Name) ($([int]($rel.Size / 1024)) KB) from GitHub and restart" }
            $BtnUpdateApp.Visibility = [System.Windows.Visibility]::Visible
            # Il pulsante dice gia' quale versione c'e': una scritta accanto la ripeterebbe.
            $TxtUpdateStatus.Text    = ''
            Write-Log "Version $($rel.Tag) is available (you have v$AppVersion)."
        })
}

# Scarica, verifica e sostituisce. Chiamata dal pulsante, dopo conferma.
function Start-SelfUpdate {
    $rel = $script:pendingUpdate
    # Test-WinGetBusy e non isBusy: questa funzione finisce sostituendo l'eseguibile e
    # chiudendo la finestra, e farlo mentre un runspace sta ancora dentro winget e' l'ultima
    # cosa da fare. Il controllo degli aggiornamenti (Start-UpdateCheck) invece non ha guardie:
    # parla solo con GitHub e non tocca niente.
    if (-not $rel -or (Test-WinGetBusy) -or (Test-IsWinGetPortable)) { return }
    $exe = Get-RunningExePath
    if (-not $exe) { return }
    # Il setup si esegue con privilegi di amministratore: senza digest non si scarica nemmeno.
    $installed = $script:updateChannel -eq 'installed'
    if ($installed -and -not $rel.Sha256) {
        Write-Log "Update refused: $($rel.Tag) publishes no checksum for $($rel.Name), and the installer would run as administrator."
        return
    }

    $answer = Show-AppDialog -Text ($(if ($installed) { "Download the $($rel.Tag) installer and update WinGet Studio? It closes, updates and reopens.`n`n" }
          else { "Download $($rel.Tag) and restart WinGet Studio?`n`n" }) +
        "$($rel.Name) - $([int]($rel.Size / 1024)) KB`nFrom: $($rel.Url)`n`n" +
        $(if ($rel.Sha256) { "The download is checked against the SHA-256 published with the release, and must carry the WinGet Studio signature." }
          else { "WARNING: this release publishes no checksum, so the download is checked against the WinGet Studio signature only." })) `
        -Title 'Update WinGet Studio' `
        -Button ([System.Windows.MessageBoxButton]::YesNo) `
        -Image ([System.Windows.MessageBoxImage]::Question) `
        -Default ([System.Windows.MessageBoxResult]::No)
    if ($answer -ne [System.Windows.MessageBoxResult]::Yes) { return }

    # Una cartella che un processo non elevato non puo' toccare: il file verificato e' quello che
    # si esegue (ADR 0022).
    try { $tmp = Join-Path (New-UpdateDownloadDir) $rel.Name }
    catch {
        Write-Log "Update FAILED: the download folder could not be created: $($_.Exception.Message)"
        return
    }
    Set-AppBusy $true
    Write-Log "Downloading $($rel.Name) ..."

    # OnDone gira sul thread UI e NON vede le variabili locali di questa funzione: con
    # $exe, $tmp e $rel locali arrivavano vuote, e l'aggiornamento moriva su
    # "Remove-Item: Path e' null" e "Start-Process: FilePath e' null".
    # Stesso inciampo di scope documentato per i job in DEVELOPMENT.md.
    $script:updExe = $exe
    $script:updTmp = $tmp
    $script:updRel = $rel
    $script:updInstalled = $installed

    [void](Start-BackgroundJob -Functions 'Test-UpdateSignature' `
        -Vars @{ url = $rel.Url; dest = $tmp; expected = $rel.Sha256; signer = $UpdateSignerThumbprint } `
        -Script {
            try {
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing `
                    -Headers @{ 'User-Agent' = 'WinGetStudio' } -TimeoutSec 300
                $hash = (Get-FileHash $dest -Algorithm SHA256).Hash
                # Il confronto e' il presidio principale: si sta per ESEGUIRE questo file.
                # Senza checksum pubblicato non si puo' verificare, e lo si dice.
                $okHash = (-not $expected) -or ($hash -eq $expected.ToUpperInvariant())
                # Poi la firma, in ogni canale: il digest arriva da GitHub come il file, quindi con
                # l'account GitHub compromesso non protegge. La chiave privata non sta su GitHub.
                $sig   = Get-AuthenticodeSignature -LiteralPath $dest
                $okSig = Test-UpdateSignature $sig $signer
                [PSCustomObject]@{ Ok = $okHash -and $okSig; HashOk = $okHash; Hash = $hash; Verified = [bool]$expected
                                   Signature = "$($sig.Status)"; Signer = "$($sig.SignerCertificate.Subject)" }
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
                $why = if (-not $d) { 'the download job returned nothing' }
                       elseif ($d.Error) { $d.Error }
                       elseif (-not $d.HashOk) { 'checksum mismatch, the download was discarded' }
                       else { "the download does not carry the WinGet Studio signature ($($d.Signature)$(if ($d.Signer) { ", signed by $($d.Signer)" })), it was discarded" }
                Write-Log "Update FAILED: $why."
                if ($tmp) { Remove-Item -LiteralPath (Split-Path $tmp) -Recurse -Force -ErrorAction SilentlyContinue }
                Set-AppBusy $false
                return
            }
            Write-Log $(if ($d.Verified) { "Download verified (SHA-256 matches, signed by WinGet Studio)." } else { "Download verified (signed by WinGet Studio; no checksum to compare)." })

            if ($script:updInstalled) {
                # Il setup chiude l'app (Restart Manager), sostituisce i file e la riapre. Gia'
                # elevati: nessun secondo UAC. Il file resta nella cartella protetta in
                # %SystemRoot%\Temp e la spazza Clear-WinGetTempFiles al prossimo avvio (prefisso wgt_).
                $log = [IO.Path]::Combine([IO.Path]::GetTempPath(), 'WinGetStudio-update.log')
                Write-Log "Running $($rel.Name); if the update fails, its log is $log"
                try {
                    Start-Process -FilePath $tmp -ArgumentList "/SILENT /CLOSEAPPLICATIONS /relaunch=1 `"/LOG=$log`"" -ErrorAction Stop
                }
                catch {
                    Write-Log "Update FAILED: the installer did not start: $($_.Exception.Message)"
                    Set-AppBusy $false
                    return
                }
                $window.Close()
                return
            }

            try {
                # Il file in esecuzione non si sovrascrive, ma si rinomina: dopo lo
                # spostamento il suo percorso e' libero per il file nuovo.
                Move-Item -LiteralPath $exe -Destination "$exe.old" -Force
                # Copia e non spostamento: sullo stesso volume il file spostato si porterebbe l'ACL
                # della cartella protetta (solo Administrators e SYSTEM), ed Explorer, che non e'
                # elevato, non potrebbe piu' aprirlo. La copia prende quella della cartella dell'exe;
                # la cartella protetta la spazza Clear-WinGetTempFiles all'avvio che segue.
                Copy-Item -LiteralPath $tmp -Destination $exe -Force
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
    $ChkAutoCheck.IsChecked = [bool][int](Get-Pref 'CheckAtStartup' 1)
    $ChkAutoCheck.Add_Click({ Set-Pref 'CheckAtStartup' ([int][bool]$ChkAutoCheck.IsChecked) })
    $BtnUpdateApp.Add_Click({ Start-SelfUpdate })
    $BtnCheckUpdate.Add_Click({ Start-UpdateCheck -Manual })
    Register-BusyHandler {
        param($busy)
        $BtnUpdateApp.IsEnabled   = -not $busy
        $BtnCheckUpdate.IsEnabled = -not $busy
    }
}
