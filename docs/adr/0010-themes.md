# ADR 0010 — Themes

- **Status:** Accepted
- **Date:** 2026-08-04 (in place since v1.9.0 or earlier; contrast floors, surface step, `CtrlBorderBrush` and the themed scrollbars came in v1.10.0)
- **Depends on:** ADR 0001
- **Referenced by:** ADR 0011, ADR 0016

## Context

The app has a light and a dark theme from v1.0.0, chosen as `Light`, `Dark` or `System` (called
`Auto` until v1.10.0) and switched while the window is open. The system WPF theme (Aero2) hardcodes
light colours in places no external setter can reach, and a colour that works in one theme can be
unreadable in the other. Each of the rules below was a visible defect first.

## Decision

**The palette lives in two dictionaries**, `ui\Theme.Light.xaml` and `ui\Theme.Dark.xaml`.
`Set-Theme` clears the window's `Resources.MergedDictionaries` and adds the chosen one, so the window
is repainted without being rebuilt; in dark it also sets the DWM immersive dark mode attribute,
since the title bar is drawn by Windows, not WPF.

**Colours are always `{DynamicResource ...}`.** `StaticResource` resolves once and would not follow
a theme change. **Both theme files define the same keys.**

**No colour is hardcoded in `UI.xaml`.** The *Update to vX.Y.Z* button carried `Foreground="White"`:
4.53:1 on the light accent (`#0078D4`), **2.01:1** on the dark one (`#4CC2FF`) — unreadable on the
one button that only appears when there is something important to say. Its foreground is now a
theme key, `AccentFgBrush` (`#00243A` in dark, 7.97:1).

**Contrast floors are measured, not eyeballed.** Every foreground/background pair in both themes
is checked against WCAG: 4.5:1 for text, 3:1 for graphical elements such as the status glyphs and
the progress fill. The light warning colour failed at 2.86:1 and was darkened (`#8A6F00`, 4.35:1
in the file's own note).

**A control needs a surface step or a visible border.** The light theme had neither: `BgBrush`
`#FFFFFF` and `CtrlBgBrush` `#FDFDFD` — a 0.6% luminance step, which is to say none — so the only
thing defining a button, a text box, the log or a tab was a `#CCCCCC` hairline at 1.61:1, and the
disabled state's `Opacity 0.5` took that to about 1.31 and erased it. Now:

| Key | Light | Dark | Role |
|---|---|---|---|
| `BgBrush` | `#F3F3F3` | `#202020` | the page |
| `CtrlBgBrush` | `#FFFFFF` | `#2D2D2D` | control surface |
| `CtrlBorderBrush` | `#8A8A8A` (3.11:1 on the page, 3.45:1 on the control) | `#666666` (2.84:1) | border of an **interactive** control |
| `BorderBrush2` | `#DCDCDC` | `#3D3D3D` | grid lines only |

Light meets the 3:1 WCAG 1.4.11 asks of anything that identifies a component. Dark stays under it
on purpose: on a dark ground the surface step does the work, and a 3:1 outline is heavier than
anything Windows 11 draws — still three times the `#3D3D3D` it replaces. A disabled button keeps its
outline and dims only its label; the disabled trigger no longer uses `Opacity`.

**Controls Aero2 paints in light colours are re-templated:**

- **CheckBox** — the tick is filled with `#FF212121` declared as a `StaticResource` inside the system
  theme, so in dark it was black on black.
- **DataGridColumnHeader** — `DataGridHeaderBorder` ignores `Background`. Re-templating throws away
  the two `Thumb`s `PART_LeftHeaderGripper` / `PART_RightHeaderGripper` that DataGrid hooks for
  column resizing; they are added back under those exact names, or the columns silently become
  fixed with no error at all. The header template binds `HorizontalAlignment` to
  `HorizontalContentAlignment`, or centring a header has no effect.
- **ContextMenu / MenuItem** — light background, black text, blue highlight.
- **ComboBox** — WPF requires a `ToggleButton` bound to `IsDropDownOpen` and a `Popup` named
  `PART_Popup`. The ToggleButton is transparent and sits over the border, catching clicks across the
  whole control without nesting one template in another.
- **ScrollBar** (v1.10.0) — the last control still painted by Windows: every scrollbar stayed white in
  dark. The replacement is track plus thumb, no arrow buttons, as Windows 11 draws it. It keeps the
  `Track` named `PART_Track` (rename it and the bar stops working, with no error) and the two
  transparent `RepeatButton`s that page up or down on a click in the empty track. An `Orientation`
  trigger swaps the axes for the horizontal bar.

Tooltips follow the theme too, and a long one wraps (v1.10.1); they used to arrive white with black
text over the dark theme.

**Glyphs are written `[char]0xE706`**, never `` "`u{E706}" ``: that escape exists from PowerShell 6
on, and ps2exe compiles against 5.1, where it stays the literal text `u{E706}`.

## Consequences

**Positive**
- A theme switch repaints in place, and every colour follows it.
- A contrast or border regression fails the suite instead of shipping.

**To watch**
- Adding a colour means adding it to both theme files and, if anything sits on top of it, adding the
  pair to the contrast check in `Test-Ui.ps1`.
- `Test-Ui.ps1` fails on a key present in only one theme, on a `DynamicResource` that does not
  resolve (only keys containing `Brush` are checked, because of two non-colour keys, ADR 0011), on
  missing header grippers, on a `&#x....;` glyph absent from either system icon font, and if the
  disabled trigger goes back to `Opacity`. It also measures the surface step and both border pairs.
- If paging on the horizontal scrollbar ever goes the wrong way, name its two repeat buttons and
  swap their commands to `PageLeftCommand` / `PageRightCommand`.

## Alternatives considered

1. **`StaticResource`** — turned down: resolves once, does not follow a theme change.
2. **`Opacity` for the disabled state** — turned down: erased the only border a control had.
3. **`CtrlBorderBrush` at 3:1 in dark too** — turned down: heavier than anything Windows 11 draws.
4. **Grid lines at the same strength as control borders** — turned down: the grid turns into a
   spreadsheet, so `BorderBrush2` keeps the lighter value for grid lines only.
