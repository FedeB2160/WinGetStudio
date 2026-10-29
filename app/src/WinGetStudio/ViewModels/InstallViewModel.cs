using System.Windows;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using WinGetStudio.Core;

namespace WinGetStudio.ViewModels;

// Scheda Install (Tab.Install.ps1 della 1.x): ricerca nel catalogo mentre si scrive e
// installazione dei pacchetti scelti.
public sealed partial class InstallViewModel : PackageListViewModel
{
    private const string Hint = "Type a package name to search the winget catalog.";

    private string _searchText = "";
    private bool _includeStore;
    private InstallScope _scope;
    private CancellationTokenSource? _typeahead;

    public InstallViewModel(AppState state) : base(state)
    {
        _includeStore = state.Prefs.GetBool(Preferences.IncludeStore, false);
        _scope = Enum.TryParse<InstallScope>(state.Prefs.GetString(Preferences.InstallScope, "Auto"), out var s) ? s : InstallScope.Auto;
        Message = Hint;
        InfoText = "";
        Refresh();
    }

    protected override bool DetailsInstalled => false;

    // Pausa dopo l'ultimo tasto: una ricerca sull'indice locale ne impiega ~450 ms, quindi i
    // risultati arrivano sotto il secondo, senza un winget per lettera.
    internal TimeSpan TypeaheadDelay { get; set; } = TimeSpan.FromMilliseconds(350);

    // La ricerca mentre si scrive in corso (i test la aspettano).
    internal Task TypeaheadTask { get; private set; } = Task.CompletedTask;

    public string SearchText
    {
        get => _searchText;
        set
        {
            if (!SetProperty(ref _searchText, value)) return;
            _typeahead?.Cancel();
            if (value.Trim().Length >= 3)
            {
                _typeahead = new CancellationTokenSource();
                TypeaheadTask = TypeaheadAsync(_typeahead.Token);
            }
            else ShowMessage(Hint);
        }
    }

    // Anche il Microsoft Store: va in rete (~5 s), quindi solo con Invio o Search.
    public bool IncludeStore
    {
        get => _includeStore;
        set { if (SetProperty(ref _includeStore, value)) State.Prefs.Set(Preferences.IncludeStore, value); }
    }

    public string ScopeText => $"Scope: {_scope}";

    public string ScopeToolTip => _scope switch
    {
        InstallScope.User => "Install for the current user only (--scope user)",
        InstallScope.Machine => "Install for all users (--scope machine). Packages that only ship a per-user installer will fail",
        _ => "Let winget decide (no --scope flag), same as the Updates tab does",
    };

    [ObservableProperty] public partial string Message { get; private set; }
    [ObservableProperty] public partial string InfoText { get; private set; }

    public bool Searching => State.SearchesInFlight > 0;

    [RelayCommand(CanExecute = nameof(IsIdle))]
    private void CycleScope()
    {
        _scope = _scope switch { InstallScope.Auto => InstallScope.User, InstallScope.User => InstallScope.Machine, _ => InstallScope.Auto };
        State.Prefs.Set(Preferences.InstallScope, _scope.ToString());
        OnPropertyChanged(nameof(ScopeText));
        OnPropertyChanged(nameof(ScopeToolTip));
    }

    // Invio o Search: subito, con lo Store se spuntato.
    [RelayCommand(CanExecute = nameof(IsIdle))]
    public Task SearchNowAsync()
    {
        _typeahead?.Cancel();
        return SearchAsync(IncludeStore);
    }

    [RelayCommand(CanExecute = nameof(CanInstall))]
    public Task InstallAsync()
    {
        var rows = Items.Where(i => i.Selected).ToList();
        if (rows.Count > 0) return InstallRowsAsync(rows);
        State.Dialogs.Show("No packages selected.", image: MessageBoxImage.Information);
        return Task.CompletedTask;
    }

    // Doppio clic: quel pacchetto, senza passare dalle spunte.
    [RelayCommand(CanExecute = nameof(IsIdle))]
    public Task InstallOneAsync(PackageItem? item) => item is null || State.IsBusy ? Task.CompletedTask : InstallRowsAsync([item]);

    private bool CanInstall() => State.IsIdle && Items.Any(i => i.Selected);

    private async Task TypeaheadAsync(CancellationToken cancel)
    {
        try { await Task.Delay(TypeaheadDelay, cancel); }
        catch (TaskCanceledException) { return; }
        await SearchAsync(includeStore: false);   // mai lo Store mentre si scrive
    }

    private async Task SearchAsync(bool includeStore)
    {
        var query = SearchText.Trim();
        if (query.Length < 3)
        {
            ShowMessage("Type at least 3 characters.");
            return;
        }
        if (State.IsBusy) return;
        State.SearchesInFlight++;
        ReadResult<PackageRow> read;
        try { read = await State.Backend.SearchAsync(query, includeStore); }
        finally { State.SearchesInFlight--; }

        // Superato: l'utente ha continuato a scrivere. Partita un'installazione: sostituire le
        // righe farebbe sparire proprio quelle in corso, col loro esito.
        if (query != SearchText.Trim() || State.IsBusy) return;
        if (!read.Success)
        {
            // Solo a schermo: mentre si scrive ogni pausa aggiungerebbe una riga uguale al log.
            ShowMessage(AppState.ReadError($"search '{query}'", read));
            return;
        }
        Items.Clear();
        Fill(read.Rows, null);
        if (Items.Count > 0)
        {
            // Store giu' ma winget trova qualcosa: senza questa riga i risultati dello Store
            // mancherebbero senza un perche'.
            foreach (var l in read.Output.Split('\n').Where(l => l.Contains("msstore"))) State.Log.Write($"winget: {l.Trim()}");
            Message = "";
        }
        else
        {
            var said = WinGetTable.OutputTail(read.Output, 3);
            ShowMessage($"No package matches '{query}'." + (said.Count > 1 ? $" winget: {string.Join(' ', said)}" : ""));
        }
    }

    private void ShowMessage(string text)
    {
        Items.Clear();
        Message = text;
    }

    // I risultati restano col loro esito; Updates e Installed sono di prima e si rileggono alla
    // prossima apertura.
    private Task InstallRowsAsync(IReadOnlyList<PackageItem> items)
    {
        var scope = _scope;
        return State.RunQueueAsync(new QueueRequest(Core.QueueVerb.Install, [.. items.Select(i => i.Row)], r => WinGetCommands.Install(r, scope)), Items, () =>
        {
            State.MarkUpdatesStale();
            State.MarkInstalledStale();
            return Task.CompletedTask;
        });
    }

    protected override void Refresh()
    {
        base.Refresh();
        var total = Items.Count;
        var selected = Items.Count(i => i.Selected);
        InfoText = selected > 0 ? $"{selected} selected"
            : total > 0 ? $"{total} result{(total == 1 ? "" : "s")} - tick the ones to install, or double click a row"
            : "";
        OnPropertyChanged(nameof(Searching));
        InstallCommand?.NotifyCanExecuteChanged();
        InstallOneCommand?.NotifyCanExecuteChanged();
        SearchNowCommand?.NotifyCanExecuteChanged();
        CycleScopeCommand?.NotifyCanExecuteChanged();
    }
}
