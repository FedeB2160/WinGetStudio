using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Documents;
using System.Windows.Media;
using System.Windows.Navigation;
using WinGetStudio.ViewModels;

namespace WinGetStudio;

// Il dialogo rifa' cio' che la MessageBox dava gratis (ADR 0020): Invio sceglie il predefinito
// (No sulle conferme), Esc e la X l'ultimo pulsante, cioe' No oppure OK; il testo si copia.
public partial class AppDialog : Window
{
    // Glifo e colore della colonna Result per lo stesso significato.
    private static readonly Dictionary<MessageBoxImage, (string Glyph, string Brush)> Icons = new()
    {
        [MessageBoxImage.Error] = ("", "SystemFillColorCriticalBrush"),
        [MessageBoxImage.Warning] = ("", "SystemFillColorCautionBrush"),
        [MessageBoxImage.Question] = ("", "AccentTextFillColorPrimaryBrush"),
        [MessageBoxImage.Information] = ("", "AccentTextFillColorPrimaryBrush"),
    };

    private readonly MessageBoxButton _button;
    private MessageBoxResult? _answer;

    public AppDialog(string text, string title, MessageBoxButton button, MessageBoxImage image, MessageBoxResult defaultResult, object? content, bool links)
    {
        InitializeComponent();
        _button = button;
        Title = title;
        DlgText.Text = text;
        if (links)
        {
            DlgBody.Children.Insert(0, LinkedText(text));
            DlgText.Visibility = Visibility.Collapsed;
        }
        DlgContent.Content = content;

        if (Icons.TryGetValue(image, out var icon))
        {
            DlgIcon.Text = icon.Glyph;
            DlgIcon.SetResourceReference(TextBlock.ForegroundProperty, icon.Brush);
            DlgIcon.Visibility = Visibility.Visible;
        }

        // Il predefinito in colore accento: si vede cosa fa Invio.
        MessageBoxResult[] answers = button == MessageBoxButton.YesNo ? [MessageBoxResult.Yes, MessageBoxResult.No] : [MessageBoxResult.OK];
        var preferred = answers.Length == 1 ? MessageBoxResult.OK : defaultResult == MessageBoxResult.No ? MessageBoxResult.No : MessageBoxResult.Yes;
        foreach (var a in answers)
        {
            var b = new Button { Content = a.ToString(), MinWidth = 96, Margin = new Thickness(8, 0, 0, 0), IsDefault = a == preferred, IsCancel = a == answers[^1] };
            if (b.IsDefault) b.SetResourceReference(StyleProperty, "AccentButtonStyle");
            b.Click += (_, _) => { _answer = a; Close(); };
            DlgButtons.Children.Add(b);
        }
        Loaded += (_, _) => DlgButtons.Children.OfType<Button>().FirstOrDefault(b => b.IsDefault)?.Focus();

        // I link del testo nel browser: WPF non lo apre da solo.
        AddHandler(Hyperlink.RequestNavigateEvent, new RequestNavigateEventHandler((_, e) =>
        {
            try { Process.Start(new ProcessStartInfo(e.Uri.AbsoluteUri) { UseShellExecute = true }); }
            catch (System.ComponentModel.Win32Exception) { }
            e.Handled = true;
        }));
    }

    // Esc o la X: la risposta prudente.
    public MessageBoxResult Answer => _answer ?? (_button == MessageBoxButton.YesNo ? MessageBoxResult.No : MessageBoxResult.OK);

    // Testo coi link cliccabili (ADR 0021), in sola lettura ma selezionabile. Larghezza fissa:
    // in un dialogo che prende la misura del contenuto un RichTextBox non ne ha una sua. E' il
    // testo lungo dei dettagli: piu' largo e piu' piccolo del resto, allineato a sinistra.
    private RichTextBox LinkedText(string text)
    {
        var p = new Paragraph { Margin = new Thickness(0), TextAlignment = TextAlignment.Left };
        var lines = text.Replace("\r\n", "\n").Split('\n');
        for (var i = 0; i < lines.Length; i++)
        {
            foreach (var part in LinkText.Split(lines[i]))
                p.Inlines.Add(part.IsLink ? new Hyperlink(new Run(part.Text)) { NavigateUri = new Uri(part.Text) } : new Run(part.Text));
            if (i < lines.Length - 1) p.Inlines.Add(new LineBreak());
        }
        // Il FlowDocument ha un font serif suo: prende quello della finestra, cioe' dell'app.
        var doc = new FlowDocument(p) { PagePadding = new Thickness(0), FontSize = 12 };
        doc.SetBinding(FlowDocument.FontFamilyProperty, new System.Windows.Data.Binding(nameof(FontFamily)) { Source = this });
        MaxWidth = 760;
        return new RichTextBox(doc)
        {
            IsReadOnly = true,
            IsDocumentEnabled = true,
            BorderThickness = new Thickness(0),
            Background = Brushes.Transparent,
            Width = 680,
            MaxHeight = 520,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
        };
    }
}
