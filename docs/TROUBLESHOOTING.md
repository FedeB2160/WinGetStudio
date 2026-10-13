# Troubleshooting

Problems that are not bugs in WinGet Studio but can stop it from running, and what to do about them. Back to the [README](../README.md).

- [An antivirus quarantines the executable](#an-antivirus-quarantines-the-executable)
- [Windows warns about an unknown publisher](#windows-warns-about-an-unknown-publisher)

## An antivirus quarantines the executable

`WinGetStudio.exe` is a PowerShell script compiled by ps2exe and signed with a self-signed certificate, so it carries no reputation with any antivirus engine. Microsoft Defender's machine-learning heuristic sometimes decides that this combination is malware. It reports it as `Trojan:Win32/Wacatac` or `Trojan:Script/Wacatac`; `.C!ml`, `.F!ml` and `.H!ml` have all been seen on the same build. The `!ml` suffix marks a verdict reached by the model rather than by a signature. It is a false positive, and not a sign that one release differs from the ones before it. It can also come and go: a build that is fine today may be flagged on another machine, or after a model update.

> [!NOTE]
> Since 1.11.0, `winget install FedeB2160.WinGetStudio` runs the installer, which puts the app in `C:\Program Files (x86)\WinGet Studio`. Up to 1.10.3, winget installed a **portable** copy in `%LOCALAPPDATA%\Microsoft\WinGet\Packages`. The symptoms and the recovery below mention both, where they differ.

### How it shows

It surfaces in three ways, none of which names the antivirus:

- Installing from winget stops with `0x8a150040 : Error reading stream`. The hash check *passes* first: the file is taken away between verification and the copy.
- The app vanishes while running, or will not start. With the portable copy, `%LOCALAPPDATA%\Microsoft\WinGet\Packages\FedeB2160.WinGetStudio*` is empty even though `winget list` still reports the package as installed.
- The automatic update reports a failed download from a release that other machines download without trouble.

Confirm it before changing anything, from an elevated PowerShell:

```powershell
Get-MpThreatDetection | Sort-Object InitialDetectionTime -Descending |
    Select-Object -First 5 InitialDetectionTime, Resources | Format-List
```

If the paths listed are WinGet Studio's, the file was quarantined.

### Getting it back

The fix that asks nothing of anyone installing the app is to report the file to Microsoft as a false positive, at [the Windows Defender file submission page](https://www.microsoft.com/en-us/wdsi/filesubmission), submitting as a software developer. It costs nothing, usually gets an answer within a day or two, and once it is accepted the detection is dropped for every Defender installation.

> [!IMPORTANT]
> **On a machine managed by a company, expect a local exclusion not to hold.** Where Microsoft Defender for Endpoint is onboarded (`OnboardingState` is `1` under `HKLM:\SOFTWARE\Microsoft\Windows Advanced Threat Protection\Status`), or Defender is driven by Intune or group policy, cloud-delivered blocking overrides anything added locally. The file is removed again within a minute of being written, including while the app is running, which reads as the window simply disappearing. There the only routes are the Microsoft submission above, or an allow-list entry made by whoever administers the tenant.

To use the app before that, exclude it from scanning.

> [!WARNING]
> **An exclusion stops the antivirus from scanning that path for every file it contains, not only this one.** It is worth doing for a program you compiled yourself, and worth thinking about otherwise.

Run the exclusion from an elevated PowerShell, for the folder the app runs from:

```powershell
# Installed with the setup, or with winget from 1.11.0 on
Add-MpPreference -ExclusionPath "${env:ProgramFiles(x86)}\WinGet Studio"
```

With the portable package from winget (up to 1.10.3), two paths are needed: the first is where winget keeps the executable, the second is where it downloads it. First check that `$env:LOCALAPPDATA` and `$env:TEMP` are the profile you are signed in with, not the profile of the account you elevated with:

```powershell
Add-MpPreference -ExclusionPath "$env:LOCALAPPDATA\Microsoft\WinGet\Packages"
Add-MpPreference -ExclusionPath "$env:TEMP\WinGet"
```

Print the two variables before trusting them. On a profile whose name contains a dot, `%TEMP%` expands to an 8.3 short path such as `C:\Users\FB5FE~1.BOR\AppData\Local\Temp`, which is the form winget writes to and therefore the form the exclusion has to match.

If you run the portable exe from a folder of your own, exclude that one file with `-ExclusionPath` pointing at it. `Remove-MpPreference -ExclusionPath` undoes any of this.

Then reinstall:

```powershell
winget install FedeB2160.WinGetStudio
```

Reinstalling is simpler than restoring the quarantined copy with `MpCmdRun.exe -Restore`, and it gets the current version.

### With the portable package (up to 1.10.3)

Reinstall from a prompt that is **not** elevated. winget will not uninstall or replace a user-scope package from an elevated prompt: it answers *"The package installed for user scope cannot be uninstalled when running with administrator privileges"*. The log will also say `Failed to create symlink at ...\WinGet\Links\WinGetStudio.exe`. That is expected without elevation and is not the failure: winget falls back to appending the package directory to the user PATH, so `WinGetStudio` works from any terminal opened afterwards.

If winget insists the package is already installed while there is nothing left to run, the uninstall entry outlived its files. Remove it, unelevated, and install again:

```powershell
Remove-Item "$env:LOCALAPPDATA\Microsoft\WinGet\Packages\FedeB2160.WinGetStudio*" -Recurse -Force
Remove-Item "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\FedeB2160.WinGetStudio*" -Recurse -Force
```

## Windows warns about an unknown publisher

The exe *is* signed, but with a self-signed certificate, and Windows only trusts certificates issued by a recognised authority. Either accept the warning (*More info* → *Run anyway*), or import `assets/WinGetStudio-codesign.cer` from this repository into *Trusted Root Certification Authorities* to make the signature trusted.

> [!CAUTION]
> A trusted root vouches for **anything** signed with that certificate, not only WinGet Studio. Read [Signing in DEVELOPMENT.md](../DEVELOPMENT.md#signing) before importing it.
