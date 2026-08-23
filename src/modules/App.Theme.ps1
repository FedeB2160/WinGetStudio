<#
    App.Theme.ps1 — tema Light / Dark / System.

    I colori stanno in ui\Theme.Light.xaml / ui\Theme.Dark.xaml e vengono montati in
    Resources.MergedDictionaries: UI.xaml li referenzia con DynamicResource, quindi
    lo swap del dizionario ridipinge la finestra senza ricrearla.

    Initialize-Theme va chiamata dal bootstrap DOPO il FindName: aggancia il pulsante
    e avvia il timer, cose che richiedono i controlli gia' risolti.

    Caricato dal bootstrap (src\main.ps1): dot-source come .ps1,
    concatenato nell'exe al posto del marcatore ###MODULES###.
#>

# Tema di sistema: AppsUseLightTheme = 0 -> scuro. Assente su Win10 vecchi -> chiaro.
function Test-SystemDark {
    try {
        (Get-ItemPropertyValue -Path 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Themes\Personalize' `
                               -Name 'AppsUseLightTheme' -ErrorAction Stop) -eq 0
    } catch { $false }
}

$script:dwmReady = $false
function Set-TitleBarDark([bool]$dark) {
    # Senza questo la barra titolo resta bianca in Dark-Mode (la disegna Windows, non WPF).
    if (-not $dark -and -not $script:dwmReady) { return }   # gia' chiara: niente da fare
    if (-not $script:dwmReady) {
        # Add-Type -MemberDefinition compila C# al volo (~1s): si paga solo al primo
        # passaggio in Dark-Mode, non a ogni avvio.
        Add-Type -Namespace Dwm -Name Api -MemberDefinition @'
[DllImport("dwmapi.dll")]
public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int val, int size);
'@
        $script:dwmReady = $true
    }
    $hwnd = (New-Object Windows.Interop.WindowInteropHelper $window).Handle
    if ($hwnd -eq [IntPtr]::Zero) { return }   # finestra non ancora mostrata
    $v = [int]$dark
    # DWMWA_USE_IMMERSIVE_DARK_MODE = 20 (Win10 2004+ / Win11). Su build precedenti
    # l'attributo non esiste: la chiamata torna errore e la barra resta chiara.
    [void][Dwm.Api]::DwmSetWindowAttribute($hwnd, 20, [ref]$v, 4)
}

function Set-Theme {
    $dark = switch ($script:themeMode) {
        'Dark'  { $true }
        'Light' { $false }
        default { Test-SystemDark }
    }
    $window.Resources.MergedDictionaries.Clear()
    $window.Resources.MergedDictionaries.Add(
        (Read-Xaml $(if ($dark) { 'Theme.Dark.xaml' } else { 'Theme.Light.xaml' })))
    Set-TitleBarDark $dark

    # In System si dice quale dei due tempi sta seguendo, altrimenti la scelta non spiega
    # cosa si vede a schermo.
    $TxtThemeHint.Text = if ($script:themeMode -eq 'System') {
        "following the system: $(if ($dark) { 'dark' } else { 'light' })"
    } else { '' }
}

function Initialize-Theme {
    # System | Light | Dark. "System" e non "Auto": dice cosa segue invece di lasciarlo
    # indovinare. Un valore fuori dai tre torna al default — compreso l'"Auto" che le versioni
    # fino alla 1.9.0 salvavano, che e' esattamente lo stesso comportamento con un altro nome,
    # quindi chi aggiorna non perde niente e non serve una conversione.
    $saved = [string](Get-Pref 'Theme' 'System')
    $script:themeMode = if ($saved -in @('System', 'Light', 'Dark')) { $saved } else { 'System' }

    # Le voci sono ANCHE i valori salvati nel registro: nessuna tabella di conversione
    # fra etichetta a schermo e valore memorizzato.
    foreach ($m in 'Light', 'Dark', 'System') { [void]$CmbTheme.Items.Add($m) }
    $CmbTheme.SelectedItem = $script:themeMode

    # NB: Set-Theme non riscrive la selezione della tendina, altrimenti questo handler
    # richiamerebbe se stesso a ogni applicazione del tema.
    $CmbTheme.Add_SelectionChanged({
        $chosen = [string]$CmbTheme.SelectedItem
        if (-not $chosen -or $chosen -eq $script:themeMode) { return }
        $script:themeMode = $chosen
        Set-Pref 'Theme' $script:themeMode
        Set-Theme
    })

    # In System: segue il tema di sistema a caldo.
    # ponytail: poll a 5s invece di SystemEvents.UserPreferenceChanged — l'evento arriva su un
    # thread non-UI e va deiscritto a mano, altrimenti il processo non esce. Se servisse
    # reattivita' istantanea, passare all'evento con unsubscribe in Add_Closed.
    $script:lastSysDark = Test-SystemDark
    $script:themeTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:themeTimer.Interval = [TimeSpan]::FromSeconds(5)
    $script:themeTimer.Add_Tick({
        if ($script:themeMode -ne 'System') { return }
        $d = Test-SystemDark
        if ($d -ne $script:lastSysDark) { $script:lastSysDark = $d; Set-Theme }
    })
    $script:themeTimer.Start()

    Set-Theme
}

