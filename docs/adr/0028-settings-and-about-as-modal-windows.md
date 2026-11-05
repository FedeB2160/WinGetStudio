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
    with horizontal lines only inside. Inactive tabs are grey; the active one is bold at the same
    size (a larger title sat below its icon). The shared progress bar becomes a status line,
    "Updating 2 of 3: LibreOffice", with a 10 px bar clipped to rounded corners on the strong
    stroke as track, and the Result column shows the spinner while a row runs. Columns cannot be
    moved, and after any manual resize (drag or double click on the header edge) the resizable
    columns go back to `*` widths in the proportions chosen: a column widened to pixels used to push
    Result out of the grid. Settings is compact, in two columns (Appearance and Startup, Updates) so
    that new settings widen it instead of making it taller, with outcomes and notes on their own
    wrapped line. The count of updates is a badge overlaid on the top-right corner of the Updates tab (drawn
    shifted, so the tab keeps its width), in the accent colour, seen
    from every tab (grey, as if disabled, when another tab is active), instead of a
    "N updates available" line inside it. An update queue with failures no longer reloads the list
    (issue #24 reloaded after every queue): the rows keep their outcomes, the list is marked out of
    date (Update off, Retry failed on) and the next check is the user's. The pin menu shows Pin
    and Remove pin only when they would change one of the highlighted rows. Check for updates is never
    disabled by a queue (it talks to GitHub and asks `winget --version` under the lock); installing
    the update still waits. Settings gains **Start with Windows**: a `Run` entry for the user, which
    is itself the state, off in a development build.
12. Shared styles live in `Styles.xaml`, merged into each window's resources rather than into
   `App.xaml`, because the window smoke test runs under an `Application` of its own.
13. **Fourth review (2026-11-03), after a measured comparison with 1.12.** The text sizes come from
    one place: every window (main, Settings, About, dialogs) sets `FontSize` from `BaseFontSize`
    (12, as 1.x and the Windows list views), instead of Fluent's 14 in some windows and 13 inside
    the tabs. Column headers and notes use `CaptionFontSize` (12), section titles `SectionFontSize`
    (14, semi-bold), the empty-list message 16, the About title 20; text is regular weight, titles
    semi-bold, the active tab semi-bold rather than bold. Grid rows are 28 px (`ListRowHeight`): at
    24 the row check box was clipped. Column titles are in Title Case ("Package Name", "Package
    ID", "Installed Version"), and the ID column follows the name. Result is 56 px wide, the
    title's own width plus a margin. The vertical scroll bar sits outside the grid's border, in a
    column always reserved for it, so the columns do not move when it appears; the grid's own bar
    is hidden and wheel and keys still scroll it. A double click on a header edge (auto-fit) no
    longer ruins the grid: when the widened column does not fit, the others share the rest by
    their `*` weights, none below its title's width (the Fluent DataGrid had squeezed them, fixed
    columns included, to 20 px, and the refit saved that). Tabs stand 2 px apart (attached, the
    rounded corners met in a V; `TabPanel` ignores margins, so only the drawing is shifted);
    inactive tabs have a fainter border (25%) and tertiary text (secondary since point 16: the
    tertiary measured 3.28:1 in the light theme). Dialogs separate the buttons in a
    band with its own background and a line above, as 1.x did. The theme hint ("following the
    system: dark") is gone: it was clipped and the theme in use is on screen anyway.
14. **Settings with a menu on the left (2026-11-03)**, replacing the two columns of point 11: four
    cards of different sizes side by side read as clutter. A fixed 760×460 window with three
    sections, each a page: **Appearance** (theme, tab strip), **General** (Start with Windows,
    Always start as administrator, Close to tray, the periodic check) and **Updates** (WinGet
    Studio, winget, Check for updates). The menu is a Fluent `ListBox` with glyph and name, as in
    the Windows 11 Settings app; the chosen entry has a subtle background (the keys its template
    reads, redefined on Fluent subtle fills) and an accent bar. A line separates it from the page;
    a button at its top collapses it to icons only (names in tooltips), sliding in 150 ms when
    Windows animations are on, not saved between openings. It always opens on Appearance.
    Close sits in a band at the bottom, the same as the dialogs. The view model is unchanged.
15. **Tab borders (2026-11-03).** The tab area's border and the active tab's are 2 px, the inactive
    tabs' 1 px (the Fluent tab template fixes its border at 1 px on an inner `Border` that ignores
    `BorderThickness`, so the code sets it there). The strokes were translucent, and where they
    overlapped (tab edges on the area's top line) their light added up into bright dots: the main
    window now uses the same colours already blended on the window background, opaque, recomputed
    when the theme changes. Inactive tabs end above the area's line; only the active one covers it.
16. **Accessibility (2026-11-05), the high-severity findings of the UI/UX review.**
    - **Inactive tab text is secondary, not tertiary**: 6.07:1 in the light theme and 9.37:1 in
      the dark one, against the tertiary's 3.28:1, below WCAG AA. The active tab is still told
      apart by its semi-bold text, its 2 px border and covering the area's line.
    - **The keyboard focus frame is on the whole row.** The cell style had `FocusVisualStyle`
      null, so moving with Tab and the arrows showed nowhere where the focus was. Removing it
      was not enough, as the real app showed. Fluent has no implicit `DataGridCell` style, so the
      cell style is based on the classic one, which sets no focus visual. The cell then took the
      system one, `DefaultControlFocusVisualStyle`, drawn 3 px outside the element. It outlined a
      single cell, and on the check box and Result columns it ran past the grid's edge.
      Cells are back to `FocusVisualStyle` null. `RowFocusFrame`, an adorner, draws a 2 px frame
      inside the row that has the keyboard focus, as one element. It follows the focus, which with
      Ctrl+arrows can be on a row other than the selected one. It appears only when the focus
      arrived from the keyboard (`InputManager.Current.MostRecentInputDevice`), and a click or
      the focus leaving the grids removes it. The check boxes inside rows have no focus visual
      of their own either (`RowCellCheck`): with the focus on one, the two frames showed together.
      Select all, in the column header, keeps its own.
      It is an adorner and not the row's `BorderThickness`, which the Fluent row template does
      honour, because a border takes layout space. The cells presenter is held at `RowHeight`,
      so rows would grow from 28 to 32 px. The DataGrid measures the cells' offset from its
      scroll viewer, so the cells would also shift 2 px right of their titles, and the Result
      column would lose 2 px. The adorner lives in the scroll content presenter's layer, which
      clips to the grid's content.
      Its colour is `FocusStrokeColorOuterBrush`, nearly opaque, and not the translucent
      `KeyboardFocusBorderColorBrush` of the other controls' frames: over the selected row's blue,
      that one drops to about 2:1.
    - **Space checks the row with the focus.** The DataGrid does not use Space, and a check box
      in a template cell gets no keyboard focus from the arrows, so without a mouse no row
      could be checked. Space on a cell, with no modifiers, now toggles that row's check box,
      the framed row and not necessarily the selected one. It goes through the check box, so a
      disabled one (winget busy, a pinned row in Updates) stays as it is.
    - **Screen readers hear what changes.** `LiveRegion.Announce` (an attached property) sets
      `AutomationProperties.LiveSetting` to Polite and raises `LiveRegionChanged` each time the
      `TextBlock` gets a new, non-empty text: WPF raises nothing by itself. It is on the status
      line beside the bar ("Updating 2 of 3: ..."), on the `Hint` style (the counts next to the
      buttons) and on the empty-list message. The queue's summary ("Update complete: 2 ok, 1
      failed.") goes to `AppState.Announcement`, read by a transparent `TextBlock` in the status
      row: the bar's row is hidden when the queue ends, and a hidden element leaves the
      automation tree just when there is something to say. The Updates badge is named
      "N updates available" instead of a bare number with a help text.
17. **Clarity (2026-11-05), the medium-severity findings of the UI/UX review.**
    - **One name per action.** "Check for updates" always means the packages: the Updates tab
      button (it was "Check") and the notification-area menu. The Settings page of point 14 is
      **App updates**, and its button, which asks GitHub about WinGet Studio and winget, is
      **Check for new versions**. "Updates" is only the tab. An out-of-date list says "List out of
      date: press Check for updates."
    - **A filter that hides everything says so.** In Installed the grid gives way to "No
      installed package matches 'x'." and, on its own line, "Clear the filter to see all N.", as an Install search with
      no result does.
    - **Install for is a choice in sight.** The "Scope: Auto" button cycled through three values
      it did not show. It is now a Fluent `ComboBox` labelled "Install for", with Auto, Current
      user and All users; each item's tooltip says what it passes to winget. The saved values
      (`InstallScope`: Auto, User, Machine) do not change.
    - **A double click opens, it does not run.** In Install a double click on a row installed it at
      once, ticked or not, with no confirmation. It now opens the details (the same as the context
      menu item), whose button band offers **Install** and **Close**; Close is the default, so
      Enter and Esc close and only a click on Install installs that row, from its source.
    - **Errors say what to do next.** `ExitCodes.Hint` explains the winget codes it knows (names
      checked with `winget error`): needs administrator, application running, disk full, no
      network, restart Windows, sources that cannot be opened, and a few more. The Result tooltip
      shows it ("Needs administrator rights: use Retry as administrator (exit ...)", the Retry
      part only where that button exists, never elevated), and the log adds it under the
      failure. A failed export or import is no longer only in the log: a dialog gives the reason
      and the next step. A file that is not a package list says how to make one (Export...). A
      failed self-update or winget update says why and where to get it, in the note under the
      version, since the log is under the page's veil. Upper-case FAILED and WARNING stay in the
      log, where they help to scan it, and leave dialogs.

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
