using System.Windows;
using System.Windows.Controls;
using System.Windows.Media.Animation;

namespace WinGetStudio;

// IsActive vero: visibile subito ma trasparente, piena dopo 400 ms con un salto (keyframe
// discreto, non una dissolvenza: vale anche con le animazioni di Windows spente). Una ricerca
// piu' breve non fa lampeggiare nulla e non fa parlare Narrator. IsActive falso: via subito.
public partial class BusyOverlay : UserControl
{
    public static readonly DependencyProperty IsActiveProperty = DependencyProperty.Register(
        nameof(IsActive), typeof(bool), typeof(BusyOverlay), new PropertyMetadata(false, (d, _) => ((BusyOverlay)d).Update()));

    public static readonly DependencyProperty TextProperty = DependencyProperty.Register(
        nameof(Text), typeof(string), typeof(BusyOverlay), new PropertyMetadata("", (d, _) => ((BusyOverlay)d).Update()));

    public bool IsActive
    {
        get => (bool)GetValue(IsActiveProperty);
        set => SetValue(IsActiveProperty, value);
    }

    public string Text
    {
        get => (string)GetValue(TextProperty);
        set => SetValue(TextProperty, value);
    }

    private readonly DoubleAnimationUsingKeyFrames _reveal = new()
    {
        KeyFrames = { new DiscreteDoubleKeyFrame(1, KeyTime.FromTimeSpan(TimeSpan.FromMilliseconds(400))) },
    };

    private bool _shown;

    public BusyOverlay()
    {
        InitializeComponent();
        _reveal.Completed += (_, _) =>
        {
            if (!IsActive) return;
            _shown = true;
            Caption.Text = Text;
        };
    }

    private void Update()
    {
        if (IsActive)
        {
            // Gia' acceso: cambia solo la scritta (l'import che rilegge l'elenco), se gia' a schermo.
            if (Visibility == Visibility.Visible)
            {
                if (_shown) Caption.Text = Text;
                return;
            }
            Visibility = Visibility.Visible;
            BeginAnimation(OpacityProperty, _reveal);
        }
        else
        {
            BeginAnimation(OpacityProperty, null);
            Visibility = Visibility.Collapsed;
            _shown = false;
            Caption.Text = "";
        }
    }
}
