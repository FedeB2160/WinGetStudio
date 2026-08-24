<#
    App.Pins.ps1 — pin dei pacchetti: blocca un pacchetto agli aggiornamenti finche' il
    pin non viene rimosso.

    Riguarda DUE schede (Updates e Installed), che mostrano lo stesso stato sulle
    proprie righe, quindi vive qui e non dentro una di loro.

    Caricato da src\main.ps1: dot-source come .ps1, concatenato nell'exe al posto
    del marcatore ###MODULES###.
#>

# Segna quali righe hanno un pin. $PinIds arriva da Get-WinGetPins.
# Riguarda entrambe le griglie: lo stesso pacchetto puo' essere elencato in Updates e in
# Installed, e il pin e' lo stesso.
function Set-PinFlags([string[]]$PinIds) {
    $pins = @($PinIds)
    foreach ($row in @($items) + @($installedItems)) {
        $row.Pinned = ($pins -contains $row.Id)
    }
    # I pinnati non sono selezionabili: i contatori vanno ricalcolati.
    Refresh-SelectionState
    Refresh-InstalledState
}

# Rilegge i pin da winget e riallinea i flag. E' l'ULTIMO passo di un'operazione sui pin,
# quindi chiude lei lo stato occupato: winget non va lanciato in parallelo, e lasciare
# questa lettura fuori dallo stato occupato permetteva all'utente di avviare un
# aggiornamento nello stesso istante — due winget insieme, ed e' proprio cosi' che il
# comando pin usciva con exit 1.
# Rilegge invece di dare per buono l'esito: un pin aggiunto da riga di comando deve
# comparire comunque, ed e' winget la fonte di verita'.
function Update-PinFlags {
    [void](Start-BackgroundJob -Functions 'Get-WinGetTable', 'Get-WinGetPins' `
        -Vars @{ wingetPath = $wingetPath } `
        -Script { Get-WinGetPins } `
        -OnDone {
            param($result)
            Set-PinFlags @($result)
            Set-AppBusy $false
        })
}

# Aggiunge o toglie il pin sulle righe passate. $Rows arriva dalla selezione della
# griglia (la riga evidenziata), NON dalle spunte: la spunta di una riga pinnata e'
# disabilitata, quindi con le spunte non si potrebbe piu' togliere un pin.
function Set-PackagePin([object[]]$Rows, [bool]$Pin) {
    if (-not $Rows -or $Rows.Count -eq 0) { return }

    # Solo le righe che cambiano davvero stato: ripinnare un pinnato fa uscire winget
    # con un errore, e sarebbe segnato in rosso nella colonna Result.
    $todo = @($Rows | Where-Object { $_.Pinned -ne $Pin })
    if ($todo.Count -eq 0) {
        Write-Log $(if ($Pin) { "Already pinned." } else { "Not pinned." })
        return
    }

    # Lo stato occupato lo prende Start-WinGetQueue, che e' anche il punto in cui si controlla
    # che non ci sia gia' un winget in corso.
    Start-WinGetQueue -Rows $todo -Verb $(if ($Pin) { 'Pin' } else { 'Unpin' }) `
        -Vars @{ pinVerb = $(if ($Pin) { 'add' } else { 'remove' }) } `
        -ArgsBuilder {
            param($r)
            "pin $pinVerb --id `"$($r.Id)`" -e --accept-source-agreements"
        } -OnDone {
            # Non si sblocca qui: Update-PinFlags lancia un altro winget e deve restare
            # dentro lo stato occupato. Lo sblocco lo fa lei alla fine.
            Update-PinFlags
        }
}
