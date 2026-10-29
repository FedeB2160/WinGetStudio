using System.Media;
using System.Windows;
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
        // Owner solo a finestra visibile: su una finestra mai mostrata WPF lancia un'eccezione.
        var owner = Owner is { IsVisible: true } w ? w : null;
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
        owner?.SetDim(true);
        try { dialog.ShowDialog(); }
        finally { owner?.SetDim(false); }
        return dialog.Answer;
    }

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
