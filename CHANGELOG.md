# Changelog

## v1.10.1

Fixes only, all of them found in 1.10.0. Coming from v1.10.0: download the new exe and delete the old one, or let the app update itself from **Settings** — unless you installed it with winget, in which case read the first entry.

### Installed with winget, the app no longer replaces itself

A winget `portable` package is a file winget owns: it keeps the exe in its own folder, records the file's SHA-256, and expects to find exactly that back. Updating from **Settings** renamed that file and wrote a new one over it, which left winget with a hash that no longer matched, a leftover `.exe.old` it had never installed, and an uninstall entry still naming the old version. From there `winget upgrade` and `winget uninstall` refused to touch the package and `winget install` answered that it was already installed, so the app could neither start nor be reinstalled.

When the running exe sits in winget's package folder, the update button no longer appears and **Check for updates** says to use `winget upgrade FedeB2160.WinGetStudio` instead. Nothing changes for a copy of the exe you placed yourself.

If a machine is already in that state: `winget uninstall FedeB2160.WinGetStudio --force`, then install again from an elevated prompt.

### Tooltips belonging to something else

Hovering a control with no tooltip of its own showed the tooltip of the tab it was in — hovering **Check for updates** in Settings explained the Settings tab. WPF looks for a tooltip by walking up from the control, and it walks the logical tree, where the content of a tab hangs off the tab itself; the text has moved off the tab and onto the tab's own header, so it stays where it belongs.

The Result column had a second one: an empty grey box opened over every row that had no result yet, because an empty string is a tooltip as far as WPF is concerned. It only appears now when there is a result to explain.

Tooltips also follow the theme, instead of arriving white with black text over the dark one, and a long one wraps rather than running off the screen.

### The Updates section of Settings reads in two lines

Version, **Check for updates** and its outcome share one line, the startup check the next, each with its label on the left like the rest of the page. Before, three of them were stacked with nothing in the label column, so the checkbox and the buttons floated in the middle of the page.

## v1.10.0

Coming from v1.9.0: download the new exe and delete the old one, or let the app update itself from **Settings**. Your theme carries over; if it was set to `Auto` it becomes `System`, which is the same thing under a name that says what it does.

### Settings and About are tabs now

The gear button and the full-window overlay behind it are gone. **Settings** and **About** are tabs at the right end of the strip, so the progress bar and the log stay visible while you are in them — the overlay used to cover exactly the part of the window that tells you how an operation is going.

The three functional tabs are in alphabetical order, **Install | Installed | Updates**, and Updates is still the view the app opens on, since that is what the startup scan fills.

Every tab has an icon and a tooltip, and **Tab strip** in Settings chooses whether the strip shows the icon, the name, or both.

**About** says what the app actually does: the five features in a table, name and description aligned, followed by links to the source, the release notes, the licence and where to report a bug.

### Updates you can stop, and a list that stops lying

**Update** turns into **Cancel** while its own queue runs. Cancelling lets the package in flight finish and then stops: nothing is killed halfway through an installer, and the packages that never ran keep their tick and an empty result.

After an update, an install, an uninstall or an import, **Update** locks until the next **Check**, and the counter says why. Pressing it again used to re-run winget on packages that were already current, which exits non-zero and painted a red cross over rows that had in fact succeeded. Pins do not lock it: a pin blocks upgrades, it does not change installed versions.

While a queue runs the ticks and the pin entries are visibly disabled rather than merely refusing to work, and the lists still scroll. They were blocked before; they just did not look it.

### Fixed: two winget processes at once

Typing in **Install** and switching straight to **Installed** could run `winget search` and `winget list` at the same time, which is how a winget command ends up failing for no visible reason. A search counts as winget work like everything else now, and the update, install, uninstall and pin queues all pass through a single place that takes the busy state and refuses to start a second process.

### The light theme has structure again

Buttons, text boxes, the log and the tabs sat on a white page with an almost-white fill and a hairline border, so they were nearly invisible — and a disabled button vanished completely. The page is a light grey with white controls on it now, the way Windows 11 does it, the border that marks an interactive control is a stronger colour than the grid lines, and a disabled button keeps its outline and only dims its label.

The **Update to vX.Y.Z** button is readable in the dark theme: its label was white on the accent colour, which measured 2.01:1 there. The light theme's warning glyph was below the threshold too and has been darkened. Every foreground/background pair in both themes is measured by the test suite now, so this cannot come back quietly.

The scrollbars follow the theme. In the dark theme they used to stay white, the last piece of the window that Windows still painted its own way.

### Your choices are remembered

**Unknown**, **MS Store** and **Scope** used to reset at every launch while the theme did not. They persist now, and ticking **Unknown** rescans immediately instead of quietly applying to the next check.

