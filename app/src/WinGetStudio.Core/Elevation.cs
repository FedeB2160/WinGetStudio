using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Security.Principal;
using System.Text;

namespace WinGetStudio.Core;

// Esito di un runas. Approved falso: UAC rifiutato, o Cancel durante l'attesa; nulla e' partito.
// Results: uno per comando, null per un passo che non e' partito (annullato).
public sealed record ElevatedRun(bool Approved, IReadOnlyList<ProcessResult?> Results);

// I diritti di amministratore visti dall'app (ADR 0024): l'app gira non elevata e chiede l'UAC
// solo per Retry as administrator; elevata (Restart as administrator) ripete senza elevazione cio'
// che winget rifiuta da amministratore (ADR 0018). Dietro un'interfaccia per i test.
public interface IElevation
{
    bool IsElevated { get; }
    // Elevata con un account diverso da quello della sessione: i pacchetti per utente sono suoi.
    bool OtherAccount { get; }
    string Account { get; }

    // Tutti i comandi in UN solo runas. step(i, null): il passo i parte; step(i, esito): finito.
    Task<ElevatedRun> RunElevatedAsync(string exePath, IReadOnlyList<IReadOnlyList<string>> commands, Action<int, ProcessResult?>? step, CancellationToken cancel);

    // Lo stesso account senza elevazione, con un'attivita' pianificata (ADR 0018).
    Task<ProcessResult> RunUnelevatedAsync(string exePath, IReadOnlyList<string> arguments, Action<TimeSpan>? tick);

    // Avvia exePath senza elevazione e torna appena e' partito: il riavvio non elevato.
    Task StartUnelevatedAsync(string exePath);
}

// File di un batch in %TEMP%, col prefisso di TempFiles: l'avvio pulisce cio' che resta.
internal sealed record BatchFiles(string Directory, int Count, string? Tag = null)
{
    private readonly string _tag = Tag ?? Guid.NewGuid().ToString("N");
    public string Cancel => Path.Combine(Directory, $"{TempFiles.Prefix}{_tag}.cancel");
    public string Out(int i) => Path.Combine(Directory, $"{TempFiles.Prefix}{_tag}_{i}.out");
    public string Err(int i) => Path.Combine(Directory, $"{TempFiles.Prefix}{_tag}_{i}.err");
    public string Code(int i) => Path.Combine(Directory, $"{TempFiles.Prefix}{_tag}_{i}.code");
}

public sealed partial class Elevation : IElevation
{
    private static readonly string Cmd = Path.Combine(Environment.SystemDirectory, "cmd.exe");
    private const int ErrorCancelled = 1223;

    public bool IsElevated { get; } = CheckElevated();
    public string Account { get; } = CurrentAccount();
    public bool OtherAccount => IsElevated && SessionAccount() is { } user && !string.Equals(user, Account, StringComparison.OrdinalIgnoreCase);

    // Il portable self-contained estrae le librerie native in %TEMP%\.net, che l'utente non
    // elevato puo' riscrivere: elevato le caricherebbe da li' (ADR 0026). Il setup e' in Program
    // Files col runtime condiviso; la build di sviluppo resta, per provarlo.
    public static bool CanRestartElevated(InstallChannel channel) => channel is InstallChannel.Installed or InstallChannel.Source;

    // false se l'UAC e' stato rifiutato.
    public static bool RestartElevated(string exePath)
    {
        try
        {
            using var p = Process.Start(new ProcessStartInfo(exePath) { UseShellExecute = true, Verb = "runas" });
            return true;
        }
        catch (Win32Exception e) when (IsDeclined(e)) { return false; }
    }

    // ShellExecute runas con l'UAC rifiutato: ERROR_CANCELLED, nessun processo.
    public static bool IsDeclined(Win32Exception e) => e.NativeErrorCode == ErrorCancelled;

    public Task<ElevatedRun> RunElevatedAsync(string exePath, IReadOnlyList<IReadOnlyList<string>> commands, Action<int, ProcessResult?>? step, CancellationToken cancel) =>
        RunBatchAsync(exePath, commands, step, cancel);

