# Verifica delle correzioni ai bug esistenti

**Seguito del 2026-10-05:** commit, push e PR sono stati successivamente autorizzati dall'utente. Le indicazioni "solo locale" sotto descrivono la verifica precedente. L'integrazione e la CI sono tracciate nel [report PR/CI](2026-10-05-pr-ci-verification.md).

Data: 2026-10-04. Piano: [existing-bugs](../plans/2026-10-04-existing-bugs.md).

## Stato

Correzioni locali implementate e verificate. Nessun commit o push delle modifiche; HEAD rimane `3ccbc67dfe5157d5b260dfa2b1210943eb066785`.

Il worktree creato è stato archiviato senza modifiche applicative. Le modifiche sono nel checkout `D:\AI Projects\WinGet Studio`: la creazione del branch nel worktree era stata impedita dai permessi sulla directory Git condivisa.

## Correzioni

- **Letture Winget:** stato, exit code e output arrivano fino alla UI. Un errore non diventa più una lista vuota riuscita. Le tabelle vengono parsate solo con exit zero.
- **Risultati senza corrispondenze:** il codice `-1978335212` (`APPINSTALLER_CLI_ERROR_NO_APPLICATIONS_FOUND`) produce un risultato vuoto valido per `search`, `list` e `upgrade`, conservando il codice originale. Non viene accettato come successo per `pin list`.
- **Pin:** l'ultima lettura riuscita viene conservata anche quando un refresh sostituisce gli oggetti delle righe e la successiva lettura dei pin fallisce. Una lettura vuota riuscita elimina invece correttamente i vecchi flag.
- **Import:** validazione di radice JSON, array `Sources`/`Packages` e identificatori non vuoti. Le strutture malformate restituiscono `null`; gli export validi vuoti restituiscono zero.
- **Test UI:** consenso esplicito prima dell'avvio, filtro con righe deterministiche, protezione dei pin preesistenti e tentativo di pulizia anche se la lettura iniziale del cleanup fallisce. Le simulazioni ripristinano lo stato necessario ai test live successivi.
- **About:** Codex (OpenAI) aggiunto accanto a Claude Code (Anthropic).

## Revisione e regressioni riprodotte

Una revisione indipendente del diff locale ha identificato tre problemi, tutti corretti con test osservati prima fallire e poi riuscire:

1. Ricerca senza risultati interpretata come errore: tre asserzioni su `search`, `list` e `upgrade` fallivano prima della correzione.
2. Perdita dei pin durante il refresh completo: entrambe le griglie perdevano i flag in due refresh consecutivi.
3. Cleanup interrotto da una lettura fallita: veniva chiamato solo `list`; ora la sequenza verificata è `list,remove,list`.

Ulteriori regressioni riprodotte durante la chiusura:

- La simulazione lasciava `installedLoaded` attivo; la precondizione del test live falliva anche senza Winget. Stato ripristinato nel `finally`.
- Un array JSON alla radice con un solo oggetto veniva enumerato dalla pipeline PowerShell e contato come export valido: `root-array -> 1`. Il controllo precedente alla conversione ora lo rifiuta.

