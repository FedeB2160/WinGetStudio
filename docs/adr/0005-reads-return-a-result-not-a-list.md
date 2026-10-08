# ADR 0005 — Reads return a result, not a list

- **Status:** Accepted
- **Date:** 2026-10-07 (v1.10.2)
- **Depends on:** ADR 0004, ADR 0006

## Context

Up to v1.10.1 the readers (`upgrade`, `list`, `search`, `pin list`) returned the parsed rows and
nothing else. When winget itself failed — a source that would not open, a broken index — the app
read its silence as "nothing here": **No updates available**, **No installed package found**,
**No package matches**. A search with **MS Store** ticked while the Store did not answer
pretended the package did not exist.

A job could also come back empty without a word: a non-terminating error (for example a function
missing from `-Functions`) lands in the job's error stream, not in `EndInvoke`.

## Decision

**`Invoke-WinGetRead` returns a result object**: `Success`, `Rows`, `ExitCode`, `Output`. The
table is parsed only on exit 0, so a failing winget can no longer pass for an empty list. Each
reader (`Get-WinGetUpgrades`, `Get-WinGetInstalled`, `Get-WinGetSearch`, `Get-WinGetPins`) maps
the rows and returns the same object.

**The one non-zero exit that is a valid result** — `0x8A150014`,
`APPINSTALLER_CLI_ERROR_NO_APPLICATIONS_FOUND`, no match — is mapped to success in
`Get-WinGetSearch`, the only reader that can get it: `list` and `upgrade` without filters list
everything installed and never produce it. The exit code is normalised to unsigned 32 bits before
the comparison, as in `Get-UpdateStatus`.

**Messages use the last two meaningful lines of winget's output** (`Get-WinGetOutputTail`), the
rule the queue already used: when an installer fails, winget prints the path of its log *after*
the message, so the last line alone showed only the path. `Format-WinGetReadError` puts exit
code and tail on one line, shown where the list would be and in the log.

**Three cases, three messages.** An empty list, a winget failure and a job that died each say
something different; never "no updates" when winget did not answer.

**A failed pin read re-applies the last good list.** Rows that a refresh just created start
unpinned, so showing them as unpinned would be a claim winget never made. `Set-PinFlagsFromRead`
logs the error and re-applies `$script:lastPinIds`.

**A job's error stream is logged** by `Start-BackgroundJob`, so a non-terminating error no longer
leaves the job empty and the log silent.

## Consequences

**Positive**
- The user sees winget's own reason instead of an empty tab.
- A Store search that fails says so rather than reporting no match.
- Pins do not flicker off when one read fails.

**To watch**
- A new reader must return the result object and parse only on success; returning rows alone
  brings back the empty-list lie.
- A new benign exit code belongs in the reader that can receive it, not in `Invoke-WinGetRead`.

## Alternatives considered

The previous behaviour — return the parsed rows regardless of exit code — is the only alternative
the sources record, and it is the bug this decision fixes.
