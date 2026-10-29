using System.Windows;
using CommunityToolkit.Mvvm.ComponentModel;
using WinGetStudio.Core;

namespace WinGetStudio.ViewModels;

// L'ultima coda, per Retry failed: la stessa richiesta e lo stesso passo finale.
public sealed record LastQueue(QueueResult Result, Func<Task>? Then);

// Stato condiviso da tutte le schede (App.Ui.ps1 e App.Jobs.ps1 della 1.x): stato occupato
// globale, barra di avanzamento, coda, pin, log, dialoghi.
public sealed partial class AppState : ObservableObject
{
    private CancellationTokenSource? _cancel;

    public AppState(WinGetCli cli, LogViewModel log, IDialogService dialogs, Preferences prefs)
    {
        Cli = cli;
        Queue = new PackageQueue(cli);
        Log = log;
        Dialogs = dialogs;
        Prefs = prefs;
        ProgressMaximum = 100;
    }

    public WinGetCli Cli { get; }
    public IWinGetBackend Backend => Cli;
    public PackageQueue Queue { get; }
    public LogViewModel Log { get; }
    public IDialogService Dialogs { get; }
    public Preferences Prefs { get; }
    public PinState Pins { get; } = new();
    public LastQueue? Last { get; private set; }

    // winget non regge due processi insieme (ADR 0003): un'operazione in corso spegne i comandi
    // di TUTTE le schede.
    [ObservableProperty, NotifyPropertyChangedFor(nameof(IsIdle), nameof(IsWinGetBusy))]
    public partial bool IsBusy { get; private set; }

    public bool IsIdle => !IsBusy;

    // Quale coda gira, o null: solo chi l'ha avviata offre Cancel.
    [ObservableProperty] public partial QueueVerb? QueueVerb { get; private set; }
    [ObservableProperty] public partial bool Cancelling { get; private set; }

    // Le ricerche NON alzano lo stato occupato (la digitazione resta fluida), ma sono un winget:
    // chi sta per lanciarne un altro chiede IsWinGetBusy, non IsBusy.
    [ObservableProperty, NotifyPropertyChangedFor(nameof(IsWinGetBusy))]
    public partial int SearchesInFlight { get; set; }

    public bool IsWinGetBusy => IsBusy || SearchesInFlight > 0;

    [ObservableProperty] public partial double ProgressValue { get; set; }
    [ObservableProperty] public partial double ProgressMaximum { get; set; }
    [ObservableProperty] public partial bool ProgressIndeterminate { get; set; }

    // Le liste sono una fotografia della macchina: un'azione da un'altra scheda le rende vecchie.
    public event Action? PinsChanged, UpdatesStale, InstalledStale;
    public void MarkUpdatesStale() => UpdatesStale?.Invoke();
    public void MarkInstalledStale() => InstalledStale?.Invoke();

    // L'ultima operazione partita da un evento della UI (cambio di scheda, una spunta): i test
    // la aspettano qui.
    public Task LastFired { get; private set; } = Task.CompletedTask;

    public void Fire(Func<Task> operation) => LastFired = RunLogged(operation);

    private async Task RunLogged(Func<Task> operation)
    {
        try { await operation(); }
        catch (Exception e) { Log.Write($"ERROR: {e.Message}"); }
    }

    public bool TryBegin()
    {
        if (IsWinGetBusy) return false;
        IsBusy = true;
        return true;
    }

    // Il verbo si azzera PRIMA dello stato occupato: chi reagisce vede lo stato finale.
    public void End()
    {
        QueueVerb = null;
        Cancelling = false;
        ProgressIndeterminate = false;
        IsBusy = false;
    }

    // Messaggio per una lettura fallita, su UNA riga: exit e le ultime due righe di winget.
    public static string ReadError<T>(string command, ReadResult<T> read)
    {
        var detail = string.Join(' ', WinGetTable.OutputTail(read.Output));
        return $"winget {command} failed (exit {read.ExitCode})" + (detail.Length > 0 ? $": {detail}" : "");
    }

    // "  - Nome" per i primi 12, poi quanti altri: per le conferme.
    public static string NameList(IEnumerable<string> names)
    {
        var all = names.ToList();
        return string.Join("\n", all.Take(12).Select(n => $"  - {n}")) + (all.Count > 12 ? $"\n  ... and {all.Count - 12} more" : "");
    }

