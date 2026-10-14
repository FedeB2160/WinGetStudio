<#
    App.Ui.ps1 — helper di UI condivisi da tutte le schede.

    Caricato dal bootstrap (src\main.ps1): dot-source come .ps1,
    concatenato nell'exe al posto del marcatore ###MODULES###.
#>

# Riga di log con timestamp. $TxtLog e il log stesso sono condivisi da tutte le
# schede: vivono fuori dal TabControl, in fondo alla finestra.
function Write-Log([string]$msg) {
    $ts = (Get-Date).ToString('HH:mm:ss')
    $TxtLog.AppendText("[$ts] $msg`r`n")
    $TxtLog.ScrollToEnd()
}

# Tempo di avvio per il log: dall'avvio del processo alla finestra disegnata, diviso fra il prima
# del codice dell'app (host dell'exe, scansione antivirus) e l'app stessa. Senza l'inizio dello
# script (test, sorgente caricata a mano) solo il totale.
function Format-StartupTime([datetime]$ProcessStart, $ScriptStart, [datetime]$Ready) {
    $ci = [Globalization.CultureInfo]::InvariantCulture
    $total = ($Ready - $ProcessStart).TotalSeconds.ToString('0.0', $ci)
    if (-not $ScriptStart) { return "Ready in $total s." }
    $before = ([datetime]$ScriptStart - $ProcessStart).TotalSeconds.ToString('0.0', $ci)
    $app    = ($Ready - [datetime]$ScriptStart).TotalSeconds.ToString('0.0', $ci)
    "Ready in $total s: $before s before the app's code started (exe host, antivirus scan), $app s in the app."
}

# Messaggio per una lettura winget fallita, su UNA riga (log e riquadri vuoti): exit e le
# ultime due righe significative, dove winget mette la causa. Stessa regola della coda.
function Format-WinGetReadError([string]$Command, $Result) {
    $message = "winget $Command failed (exit $($Result.ExitCode))"
    $detail  = @(Get-WinGetOutputTail $Result.Output 2) -join ' '
    if ($detail) { $message += ": $detail" }
    return $message
}

# ------------------------------------------------------------------
# POPUP A TEMA (ADR 0020)
# ------------------------------------------------------------------
# La MessageBox di sistema ignora il tema: in Dark esce bianca. Il popup e' una finestra
# propria che prende stili e colori della finestra principale, e rifa' a mano quello che la
# MessageBox dava gratis: Invio ed Esc, il pulsante predefinito, il suono, il testo copiabile,
# la posizione al centro dell'app. Gli enum sono quelli della MessageBox, cosi' le chiamate
# restano leggibili allo stesso modo.
$script:dialogXaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        ShowInTaskbar="False" ResizeMode="NoResize" SizeToContent="WidthAndHeight"
        MinWidth="360" MaxWidth="520"
        Background="{DynamicResource BgBrush}" Foreground="{DynamicResource FgBrush}">
    <Grid>
        <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="Auto"/>
        </Grid.RowDefinitions>
        <Grid Margin="20,20,24,20">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="*"/>
            </Grid.ColumnDefinitions>
            <TextBlock x:Name="DlgIcon" FontFamily="Segoe Fluent Icons, Segoe MDL2 Assets" FontSize="28"
                       Margin="0,0,16,0" VerticalAlignment="Top"/>
            <TextBox x:Name="DlgText" Grid.Column="1" IsReadOnly="True" TextWrapping="Wrap"
                     MaxHeight="480" VerticalScrollBarVisibility="Auto"
                     BorderThickness="0" Background="Transparent" Padding="0"
                     VerticalAlignment="Center" Foreground="{DynamicResource FgBrush}"/>
        </Grid>
        <Border Grid.Row="1" Background="{DynamicResource HeaderBgBrush}" Padding="16,12"
                BorderBrush="{DynamicResource CtrlBorderBrush}" BorderThickness="0,1,0,0">
            <StackPanel x:Name="DlgButtons" Orientation="Horizontal" HorizontalAlignment="Right"/>
        </Border>
    </Grid>
</Window>
'@

