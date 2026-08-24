<#
    build.ps1 — compila main.ps1 in un .exe con elevazione UAC.
    Esegui in PowerShell (non serve essere admin per compilare).
#>
# Stop al primo errore: senza, un ps2exe mancante lascia passare la build e si finisce
# per distribuire l'exe vecchio credendolo nuovo.
$ErrorActionPreference = 'Stop'

# Installa ps2exe una sola volta (salta se gia' presente)
if (-not (Get-Module -ListAvailable -Name ps2exe)) {
    Write-Host "Installazione modulo ps2exe..." -ForegroundColor Cyan
    Install-Module ps2exe -Scope CurrentUser -Force
}
Import-Module ps2exe

$root = Split-Path -Parent $PSScriptRoot   # build.ps1 sta in src\
$src  = Join-Path $PSScriptRoot 'main.ps1'
$out  = Join-Path $root 'dist\WinGetStudio.exe'
$icon = Join-Path $root 'assets\icon.ico'
New-Item -ItemType Directory -Force -Path (Split-Path $out) | Out-Null

# I file .xaml vivono in ui\ per poterli editare; qui vengono iniettati al posto dei
# marcatori ###nome### cosi' l'exe resta un file solo (a runtime lo script preferisce
# comunque il .xaml su disco, se presente accanto all'eseguibile o in un suo ui\).
$code = Get-Content $src -Raw -Encoding UTF8

# Versione dall'unica fonte di verita' (la costante nello script), cosi' titolo della
# finestra e proprieta' dell'exe non possono divergere. Se la costante viene rinominata
# la build si ferma qui invece di produrre un exe senza versione.
$mv = [regex]::Match($code, "(?m)^\s*\`$AppVersion\s*=\s*'([\d.]+)'")
if (-not $mv.Success) { throw "Costante `$AppVersion non trovata in $src" }
$version = $mv.Groups[1].Value

# I moduli vivono in src\modules\ per poterli leggere e modificare uno per volta; ps2exe
# accetta un solo file di input, quindi qui vengono CONCATENATI al posto del marcatore
# ###MODULES###. La lista NON si ripete qui: si legge da $moduleNames nel bootstrap,
# altrimenti le due copie divergono e un modulo nuovo finisce fuori dall'exe in silenzio.
$mm = [regex]::Match($code, "(?ms)^\s*\`$moduleNames\s*=\s*@\((.*?)^\)")
if (-not $mm.Success) { throw "Array `$moduleNames non trovato in $src" }
$modules = @([regex]::Matches($mm.Groups[1].Value, "'([^']+)'") | ForEach-Object { $_.Groups[1].Value })
if ($modules.Count -eq 0) { throw "`$moduleNames e' vuoto in $src" }
if ($code -notmatch [regex]::Escape('###MODULES###')) { throw "Marcatore ###MODULES### non trovato in $src" }

$moduleCode = foreach ($m in $modules) {
    $path = Join-Path $PSScriptRoot "modules\$m"
    if (-not (Test-Path $path)) { throw "Modulo mancante: $m" }
    "# --- $m ---"
    (Get-Content $path -Raw -Encoding UTF8).TrimEnd()
    ''
}
$code = $code.Replace('###MODULES###', ($moduleCode -join "`r`n"))
Write-Host "Moduli iniettati: $($modules -join ', ')" -ForegroundColor Cyan

foreach ($f in 'UI.xaml', 'Theme.Light.xaml', 'Theme.Dark.xaml') {
    $path = Join-Path $root "ui\$f"
    if (-not (Test-Path $path)) { throw "File mancante: $f" }
    $text = (Get-Content $path -Raw -Encoding UTF8).TrimEnd()
    # Una riga che inizia con '@ chiuderebbe l'here-string: l'unico modo in cui
    # l'iniezione puo' rompersi in silenzio.
    if ($text -match "(?m)^'@") { throw "$f contiene una riga che inizia con '@" }
    if ($code -notmatch [regex]::Escape("###$f###")) { throw "Marcatore ###$f### non trovato in $src" }
    $code = $code.Replace("###$f###", $text)
}
# UTF8 con BOM: senza, PowerShell 5.1 legge il sorgente come ANSI e storpia gli accenti.
$src = Join-Path ([IO.Path]::GetTempPath()) 'WinGetStudio.build.ps1'
Set-Content -LiteralPath $src -Value $code -Encoding UTF8

