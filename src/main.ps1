<#
    main.ps1 — ENTRY POINT
    ----------------------
    Tool WPF standalone per gestire i pacchetti winget. Richiede privilegi
    amministratore (self-elevation + manifest UAC generato da ps2exe).

    Qui c'e' SOLO l'avvio: versione, elevazione, caricamento dei moduli, Start-App.
    Tutta la logica sta in src\modules\*.ps1, la UI in ..\ui\*.xaml.

    Questo file esiste perche' ps2exe accetta un solo file di ingresso e la
    self-elevation deve girare prima di ogni altra cosa.

    Compilazione: build.bat (oppure src\build.ps1) — vedi README.md
#>

# ------------------------------------------------------------------
# VERSIONE
# ------------------------------------------------------------------
# UNICA fonte di verita': finisce nel titolo della finestra come "[x.y.z]" e, letta
# da build.ps1 con questa stessa regex, nelle proprieta' dell'exe (scheda Dettagli).
# Aggiornarla qui e basta; Test-Ui.ps1 verifica che la regex la trovi ancora.
$AppVersion = '1.9.0'

# ------------------------------------------------------------------
# SELF-ELEVATION (fallback al manifest UAC generato da ps2exe)
# ------------------------------------------------------------------
# Se lo script/exe non gira come amministratore, si rilancia elevato e termina.
$identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($identity)
$isAdmin   = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if (-not $isAdmin) {
    try {
        # GetCommandLineArgs()[0] = host che esegue (powershell.exe oppure il .exe compilato)
        $exe = [Environment]::GetCommandLineArgs()[0]

        if ($exe -match '(?i)powershell(\.exe)?$|pwsh(\.exe)?$') {
            # Eseguito come .ps1 tramite PowerShell: rilancio passando il percorso dello script
            $scriptPath = $PSCommandPath
            Start-Process -FilePath $exe -Verb RunAs `
                -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
        }
        else {
            # Eseguito come .exe compilato: rilancio l'exe stesso elevato
            Start-Process -FilePath $exe -Verb RunAs
        }
    }
    catch {
        # L'utente ha annullato il prompt UAC (o errore): esci silenziosamente
    }
    exit
}

# ------------------------------------------------------------------
# RISORSE DI CORREDO
# ------------------------------------------------------------------
# Cartella base: $PSScriptRoot e' vuoto nell'exe compilato con ps2exe,
# quindi si ripiega su PSCommandPath o sul percorso del processo.
$baseDir = if ($PSScriptRoot) { $PSScriptRoot }
           elseif ($PSCommandPath) { Split-Path -Parent $PSCommandPath }
           else { Split-Path -Parent ([Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }

# Cerca un file di corredo in tre posti: nel layout del repo (questo script sta in src\,
# le risorse in ui\ e assets\ un livello sopra, i moduli in src\modules\), accanto
# all'exe con la stessa struttura, oppure sciolto accanto all'exe. Torna $null se non c'e'.
# Serve al caricamento dei moduli, quindi deve stare qui e non in un modulo.
function Resolve-Asset([string]$rel) {
    if (-not $baseDir) { return $null }
    $parent = Split-Path -Parent $baseDir
    $cand = @((Join-Path $baseDir $rel), (Join-Path $baseDir (Split-Path $rel -Leaf)))
    if ($parent) { $cand = @(Join-Path $parent $rel) + $cand }
    foreach ($p in $cand) { if (Test-Path $p) { return $p } }
    return $null
}

# ------------------------------------------------------------------
# MODULI
# ------------------------------------------------------------------
# L'ORDINE conta solo per il codice a livello di file (Add-Type, variabili): le
# funzioni si risolvono a runtime. App.Bootstrap va per ultimo, e' l'orchestratore.
$moduleNames = @(
    'WinGet.Exec.ps1'
    'WinGet.Parse.ps1'
    'App.Ui.ps1'
    'App.Jobs.ps1'
    'App.Theme.ps1'
    'App.Pins.ps1'
    'App.Backup.ps1'
    'App.Update.ps1'
    'App.Settings.ps1'
    'Tab.Updates.ps1'
    'Tab.Install.ps1'
    'Tab.Installed.ps1'
    'App.Bootstrap.ps1'
)

# build.ps1 sostituisce il marcatore qui sotto col contenuto dei moduli, cosi' l'exe
# resta un file solo. Il marcatore e' una RIGA DI COMMENTO: eseguito come .ps1 resta
# innocuo e i moduli vengono dot-sourced da disco dal blocco successivo.
###MODULES###

# Get-WinGetPath e' la prima funzione del primo modulo: se manca, il marcatore non e'
# stato sostituito (esecuzione come .ps1) e i moduli si caricano da disco.
# Il dot-source NON crea uno scope proprio: i moduli vedono le variabili di questo file
# e viceversa, esattamente come nel caso concatenato.
if (-not (Get-Command Get-WinGetPath -ErrorAction SilentlyContinue)) {
    foreach ($m in $moduleNames) {
        $p = Resolve-Asset "modules\$m"
        if (-not $p) { throw "Module not found: $m" }
        . $p
    }
}

Start-App












