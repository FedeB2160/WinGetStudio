<#
    WinGet.Setup.ps1 — winget stesso: installarlo quando manca, mostrarne la versione e
    aggiornarlo dove non ci pensa lo Store (ADR 0019).

    Caricato da src\main.ps1: dot-source come .ps1, concatenato nell'exe al posto
    del marcatore ###MODULES###.
#>

# Versione del pacchetto App Installer, che porta winget, o $null. Si legge dal pacchetto e
# NON con "winget --version": nessun processo winget, quindi gira insieme alla scansione
# (ADR 0003). Dalla 1.28 coincide con la versione di winget (1.29.380.0 = v1.29.380); prima
# App Installer era avanti di 15 minor (1.27 = winget 1.12), e il confronto con l'ultima
# release resta giusto lo stesso.
function Get-WinGetVersion {
    $p = @(Get-AppxPackage Microsoft.DesktopAppInstaller -ErrorAction SilentlyContinue |
           Sort-Object { [version]$_.Version } -Descending)[0]
    if ($p) { return [string]$p.Version }
    return $null
}

# Lo Store aggiorna App Installer da solo, e a delta: se c'e' ed e' libero di farlo, il
# pulsante (oltre 300 MB da GitHub) non serve. "C'e'" non basta: su un PC gestito lo Store
# puo' esserci con gli aggiornamenti spenti (AutoDownload=2) o essere bloccato
# (RemoveWindowsStore=1), e l'etichetta direbbe il falso. Il pacchetto si cerca per QUESTO
# account: se l'admin elevato non ha lo Store, il pulsante aggiorna proprio il suo winget.
# Parametri con i valori veri come default: il test passa casi finti.
function Test-StoreUpdatesWinGet(
    [bool]$HasStore = [bool](Get-AppxPackage Microsoft.WindowsStore -ErrorAction SilentlyContinue),
    $Policy = (Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\WindowsStore' -ErrorAction SilentlyContinue)) {
    if (-not $HasStore) { return $false }
    if ($Policy -and ($Policy.RemoveWindowsStore -eq 1 -or $Policy.AutoDownload -eq 2)) { return $false }
    return $true
}

# Pacchetti di dipendenza per l'architettura di questo Windows. Lo zip della release ha una
# cartella per architettura (x64, x86, arm64); la si cerca a qualunque profondita', perche' la
# struttura dello zip e' gia' cambiata in passato.
function Get-WinGetDependency([string]$Dir, [string]$Arch = $env:PROCESSOR_ARCHITECTURE) {
    $folder = @{ AMD64 = 'x64'; ARM64 = 'arm64'; x86 = 'x86' }[$Arch]
    $files = @(if ($folder) {
        Get-ChildItem -LiteralPath $Dir -Recurse -File | Where-Object { $_.Directory.Name -eq $folder } | ForEach-Object { $_.FullName }
    })
    if (-not $files) { throw "the winget release has no dependencies for architecture '$Arch'" }
    return $files
}

# Scarica App Installer e le sue dipendenze dall'ultima release di microsoft/winget-cli, li
# verifica col SHA-256 che GitHub pubblica e li installa per QUESTO account. Gira in un
# runspace: lancia un'eccezione col motivo se qualcosa va storto. Torna la versione registrata.
function Install-WinGetPackage {
    # Oltre 300 MB: in PowerShell 5.1 la barra di Invoke-WebRequest rallenta il download di
    # ordini di grandezza.
    $ProgressPreference = 'SilentlyContinue'
    # Prefisso wgt_: se il processo muore a meta', la cartella la spazza Clear-WinGetTempFiles.
    $dir = Join-Path ([IO.Path]::GetTempPath()) 'wgt_winget'
    try {
        [void](New-Item -ItemType Directory -Path $dir -Force)
        $files = foreach ($asset in 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle', 'DesktopAppInstaller_Dependencies.zip') {
            $rel = Get-LatestRelease 'microsoft/winget-cli' $asset
            # Si installa come amministratore: senza checksum non si scarica nemmeno.
            if (-not $rel -or -not $rel.Url -or -not $rel.Sha256) { throw "the latest winget release on GitHub has no verifiable $asset" }
            LogUI "   Downloading $asset ($([int]($rel.Size / 1MB)) MB, winget $($rel.Tag))..."
            $dest = Join-Path $dir $asset
            # TLS 1.2 l'ha gia' imposto Get-LatestRelease, per tutto il processo.
            Invoke-WebRequest -Uri $rel.Url -OutFile $dest -UseBasicParsing -Headers @{ 'User-Agent' = 'WinGetStudio' } -TimeoutSec 300
            LogUI "   Verifying $asset..."
            if ((Get-FileHash $dest -Algorithm SHA256).Hash -ne $rel.Sha256.ToUpperInvariant()) {
                throw "checksum mismatch for ${asset}: the download was discarded"
            }
            $dest
        }
        LogUI '   Unpacking the dependencies...'
        Expand-Archive -LiteralPath $files[1] -DestinationPath (Join-Path $dir 'deps') -Force
        LogUI '   Installing App Installer...'
        # Registrazione rinviata e non chiusura forzata: chiudere d'autorita' toccherebbe anche le
        # app che usano le dipendenze, e un winget aperto in un terminale. Cosi' la versione
        # nuova si attiva quando i processi di App Installer ancora aperti terminano.
        Add-AppxPackage -Path $files[0] -DependencyPath (Get-WinGetDependency (Join-Path $dir 'deps')) -DeferRegistrationWhenPackagesAreInUse -ErrorAction Stop
        return Get-WinGetVersion
    }
    finally { Remove-Item -LiteralPath $dir -Recurse -Force -ErrorAction SilentlyContinue }
}

# Installa winget (-Missing: all'avvio, quando manca) o lo aggiorna (pulsante in Settings).
# Prima la conferma, con No come default: si scaricano oltre 300 MB e si installa come
# amministratore. Poi un job con lo stato occupato alzato, perche' si sostituisce winget
# stesso (ADR 0003). Con -Missing prima si prova a registrare l'App Installer gia' presente in
# Windows (profilo nuovo, admin diverso): pochi secondi e nessun download.
function Start-WinGetInstall([switch]$Missing) {
    $rel = $script:pendingWinGet
    if (-not $Missing -and (-not $rel -or (Test-WinGetBusy))) { return }
    $text = if ($Missing) {
        "WinGet Studio needs winget, which is not installed for this account.`n`n" +
        "Install it now? WinGet Studio first registers the App Installer that comes with Windows. " +
        "If there is none, it downloads App Installer and its dependencies from github.com/microsoft/winget-cli " +
        "(a few hundred MB) and checks them against the SHA-256 published with the release.`n`n" +
        "No closes WinGet Studio."
    }
    else {
        "Download winget $($rel.Tag) from github.com/microsoft/winget-cli and install it?`n`n" +
        "App Installer: $([int]($rel.Size / 1MB)) MB, plus its dependencies. " +
        "The download is checked against the SHA-256 published with the release.`n`n" +
        "If winget is running somewhere else, the new version starts when it closes."
    }
    $answer = Show-AppDialog -Text $text `
        -Title $(if ($Missing) { 'winget not found' } else { 'Update winget' }) `
        -Button ([System.Windows.MessageBoxButton]::YesNo) `
        -Image ([System.Windows.MessageBoxImage]::Question) `
        -Default ([System.Windows.MessageBoxResult]::No)
    if ($answer -ne [System.Windows.MessageBoxResult]::Yes) {
        if ($Missing) { $window.Close() }
        return
    }

    Set-AppBusy $true
    $Progress.IsIndeterminate = $true
    Write-Log $(if ($Missing) { 'Installing winget...' } else { "Updating winget to $($rel.Tag)..." })
    # $script: e non locali: OnDone gira sul thread UI e non vede le variabili di qui (ADR 0008).
    $script:wingetMissing = [bool]$Missing
    $script:wingetTarget  = if ($Missing) { $null } else { $rel }
    [void](Start-BackgroundJob -Functions 'Get-LatestRelease', 'Get-WinGetVersion', 'Get-WinGetDependency', 'Install-WinGetPackage', 'Get-WinGetPath' `
        -Vars @{ register = [bool]$Missing } `
        -Script {
            try {
                if ($register) {
                    LogUI '   Registering the App Installer that comes with Windows...'
                    # Procedura Microsoft per App Installer presente ma non registrato per
                    # l'account. Se non c'e' fallisce, e si passa al download.
                    try { Add-AppxPackage -RegisterByFamilyName -MainPackage 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe' -ErrorAction Stop } catch { }
                    if (Get-WinGetPath) { return [PSCustomObject]@{ Ok = $true; Version = Get-WinGetVersion } }
                }
                [PSCustomObject]@{ Ok = $true; Version = Install-WinGetPackage }
            }
            catch { [PSCustomObject]@{ Ok = $false; Error = $_.Exception.Message } }
        } `
        -OnDone {
            param($result)
            $d = @($result)[0]
            $target = $script:wingetTarget
            $Progress.IsIndeterminate = $false
            $script:wingetPath = Get-WinGetPath
            if ($d -and $d.Ok -and $script:wingetPath) {
                Write-Log $(if ($target -and (Test-NewerVersion $target.Version $d.Version)) {
                    "winget $($target.Tag) is installed: it starts when the App Installer processes still running close."
                } else { "winget is ready (App Installer $($d.Version))." })
                $BtnUpdateWinGet.Visibility = [System.Windows.Visibility]::Collapsed
                Set-AppBusy $false
                # Installato: la scansione parte ora. Aggiornato: una riga App Installer nella
                # scheda Updates e' vecchia, e Update resta bloccato fino al Check.
                if ($script:wingetMissing) { Load-Upgrades } else { Set-UpdatesStale }
                Start-WinGetCheck
                return
            }
            $why = if ($d -and $d.Error) { $d.Error }
                   elseif ($d) { 'winget is still not found after the installation' }
                   else { "the installation did not complete ($(@($result).Count) results from the job): see the log" }
            if ($script:wingetMissing) {
                # La finestra resta aperta: il motivo vero sta nel log (anche l'errore di un job
                # morto, scritto da Start-BackgroundJob), e chiudendo sparirebbe con lei. Lo stato
                # occupato resta alzato: senza winget nessun comando deve partire.
                Write-Log "winget could not be installed: $why"
                Show-AppDialog -Text ("winget could not be installed: $why`n`n" +
                    "The log below says what happened. Install App Installer from the Microsoft Store, or from " +
                    "https://github.com/microsoft/winget-cli/releases, then start WinGet Studio again. If it is installed " +
                    "already, check that the winget alias is on in Settings > Apps > Advanced app settings > App execution aliases.") `
                    -Title 'winget not found' `
                    -Button ([System.Windows.MessageBoxButton]::OK) `
                    -Image ([System.Windows.MessageBoxImage]::Error) | Out-Null
                return
            }
            Write-Log "winget update FAILED: $why"
            Set-AppBusy $false
        })
}

