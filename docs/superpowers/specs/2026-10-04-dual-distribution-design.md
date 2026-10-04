# WinGet Studio: installer e versione portable

**Data:** 2026-10-04  
**Stato:** disegno approvato in chat; in attesa di revisione di questa specifica.

## Obiettivo

Distribuire WinGet Studio in due forme:

1. Un installer Windows scaricabile da GitHub e usato anche dal manifesto Winget. Crea il collegamento nel menu Start; il collegamento Desktop è facoltativo.
2. Un eseguibile portable autonomo scaricabile da GitHub.

Entrambe le forme verificano la disponibilità di aggiornamenti. L’installazione Winget si aggiorna tramite `winget upgrade FedeB2160.WinGetStudio`, mantenendo lo scope utente/macchina usato all’installazione. La copia portable continua a sostituire il proprio eseguibile. La copia installata manualmente usa l’installer aggiornato.

Durante un aggiornamento installato, il processo principale termina prima che i file vengano sostituiti. Dopo un esito positivo l’app si riapre automaticamente. Dopo un errore resta chiusa e l’utente riceve una notifica con codice di uscita e percorso del log.

## Stato attuale verificato

- `src/build.ps1` genera `dist\WinGetStudio.exe` con manifest UAC `requireAdministrator`.
- `src/main.ps1` è l’unica fonte della versione (`$AppVersion`).
- Il manifesto `winget\1.10.1\FedeB2160.WinGetStudio.installer.yaml` usa `InstallerType: portable`.
- `src/modules/App.Update.ps1` sceglie il primo asset `.exe` della release. Con più eseguibili questo può scaricare l’artefatto sbagliato.
- `Test-IsWinGetPortable` disabilita l’auto-update per il pacchetto portable gestito da Winget.
- `DEVELOPMENT.md` documenta la build e pubblicazione manuale; nel repository non è presente una pipeline GitHub Actions.
- Il passaggio del pacchetto Winget dallo scope portable a Inno Setup è una migrazione da provare, non un comportamento da presumere.

## Approcci valutati

1. **Un installer Inno Setup che supporta entrambi gli scope — scelto.** Lo stesso asset serve per installazione manuale e Winget. Il manifesto contiene voci distinte per scope, con gli argomenti Inno appropriati. Evita due installer mantenuti separatamente.
2. **Due installer distinti.** Rende esplicite le differenze di scope, ma duplica output e configurazione senza un beneficio funzionale dimostrato.
3. **Mantenere Winget portable e creare collegamenti dall’app.** Non soddisfa l’installazione tradizionale e lascia all’app gestione di disinstallazione, aggiornamento e collegamenti.

## Architettura scelta

### Artefatti e release

- `WinGetStudio.exe`: eseguibile portable.
- `WinGetStudio-Setup.exe`: installer Inno Setup per installazione manuale e Winget.
- Entrambi condividono versione e sorgente dell’applicazione; lo script di build produce gli artefatti a partire dalla stessa build applicativa.
- Gli aggiornamenti selezionano asset per nome esplicito, mai per posizione nella lista degli asset GitHub.
- Per compatibilità con le vecchie copie portable che selezionano il primo `.exe`, la procedura di rilascio carica prima `WinGetStudio.exe` e poi `WinGetStudio-Setup.exe`. Le nuove versioni non dipendono da quest’ordine.

### Installazione e rilevamento del canale

- L’installer manuale consente installazione per utente o per macchina e crea il collegamento Start Menu. Il collegamento Desktop resta facoltativo.
- Il manifesto Winget offre le due voci di scope riferite allo stesso installer; ciascuna passa a Inno lo scope corrispondente e un marcatore d’origine Winget.
- L’installer registra scope, origine (Winget o manuale) e percorso installato in un’area coerente con lo scope. L’app legge tali dati per scegliere il flusso di aggiornamento.
- L’eseguibile fuori dal percorso registrato dell’installer è portable. Le installazioni Winget portable già esistenti sono riconosciute separatamente durante la migrazione.

