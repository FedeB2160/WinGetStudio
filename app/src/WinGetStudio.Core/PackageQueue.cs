namespace WinGetStudio.Core;

// Parola dei messaggi di log ("Update complete: ...").
public enum QueueVerb { Update, Install, Uninstall, Pin, Unpin }

public sealed record PackageOutcome(OperationStatus Status, string Detail);

// Cosa fare e su quali righe. Retry failed e' la stessa richiesta con le sole righe fallite.
public sealed record QueueRequest(QueueVerb Verb, IReadOnlyList<PackageRow> Rows, Func<PackageRow, IReadOnlyList<string>> Arguments);

// Esito per Id: dopo la coda le liste si rileggono e le righe sono nuove, quindi l'esito si
// riporta per Id (issue #24). Un Id assente non e' partito (annullato).
public sealed record QueueResult(QueueRequest Request, IReadOnlyDictionary<string, PackageOutcome> Outcomes, bool Cancelled)
{
    public IReadOnlyList<string> FailedIds =>
        Outcomes.Where(kv => kv.Value.Status == OperationStatus.Error).Select(kv => kv.Key).ToList();

    public string Summary => FormatSummary(Request.Rows.Select(r => Outcomes.GetValueOrDefault(r.Id)?.Status));

    // "5 ok, 1 with warnings, 2 failed, 3 not run"; i conteggi a zero non si scrivono.
    public static string FormatSummary(IEnumerable<OperationStatus?> statuses)
    {
        var all = statuses.ToList();
        var parts = new (OperationStatus? Status, string Label)[]
            { (OperationStatus.Ok, "ok"), (OperationStatus.Warning, "with warnings"), (OperationStatus.Error, "failed"), (null, "not run") };
        return string.Join(", ", parts.Select(p => (n: all.Count(s => s == p.Status), p.Label)).Where(x => x.n > 0).Select(x => $"{x.n} {x.Label}"));
    }
}

// Esegue winget su ogni riga in SEQUENZA (Start-WinGetQueue della 1.x). Un errore su un
// pacchetto NON interrompe la coda. Il lock di WinGetCli tiene un solo winget alla volta.
public sealed class PackageQueue(WinGetCli cli)
{
    // log: righe per il log della finestra. rowChanged: esito null = in corso, poi l'esito.
    // cancel: si controlla PRIMA di partire con un pacchetto, mai a meta'.
    public async Task<QueueResult> RunAsync(QueueRequest request, Action<string>? log = null,
        Action<PackageRow, PackageOutcome?>? rowChanged = null, CancellationToken cancel = default)
    {
        var verb = request.Verb.ToString();
        var outcomes = new Dictionary<string, PackageOutcome>();
        var done = 0;
        log?.Invoke($"Starting {verb.ToLowerInvariant()} of {request.Rows.Count} packages...");

        foreach (var row in request.Rows)
        {
            if (cancel.IsCancellationRequested) break;
            rowChanged?.Invoke(row, null);
            log?.Invoke($"-> {row.Name} [{row.Id}]");
            PackageOutcome outcome;
            try
            {
                var r = await cli.RunAsync(request.Arguments(row), t => log?.Invoke($"   ...{row.Name} running for {(int)t.TotalSeconds}s"));
                outcome = new PackageOutcome(ExitCodes.Classify(r.ExitCode), $"exit {r.ExitCode}");
                switch (outcome.Status)
                {
                    case OperationStatus.Ok: log?.Invoke($"   OK: {row.Name} ({(int)r.Elapsed.TotalSeconds}s)"); break;
                    case OperationStatus.Warning: log?.Invoke($"   WARNING (exit {r.ExitCode}): {row.Name}"); break;
                    default:
                        log?.Invoke($"   ERROR (exit {r.ExitCode}): {row.Name}");
                        // Le ultime DUE righe: winget stampa il percorso del log dell'installer
                        // DOPO il messaggio d'errore.
                        foreach (var l in WinGetTable.OutputTail(r.Output)) log?.Invoke($"      {l}");
                        break;
                }
            }
            catch (Exception e) when (e is ArgumentException or System.ComponentModel.Win32Exception or IOException or UnauthorizedAccessException)
            {
                outcome = new PackageOutcome(OperationStatus.Error, e.Message);
                log?.Invoke($"   EXCEPTION: {e.Message}");
            }
            outcomes[row.Id] = outcome;
            done++;
            rowChanged?.Invoke(row, outcome);
        }

        var result = new QueueResult(request, outcomes, done < request.Rows.Count);
        log?.Invoke(result.Cancelled
            ? $"{verb} cancelled after {done} of {request.Rows.Count} packages; the rest were left untouched: {result.Summary}."
            : $"{verb} complete: {result.Summary}.");
        return result;
    }
}
