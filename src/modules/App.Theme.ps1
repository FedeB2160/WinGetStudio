<#
    App.Theme.ps1 — tema Light / Dark / Auto.

    I colori stanno in ui\Theme.Light.xaml / ui\Theme.Dark.xaml e vengono montati in
    Resources.MergedDictionaries: UI.xaml li referenzia con DynamicResource, quindi
    lo swap del dizionario ridipinge la finestra senza ricrearla.

    Initialize-Theme va chiamata dal bootstrap DOPO il FindName: aggancia il pulsante
    e avvia il timer, cose che richiedono i controlli gia' risolti.

    Caricato dal bootstrap (src\main.ps1): dot-source come .ps1,
    concatenato nell'exe al posto del marcatore ###MODULES###.
#>

$themeKey = 'HKCU:\Software\WinGetStudio'

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

    # Icone dal set di sistema: E706 sole, E708 luna, F08C sole con la luna dentro
    # (il "mix" per Auto). Presenti sia in Segoe Fluent Icons sia in Segoe MDL2 Assets.
    # NB: [char]0x.... e non "`u{....}" — l'escape `u esiste solo da PowerShell 6, e
    # ps2exe compila contro 5.1: la stringa resterebbe il letterale "u{E706}" (tofu).
    $glyph, $tip = switch ($script:themeMode) {
        'Light' { [char]0xE706, 'Theme: Light' }
        'Dark'  { [char]0xE708, 'Theme: Dark' }
        default { [char]0xF08C, 'Theme: Auto (follows the system)' }
    }
    $BtnTheme.Content = $glyph
    $BtnTheme.ToolTip = $tip
}

function Initialize-Theme {
    $script:themeMode = 'Auto'   # Auto | Light | Dark
    try {
        $saved = (Get-ItemProperty -Path $themeKey -Name Theme -ErrorAction Stop).Theme
        if ($saved -in @('Auto', 'Light', 'Dark')) { $script:themeMode = $saved }
    } catch { }

    $BtnTheme.Add_Click({
        $script:themeMode = switch ($script:themeMode) {
            'Light' { 'Dark' }
            'Dark'  { 'Auto' }
            default { 'Light' }
        }
        try {
            if (-not (Test-Path $themeKey)) { New-Item -Path $themeKey -Force | Out-Null }
            Set-ItemProperty -Path $themeKey -Name Theme -Value $script:themeMode
        } catch { }   # scelta non persistita: non e' un motivo per non applicare il tema
        Set-Theme
    })

    # In Auto: segue il tema di sistema a caldo.
    # ponytail: poll a 5s invece di SystemEvents.UserPreferenceChanged — l'evento arriva su un
    # thread non-UI e va deiscritto a mano, altrimenti il processo non esce. Se servisse
    # reattivita' istantanea, passare all'evento con unsubscribe in Add_Closed.
    $script:lastSysDark = Test-SystemDark
    $script:themeTimer = New-Object System.Windows.Threading.DispatcherTimer
    $script:themeTimer.Interval = [TimeSpan]::FromSeconds(5)
    $script:themeTimer.Add_Tick({
        if ($script:themeMode -ne 'Auto') { return }
        $d = Test-SystemDark
        if ($d -ne $script:lastSysDark) { $script:lastSysDark = $d; Set-Theme }
    })
    $script:themeTimer.Start()

    Set-Theme
}

