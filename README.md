# WinGet Studio

A Windows desktop front end for `winget`. Everything happens in one table with checkboxes: **update** what has a newer version, **install** something new by searching as you type, **list and uninstall** what is already there, **pin** what must not be touched, and **export / import** the whole package list to rebuild a machine.

Light and dark theme, no telemetry, no branding, a single `.exe` with nothing to install.

## Requirements

- Windows 10 or 11 with **winget** (the *App Installer* package from the Microsoft Store). Without it the app says so at startup and exits.
- **Administrator rights**: installing and removing software needs them, so the app asks for elevation when it starts.

## Getting it

Download `WinGetStudio.exe` from the [latest release](https://github.com/FedeB2160/WinGetStudio/releases) and run it. There is no installer and nothing is written outside the registry key holding your theme preference.

**Windows will warn about an unknown publisher.** The exe *is* signed, but with a self-signed certificate, and Windows only trusts certificates issued by a recognised authority. You can either accept the warning (*More info* → *Run anyway*), or import `assets/WinGetStudio-codesign.cer` from this repository into *Trusted Root Certification Authorities* to make the signature trusted — see [DEVELOPMENT.md](DEVELOPMENT.md#signing) before doing that, since it affects anything signed with that certificate.

## Using it

The window has three tabs. The **progress bar and the log at the bottom stay visible from every tab**, so you can start a long update, switch tab, and still see how it is going.

### Updates

1. **Check** lists what has a newer version available.
   - **Unknown** (off by default) also lists packages whose installed version winget cannot determine. It applies to the *next* check.
2. Tick what you want, or **Select all**.
3. **Update** upgrades them one at a time. Each row shows its own outcome, and slow installers are never cut off — the log writes a line every 30 seconds so you can see it is still working.

The list stays scrollable while updating, and columns can be resized by dragging their edge in the header.

### Install

Type a name and results appear **as you type** — there is no autocomplete popup, the results list itself is the suggestion, so you see version and ID before choosing.

1. Type **at least 3 characters**. The search runs against the local winget catalogue, which is fast.
2. **MS Store** also searches the Microsoft Store. Since that goes online and is much slower, it only applies when you press **Enter** or **Search**, never while typing.
3. **Scope** chooses who the package is installed for: `Auto` lets winget decide, `Machine` installs for all users, `User` only for you.
   - The app runs elevated. If you elevated with a *different* account than the one you are signed in with, a per-user package would end up in that other profile — the log warns you once when that can happen.
4. Tick rows and press **Install**, or **double click a row** to install just that one.

### Installed

The inventory of what is on the machine, loaded the first time you open the tab.

1. The **filter box** narrows the list by name or ID as you type.
2. Tick rows and press **Uninstall**. A confirmation lists exactly what will be removed, and defaults to *No* — a stray Enter cannot delete anything.
   - If the filter is hiding a package you had ticked, both the counter and the confirmation say so, so nothing is removed off screen.
3. **Export...** saves the list of installed packages to a `.json` file. **Import...** installs the packages a file describes — the quick way to set up a new machine.

Packages you installed without winget appear here too, with IDs like `ARP\Machine\X64\Android Studio`, and can be uninstalled like any other.

After an uninstall the list is not rebuilt automatically, so you can read the outcome of each row. Press **Refresh** when you are done.

### Pinning

A pin tells winget to leave a package alone until you remove the pin — for the one that keeps reappearing and that you do not want touched.

**Right click a row** in Updates or Installed → *Pin (block upgrades)* or *Remove pin*. It works on the highlighted rows, not the ticked ones. A pinned package shows a pin icon and is skipped by updates, including *Select all*. It can still be uninstalled: a pin blocks upgrades, not removal.

### Settings

The **gear button** in the top-right corner opens the settings screen; the **X** or **Esc** closes it.

- **Theme** — `Light`, `Dark`, or `Auto` to follow Windows (which it keeps following while the window is open).
- **Installed version** and **Check for updates** — see below.

### What the Result column means

| Icon | Meaning |
|---|---|
| spinner | in progress |
| green circle with a tick | done |
| yellow triangle | done, with a warning — usually "a reboot is needed" or "already installed" |
| red circle with a cross | failed — hover for the code, full detail in the log |

## Automatic updates

At startup the app checks GitHub for a newer release. If there is one, an **Update to vX.Y.Z** button appears in the settings screen, and the log says so. Nothing is downloaded until you ask: the button explains what will be downloaded and from where, the file is verified against the checksum published with the release, and the app then replaces itself and restarts.

If there is no newer release, no network, or you are running from source, the check says nothing at all. You can always ask explicitly with **Check for updates**, which does report the outcome either way.

## Building it, and how it works inside

See **[DEVELOPMENT.md](DEVELOPMENT.md)**: project layout, how the single-file exe is built from the modules, signing, publishing a release, the test suite, and the design decisions worth knowing before changing the code.

Version history is in **[CHANGELOG.md](CHANGELOG.md)**.
