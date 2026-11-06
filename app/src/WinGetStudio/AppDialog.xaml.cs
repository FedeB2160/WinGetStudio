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

    public AppDialog(string text, string title, MessageBoxButton button, MessageBoxImage image, MessageBoxResult defaultResult, object? content, bool links,
        (string Yes, string No)? verbs = null)
    {
        InitializeComponent();
        TitleBar.Follow(this);
        _button = button;
        Title = title;
        DlgText.Text = text;
        // I dettagli di un pacchetto come tabella (ADR 0021); il testo resta per il ripiego.
        if (content is PackageDetails details)
        {
            DlgBody.Children.Insert(0, DetailsTable(details));
            DlgText.Visibility = Visibility.Collapsed;
        }
        else
        {
            if (links)
            {
                DlgBody.Children.Insert(0, LinkedText(text));
                DlgText.Visibility = Visibility.Collapsed;
            }
            DlgContent.Content = content;
        }

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
            // Il verbo dice cosa succede: "Uninstall" / "Cancel" invece di Yes / No.
            var label = verbs is { } v && answers.Length == 2 ? (a == MessageBoxResult.Yes ? v.Yes : v.No) : a.ToString();
            var b = new Button { Content = label, MinWidth = 96, Margin = new Thickness(8, 0, 0, 0), IsDefault = a == preferred, IsCancel = a == answers[^1] };
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

    // Dettagli come tabella (ADR 0021): il nome come titolo, poi per ogni lettura di winget la sua
    // prima riga e le coppie etichetta/valore. Etichette e titoletti in secondario, valori coi link.
    // In un RichTextBox e non in una griglia: il testo resta selezionabile e si copia (ADR 0020).
    private RichTextBox DetailsTable(PackageDetails details)
    {
        Block Text(string value, bool secondary)
        {
            var p = new Paragraph { Margin = new Thickness(0, 0, 0, 4) };
            var lines = value.Split('\n');
            for (var i = 0; i < lines.Length; i++)
            {
                foreach (var part in LinkText.Split(lines[i]))
                    p.Inlines.Add(part.IsLink ? new Hyperlink(new Run(part.Text)) { NavigateUri = new Uri(part.Text) } : new Run(part.Text));
                if (i < lines.Length - 1) p.Inlines.Add(new LineBreak());
            }
            if (secondary) p.SetResourceReference(TextElement.ForegroundProperty, "TextFillColorSecondaryBrush");
            return p;
        }
        TableCell Cell(string value, bool secondary, int span = 1)
        {
            var c = new TableCell(Text(value, secondary)) { ColumnSpan = span, Padding = new Thickness(0, 0, 12, 0) };
            if (secondary) c.SetResourceReference(TextElement.ForegroundProperty, "TextFillColorSecondaryBrush");
            return c;
        }
        var title = new Paragraph(new Run(details.Name)) { FontWeight = FontWeights.SemiBold, Margin = new Thickness(0, 0, 0, 8) };
        title.SetResourceReference(TextElement.FontSizeProperty, "SectionFontSize");
        var table = new Table { CellSpacing = 0, Margin = new Thickness(0) };
        table.Columns.Add(new TableColumn { Width = new GridLength(180) });
        table.Columns.Add(new TableColumn { Width = new GridLength(1, GridUnitType.Star) });
        var group = new TableRowGroup();
        foreach (var part in details.Parts)
        {
            group.Rows.Add(new TableRow { Cells = { Cell(part.Heading, secondary: true, span: 2) } });
            foreach (var row in part.Rows)
                group.Rows.Add(row.Label.Length == 0
                    ? new TableRow { Cells = { Cell(row.Value, secondary: false, span: 2) } }
                    : new TableRow { Cells = { Cell(row.Label, secondary: true), Cell(row.Value, secondary: false) } });
        }
        table.RowGroups.Add(group);
        var doc = new FlowDocument(title) { PagePadding = new Thickness(0), FontSize = 12 };
        doc.Blocks.Add(table);
        doc.SetBinding(FlowDocument.FontFamilyProperty, new System.Windows.Data.Binding(nameof(FontFamily)) { Source = this });
        MaxWidth = 760;
        return new RichTextBox(doc)
        {
            IsReadOnly = true,
            IsDocumentEnabled = true,
            BorderThickness = new Thickness(0),
            Background = Brushes.Transparent,
            Width = 600,
            MaxHeight = 520,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
        };
    }

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
