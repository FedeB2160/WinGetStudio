<#
    App.Prefs.ps1 — preferenze dell'utente in HKCU.

    Un posto solo per leggere e scrivere le scelte che devono sopravvivere alla chiusura.
    Prima la chiave viveva dentro App.Theme.ps1 e persisteva solo il tema, mentre le altre tre
    scelte dell'utente (Unknown, MS Store, Scope) si perdevano a ogni avvio.

    Il registro NON e' un requisito: se non si riesce a leggere si usa il default, se non si
    riesce a scrivere la scelta vale per questa sessione. Una preferenza non persistita non e'
    un motivo per rifiutare la scelta, ne' per fermare l'avvio.

    I booleani si salvano come 0/1: Set-ItemProperty su un [bool] scrive la stringa
    "True"/"False", che poi andrebbe riconvertita a mano in ogni punto di lettura.

    Caricato da src\main.ps1: dot-source come .ps1, concatenato nell'exe al posto
    del marcatore ###MODULES###.
#>

$PrefsKey = 'HKCU:\Software\WinGetStudio'

# Valore salvato, oppure $Default se non c'e' o non si legge.
function Get-Pref([string]$Name, $Default) {
    try { return (Get-ItemProperty -Path $PrefsKey -Name $Name -ErrorAction Stop).$Name }
    catch { return $Default }
}

# Salva, best effort.
function Set-Pref([string]$Name, $Value) {
    try {
        if (-not (Test-Path $PrefsKey)) { New-Item -Path $PrefsKey -Force | Out-Null }
        Set-ItemProperty -Path $PrefsKey -Name $Name -Value $Value
    }
    catch { }
}
