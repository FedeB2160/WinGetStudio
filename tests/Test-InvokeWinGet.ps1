<#
    Test-InvokeWinGet.ps1
    ---------------------
    Verifica eseguibile delle due cause radice corrette in WinGetUpdateTool.ps1.
    Non serve admin, non installa nulla.

        powershell -ExecutionPolicy Bypass -File .\tests\Test-InvokeWinGet.ps1

    Esce 0 se tutto passa, 1 al primo assert fallito.
#>

$ErrorActionPreference = 'Stop'
$failures = 0
function Check([string]$what, [bool]$ok, [string]$detail = '') {
    if ($ok) { Write-Host "  OK   $what" -ForegroundColor Green }
    else     { Write-Host "  FAIL $what $detail" -ForegroundColor Red; $script:failures++ }
}

# Estrae Invoke-WinGet dallo script reale (via AST): il test gira sul codice di
# produzione, non su una copia che puo' divergere.
$src = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\WinGetUpdateTool.ps1'
$ast = [System.Management.Automation.Language.Parser]::ParseFile($src, [ref]$null, [ref]$null)
$fn  = $ast.Find({
    param($n)
    $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-WinGet'
}, $true)
if (-not $fn) { Write-Host "Invoke-WinGet non trovata in $src" -ForegroundColor Red; exit 1 }
Invoke-Expression $fn.Extent.Text

# ------------------------------------------------------------------
Write-Host "`n1) Attesa legata al processo, non alla pipe" -ForegroundColor Cyan
# Un figlio staccato eredita il handle di stdout e resta vivo ~40s: con
# '& cmd | Out-String' la pipe non arriva a EOF e l'attesa sarebbe infinita
# (il bug degli spinner eterni). Invoke-WinGet deve ritornare all'uscita di cmd.
$sw = [Diagnostics.Stopwatch]::StartNew()
$r  = Invoke-WinGet 'cmd.exe' '/c start /b ping -n 40 127.0.0.1'
$sw.Stop()
$pingAlive = @(Get-Process -Name PING -ErrorAction SilentlyContinue).Count -gt 0

Check "ritorna senza aspettare il figlio ($([int]$sw.Elapsed.TotalSeconds)s)" ($sw.Elapsed.TotalSeconds -lt 15)
Check "exit code del processo padre disponibile (=$($r.ExitCode))" ($r.ExitCode -eq 0)
Check "il figlio era ancora vivo al ritorno" $pingAlive `
      "(se falso il test non prova nulla: il figlio e' morto troppo presto)"
Get-Process -Name PING -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

# ------------------------------------------------------------------
Write-Host "`n2) Overload di Dispatcher.BeginInvoke" -ForegroundColor Cyan
# BeginInvoke non ha overload (Delegate, DispatcherPriority): la forma con la stringa
# in seconda posizione passa 'Background' COME ARGOMENTO a un delegate senza parametri
# -> TargetParameterCountException a dispatch. Si riconosce dalla priorita' risolta.
Add-Type -AssemblyName WindowsBase
$d = [System.Windows.Threading.Dispatcher]::CurrentDispatcher
$bad  = $d.BeginInvoke([action]{ }, 'Background')
$good = $d.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [action]{ })
Check "forma buggata riconoscibile (Priority=$($bad.Priority), attesa Normal)" ($bad.Priority -eq 'Normal')
Check "forma corretta priority-first (Priority=$($good.Priority))" ($good.Priority -eq 'Background')

# Solo codice, non commenti (il commento esplicativo cita la forma sbagliata).
$badCalls = @(Get-Content $src | Where-Object { $_ -notmatch '^\s*#' -and $_ -match 'BeginInvoke\(\[action\]' })
Check "nessun BeginInvoke([action]...) nel codice dello script" ($badCalls.Count -eq 0) $badCalls

# ------------------------------------------------------------------
Write-Host "`n3) Smoke test su winget" -ForegroundColor Cyan
$wg = Get-Command winget -ErrorAction SilentlyContinue
if (-not $wg) { Write-Host "  SKIP winget non presente" -ForegroundColor Yellow }
else {
    $v = Invoke-WinGet $wg.Source '--version'
    Check "winget --version exit 0 (=$($v.ExitCode))" ($v.ExitCode -eq 0)
    Check "output catturato ('$($v.Output.Trim())')" (-not [string]::IsNullOrWhiteSpace($v.Output))
}

# ------------------------------------------------------------------
if ($failures -eq 0) { Write-Host "`nTutti i test passati.`n" -ForegroundColor Green; exit 0 }
Write-Host "`n$failures test falliti.`n" -ForegroundColor Red
exit 1
