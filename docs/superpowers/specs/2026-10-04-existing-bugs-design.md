# WinGet Studio: correzione dei difetti già riprodotti

**Data:** 2026-10-04
**Stato:** perimetro richiesto dall’utente; nessuna modifica al codice applicativo.

## Obiettivo

Preparare un piano separato dalla distribuzione installer/portable per correggere i difetti già osservati, mantenendo i risultati validi e rendendo i test indipendenti dai pacchetti installati sulla macchina.

## Evidenze riprodotte

### Errore Winget presentato come elenco vuoto

Le funzioni di lettura in `src/modules/WinGet.Parse.ps1` eseguono `winget`, acquisiscono output con `2>&1 | Out-String` e passano il testo al parser senza controllare `$LASTEXITCODE`.

Riproduzione del 2026-10-04 con `winget` simulato, output `Failed to open source: test fixture` ed exit code `1`:

```text
search rows=0 exit=1
pin rows=0 exit=1
installed rows=0 exit=1
upgrade rows=0 exit=1
```

Il difetto è confermato su ricerca, pin, inventario e aggiornamenti. L’interfaccia può quindi interpretare un errore di Winget come “nessun risultato”, “nessun pacchetto installato”, “nessun pin” o “nessun aggiornamento”.

### Conteggio positivo per export JSON malformato

`Get-ImportPackageCount` in `src/modules/App.Backup.ps1` verifica solo che `Sources` esista e somma il numero di elementi in `Packages`. Non valida la struttura dei pacchetti.

Riproduzione del 2026-10-04 con `{"Sources":[{}]}`:

```text
malformed count=1
```

Un file non conforme viene presentato come importabile con un pacchetto.

### Test UI dipendente da 7-Zip installato

`tests/Test-Ui.ps1:1126-1129` imposta il filtro `7zip` sull’inventario reale e fallisce se il filtro mostra zero righe. La precedente esecuzione ha prodotto `il filtro '7zip' mostra 0 righe su 146`: 7-Zip non era presente nell’inventario. È un difetto del test, non evidenza di un difetto del filtro applicativo.

### Test descritto come headless ma con operazioni Winget reali

L’intestazione di `tests/Test-Ui.ps1` dichiara che il test non tocca Winget. In realtà avvia l’app nascosta con `Start-App -NoShow`, fa ricerche live, esegue `winget pin add/list/remove` e un export reale.

In più, il test seleziona `7zip.7zip` quando presente e il `finally` esegue sempre `winget pin remove`. Se il pacchetto era già pinnato prima del test, il cleanup può rimuovere il pin preesistente. Questo rischio è dedotto dal percorso nel codice; non è stato riprodotto con un pin preesistente.

## Verifiche positive o non conclusive

- `tests/Test-InvokeWinGet.ps1` aveva superato le asserzioni simulate; la verifica Winget live è stata saltata in una sessione non elevata.
- Il ciclo live add/list/remove di un pin è riuscito e il pin è stato rimosso. Non è emerso un difetto nel percorso reale del pin.
- L’export live ha prodotto JSON leggibile. I messaggi relativi a pacchetti non disponibili nella sorgente non dimostrano un difetto del conteggio o dell’import.

## Comportamento richiesto

- Le funzioni di lettura Winget distinguono un comando riuscito da uno fallito. L’interfaccia mostra l’errore e non lo presenta come risultato vuoto.
- Un errore nella lettura dei pin non azzera o falsifica i pin già visualizzati.
- Il conteggio dell’import accetta l’export Winget valido, incluso un export valido senza pacchetti, e restituisce `null` per JSON malformato o struttura `Sources`/`Packages` non valida. L’import non parte per un file non valido.
- Il test del filtro UI usa dati deterministici e non richiede che 7-Zip sia installato.
- Il test UI che usa Winget è esplicitamente opt-in e dichiara prerequisiti ed effetti collaterali.
- Il ciclo live dei pin non modifica né rimuove pin preesistenti; ripristina solo il pin creato dal test.
- Le regressioni vengono coperte dai test esistenti; il test Winget live resta separato e si esegue solo in ambiente elevato controllato.

## Ambito

Questo lavoro non include modifiche al packaging, ai manifesti Winget, al self-update o alla migrazione portable/Inno Setup; questi restano nel disegno separato `2026-10-04-dual-distribution-design.md`.
