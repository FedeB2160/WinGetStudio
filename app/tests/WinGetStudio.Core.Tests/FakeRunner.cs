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
