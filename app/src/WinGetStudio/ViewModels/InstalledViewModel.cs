using System.IO;
using System.Windows;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using WinGetStudio.Core;

namespace WinGetStudio.ViewModels;

// Scheda Installed (Tab.Installed.ps1 e App.Backup.ps1 della 1.x): inventario, filtro,
// disinstallazione, export e import dell'elenco.
public sealed partial class InstalledViewModel : PackageListViewModel
{
    private const string ListFilter = "Package list (*.json)|*.json|All files (*.*)|*.*";

    private string _filterText = "";

    public InstalledViewModel(AppState state) : base(state)
    {
        state.InstalledStale += () => Loaded = false;
        EmptyText = "Press Refresh to list the installed packages.";
        CountText = InfoText = "";
        Refresh();
    }

    protected override bool DetailsInstalled => true;

    // L'elenco costa un paio di secondi di winget: si carica alla prima apertura della scheda,
    // e dopo un'azione da un'altra scheda alla prossima.
    public bool Loaded { get; private set; }

    // Filtro locale: le righe escluse restano (e restano spuntate), la vista le nasconde.
    public string FilterText
    {
        get => _filterText;
        set { if (SetProperty(ref _filterText, value)) Refresh(); }
    }

    [ObservableProperty] public partial bool Loading { get; private set; }
    // La scritta sotto lo spinner al centro della griglia (BusyOverlay): cosa sta facendo winget.
    [ObservableProperty] public partial string LoadingText { get; private set; } = "";
    [ObservableProperty] public partial string EmptyText { get; private set; }
    [ObservableProperty] public partial string CountText { get; private set; }
    [ObservableProperty] public partial string InfoText { get; private set; }

    // "Seleziona tutto" solo sulle righe visibili: spuntare righe nascoste dal filtro per poi
    // disinstallarle e' proprio cio' che la conferma deve segnalare, non provocare.
    protected override IEnumerable<PackageItem> Selectable => Items.Where(Matches);

    // Un filtro che nasconde tutto: al posto della griglia vuota, il messaggio che lo dice.
    public override bool HasItems => Items.Any(Matches);

    public bool Matches(PackageItem item)
    {
        var f = FilterText.Trim();
        return f.Length == 0 || item.Name.Contains(f, StringComparison.OrdinalIgnoreCase) || item.Id.Contains(f, StringComparison.OrdinalIgnoreCase);
    }

    [RelayCommand(CanExecute = nameof(IsIdle))]
    private Task Reload() => LoadAsync();

    public async Task LoadAsync(bool keepOutcome = false)
    {
        if (!State.TryBegin()) return;
        try { await LoadCoreAsync(keepOutcome); }
        finally { State.End(); }
    }

    private async Task LoadCoreAsync(bool keepOutcome)
    {
        var outcomes = keepOutcome ? SnapshotOutcomes() : null;
        Loaded = true;
        State.Log.Write("Listing installed packages...");
        EmptyText = "";
        LoadingText = "Listing installed packages...";
        Loading = true;
        // I pin nella stessa operazione: due winget insieme fanno fallire uno dei due.
        var read = await State.Backend.GetInstalledAsync();
        var pins = await State.Backend.GetPinsAsync();
        Loading = false;
        // Le righe vecchie restano sotto il velo (BusyOverlay) finche' arrivano le nuove.
        Items.Clear();
        if (read.Success) Fill(read.Rows, outcomes);
        if (Items.Count == 0)
        {
            EmptyText = read.Success ? "No installed package found." : AppState.ReadError("list", read);
            State.Log.Write(EmptyText);
        }
        else State.Log.Write($"Found {Items.Count} installed packages.");
        State.ApplyPins(pins);
    }

