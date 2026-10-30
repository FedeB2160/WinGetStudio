using System.Collections;
using System.Collections.ObjectModel;
using System.Collections.Specialized;
using System.ComponentModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using WinGetStudio.Core;

namespace WinGetStudio.ViewModels;

// Cio' che le tre schede hanno in comune: righe, stato occupato, Retry failed, pin e dettagli
// dal menu contestuale, esito riportato per Id dopo una ricarica.
public abstract partial class PackageListViewModel : ObservableObject
{
    protected PackageListViewModel(AppState state)
    {
        State = state;
        Items.CollectionChanged += OnItemsChanged;
        state.PropertyChanged += (_, e) =>
        {
            if (e.PropertyName is nameof(AppState.IsBusy) or nameof(AppState.QueueVerb) or nameof(AppState.Cancelling) or nameof(AppState.SearchesInFlight))
                Refresh();
        };
        state.PinsChanged += () => { foreach (var i in Items) i.Pinned = state.Pins.IsPinned(i.Id); };
    }

    public AppState State { get; }
    public ObservableCollection<PackageItem> Items { get; } = [];

    [ObservableProperty, NotifyPropertyChangedFor(nameof(RetryText), nameof(RetryVisible))]
    public partial int RetryCount { get; private set; }

    public string RetryText => $"Retry failed ({RetryCount})";
    public bool RetryVisible => RetryCount > 0;

    // Retry as administrator (ADR 0024): mentre il suo batch gira il pulsante diventa Cancel, che
    // puo' anche smettere di aspettare l'UAC. Solo nella scheda che l'ha avviato.
    private bool _elevating;

    [ObservableProperty, NotifyPropertyChangedFor(nameof(RetryAdminText), nameof(RetryAdminVisible))]
    public partial int RetryAdminCount { get; private set; }

    public string RetryAdminText => _elevating ? State.Cancelling ? "Cancelling..." : "Cancel" : $"Retry as administrator ({RetryAdminCount})";
    public bool RetryAdminVisible => _elevating || RetryAdminCount > 0;

    [RelayCommand(CanExecute = nameof(CanRetryAdmin), AllowConcurrentExecutions = true)]
    public async Task RetryAdminAsync()
    {
        if (_elevating)
        {
            State.CancelQueue();
            return;
        }
        _elevating = true;
        try { await State.RetryElevatedAsync(Items); }
        finally
        {
            _elevating = false;
            Refresh();
        }
    }

    private bool CanRetryAdmin() => _elevating ? !State.Cancelling : State.IsIdle;
    public bool HasItems => Items.Count > 0;
    public bool IsEmpty => Items.Count == 0;

    // Dettagli: list --details per cio' che e' installato, solo il catalogo per una ricerca.
    protected abstract bool DetailsInstalled { get; }

    [RelayCommand(CanExecute = nameof(IsIdle))]
    public Task RetryAsync() => State.RetryAsync(Items);

    [RelayCommand(CanExecute = nameof(IsIdle))]
    private Task Pin(IList? highlighted) => PinAsync([.. highlighted?.OfType<PackageItem>() ?? []]);

    [RelayCommand(CanExecute = nameof(IsIdle))]
    private Task Unpin(IList? highlighted) => UnpinAsync([.. highlighted?.OfType<PackageItem>() ?? []]);

    [RelayCommand(CanExecute = nameof(IsIdle))]
    public Task DetailsAsync(PackageItem? item) => State.ShowDetailsAsync(item, DetailsInstalled);

    public Task PinAsync(IReadOnlyList<PackageItem> highlighted) => State.SetPinAsync(highlighted, Items, true);
    public Task UnpinAsync(IReadOnlyList<PackageItem> highlighted) => State.SetPinAsync(highlighted, Items, false);

    protected bool IsIdle() => State.IsIdle;

    // Esiti per Id, da riportare sulle righe nuove della ricarica (issue #24).
    protected Dictionary<string, (RowStatus Status, string Detail)> SnapshotOutcomes() =>
        Items.Where(i => i.Status is not (RowStatus.None or RowStatus.Running))
            .GroupBy(i => i.Id).ToDictionary(g => g.Key, g => (g.First().Status, g.First().StatusDetail));

    // Righe nuove con pin ed esiti riportati.
    protected void Fill(IEnumerable<PackageRow> rows, Dictionary<string, (RowStatus Status, string Detail)>? outcomes)
    {
        foreach (var r in rows)
        {
            var item = new PackageItem(r) { Pinned = State.Pins.IsPinned(r.Id) };
            if (outcomes?.TryGetValue(r.Id, out var o) == true) (item.Status, item.StatusDetail) = o;
            Items.Add(item);
        }
    }

    // Le righe che "seleziona tutto" tocca: tutte, salvo dove la scheda dice altrimenti.
    protected virtual IEnumerable<PackageItem> Selectable => Items;

    // La spunta nell'intestazione della griglia: true tutte, false nessuna, null alcune. Un clic
    // su "alcune" le spunta tutte.
    public bool? AllChecked
    {
        get => Selectable.Any() && Selectable.All(i => i.Selected) ? true : Selectable.Any(i => i.Selected) ? null : false;
        set
        {
            var on = value == true;
            foreach (var i in Selectable.ToList()) i.Selected = on;
        }
    }

    public bool CanCheckAll => State.IsIdle && Selectable.Any();

    // Il numero nel badge della linguetta, o "" (nessun badge).
    public virtual string Badge => "";

    // Contatori, etichette e comandi dipendono da righe, spunte e stato occupato.
    protected virtual void Refresh()
    {
        OnPropertyChanged(nameof(Badge));
        OnPropertyChanged(nameof(AllChecked));
        OnPropertyChanged(nameof(CanCheckAll));
        RetryCount = State.RetryItems(Items).Count;
        RetryAdminCount = State.ElevateItems(Items).Count;
        OnPropertyChanged(nameof(RetryAdminText));
        OnPropertyChanged(nameof(RetryAdminVisible));
        OnPropertyChanged(nameof(HasItems));
        OnPropertyChanged(nameof(IsEmpty));
        RetryCommand.NotifyCanExecuteChanged();
        RetryAdminCommand.NotifyCanExecuteChanged();
        PinCommand.NotifyCanExecuteChanged();
        UnpinCommand.NotifyCanExecuteChanged();
        DetailsCommand.NotifyCanExecuteChanged();
    }

    private void OnItemsChanged(object? sender, NotifyCollectionChangedEventArgs e)
    {
        foreach (var i in e.NewItems?.OfType<PackageItem>() ?? []) i.PropertyChanged += OnItemChanged;
        foreach (var i in e.OldItems?.OfType<PackageItem>() ?? []) i.PropertyChanged -= OnItemChanged;
        Refresh();
    }

    private void OnItemChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName is nameof(PackageItem.Selected) or nameof(PackageItem.Pinned) or nameof(PackageItem.Status)) Refresh();
    }
}