# Apre nel browser i link cliccati in una finestra. Un handler per finestra e non uno per link,
# cosi' un link nuovo non richiede codice nuovo. La finestra principale e i popup ne hanno uno
# ciascuno: l'evento sale solo dentro la propria finestra.
function Add-LinkHandler($Target) {
    $Target.AddHandler(
        [System.Windows.Documents.Hyperlink]::RequestNavigateEvent,
        [System.Windows.Navigation.RequestNavigateEventHandler]{
            param($s, $e)
            try { Start-Process $e.Uri.AbsoluteUri } catch { Write-Log "Could not open $($e.Uri): $($_.Exception.Message)" }
            $e.Handled = $true
        })
}

# Testo con i link cliccabili, per -Links: un RichTextBox in sola lettura, selezionabile e
# copiabile come il TextBox, dove ogni http(s):// diventa un Hyperlink. La punteggiatura che
# chiude una frase o una parentesi non fa parte del link. Larghezza fissa: in un popup che
# prende la misura del contenuto un RichTextBox non ne ha una sua.
function New-LinkedText([string]$Text) {
    $p = New-Object System.Windows.Documents.Paragraph
    $p.Margin = New-Object System.Windows.Thickness 0
    $lines = $Text -split "`r?`n"
    for ($i = 0; $i -lt $lines.Count; $i++) {
        $rest = $lines[$i]
        while ($rest -match '(?<pre>.*?)(?<url>https?://[^\s<>"]*[^\s<>".,;:!?)\]])') {
            if ($Matches.pre) { $p.Inlines.Add((New-Object System.Windows.Documents.Run $Matches.pre)) }
            $link = New-Object System.Windows.Documents.Hyperlink (New-Object System.Windows.Documents.Run $Matches.url)
            $link.NavigateUri = [Uri]$Matches.url
            $link.SetResourceReference([System.Windows.Documents.TextElement]::ForegroundProperty, 'AccentBrush')
            $p.Inlines.Add($link)
            $rest = $rest.Substring($Matches[0].Length)
        }
        if ($rest) { $p.Inlines.Add((New-Object System.Windows.Documents.Run $rest)) }
        if ($i -lt $lines.Count - 1) { $p.Inlines.Add((New-Object System.Windows.Documents.LineBreak)) }
    }
    $doc = New-Object System.Windows.Documents.FlowDocument $p
    $doc.PagePadding = New-Object System.Windows.Thickness 0
    $doc.FontFamily  = New-Object System.Windows.Media.FontFamily 'Segoe UI'
    $doc.FontSize    = 12
    $rtb = New-Object System.Windows.Controls.RichTextBox $doc
    $rtb.IsReadOnly        = $true
    $rtb.IsDocumentEnabled = $true
    $rtb.BorderThickness   = New-Object System.Windows.Thickness 0
    $rtb.Background        = [System.Windows.Media.Brushes]::Transparent
    $rtb.Width             = 440
    $rtb.MaxHeight         = 480
    $rtb.VerticalScrollBarVisibility = [System.Windows.Controls.ScrollBarVisibility]::Auto
    $rtb.SetResourceReference([System.Windows.Controls.Control]::ForegroundProperty, 'FgBrush')
    $rtb
}

