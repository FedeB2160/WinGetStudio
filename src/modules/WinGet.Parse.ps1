<#
    WinGet.Parse.ps1 — lettura dell'output tabellare di winget.

    winget stampa TABELLE A LARGHEZZA FISSA localizzate. Questo modulo le trasforma
    in oggetti; l'esecuzione dei comandi sta in WinGet.Exec.ps1.

    Caricato da src\main.ps1: dot-source come .ps1, concatenato nell'exe al posto
    del marcatore ###MODULES###.
#>

# ------------------------------------------------------------------
# PARSING OUTPUT WINGET (punto critico)
# ------------------------------------------------------------------
# winget stampa una TABELLA A LARGHEZZA FISSA. I nomi contengono spazi, quindi
# NON si puo' fare split su spazi: si parsa per posizione delle colonne, ricavata
# dagli offset della riga di header.
#
# Ritorna, per ogni riga di dati, l'ARRAY DEI CAMPI nell'ordine delle colonne. Sono i
# chiamanti a sapere cosa significano, perche' cambia col comando: la 4a colonna e'
# "Disponibile" in upgrade, "Corrispondenza" in search, "Origine" in list. Le PRIME TRE
# (Nome, Id, Versione) sono le stesse in tutti e tre, ed e' tutto cio' che serve a
# search e list.
# NB: il numero di colonne varia anche a parita' di comando — "search vlc" ha
# Corrispondenza, "search ab --count 5" no. Mai contare sulle colonne oltre la terza.
function Get-WinGetTable([string]$raw) {
    # Normalizza in righe; winget usa \r di progresso -> tieni solo l'ultimo segmento
    $lines = $raw -split "`r`n|`n" | ForEach-Object { ($_ -split "`r")[-1] }

    # Estrae in sicurezza una sottostringa [start, end) gestendo righe corte.
    # $end -lt 0 significa "fino a fine riga" (ultima colonna).
    function Get-Field([string]$line, [int]$start, [int]$end) {
        if ($start -lt 0 -or $start -ge $line.Length) { return '' }
        if ($end -lt 0 -or $end -gt $line.Length) { $end = $line.Length }
        if ($end -le $start) { return '' }
        return $line.Substring($start, $end - $start).Trim()
    }

    # INDIPENDENTE DALLA LINGUA: winget localizza gli header (Nome/ID/Versione/...)
    # ma la riga separatore e' sempre una sequenza di trattini. La usiamo come ancora:
    # header = riga subito prima del separatore; dati = righe subito dopo.
    # MULTI-TABELLA: l'output puo' contenere PIU' tabelle — dopo gli upgrade normali
    # winget ne stampa una seconda per i pacchetti che richiedono targeting esplicito
    # ("...ma e' necessario un targeting esplicito per l'aggiornamento"), con larghezze
    # di colonna PROPRIE. Con una sola ancora fissa quella tabella veniva letta con gli
    # offset della prima: il suo header finiva in griglia come riga fantasma e i suoi
    # pacchetti (es. Discord) sparivano. Quindi si ri-ancora a ogni separatore.
    $results = New-Object System.Collections.ArrayList
    $cols = $null   # offset di inizio colonna della tabella in corso

    for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ([string]::IsNullOrWhiteSpace($line)) { continue }

        # Separatore: apre una tabella, gli offset arrivano dalla riga di header sopra.
        if ($line.Trim() -match '^-{3,}$') {
            $cols = $null   # tabella inattesa fino a prova contraria
            $header = if ($i -gt 0) { $lines[$i - 1] } else { '' }

            # Offset di inizio colonna: posizioni nella riga header dove inizia un token
            # (carattere non-spazio preceduto da spazio o inizio riga).
            $starts = New-Object System.Collections.ArrayList
            for ($c = 0; $c -lt $header.Length; $c++) {
                $isStart = ($header[$c] -ne ' ') -and ($c -eq 0 -or $header[$c-1] -eq ' ')
                if ($isStart) { [void]$starts.Add($c) }
            }
            # Soglia a TRE, non quattro: "winget list --source winget" stampa solo
            # Nome|Id|Versione e con la soglia a 4 la tabella veniva scartata in silenzio.
            if ($starts.Count -ge 3) { $cols = $starts }
            continue
        }

        if (-not $cols) { continue }   # fuori da una tabella riconosciuta
        # Riga di header (la prossima e' il separatore): non e' un dato.
        if ($i + 1 -lt $lines.Count -and $lines[$i + 1].Trim() -match '^-{3,}$') { continue }

        # Filtro riepilogo/prose localizzata ("N aggiornamenti disponibili.", la frase
        # sul targeting esplicito, ecc.): una riga dati rispetta la griglia, cioe' ogni
        # inizio colonna e' preceduto da almeno uno spazio di padding. Una frase no.
        # NB: NON si filtra sul numero di token separati da 2+ spazi — nella seconda
        # tabella le colonne sono strette e distano un solo spazio.
        $aligned = $true
        for ($k = 1; $k -lt $cols.Count; $k++) {
            $o = $cols[$k]
            if ($o -gt 0 -and $o -le $line.Length -and $line[$o - 1] -ne ' ') { $aligned = $false; break }
        }
        if (-not $aligned) { continue }

        # Un campo per colonna: da un offset al successivo, l'ultimo fino a fine riga.
        $fields = @(for ($k = 0; $k -lt $cols.Count; $k++) {
            $end = if ($k + 1 -lt $cols.Count) { $cols[$k + 1] } else { -1 }
            Get-Field $line $cols[$k] $end
        })

        # Id vuoto: non e' una riga di dati.
        if ([string]::IsNullOrWhiteSpace($fields[1])) { continue }

        [void]$results.Add($fields)
    }
    return $results
}

