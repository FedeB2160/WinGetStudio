# ADR 0030 — Version 2 keeps an icon in the notification area

- **Status:** Accepted (for 2.0)
- **Date:** 2026-11-02
- **Depends on:** ADR 0003, ADR 0024, ADR 0027, ADR 0028

## Context

1.x is a window and nothing else: closed, it is gone, and the only way to learn that updates are out
is to open it. 2.0 already starts with Windows (ADR 0028, point 11; the `Run` entry passes
`--startup`, ADR 0024), which opened the whole window at every sign-in. Phase 1 of 2.0 ends with a
presence in the notification area, decided with the user on 2026-10-30.

WPF has no notification-area icon. The choices are the WinForms `NotifyIcon`, which ships with the
Windows desktop runtime the app already uses, a library (H.NotifyIcon, Hardcodet), or
`Shell_NotifyIcon` by hand.

## Decision

1. **The icon is the WinForms `NotifyIcon`**: `UseWindowsForms` alongside WPF, with the
   `System.Windows.Forms` and `System.Drawing` implicit usings removed (their `Application`,
   `MessageBox`, `Color` and others clash with WPF's) and the one file that uses them importing them
   under the aliases `Forms` and `Drawing` (`TrayIcon.cs`). The icon is always there while the app runs.
2. **The colour of the icon's badge says the state**, by priority: yellow, an operation in progress
   (the busy state of ADR 0003, scans included); red, failures in the last queue; green, updates
   available; blue, nothing to report (the icon as it is). The tooltip says the same in words
   ("WinGet Studio - 3 updates available"). The four icons are made once at startup from the frame of
   `assets\icon.ico` (embedded as a resource) at the system small-icon size, 16 px at 100%, with no
   scaling: the frames are drawn on the pixel grid (ADR 0017), and a larger image would be scaled down
   by Windows and blur. Only the badge is recoloured, arrow included: its pixels are the badge blue
   mixed with the white of the arrow, and the mix is kept with the new colours. On yellow the arrow is
   dark, as in Windows' caution signs; elsewhere it stays white. A dot drawn over the icon (the first
   version) covered the badge and blurred at 16 px.
3. **The menu is a WPF `ContextMenu`**, not the WinForms one, so it follows the Fluent theme (ADR 0027)
   like the rest of the app: Install, Installed, Updates (open the window on that tab), Check for
   updates, Settings, About, Exit. A double click opens the window. (The last item was "Close"
   until the UI/UX review of 2026-11-05: with Close to tray the window's X does not close the
   app, so one word had two effects. "Exit", as in the Windows apps that live in the tray.) An invisible window of its own is
   brought to the foreground before the menu opens, or the menu would not close on a click elsewhere;
   the main window would come up over the others and make the app count as active. With Settings or
   a dialog already open, the items bring that to the front instead of opening a second modal page.
4. **A notification (a balloon of the `NotifyIcon`, shown by Windows as a toast) when a scan finds
   updates not announced before and no window of the app is active.** "Not announced" is by Id and
   available version: an hourly check does not repeat the same toast, a new version of a package
   already listed does. Clicking it opens the Updates tab. Check for updates from the menu always
   reports, "No updates available." included, even with the window active: whoever asked is looking
   at the icon. "Active" means a window of the app that is visible and active.
5. **Settings gains a "Notification area" card**, at the top of the right column, above Updates
   (ADR 0028, point 11: settings widen, not lengthen):
   - **Close to tray**, preference `CloseToTray`, off by default: off, the X closes the app as before;
     on, it hides the window. Exit in the menu, an update that restarts the app, the end of the
     Windows session and every other path that closes the app on purpose still close it.
   - **Check for package updates**: Never, Every hour, Every 6 hours, Every 24 hours, preference
     `CheckInterval`, **Never by default**, so winget does not start on its own unless asked. The
     periodic scan never starts over another winget, searches included (ADR 0003): it is then due,
     and starts as soon as the lock is free, instead of skipping a whole interval. It keeps the rows'
     outcomes, so a failed row stays there to retry (ADR 0028, point 11 left the next check to the
     user; this one does not wipe what the user has to see).
6. **Started with Windows (`--startup`), the app opens in the notification area**: no window, but the
   startup scan and the update check run as usual, so the dot and the toast have something to say.
   Without winget it shows the window anyway, since installing winget asks a question (ADR 0019).
   The startup work runs once, whether the window opens at startup or later from the icon.

## Consequences

**Positive**
- The app can stay out of the way and still say when there is something to update.
- No new dependency; the menu looks like the app.

**To watch**
- WinForms is loaded with the app: a few MB of the runtime more in memory, and in the self-contained
  exe (ADR 0026).
- The balloon API is the old one: Windows 10 and 11 show it as a toast, but it carries no actions,
  and Focus assist can hide it. A real toast with buttons needs the Windows App SDK or an AUMID.
- A WPF `ContextMenu` opened from a hidden window relies on `SetForegroundWindow` to close when the
  user clicks elsewhere: to check by hand on each Windows release.
- The tests cover the rules (`TrayViewModelTests`); the shell side (icon, menu on a real right click,
  toast) is checked by hand.
- Red stays until the next queue: a check does not clear the failures of the last queue.

## Alternatives considered

1. **H.NotifyIcon or Hardcodet.NotifyIcon.Wpf** — WPF-native, with a themed menu out of the box, but a
   dependency for what `NotifyIcon` and a `ContextMenu` already do in about 150 lines.
2. **`Shell_NotifyIcon` by hand** — no WinForms, but the message window, the taskbar-restart message
   and the balloon all to write and test.
3. **The WinForms `ContextMenuStrip`** — native to `NotifyIcon`, but drawn light only unless the
   experimental WinForms colour mode is turned on, and it would not match the Fluent window.
4. **Only the badge in the tray**, filling the 16 px, the way Teams and Outlook show the simplest form
   of their logo — reads better at 16 px, but drops the box, which is the app's mark. Turned down by
   the user (2026-11-02); the tray keeps the app icon.
5. **Close to tray on by default** — turned down: the X has always closed the app, and a window that
   disappears without closing surprises who did not ask for it.
