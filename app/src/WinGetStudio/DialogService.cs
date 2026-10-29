using System.Diagnostics;
using System.Media;
using System.Windows;
using System.Windows.Documents;
using System.Windows.Navigation;
using Microsoft.Win32;
using WinGetStudio.ViewModels;

namespace WinGetStudio;

// I dialoghi veri: AppDialog sopra la finestra, col velo, e i selettori di file di Windows.
public sealed class DialogService : IDialogService
{
    public MainWindow? Owner { get; set; }

    public MessageBoxResult Show(string text, string title = "WinGet Studio", MessageBoxButton button = MessageBoxButton.OK,
        MessageBoxImage image = MessageBoxImage.None, MessageBoxResult defaultResult = MessageBoxResult.None, object? content = null, bool links = false)
    {
        AppDialog dialog;
        try { dialog = new AppDialog(text, title, button, image, defaultResult, content, links); }
        catch (Exception e) when (e is System.Windows.Markup.XamlParseException or InvalidOperationException or ResourceReferenceKeyNotFoundException)
        {
            // Ripiego sulla MessageBox: un messaggio non deve perdersi proprio quando qualcosa
            // e' guasto.
            return Owner is { IsVisible: true } o ? MessageBox.Show(o, text, title, button, image, defaultResult) : MessageBox.Show(text, title, button, image, defaultResult);
        }
        var owner = TopOwner();
        dialog.Owner = owner;
        dialog.WindowStartupLocation = owner is null ? WindowStartupLocation.CenterScreen : WindowStartupLocation.CenterOwner;
        // Il suono che la MessageBox fa per lo stesso tipo di messaggio.
        (image switch
        {
            MessageBoxImage.Error => SystemSounds.Hand,
            MessageBoxImage.Warning => SystemSounds.Exclamation,
            MessageBoxImage.Question => SystemSounds.Question,
            MessageBoxImage.Information => SystemSounds.Asterisk,
            _ => null,
        })?.Play();
        ShowDimmed(dialog);
        return dialog.Answer;
    }

    public void ShowSettings(SettingsViewModel settings) => ShowDimmed(new SettingsWindow { DataContext = settings });

    public void ShowAbout(string version) => ShowDimmed(new AboutWindow(version));

    // Una pagina o un dialogo: sopra la finestra piu' in alto, col velo sulla principale. Il velo
    // c'e' gia' se sopra la principale sta una pagina (un dialogo aperto da Settings).
    private void ShowDimmed(Window window)
    {
        var owner = TopOwner();
        window.Owner ??= owner;
        if (window.Owner is not null) window.WindowStartupLocation = WindowStartupLocation.CenterOwner;
        var dim = window.Owner is MainWindow main ? main : null;
        dim?.SetDim(true);
        try { window.ShowDialog(); }
        finally { dim?.SetDim(false); }
    }

    // Owner solo a finestra visibile: su una finestra mai mostrata WPF lancia un'eccezione. Se una
    // pagina e' aperta, il dialogo e' suo: owner la principale lo metterebbe dietro la pagina.
    private Window? TopOwner() =>
        Owner is not { IsVisible: true } main ? null : main.OwnedWindows.OfType<Window>().LastOrDefault(w => w.IsVisible) ?? main;

    // I link di una pagina nel browser: WPF non lo apre da solo.
    public static void OpenLinks(Window window, Action<string>? log = null) =>
        window.AddHandler(Hyperlink.RequestNavigateEvent, new RequestNavigateEventHandler((_, e) =>
        {
            try { Process.Start(new ProcessStartInfo(e.Uri.AbsoluteUri) { UseShellExecute = true })?.Dispose(); }
            catch (System.ComponentModel.Win32Exception ex) { log?.Invoke($"Could not open {e.Uri}: {ex.Message}"); }
            e.Handled = true;
        }));

    public string? PickSaveFile(string title, string filter, string fileName)
    {
        var d = new SaveFileDialog { Title = title, Filter = filter, FileName = fileName, InitialDirectory = Desktop };
        return d.ShowDialog(Owner) == true ? d.FileName : null;
    }

    public string? PickOpenFile(string title, string filter)
    {
        var d = new OpenFileDialog { Title = title, Filter = filter, InitialDirectory = Desktop };
        return d.ShowDialog(Owner) == true ? d.FileName : null;
    }

    private static string Desktop => Environment.GetFolderPath(Environment.SpecialFolder.Desktop);
}
