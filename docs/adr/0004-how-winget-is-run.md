# ADR 0004 — How winget is run

- **Status:** Accepted
- **Date:** 2026-08-04 (in place since v1.9.0 or earlier; the resolved path and the quote guard came in v1.10.0, UTF-8 decoding of reads and the temp sweep in v1.10.3)
- **Depends on:** ADR 0002, ADR 0003, ADR 0008
- **Referenced by:** ADR 0005, ADR 0006

## Context

winget is a console program started from a windowless (`-noConsole`), elevated (ADR 0002) WPF
process, from background runspaces (ADR 0008). Each of the obvious ways to start it failed in
a specific way:

- **`& winget ... | Out-String` never returned.** A pipeline returns at EOF on the stdout pipe,
  that is when *every* process holding that handle has closed it. Silent installers launched by
  winget inherit the handle; if one stays alive, or relaunches itself detached, EOF never comes
  and the wait is endless, with winget long gone and the packages installed. `Start-Process -Wait`
  is no way out: it waits for the descendants too, which is exactly the problem.
- **`Start-Process -PassThru` lost the exit code.** Its `Process` object loses `ExitCode` when
  the process exits before the native handle is cached — a race the fast commands win. An empty
  `ExitCode` cast to `int` is `0`, which painted a failure green.
- **Localized messages came out as mojibake.** winget writes UTF-8; `Get-Content` on PowerShell
  5.1 assumes the ANSI code page.
- **The first scan after launch garbled every accented letter** (`è` as `Ã¨`, v1.10.3). winget
  always writes UTF-8 to a pipe — measured on the raw bytes with the console at cp850, at cp65001
  and with no console at all; its `SetConsoleOutputCP(CP_UTF8)` only affects what a console
  shows. `& winget | Out-String` decodes with the console's code page instead, and in the
  `-noConsole` exe the first background job runs before any console exists: the job prologue's
  UTF-8 setter throws, so the first scan was read as cp1252. Every later scan was right, which is
  why it looked random.
- **`wgt_*.out` / `.err` files piled up in `%TEMP%`.** An installer that leaves a detached child
  behind keeps the redirect files open when `Invoke-WinGet` tries to delete them.

## Decision

**Writes (queues) go through `Invoke-WinGet`** (`WinGet.Exec.ps1`): `Process.Start` on `cmd.exe`
with `/d /s /c`, which redirects stdout and stderr to two `wgt_<guid>` files in `%TEMP%`, and a
wait bound to the process exit (`WaitForExit`, with a tick every 30 s for an "elapsed" log line
and no timeout, so slow installers are not cut off). The files are read back with
`-Encoding UTF8`.

**Reads go through `Invoke-WinGetRead`** (`WinGet.Parse.ps1`): `Process.Start` on winget itself,
no shell, with `StandardOutputEncoding` / `StandardErrorEncoding` set to UTF-8, so decoding never
depends on a console. The arguments are quoted for `CreateProcess` by the function itself, so
text typed into the search box cannot become a command. stderr is read in parallel with stdout,
since reading one after the other can block when the other's buffer fills.

**Every queue command carries `--disable-interactivity`**: without a console a prompt would hang
forever.

**One resolved path.** `$wingetPath` is resolved once at startup (`Get-WinGetPath`) and passed into
every runspace through `-Vars`. `& winget` resolves the *name* on every call and depends on PATH
and on the app execution alias, which under an elevated account other than the interactive one
may not be there. Four read commands used to do that while the five write paths did not; forget
one `-Vars` entry and the variable is `$null` inside the runspace, the read comes back empty, and
it looks like winget found nothing.

**Unbalanced quotes are refused, not run.** The line handed to `cmd` is built by concatenation and
each caller interpolates the package Id between quotes. Ids come from the catalogue and from ARP
display names written by whoever authored the installer, and this process is elevated. An odd
number of double quotes throws instead of running.

**Leftover output files are swept at startup** by `Clear-WinGetTempFiles`, with
`[IO.File]::Delete`: the FileSystem provider can fail to resolve a `%TEMP%` in 8.3 form
(`C:\Users\FB5FE~1.BOR\…`), and `-LiteralPath` does not help. A file still in use waits for the
next launch. The setup downloaded by the self-update uses the same `wgt_` prefix and is swept the
same way (ADR 0013).

## Consequences

**Positive**
- Completion depends on winget alone, not on its children.
- The exit code is always the real one.
- Output is UTF-8 everywhere, console or not.

**To watch**
- The quote guard does **not** cover `%VAR%` expansion by `cmd`, which is a different problem; it
  should not be believed complete.
- Forgetting `wingetPath` in a job's `-Vars` fails quietly as an empty read; `Test-Ui.ps1`
  checks the rule (ADR 0016).

## Alternatives considered

1. **`& winget ... | Out-String`** — turned down: waits on pipe EOF, which an inheriting child can
   hold forever, and decodes with the console code page.
2. **`Start-Process -PassThru`** — turned down: loses `ExitCode` when the process exits first.
3. **`Start-Process -Wait`** — turned down: waits for the descendants as well.
4. **`Remove-Item` / `-LiteralPath` for the sweep** — turned down: fails on an 8.3 `%TEMP%`.