    // Una riga di cmd per tutti i passi: runas non passa handle ereditati, quindi i redirect li fa
    // cmd (misurato in ADR 0024). Prima di ogni passo il segnale di annullamento; dopo, l'exit code
    // nel suo file: il handle del processo ne ha uno solo, quello dell'ultimo comando. Redirect
    // DAVANTI a echo: "echo 3>file" sarebbe la redirezione dell'handle 3.
    internal static string BatchLine(string exePath, IReadOnlyList<IReadOnlyList<string>> commands, BatchFiles files)
    {
        var steps = commands.Select((args, i) =>
            $"(if not exist {Quote(files.Cancel)} ({Quote(exePath)} {Arguments(args)} >{Quote(files.Out(i))} 2>{Quote(files.Err(i))} & >{Quote(files.Code(i))} call echo %^errorlevel%))");
        return $"/d /v:off /s /c \"{string.Join(" & ", steps)}\"";
    }

    // verb "" nei test: lo stesso batch senza UAC.
    internal static async Task<ElevatedRun> RunBatchAsync(string exePath, IReadOnlyList<IReadOnlyList<string>> commands,
        Action<int, ProcessResult?>? step, CancellationToken cancel, string verb = "runas")
    {
        var notRun = new ElevatedRun(false, [.. commands.Select(_ => (ProcessResult?)null)]);
        if (cancel.IsCancellationRequested) return notRun;
        var files = new BatchFiles(Path.GetTempPath(), commands.Count);
        var line = BatchLine(exePath, commands, files);
        // I file li crea l'app PRIMA dell'elevazione e li tiene aperti senza FileShare.Delete fino
        // alla fine: in %TEMP% un processo non elevato potrebbe mettere al loro posto un link, e il
        // cmd elevato scriverebbe dove dice lui. Tenuti aperti non si cancellano ne' rinominano.
        // In SOLA lettura: il redirect di cmd non condivide la scrittura. Il handle di lettura si
        // apre prima di chiudere quello che crea il file, cosi' non c'e' un istante senza.
        var held = new List<FileStream>();
        var handOver = false;
        try
        {
            for (var i = 0; i < commands.Count; i++)
                foreach (var f in new[] { files.Out(i), files.Err(i), files.Code(i) })
                    using (new FileStream(f, FileMode.CreateNew, FileAccess.ReadWrite, FileShare.ReadWrite))
                        held.Add(new FileStream(f, FileMode.Open, FileAccess.Read, FileShare.ReadWrite));

            // ShellExecuteEx resta bloccato finche' l'UAC non ha risposta: winget e questa coda non
            // hanno timeout (ADR 0004), quindi Cancel deve poter smettere di aspettarlo.
            var start = Task.Run(() => Process.Start(new ProcessStartInfo(Cmd, line) { UseShellExecute = true, Verb = verb, WindowStyle = ProcessWindowStyle.Hidden }));
            if (await Task.WhenAny(start, Task.Delay(Timeout.Infinite, cancel)) != start)
            {
                // Approvato dopo, il batch trova il segnale e non fa nulla; i file restano aperti
                // finche' quel processo, se parte, non e' uscito.
                CreateMarker(files.Cancel);
                handOver = true;
                _ = ReleaseAfterAsync(start, held, files, commands.Count);
                return notRun;
            }

            Process? process;
            try { process = await start; }
            catch (Win32Exception e) when (IsDeclined(e)) { return notRun; }
            using (process ?? throw new InvalidOperationException("Windows did not start the elevated command."))
            {
                var results = new ProcessResult?[commands.Count];
                var current = 0;
                var marked = false;
                var sw = Stopwatch.StartNew();
                var exit = process.WaitForExitAsync();
                step?.Invoke(0, null);
                while (true)
                {
                    await Task.WhenAny(exit, Task.Delay(250));
                    var exited = exit.IsCompleted;
                    if (cancel.IsCancellationRequested && !marked)
                    {
                        CreateMarker(files.Cancel);
                        marked = true;
                    }
                    // I passi finiti hanno scritto il loro exit code.
                    while (current < commands.Count && ReadCode(held[current * 3 + 2]) is int code)
                    {
                        results[current] = new ProcessResult(code, ReadAll(held[current * 3]) + ReadAll(held[current * 3 + 1]), sw.Elapsed);
                        step?.Invoke(current, results[current]);
                        sw.Restart();
                        if (++current < commands.Count && !marked) step?.Invoke(current, null);
                    }
                    if (exited) break;
                }
                return new ElevatedRun(true, results);
            }
        }
        finally
        {
            if (!handOver) Release(held, files, commands.Count);
        }
    }