# Costruisce il popup SENZA mostrarlo, cosi' il test lo puo' ispezionare.
# -Links: gli indirizzi web del testo si aprono col clic (dettagli di un pacchetto).
function New-AppDialog {
    param(
        [string]$Text,
        [string]$Title = 'WinGet Studio',
        [System.Windows.MessageBoxButton]$Button = 'OK',
        [System.Windows.MessageBoxImage]$Image = 'None',
        [System.Windows.MessageBoxResult]$Default = 'None',
        [switch]$Links
    )
    $dlg = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader ([xml]$script:dialogXaml)))
    # Stili (il template dei Button compreso) e brush del tema corrente: quelli della finestra
    # principale, che li tiene nelle sue Resources.
    $dlg.Resources.MergedDictionaries.Add($window.Resources)
    $dlg.Title = $Title
    $dlgText = $dlg.FindName('DlgText')
    $dlgText.Text = $Text
    if ($Links) {
        $rtb = New-LinkedText $Text
        [System.Windows.Controls.Grid]::SetColumn($rtb, 1)
        [void]$dlgText.Parent.Children.Add($rtb)
        $dlgText.Visibility = [System.Windows.Visibility]::Collapsed
    }
    Add-LinkHandler $dlg
    # Owner solo a finestra visibile: su una finestra mai mostrata WPF lancia un'eccezione.
    if ($window.IsVisible) {
        $dlg.Owner = $window
        $dlg.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterOwner
    }
    else { $dlg.WindowStartupLocation = [System.Windows.WindowStartupLocation]::CenterScreen }

    # Icone e colori della colonna Result; informazione e domanda nel colore accento.
    $icon = @{ 16 = @(0xEB90, 'ErrBrush'); 48 = @(0xE814, 'WarnBrush')
               32 = @(0xE9CE, 'AccentBrush'); 64 = @(0xE946, 'AccentBrush') }[[int]$Image]
    $iconBlock = $dlg.FindName('DlgIcon')
    if ($icon) {
        $iconBlock.Text = [string][char]$icon[0]
        $iconBlock.SetResourceReference([System.Windows.Controls.TextBlock]::ForegroundProperty, $icon[1])
    }
    else { $iconBlock.Visibility = [System.Windows.Visibility]::Collapsed }

    # Invio sceglie il predefinito (No sulle conferme, se chi chiama lo chiede), Esc e la X
    # l'ultimo, cioe' No oppure OK. Il predefinito e' in colore accento: si vede cosa fa Invio.
    $names  = @(if ($Button -eq [System.Windows.MessageBoxButton]::YesNo) { 'Yes', 'No' } else { 'OK' })
    $def    = if ($names.Count -eq 1) { 'OK' } elseif ($Default -eq [System.Windows.MessageBoxResult]::No) { 'No' } else { 'Yes' }
    foreach ($n in $names) {
        $b = New-Object System.Windows.Controls.Button
        $b.Content   = $n
        $b.Tag       = $n
        $b.MinWidth  = 88
        $b.Height    = 28
        $b.Padding   = New-Object System.Windows.Thickness 16, 0, 16, 0
        $b.Margin    = New-Object System.Windows.Thickness 8, 0, 0, 0
        $b.IsDefault = $n -eq $def
        $b.IsCancel  = $n -eq $names[-1]
        if ($b.IsDefault) {
            $b.SetResourceReference([System.Windows.Controls.Control]::BackgroundProperty, 'AccentBrush')
            $b.SetResourceReference([System.Windows.Controls.Control]::ForegroundProperty, 'AccentFgBrush')
        }
        # Il sender e non $b: l'handler non vede le variabili di questo ciclo (ADR 0008).
        $b.Add_Click({ param($s, $e) $w = [System.Windows.Window]::GetWindow($s); $w.Tag = $s.Tag; $w.Close() })
        [void]$dlg.FindName('DlgButtons').Children.Add($b)
    }
    $dlg.Add_Loaded({
        param($s, $e)
        $d = @($s.FindName('DlgButtons').Children | Where-Object { $_.IsDefault })[0]
        if ($d) { [void]$d.Focus() }
    })
    # La barra del titolo la disegna Windows: va scurita come quella della finestra principale.
    $dlg.Add_SourceInitialized({ param($s, $e) Set-TitleBarDark $script:themeDark $s })
    return $dlg
}

