# ADR 0024 — Version 2 runs unelevated and asks for administrator rights only when needed

- **Status:** Accepted (for 2.0; supersedes ADR 0002 there, the 1.x line keeps ADR 0002)
- **Date:** 2026-10-29
- **Depends on:** ADR 0002, ADR 0003, ADR 0018, ADR 0022, ADR 0023
- **Referenced by:** ADR 0025, ADR 0026

## Context

1.x is `requireAdministrator` (ADR 0002): one UAC at startup, everything elevated. The price was paid
in ADR 0018 (winget refuses some per-user operations as administrator, retried through a scheduled
task), in the warning about elevating with another account, and in guarding everything an elevated
process runs (the `%` and import fixes of v1.13). winget itself, and UniGetUI, run unelevated and
elevate per installer.

Measured on 2026-10-29 with winget 1.29.380 from an unelevated process (standard UAC):

| Operation | UAC | Result |
|---|---|---|
| Install of a per-machine MSI (PuTTY), CLI or COM | one, raised by winget ("The installer will request to run as administrator") | ok |
| Install of a portable zip (ripgrep), COM | none | ok |
| **Silent uninstall of a per-machine MSI**, CLI or COM | **none** | **fails**: `0x8A150030`, MSI 1603 |
| Same uninstall repeated with `ShellExecute runas` of `cmd /c winget … > file` | one | ok; exit code read from the process handle |
| Two uninstalls in **one** `runas` | one | both ok |
| `runas` with the UAC declined | — | `Win32Exception`, `NativeErrorCode` 1223, no process |
| Install whose UAC is left unanswered | open | winget waits indefinitely |
| COM API from an **elevated** process | — | activation fails, `0x80040154` |

## Decision

1. **The exe is `asInvoker`.** No UAC at startup; reads, search and checks never ask for one.
2. **Installs and updates run unelevated.** winget raises the installer's own UAC when it needs one;
   that is the expected flow, not an error.
3. **"Retry as administrator"** for the packages of the last queue that failed in a way elevation can
   fix (first case: `0x8A150030` on per-machine uninstalls; also `0x8A150019` COMMAND_REQUIRES_ADMIN).
   It runs the same command lines through **one** `runas` for all of them, output to files, exit code
   from the process handle, under the one-winget-at-a-time lock (ADR 0003). A declined UAC (1223) is an
   outcome of its own, *Cancelled at the administrator prompt*, and stays retryable.
4. **A row waiting for a UAC says so** (*Waiting for administrator approval*), and Cancel can stop the
   wait: winget has no timeout and the queue deliberately has none either (ADR 0004).
5. **"Restart as administrator"** (Settings and the window menu) relaunches the whole app with `runas`
   for those who prefer one UAC per session, today's behaviour. In that mode a banner says so, only the
   CLI backend is used (COM does not activate elevated), and ADR 0018's unelevated retry and the
   other-account warning apply as in 1.x.
6. **The self-update downloads to `%LOCALAPPDATA%\WinGetStudio\update`** and keeps the file open with
   read-only sharing from the signer check (ADR 0022) until the setup has started, instead of the
   administrators-only folder, which an unelevated process cannot create.

## Consequences

**Positive**
- No UAC to open the app; per-user packages and installers that refuse elevation work without a
  workaround; the app runs as the signed-in user, so per-user packages land in the right profile.
- Much less runs elevated, so a bug or a hostile input has less to reach.

**To watch**
- A queue may show several UACs, one per per-machine installer; "Restart as administrator" is the
  answer for users who mind.
- The UAC declined by an installer that winget elevated was not observed in the test (expected
  `0x8A15010C` or 1223): to confirm by hand during the port.
- In the portable, self-contained exe the WPF native libraries are extracted to `%TEMP%\.net`; an
  elevated restart would load them from a user-writable folder. The elevated restart of the portable
  must point the extraction to a protected folder, or be offered only in the installed channel (ADR 0026).

## Alternatives considered

1. **Keep `requireAdministrator`** (ADR 0002) — simplest, but keeps every cost listed in the context.
2. **One UAC per queue through an elevated helper** — fewer prompts, but a new elevated component that
   receives work from an unelevated process: an elevation broker to secure. Turned down for now.
3. **Cache elevation like UniGetUI** (a gsudo fork whose cache trusts only a signed parent) — the same
   broker problem, with more code.
