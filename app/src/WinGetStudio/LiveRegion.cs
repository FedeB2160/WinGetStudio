using System.ComponentModel;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Automation.Peers;
using System.Windows.Controls;

namespace WinGetStudio;

// Testo che i lettori di schermo leggono da soli quando cambia (ADR 0028, punto 16): la riga di
// stato, gli Hint, i messaggi al posto della griglia vuota, il riepilogo a fine coda. WPF non
// solleva LiveRegionChanged da se': LiveSetting dice solo come annunciare.
public static class LiveRegion
{
    public static readonly DependencyProperty AnnounceProperty = DependencyProperty.RegisterAttached(
        "Announce", typeof(bool), typeof(LiveRegion), new PropertyMetadata(false, OnAnnounceChanged));

    public static bool GetAnnounce(DependencyObject d) => (bool)d.GetValue(AnnounceProperty);
    public static void SetAnnounce(DependencyObject d, bool value) => d.SetValue(AnnounceProperty, value);

    private static readonly DependencyPropertyDescriptor TextDescriptor =
        DependencyPropertyDescriptor.FromProperty(TextBlock.TextProperty, typeof(TextBlock));

    // shortcut: AddValueChanged tiene vivo il TextBlock finche' Announce resta True; va bene per
    // la finestra principale, che vive quanto l'app. Da rivedere se lo usa una finestra che si chiude.
    private static void OnAnnounceChanged(DependencyObject d, DependencyPropertyChangedEventArgs e)
    {
        if (d is not TextBlock text) return;
        if ((bool)e.NewValue)
        {
            // Polite: aspetta che il lettore finisca la frase in corso, non la interrompe.
            AutomationProperties.SetLiveSetting(text, AutomationLiveSetting.Polite);
            TextDescriptor.AddValueChanged(text, Raise);
        }
        else
        {
            text.ClearValue(AutomationProperties.LiveSettingProperty);
            TextDescriptor.RemoveValueChanged(text, Raise);
        }
    }

    // Solo se un lettore di schermo ascolta, e mai per un testo vuotato.
    private static void Raise(object? sender, EventArgs e)
    {
        if (sender is not TextBlock { Text.Length: > 0 } text || !AutomationPeer.ListenerExists(AutomationEvents.LiveRegionChanged)) return;
        UIElementAutomationPeer.CreatePeerForElement(text)?.RaiseAutomationEvent(AutomationEvents.LiveRegionChanged);
    }
}
