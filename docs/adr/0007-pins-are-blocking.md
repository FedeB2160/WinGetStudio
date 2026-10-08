# ADR 0007 — Pins are blocking

- **Status:** Accepted
- **Date:** 2026-10-07 (v1.10.2)
- **Depends on:** ADR 0003, ADR 0006

## Context

Pinning came in v1.9.0: right click a row in Updates or Installed, **Pin (block upgrades)** or
**Remove pin**. The app created winget's default pin type, *Pinning*.

A *Pinning* pin only keeps a package out of `winget upgrade --all`. An explicit
`winget upgrade --id` — which is how this app upgrades a package — goes straight through it: in
winget's `UpdateFlow.cpp`, `includePinned = m_isSinglePackage || ...`. A pin made from the app
therefore did not stop an upgrade made from the app, nor one by name from the command line.

## Decision

**The app adds pins with `winget pin add --blocking`** (`Set-PackagePin`, `App.Pins.ps1`). A
*Blocking* pin is enforced by winget on every upgrade path, from this app or from the command
line, until it is removed. Removing is `winget pin remove`.

**The row's `Pinned` flag still keeps pinned packages out of the queue**, whatever their type, so
a *Pinning* pin made from the command line is respected by the app too. A pinned row's tick is
disabled; pin and unpin act on the **highlighted** rows, not the ticked ones, since otherwise a
pin could never be removed.

**Only rows that actually change state are queued**: re-pinning a pinned package makes winget exit
with an error, which would be marked red in the Result column.

**winget is the source of truth.** After a pin or unpin the pins are re-read rather than assumed
from the queue's outcome, so a pin added from the command line shows up too. That re-read is the
last step and releases the busy state (ADR 0003).

## Consequences

**Positive**
- A pin from the app holds against explicit upgrades, from anywhere.
- A pin still blocks upgrades, not removal: a pinned package can be uninstalled.

**To watch**
- Pins created before v1.10.2 keep their type; the app does not convert them.
- Pin type is not shown: `Get-WinGetPins` reads only the Id (ADR 0006), since the type
  (*Pinning*, *Blocking*, *Gating*) does not change what the app displays.
- The live suite exercises one pin cycle on `7zip.7zip`, only when it is installed and not
  already pinned, and removes the pin in a `finally` that first waits for the queue's winget to
  exit (ADR 0016).

## Alternatives considered

1. **Keep the default *Pinning* type** — turned down: it does not stop `upgrade --id`, which is
   the only way this app upgrades.
