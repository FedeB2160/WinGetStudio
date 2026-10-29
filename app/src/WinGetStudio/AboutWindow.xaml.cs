using System.Windows;

namespace WinGetStudio;

// About come finestra modale (ADR 0028).
public partial class AboutWindow : Window
{
    public AboutWindow(string version)
    {
        InitializeComponent();
        TxtVersion.Text = $"Version {version}";
        DialogService.OpenLinks(this);
    }
}