### Verifica e applicazione aggiornamenti

- L’app continua a verificare GitHub Releases per scoprire versioni più recenti.
- **Winget:** l’azione avvia `winget upgrade --exact --id FedeB2160.WinGetStudio --scope user|machine`, usando lo scope registrato. Un processo supervisore aspetta Winget mentre l’app principale termina. Se Winget termina con successo, il supervisore rilancia l’app; altrimenti salva stdout/stderr in un log e mostra codice di uscita e percorso del log. Se Winget non è avviabile, l’app non si chiude.
- **Installazione manuale:** l’app scarica e verifica l’asset `WinGetStudio-Setup.exe`, poi il supervisore avvia l’installer mantenendo scope e percorso esistenti. Dopo l’esito positivo rilancia l’app; in caso di errore mostra la notifica e il log.
- **Portable:** l’app scarica e verifica `WinGetStudio.exe`, lo sostituisce e si riavvia come nel flusso attuale.
- Il download continua a verificare il digest SHA-256 fornito da GitHub quando disponibile. Un asset senza digest non deve essere trattato come verificato.
- Per installazioni Winget, la release GitHub può precedere la pubblicazione/approvazione del manifesto nella sorgente Winget. In quel caso l’upgrade Winget può non essere ancora disponibile: l’errore va riportato senza sostituire file manualmente né riaprire l’app come se l’aggiornamento fosse riuscito.

### Migrazione Winget

Il pacchetto attuale è portable e il nuovo pacchetto userà Inno Setup. Prima della pubblicazione va provato l’upgrade sul medesimo PackageIdentifier, inclusi scope e disinstallazione. Se Winget non completa la migrazione in modo pulito, il rilascio non deve procedere assumendo che l’aggiornamento in-place funzioni; va definito un passaggio di migrazione esplicito.

## Errori e sicurezza

- Nessun aggiornamento deve avviare un asset ambiguo o non verificato come se fosse quello giusto.
- Il supervisore tratta come successo solo i codici che la documentazione Winget identifica come riusciti; codici inattesi sono errori e non rilanciano l’app.
- L’app resta aperta se non riesce ad avviare il supervisore. Dopo l’avvio riuscito del supervisore termina prima dell’installazione.
- Il log di aggiornamento contiene output e codice di uscita, senza token o credenziali.
- Lo scope passato a Winget e quello dichiarato nel manifesto devono coincidere. La documentazione Winget e casi reali mostrano che la selezione dello scope può essere incoerente: entrambe le modalità vanno provate con installazione e aggiornamento reali in ambiente isolato.

## Verifica richiesta prima del rilascio

- Eseguire le suite esistenti `tests/Test-InvokeWinGet.ps1` e `tests/Test-Ui.ps1`.
- Compilare portable e Setup, validare manifesto e hash, verificare nomi e selezione degli asset.
- In ambiente Windows isolato, installare e aggiornare via Winget sia in scope utente sia macchina; verificare chiusura dell’app, aggiornamento, riapertura dopo successo e notifica/log senza riapertura dopo errore.
- Provare installazione manuale e aggiornamento nei due scope, collegamenti, percorso scelto e disinstallazione.
- Provare la migrazione dall’attuale Winget portable al nuovo installer, inclusi aggiornamento e disinstallazione successivi.
- Provare portable da GitHub: avvio, controllo release, verifica SHA-256, sostituzione e riavvio.
- Non usare l’installazione quotidiana dell’utente per i test di migrazione o aggiornamento.

## Limiti e decisioni mantenute

- Il progetto continua a non introdurre una pipeline CI in questo cambiamento; build, artefatti e pubblicazione seguono il flusso manuale esistente, aggiornato per i due file.
- La firma dipende dal certificato disponibile sulla macchina di build, come oggi.
- Il piano di implementazione verrà creato dopo la revisione e approvazione di questa specifica.