# Versione di winget in Settings e, dove lo Store non lo aggiorna, controllo dell'ultima
# release su GitHub con il pulsante di aggiornamento. Nessun processo winget: gira insieme alla
# scansione. GitHub solo col controllo all'avvio acceso o dal pulsante; -Manual come in
# Start-UpdateCheck: riferisce SEMPRE l'esito.
function Start-WinGetCheck([switch]$Manual) {
    # $script: e non una locale: OnDone gira sul thread UI e non la vedrebbe.
    $script:wingetManual = [bool]$Manual
    if ($Manual) { $TxtWinGetStatus.Text = 'Checking...' }
    [void](Start-BackgroundJob -Functions 'Get-WinGetVersion', 'Test-StoreUpdatesWinGet', 'Get-LatestRelease' `
        -Vars @{ online = ($Manual -or [bool]$ChkAutoCheck.IsChecked) } `
        -Script {
            $store = Test-StoreUpdatesWinGet
            [PSCustomObject]@{
                Version = Get-WinGetVersion
                Store   = $store
                Release = if (-not $store -and $online) { Get-LatestRelease 'microsoft/winget-cli' 'Microsoft.DesktopAppInstaller_8wekyb3d8bbwe.msixbundle' }
            }
        } `
        -OnDone {
            param($result)
            $manual = $script:wingetManual
            $r = @($result)[0]
            $TxtWinGetStatus.Text = ''
            if (-not $r) {
                if ($manual) { $TxtWinGetStatus.Text = 'The check did not complete: see the log.' }
                return
            }
            $TxtWinGetVersion.Text = if ($r.Version) { "App Installer $($r.Version)" } else { 'App Installer not found' }
            $TxtWinGetStore.Visibility = if ($r.Store) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed }
            $rel = $r.Release
            if ($r.Store -or -not $r.Version) { return }
            if (-not $rel) {
                if ($manual) { $TxtWinGetStatus.Text = 'No release found (or GitHub not reachable).' }
                return
            }
            if (-not (Test-NewerVersion $rel.Version $r.Version)) {
                if ($manual) { $TxtWinGetStatus.Text = "Up to date (latest published is $($rel.Tag))." }
                return
            }
            if (-not $rel.Url) {
                if ($manual) { $TxtWinGetStatus.Text = "$($rel.Tag) is out, but without $($rel.Name): nothing to update with." }
                return
            }
            $script:pendingWinGet = $rel
            $BtnUpdateWinGet.Content    = "Update to $($rel.Tag)"
            $BtnUpdateWinGet.ToolTip    = "Download App Installer $($rel.Tag) ($([int]($rel.Size / 1MB)) MB) and its dependencies from GitHub, and install them"
            $BtnUpdateWinGet.Visibility = [System.Windows.Visibility]::Visible
            $TxtWinGetStatus.Text       = "$($rel.Tag) is available."
            Write-Log "winget $($rel.Tag) is available (App Installer $($r.Version) is installed)."
        })
}

function Initialize-WinGetSetup {
    $BtnUpdateWinGet.Add_Click({ Start-WinGetInstall })
    # Secondo handler sullo stesso pulsante: "Check for updates" controlla app e winget.
    $BtnCheckUpdate.Add_Click({ Start-WinGetCheck -Manual })
    Register-BusyHandler { param($busy) $BtnUpdateWinGet.IsEnabled = -not $busy }
}
