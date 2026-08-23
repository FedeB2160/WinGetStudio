<#
    App.Bootstrap.ps1 — costruzione della finestra e avvio dell'applicazione.

    Il tipo riga (WgtRow), il caricamento degli XAML e Start-App, che monta la
    finestra, risolve i controlli e passa la mano ai moduli di scheda.

    PERCHE' $script: SUI CONTROLLI: Start-App e' una funzione, quindi un semplice
    "$Grid = ..." creerebbe una variabile locale invisibile ai moduli. Con $script: i
    controlli finiscono nello scope dello script e i moduli li leggono senza prefisso
    (la catena di scope risale fino a lui).

    Caricato da src\main.ps1: dot-source come .ps1, concatenato nell'exe al posto
    del marcatore ###MODULES###.
#>

# ------------------------------------------------------------------
# Assembly WPF
# ------------------------------------------------------------------
Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

# Output winget in UTF-8 (nomi con accenti/caratteri non-ASCII)
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }

# ------------------------------------------------------------------
# Riga della griglia (INotifyPropertyChanged)
# ------------------------------------------------------------------
# PERCHE' NON UN PSCustomObject: le NoteProperty non notificano WPF, quindi ogni cambio
# di stato richiedeva $Grid.Items.Refresh(). Quel Refresh rigenera l'intera vista e
# riporta lo scroll in cima: durante l'aggiornamento veniva chiamato 3 volte per
# pacchetto, rendendo l'elenco di fatto non scorrevole. Con INotifyPropertyChanged si
# ridisegna la sola cella cambiata e lo scroll resta dov'e' l'utente.
# NB: i setter vanno invocati sul thread UI (nel runspace di update passano da UI{}).
# Add-Type registra il tipo nell'AppDomain, quindi WgtRow e' visibile anche dentro i
# runspace di background, che ricevono solo il corpo delle funzioni.
if (-not ('WgtRow' -as [type])) {
    Add-Type -TypeDefinition @'
using System.ComponentModel;
public class WgtRow : INotifyPropertyChanged {
    public event PropertyChangedEventHandler PropertyChanged;
    private void P(string n) {
        PropertyChangedEventHandler h = PropertyChanged;
        if (h != null) h(this, new PropertyChangedEventArgs(n));
    }
    private bool _selected, _pinned;
    private string _name = "", _version = "", _available = "", _id = "", _status = "", _detail = "";
    public bool Selected      { get { return _selected; }  set { _selected = value;  P("Selected"); } }
    public bool Pinned        { get { return _pinned; }    set { _pinned = value;    P("Pinned"); } }
    public string Name        { get { return _name; }      set { _name = value;      P("Name"); } }
    public string Version     { get { return _version; }   set { _version = value;   P("Version"); } }
    public string Available   { get { return _available; } set { _available = value; P("Available"); } }
    public string Id          { get { return _id; }        set { _id = value;        P("Id"); } }
    public string Status      { get { return _status; }    set { _status = value;    P("Status"); } }
    public string StatusDetail{ get { return _detail; }    set { _detail = value;    P("StatusDetail"); } }
}
'@
}

# ------------------------------------------------------------------
# XAML
# ------------------------------------------------------------------
# Copie embeddate dei file XAML: build.ps1 sostituisce i marcatori ###nome### col
# contenuto reale, cosi' l'exe resta un file solo. Eseguito come .ps1 i marcatori
# restano tali, ma non importa: i file su disco ci sono e hanno la precedenza.
$embeddedXaml = @{
    'UI.xaml' = @'
###UI.xaml###
'@
    'Theme.Light.xaml' = @'
###Theme.Light.xaml###
'@
    'Theme.Dark.xaml' = @'
###Theme.Dark.xaml###
'@
}

# File su disco se presente (si ritocca la UI senza ricompilare), altrimenti la copia
# embeddata nell'exe.
function Get-XamlText([string]$name) {
    $p = Resolve-Asset "ui\$name"
    if ($p) { return (Get-Content $p -Raw -Encoding UTF8) }
    return $embeddedXaml[$name]
}

