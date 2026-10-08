# ADR 0006 — Parsing winget tables by column position

- **Status:** Accepted
- **Date:** 2026-08-04 (in place since v1.9.0 or earlier; `-MaxColumns` came with pinning in v1.9.0)
- **Depends on:** ADR 0004
- **Referenced by:** ADR 0005, ADR 0007

## Context

For `upgrade`, `list`, `search` and `pin list` the app reads what winget prints:
**localized fixed-width tables**. Package names contain spaces, so a row cannot be split on
spaces. Several details make the tables harder than they look:

- `winget upgrade` prints a **second table** for packages needing explicit targeting, with its own
  column widths.
- Localized prose lines sit around the tables, and progress output uses `\r`.
- The meaning of the columns changes with the command: the 4th is *Available* in `upgrade`,
  *Match* in `search`, *Source* in `list`. The count varies even within one command —
  `search vlc` has a Match column, `search ab --count 5` does not. Only the first three (Name, Id,
  Version) are the same everywhere.
- `winget list --source winget` prints exactly three columns.
- `winget pin list` ends with the header "Tipo di pin" ("Pin type") in Italian: a header that
  contains spaces.

## Decision

**`Get-WinGetTable` parses by column position, one table at a time.** Offsets come from the
header row; columns are re-anchored at every separator row, so the second table gets its own
widths. Of `\r`-separated progress segments only the last is kept. A data row is told apart from
localized prose by its **grid alignment**.

**It returns the raw fields per row, and each caller maps them**, since only the caller knows what
the columns mean. The readers in `WinGet.Parse.ps1` use the first three columns, plus the 4th as
*Available* in `upgrade`, where a row without it is not an upgrade.

**Tables are accepted from three columns up.**

**`-MaxColumns` limits how many columns are considered**, for headers with spaces. `Get-WinGetPins`
passes `-MaxColumns 3`: it needs only the Id, and columns past the third are then neither
extracted nor checked.

## Consequences

**Positive**
- Localized output parses without knowing the language, as long as the grid holds.
- A second table with different widths is read correctly.

**To watch**
- Never rely on columns past the third without knowing the command and checking the count.
- A new reader whose last header may contain spaces needs `-MaxColumns`.
- `Test-InvokeWinGet.ps1` parses four fixtures through the real code — the two-table `upgrade`
  output, a 3-column `search`, a 4-column `list` whose 4th column is *Source* and whose version
  carries a `>` prefix, and a `pin list` whose last header contains spaces (ADR 0016). A new
  layout deserves a new fixture.

## Alternatives considered

1. **Tell data rows from prose by counting runs of two or more spaces** — turned down: the
   heuristic also dropped rows whose columns are exactly full.
2. **A four-column minimum** — turned down: it silently discarded the three-column table of
   `winget list --source winget`.
3. **Column detection by header tokens alone, without a limit** — on "Tipo di pin" it saw three
   phantom columns whose offsets fall mid-text in the data rows, judged every row misaligned and
   dropped them all: the pin list came back empty while winget had created the pin.
