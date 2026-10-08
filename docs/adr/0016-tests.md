# ADR 0016 — Tests

- **Status:** Accepted
- **Date:** 2026-08-04 (v1.9.0; offline by default with `-Live` opt-in, and the Windows CI, since v1.10.2)
- **Depends on:** ADR 0001, ADR 0003, ADR 0010, ADR 0012, ADR 0014

## Context

Most of what has broken in this app passed every static check: scope and closure bugs in runspaces
(ADR 0008), a module present on disk but absent from the exe (ADR 0001), a tooltip resolved along the
logical tree (ADR 0011), contrast that read fine in one theme only (ADR 0010), two winget processes at
once (ADR 0003). The exe also loads its code differently from the `.ps1`, so a failure in the
concatenated form would otherwise only show up on a double click.

Up to v1.10.1 the UI suite always reached the real winget — a real search, a real package list, the
full pin cycle, a real export. v1.10.2 added a Windows CI and made that suite offline by default.

## Decision

**Two standalone scripts, no framework, no runner.** Each is one file of sequential assertions; there
is no single-test selector.

- **`tests\Test-InvokeWinGet.ps1`** — winget execution and table parsing. It extracts the functions from
  the real modules through the AST, so it tests production code rather than a copy. It checks that the
  wait is bound to the process (a detached child holding stdout must not hang it), that the exit code is
  available, that output is read back as UTF-8, that leftover temp files are swept, and it parses four
  fixtures (ADR 0006). It needs no admin rights, installs nothing, and calls `winget --version` only when
  winget exists.
- **`tests\Test-Ui.ps1`** — runs with `-STA` and **mounts the real app in a hidden window**: `Start-App
  -NoShow` builds the window without displaying it.

**Offline by default; `-Live` is opt-in.** Without `-Live`, `Test-Ui.ps1` touches neither winget nor
the network; that is what CI runs. `-Live` adds real search, list and export — including the real
search-as-you-type, where a slower earlier query returns after a newer one — the GitHub release check,
and one pin cycle on `7zip.7zip` — only when it is installed and not already pinned, and the pin it
creates is removed in a `finally` that first waits for the queue's winget to exit. The live run stays a
manual gate before a release.

**What `Test-Ui.ps1` checks**, beyond parsing every file:

- **Static checks on the concatenated source.** It re-does the module and XAML injection the way
  `build.ps1` does, reading `$moduleNames` with the same regex, and verifies the result parses and keeps
  every function; a module missing from or orphaned by `$moduleNames` fails; no PowerShell 6+ syntax
  such as `` "`u{...}" `` anywhere.
- **The mounted app.** The modules actually see the controls; `Start-BackgroundJob` completes, returns
  its result and unhooks itself; every control the code asks for exists in `UI.xaml`.
- **Themes and layout.** Same keys in both themes, every `DynamicResource` resolves, contrast pairs,
  surface step and borders measured (ADR 0010), header grippers present, column headers non-empty,
  uppercase and centred, every glyph present in both system icon fonts, no tooltip resolving to a
  `TabItem` (ADR 0011), the About table alignments, no em dash in UI text.
- **Behaviour that must not regress.** Confirmations for uninstall and self-update come *before*
  anything is queued or downloaded, are Yes/No and default to No; reads use `$wingetPath` and every job
  passes it; the two grid-freeze regressions; `$AppVersion` is found, is `x.y.z`, reaches the settings
  screen and is forwarded by `build.ps1`.
- **Installer and self-update** (ADR 0013, ADR 0014): `Get-InstallChannel` on its four channels from fake
  paths; `Get-LatestRelease` choosing by name from an asset list where the setup sorts first; the
  `installed` channel refusing an asset with no digest; the setup name consistent and sorting after
  `WinGetStudio.exe`; the `.iss` `AppId` being a GUID.

**Windows CI** (`.github\workflows\ci.yml`, GitHub-hosted `windows-2022`) on every pull request and push
to `main`: both suites offline, then installs Inno Setup 6.7.1, builds the exe and the setup, fails if
either is missing, and uploads both as **unsigned** test artifacts kept seven days. Actions are pinned to
commit SHAs, the token is read-only (`contents: read`, `persist-credentials: false`), and **no signing
key ever reaches CI** (ADR 0012).

## Consequences

**Positive**
- Scope, closure and injection bugs are caught where static analysis cannot see them.
- CI is deterministic: it does not depend on winget, the network or a signing key.
- Both suites are green before every commit, and CI repeats them on every pull request.

**To watch**
- No selector: to run part of a suite, comment out or run the file.
- Offline CI cannot see a change in winget's output; the `-Live` run before a release is what does.
- The full update path of the `installed` channel cannot be tested until a newer release exists
  (ADR 0013); the installer's interactive behaviour is tested by hand in Sandbox or a VM (ADR 0014).

## Alternatives considered

The sources record no test framework that was considered and rejected. The only recorded change of
approach is the move from a UI suite that always reached the real winget to offline-by-default with
`-Live` (v1.10.2).
