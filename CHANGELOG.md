# Changelog

## Unreleased

- Settings is a tab pinned to the right of the strip instead of an overlay covering the window, so the progress bar and the log stay visible while you are in it. The gear button, the close button and Esc are gone with it. The three functional tabs are in alphabetical order — Install, Installed, Updates — and Updates is still the view the app opens on.
- The *Update to vX.Y.Z* button is readable in the dark theme: its label was white on the accent colour, which measured 2.01:1 there. The light theme's warning glyph was also below the threshold and has been darkened. Every foreground/background pair in both themes is now measured by the test suite.
- The scrollbars follow the theme. In the dark theme they used to stay white — the last piece of the window that Windows still painted its own way — because the system template hardcodes light colours and ignores what the app asks for.
- The status icons in the RESULT column carry accessible names, so a screen reader announces "Succeeded" or "Failed" instead of reading out the character code behind the icon.
- **The light theme has structure again.** Buttons, text boxes, the log and the tabs used to sit on a white page with an almost-white fill and a hairline border, so they were nearly invisible — and a disabled button vanished completely. The page is now a light grey with white controls on top of it, the way Windows 11 does it, and the border that marks an interactive control is a separate, stronger colour from the grid lines. Disabled buttons keep their outline and only dim their label.
- **Fixed: two winget processes at once.** Typing in Install and switching straight to Installed could run `winget search` and `winget list` together, which is how a winget command ends up failing for no visible reason. A search now counts as winget work like everything else, and the update, install, uninstall and pin queues all pass through a single place that takes the busy state and refuses to start a second process.
- The startup check for a new release can be turned off, from **Check for updates at startup** in Settings. It is on by default, as it always was; the point is that a program going online by itself should at least say so and let you decide.
- **About** says what the app actually does, function by function, and links to the source, the release notes, the licence and where to report a bug. The settings rows are laid out on a grid instead of being aligned by hand with fixed widths, so a longer label cannot break the column any more.
- **Unknown**, **MS Store** and **Scope** are remembered between launches. They used to reset every time, while the theme did not. Ticking **Unknown** also rescans immediately instead of quietly applying to the next check.
- **Update** turns into **Cancel** while its own queue runs. Cancelling lets the package in flight finish and then stops: nothing is killed halfway through an installer, and the packages that never ran keep their tick and an empty result.
- After an update, an install, an uninstall or an import, **Update** locks until the next **Check**. Pressing it again used to re-run winget on packages that were already current, which exits non-zero and painted a red cross over rows that had in fact succeeded; the counter now says why the button is greyed. Pins do not lock it: a pin blocks upgrades, it does not change installed versions.
- While a queue runs, the ticks and the pin entries are visibly disabled instead of merely refusing to work — and the lists still scroll. They were blocked before, they just did not look it.
- The Settings tab sits flush with the content frame, with no step under it. It used to be 2px short of the frame, and the frame's rounded top-right corner showed through beneath it.

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