    private static async Task ReleaseAfterAsync(Task<Process?> start, List<FileStream> held, BatchFiles files, int count)
    {
        try
        {
            using var p = await start;
            if (p is not null) await p.WaitForExitAsync();
        }
        catch (Win32Exception) { }
        finally { Release(held, files, count); }
    }

    // Il segnale resta: un batch approvato piu' tardi deve trovarlo. Lo pulisce l'avvio.
    private static void Release(List<FileStream> held, BatchFiles files, int count)
    {
        foreach (var h in held) h.Dispose();
        for (var i = 0; i < count; i++)
            foreach (var f in new[] { files.Out(i), files.Err(i), files.Code(i) })
                try { File.Delete(f); } catch (IOException) { } catch (UnauthorizedAccessException) { }
    }

    private static void CreateMarker(string path)
    {
        try { File.WriteAllText(path, ""); } catch (IOException) { }
    }

    // "3\r\n" quando il passo e' finito; vuoto prima (il file lo crea l'app).
    private static int? ReadCode(FileStream s)
    {
        var text = ReadAll(s);
        return text.EndsWith('\n') && int.TryParse(text.Trim(), out var code) ? code : null;
    }

    // winget scrive UTF-8 (ProcessRunner).
    private static string ReadAll(FileStream s)
    {
        s.Position = 0;
        using var r = new StreamReader(s, new UTF8Encoding(false), false, 4096, leaveOpen: true);
        return r.ReadToEnd();
    }

    // cmd espande %VAR% anche fra apici, e un apice nell'argomento chiuderebbe la quotatura: dentro
    // un processo elevato sarebbero comandi scelti da chi ha scritto la variabile o il nome del
    // pacchetto (il controllo della 1.x, v1.13). Il resto lo protegge la quotatura.
    private static string Arguments(IReadOnlyList<string> args)
    {
        foreach (var a in args)
            if (a.Any(c => c is '%' or '"' || char.IsControl(c)))
                throw new ArgumentException($"refusing to pass to cmd an argument with '%', a quote or a control character: {a}");
        return CommandLine.Join(args);
    }

    private static string Quote(string path) => "\"" + path + "\"";

    public Task<ProcessResult> RunUnelevatedAsync(string exePath, IReadOnlyList<string> arguments, Action<TimeSpan>? tick) =>
        Task.Run(() => RunTask(exePath, arguments, tick));

    // L'exe direttamente, senza cmd: nessuna console. Cancellare l'attivita' non chiude il processo
    // che ha avviato (verificato).
    public Task StartUnelevatedAsync(string exePath) => Task.Run(() => RunScheduled(exePath, "", untilStarted: true, null));

    // cmd visibile e non nascosto con trucchi: e' cio' che gli antivirus aziendali segnalano.
    private ProcessResult RunTask(string exePath, IReadOnlyList<string> arguments, Action<TimeSpan>? tick)
    {
        var files = new BatchFiles(Path.GetTempPath(), 1);
        // Il titolo dice di chi e' la console che si apre.
        var line = $"/d /v:off /s /c \"title WinGet Studio & {Quote(exePath)} {Arguments(arguments)} >{Quote(files.Out(0))} 2>{Quote(files.Err(0))}\"";
        var sw = Stopwatch.StartNew();
        try
        {
            var result = RunScheduled(Cmd, line, untilStarted: false, tick);
            return new ProcessResult(result, ReadFile(files.Out(0)) + ReadFile(files.Err(0)), sw.Elapsed);
        }
        finally
        {
            foreach (var f in new[] { files.Out(0), files.Err(0) })
                try { File.Delete(f); } catch (IOException) { } catch (UnauthorizedAccessException) { }
        }
    }

