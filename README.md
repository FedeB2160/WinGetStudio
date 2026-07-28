# WinGet Update Tool

Tool Windows standalone (WPF) che mostra gli aggiornamenti `winget` in una tabella con checkbox e aggiorna solo gli elementi selezionati. Elevazione UAC automatica, UI non bloccante, tema chiaro/scuro, nessun branding.

## Struttura

```
build.bat                    doppio click -> genera dist\WinGetUpdateTool.exe
README.md
src\   WinGetUpdateTool.ps1  script principale (logica + winget)
       build.ps1             compilazione con ps2exe
ui\    UI.xaml               finestra: layout e stili
       Theme.Light.xaml      palette chiara
       Theme.Dark.xaml       palette scura
assets\icon.ico              icona app (embeddata nell'exe)
tests\ Test-Ui.ps1           controllo headless di XAML e temi
       Test-InvokeWinGet.ps1 test dell'esecuzione winget
dist\  WinGetUpdateTool.exe  output della build
```

I tre `.xaml` **non** sono un requisito a runtime: `build.ps1` li inietta nell'exe (che resta un file solo, copiabile da solo su un'altra macchina). Se però un `.xaml` è presente su disco, vince su quello embeddato — utile per ritoccare la UI senza ricompilare. Percorsi cercati, nell'ordine: `..\ui\<file>`, `<cartella exe>\ui\<file>`, `<cartella exe>\<file>`.

## Requisiti
- Windows 10/11 con **winget** (App Installer dal Microsoft Store).
- PowerShell 5.1+.
- Modulo **ps2exe** (solo per compilare): `Install-Module ps2exe -Scope CurrentUser`.

## Eseguire senza compilare
```powershell
powershell -ExecutionPolicy Bypass -File .\src\WinGetUpdateTool.ps1
```
Parte il prompt UAC, poi si apre la finestra con l'elenco aggiornamenti.

## Compilare in .exe
Doppio click su **`build.bat`**, oppure:
```powershell
powershell -ExecutionPolicy Bypass -File .\src\build.ps1
```
Genera `dist\WinGetUpdateTool.exe`. Doppio click → prompt UAC → stessa UI.

La build sostituisce i marcatori `###UI.xaml###`, `###Theme.Light.xaml###`, `###Theme.Dark.xaml###` in `src\WinGetUpdateTool.ps1` col contenuto dei file, scrive un sorgente temporaneo in `%TEMP%` e passa quello a ps2exe (`-requireAdmin` → manifest UAC, `-noConsole` → solo la finestra WPF, `-iconFile` → icona embeddata). Fallisce con errore esplicito se un marcatore manca o se l'exe non viene riscritto.

## Test
```powershell
powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-Ui.ps1
powershell -ExecutionPolicy Bypass -File .\tests\Test-InvokeWinGet.ps1
```
- `Test-Ui.ps1` — headless, non apre finestre: verifica che gli script parsino, che `UI.xaml` carichi con tutti gli `x:Name` attesi, che i due temi definiscano le stesse chiavi, che ogni `DynamicResource` esista e che i marcatori di build siano al loro posto.
- `Test-InvokeWinGet.ps1` — verifica l'esecuzione di winget; non serve admin, non installa nulla.

## Uso
1. **Cerca aggiornamenti** (in alto a sinistra) — esegue `winget upgrade --include-unknown` con spinner di caricamento; in alto compare "N aggiornamenti disponibili". La barra di avanzamento si azzera: appartiene alla coda precedente, non al nuovo elenco.
2. Spunta le righe da aggiornare, o **Seleziona tutto** (sotto l'elenco). Accanto compare "M selezionati".
3. **Aggiorna** (sotto l'elenco) — lancia l'update in sequenza, **un pacchetto per volta per ID**; progresso nella barra e stato per riga nella colonna **Esito**.
   - Nessun timeout: gli installer lenti non vengono troncati. Durante un'attesa lunga il log scrive una riga ogni 30s (`...nome in corso da Ns`), così un blocco è visibile mentre accade.
   - "Seleziona tutto" è attivo solo con almeno un elemento; "Aggiorna" solo con almeno uno selezionato.

### Tema
Il pulsante icona in alto a destra **cicla** fra tre modi (il ToolTip dice quello attivo):

| Icona | Glifo | Modo | Comportamento |
|---|---|---|---|
| sole | `E706` | Chiaro | sempre chiaro |
| luna | `E708` | Scuro | sempre scuro |
| sole con la luna dentro | `F08C` | Auto | segue Windows, anche a finestra aperta (controllo ogni 5s) |

- Icone dal set di sistema, presenti sia in **Segoe Fluent Icons** (Win11) sia in **Segoe MDL2 Assets** (Win10).
- I glifi vanno scritti `[char]0xE706`, **non** `` "`u{E706}" ``: quell'escape esiste solo da PowerShell 6 e ps2exe compila contro 5.1, dove resterebbe il letterale `u{E706}` (rettangoli vuoti). `Test-Ui.ps1` lo controlla.
- La scelta è ricordata in `HKCU:\Software\WinGetUpdateTool`, valore `Theme`.
- In modo Scuro anche la barra del titolo diventa scura (`DWMWA_USE_IMMERSIVE_DARK_MODE`, Windows 10 2004+ / 11; su build precedenti resta chiara).
- **Per cambiare i colori** basta editare `ui\Theme.Light.xaml` / `ui\Theme.Dark.xaml` e rilanciare: sono due elenchi di `SolidColorBrush` con le stesse chiavi. Aggiungere una chiave a un file solo fa fallire `Test-Ui.ps1`.
- `UI.xaml` referenzia i colori con `{DynamicResource ...}`: usare `StaticResource` romperebbe il cambio tema a caldo (si risolve una volta sola).

### Icone di stato (colonna Esito)
Icone dal set di sistema (**Segoe Fluent Icons**, fallback **Segoe MDL2 Assets** su Windows 10):
- spinner = aggiornamento in corso
- cerchio pieno verde con spunta = completato (exit 0)
- triangolo pieno giallo = avviso (codici benigni: riavvio richiesto, già installato, ...)
- cerchio pieno rosso con X = errore (passa il mouse per il codice; dettaglio completo nel log)

## Note
- Se `winget` manca → messaggio di errore chiaro all'avvio.
- Se non ci sono aggiornamenti → messaggio "Nessun aggiornamento disponibile".
- Un errore su un pacchetto **non** ferma gli altri in coda (esito per riga).
- Aggiornamenti eseguiti sequenzialmente (winget non è affidabile in parallelo).
- winget è lanciato con output su file e attesa sulla sola uscita del processo (non sulla pipe): gli installer figli che ereditano stdout non possono più bloccare l'attesa a tempo indefinito. Flag `--disable-interactivity`: senza console (exe `-noConsole`) un prompt bloccherebbe l'aggiornamento per sempre.
- In tema scuro il quadratino della checkbox non spuntata resta chiaro: usa il template di sistema, ri-templarlo non valeva il codice.