# Velo sulla finestra principale mentre un popup e' aperto. Dissolvenza di 150 ms, niente se in
# Windows le animazioni sono spente. $script:dimOn dice se nel frattempo un altro popup l'ha
# riacceso, e allora la fine della dissolvenza in uscita non lo deve nascondere.
$script:dimOn = $false
function Set-DialogDim([bool]$On, [bool]$Animate = [System.Windows.SystemParameters]::ClientAreaAnimation) {
    $script:dimOn = $On
    $prop = [System.Windows.UIElement]::OpacityProperty
    if ($On) { $DialogDim.Visibility = [System.Windows.Visibility]::Visible }
    if (-not $Animate) {
        $DialogDim.BeginAnimation($prop, $null)
        $DialogDim.Opacity = [double][int]$On
        if (-not $On) { $DialogDim.Visibility = [System.Windows.Visibility]::Collapsed }
        return
    }
    $a = New-Object System.Windows.Media.Animation.DoubleAnimation
    $a.To       = [double][int]$On
    $a.Duration = New-Object System.Windows.Duration ([TimeSpan]::FromMilliseconds(150))
    $ease = New-Object System.Windows.Media.Animation.CubicEase
    $ease.EasingMode = [System.Windows.Media.Animation.EasingMode]::EaseOut
    $a.EasingFunction = $ease
    if (-not $On) {
        $a.Add_Completed({ if (-not $script:dimOn) { $DialogDim.Visibility = [System.Windows.Visibility]::Collapsed } })
    }
    $DialogDim.BeginAnimation($prop, $a)
}

# Mostra il popup e torna la risposta come la MessageBox ([MessageBoxResult]).
function Show-AppDialog {
    param(
        [string]$Text,
        [string]$Title = 'WinGet Studio',
        [System.Windows.MessageBoxButton]$Button = 'OK',
        [System.Windows.MessageBoxImage]$Image = 'None',
        [System.Windows.MessageBoxResult]$Default = 'None',
        [switch]$Links
    )
    try { $dlg = New-AppDialog -Text $Text -Title $Title -Button $Button -Image $Image -Default $Default -Links:$Links }
    catch {
        # Ripiego sulla MessageBox di sistema: un messaggio non deve perdersi proprio quando
        # qualcosa e' guasto (tema o XAML).
        if ($window -and $window.IsVisible) { return [System.Windows.MessageBox]::Show($window, $Text, $Title, $Button, $Image, $Default) }
        return [System.Windows.MessageBox]::Show($Text, $Title, $Button, $Image, $Default)
    }
    # Il suono che la MessageBox fa per lo stesso tipo di messaggio.
    switch ([int]$Image) {
        16 { [System.Media.SystemSounds]::Hand.Play() }
        48 { [System.Media.SystemSounds]::Exclamation.Play() }
        32 { [System.Media.SystemSounds]::Question.Play() }
        64 { [System.Media.SystemSounds]::Asterisk.Play() }
    }
    Set-DialogDim $true
    try { [void]$dlg.ShowDialog() } finally { Set-DialogDim $false }
    if ($dlg.Tag) { return [System.Windows.MessageBoxResult]$dlg.Tag }
    # Esc o la X: la risposta prudente, cioe' No (oppure OK).
    if ($Button -eq [System.Windows.MessageBoxButton]::YesNo) { return [System.Windows.MessageBoxResult]::No }
    return [System.Windows.MessageBoxResult]::OK
}