    [RelayCommand(CanExecute = nameof(CanUninstall))]
    public async Task UninstallAsync()
    {
        var selected = Items.Where(i => i.Selected).ToList();
        if (selected.Count == 0) return;
        // CONFERMA OBBLIGATORIA, con i nomi reali in coda compresi quelli che il filtro
        // nasconde, e No predefinito: un Invio distratto non deve disinstallare nulla.
        var hidden = selected.Count(i => !Matches(i));
        var answer = State.Dialogs.Show(
            $"Uninstall {selected.Count} package{(selected.Count == 1 ? "" : "s")}?\n\n" + AppState.NameList(selected.Select(i => i.Name)) +
            (hidden > 0 ? $"\n\n{hidden} of them are currently hidden by the filter." : "") + "\n\nThis cannot be undone.",
            "Confirm uninstall", MessageBoxButton.YesNo, MessageBoxImage.Warning, MessageBoxResult.No, verbs: ("Uninstall", "Cancel"));
        if (answer != MessageBoxResult.Yes)
        {
            State.Log.Write("Uninstall canceled.");
            return;
        }
        // Updates ora mente: un pacchetto rimosso puo' esserci ancora. Questo elenco si rilegge
        // subito, con l'esito per Id: i rimossi spariscono, i falliti restano.
        await State.RunQueueAsync(new QueueRequest(Core.QueueVerb.Uninstall, [.. selected.Select(i => i.Row)], WinGetCommands.Uninstall), Items, () =>
        {
            State.MarkUpdatesStale();
            return LoadCoreAsync(keepOutcome: true);
        });
    }

    private bool CanUninstall() => State.IsIdle && Items.Any(i => i.Selected);

    // Un comando unico su tutta la macchina, non una coda.
    [RelayCommand(CanExecute = nameof(IsIdle))]
    public async Task ExportAsync()
    {
        if (State.IsWinGetBusy) return;
        var file = State.Dialogs.PickSaveFile("Export installed packages", ListFilter, $"winget-packages-{DateTime.Now:yyyy-MM-dd}.json");
        // Di nuovo: fra la scelta del file e qui puo' essere rientrata una ricerca.
        if (file is null || !State.TryBegin()) return;
        LoadingText = "Exporting the package list...";
        Loading = true;
        State.Log.Write($"Exporting the package list to {file} ...");
        string? failure = null;
        try
        {
            var r = await RunAsync(WinGetCommands.Export(file), "export");
            if (ExitCodes.Classify(r.ExitCode) == OperationStatus.Ok)
            {
                var n = PackageList.Load(file)?.Packages.Count;
                State.Log.Write($"Export done: {(n is null ? "file written" : $"{n} packages")}.");
                // Pacchetti che nessuna sorgente conosce: non sono nel file, l'utente deve saperlo.
                var skipped = WinGetCommands.ExportSkippedCount(r.Output);
                if (skipped > 0) State.Log.Write($"  {skipped} installed packages are in no source and were left out.");
            }
            else
            {
                State.Log.Write($"Export FAILED (exit {r.ExitCode}).");
                foreach (var l in WinGetTable.OutputTail(r.Output)) State.Log.Write($"   {l}");
                failure = $"The package list could not be exported (exit {r.ExitCode}).\n\n" + Reason(r) +
                    "Try again, or save it to another folder. The log has winget's full output.";
            }
        }
        finally
        {
            Loading = false;
            State.End();
        }
        // Dopo lo stato occupato: sotto il dialogo la scheda non resta "al lavoro".
        if (failure is not null) State.Dialogs.Show(failure, "Export failed", MessageBoxButton.OK, MessageBoxImage.Error);
    }

    // Perche' winget ha fallito, per un dialogo: il motivo noto del codice, o le sue ultime righe.
    private static string Reason(ProcessResult r)
    {
        var why = ExitCodes.Hint(r.ExitCode) is { } hint ? $"{hint}." : string.Join("\n", WinGetTable.OutputTail(r.Output));
        return why.Length > 0 ? $"{why}\n\n" : "";
    }

