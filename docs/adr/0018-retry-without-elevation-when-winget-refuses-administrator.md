# ADR 0018 — Retry without elevation when winget refuses administrator

- **Status:** Accepted
- **Date:** 2026-10-12 ([issue #12](https://github.com/FedeB2160/WinGetStudio/issues/12))
- **Depends on:** ADR 0002, ADR 0003, ADR 0004, ADR 0008

## Context

WinGet Studio always runs elevated (ADR 0002). winget refuses to uninstall or repair a package
installed **per user** when it runs elevated: for installer types `exe`, `burn`, `inno`, `nullsoft`
and `portable` (winget's own portables included) it exits with `0x8A15007D` (`-1978335107`,
`APPINSTALLER_CLI_ERROR_ADMIN_CONTEXT_ACTION_PROHIBITED`). The block is deliberate
(`AdminExecutionShouldBlockUserScopePackages` in `UninstallFlow.cpp`) and no option gets round it.
The app offers no repair, so the cost was that every uninstall of such a package failed.

ADR 0002 listed three ways out and recommended the first: repeat the command unelevated through a
scheduled task. It said to run it as the signed-in user, so that it would work even when elevation
used another administrator account. That part was wrong:

- elevated, `winget list` reads the HKCU of the **elevated account**, so the per-user packages in the
  Installed tab belong to that account;
- repeated as the signed-in user, the command would act on another profile. At best winget answers
  "No installed package found"; at worst it removes the signed-in user's own copy of the same
  program.

## Decision

**On `0x8A15007D` the queue repeats the same command as the same account, without elevation.**

- `Start-WinGetQueue` (`App.Jobs.ps1`) checks the exit code of every package. On `-1978335107` it
  logs the retry and calls `Invoke-WinGet ... -Unelevated` with the same argument line. The
  retry's outcome replaces the first.
- `Invoke-WinGet -Unelevated` (`WinGet.Exec.ps1`) keeps everything that makes `Invoke-WinGet` safe
  (ADR 0004): the quote guard, the `wgt_*` output files in `%TEMP%` and the `cmd.exe /d /s /c`
  line. The files and the winget alias belong to the same account, so the filtered token can use
  them. The line is prefixed with `title WinGet Studio &`. Only the start differs: it goes through
  `Invoke-UnelevatedTask` instead of `Process.Start`.
- `Invoke-UnelevatedTask` registers a one-off scheduled task, `WinGetStudio_<guid>`, that runs
  `cmd.exe` with that line:
  - its principal is the current identity, with `-LogonType Interactive` (it runs in the session
    the account already has open) and `-RunLevel Limited` (the filtered, unelevated token);
  - it may start and keep running on battery, with no time limit;
  - the function polls the task every half second and calls the queue's tick every 30 seconds;
  - the exit code comes from `LastTaskResult`, a UInt32 turned back into winget's negative HRESULT;
  - the task is unregistered in a `finally`;
  - if the task has not started after 30 seconds, the function throws: the account has no open
    session.
- **When the elevated account is not the signed-in user** (`Test-ElevatedUserMismatch`), the queue
  does not retry. The package belongs to an account with no session to run in. The log says so and
  tells the user to sign in as that account.

## Consequences

**Positive**
- Per-user `exe`, `burn`, `inno`, `nullsoft` and `portable` packages now uninstall from the app in
  the common case, UAC over the signed-in account. There is still one UAC prompt per session.
- The command always acts on the account whose list the user is looking at.
- The change stays in `WinGet.Exec.ps1` plus one branch in the queue. Every other caller of
  `Invoke-WinGet` is unchanged, and the retry runs after the first winget has exited, so there is
  still only one winget process at a time (ADR 0003).

**To watch**
- **A console window opens while the retry runs.** An interactive task shows its console. With
  Windows Terminal as the default terminal it opens a Terminal window, which can stay open showing
  the exit code if the retry fails. The window is empty, because the output goes to the log.
- **Domain policies** can forbid creating scheduled tasks. The retry then fails, with the error in
  the log.
- **UAC turned off** (`EnableLUA=0`) is not verified. winget may not block at all, since the full
  token is then the default one; if it does, the retry fails too and the log says so.
- A crash during the retry leaves a `WinGetStudio_*` task with no trigger, which never runs again.
  It is not swept at startup, because `Get-ScheduledTask` would slow every start.
- Windows Sandbox is not the place to check this: its account runs with a full token, so the block
  probably does not show there (not verified). The live suite runs `winget --version` through a real
  unelevated task.

## Alternatives considered

1. **Retry as the signed-in user** (ADR 0002's wording) — it acts on another profile when elevation
   used another account (see Context).
2. **Unelevated app, elevation per operation** (ADR 0002, approach 2) — one UAC prompt per
   machine-scope package in a queue, and a large change: startup, the self-update, the winget
   manifest's `ElevationRequirement`.
3. **Unelevated app with an elevated helper per queue** (ADR 0002, approach 3) — one UAC prompt per
   queue, but inter-process communication makes it the most complex of the three.
4. **A hidden window** (`conhost.exe --headless`, `powershell -WindowStyle Hidden`, a `wscript`
   launcher) — `conhost` always returns 0 instead of the command's exit code (checked), and
   hidden-window tricks are what corporate endpoint protection flags. `wscript` also means VBScript,
   which Windows is retiring.
5. **The shell's token** (`CreateProcessWithTokenW` with explorer's token, or `ShellExecute` through
   the desktop's shell view) — no window and a real exit code. The cost is some sixty lines of
   P/Invoke, a dependency on the Secondary Logon service, and token duplication, which endpoint
   protection also watches.
6. **`-LogonType S4U`** (runs whether the account is signed in or not, without a window) — it runs in
   session 0, where an uninstaller that shows a dialog would wait forever unseen, and S4U tasks get
   no network credentials.

## Note 2026-10-14 — repair

Repair ([issue #24](https://github.com/FedeB2160/WinGetStudio/issues/24)) goes through the same queue,
and winget refuses `repair` of a per-user `exe`, `inno`, `nullsoft`, `burn` or `portable` package as
administrator with the same `0x8A15007D` (`ShellExecuteInstallerHandler.cpp`). The retry is
verb-agnostic, so repair gets it with no extra code. The message for a mismatched account now names
the queue's verb instead of always saying "uninstall".
