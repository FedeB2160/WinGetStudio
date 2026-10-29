# ADR 0027 — Version 2 uses WPF's Fluent theme through ThemeMode, with no templates of its own

- **Status:** Accepted (for 2.0; supersedes ADR 0010 there and amends ADR 0011 and 0020)
- **Date:** 2026-10-29
- **Depends on:** ADR 0010, ADR 0011, ADR 0020, ADR 0023

## Context

1.x draws its own light and dark themes: two dictionaries of 17 brushes, and CheckBox, column header,
ContextMenu, ComboBox, ScrollBar and other controls re-templated because Aero2 hard-codes light colours
(ADR 0010), plus a P/Invoke for the dark title bar.

.NET 9 added the Fluent theme, set with `Application.ThemeMode` (System, Light, Dark). In .NET 10 the API
is still marked `Experimental("WPF0001")`, and controls with templates of their own do not pick it up.

A prototype of the 1.x layout on .NET 10 (2026-10-29), with no template or colour of its own, showed:

- every standard control styled: tabs, DataGrid, check and radio boxes, buttons, combo, text boxes,
  progress bar, scroll bars, context menus, hyperlinks, dialogs;
- `AccentButtonStyle` for the primary button; the Windows accent followed (`SystemColors.AccentColor`,
  `AccentFillColorDefaultBrush` as WinUI computes it);
- the WinUI tokens available by key: `TextFillColor*`, `SystemFillColorSuccess/Caution/CriticalBrush`,
  `ControlFillColor*`, `ApplicationBackgroundBrush`, `ControlCornerRadius` 4, `OverlayCornerRadius` 8;
- the title bar dark by itself in the dark theme, and a transparent window background (the system
  backdrop, Mica, on Windows 11);
- switching theme at run time by setting `ThemeMode`;
- rows taller than in 1.x and upper-case column headers cut off at 1.x widths.

## Decision

1. **`ThemeMode` only**, System by default, the user's choice kept in the 1.x preference `Theme`. No
   colour dictionaries, no re-templated controls, no DWM call for the title bar. `WPF0001` is suppressed
   and the SDK pinned (ADR 0026).
2. **Own resources only for meaning**, and always as references to Fluent keys: result glyphs use
   `SystemFillColorSuccess/Caution/CriticalBrush`, hints `TextFillColorSecondaryBrush`.
3. **Primary actions use `AccentButtonStyle`** (Update, Install, the default button of a dialog).
4. **Dialogs stay separate modal windows** (ADR 0020), themed by `ThemeMode`, with *No* as the default
   on confirmations.
5. **Column headers in sentence case** ("Installed version"), as Windows 11 writes them; row height and
   column widths set while porting, so that the Updates list shows as many rows as 1.x at the default size.
6. **Mica, the Windows accent and high contrast come from the theme.** They are checked by hand before
   release (high contrast and accent changes need Windows settings); Windows 10 gets an opaque background.

## Consequences

**Positive**
- Hundreds of lines of templates and the contrast bookkeeping of ADR 0010 go away; the app looks like
  Windows 11 and follows its accent and high contrast.

**To watch**
- An experimental API: a .NET update may change it. Pin the SDK and re-check the look on each upgrade.
- The 1.x tests that check templates, brush keys and upper-case headers do not carry over; the 2.0 smoke
  test checks that the theme loads and switches instead.

## Alternatives considered

1. **Port the 1.x templates and colours** — keeps a look Fluent replaces, and the templates would hide
   the Fluent styles.
2. **A Fluent library (WPF UI, ModernWpf)** — more controls, but a dependency where the platform now has
   the theme.
