# Contributing to WinGet Studio

Thanks for wanting to help. This page says how to report a problem, how to get the code running, and what a pull request needs before it can be merged. How the code is built and why it is shaped the way it is lives in [DEVELOPMENT.md](DEVELOPMENT.md) and [docs/adr/](docs/adr/): this page links there rather than repeating it.

Issues, pull requests and commit messages are written in **English**.

## Reporting a problem or an idea

Open an issue from the **[New issue](https://github.com/FedeB2160/WinGetStudio/issues/new/choose)** page and pick a form:

- **Bug report**: something does not work as described in the [README](README.md). The form asks for the app version, how you installed it, your Windows and winget versions, and the steps that lead to the problem. Attach the log if you can: right-click it, *Save log...*.
- **Feature request**: something the app does not do and should.

Before opening one:

- Read [Troubleshooting](docs/TROUBLESHOOTING.md). Some things that look like bugs are Windows or winget behaving as designed, and the fix is there.
- Search the [existing issues](https://github.com/FedeB2160/WinGetStudio/issues?q=is%3Aissue), open and closed. If yours is already there, add what is new to it instead of opening another.
- **Security problems are never reported in a public issue.** See [SECURITY.md](SECURITY.md).

New issues get the `needs-triage` label until the maintainer has looked at them.

## Before writing code

For anything bigger than a typo, open an issue first, or comment on an existing one, and say what you plan to do. It saves you writing a pull request for something that will not be merged, or that someone else is already doing.

Read the [ADR](docs/adr/) about the area you are touching before changing it. Most of the odd-looking code in this repository is a bug that was already paid for once, and the ADR says which.

## Getting the code

You need Windows 10 (1809 or later) or 11, winget, and Windows PowerShell 5.1, which comes with Windows. Nothing else: no SDK, no package to restore.

1. Fork the repository on GitHub.
2. Clone your fork and add this repository as `upstream`:

   ```powershell
   git clone https://github.com/<your-account>/WinGetStudio.git
   cd WinGetStudio
   git remote add upstream https://github.com/FedeB2160/WinGetStudio.git
   ```

3. Start every change from an up-to-date `main`, on a branch of its own:

   ```powershell
   git fetch upstream
   git switch -c fix/issue-42-short-description upstream/main
   ```

## Running and testing

Run the app straight from the sources, with no build: [Running from source](DEVELOPMENT.md#running-from-source). Build the exe only when your change touches the build: [Compiling](DEVELOPMENT.md#compiling).

Both test suites must pass before you open a pull request:

```powershell
powershell -NoProfile -STA -ExecutionPolicy Bypass -File .\tests\Test-Ui.ps1
powershell -ExecutionPolicy Bypass -File .\tests\Test-InvokeWinGet.ps1
```

They run offline and change nothing on the machine. If your change touches how winget is called or read, also run `Test-Ui.ps1 -Live` and say so in the pull request: it reads real winget output, so it is not part of CI. What each suite covers: [Tests](DEVELOPMENT.md#tests).

The code targets **Windows PowerShell 5.1**, the version ps2exe compiles for. Syntax that needs PowerShell 6 or later breaks the exe even when it works in `pwsh`.

## Making changes

- **Branch names** start with the kind of change: `feat/`, `fix/`, `perf/`, `docs/` or `chore/`, followed by the issue number when there is one (`fix/issue-42-...`).
- **Commit messages** follow the same prefixes, in lowercase, with the issue in parentheses: `fix: pinned packages no longer listed as updatable (#42)`.
- **Changelog**: add one line under `## Unreleased` in [CHANGELOG.md](CHANGELOG.md), describing what the user sees, not what the code does.
- **Documentation travels with the code**: if your change makes a line of the README or DEVELOPMENT.md wrong, fix it in the same pull request.
- **A decision that shapes the architecture** gets a new ADR, copied from [docs/adr/TEMPLATE.md](docs/adr/TEMPLATE.md) with the next free number.
- **Language**: UI text and documentation in English; comments in the code in Italian, like the rest of it.
- **Dialogs** go through `Show-AppDialog`, never `[System.Windows.MessageBox]::Show`, which ignores the theme.
- **Glyphs** are written `[char]0xE706`, never with the `` `u{...} `` escape, which needs PowerShell 6.
- **New module**: add it to `$moduleNames` in `src\main.ps1`, or it is silently missing from the exe.

## Signing

Your builds come out **unsigned**, and that is expected: `build.ps1` signs only with the maintainer's key, which is not in the repository. Never commit a certificate or a private key (`*.pfx`, `*.p12`, `*.snk`), and never generate a new certificate to make the build "work". Releases are built and signed by the maintainer.

## Pull requests

- Open the pull request against `main` and fill in the template: what changes, why, and how you tested it.
- CI runs both test suites and the build on every pull request. It must be green.
- A pull request is merged **only after a code owner has approved it** (see [CODEOWNERS](.github/CODEOWNERS)). Expect questions and change requests: they are about the code, not about you.
- The maintainer merges and decides when a change goes into a release.

## Licence

WinGet Studio is released under the [MIT licence](LICENSE). By opening a pull request you agree that your contribution is released under the same licence.

## Conduct

Everyone taking part is expected to follow the [Code of Conduct](CODE_OF_CONDUCT.md).
