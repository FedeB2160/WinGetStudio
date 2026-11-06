using System.Diagnostics;
using System.Globalization;
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
            DlgBody.Children.Insert(0, DetailsView(details));
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
            // Un pulsante solo sotto i dettagli: Close, come accanto a Install.
            var label = verbs is { } v && answers.Length == 2 ? (a == MessageBoxResult.Yes ? v.Yes : v.No)
                : content is PackageDetails ? "Close" : a.ToString();
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

    // Dettagli come tabella (ADR 0021): il nome come titolo e l'Id sotto, poi una sezione per
    // lettura col nome che le da' l'app, e le coppie etichetta/valore. Etichette in secondario,
    // valori coi link, gruppi rientrati. In un FlowDocumentScrollViewer: il testo resta selezionabile
    // e si copia (ADR 0020), senza l'aspetto di un campo di testo.
    private const double DetailsWidth = 620, NestedIndent = 12;

    private FlowDocumentScrollViewer DetailsView(PackageDetails details)
    {
        // La colonna delle etichette larga quanto la piu' lunga (fra 100 e 220 px): nelle lingue con
        // etichette lunghe vanno a capo, nelle altre il valore non resta lontano.
        var typeface = new Typeface(FontFamily, FontStyles.Normal, FontWeights.Normal, FontStretches.Normal);
        double Measure(string s) => new FormattedText(s, CultureInfo.CurrentCulture, FlowDirection.LeftToRight, typeface, 12, Brushes.Black,
            VisualTreeHelper.GetDpi(this).PixelsPerDip).WidthIncludingTrailingWhitespace;
        var labelWidth = Math.Clamp(details.Parts.SelectMany(p => p.Rows).Where(r => r.Label.Length > 0)
            .Select(r => Measure(r.Label) + (r.Nested ? NestedIndent : 0)).DefaultIfEmpty(0).Max() + 16, 100, 220);

        Paragraph Text(string value, double indent = 0)
        {
            var p = new Paragraph { Margin = new Thickness(indent, 0, 0, 0) };
            var lines = value.Split('\n');
            for (var i = 0; i < lines.Length; i++)
            {
                foreach (var part in LinkText.Split(lines[i]))
                    p.Inlines.Add(part.IsLink ? new Hyperlink(new Run(part.Text)) { NavigateUri = new Uri(part.Text) } : new Run(part.Text));
                if (i < lines.Length - 1) p.Inlines.Add(new LineBreak());
            }
            return p;
        }
        T Secondary<T>(T e) where T : TextElement
        {
            e.SetResourceReference(TextElement.ForegroundProperty, "TextFillColorSecondaryBrush");
            return e;
        }

        var doc = new FlowDocument { PagePadding = new Thickness(0, 0, 16, 0), FontSize = 12, TextAlignment = TextAlignment.Left };
        doc.SetBinding(FlowDocument.FontFamilyProperty, new System.Windows.Data.Binding(nameof(FontFamily)) { Source = this });
        doc.SetResourceReference(FlowDocument.ForegroundProperty, "TextFillColorPrimaryBrush");
        var title = new Paragraph(new Run(details.Name)) { FontWeight = FontWeights.SemiBold, Margin = new Thickness(0) };
        title.SetResourceReference(TextElement.FontSizeProperty, "SectionFontSize");
        doc.Blocks.Add(title);
        doc.Blocks.Add(Secondary(new Paragraph(new Run(details.Id)) { Margin = new Thickness(0, 2, 0, 0) }));
        foreach (var part in details.Parts)
        {
            // Il nome della sezione con una riga sotto: catalogo e installato non si confondono.
            var header = new Paragraph(new Run(part.Title))
            {
                FontWeight = FontWeights.SemiBold, Margin = new Thickness(0, 16, 0, 6), Padding = new Thickness(0, 0, 0, 4),
                BorderThickness = new Thickness(0, 0, 0, 1),
            };
            header.SetResourceReference(Block.BorderBrushProperty, "AreaStrokeBrush");
            doc.Blocks.Add(header);
            var table = new Table { CellSpacing = 0, Margin = new Thickness(0) };
            // Larghezze assolute: in un documento una colonna '*' non prende lo spazio rimasto.
            table.Columns.Add(new TableColumn { Width = new GridLength(labelWidth) });
            table.Columns.Add(new TableColumn { Width = new GridLength(DetailsWidth - labelWidth - 40) });
            var group = new TableRowGroup();
            foreach (var row in part.Rows)
            {
                var r = new TableRow();
                if (row.Label.Length == 0) r.Cells.Add(new TableCell(Text(row.Value)) { ColumnSpan = 2, Padding = new Thickness(0, 3, 0, 3) });
                else
                {
                    r.Cells.Add(Secondary(new TableCell(Text(row.Label, row.Nested ? NestedIndent : 0)) { Padding = new Thickness(0, 3, 12, 3) }));
                    r.Cells.Add(new TableCell(Text(row.Value)) { Padding = new Thickness(0, 3, 0, 3) });
                }
                group.Rows.Add(r);
            }
            table.RowGroups.Add(group);
            doc.Blocks.Add(table);
        }
        MaxWidth = 760;
        return new FlowDocumentScrollViewer
        {
            Document = doc,
            IsToolBarVisible = false,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto,
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
            Width = DetailsWidth,
            MaxHeight = 520,
            Background = Brushes.Transparent,
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
