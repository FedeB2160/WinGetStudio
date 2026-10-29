namespace WinGetStudio.Core;

// winget attraverso la sua CLI (ADR 0025): argomenti come lista, mai una shell; tabelle lette
// per posizione di colonna (ADR 0006).
public sealed class WinGetCli(string wingetPath, IProcessRunner? runner = null) : IWinGetBackend
{
    // Un solo processo winget alla volta in tutta l'app: due invocazioni concorrenti fanno
    // fallire una delle due con exit 1 (ADR 0003). Statico perche' vale fra istanze.
    private static readonly SemaphoreSlim Gate = new(1, 1);

    private readonly IProcessRunner _runner = runner ?? new ProcessRunner();
    private bool? _noProgress;

    // Percorso completo di winget, o null. Sempre completo: CreateProcess con un nome nudo
    // cercherebbe prima nella cartella corrente.
    public static string? FindWinGet()
    {
        foreach (var dir in (Environment.GetEnvironmentVariable("PATH") ?? "").Split(';', StringSplitOptions.RemoveEmptyEntries))
        {
            var candidate = Path.Combine(dir.Trim().Trim('"'), "winget.exe");
            if (Path.IsPathFullyQualified(candidate) && File.Exists(candidate)) return candidate;
        }
        // PATH senza WindowsApps (winget-cli#210): l'alias di esecuzione c'e' lo stesso.
        var alias = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), @"Microsoft\WindowsApps\winget.exe");
        return File.Exists(alias) ? alias : null;
    }

    // Ricerca nel catalogo, una sorgente per volta, quindi la sorgente di ogni riga e' quella
    // interrogata. Colonne: Nome | Id | Versione | [Corrispondenza], si usano le prime tre.
    // --source winget: solo l'indice locale (~0.4 s). msstore va in rete (~5 s): solo su
    //   richiesta, in una seconda ricerca coi risultati in coda. Dalla 1.29 winget non porta piu'
    //   in cima lo Store, e con un --count unico una parola comune lo lasciava fuori.
    // --count: senza tetto "ab" torna 1288 righe. Allo Store ne bastano 10.
    // Uno Store che non risponde non fa fallire la ricerca: il motivo va nell'output.
    public async Task<ReadResult<PackageRow>> SearchAsync(string query, bool includeStore, int count = 25)
    {
        if (string.IsNullOrWhiteSpace(query)) return new(true, [], 0, "");
        var rows = new List<PackageRow>();
        ReadResult<string[]>? first = null;
        var output = "";
        foreach (var (source, n) in new[] { ("winget", count), ("msstore", 10) })
        {
            if (source == "msstore" && !includeStore) break;
            var read = await ReadAsync(["search", query, "--count", n.ToString(), "--source", source, "--accept-source-agreements"]);
            // NO_APPLICATIONS_FOUND e' "nessuna corrispondenza": vuoto valido, solo qui.
            if (read.ExitCode == ExitCodes.NoApplicationsFound) read = read with { Success = true };
            if (first is null)
            {
                first = read;
                output = read.Output;
                if (!read.Success) return new(false, [], read.ExitCode, read.Output);
            }
            else if (!read.Success)
            {
                output += "\r\nmsstore: " + string.Join(' ', WinGetTable.OutputTail(read.Output));
                continue;
            }
            rows.AddRange(read.Rows.Select(f => new PackageRow(f[0], f[1], f[2], Source: source)));
        }
        return new(true, rows, first!.ExitCode, output);
    }

    // Colonne: Nome | Id | Versione | [Disponibile] | [Origine]. Disponibile compare solo se
    // qualcosa ha un aggiornamento, quindi la sorgente e' l'ULTIMA colonna; senza sorgenti non
    // c'e' nemmeno Disponibile. Le righe ARP ("ARP\Machine\X64\Nome") non hanno Origine.
    public Task<ReadResult<PackageRow>> GetInstalledAsync() =>
        ReadRowsAsync(["list", "--accept-source-agreements"], f =>
            // "> 8.12.30.21": il ">" segnala un aggiornamento, di cui si occupa Updates.
            new PackageRow(f[0], f[1], f[2].StartsWith('>') ? f[2][1..].TrimStart() : f[2], Source: f.Length >= 4 ? f[^1] : ""));

    // Colonne: Nome | Id | Versione | Disponibile | [Origine].
    public Task<ReadResult<PackageRow>> GetUpgradesAsync(bool includeUnknown) =>
        ReadRowsAsync(includeUnknown ? ["upgrade", "--accept-source-agreements", "--include-unknown"] : ["upgrade", "--accept-source-agreements"],
            // Senza la colonna Disponibile non e' un aggiornamento.
            f => f.Length < 4 ? null : new PackageRow(f[0], f[1], f[2], f[3], f.Length >= 5 ? f[4] : ""));

    // Id dei pacchetti con un pin; il tipo (Pinning / Blocking / Gating) non cambia cosa si
    // mostra. maxColumns 3 obbligatorio: l'ultima intestazione ("Tipo di pin") ha spazi.
    public Task<ReadResult<string>> GetPinsAsync() =>
        ReadRowsAsync(["pin", "list", "--accept-source-agreements"], f => f[1], maxColumns: 3);

    // Dettagli come TESTO di winget (ADR 0021): le etichette sono tradotte. list --details per
    // cio' che e' installato, show dal catalogo della sua sorgente; le righe ARP non ne hanno.
    public async Task<string> GetDetailsAsync(string id, string? source, bool installed)
    {
        ValidateId(id);
        var reads = new List<string[]>();
        if (installed) reads.Add(["list", "--id", id, "-e", "--details", "--accept-source-agreements", "--disable-interactivity"]);
        if (!string.IsNullOrEmpty(source)) reads.Add(["show", "--id", id, "-e", "--source", source, "--accept-source-agreements", "--disable-interactivity"]);
        var parts = new List<string>();
        foreach (var a in reads)
        {
            var text = WinGetTable.CleanText((await ReadAsync(a)).Output);
            if (text.Length > 0) parts.Add(text);
        }
        return string.Join("\r\n\r\n", parts);
    }

    // Gli Id vengono dal catalogo e dal registro ARP, dove il nome lo scrive l'installer: uno
    // che sembri un'opzione o porti caratteri di controllo non arriva a winget.
    public static void ValidateId(string id)
    {
        if (string.IsNullOrWhiteSpace(id) || id.StartsWith('-') || id.Any(char.IsControl))
            throw new ArgumentException($"Invalid package id: '{id}'", nameof(id));
    }

    private async Task<ReadResult<T>> ReadRowsAsync<T>(string[] arguments, Func<string[], T?> map, int maxColumns = 0)
    {
        var read = await ReadAsync(arguments, maxColumns);
        return new(read.Success, read.Rows.Select(map).OfType<T>().ToList(), read.ExitCode, read.Output);
    }

    // Lettura: Success = exit 0, e solo allora si parsa la tabella. Quando un exit non zero e'
    // un risultato valido lo decide il chiamante (SearchAsync).
    private async Task<ReadResult<string[]>> ReadAsync(string[] arguments, int maxColumns = 0)
    {
        ProcessResult r;
        try { r = await RunAsync(arguments); }
        catch (Exception e) when (e is System.ComponentModel.Win32Exception or IOException or UnauthorizedAccessException)
        {
            return new(false, [], -1, e.Message);
        }
        return new(r.ExitCode == 0, r.ExitCode == 0 ? WinGetTable.Parse(r.Output, maxColumns) : [], r.ExitCode, r.Output);
    }

    private async Task<ProcessResult> RunAsync(IReadOnlyList<string> arguments, Action<TimeSpan>? tick = null)
    {
        await Gate.WaitAsync();
        try
        {
            // --no-progress dalla 1.29 (accettato anche se --help non lo elenca); prima restano i
            // frame \r, che il parser riduce all'ultimo segmento.
            _noProgress ??= await SupportsNoProgressAsync();
            return await _runner.RunAsync(wingetPath, _noProgress.Value ? [.. arguments, "--no-progress"] : arguments, tick);
        }
        finally { Gate.Release(); }
    }

    // "v1.29.380". Una versione illeggibile vale come vecchia: senza l'opzione si legge lo stesso.
    private async Task<bool> SupportsNoProgressAsync()
    {
        var r = await _runner.RunAsync(wingetPath, ["--version"]);
        return r.ExitCode == 0 && Version.TryParse(r.Output.Trim().TrimStart('v'), out var v) && v >= new Version(1, 29);
    }
}
