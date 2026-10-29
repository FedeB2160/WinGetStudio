using System.Windows;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using WinGetStudio.Core;

namespace WinGetStudio.ViewModels;

// Scheda Updates (Tab.Updates.ps1 della 1.x): aggiornamenti disponibili, spunte, coda.
public sealed partial class UpdatesViewModel : PackageListViewModel
{
    private bool _includeUnknown;

    public UpdatesViewModel(AppState state) : base(state)
    {
        _includeUnknown = state.Prefs.GetBool(Preferences.IncludeUnknown, false);
        EmptyText = AvailableText = SelectedText = "";
        ToggleAllText = "Select all";
        UpdateButtonText = "Update";
        state.UpdatesStale += () => { Stale = true; Refresh(); };
        UpdateCommand = new AsyncRelayCommand(UpdateAsync, () => UpdateEnabled, AsyncRelayCommandOptions.AllowConcurrentExecutions);
        Refresh();
    }

    protected override bool DetailsInstalled => true;

    // L'elenco e' una fotografia della macchina: dopo un'azione da un'altra scheda le versioni a
    // schermo non valgono piu', e ripremere Update rilancerebbe winget su pacchetti gia'
    // aggiornati. Update si spegne finche' non si rilegge; riaprire la scheda rilegge.
    public bool Stale { get; private set; }

    // --include-unknown, salvata e subito applicata: una spunta che cambia COSA c'e' nell'elenco
    // senza cambiare l'elenco costringe a premere Check per capire cosa ha fatto.
    public bool IncludeUnknown
    {
        get => _includeUnknown;
        set
        {
            if (!SetProperty(ref _includeUnknown, value)) return;
            State.Prefs.Set(Preferences.IncludeUnknown, value);
            State.Fire(() => LoadAsync());
        }
    }

    [ObservableProperty] public partial bool Loading { get; private set; }
    [ObservableProperty] public partial string EmptyText { get; private set; }
    [ObservableProperty] public partial string AvailableText { get; private set; }
    [ObservableProperty] public partial string SelectedText { get; private set; }
    [ObservableProperty] public partial string ToggleAllText { get; private set; }
    [ObservableProperty] public partial string UpdateButtonText { get; private set; }
    [ObservableProperty] public partial string? UpdateButtonToolTip { get; private set; }

    // Update a riposo, Cancel mentre gira LA NOSTRA coda.
    public IAsyncRelayCommand UpdateCommand { get; }

    private bool OurQueue => State.IsBusy && State.QueueVerb == Core.QueueVerb.Update;
    private IEnumerable<PackageItem> Selectable => Items.Where(i => !i.Pinned);
    private bool AllSelected => Selectable.Any() && Selectable.All(i => i.Selected);
    private bool UpdateEnabled => OurQueue ? !State.Cancelling : State.IsIdle && !Stale && Items.Any(i => i.Selected);

    [RelayCommand(CanExecute = nameof(IsIdle))]
    private Task Check() => LoadAsync();

    // I pinnati restano fuori: spuntarli sarebbe una promessa che la coda non puo' mantenere.
    [RelayCommand(CanExecute = nameof(CanToggleAll))]
    private void ToggleAll()
    {
        var value = !AllSelected;
        foreach (var i in Selectable) i.Selected = value;
    }

    private bool CanToggleAll() => State.IsIdle && Items.Count > 0;

    public async Task LoadAsync(bool keepOutcome = false)
    {
        // Non si scansiona sopra un altro winget, ricerche comprese.
        if (!State.TryBegin()) return;
        try { await LoadCoreAsync(keepOutcome); }
        finally { State.End(); }
    }

    // Dentro uno stato occupato gia' preso (la ricarica a fine coda). keepOutcome: l'esito delle
    // righe vecchie torna sulle nuove, per Id.
    private async Task LoadCoreAsync(bool keepOutcome)
    {
        var outcomes = keepOutcome ? SnapshotOutcomes() : null;
        // La lettura che si sta per fare E' la nuova fotografia.
        Stale = false;
        State.Log.Write("Searching for updates...");
        Items.Clear();
        EmptyText = "";
        Loading = true;
        State.ProgressIndeterminate = true;
        // I pin nella stessa operazione, dopo: due winget insieme fanno fallire uno dei due.
        var read = await State.Backend.GetUpgradesAsync(IncludeUnknown);
        var pins = await State.Backend.GetPinsAsync();
        Loading = false;
        State.ProgressIndeterminate = false;
        if (read.Success) Fill(read.Rows, outcomes);
        if (Items.Count == 0)
        {
            // Mai "nessun aggiornamento" quando winget non ha risposto.
            EmptyText = read.Success ? "No updates available." : AppState.ReadError("upgrade", read);
            State.Log.Write(EmptyText);
        }
        else State.Log.Write($"Found {Items.Count} updates.");
        State.ApplyPins(pins);
        Refresh();
    }

    // Il pulsante: Update, o Cancel se la coda in corso e' questa.
    public Task UpdateAsync()
    {
        if (OurQueue)
        {
            State.CancelQueue();
            return Task.CompletedTask;
        }
        return UpdateSelectedAsync();
    }

    private async Task UpdateSelectedAsync()
    {
        var selected = Items.Where(i => i.Selected).ToList();
        // Si escludono QUI e non solo con la spunta spenta: una riga puo' essere stata spuntata
        // prima che il pin arrivasse.
        var rows = State.Pins.ExcludePinned(selected.Select(i => i.Row), out var skipped);
        if (skipped is not null)
        {
            foreach (var i in selected.Where(i => State.Pins.IsPinned(i.Id))) i.Selected = false;
            State.Log.Write(skipped);
        }
        if (rows.Count == 0)
        {
            State.Dialogs.Show("No items selected.", image: MessageBoxImage.Information);
            return;
        }
        // Le versioni a schermo sono vecchie: la lista si rilegge subito, con l'esito per Id. Le
        // riuscite spariscono, le fallite restano e si possono ripetere.
        await State.RunQueueAsync(new QueueRequest(Core.QueueVerb.Update, rows, WinGetCommands.Upgrade), Items, () =>
        {
            State.MarkInstalledStale();
            return LoadCoreAsync(keepOutcome: true);
        });
    }

    protected override void Refresh()
    {
        base.Refresh();
        var total = Items.Count;
        var selected = Items.Count(i => i.Selected);
        AvailableText = total switch { 0 => "", 1 => "1 update available", _ => $"{total} updates available" };
        // A lista vecchia il contatore cede il posto al motivo per cui Update e' spento.
        SelectedText = Stale ? "list out of date - press Check" : selected > 0 ? $"{selected} selected" : "";
        ToggleAllText = AllSelected ? "Deselect all" : "Select all";
        UpdateButtonText = OurQueue ? State.Cancelling ? "Cancelling..." : "Cancel" : "Update";
        UpdateButtonToolTip = OurQueue ? "Finish the package in progress, then stop without starting the others" : null;
        UpdateCommand?.NotifyCanExecuteChanged();
        CheckCommand.NotifyCanExecuteChanged();
        ToggleAllCommand.NotifyCanExecuteChanged();
    }
}
