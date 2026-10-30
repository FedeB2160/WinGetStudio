using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;

namespace WinGetStudio;

// L'animazione parte quando lo spinner compare e si ferma quando sparisce: nascosto non consuma.
// Con le animazioni di Windows spente l'arco resta fermo: si vede lo stesso che si sta lavorando.
public partial class Spinner : UserControl
{
    private static readonly DoubleAnimation Spin = new(0, 360, TimeSpan.FromSeconds(0.9)) { RepeatBehavior = RepeatBehavior.Forever };

    public Spinner()
    {
        InitializeComponent();
        IsVisibleChanged += (_, e) =>
            Turn.BeginAnimation(RotateTransform.AngleProperty, (bool)e.NewValue && SystemParameters.ClientAreaAnimation ? Spin : null);
    }
}
