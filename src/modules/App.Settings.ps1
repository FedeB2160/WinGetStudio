<#
    App.Settings.ps1 — schermata delle impostazioni: apertura, chiusura e nient'altro.

    Chi ci sta dentro se lo gestisce da solo: il tema e' in App.Theme.ps1, versione e
    aggiornamenti in App.Update.ps1. Qui c'e' solo il pannello.

    PERCHE' NON UNA SECONDA FINESTRA: i colori del tema vivono in
    $window.Resources.MergedDictionaries, quindi una Window separata andrebbe agganciata
    a mano ai dizionari e riagganciata a ogni cambio tema, oltre a richiedere proprietario,
    modalita' e posizione. Un pannello sovrapposto con fondo opaco e' la stessa cosa per
    chi guarda, e segue il tema da solo.

    Caricato da src\main.ps1: dot-source come .ps1, concatenato nell'exe al posto
    del marcatore ###MODULES###.
#>

function Show-Settings {
    $SettingsPanel.Visibility = [System.Windows.Visibility]::Visible
    # Il fuoco va nel pannello, altrimenti Esc resterebbe alla griglia sotto.
    [void]$SettingsPanel.Focus()
}

function Hide-Settings {
    $SettingsPanel.Visibility = [System.Windows.Visibility]::Collapsed
}

function Initialize-Settings {
    $BtnSettings.Add_Click({ Show-Settings })
    $BtnCloseSettings.Add_Click({ Hide-Settings })

    # Esc chiude. PreviewKeyDown sulla FINESTRA e non sul pannello: il tasto arriva al
    # controllo che ha il fuoco, che dopo un clic dentro le impostazioni e' la tendina o
    # un pulsante, non il pannello. In tunneling la finestra lo vede sempre per prima.
    $window.Add_PreviewKeyDown({
        param($s, $e)
        if ($e.Key -eq [System.Windows.Input.Key]::Escape -and
            $SettingsPanel.Visibility -eq [System.Windows.Visibility]::Visible) {
            Hide-Settings
            $e.Handled = $true
        }
    })
}
