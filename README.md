# WinGet Studio

A Windows desktop front end for `winget`. Everything happens in one table with checkboxes: **update** what has a newer version, **install** something new by searching as you type, **list and uninstall** what is already there, **pin** what must not be touched, and **export / import** the whole package list to rebuild a machine.

Light and dark theme, no telemetry, no branding, a single `.exe` with nothing to install.

## Requirements

- Windows 10 or 11 with **winget** (the *App Installer* package from the Microsoft Store). Without it the app says so at startup and exits.
- **Administrator rights**: installing and removing software needs them, so the app asks for elevation when it starts.

## Getting it

Download `WinGetStudio.exe` from the [latest release](https://github.com/FedeB2160/WinGetStudio/releases) and run it. There is no installer and nothing is written outside the registry key holding your preferences.

It is also in the winget catalogue:

```powershell
winget install FedeB2160.WinGetStudio
```

That copies the executable and puts an alias on the PATH, so `WinGetStudio` starts it from any terminal. It creates **no desktop or Start menu shortcut**: a portable package cannot, and the request to allow it is still open upstream as [winget-cli#2299](https://github.com/microsoft/winget-cli/issues/2299).

**Windows will warn about an unknown publisher.** The exe *is* signed, but with a self-signed certificate, and Windows only trusts certificates issued by a recognised authority. You can either accept the warning (*More info* → *Run anyway*), or import `assets/WinGetStudio-codesign.cer` from this repository into *Trusted Root Certification Authorities* to make the signature trusted — see [DEVELOPMENT.md](DEVELOPMENT.md#signing) before doing that, since it affects anything signed with that certificate.

### If an antivirus quarantines the executable

`WinGetStudio.exe` is a PowerShell script compiled by ps2exe and signed with a self-signed certificate, so it carries no reputation with any antivirus engine. Microsoft Defender's machine-learning heuristic sometimes decides that combination is malware and reports it as `Trojan:Win32/Wacatac` or `Trojan:Script/Wacatac` — `.C!ml`, `.F!ml` and `.H!ml` have all been seen on the same build. The `!ml` suffix marks a verdict reached by the model rather than by a signature — a false positive, and not a sign that one release differs from the ones before it.

It surfaces in three ways, none of which names the antivirus:

- Installing from winget stops with `0x8a150040 : Error reading stream`. The hash check *passes* first: the file is taken away between verification and the copy.
- The app vanishes while running, or will not start, and `%LOCALAPPDATA%\Microsoft\WinGet\Packages\FedeB2160.WinGetStudio*` is empty even though `winget list` still reports the package as installed.
- The automatic update reports a failed download from a release other machines download without trouble.

Confirm it before changing anything, from an elevated PowerShell:

```powershell
Get-MpThreatDetection | Sort-Object InitialDetectionTime -Descending |
    Select-Object -First 5 InitialDetectionTime, Resources | Format-List
```

If the paths listed are the ones above, the file was quarantined.

#### Getting it back

The fix that asks nothing of anyone installing the app is to report the file to Microsoft as a false positive, at [the Windows Defender file submission page](https://www.microsoft.com/en-us/wdsi/filesubmission), submitting as a software developer. It costs nothing, usually gets an answer within a day or two, and once accepted the detection is dropped for every Defender installation.

On a machine managed by a company, expect the exclusion not to hold. Where Microsoft Defender for Endpoint is onboarded (`OnboardingState` is `1` under `HKLM:\SOFTWARE\Microsoft\Windows Advanced Threat Protection\Status`) or Defender is driven by Intune or group policy, cloud-delivered blocking overrides anything added locally, and the file is removed again within a minute of being written — including while the app is running, which reads as the window simply disappearing. There the only routes are the Microsoft submission above or an allow-list entry made by whoever administers the tenant.

To use the app before that, exclude it from scanning. **An exclusion stops the antivirus from scanning that path for every file it contains, not only this one** — worth doing for a program you compiled yourself, worth thinking about otherwise. Run it from an elevated PowerShell, and first check that `$env:LOCALAPPDATA` and `$env:TEMP` are the profile you are signed in with, not the profile of the account you elevated with:

```powershell
Add-MpPreference -ExclusionPath "$env:LOCALAPPDATA\Microsoft\WinGet\Packages"
Add-MpPreference -ExclusionPath "$env:TEMP\WinGet"
```

Both paths are needed: the first is where winget keeps the installed executable, the second is where it downloads it. Print the two variables before trusting them: on a profile whose name contains a dot, `%TEMP%` expands to an 8.3 short path such as `C:\Users\FB5FE~1.BOR\AppData\Local\Temp`, which is the form winget writes to and therefore the form the exclusion has to match. If instead you run the exe from a folder of your own, exclude that one file with `-ExclusionPath` pointing at it. `Remove-MpPreference -ExclusionPath` undoes any of this.

Then reinstall, from a prompt that is **not** elevated:

```powershell
winget install FedeB2160.WinGetStudio
```

The log will say `Failed to create symlink at ...\WinGet\Links\WinGetStudio.exe`. That is expected without elevation and is not the failure: winget falls back to appending the package directory to the user PATH, so `WinGetStudio` works from any terminal opened afterwards.

Elevation matters here. winget will not uninstall or replace a user-scope package from an elevated prompt — it answers *"The package installed for user scope cannot be uninstalled when running with administrator privileges"* — so the winget half of the recovery has to run unelevated, even though creating the PATH alias would need elevation (see the manifest notes in [DEVELOPMENT.md](DEVELOPMENT.md)). Reinstalling is simpler than restoring the quarantined copy with `MpCmdRun.exe -Restore`, and it gets the current version.

If winget insists the package is already installed while there is nothing left to run, the uninstall entry outlived its files. Remove it, unelevated, and install again:

```powershell
Remove-Item "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\FedeB2160.WinGetStudio*" -Recurse -Force
Remove-Item "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\FedeB2160.WinGetStudio*" -Recurse -Force
```

## Using it

The window has three tabs, plus **Settings** and **About** pinned to the right of the strip. **Unknown**, **MS Store** and **Scope** are remembered between launches, next to the theme. The **progress bar and the log at the bottom stay visible from every tab**, so you can start a long update, switch tab, and still see how it is going.

### Updates

1. **Check** lists what has a newer version available.
   - **Unknown** (off by default) also lists packages whose installed version winget cannot determine. It applies to the *next* check.
2. Tick what you want, or **Select all**.
3. **Update** upgrades them one at a time. Each row shows its own outcome, and slow installers are never cut off — the log writes a line every 30 seconds so you can see it is still working.
   - While the queue runs, **Update** reads **Cancel**. Pressing it lets the package in progress finish and then stops, so nothing is interrupted halfway through an installer; the packages that never ran keep their tick and an empty result.
4. When the queue ends, **Update** is greyed until you press **Check** again. The versions on screen describe the machine as it was before, so running the queue on them would report failures for packages that had in fact succeeded. The list is not rebuilt automatically on purpose: that would wipe the outcome of each row, which is the point of the Result column.

The list stays scrollable while updating — the ticks and the pin entries are greyed, not the list — and columns can be resized by dragging their edge in the header.

While a scan is running the progress bar is **indeterminate**: a scan has no progress to report, and a bar sitting at zero looks like something stuck. It shows real progress only for a queue, which knows how many packages it has.

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

**Right click a row** in Updates or Installed → *Pin highlighted* or *Remove pin from highlighted*. It works on the highlighted rows, not the ticked ones, and the entries say so. A pinned package shows a pin icon and is skipped by updates, including *Select all*. It can still be uninstalled: a pin blocks upgrades, not removal.

### Settings

The **Settings** tab, on the right of the strip next to About, is a tab like the others — so the progress bar and the log stay visible while you are in it.

- **Theme** — `Light`, `Dark`, or `System` to follow Windows (which it keeps following while the window is open).
- **Installed version** and **Check for updates** — see below.
- **Tab strip** — whether the tabs show their icon, their name, or both. Every tab also has a tooltip saying what it is for.
- **Check for updates at startup** — on by default, and it can be turned off: it is one anonymous call to the GitHub API every time the app starts. The **Check for updates** button always works regardless.

### About

Its own tab, at the very right end of the strip: what the app does function by function, and links to the source, the release notes, the licence and where to report a bug.

### Keyboard

**F5** rescans the active tab — Updates or Installed; it does nothing on the others. **Ctrl+F** jumps to the Install tab with the cursor in the search box.

### What the Result column means

| Icon | Meaning |
|---|---|
| spinner | in progress |
| green circle with a tick | done |
| yellow triangle | done, with a warning — usually "a reboot is needed" or "already installed" |
| red circle with a cross | failed — hover for the code, full detail in the log |

## Automatic updates

At startup the app checks GitHub for a newer release. If there is one, an **Update to vX.Y.Z** button appears in the Settings tab, and the log says so. Nothing is downloaded until you ask: the button explains what will be downloaded and from where, the file is verified against the checksum published with the release, and the app then replaces itself and restarts.

If there is no newer release, no network, or you are running from source, the check says nothing at all. You can always ask explicitly with **Check for updates**, which does report the outcome either way.

## Building it, and how it works inside

See **[DEVELOPMENT.md](DEVELOPMENT.md)**: project layout, how the single-file exe is built from the modules, signing, publishing a release, the test suite, and the design decisions worth knowing before changing the code.

Version history is in **[CHANGELOG.md](CHANGELOG.md)**.
