using WinGetStudio.Core;

namespace WinGetStudio.Core.Tests;

// winget finto: registra gli argomenti di ogni chiamata (tranne --version) e risponde con
// Respond. Running/MaxRunning contano le chiamate sovrapposte.
internal sealed class FakeRunner : IProcessRunner
{
    public readonly List<string[]> Calls = [];
    public string Version = "v1.29.380";
    public Func<IReadOnlyList<string>, ProcessResult> Respond = _ => Result(0, "");
    public Func<Task> Delay = () => Task.CompletedTask;
    public TimeSpan? Tick;   // se impostato, un tick con questo tempo prima della risposta
    public int Running, MaxRunning;

    public static ProcessResult Result(int exit, string output) => new(exit, output, TimeSpan.Zero);

    public async Task<ProcessResult> RunAsync(string exePath, IReadOnlyList<string> arguments, Action<TimeSpan>? tick = null)
    {
        MaxRunning = Math.Max(MaxRunning, Interlocked.Increment(ref Running));
        try
        {
            await Delay();
            if (arguments is ["--version"]) return Result(0, Version);
            lock (Calls) Calls.Add([.. arguments]);
            if (Tick is { } t) tick?.Invoke(t);
            return Respond(arguments);
        }
        finally { Interlocked.Decrement(ref Running); }
    }
}

// Elevazione finta: Batches registra ogni runas (le righe di comando di tutti i passi), Unelevated
// ogni attivita' non elevata. Approved false = UAC rifiutato; Respond null = passo non partito.
internal sealed class FakeElevation : IElevation
{
    public bool IsElevated { get; set; }
    public bool OtherAccount { get; set; }
    public string Account { get; set; } = @"PC\admin";
    public bool Approved = true;
    public Func<IReadOnlyList<string>, ProcessResult?> Respond = _ => FakeRunner.Result(0, "");
    public Func<IReadOnlyList<string>, ProcessResult> RespondUnelevated = _ => FakeRunner.Result(0, "");
    public readonly List<string[][]> Batches = [];
    public readonly List<string[]> Unelevated = [];

    public Task<ElevatedRun> RunElevatedAsync(string exePath, IReadOnlyList<IReadOnlyList<string>> commands, Action<int, ProcessResult?>? step, CancellationToken cancel)
    {
        Batches.Add([.. commands.Select(c => c.ToArray())]);
        if (!Approved) return Task.FromResult(new ElevatedRun(false, [.. commands.Select(_ => (ProcessResult?)null)]));
        var results = new List<ProcessResult?>();
        for (var i = 0; i < commands.Count; i++)
        {
            if (cancel.IsCancellationRequested) { results.Add(null); continue; }
            step?.Invoke(i, null);
            var r = Respond(commands[i]);
            results.Add(r);
            if (r is not null) step?.Invoke(i, r);
        }
        return Task.FromResult(new ElevatedRun(true, results));
    }

    public Task<ProcessResult> RunUnelevatedAsync(string exePath, IReadOnlyList<string> arguments, Action<TimeSpan>? tick)
    {
        Unelevated.Add([.. arguments]);
        return Task.FromResult(RespondUnelevated(arguments));
    }

    public Task StartUnelevatedAsync(string exePath) => Task.CompletedTask;
}
