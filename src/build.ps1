<#
    build.ps1 — compila WinGetUpdateTool.ps1 in un .exe con elevazione UAC.
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
$src  = Join-Path $PSScriptRoot 'WinGetUpdateTool.ps1'
$out  = Join-Path $root 'dist\WinGetUpdateTool.exe'
$icon = Join-Path $root 'assets\icon.ico'
New-Item -ItemType Directory -Force -Path (Split-Path $out) | Out-Null

# I file .xaml vivono in ui\ per poterli editare; qui vengono iniettati al posto dei
# marcatori ###nome### cosi' l'exe resta un file solo (a runtime lo script preferisce
# comunque il .xaml su disco, se presente accanto all'eseguibile o in un suo ui\).
$code = Get-Content $src -Raw -Encoding UTF8
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
$src = Join-Path ([IO.Path]::GetTempPath()) 'WinGetUpdateTool.build.ps1'
Set-Content -LiteralPath $src -Value $code -Encoding UTF8

# -requireAdmin  -> manifest requireAdministrator (prompt UAC automatico)
# -noConsole     -> nessuna finestra console, solo la UI WPF
# -iconFile      -> icona embeddata (finestra + taskbar + file .exe)
$params = @{
    inputFile   = $src
    outputFile  = $out
    requireAdmin = $true
    noConsole   = $true
    title       = 'WinGet Update Tool'
    product     = 'WinGet Update Tool'
    description = 'Aggiorna pacchetti winget con selezione'
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
Write-Host "`nFatto: $out" -ForegroundColor Green