    // Un'attivita' pianificata e' il modo documentato di avere il token non elevato da un processo
    // elevato senza chiedere password (ADR 0018): LogonType Interactive nella sessione gia' aperta
    // dall'account, RunLevel Limited. Senza sessione non parte: dopo 30 s si esce con un errore.
    // untilStarted: si torna appena e' partita; altrimenti alla fine, con l'exit code.
    private int RunScheduled(string path, string arguments, bool untilStarted, Action<TimeSpan>? tick)
    {
        var name = $"WinGetStudio_{Guid.NewGuid():N}";
        dynamic service = Activator.CreateInstance(Type.GetTypeFromProgID("Schedule.Service", true)!)!;
        service.Connect();
        dynamic folder = service.GetFolder(@"\");
        try
        {
            dynamic definition = service.NewTask(0);
            definition.Principal.UserId = Account;
            definition.Principal.LogonType = 3;   // TASK_LOGON_INTERACTIVE_TOKEN
            definition.Principal.RunLevel = 0;    // TASK_RUNLEVEL_LUA
            // Senza queste, su un portatile scollegato l'attivita' non parte.
            definition.Settings.DisallowStartIfOnBatteries = false;
            definition.Settings.StopIfGoingOnBatteries = false;
            definition.Settings.ExecutionTimeLimit = "PT0S";
            dynamic action = definition.Actions.Create(0);   // TASK_ACTION_EXEC
            action.Path = path;
            action.Arguments = arguments;
            folder.RegisterTaskDefinition(name, definition, 6, null, null, 3);   // CREATE_OR_UPDATE, INTERACTIVE_TOKEN
            folder.GetTask(name).Run(null);
            var sw = Stopwatch.StartNew();
            var nextTick = TimeSpan.FromSeconds(30);
            while (true)
            {
                Thread.Sleep(untilStarted ? 100 : 500);
                dynamic task = folder.GetTask(name);
                int state = task.State;
                int result = task.LastTaskResult;
                // 0x41301 in corso, 0x41303 non ancora partita; altrimenti l'exit code.
                if (untilStarted ? result != 0x41303 : state is not (2 or 4) && result is not (0x41301 or 0x41303)) return result;
                if (result == 0x41303 && sw.Elapsed >= TimeSpan.FromSeconds(30))
                    throw new InvalidOperationException($"the unelevated task did not start within 30 seconds: {Account} has no open session to run it in");
                if (sw.Elapsed >= nextTick)
                {
                    tick?.Invoke(sw.Elapsed);
                    nextTick += TimeSpan.FromSeconds(30);
                }
            }
        }
        finally
        {
            try { folder.DeleteTask(name, 0); } catch (COMException) { }
        }
    }

    private static string ReadFile(string path)
    {
        try { return File.ReadAllText(path, new UTF8Encoding(false)); }
        catch (IOException) { return ""; }
    }

    private static bool CheckElevated()
    {
        using var id = WindowsIdentity.GetCurrent();
        return new WindowsPrincipal(id).IsInRole(WindowsBuiltInRole.Administrator);
    }

    private static string CurrentAccount()
    {
        using var id = WindowsIdentity.GetCurrent();
        return id.Name;
    }

    // DOMINIO\utente di chi ha aperto la sessione di questo processo (anche in desktop remoto), o
    // null: se non si riesce a stabilirlo meglio tacere che allarmare (1.x).
    private static string? SessionAccount()
    {
        var session = Process.GetCurrentProcess().SessionId;
        var user = SessionString(session, 5);     // WTSUserName
        var domain = SessionString(session, 7);   // WTSDomainName
        return string.IsNullOrEmpty(user) ? null : string.IsNullOrEmpty(domain) ? user : $@"{domain}\{user}";
    }

    private static string? SessionString(int session, int infoClass)
    {
        if (!WTSQuerySessionInformationW(0, session, infoClass, out var buffer, out _)) return null;
        try { return Marshal.PtrToStringUni(buffer); }
        finally { WTSFreeMemory(buffer); }
    }

    [LibraryImport("wtsapi32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool WTSQuerySessionInformationW(nint server, int sessionId, int infoClass, out nint buffer, out int bytes);

    [LibraryImport("wtsapi32.dll")]
    private static partial void WTSFreeMemory(nint memory);
}
