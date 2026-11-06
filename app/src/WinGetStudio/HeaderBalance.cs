using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;

namespace WinGetStudio;

// Titoli di colonna davvero al centro (ADR 0028, punto 18). Il template Fluent dell'intestazione
// tiene a destra lo spazio della freccia di ordinamento anche quando e' nascosta (SortIndicator,
// colonna Auto), e il contenuto centrato finiva a sinistra di quel tanto. Quanto e' largo dipende
// dal font dei glifi (la CI ne ha un altro): si misura e lo si rende come padding a sinistra.
public static class HeaderBalance
{
    public static readonly DependencyProperty BalanceProperty = DependencyProperty.RegisterAttached(
        "Balance", typeof(bool), typeof(HeaderBalance), new PropertyMetadata(false, (d, e) =>
        {
            if (d is not DataGridColumnHeader header || e.NewValue is not true) return;
            header.Loaded += (_, _) => Apply(header);
            header.LayoutUpdated += (_, _) => Apply(header);
        }));

    public static bool GetBalance(DependencyObject d) => (bool)d.GetValue(BalanceProperty);
    public static void SetBalance(DependencyObject d, bool value) => d.SetValue(BalanceProperty, value);

    private static void Apply(DataGridColumnHeader header)
    {
        if (header.Template?.FindName("SortIndicator", header) is not FrameworkElement indicator) return;
        // Colonna che non si ordina (spunta, Pin, Result): la freccia non compare mai, il suo spazio
        // si toglie del tutto, che nelle colonne strette serve al titolo.
        if (!header.CanUserSort)
        {
            indicator.Visibility = Visibility.Collapsed;
            if (header.Padding != default) header.Padding = default;
            return;
        }
        // Visibility Hidden: occupa comunque il suo spazio, margine compreso.
        indicator.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
        // Colonna stretta: non oltre lo spazio che il titolo lascia libero, o il titolo si sposterebbe.
        var content = (indicator.Parent as Panel)?.Children.OfType<ContentPresenter>().FirstOrDefault();
        var room = header.ActualWidth - indicator.DesiredSize.Width - (content?.DesiredSize.Width ?? 0);
        var left = Math.Max(0, Math.Min(indicator.DesiredSize.Width, room));
        if (Math.Abs(header.Padding.Left - left) > 0.01) header.Padding = new Thickness(left, 0, 0, 0);
    }
}
