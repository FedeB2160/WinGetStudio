<#
    sign.ps1 — firma un file con il certificato indicato, con marca temporale se il server
    risponde. Lo usano build.ps1 per l'exe e Inno Setup (SignTool) per setup e disinstallatore:
    una sola implementazione della firma per tre file.
    Esce con errore se la firma non e' stata applicata (Inno si ferma su exit code non zero).
#>
param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Thumbprint)
$ErrorActionPreference = 'Stop'
$cert = Get-ChildItem Cert:\CurrentUser\My, Cert:\LocalMachine\My -CodeSigningCert -ErrorAction SilentlyContinue |
        Where-Object { $_.Thumbprint -eq $Thumbprint } | Select-Object -First 1
if (-not $cert) { throw "Certificato $Thumbprint non trovato negli archivi personali" }

# -TimestampServer: senza marca temporale la firma diventa invalida alla scadenza del
# certificato; con la marca resta valida per sempre. Richiede rete.
$sig = Set-AuthenticodeSignature -LiteralPath $Path -Certificate $cert -HashAlgorithm SHA256 `
           -TimestampServer 'http://timestamp.digicert.com' -ErrorAction SilentlyContinue
# Il timestamp si verifica guardando il TIMESTAMP, non lo Status: con un self-signed lo Status
# non sara' mai 'Valid' su una macchina che non lo considera fidato.
if ($sig -and -not $sig.TimeStamperCertificate) {
    Write-Host "Marca temporale non applicata (server non raggiungibile): la firma scadra' col certificato." -ForegroundColor Yellow
    $sig = Set-AuthenticodeSignature -LiteralPath $Path -Certificate $cert -HashAlgorithm SHA256
}
if (-not $sig -or -not $sig.SignerCertificate) { throw "Firma non applicata a $Path" }
$stamp = if ($sig.TimeStamperCertificate) { ', con marca temporale' } else { '' }
Write-Host "Firmato $(Split-Path $Path -Leaf): $($cert.Subject)$stamp" -ForegroundColor Cyan
# 'UnknownError' con un self-signed e' NORMALE: la firma c'e', la radice non e' fidata qui.
if ($sig.Status -ne 'Valid') { Write-Host "  Catena non fidata su questa macchina (normale con un self-signed): $($sig.Status)" -ForegroundColor Yellow }
