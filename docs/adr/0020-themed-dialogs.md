# ADR 0020 — Themed dialogs

- **Status:** Accepted
- **Date:** 2026-10-13
- **Depends on:** ADR 0008, ADR 0010

## Context

Up to v1.11.1 every message and confirmation was a `[System.Windows.MessageBox]::Show`: eight calls,
covering confirmations of uninstall, import, self-update and the winget install, errors, and "nothing
selected". The system MessageBox ignores the app's theme, so in Dark it came up white in the middle
of a dark window. Some calls passed no owner either, so the box opened in the middle of the screen,
not over the app.

The MessageBox also gave a few things for free, and some of them are safety rules here:
- Enter picks the default button, and every confirmation sets it to **No**;
- Esc and the close button answer the safe way;
- the system sound for each kind of message;
- Ctrl+C copies the text;
- the box is modal to the window.

## Decision

**Every dialog goes through `Show-AppDialog` (`App.Ui.ps1`), a window of the app's own.**
- It takes the same enums as the MessageBox (`MessageBoxButton`, `MessageBoxImage`,
  `MessageBoxResult` for the default) and returns a `MessageBoxResult`, so call sites read the same
  and the static checks on "confirmation before action, default No" still hold.
- `New-AppDialog` builds the window without showing it, so the tests can inspect it. Its XAML is a
  here-string in the module, so `build.ps1` needs no fourth file and no new marker.
- **Styles and colours come from the main window.** `$window.Resources` is merged into the dialog's
  resources, so the dialog uses the same Button template and the current theme's brushes. Colours
  are `DynamicResource`, as everywhere (ADR 0010).
- **Its own title bar follows the theme.** `Set-TitleBarDark` takes the target window, and the
  dialog calls it at `SourceInitialized` with the theme that `Set-Theme` records.
- **The icon is the one the Result column uses for the same meaning**: error `EB90` in `ErrBrush`,
  warning `E814` in `WarnBrush`, plus `E946` (information) and `E9CE` (question) in `AccentBrush`.
- **The text is a read-only TextBox**, so it can be selected and copied.
- **The buttons:**
  - the default one (No on confirmations) answers Enter and has the accent colour, so the button
    Enter will press is visible;
  - the last one answers Esc, and so does the close button: No, or OK;
  - the default button has the focus when the dialog opens;
  - the click handler reads the window from the sender, not from a captured variable (ADR 0008).
- **Placement**: centred on the app (`Owner` plus `CenterOwner`), never in the taskbar, not
  resizable.
- **The sound**: the one the MessageBox plays for the same image.
- **The main window dims behind the dialog.** A `DialogDim` border covers the whole window, its
  margin included, in `DimBrush` (lighter in the light theme). `Set-DialogDim` fades it in and out
  in 150 ms, or switches it with no fade when Windows animations are off.
- **Fallback**: if the dialog cannot be built (a broken theme or XAML), `Show-AppDialog` uses the
  system MessageBox. A message must not get lost exactly when something is broken. The fallback
  is the only `[System.Windows.MessageBox]::Show` left in `src`, and `Test-Ui.ps1` checks that.

## Consequences

**Positive**
- Dialogs match the window in both themes, title bar included, and open over the app.
- Every behaviour the MessageBox gave for free is kept, and the default-No rule still holds.

**To watch**
- **`Owner` only on a visible window.** WPF throws when the owner has never been shown. Before the
  window opens, and in the hidden test window, the dialog centres on the screen instead.
- **No fade of the dialog itself.** A window's opacity needs `AllowsTransparency=True`, which forces
  `WindowStyle=None` and would lose the themed title bar. Windows animates the window's opening
  anyway.
- **The fade must not hide a newer dialog.** Two dialogs can come in a row: a confirmation, then an
  error from the job it started. When a fade-out ends, it collapses the dim only if no dialog has
  turned it back on since (`$script:dimOn`).
- A new dialog is one `Show-AppDialog` call. `[System.Windows.MessageBox]::Show` anywhere else
  fails the tests.

## Alternatives considered

1. **The system MessageBox** — white in Dark, and centred on the screen when no owner is passed.
2. **A dialog drawn inside the main window**, like the Windows 11 ContentDialog. It cannot be
   moved, and waiting for the answer needs a nested dispatcher frame and focus handling. A separate
   modal window gives that for free; the dim gives the same "the app is waiting" look.
3. **A borderless window with a fade-in** — it loses the themed native title bar for an animation
   that Windows already provides.