The startup check for a new release can be turned off, from **Check for updates at startup**. It is on by default, as it always was; the point is that a program going online by itself should say so and leave you the choice.

### Smaller things

- **F5** rescans the active tab, **Ctrl+F** jumps to the search box.
- The progress bar goes **indeterminate while scanning** rather than sitting at zero, which looked like something stuck. It shows real progress only for a queue, which knows how many packages it has.
- The context menu entries say they act on the **highlighted** rows rather than the ticked ones. That was always true and documented only in the code, which nobody reads with the right mouse button held down.
- The status icons in the Result column carry accessible names, so a screen reader announces "Succeeded" or "Failed" instead of the character code behind the icon.
- Internally: every winget invocation uses the path resolved once at startup rather than looking the name up on each call, and a command line whose quotes do not balance is refused instead of being run.

## v1.9.0

**The tool was renamed.** `WinGetUpdateTool.exe` is now **`WinGetStudio.exe`** — the old name only described a third of what it does.

Coming from v1.0.0: download the new exe and delete the old one. The theme preference resets once, having moved to `HKCU:\Software\WinGetStudio`.

### Three tabs instead of one screen

**Updates** — what it always did: `winget upgrade` in a checkbox table, sequential upgrades by ID, per-row result and a log.

**Install** — find and install something new. Results appear **as you type**, so there is no autocomplete popup: the grid *is* the suggestion list, and version and ID are visible before choosing.
- Searches the local winget catalogue. An **MS Store** checkbox adds the Microsoft Store, but only for an explicit search, since going online is far slower and cannot keep up with typing.
- **Scope** chooses `Auto` / `User` / `Machine`. The app runs elevated, so it warns once if the elevated account is not the signed-in user, where a per-user package would land in the wrong profile.
- Double click a row to install just that one.

**Installed** — the inventory of the machine, loaded on first entry into the tab rather than at startup.
- A **filter box** narrows the list locally, without calling winget again.
- **Uninstall** is behind a Yes/No confirmation with **No as the default**, listing the actual package names. If the filter is hiding a ticked package, both the counter and the dialog say so, so nothing is removed off screen.
- Packages not installed through winget appear too, with IDs like `ARP\Machine\X64\Android Studio`, and uninstall like any other.

### Pinning
Right click a row in Updates or Installed: **Pin (block upgrades)** / **Remove pin**. A pinned package is skipped by updates, including *Select all*, and shows a pin icon. It can still be uninstalled: a pin blocks upgrades, not removal.

### Export and import
**Export** saves the installed packages to a `.json` file, **Import** installs what a list describes — the quick way to rebuild a machine.
- Export omits exact versions on purpose: pinning them makes the import fail as soon as one is no longer published.
- Import ignores unavailable packages, so a single unpublished one cannot abort everything, and asks for confirmation stating how many packages the file contains — a count read from the file, not an estimate.

### Settings screen and automatic updates
The **gear button** in the top-right corner opens a settings screen (closed by the X or **Esc**): theme as a `Light` / `Dark` / `Auto` dropdown, the installed version, and **Check for updates**.

The app checks GitHub for newer releases at startup — one anonymous API call, no token. When one exists, an **Update to vX.Y.Z** button appears. The download is confirmed explicitly, verified against the SHA-256 GitHub publishes with the asset, and installed by the app replacing itself and restarting. No external updater.

### Signed, but by a self-signed certificate
The exe is signed (`CN=WinGet Studio`) with a DigiCert timestamp, which proves the file has not been altered since the build.

**Windows still says "unknown publisher"**, because the certificate is self-signed and its root is not trusted. That is expected and does not mean the signature is missing. To make it trusted, import `assets/WinGetStudio-codesign.cer` (public certificate, no private key) into *Trusted Root Certification Authorities*.

### Under the hood
The single 744-line script became an entry point plus one module per concern under `src\modules\`. The exe is still a single file: the build concatenates the modules at compile time, while running from source dot-sources them from disk, so a module can be edited without recompiling.

The test suite exercises the real thing where it matters — a real winget search, a real package list, the full pin cycle (removed afterwards), a real export — plus checks only a machine can do reliably: that the concatenated exe source keeps every function, that the modules actually see the controls, and that every icon glyph exists in both system fonts.

## v1.0.0

First release, as **WinGet Update Tool**: `winget upgrade` in a checkbox table, upgrading only the selected entries, with automatic UAC elevation, a non-blocking UI and a light/dark theme.

This release was removed from GitHub after the rename: it carried the pre-rename binary, so the update check would have offered users a downgrade.