    // UNICO passaggio di update, install, uninstall e pin: prende lo stato occupato, scrive
    // l'esito nelle righe di items, e tiene lo stato occupato anche durante then (la ricarica
    // della lista, la rilettura dei pin): un winget lanciato nel mezzo sarebbe il secondo.
    // null se un altro winget e' in corso.
    public async Task<QueueResult?> RunQueueAsync(QueueRequest request, IEnumerable<PackageItem> items, Func<Task>? then)
    {
        if (IsWinGetBusy)
        {
            Log.Write("Another winget operation is still running: try again in a moment.");
            return null;
        }
        // Il verbo PRIMA dello stato occupato: le schede lo leggono per decidere se e' la loro.
        QueueVerb = request.Verb;
        IsBusy = true;
        // Nuovo a ogni coda: un annullamento fra due code non si trascina sulla successiva.
        _cancel = new CancellationTokenSource();
        var rows = new Dictionary<PackageRow, PackageItem>(ReferenceEqualityComparer.Instance);
        foreach (var i in items) rows[i.Row] = i;
        foreach (var r in request.Rows)
            if (rows.TryGetValue(r, out var i)) { i.Status = RowStatus.None; i.StatusDetail = ""; }
        ProgressIndeterminate = false;
        ProgressValue = 0;
        ProgressMaximum = request.Rows.Count;
        try
        {
            var result = await Queue.RunAsync(request, Log.Write, (row, outcome) =>
            {
                if (rows.TryGetValue(row, out var item)) item.SetOutcome(outcome);
                if (outcome is not null) ProgressValue++;
            }, _cancel.Token);
            Last = new LastQueue(result, then);
            QueueVerb = null;
            Cancelling = false;
            if (then is not null) await then();
            return result;
        }
        finally { End(); }
    }

    // Finisce il pacchetto in corso e non parte col prossimo: un installer interrotto a meta'
    // lascia la macchina in uno stato che nessuno sa descrivere.
    public void CancelQueue()
    {
        if (QueueVerb is null || Cancelling) return;
        _cancel?.Cancel();
        Cancelling = true;
        Log.Write("Cancelling: the package in progress will finish, then the queue stops.");
    }

    // Righe da ripetere in un elenco: fallite nell'ultima coda, per Id (dopo la ricarica le
    // righe sono nuove), e con l'esito ancora Error.
    public IReadOnlyList<PackageItem> RetryItems(IEnumerable<PackageItem> items)
    {
        if (Last is null) return [];
        var failed = Last.Result.FailedIds.ToHashSet(StringComparer.OrdinalIgnoreCase);
        return items.Where(i => i.Status == RowStatus.Error && failed.Contains(i.Id)).ToList();
    }

    // Conferma con No predefinito: puo' essere una disinstallazione. Il blocco "lista vecchia"
    // non vale qui: si ripetono solo righe fallite, che non hanno cambiato nulla.
    public async Task RetryAsync(IReadOnlyList<PackageItem> items)
    {
        var retry = RetryItems(items);
        if (retry.Count == 0 || Last is not { } last) return;
        var verb = last.Result.Request.Verb.ToString().ToLowerInvariant();
        var answer = Dialogs.Show($"Retry the {verb} of {retry.Count} package{(retry.Count == 1 ? "" : "s")} that failed?\n\n" + NameList(retry.Select(r => r.Name)),
            "Retry failed", MessageBoxButton.YesNo, MessageBoxImage.Question, MessageBoxResult.No);
        if (answer != MessageBoxResult.Yes) return;
        await RunQueueAsync(last.Result.Request with { Rows = [.. retry.Select(r => r.Row)] }, items, last.Then);
    }

    // La lista nuova se la lettura e' riuscita, altrimenti l'ultima buona e l'errore nel log.
    public void ApplyPins(ReadResult<string> read)
    {
        if (!read.Success) Log.Write(ReadError("pin list", read));
        Pins.Apply(read);
        PinsChanged?.Invoke();
    }

    // Pin o unpin delle righe EVIDENZIATE (la spunta di una pinnata e' spenta). Solo quelle che
    // cambiano stato; poi si rileggono i pin da winget, che e' la fonte di verita' (ADR 0007),
    // dentro lo stato occupato.
    public async Task SetPinAsync(IReadOnlyList<PackageItem> highlighted, IReadOnlyList<PackageItem> items, bool pin)
    {
        if (highlighted.Count == 0) return;
        var todo = Pins.Changing(highlighted.Select(i => i.Row), pin);
        if (todo.Count == 0)
        {
            Log.Write(pin ? "Already pinned." : "Not pinned.");
            return;
        }
        await RunQueueAsync(new QueueRequest(pin ? Core.QueueVerb.Pin : Core.QueueVerb.Unpin, todo, pin ? WinGetCommands.PinAdd : WinGetCommands.PinRemove),
            items, async () => ApplyPins(await Backend.GetPinsAsync()));
    }

    // Dettagli come testo di winget (ADR 0021), letti dietro lo stato occupato: e' un winget
    // come gli altri.
    public async Task ShowDetailsAsync(PackageItem? item, bool installed)
    {
        if (item is null || !TryBegin()) return;
        ProgressIndeterminate = true;
        Log.Write($"Reading the details of {item.Name} [{item.Id}]...");
        string text;
        try { text = await Backend.GetDetailsAsync(item.Id, item.Source, installed); }
        catch (ArgumentException e) { text = e.Message; }
        finally { End(); }
        Dialogs.Show(text.Length > 0 ? text : "winget returned no details for this package.", $"{item.Name} - details", links: true);
    }
}
