# ADR 0017 — The app icon is drawn in code

- **Status:** Accepted
- **Date:** 2026-10-08
- **Depends on:** ADR 0001, ADR 0014

## Context

Up to v1.11.0 `assets\icon.ico` held a single 256 px PNG frame, a white download arrow on blue,
unchanged since the initial commit. Windows scaled it down for every other size, so it came out
blurred exactly where it is seen most:
- the title bar (16 px);
- the taskbar (24 px at 100%);
- Alt+Tab and Explorer (32 and 48 px).

The same file feeds three places, none of which needs to change:
- the exe, through ps2exe `-iconFile` (ADR 0001);
- the setup, through `SetupIconFile` (ADR 0014);
- the window when running from source, through `Resolve-Asset 'assets\icon.ico'`.

Constraints are those of the rest of the repository: Windows PowerShell 5.1, nothing beyond what
Windows ships with, and a result that can be reviewed and rebuilt.

## Decision

**What it shows.** The icon has three elements:
- a cardboard box in isometric view, for the package, which is what winget manages;
- `>_` stamped on the box's side, for the command line the package comes from;
- a blue badge with a download arrow, cut out from the box by a transparent ring.

The box is cardboard, not blue. In a taskbar full of blue squares a warm hexagon is recognised at a
glance, and a blue box with an arrow would look like one of Microsoft's own icons, since winget ships
with App Installer. The badge keeps the blue of the previous icon.

**Drawn by `src\icon.ps1`**, which renders with WPF (`DrawingVisual` → `RenderTargetBitmap` → PNG). It
is run by hand when the icon changes, and its output is committed; the build does not run it.

**14 frames in the `.ico`:** 16, 20, 24, 30, 32, 36, 40, 48, 60, 64, 72, 80, 96 and 256. This is
Microsoft's list for Win32 app icons, the sizes Windows asks for at the common display scales; for
anything larger it scales down the 256. Next to the `.ico`, `assets\icon\icon-<n>.png` holds the
same icon at 16, 24, 32, 48, 64, 128, 256, 512 and 1024 px, for wherever a PNG is needed.

**Three levels of detail, each designed on its own grid.** A detail that cannot be drawn in whole
pixels is dropped rather than left as a smudge:

| Sizes | What is drawn |
|---|---|
| 16–20 px | box, tape, badge |
| 24–40 px | adds a `>` stamp |
| 48 px and up | the full `>_` |

**Snapped to the pixel grid at every size.** This keeps 20, 24 and 30 px as sharp as the sizes the
grids were drawn at:
- the box's vertical edges fall on whole pixels;
- the isometric slope is exactly 2:1, so diagonal edges step two pixels at a time;
- the arrow's shaft sits on a half pixel when its stroke is odd.

**All frames are PNG**, like the single 256 px frame before them, which ps2exe and Inno Setup already
accepted. Windows reads PNG frames at any size since Vista.

`Test-Ui.ps1` fails if any of the 14 sizes is missing from `assets\icon.ico`.

## Consequences

**Positive**
- Sharp at every size Windows asks for, instead of a 256 px image scaled down.
- Changing the icon is a code change: a diff to review, a script to rerun, the output to commit.
- No new dependency: WPF ships with Windows, like everything else the app uses.

**To watch**
- **`assets\icon.ico` and `assets\icon\` are generated.** Edit `src\icon.ps1`, never the files.
- **The script needs an STA thread.** `powershell.exe` 5.1 runs on one; `pwsh` needs `-STA`. The script
  says so and stops otherwise.
- **Explorer caches icons.** After a rebuild the exe may still show the old icon until the cache is
  refreshed (`ie4uinit.exe -show`).
- **Small PNG frames.** If some program ever rejects them, the frames up to 48 px have to be written
  as 32-bit BMP. That is a few lines in the writer.

## Alternatives considered

1. **An SVG master rasterised by Inkscape or ImageMagick** — the usual route for icons. Turned down:
   every machine that rebuilds the icon would need an external tool.
2. **An SVG rasterised by Edge headless** — available on every Windows machine. Turned down: the
   minimum window size and the transparent background make exact 16–48 px renders unreliable.
3. **Drawn by hand in an icon editor** — fine once, but not reproducible, and a binary `.ico` gives
   nothing to review.
4. **Keep the single 256 px frame** — the status quo, blurred at the sizes Windows shows most.
5. **A terminal window with a download badge**, or **a blue tile with `>_` and an arrow** — the other
   concepts drawn. Neither says "package". At 16 px a dark window vanishes on a dark taskbar and looks
   like Windows Terminal.