# Ricerca nel catalogo. Colonne: Nome | Id | Versione | [Corrispondenza] | [Origine] —
# si usano solo le prime tre, le altre compaiono o no a seconda del risultato.
#
# --source winget: interroga il solo indice LOCALE (~0.4s). Con msstore la stessa ricerca
#   va in rete e passa a ~5s, troppo per aggiornare l'elenco mentre si digita.
# --count: senza un tetto una query di 2-3 lettere torna oltre mille righe (misurato:
#   "ab" -> 1288) e la griglia annega.
function Get-WinGetSearch([string]$Query, [bool]$IncludeStore = $false, [int]$Count = 25) {
    if ([string]::IsNullOrWhiteSpace($Query)) { return @() }
    $wgArgs = @('search', $Query, '--count', "$Count", '--accept-source-agreements')
    if (-not $IncludeStore) { $wgArgs += @('--source', 'winget') }
    $raw = & winget @wgArgs 2>&1 | Out-String -Width 4096

    $results = New-Object System.Collections.ArrayList
    foreach ($f in Get-WinGetTable $raw) {
        [void]$results.Add([WgtRow]@{
            Selected = $false
            Name     = $f[0]
            Id       = $f[1]
            Version  = $f[2]
        })
    }
    return $results
}

# Inventario dei pacchetti installati. Colonne: Nome | Id | Versione | [Origine].
# ATTENZIONE: la quarta colonna qui e' Origine, NON "Disponibile" come in upgrade.
# Include anche cio' che non e' stato installato con winget: quei pacchetti hanno un Id
# di tipo "ARP\Machine\X64\Nome Prodotto" (con spazi dentro, del tutto legittimi) e
# Origine vuota.
function Get-WinGetInstalled {
    $raw = & winget list --accept-source-agreements 2>&1 | Out-String -Width 4096

    $results = New-Object System.Collections.ArrayList
    foreach ($f in Get-WinGetTable $raw) {
        # "> 8.12.30.21" -> "8.12.30.21": il ">" segnala che esiste un aggiornamento, e di
        # quello si occupa la scheda Updates.
        [void]$results.Add([WgtRow]@{
            Selected = $false
            Name     = $f[0]
            Id       = $f[1]
            Version  = ($f[2] -replace '^>\s*', '')
        })
    }
    return $results
}

# Elenco degli upgrade disponibili. Colonne: Nome | Id | Versione | Disponibile | [Origine].
function Get-WinGetUpgrades([bool]$IncludeUnknown = $false) {
    # --include-unknown: include pacchetti con versione installata sconosciuta (opzionale,
    #   la spunta in alto lo comanda: senza, winget elenca solo cio' di cui sa la versione)
    # --accept-source-agreements: evita prompt interattivi al primo uso della sorgente
    $wgArgs = @('upgrade', '--accept-source-agreements')
    if ($IncludeUnknown) { $wgArgs += '--include-unknown' }
    # -Width alto: senza console (exe -noConsole) o con finestra stretta Out-String
    # manderebbe a capo le righe alla larghezza dell'host, spezzando la tabella.
    $raw = & winget @wgArgs 2>&1 | Out-String -Width 4096

    $results = New-Object System.Collections.ArrayList
    foreach ($f in Get-WinGetTable $raw) {
        if ($f.Count -lt 4) { continue }   # senza la colonna Disponibile non e' un upgrade
        [void]$results.Add([WgtRow]@{
            Selected     = $false
            Name         = $f[0]
            Id           = $f[1]
            Version      = $f[2]
            Available    = $f[3]
        })
    }
    return $results
}