Il codice senza corrispondenze è documentato dal [workflow ufficiale Microsoft](https://github.com/microsoft/winget-cli/blob/master/src/AppInstallerCLICore/Workflows/WorkflowBase.cpp#L1194) ed è stato osservato sulla macchina con questa ricerca reale:

```powershell
winget search --id WinGetStudio.DoesNotExist.RegressionProbe -e --source winget --disable-interactivity --accept-source-agreements
# Output: Nessun pacchetto trovato con criteri di input corrispondenti.
# ExitCode: -1978335212
```

Con `Invoke-WinGetRead` lo stesso comando ha restituito `Success=True; ExitCode=-1978335212; Rows=0`.

## Comandi ed esiti finali

Eseguiti con Windows PowerShell 5.1 (`C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe`):

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-InvokeWinGet.ps1
powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-Ui.ps1 -ConfirmLiveWinget
```

- `Test-InvokeWinGet.ps1`: exit **0**, `Tutti i test passati`. Lo smoke WinGet interno è saltato nel sandbox; `winget --version` e il lettore senza corrispondenze sono stati verificati separatamente nell'account reale.
- `Test-Ui.ps1`: exit **0**, `TUTTO OK`, eseguito fuori dal sandbox con WinGet **1.29.380** e account interattivo. Il token è **non elevato** (`AdminToken=False`).
- Senza `-ConfirmLiveWinget`: exit **1**, messaggio esplicito prima di qualsiasi inizializzazione dell'app.
- `git diff --check`: exit **0**.

Il giro WPF reale ha verificato persistenza sul registro, annullamento della coda su ID di prova inesistenti, ricerca (`vlc`: 9 risultati), inventario, filtro, export di **50 pacchetti**, lettura della release GitHub **v1.10.1** e controllo manuale degli aggiornamenti. I test di errore, import malformato e conservazione dei pin usano fixture controllate.

## Limiti e decisioni

- Il ciclo reale `pin add/list/remove` è **saltato**: `7zip.7zip` non è installato. La pulizia dopo lettura fallita è verificata con una simulazione; la conservazione di un pin preesistente è protetta dalle condizioni nel codice, non verificata mediante una modifica reale in questa esecuzione.
- L'app è stata montata come WPF nascosto dal test. Avvio dell'eseguibile distribuito con UAC, installazione/disinstallazione e sostituzione dell'app durante l'aggiornamento non sono stati eseguiti. La compilazione, assente nella verifica iniziale, è stata eseguita nel successivo allineamento alla versione 1.10.2 documentato sotto.
- I commit previsti dal piano sono sospesi per richiesta dell'utente. Il lavoro rimane senza una nuova copia pubblicata su GitHub.
- Il test di scrittura HKCU può saltare soltanto se il token non può aprire `HKCU\Software` in scrittura: in un ambiente limitato una regressione di persistenza potrebbe quindi sfuggire. Il successivo giro sull'account reale ha verificato con successo la scrittura e rilettura.
- L'ipotesi del piano “qualsiasi exit nonzero significa errore da mostrare” è stata corretta usando il codice documentato per l'assenza di corrispondenze. L'eccezione resta limitata ai tre comandi di lettura indicati; modifiche future della semantica Winget richiederanno nuovi test.
- Il requisito di elevazione del giro live è riportato come limite, senza trasformarlo in un esito positivo: le letture richieste e l'export hanno funzionato con il token reale non elevato; il percorso UAC rimane da verificare.
- Packaging installer/portable e relativo self-update restano nel piano separato. PR e CI saranno affrontate quando richiesto.

Nessun rilievo minore differito dal revisore. I file di lavoro e il piano sono conservati perché non esistono commit di implementazione dai quali recuperarli.

## Seguito: versione 1.10.2 e controllo di completezza

La versione era rimasta erroneamente a 1.10.1 dopo le correzioni. Il seguito richiesto dall'utente l'ha portata a **1.10.2**, incremento patch per correzioni compatibili. La versione è locale e non pubblicata.

Aggiornati `src/main.ps1`, README, changelog, procedura in DEVELOPMENT e checklist del piano. Le istruzioni globali in `C:\Users\fborg\.codex\AGENTS.md` ora impongono, a ogni esecuzione o ripresa, verifica di tutti i requisiti, aggiornamento della documentazione e controllo del versionamento. Le vecchie istruzioni di commit/push automatico sono state sostituite dalla procedura locale autorizzata, con PR e CI quando sarà autorizzata l'integrazione.

| Punto del piano | Stato verificato |
| --- | --- |
| Test UI deterministico e sicuro | Implementato; opt-in e filtro verificati. Cleanup simulato verificato. Ciclo pin reale saltato per assenza di 7-Zip. |
| Errori nelle letture Winget | Implementato; regressioni simulate e letture reali superate, inclusi risultato vuoto e conservazione dei pin. |
| Import JSON malformati | Implementato; fixture valide e invalide superate, radice array rifiutata; controllo statico del blocco prima dell'import. Nessuna installazione reale eseguita. |
| Gate completo | Entrambe le suite exit 0; limiti ambientali espliciti. Passaggi di commit sospesi su istruzione dell'utente. |
| Versione e documentazione | Sorgenti e metadati binari 1.10.2; changelog e README allineati, versione indicata come non pubblicata. |

Evidenze di questo seguito:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\src\build.ps1
# Exit 0: Fatto: ...\dist\WinGetStudio.exe (versione 1.10.2)

(Get-Item .\dist\WinGetStudio.exe).VersionInfo | Select-Object FileVersion, ProductVersion
# FileVersion 1.10.2; ProductVersion 1.10.2
```

- `Test-InvokeWinGet.ps1`: exit 0; smoke WinGet interno saltato nel sandbox.
- `Test-Ui.ps1 -ConfirmLiveWinget` sull'account reale: exit 0, `TUTTO OK`; versione 1.10.2 verificata, export reale di **51 pacchetti** in questo giro, release pubblicata ancora v1.10.1. Il conteggio di 50 riportato sopra appartiene alla verifica precedente.
- Exe firmato con `CN=WinGet Studio` e marca temporale DigiCert. `Get-AuthenticodeSignature` restituisce `UnknownError`: il messaggio indica che la radice non è nell'elenco locale delle autorità attendibili. Firma presente; attendibilità locale non confermata. Nessuna modifica agli archivi delle autorità attendibili.
- Rimangono da verificare il ciclo pin reale e l'avvio dell'exe con UAC. Non sono stati eseguiti commit, push, tag o pubblicazioni.
- `assets/WinGetStudio-codesign.cer` risultava già modificato all'inizio di questo seguito e non è stato modificato da queste operazioni.
