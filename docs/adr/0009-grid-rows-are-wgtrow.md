# ADR 0009 — Grid rows are WgtRow

- **Status:** Accepted
- **Date:** 2026-08-04 (in place since v1.9.0 or earlier)
- **Depends on:** ADR 0008

## Context

Every grid in the app — Updates, Install, Installed — shows rows whose state changes while the
user looks at them: the tick, the pin flag, the per-row result and its detail during a queue. The
queue writes those values from a runspace through `UI{}` (ADR 0008), and WPF has to repaint the
row.

Rows used to be `PSCustomObject`. Their `NoteProperty` values do not notify WPF of a change, so
every state change needed a `$Grid.Items.Refresh()` — and that regenerates the whole view and
sends the scroll back to the top. During an update it was called three times per package, which
made the list in practice impossible to scroll.

## Decision

**Grid rows are instances of `WgtRow`**, a C# class compiled with `Add-Type` in
`App.Bootstrap.ps1`, implementing `INotifyPropertyChanged`. Its properties are `Selected`,
`Pinned`, `Name`, `Version`, `Available`, `Id`, `Status` and `StatusDetail`; each setter raises
`PropertyChanged`, and WPF redraws only the cell that changed.

The readers build rows directly as `[WgtRow]@{ Selected = ...; Name = ...; Id = ...; Version = ... }`
(ADR 0006), and the queue updates them by reference (`$item.Status`, `$item.StatusDetail`).
`Add-Type` registers the type in the AppDomain, so `WgtRow` is visible inside the background
runspaces too, which receive only function bodies.

## Consequences

**Positive**
- No `Items.Refresh()`: the scroll stays where the user left it.
- Rows can be updated from a runspace through the dispatcher without touching the grid.

**To watch**
- The setters must run on the UI thread; in a runspace they go through `UI{}`.
- A new property shown in a grid must be added to the class with its `PropertyChanged` call; a
  value attached any other way will not repaint.

## Alternatives considered

1. **`PSCustomObject` plus `$Grid.Items.Refresh()`** — the previous design, turned down because
   the refresh resets the scroll.
