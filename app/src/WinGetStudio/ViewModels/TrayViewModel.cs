using System.ComponentModel;
using CommunityToolkit.Mvvm.ComponentModel;

namespace WinGetStudio.ViewModels;

// Il pallino sull'icona, in ordine di priorita' (ADR 0030).
public enum TrayDot { Idle, Updates, Errors, Busy }

// Icona nell'area di notifica (ADR 0030): pallino e tooltip dallo stato, notifica degli
// aggiornamenti nuovi a finestra non attiva, controllo periodico sotto il lock di winget.
public sealed partial class TrayViewModel : ObservableObject
{
    private readonly AppState _state;
    private readonly UpdatesViewModel _updates;
    // Gli aggiornamenti gia' visti, come "Id versione": la stessa lista non si annuncia due volte.
    private HashSet<string> _seen = [];
    private bool _due, _manual;

    public TrayViewModel(AppState state, UpdatesViewModel updates)
    {
        _state = state;
        _updates = updates;
        ToolTip = "WinGet Studio";
        state.PropertyChanged += OnStateChanged;
        updates.Items.CollectionChanged += (_, _) => Refresh();
        updates.Scanned += OnScanned;
    }

    [ObservableProperty] public partial TrayDot Dot { get; private set; }
    [ObservableProperty] public partial string ToolTip { get; private set; }

    // Una finestra dell'app in primo piano: l'utente vede gia' la lista. La imposta la vista.
    public bool WindowActive { get; set; }

    // Titolo e testo del fumetto.
    public event Action<string, string>? Notify;

    // Il timer del controllo periodico. Sopra un altro winget non parte (ADR 0003): resta dovuto e
    // parte appena il lock si libera, invece di saltare un intervallo intero.
    public Task BackgroundCheckAsync()
    {
        if (_state.IsWinGetBusy)
        {
            _due = true;
            return Task.CompletedTask;
        }
        _due = false;
        // Gli esiti restano: una riga fallita resta da ripetere.
        return _updates.LoadAsync(keepOutcome: true);
    }

    // Check for updates dal menu: l'esito si dice sempre.
    public async Task CheckNowAsync()
    {
        if (_state.IsWinGetBusy)
        {
            Notify?.Invoke("Another winget operation is still running", "Try again in a moment.");
            return;
        }
        _manual = true;
        try { await _updates.LoadAsync(keepOutcome: true); }
        finally { _manual = false; }
    }

    private void OnStateChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (e.PropertyName is nameof(AppState.IsBusy)) Refresh();
        if (e.PropertyName is nameof(AppState.IsWinGetBusy) && _due && !_state.IsWinGetBusy) _state.Fire(BackgroundCheckAsync);
    }

    private void OnScanned()
    {
        var items = _updates.Items;
        var now = items.Select(i => $"{i.Id} {i.Row.Available}").ToHashSet(StringComparer.OrdinalIgnoreCase);
        var fresh = !now.IsSubsetOf(_seen);
        _seen = now;
        // Dal menu si risponde sempre: chi ha chiesto guarda l'icona, non la finestra.
        if (!_manual && (WindowActive || !fresh)) return;
        if (items.Count == 0) Notify?.Invoke(_updates.EmptyText, "");
        else Notify?.Invoke($"{items.Count} update{(items.Count == 1 ? "" : "s")} available",
            string.Join(", ", items.Take(5).Select(i => i.Name)) + (items.Count > 5 ? $" and {items.Count - 5} more" : ""));
    }

    private void Refresh()
    {
        var failed = _state.Last?.Result.FailedIds.Count ?? 0;
        Dot = _state.IsBusy ? TrayDot.Busy : failed > 0 ? TrayDot.Errors : _updates.Items.Count > 0 ? TrayDot.Updates : TrayDot.Idle;
        ToolTip = "WinGet Studio" + Dot switch
        {
            TrayDot.Busy => " - working",
            TrayDot.Errors => $" - {failed} failed in the last {_state.Last!.Result.Request.Verb.ToString().ToLowerInvariant()}",
            TrayDot.Updates => $" - {_updates.Items.Count} update{(_updates.Items.Count == 1 ? "" : "s")} available",
            _ => "",
        };
    }
}