    // L'import installa software senza altre domande: anteprima con tutto spuntato, No
    // predefinito, argomenti salvati nel file tolti salvo scelta.
    [RelayCommand(CanExecute = nameof(IsIdle))]
    public async Task ImportAsync()
    {
        if (State.IsWinGetBusy) return;
        var file = State.Dialogs.PickOpenFile("Import packages from a list", ListFilter);
        if (file is null) return;
        var list = PackageList.Load(file);
        // 0 come null: un export senza pacchetti winget lo rifiuterebbe dopo la conferma.
        if (list is null || list.Packages.Count == 0)
        {
            State.Dialogs.Show($"This file is not a winget package list, or it lists no packages.\n\n{file}\n\n" +
                "To make one, use Export... in the Installed tab.", "Cannot import",
                MessageBoxButton.OK, MessageBoxImage.Error);
            return;
        }
        var preview = new ImportPreviewViewModel(list);
        var n = list.StoredArguments;
        var storedNote = n == 0 ? "" : $"\n\n{n} package{(n == 1 ? " carries" : "s carry")} installer arguments saved in the file. " +
            "They are left out unless you tick the box below: winget would pass them to the installer.";
        var answer = State.Dialogs.Show($"Install the ticked packages from this list?\n{file}\n\n" +
            "Untick what you do not want. Packages already installed are skipped or upgraded; packages " +
            "no longer available in any source are ignored rather than failing the whole import." + storedNote,
            "Confirm import", MessageBoxButton.YesNo, MessageBoxImage.Warning, MessageBoxResult.No, preview, verbs: ("Import", "Cancel"));
        if (answer != MessageBoxResult.Yes)
        {
            State.Log.Write("Import canceled.");
            return;
        }
        var keep = preview.KeptIndices;
        if (keep.Count == 0)
        {
            State.Log.Write("Import canceled: no package was ticked.");
            return;
        }
        var dropStored = n > 0 && !preview.KeepStoredArguments;
        // Tutto spuntato e niente da togliere: il file com'e'. Altrimenti un file ridotto.
        var path = file;
        if (keep.Count < list.Packages.Count || dropStored)
        {
            path = list.WriteSubset(keep, preview.KeepStoredArguments);
            if (keep.Count < list.Packages.Count) State.Log.Write($"Importing {keep.Count} of the {list.Packages.Count} packages in {file}.");
            if (dropStored) State.Log.Write($"Installer arguments saved in {file} were left out.");
        }
        try { await RunImportAsync(path, keep.Count); }
        finally
        {
            // Il file ridotto serve solo a questo import; se resta, lo spazza TempFiles all'avvio.
            if (path != file) try { File.Delete(path); } catch (IOException) { } catch (UnauthorizedAccessException) { }
        }
    }

    // Una sola invocazione lunga: e' winget a scorrere la lista, non c'e' un esito per riga.
    private async Task RunImportAsync(string file, int count)
    {
        if (!State.TryBegin()) return;
        LoadingText = "Importing packages...";
        Loading = true;
        State.ProgressIndeterminate = true;
        State.Log.Write($"Importing {count} packages from {file} ...");
        string? failure = null;
        try
        {
            var r = await RunAsync(WinGetCommands.Import(file), "import");
            switch (ExitCodes.Classify(r.ExitCode))
            {
                case OperationStatus.Ok: State.Log.Write($"Import done ({(int)r.Elapsed.TotalSeconds}s)."); break;
                case OperationStatus.Warning: State.Log.Write($"Import finished with warnings (exit {r.ExitCode}): a reboot may be required, or a package was already installed."); break;
                default:
                    State.Log.Write($"Import FAILED (exit {r.ExitCode}).");
                    foreach (var l in WinGetTable.OutputTail(r.Output, 3)) State.Log.Write($"   {l}");
                    failure = $"Not every package was imported (exit {r.ExitCode}).\n\n" + Reason(r) +
                        "The log says what winget did with each package. Install the missing ones from the Install tab.";
                    break;
            }
            // Software installato: Updates si rilegge all'apertura, questo elenco subito.
            State.MarkUpdatesStale();
            await LoadCoreAsync(keepOutcome: false);
        }
        finally
        {
            Loading = false;
            State.End();
        }
        if (failure is not null) State.Dialogs.Show(failure, "Import failed", MessageBoxButton.OK, MessageBoxImage.Error);
    }