# Dettagli di un pacchetto (ADR 0021): il testo di winget in un popup, letto in un job dietro
# lo stato occupato, perche' e' un processo winget come gli altri (ADR 0003). -Installed
# aggiunge list --details; la sorgente della riga decide se c'e' anche la parte di catalogo.
# La riga passa da $script: perche' OnDone non vede le variabili di questa funzione (ADR 0008).
function Show-PackageDetails([object]$Row, [bool]$Installed) {
    if (Test-WinGetBusy) { return }
    Set-AppBusy $true
    $Progress.IsIndeterminate = $true
    Write-Log "Reading the details of $($Row.Name) [$($Row.Id)]..."
    $script:detailsRow = $Row
    [void](Start-BackgroundJob -Functions 'Get-WinGetDetails', 'Invoke-WinGetRead', 'Get-WinGetTable' `
        -Vars @{ wingetPath = $wingetPath; id = $Row.Id; source = $Row.Source; installed = $Installed } `
        -Script { Get-WinGetDetails $id $source $installed } `
        -OnDone {
            param($result)
            $Progress.IsIndeterminate = $false
            Set-AppBusy $false
            $text = (@($result) | Where-Object { $_ }) -join "`r`n"
            if (-not $text) { $text = 'winget returned no details for this package.' }
            Show-AppDialog -Text $text -Title "$($script:detailsRow.Name) - details" -Links | Out-Null
        })
}

# ------------------------------------------------------------------
# STATO "OCCUPATO" GLOBALE
# ------------------------------------------------------------------
# winget non e' affidabile in parallelo, quindi un'operazione in corso su una scheda
# deve spegnere i comandi di TUTTE le schede — non solo della sua.
# Ogni scheda registra il proprio handler in Initialize-*Tab invece di essere chiamata
# per nome da qui: cosi' aggiungere una scheda non richiede di toccare questo file.
$script:isBusy       = $false
$script:busyHandlers = New-Object System.Collections.ArrayList

function Register-BusyHandler([scriptblock]$handler) {
    [void]$script:busyHandlers.Add($handler)
}

# $script:queueVerb dice QUALE coda sta girando ('Update', 'Install', 'Uninstall', 'Pin')
# oppure $null. Lo stato occupato e' globale, quindi senza questo una scheda non puo'
# distinguere la propria operazione da quella di un'altra — ed e' l'unico modo per offrire
# "Cancel" solo a chi l'ha avviata. Lo scrive Start-WinGetQueue.
# Si azzera PRIMA di chiamare gli handler, cosi' ognuno vede lo stato finale.
function Set-AppBusy([bool]$busy) {
    $script:isBusy = $busy
    if (-not $busy) { $script:queueVerb = $null }
    foreach ($h in $script:busyHandlers) { & $h $busy }
}

# Sta girando un processo winget? Comprende le RICERCHE, che di proposito NON alzano lo stato
# occupato — il typeahead deve restare fluido — ma sono comunque un processo winget. Chi sta
# per lanciarne un altro deve chiedere a questa, non a $script:isBusy: con il solo isBusy,
# digitare in Install e passare subito a Installed lanciava winget search e winget list
# insieme, ed e' con due processi in parallelo che un comando esce con exit 1.
# $script:searchInFlight vive in Tab.Install.ps1 e vale 0 finche' quel modulo non e' stato
# caricato; il confronto regge anche su $null.
function Test-WinGetBusy {
    return ($script:isBusy -or ($script:searchInFlight -gt 0))
}

# ------------------------------------------------------------------
# RICALCOLO DIFFERITO DEI CONTATORI DI UNA GRIGLIA
# ------------------------------------------------------------------
# Aggancia a una griglia il ricalcolo dei suoi contatori. Le tre schede avevano lo stesso
# blocco copiato con dentro il solo nome della funzione diverso: il prossimo inciampo
# sull'overload di BeginInvoke andrebbe corretto in tre punti.
# PERCHE' DIFFERITO: il binding della spunta e' UpdateSourceTrigger=PropertyChanged, ma il
# valore arriva sull'oggetto solo DOPO che il ToggleButton ha commutato, quindi il ricalcolo
# va rimandato a priorita' Background.
# PERCHE' PreviewMouseLeftButtonUp: evento tunneling, raggiunge la griglia prima che la
# CheckBox marchi l'evento come gestito -> contatori ed etichette si aggiornano al clic e non
# alla perdita di fuoco della cella.
# NB: BeginInvoke([action]{...}, 'Background') NON esiste come overload -> PowerShell risolve
# su BeginInvoke(Delegate, params Object[]) e passa 'Background' COME ARGOMENTO a un delegate
# senza parametri => TargetParameterCountException, che risale da ShowDialog(). Va usata la
# forma con la priorita' PER PRIMA e l'enum tipizzato.
# Il nome della funzione si INTERPOLA nel testo e l'handler nasce da [scriptblock]::Create: i
# parametri di questa funzione non esistono piu' quando l'evento scatta, e .GetNewClosure()
# non e' la via d'uscita — la closure crea un module scope dove $script: non e' piu' lo scope
# di questo script (vedi App.Jobs.ps1).
# $Target e non $Grid: un parametro chiamato $Grid coprirebbe il controllo omonimo.
function Register-GridRefresh($Target, [string]$RefreshFunction) {
    $handler = [scriptblock]::Create(
        "`$window.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::Background, [action]{ $RefreshFunction }) | Out-Null")
    $Target.Add_CellEditEnding($handler)
    $Target.Add_PreviewMouseLeftButtonUp($handler)
}

