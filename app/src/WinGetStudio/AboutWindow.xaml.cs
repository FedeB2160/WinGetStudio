using System.Windows;

namespace WinGetStudio;

// About come finestra modale (ADR 0028).
public partial class AboutWindow : Window
{
    public AboutWindow(string version)
    {
        InitializeComponent();
        TitleBar.Follow(this);
        TxtVersion.Text = $"v{version}";
        DialogService.OpenLinks(this);
    }
}
