# ADR 0011 — Window layout

- **Status:** Accepted
- **Date:** 2026-08-24 (v1.10.0; the tooltip rule came in v1.10.1)
- **Depends on:** ADR 0003, ADR 0010

## Context

In v1.9.0 the window had three functional tabs, a progress bar and a log shared by all of them, and
a gear button in the top-right corner opening a settings screen: a `Border` with
`Grid.RowSpan="4"` covering the whole window. That overlay hid exactly the part of the window that
reports how an operation is going, and needed a chain of `ZIndex`, focus and Esc handling to behave
like a screen. The busy state is global (ADR 0003), so whatever is running must stay visible
wherever the user is.

## Decision

**The progress bar and the log live outside the `TabControl`**, so they stay visible from every
tab.

**Settings and About are tabs**, at the right end of the strip, not an overlay and not a second
Window. As tabs they need no `ZIndex`, focus or Esc handling. A second Window was not taken because
the theme brushes live in the main window's `MergedDictionaries` (ADR 0010): a separate Window would
have to be wired to those dictionaries and re-wired on every theme change, plus owner, modality and
placement.

**The tab strip is a `DockPanel` used as `IsItemsHost`**, because `TabPanel` cannot right-align a
single item. The functional tabs take the default `Dock="Left"` in declaration order; Settings and
About declare `Dock="Right"`; `LastChildFill="False"` stops the last one stretching across the strip
(the same trap that once centred the settings close button). In a `DockPanel` the *first*
`Dock=Right` child takes the right edge, so `TabAbout` is declared before `TabSettings` because it is
the one further right, and it carries the negative right margin that keeps the last tab flush with
the frame. The `Margin="0,0,0,-1"` seam between active tab and content border sits on the panel.

**Functional tabs are alphabetical — Install | Installed | Updates — and Updates is the default
view** (`IsSelected="True"`): the startup scan fills that list, and opening on a tab nobody is looking
at would hide the update count. Navigation order and default view are separate concerns.

**One `HeaderTemplate` for every tab.** The glyph comes from each tab's `Tag` through
`RelativeSource AncestorType=TabItem`; `Header` stays the plain string, which is the accessible name
and what the tab-order checks rely on. What the strip shows — icon, name or both, chosen in Settings
— is two `Visibility` values in the window's own `Resources`, read with `DynamicResource`; `Set-Theme`
clears `MergedDictionaries`, not those. Details that hold it together:

- The gap between icon and word is a **symmetric** margin on the icon (`4,0,4,0`), the only form that
  centres in every mode. On the word it leaves the word off-centre in *Text* mode; asymmetric on the
  icon it leaves the glyph off-centre in *Icon* mode, because a margin outlives the element it was
  meant to separate from. A trigger cannot fix it — a `DataTrigger`'s `Binding` does not accept a
  `DynamicResource` — and neither can a `Thickness` held as a resource and rewritten from PowerShell:
  layout then fails with `InvalidCastException` on the first measure pass.
- The header panel has `MinHeight=16`; without it the strip shrank by 2px in *Icon* mode, because the
  glyph's line box is shorter than the text's and, with the word collapsed, only the glyph set the
  height. 16 is what the text occupies on its own, so the strip is 29px in all three modes.
- Each `TabItem` has `AutomationProperties.Name`, or an icon-only tab announces nothing.

**A tooltip never sits on a container whose content has none of its own.** `ToolTipService` walks up
the *logical* tree as well as the visual one, and a tab's content is a logical child of its
`TabItem`: a tooltip on the `TabItem` was found by every control in the page, so hovering *Check for
updates* opened "Theme, tab strip, version and updates" (v1.10.1). Walking only the visual tree says
this cannot happen, which is why it survived a static check; the proof came from a real window,
printing the open `ToolTip` and its `PlacementTarget` while the cursor sat on the button. The text now
lives in the tab's `AutomationProperties.HelpText` (where a screen reader wants it anyway), and the
tooltip is carried by the `Border` inside the `TabItem` template, which covers the whole tab and is an
ancestor of nothing in the page.

**An empty string is a tooltip.** `ToolTipService` shows whatever is not `null`, so
`ToolTip="{Binding StatusDetail}"` on the always-present `Grid` of the Result cell opened an empty grey
box over every row with no result, because starting a queue resets `StatusDetail` to `''`. The binding
sits on the status glyph instead, which is `Collapsed` until there is something to say, and a collapsed
element does not take the mouse.

**During an operation the grids go read-only, not disabled**: a disabled `DataGrid` stops responding
to wheel, scrollbar and keyboard, so the list looked frozen.

Smaller rules: the lazy load of Installed compares `SelectedItem` with the `TabInstalled` object, not
its header string — the Settings tab's header is not even a string (glyph plus word), and a rename must
not silently switch the automatic load off; the search spinner sits at the end of its row, since docked right it took 20px
off the search box during every search; the shortcuts (**F5**, **Ctrl+F**) are caught with
`PreviewKeyDown` on the window: in tunnelling the window sees the key first, while a focused
`DataGrid` would swallow F5 and Ctrl+F itself. The active tab decides what F5 reloads. (In v1.9.0 the
same handler caught **Esc** for the settings overlay, since after a click inside the panel the focus
belonged to a control and a handler on the panel never saw the key; the overlay and Esc are gone.)

## Consequences

**Positive**
- The progress and the log are visible from Settings and About.
- No overlay plumbing; theme changes reach Settings for free.
- Tab strip mode changes repaint without rebuilding anything.

**To watch**
- Because of the two `Visibility` keys, the "every `DynamicResource` exists in both themes" check
  looks only at keys containing `Brush` (ADR 0010).
- `Test-Ui.ps1` walks the logical tree of every tab and fails if any control resolves its tooltip to
  a `TabItem`.

## Alternatives considered

1. **Full-window overlay for Settings** — the v1.9.0 design, removed in v1.10.0 for hiding the
   progress and log.
2. **Settings as a second Window** — turned down: theme dictionaries, owner, modality and placement
   to wire by hand.
3. **`TabPanel`** — cannot right-align a single item.
4. **Four hand-built headers** — replaced by one template fed by `Tag`.
5. **Disabled grids** — turned down: they stop scrolling.
