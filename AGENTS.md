# AGENTS.md

Istruzioni per gli agenti che lavorano su questo repository (Codex e simili).

Leggi e segui **CLAUDE.md** (architettura, comandi, convenzioni) e **DEVELOPMENT.md** (perché le cose sono fatte così e come si lavora). Dove le tue istruzioni globali divergono da questi file, vince il repository.

- Non modificare `CLAUDE.md`, `AGENTS.md` o le sezioni di processo di `DEVELOPMENT.md` se non te lo chiedono esplicitamente.
- `$AppVersion` cambia solo al rilascio; le modifiche vanno nel changelog sotto `## Unreleased`.
- Un commit per task, entrambe le suite verdi prima di ogni commit.
- Un piano che dura più di una sessione sta in `docs/superpowers/plans/` e si cancella a lavoro finito. Niente report di verifica nel repository: l'esito va nella PR.
- Documentazione e testi dell'interfaccia in inglese, commenti nel codice in italiano.
- Firma solo con la chiave di `assets/WinGetStudio-codesign.cer`. Se manca, `build.ps1` compila senza firma: non generare un certificato nuovo.
- Mai due processi winget insieme, nemmeno nei test.
