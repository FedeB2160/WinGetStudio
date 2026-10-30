using System.Windows;
using WinGetStudio.ViewModels;

namespace WinGetStudio;

// Settings come finestra modale (ADR 0028). DataContext: SettingsViewModel.
public partial class SettingsWindow : Window
{
    public SettingsWindow()
    {
        InitializeComponent();
        DialogService.OpenLinks(this, m => (DataContext as SettingsViewModel)?.State.Log.Write(m));
    }
}
