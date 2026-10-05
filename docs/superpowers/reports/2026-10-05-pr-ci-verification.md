# Verifica PR e CI 1.10.2

## Ambito autorizzato

Commit, push del branch `codex/bugfixes-1.10.2-ci` e PR verso `FedeB2160/WinGetStudio:main`, con CI su GitHub Actions. Merge, tag e pubblicazione restano esclusi. La modifica preesistente a `assets/WinGetStudio-codesign.cer` è esclusa dal commit.

## CI

Workflow `.github/workflows/ci.yml`, runner GitHub `windows-2022`, PowerShell 5.1. Due job: test processi/parser e WPF; build con ps2exe 1.0.18, confronto della versione exe con `$AppVersion` e changelog, upload dell'exe non firmato per sette giorni. Trigger su PR, push a main e avvio manuale. Token in sola lettura e action ufficiali fissate a SHA.

La modalità `-Offline` salta WinGet reale e le API GitHub, mantenendo WPF e fixture locali. Entrambi gli switch UI insieme vengono rifiutati. Il giro live resta disponibile con `-ConfirmLiveWinget`.

## Evidenze locali prima del commit

- `powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-InvokeWinGet.ps1 -Offline`: exit 0.
- `powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-Ui.ps1 -Offline`: exit 0, sia nel sandbox sia nell'account dove WinGet è installato.
- Test UI senza switch oppure con entrambi: exit 1 prima dell'avvio, come richiesto.
- Test UI `-ConfirmLiveWinget`: exit 0; ricerca, inventario, registro, export di 51 pacchetti e controllo GitHub superati. Pin live saltato per assenza di 7-Zip.
- `src/build.ps1`: exit 0; FileVersion e ProductVersion 1.10.2. Il binario locale usa la firma esistente, con radice non attendibile localmente; la CI non riceve chiavi di firma.
- Revisione indipendente CI: corretto il pin ps2exe da versione del banner 0.5.0.34 a [versione del modulo 1.0.18](https://www.powershellgallery.com/packages/ps2exe/1.0.18). La ricerca del pacchetto 0.5.0.34 falliva; la Gallery documenta 1.0.18. Nessun altro rilievo operativo.

## Verifica remota

- Commit applicativo/CI: `ba10b69`, pubblicato su `codex/bugfixes-1.10.2-ci`.
- [PR #2](https://github.com/FedeB2160/WinGetStudio/pull/2), base `main`, collegata alla conversazione Codex.
- [GitHub Actions run 37344813499](https://github.com/FedeB2160/WinGetStudio/actions/runs/37344813499): **success**.
- Job **PowerShell 5.1 and WPF tests**: **success** sul runner GitHub.
- Job **Build and verify executable**: **success**, inclusi installazione del modulo fissato, compilazione, verifica metadati/changelog e caricamento dell'artefatto unsigned.

Questo esito verifica la CI remota sul commit applicativo ba10b69. Il successivo aggiornamento della sola documentazione viene sottoposto allo stesso workflow; l'esito corrente è consultabile nella PR. Nessun merge, tag o rilascio eseguito. La modifica al certificato resta locale e non inclusa nella PR.
