# ADR 0003 — Only one winget process at a time

- **Status:** Accepted
- **Date:** 2026-08-04 (in place since v1.9.0 or earlier; the single choke point, the search counter and cancellation came in v1.10.0)
- **Depends on:** ADR 0008
- **Referenced by:** ADR 0004, ADR 0007, ADR 0011 (controls follow the busy state), ADR 0013 (`Start-SelfUpdate` guards), ADR 0016

## Context

Two concurrent winget invocations make one of them fail with exit 1. The app has three tabs
that each start winget — scans, searches, update, install, uninstall and pin queues, export and
import — and they all run in background runspaces (ADR 0008), so nothing serialises them by
default.

The rule was learnt twice:

- Reading the pins used to run *after* the busy state was released, so a click on Update in
  that window ran a second winget and one of the two failed with exit 1.
- A search must not raise the busy state, or typing would stall. Asking `$script:isBusy` alone
  was the hole: typing three characters in Install and switching straight to Installed ran
  `winget search` and `winget list` at the same time (fixed in v1.10.0).

## Decision

**The busy state is global.** `Set-AppBusy` in `App.Ui.ps1` sets `$script:isBusy` and calls
every handler registered with `Register-BusyHandler`; each tab registers its own in its
`Initialize-*` function, so an operation on one tab disables the commands of all of them and
adding a tab does not touch `App.Ui.ps1`.

**Searches count themselves instead.** A search increments `$script:searchInFlight`
(`Tab.Install.ps1`) and leaves the busy state alone. Everything about to run winget asks
**`Test-WinGetBusy`**, which is true when either the busy state is up or a search is in flight.

**`Start-WinGetQueue` is the single choke point** for the four queue operations (update, install,
uninstall, pin). It refuses to start when `Test-WinGetBusy` is true ("Another winget operation is
still running"), and it takes the busy state itself, so no caller can forget to. The paths that
call winget outside the queue guard themselves: both scans; export and import twice each,
because the file dialog gives a pending search time to come back; and `Start-SelfUpdate`,
because it ends by replacing the executable and closing the window. `Start-UpdateCheck`
deliberately does not — it only talks to GitHub.

**Pins are read inside the same job.** The scans read the pins in the job that reads the list.
After a pin or unpin the busy state is released by the pin re-read, which is the last step
(`Update-PinFlags`), not by the queue's `OnDone`.

**`$script:queueVerb` publishes which queue is running** (`Update`, `Install`, `Uninstall`,
`Pin`, `Unpin`), because a tab otherwise cannot tell its own operation from another tab's. It is
assigned *before* `Set-AppBusy $true` — the handlers run immediately and read it; with the
assignment after, the Updates button never became Cancel — and `Set-AppBusy $false` clears it
*before* calling the handlers so each sees the final state. The button label is assigned on
every call, as a function of (busy, which queue), not inside one branch.

**Cancelling a queue is cooperative.** `Start-WinGetQueue` shares a synchronized hashtable with
its runspace and checks `Requested` at the top of each iteration, so the package in flight always
finishes. A hashtable rather than a `$script:` variable because the runspace has its own scope;
a hashtable is a reference type, so both threads see the same object. A fresh one per queue, so
a request arriving between two queues does not carry over.

## Consequences

**Positive**
- The guard against a second process lives in one place for every queue.
- Typing in Install stays fluid while still counting as winget work.
- Update turns into Cancel only for the update queue (v1.10.0); nothing is killed halfway.

**To watch**
- Every new path that starts winget outside `Start-WinGetQueue` must ask `Test-WinGetBusy`
  itself; asking `$script:isBusy` reopens the search hole.
- `$script:searchInFlight` lives in `Tab.Install.ps1`; `Test-WinGetBusy` holds when it is still
  `$null` because the comparison does.
- The queueVerb mechanism is generic — wiring Cancel to Install or Uninstall is a few lines
  each — but only the Updates queue uses it today.

## Alternatives considered

1. **Let a search raise the busy state** — turned down: typing would stall.
2. **Kill the running winget on cancel** — turned down: killing an installer halfway leaves the
   machine in a state nobody can describe.
3. **A `$script:` flag for cancellation** — does not work: the runspace has its own scope and
   would not see it.