    // Il tick ogni 30 s dice che winget sta ancora lavorando.
    private async Task<ProcessResult> RunAsync(IReadOnlyList<string> arguments, string what)
    {
        try { return await State.Cli.RunAsync(arguments, t => State.Log.Write($"   ...{what} running for {(int)t.TotalSeconds}s")); }
        catch (Exception e) when (e is System.ComponentModel.Win32Exception or IOException or UnauthorizedAccessException)
        {
            return new ProcessResult(-1, e.Message, TimeSpan.Zero);
        }
    }

    protected override void Refresh()
    {
        base.Refresh();
        var total = Items.Count;
        var shown = Items.Count(Matches);
        var selected = Items.Count(i => i.Selected);
        var hidden = Items.Count(i => i.Selected && !Matches(i));
        CountText = total == 0 ? "" : shown != total ? $"{shown} of {total} installed" : $"{total} installed";
        // Senza righe il messaggio e' quello della lettura (LoadCoreAsync); con righe, solo il filtro.
        if (total > 0) EmptyText = shown == 0 ? $"No installed package matches '{FilterText.Trim()}'.\nClear the filter to see all {total}." : "";
        // Un selezionato nascosto dal filtro verrebbe disinstallato senza essere a schermo.
        InfoText = selected == 0 ? "" : hidden > 0 ? $"{selected} selected ({hidden} hidden by the filter)" : $"{selected} selected";
        ReloadCommand?.NotifyCanExecuteChanged();
        UninstallCommand?.NotifyCanExecuteChanged();
        ExportCommand?.NotifyCanExecuteChanged();
        ImportCommand?.NotifyCanExecuteChanged();
    }
}

// Anteprima dell'import nel dialogo di conferma: una riga spuntata per pacchetto, nell'ordine
// del file (il sottoinsieme si sceglie per posizione).
public sealed partial class ImportPreviewViewModel : ObservableObject
{
    private readonly PackageList list;

    public ImportPreviewViewModel(PackageList list)
    {
        this.list = list;
        Rows = [.. list.Packages.Select(p => new ImportRow(p))];
        // Seleziona tutto segue le spunte delle righe.
        foreach (var r in Rows) r.PropertyChanged += (_, _) => OnPropertyChanged(nameof(AllChecked));
    }

    public IReadOnlyList<ImportRow> Rows { get; }

    // Seleziona tutto nell'intestazione, come PackageListViewModel.AllChecked: true tutte, false
    // nessuna, null alcune; un clic su "alcune" le spunta tutte.
    public bool? AllChecked
    {
        get => Rows.All(r => r.Selected) ? true : Rows.Any(r => r.Selected) ? null : false;
        set { foreach (var r in Rows) r.Selected = value == true; }
    }

    public bool CanCheckAll => Rows.Count > 0;
    public bool HasStoredArguments => list.StoredArguments > 0;
    public string KeepStoredText => $"Keep the installer arguments saved for {list.StoredArguments} package{(list.StoredArguments == 1 ? "" : "s")} (--custom, --override)";

    // Spenta: si sceglie di riapplicarli, non di toglierli.
    public bool KeepStoredArguments { get; set; }

    public IReadOnlyList<int> KeptIndices => [.. Rows.Select((r, i) => (r, i)).Where(x => x.r.Selected).Select(x => x.i)];
}

public sealed partial class ImportRow(ImportPackage package) : ObservableObject
{
    [ObservableProperty] public partial bool Selected { get; set; } = true;
    public string Id => package.Id;
    public string Source => package.Source;
    public string Version => package.Version;
}
