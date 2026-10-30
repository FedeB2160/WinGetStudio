using System.Text.RegularExpressions;
using System.Windows;

namespace WinGetStudio.ViewModels;

// Dialoghi visti dai ViewModel (ADR 0020): stessi enum della MessageBox, quindi le chiamate si
// leggono come prima e "conferma con No predefinito" resta verificabile. content: un ViewModel
// mostrato sotto il testo (l'anteprima dell'import). links: gli indirizzi web si aprono col clic.
public interface IDialogService
{
    MessageBoxResult Show(string text, string title = "WinGet Studio", MessageBoxButton button = MessageBoxButton.OK,
        MessageBoxImage image = MessageBoxImage.None, MessageBoxResult defaultResult = MessageBoxResult.None,
        object? content = null, bool links = false);

    // Settings e About: finestre modali sopra la principale, col velo (ADR 0028).
    void ShowSettings(SettingsViewModel settings);
    void ShowAbout(string version);

    // null se l'utente annulla.
    string? PickSaveFile(string title, string filter, string fileName);
    string? PickOpenFile(string title, string filter);
}

public readonly record struct LinkPart(string Text, bool IsLink);

// Testo diviso in pezzi e link http(s) (ADR 0021). La punteggiatura che chiude una frase o una
// parentesi non fa parte del link.
public static partial class LinkText
{
    public static IEnumerable<LinkPart> Split(string text)
    {
        var at = 0;
        foreach (Match m in Url().Matches(text))
        {
            if (m.Index > at) yield return new(text[at..m.Index], false);
            yield return new(m.Value, true);
            at = m.Index + m.Length;
        }
        if (at < text.Length) yield return new(text[at..], false);
    }

    [GeneratedRegex(@"https?://[^\s<>""]*[^\s<>"".,;:!?)\]]")]
    private static partial Regex Url();
}
