# ADR 0008 — Background work in runspaces

- **Status:** Accepted
- **Date:** 2026-08-04 (in place since v1.9.0 or earlier)
- **Depends on:** ADR 0001
- **Referenced by:** ADR 0003, ADR 0004, ADR 0009

## Context

winget calls take from under a second to many minutes. Run on the WPF thread they would freeze the
window, and v1.0.0 already promised "a non-blocking UI". PowerShell 5.1 offers background
runspaces, but with traps of their own: code in another runspace cannot touch WPF controls, does
not inherit the caller's functions, and does not share its `$script:` scope.

## Decision

**`Start-BackgroundJob` (`App.Jobs.ps1`) runs a script block in a separate STA runspace** and calls
`-OnDone` on the UI thread with the results.

- **Every UI write from a runspace goes through `UI{}`**, a helper defined in the job prologue that
  calls `$window.Dispatcher.Invoke`. `LogUI` writes to the log the same way. Both are available to
  every job; `$window` and `$TxtLog` are passed to every runspace for them.
- **Functions are passed by name with `-Functions`.** Runspaces do not inherit functions, so the
  body of each named function is passed as text and recreated inside the runspace with
  `Invoke-Expression`. This works whichever module the function lives in.
- **Variables are passed with `-Vars`**, set on the runspace before it starts.
- **Prologue and body are passed as text**: a script block created in the caller stays bound to the
  caller's runspace and would not execute in the other one.
- **Completion is found by a `DispatcherTimer`** polling every 200 ms, not by an event: the callback
  of `BeginInvoke` would arrive on a non-UI thread, where touching controls throws.
- **State reaches the tick through the job object, never through a `GetNewClosure()` capture.** The
  tick finds its job from the *sender* (the timer that fired). A closure gets its own module scope,
  and inside it `$script:` no longer refers to the script: `$script:jobs` came back `$null`, the
  cleanup died on `.Remove()`, and the job kept polling forever.
- **The job's error stream is logged** after `EndInvoke`; `OnDone` runs even if the job died, so the
  UI is always restored.
- **All jobs are tracked in `$script:jobs`** and closed by `Stop-AllJobs` when the window closes;
  otherwise a live runspace or timer keeps the process alive after the window has gone.

## Consequences

**Positive**
- The window stays responsive during scans and queues.
- One mechanism for every background task, with a uniform log and cleanup.

**To watch**
- A function missing from `-Functions` makes the job fail with "term not recognized"; a variable
  missing from `-Vars` is silently `$null` (the `$wingetPath` case in ADR 0004).
- `OnDone` runs on the UI thread but does **not** see the locals of the function that started the
  job. State it needs goes in `$script:` variables or the job object: the self-update's `OnDone`
  once died on "Path is null" for exactly this reason.
- **A `CollectionView` returned from a function is unrolled** by PowerShell into its items, and the
  caller gets no `Filter` property. The Installed tab holds its view in a variable instead.
- The same closure trap applies to event handlers: `Register-GridRefresh` builds its handler with
  `[scriptblock]::Create` and interpolates the function name, rather than closing over parameters.
- `Test-Ui.ps1` checks that `Start-BackgroundJob` completes, returns its result and unhooks itself
  (ADR 0016) — these scope and closure bugs pass every static check.

## Alternatives considered

1. **`GetNewClosure()` to carry state into the tick** — turned down after the `$script:jobs` bug
   above.
2. **Completion by event (`BeginInvoke` callback)** — turned down: it runs on a non-UI thread.
