# ADR 0021 — Package details as winget's own text

- **Status:** Accepted
- **Date:** 2026-10-14
- **Depends on:** ADR 0003, ADR 0004, ADR 0005, ADR 0020

## Context

[Issue #24](https://github.com/FedeB2160/WinGetStudio/issues/24) asked for a Details action, showing
a package's description, publisher, website, licence and versions, plus installed scope, installer
type and location. winget has two commands for this:
- `show` gives the catalogue manifest;
- `list --details`, stable since winget 1.29, gives what is installed.

Both print a list of `label: value` lines, and **the labels are translated**. On an Italian Windows,
`winget show 7zip.7zip` prints `Editore:`, `Licenza:` and `Note sulla versione:`, and
`list --details` prints `Ambito installazione:` and `Posizione installata:`. Groups such as the
installer, the tags and the documentation links are nested by indentation.

The table readers do not have this problem: they parse by column position, never by header text
(ADR 0006).

Two more facts shaped the decision:
- **Which catalogue answers depends on the row.** A search with **MS Store** ticked mixes two
  sources, and `install --id X -e` without `--source` looks the Id up in every source, including the
  Store, which goes over the network.
- **Details are a winget process like any other.** Two at once make one of them fail (ADR 0003).

## Decision

**The app shows winget's text verbatim, and parses none of it.**

- `Get-WinGetDetails` (`WinGet.Parse.ps1`) runs one or two reads in sequence, through
  `Invoke-WinGetRead` (UTF-8, no shell, ADR 0004):
  - `list --id X -e --details`, for an installed package (Installed and Updates tabs);
  - `show --id X -e --source S`, when the row has a source. An ARP-only program has none, and no
    catalogue knows it.
- Of each line it keeps the last `\r` segment, drops lines that are only a spinner frame, and keeps
  the indentation `show` uses for groups.
- `Show-PackageDetails` (`App.Ui.ps1`) runs it in a background job, behind `Test-WinGetBusy` and the
  busy state, like an export. The text then appears in a `Show-AppDialog` popup. The popup's text box
  now has `MaxHeight="480"` and scrolls, so a long manifest does not grow the window off the screen.
- **Web addresses in the text can be clicked.** With `-Links`, `Show-AppDialog` shows the text in a
  read-only `RichTextBox`, still selectable and copyable, in which every `http(s)://` becomes a
  `Hyperlink`. Punctuation that closes a sentence or a bracket is not part of the link. The popup is a
  window of its own, so it gets the same `RequestNavigate` handler as the main window
  (`Add-LinkHandler`). Like the About links, the browser opens elevated, because the app is.
- The entry point is **Details of highlighted package** in the context menu of all three grids. The
  Install grid had no context menu until now. The item is disabled while busy, like the pin items.
- **Every row carries its `Source`.**
  - A search queries **one source at a time**, so a result's source is the source that was queried.
    No column is read for it.
    - Without the Store, the search is `--source winget --count 25`.
    - With **MS Store** ticked it is two searches in the same job:
      1. winget, `--count 25`;
      2. `--source msstore --count 10`, with its results appended after the winget ones.
  - Two searches, not one across all sources, for two reasons:
    - Since winget 1.29, REST sources are no longer sorted to the top. With one `--count` over all
      sources, a common word fills the list with winget packages. Measured: "spotify" gives 33 winget
      results with the Store one 34th, so the Store result never appeared.
    - A Store that does not answer no longer fails the search. The winget results stay, and the reason
      goes to the log.
  - In `list` it is the last column: `Disponibile` appears only when something has an update, so the
    fourth column is not always the source.
  - In `upgrade` it is the fifth column.
- **Install passes the row's source** (`--source "<Source>"`) when the row has one. Updates and
  Installed do not: winget already correlates the installed package.

## Consequences

**Positive**
- Works in every Windows language, and keeps working when winget adds or renames a field.
- Nothing to keep in step with winget's manifest schema.
- Older winget versions without `list --details` show their own error text, unedited, instead of an
  empty or half-parsed panel.
- An install no longer asks the Store about a package that came from the winget source.

**To watch**
- The text is in the system language and in winget's layout. It is not a formatted card.
- `show` prints the manifest of the **latest** version. For an installed package that is out of date,
  the catalogue part can describe a newer version than the one installed. The installed part comes
  first for that reason.
- A search with the Store is two winget processes in a row, never at the same time (ADR 0003). The
  Store part goes over the network and takes about 5 s, which is why it still runs only on Enter or
  **Search**, never while typing.
- Other configured sources (a company REST source, for instance) are not searched. Before this change
  they were included when **MS Store** was ticked, because that search covered every source.
- Available versions (`show --versions`) are not shown: the app has no way to install a specific
  version, so the list would not lead anywhere.

## Alternatives considered

1. **Parse `label: value` into named fields**, as the issue proposed. This was rejected: it needs one
   table of labels per language winget is translated into, and it breaks silently when a translation
   changes.
2. **Force English output.** winget has no switch for its output language. Changing the process
   locale would also change the language of the installers it launches.
3. **Read the manifests from the winget source index.** The local index format is internal to winget,
   and it does not cover the Store or ARP programs.