# -requireAdmin  -> manifest requireAdministrator (prompt UAC automatico)
# -noConsole     -> nessuna finestra console, solo la UI WPF
# -iconFile      -> icona embeddata (finestra + taskbar + file .exe)
$params = @{
    inputFile   = $src
    outputFile  = $out
    requireAdmin = $true
    noConsole   = $true
    title       = 'WinGet Studio'
    product     = 'WinGet Studio'
    description = 'GUI for winget: update, install, uninstall, pin and export packages'
    version     = $version
}
if (Test-Path $icon) { $params.iconFile = $icon }
$before = if (Test-Path $out) { (Get-Item $out).LastWriteTimeUtc } else { [datetime]::MinValue }
try   { Invoke-ps2exe @params }
finally { Remove-Item -LiteralPath $src -Force -ErrorAction SilentlyContinue }

# ps2exe segnala parecchi problemi come errori non terminanti: senza questo controllo
# il messaggio finale direbbe "Fatto" anche con l'exe vecchio ancora sul disco.
if (-not (Test-Path $out) -or (Get-Item $out).LastWriteTimeUtc -le $before) {
    throw "Compilazione fallita: $out non e' stato aggiornato."
}

# ------------------------------------------------------------------
# FIRMA
# ------------------------------------------------------------------
# Quale certificato: prima $env:WINGETSTUDIO_CERT_THUMBPRINT (cosi' si passa a un
# certificato aziendale o commerciale senza toccare questo file), altrimenti il primo
# certificato di code signing valido nell'archivio personale.
# La build NON si ferma se non ne trova: l'exe esce non firmato con un avviso, perche'
# la firma dipende da una chiave privata che non tutte le postazioni hanno.
$signCert = $null
if ($env:WINGETSTUDIO_CERT_THUMBPRINT) {
    $signCert = Get-ChildItem Cert:\CurrentUser\My, Cert:\LocalMachine\My -CodeSigningCert -ErrorAction SilentlyContinue |
                Where-Object { $_.Thumbprint -eq $env:WINGETSTUDIO_CERT_THUMBPRINT } | Select-Object -First 1
    if (-not $signCert) { throw "Certificato $($env:WINGETSTUDIO_CERT_THUMBPRINT) non trovato negli archivi personali" }
}
else {
    $signCert = Get-ChildItem Cert:\CurrentUser\My -CodeSigningCert -ErrorAction SilentlyContinue |
                Where-Object { $_.NotAfter -gt (Get-Date) -and $_.HasPrivateKey } | Select-Object -First 1
}

if (-not $signCert) {
    Write-Host "`nATTENZIONE: nessun certificato di code signing trovato, exe NON firmato." -ForegroundColor Yellow
    Write-Host "  Windows mostrera' 'editore sconosciuto'. Vedi la sezione Signing del README." -ForegroundColor Yellow
}
else {
    # -TimestampServer: senza marca temporale la firma diventa invalida alla scadenza del
    # certificato; con la marca resta valida per sempre, perche' prova che la firma
    # esisteva quando il certificato era ancora buono. Richiede rete.
    $sig = Set-AuthenticodeSignature -FilePath $out -Certificate $signCert `
               -HashAlgorithm SHA256 -TimestampServer 'http://timestamp.digicert.com' `
               -ErrorAction SilentlyContinue

    # Il timestamp si verifica guardando il TIMESTAMP, non lo Status: con un certificato
    # self-signed lo Status non sara' mai 'Valid' su una macchina che non lo considera
    # fidato, e usarlo come test faceva scartare una marca temporale perfettamente
    # applicata per poi rifirmare senza.
    if ($sig -and -not $sig.TimeStamperCertificate) {
        Write-Host "Marca temporale non applicata (server non raggiungibile): la firma scadra' col certificato." -ForegroundColor Yellow
        $sig = Set-AuthenticodeSignature -FilePath $out -Certificate $signCert -HashAlgorithm SHA256
    }

    $stamp = if ($sig.TimeStamperCertificate) { ', con marca temporale' } else { '' }
    if ($sig.Status -eq 'Valid') {
        Write-Host "Firmato: $($signCert.Subject)$stamp" -ForegroundColor Cyan
    }
    else {
        # 'UnknownError' con un self-signed e' NORMALE e non significa firma mancante:
        # la firma c'e', ma questa macchina non riconosce la radice. Diventa 'Valid'
        # dove il certificato pubblico e' fra le autorita' attendibili.
        Write-Host "Firmato: $($signCert.Subject)$stamp" -ForegroundColor Cyan
        Write-Host "  Catena non fidata su questa macchina (normale con un self-signed): $($sig.Status)" -ForegroundColor Yellow
    }
}

Write-Host "`nFatto: $out (versione $version)" -ForegroundColor Green
