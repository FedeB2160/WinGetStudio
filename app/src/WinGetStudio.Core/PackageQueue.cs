namespace WinGetStudio.Core;

// Parola dei messaggi di log ("Update complete: ...").
public enum QueueVerb { Update, Install, Uninstall, Pin, Unpin }

// ExitCode: quello di winget, null per un'eccezione. Dice se l'elevazione puo' aiutare.
public sealed record PackageOutcome(OperationStatus Status, string Detail, int? ExitCode = null);

// Cosa fare e su quali righe. Retry failed e' la stessa richiesta con le sole righe fallite.
public sealed record QueueRequest(QueueVerb Verb, IReadOnlyList<PackageRow> Rows, Func<PackageRow, IReadOnlyList<string>> Arguments);

// Esito per Id: dopo la coda le liste si rileggono e le righe sono nuove, quindi l'esito si
// riporta per Id (issue #24). Un Id assente non e' partito (annullato).
public sealed record QueueResult(QueueRequest Request, IReadOnlyDictionary<string, PackageOutcome> Outcomes, bool Cancelled)
{
    public IReadOnlyList<string> FailedIds =>
        Outcomes.Where(kv => kv.Value.Status == OperationStatus.Error).Select(kv => kv.Key).ToList();

    // Le fallite che Retry as administrator puo' risolvere (ADR 0024).
    public IReadOnlyList<string> ElevatableIds =>
        Outcomes.Where(kv => kv.Value.Status == OperationStatus.Error && ExitCodes.ElevationCanFix(kv.Value.ExitCode)).Select(kv => kv.Key).ToList();

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
    // UAC rifiutato, o Cancel mentre l'UAC aspettava: un esito suo, ripetibile (ADR 0024).
    public const string Declined = "Cancelled at the administrator prompt";
    private const int ErrorCancelled = 1223;

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
                var args = request.Arguments(row);
                Action<TimeSpan> tick = t => log?.Invoke($"   ...{row.Name} running for {(int)t.TotalSeconds}s");
                var r = await cli.RunAsync(args, tick);
                // Da amministratore winget rifiuta i pacchetti per utente: la stessa riga, stesso
                // account, senza elevazione (ADR 0018). Mai come l'utente della sessione se e' un
                // altro: i pacchetti per utente in lista sono dell'account elevato.
                if (r.ExitCode == ExitCodes.AdminContextProhibited && cli.Elevation.IsElevated)
                {
                    if (cli.Elevation.OtherAccount)
                    {
                        var me = cli.Elevation.Account;
                        log?.Invoke($"   winget refuses this as administrator, and the package belongs to {me}, which is not the signed-in user: sign in as {me} to {verb.ToLowerInvariant()} it.");
                    }
                    else
                    {
                        log?.Invoke("   winget refuses this as administrator: retrying without elevation...");
                        r = await cli.RunUnelevatedAsync(args, tick);
                    }
                }
                outcome = Report(row, r, log);
            }
            catch (Exception e) when (e is ArgumentException or System.ComponentModel.Win32Exception or IOException or UnauthorizedAccessException
                or InvalidOperationException or System.Runtime.InteropServices.COMException)
            {
                outcome = new PackageOutcome(OperationStatus.Error, e.Message);
                log?.Invoke($"   EXCEPTION: {e.Message}");
            }
            outcomes[row.Id] = outcome;
            done++;
            rowChanged?.Invoke(row, outcome);
        }

        return Finish(request, outcomes, done, log);
    }

    // Retry as administrator (ADR 0024): le stesse righe di comando in UN solo runas. Il primo
    // rowChanged in corso arriva quando l'UAC ha risposto si'.
    public async Task<QueueResult> RunElevatedAsync(QueueRequest request, Action<string>? log = null,
        Action<PackageRow, PackageOutcome?>? rowChanged = null, CancellationToken cancel = default)
    {
        var verb = request.Verb.ToString();
        var outcomes = new Dictionary<string, PackageOutcome>();
        var rows = request.Rows;
        log?.Invoke($"Starting {verb.ToLowerInvariant()} of {rows.Count} packages as administrator: approve the Windows prompt to continue...");
        try
        {
            var run = await cli.RunElevatedAsync([.. rows.Select(request.Arguments)], (i, r) =>
            {
                if (r is null)
                {
                    log?.Invoke($"-> {rows[i].Name} [{rows[i].Id}]");
                    rowChanged?.Invoke(rows[i], null);
                    return;
                }
                var outcome = Report(rows[i], r, log);
                outcomes[rows[i].Id] = outcome;
                rowChanged?.Invoke(rows[i], outcome);
            }, cancel);
            if (!run.Approved)
            {
                log?.Invoke($"{Declined}: nothing was run.");
                foreach (var row in rows)
                {
                    var outcome = new PackageOutcome(OperationStatus.Error, Declined, ErrorCancelled);
                    outcomes[row.Id] = outcome;
                    rowChanged?.Invoke(row, outcome);
                }
                return new QueueResult(request, outcomes, false);
            }
        }
        catch (Exception e) when (e is ArgumentException or System.ComponentModel.Win32Exception or IOException or UnauthorizedAccessException or InvalidOperationException)
        {
            // Il batch non e' partito: l'errore vale per tutte le righe.
            log?.Invoke($"   EXCEPTION: {e.Message}");
            foreach (var row in rows.Where(r => !outcomes.ContainsKey(r.Id)))
            {
                var outcome = new PackageOutcome(OperationStatus.Error, e.Message);
                outcomes[row.Id] = outcome;
                rowChanged?.Invoke(row, outcome);
            }
        }
        return Finish(request, outcomes, outcomes.Count, log);
    }

    private static PackageOutcome Report(PackageRow row, ProcessResult r, Action<string>? log)
    {
        var outcome = new PackageOutcome(ExitCodes.Classify(r.ExitCode), $"exit {r.ExitCode}", r.ExitCode);
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
        return outcome;
    }

    private static QueueResult Finish(QueueRequest request, Dictionary<string, PackageOutcome> outcomes, int done, Action<string>? log)
    {
        var verb = request.Verb.ToString();
        var result = new QueueResult(request, outcomes, done < request.Rows.Count);
        log?.Invoke(result.Cancelled
            ? $"{verb} cancelled after {done} of {request.Rows.Count} packages; the rest were left untouched: {result.Summary}."
            : $"{verb} complete: {result.Summary}.");
        return result;
    }
}
