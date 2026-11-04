using System.Globalization;
using System.Windows;
using System.Windows.Data;
using WinGetStudio.ViewModels;

namespace WinGetStudio;

// Settings come finestra modale (ADR 0028). DataContext: SettingsViewModel.
public partial class SettingsWindow : Window
{
    public SettingsWindow()
    {
        InitializeComponent();
        TitleBar.Follow(this);
        DialogService.OpenLinks(this, m => (DataContext as SettingsViewModel)?.State.Log.Write(m));
    }

    // Menu compresso alle sole icone: dura finche' la finestra e' aperta.
    public static readonly DependencyProperty NavCompactProperty =
        DependencyProperty.Register(nameof(NavCompact), typeof(bool), typeof(SettingsWindow));

    public bool NavCompact
    {
        get => (bool)GetValue(NavCompactProperty);
        set => SetValue(NavCompactProperty, value);
    }

    private void NavToggle_Click(object sender, RoutedEventArgs e) => NavCompact = !NavCompact;

    // Pagina visibile: la voce scelta nel menu e l'indice della pagina (Tag) coincidono.
    public static readonly IMultiValueConverter SameIndex = new SameIndexConverter();

    private sealed class SameIndexConverter : IMultiValueConverter
    {
        public object Convert(object[] values, Type targetType, object parameter, CultureInfo culture) =>
            values is [int selected, int page] && selected == page;

        public object[] ConvertBack(object value, Type[] targetTypes, object parameter, CultureInfo culture) => throw new NotSupportedException();
    }
}
