# Security policy

WinGet Studio runs as administrator, installs and removes software, and updates itself from GitHub. A flaw in it can hand someone else those same rights, so security problems are handled privately until a fix is released.

## Supported versions

Only the [latest release](https://github.com/FedeB2160/WinGetStudio/releases/latest) receives fixes. If you are on an older version, update first and check that the problem is still there.

## Reporting a vulnerability

**Do not open a public issue.** Report it privately instead:

1. Go to the **[Security](https://github.com/FedeB2160/WinGetStudio/security)** tab of the repository.
2. Choose **Report a vulnerability** and fill in the form.

Only the maintainer can read the report. Please include:

- the WinGet Studio version and how it was installed (installer, portable exe, winget, or from source);
- what an attacker can do, and what they need first (a local account, a file on disk, a network position);
- the steps to reproduce it, or a proof of concept.

Examples of what belongs here: a way to run code with the app's administrator rights, to make the self-update install something that is not an official release, or to get a command of your choice passed to winget.

## What happens next

This is a project maintained in spare time, so response times are best effort. You will get an answer to the report, a fix in a new release when the problem is confirmed, and credit in the advisory if you want it.
