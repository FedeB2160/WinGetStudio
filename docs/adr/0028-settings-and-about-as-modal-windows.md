# ADR 0028 — Version 2 opens Settings and About as modal windows, and gives areas room of their own

- **Status:** Accepted (for 2.0; amends ADR 0011 and ADR 0027 there)
- **Date:** 2026-10-29
- **Depends on:** ADR 0011, ADR 0020, ADR 0027

## Context

1.x puts Settings and About at the right end of the tab strip (ADR 0011). That needs a `TabControl`
re-templated with a `DockPanel` as items host, because `TabPanel` cannot right-align one item. ADR 0011
also turned down a second window, because the 1.x theme brushes lived in the main window's merged
dictionaries and a separate window would have had to be wired to them.

In 2.0 the Fluent theme comes from `Application.ThemeMode` (ADR 0027): every window is themed by
itself, as the themed dialogs already show (ADR 0020). ADR 0027 forbids templates of our own, so the
1.x tab strip cannot be ported. The first 2.0 Settings and About tabs (phase 1, PR 4) sat at the
left, after Updates, with nothing to set them apart from the three tabs that work on packages.

The same review of the PR 4 screenshots found two smaller faults: the grid text sat a few pixels
above the middle of its row, and the Fluent grid frame, drawn by its rounded background, closed the
list on all four sides.

## Decision

1. **Settings and About are modal windows** owned by the main window, opened by two icon buttons at
   the top right of the window, over the empty right end of the tab strip. They go through
   `IDialogService` like the dialogs: the main window is dimmed and blocked, the work going on in it
   continues, and the log keeps writing under the veil. **Close** is the cancel button, so Esc closes.
   A dialog opened from a page (an update confirmation from Settings) is owned by the page, not by
   the main window, or it would open behind it.
2. **Settings keeps its view model.** `SettingsViewModel` does not change; only where it is shown.
3. **Areas get cards**: a section header and a `Border` with the Fluent card keys
   (`CardBackgroundFillColorDefaultBrush`, `CardStrokeColorDefaultBrush`, `OverlayCornerRadius`),
   as in the Windows 11 Settings app. Still no colour and no template of our own.
4. **About carries the logo** (`assets\icon\icon-128.png`, the same file as the README) and the
   version, a longer list of what the app does, and a "Good to know" card. The exe gets
   `assets\icon.ico` as its icon, which WPF also uses for every window.
5. **Grids are open at the sides**: `BorderThickness="0,1"` and a transparent background (the Fluent
   background is rounded and drew the sides on its own), horizontal lines only. Text columns get an
   element style that centres the `TextBlock` vertically: the cell's `VerticalContentAlignment` does
   not reach it. **A click selects the whole row**: the clicked cell keeps the row's selection colour
   and loses its focus frame. **Grids stay anchored to both sides**: no horizontal scroll bar, so
   widening a column narrows the `*` columns instead of pushing the grid past the edge.
   **Select all is a check box in the header** of the Updates grid: on, off, or indeterminate when
   only some rows are ticked. It sits in a `HeaderTemplate`: a control set straight as the column
   `Header` is bound before it enters the visual tree and never finds the grid.
6. **The tab area is a card**: the Fluent `TabControl` template already draws a border and background
   from `BorderThickness`, `BorderBrush` and `Background`, so the tabs get the card keys and their
   content a 12 px margin. **The shared progress bar is 8 px** instead of the Fluent 4: it is the only
   sign, from every tab, that a queue is working.
7. **A solid window background instead of Mica** (amends ADR 0027, point 6): Mica tints the window
   with the colour of the desktop wallpaper, which read as blue in the dark theme. The runtime
   switch `Switch.System.Windows.Appearance.DisableFluentThemeWindowBackdrop` (in the project file)
   makes the Fluent theme use its `WindowBackground`, the plain Windows dark or light grey.
8. **States that can be seen.** Several Fluent defaults vanish on the dark theme (the card stroke is
   black at 10%, a hovered button goes from 6% to 8% white). The app redefines, in its own
   resources, the keys the Fluent templates already read, with brushes bound to other Fluent
   *Color* keys of the current theme, so they follow a theme change: `ButtonBackgroundPointerOver`
   (`ControlStrongStrokeColorDisabled`), `ButtonBorderBrushPointerOver` and
   `TabViewSelectedItemBorderBrush` (`SurfaceStrokeColorDefault`). Cards, tabs and the tab area use
   `SurfaceStrokeColorDefaultBrush` as border. Each tab has its border and 6 px around its name, and
   no horizontal margin: `TabPanel` lays tabs out without it and clips each tab's right border by
   that much. Grids and tab names use 13 px (`ListFontSize`, one below Fluent's 14), and column
   headers have no vertical separators, like the rows. The selected one has the tab area's background and a semi-bold title (set in the header
   template: on the `TabItem` it would reach the content). Settings and About show glyph and name.
9. **Loading has a spinner, queues a bar.** Scans, searches, export and the update check show a
   spinner next to their button (`Spinner`, an arc drawn and turned by the app, still when Windows
   animations are off). The shared progress bar shows only during a queue or a long operation
   without a spinner of its own (`AppState.ShowProgress`), hidden otherwise without moving the log.
10. **Every grid has Select all in its header** (on, off, indeterminate), on the rows the tab allows:
    all in Install, the non-pinned ones in Updates, the visible ones in Installed (never rows the
    filter hides). The check box, pin and result columns cannot be resized. Column titles are
    centred through an implicit `DataGridColumnHeader` style: with the Fluent theme the headers take
    the style by type and ignore the grid's `ColumnHeaderStyle`. Truncated cell text shows in full
    in a tooltip.
11. **Third review (2026-10-30).** Borders of areas, tabs, grids and buttons use the theme's strong
    stroke (`ControlStrongStrokeColorDefault`, white on dark and black on light) at 55%: the Fluent
    grey, the same in both themes, made the window read as one block. Grids are closed on all four
    sides by the rounded Fluent border again (open sides left the header ending in nothing),
    with horizontal lines only inside. Inactive tabs are grey; the active one is bold and 2 px
    larger. The shared progress bar becomes a status line, "Updating 2 of 3: LibreOffice" with a
    thin bar, and the Result column shows the spinner while a row runs. Check for updates is never
    disabled by a queue (it talks to GitHub and asks `winget --version` under the lock); installing
    the update still waits. Settings gains **Start with Windows**: a `Run` entry for the user, which
    is itself the state, off in a development build.
12. Shared styles live in `Styles.xaml`, merged into each window's resources rather than into
   `App.xaml`, because the window smoke test runs under an `Application` of its own.

## Consequences

**Positive**
- The three tabs are only about packages; Settings and About are one click away from any of them.
- No template of our own, and the pages follow the theme with no wiring.

**To watch**
- A page is modal: while Settings is open the lists cannot be used. Fine for a page that is opened,
  changed and closed; a setting that needs to be watched while working would need another place.
- "Restart as administrator" (ADR 0024, phase 1 PR 5) lands in the Settings window.
- Closing the app from a page (an update that restarts it, No to installing winget) closes the page
  first.

## Alternatives considered

1. **Re-template the `TabControl`** as in 1.x — keeps the tabs at the right, but is the template
   ADR 0027 rules out, to be re-checked at every .NET update.
2. **Tabs at the left, after Updates** — the PR 4 layout: nothing tells the settings apart from the
   lists.
3. **A navigation pane (NavigationView style)** — more room, but more chrome than three tabs and two
   pages need, and no standard WPF control.