# Ritorna l'oggetto radice del file: Window per UI.xaml, ResourceDictionary per i temi.
function Read-Xaml([string]$name) {
    $text = Get-XamlText $name
    if ([string]::IsNullOrWhiteSpace($text) -or $text -match '^\s*###') {
        throw "XAML not available: $name"
    }
    [Windows.Markup.XamlReader]::Load(
        (New-Object System.Xml.XmlNodeReader ([xml]$text)))
}

# ------------------------------------------------------------------
# AVVIO
# ------------------------------------------------------------------
# -NoShow monta tutto senza aprire la finestra: e' la cucitura che permette a
# Test-Ui.ps1 di verificare che i moduli vedano davvero i controlli (uno "$Grid = ..."
# senza $script: compilerebbe e passerebbe ogni controllo statico, per poi fallire a
# finestra aperta).
function Start-App([switch]$NoShow) {
    # 1) winget presente?
    $script:wingetPath = Get-WinGetPath
    if (-not $script:wingetPath) {
        [System.Windows.MessageBox]::Show(
            "winget is not installed or not available in PATH.`n`n" +
            "Install 'App Installer' from the Microsoft Store (Windows 10/11) and try again.",
            "winget not found",
            [System.Windows.MessageBoxButton]::OK,
            [System.Windows.MessageBoxImage]::Error) | Out-Null
        return
    }

    # 2) Finestra
    $script:window = Read-Xaml 'UI.xaml'

    # 3) Riferimenti ai controlli
    foreach ($n in @(
        'BtnRefresh', 'ChkUnknown', 'BtnToggleAll', 'BtnUpdate', 'TxtAvailable',
        'TxtSelected', 'Grid', 'TxtEmpty', 'TopSpinner', 'Progress', 'TxtLog',
        'TxtSearch', 'BtnSearch', 'ChkStore', 'BtnScope', 'SearchSpinner',
        'GridSearch', 'TxtSearchEmpty', 'TxtSearchInfo', 'BtnInstall',
        'TabMain', 'BtnRefreshInstalled', 'TxtFilter', 'InstalledSpinner',
        'TxtInstalledCount', 'GridInstalled', 'TxtInstalledEmpty',
        'TxtInstalledInfo', 'BtnUninstall',
        'MenuPinUpdates', 'MenuUnpinUpdates', 'MenuPinInstalled', 'MenuUnpinInstalled',
        'BtnExport', 'BtnImport',
        'CmbTheme', 'TxtThemeHint', 'TxtVersion', 'BtnCheckUpdate', 'BtnUpdateApp',
        'UpdateSpinner', 'TxtUpdateStatus',
        'TabInstall', 'TabInstalled', 'TabUpdates', 'TabSettings'
    )) {
        $c = $script:window.FindName($n)
        if (-not $c) { throw "Control not found in UI.xaml: $n" }
        Set-Variable -Name $n -Value $c -Scope Script
    }

    # 4) Icona finestra: come .exe (ps2exe -iconFile) l'icona e' gia' embeddata;
    #    come .ps1 in sviluppo carica assets\icon.ico se presente.
    $iconPath = Resolve-Asset 'assets\icon.ico'
    if ($iconPath) {
        try { $script:window.Icon = [Windows.Media.Imaging.BitmapFrame]::Create([Uri]$iconPath) } catch { }
    }

    # 5) Aggancio dei controlli: da qui in poi i moduli possono lavorare.
    Initialize-Theme
    Initialize-UpdatesTab
    Initialize-InstallTab
    Initialize-InstalledTab
    Initialize-Backup
    Initialize-Update

    # Alla chiusura: ferma timer e chiudi i job pendenti, cosi' il processo termina
    # davvero (niente thread in background lasciati vivi).
    $script:window.Add_Closed({
        Stop-AllJobs
        if ($script:themeTimer) { try { $script:themeTimer.Stop() } catch { } }
    })

    # Carica gli upgrade all'apertura. Secondo Set-Theme: al primo giro la finestra non
    # aveva ancora un HWND, quindi la barra titolo non era stata colorata.
    $script:window.Add_ContentRendered({ Set-Theme; Load-Upgrades; Start-UpdateCheck })

    if ($NoShow) { return }
    $script:window.ShowDialog() | Out-Null
}




