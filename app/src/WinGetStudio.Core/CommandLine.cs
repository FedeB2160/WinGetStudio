using System.Text.RegularExpressions;

namespace WinGetStudio.Core;

// Riga di comando per CreateProcess da una lista di argomenti: nessuna shell la interpreta
// (ADR 0025), quindi basta la quotatura di CommandLineToArgvW. Un token semplice resta nudo.
public static partial class CommandLine
{
    public static string Join(IEnumerable<string> arguments) => string.Join(' ', arguments.Select(Quote));

    public static string Quote(string arg) =>
        Plain().IsMatch(arg) ? arg
        // Backslash raddoppiati prima di un apice (e prima di quello di chiusura), apice escapato.
        : "\"" + TrailingBackslashes().Replace(BackslashesBeforeQuote().Replace(arg, "$1$1\\\""), "$1$1") + "\"";

    [GeneratedRegex(@"^[\w.\-:/\\=]+$")]
    private static partial Regex Plain();

    [GeneratedRegex(@"(\\*)""")]
    private static partial Regex BackslashesBeforeQuote();

    [GeneratedRegex(@"(\\+)$")]
    private static partial Regex TrailingBackslashes();
}
