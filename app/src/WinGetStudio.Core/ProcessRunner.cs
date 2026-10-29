using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace WinGetStudio.Core;

public sealed record ProcessResult(int ExitCode, string Output, TimeSpan Elapsed);

public interface IProcessRunner
{
    // tick: chiamato a intervalli col tempo trascorso (la riga "elapsed" del log).
    Task<ProcessResult> RunAsync(string exePath, IReadOnlyList<string> arguments, Action<TimeSpan>? tick = null);
}

// Avvia un programma SENZA cmd (ADR 0025) e attende SOLO la sua uscita, con stdout e stderr
// su file. PERCHE' NON UNA PIPE: la lettura finisce all'EOF, cioe' quando TUTTI i processi che
// possiedono il handle lo chiudono; gli installer silenziosi lanciati da winget lo ereditano,
// e se uno resta vivo l'attesa e' infinita anche a winget uscito (ADR 0004). Nessun timeout:
// gli installer lenti non vengono troncati.
// PERCHE' NON Process.Start: redirige solo su pipe. Qui CreateProcess riceve i handle dei file
// come stdout/stderr, e la lista PROC_THREAD_ATTRIBUTE_HANDLE_LIST limita l'eredita' a quelli.
public sealed partial class ProcessRunner(TimeSpan? tickInterval = null) : IProcessRunner
{
    private readonly TimeSpan _tickInterval = tickInterval ?? TimeSpan.FromSeconds(30);

    public Task<ProcessResult> RunAsync(string exePath, IReadOnlyList<string> arguments, Action<TimeSpan>? tick = null) =>
        Task.Run(() => Run(exePath, arguments, tick));

    private ProcessResult Run(string exePath, IReadOnlyList<string> arguments, Action<TimeSpan>? tick)
    {
        var outFile = Path.Combine(Path.GetTempPath(), $"{TempFiles.Prefix}{Guid.NewGuid():N}.out");
        var errFile = Path.ChangeExtension(outFile, ".err");
        try
        {
            int code;
            var sw = Stopwatch.StartNew();
            using (var stdin = OpenInheritable("NUL", FileMode.Open, FileAccess.Read))
            using (var stdout = OpenInheritable(outFile, FileMode.CreateNew, FileAccess.Write))
            using (var stderr = OpenInheritable(errFile, FileMode.CreateNew, FileAccess.Write))
            using (var process = Start(CommandLine.Join([exePath, .. arguments]), stdin, stdout, stderr))
            {
                while (WaitForSingleObject(process, (uint)_tickInterval.TotalMilliseconds) == WaitTimeout)
                    tick?.Invoke(sw.Elapsed);
                if (!GetExitCodeProcess(process, out var exit)) throw new Win32Exception();
                code = unchecked((int)exit);
            }
            // winget scrive UTF-8 sempre (Core.cpp), con o senza console.
            return new ProcessResult(code, ReadShared(outFile) + ReadShared(errFile), sw.Elapsed);
        }
        finally
        {
            // Un figlio staccato puo' tenere aperti i file: ci pensa TempFiles.Clear all'avvio.
            foreach (var f in new[] { outFile, errFile })
                try { File.Delete(f); } catch (IOException) { } catch (UnauthorizedAccessException) { }
        }
    }

    // FileShare.Delete: il file si cancella anche se un figlio staccato lo tiene ancora aperto.
    // shortcut: finche' sono ereditabili, un altro processo avviato in quell'istante da questa
    // app con bInheritHandles li erediterebbe (tiene solo aperto un file di output); se l'app
    // avviera' processi in parallelo a winget, duplicarli ereditabili subito prima di CreateProcess.
    private static SafeFileHandle OpenInheritable(string path, FileMode mode, FileAccess access)
    {
        var h = File.OpenHandle(path, mode, access, FileShare.ReadWrite | FileShare.Delete);
        if (!SetHandleInformation(h, HandleFlagInherit, HandleFlagInherit)) throw new Win32Exception();
        return h;
    }

    private static string ReadShared(string path)
    {
        using var s = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete);
        using var r = new StreamReader(s, new UTF8Encoding(false));
        return r.ReadToEnd();
    }

    private static SafeProcessHandle Start(string commandLine, SafeFileHandle stdin, SafeFileHandle stdout, SafeFileHandle stderr)
    {
        nint size = 0;
        InitializeProcThreadAttributeList(0, 1, 0, ref size);
        var attributes = Marshal.AllocHGlobal(size);
        var handles = Marshal.AllocHGlobal(3 * IntPtr.Size);
        var refs = new[] { stdin, stdout, stderr };
        var added = new bool[3];
        try
        {
            for (var i = 0; i < 3; i++)
            {
                refs[i].DangerousAddRef(ref added[i]);
                Marshal.WriteIntPtr(handles, i * IntPtr.Size, refs[i].DangerousGetHandle());
            }
            if (!InitializeProcThreadAttributeList(attributes, 1, 0, ref size)) throw new Win32Exception();
            try
            {
                if (!UpdateProcThreadAttribute(attributes, 0, ProcThreadAttributeHandleList, handles, 3 * IntPtr.Size, 0, 0))
                    throw new Win32Exception();
                var si = new StartupInfoEx
                {
                    cb = Marshal.SizeOf<StartupInfoEx>(),
                    dwFlags = StartfUseStdHandles,
                    hStdInput = refs[0].DangerousGetHandle(),
                    hStdOutput = refs[1].DangerousGetHandle(),
                    hStdError = refs[2].DangerousGetHandle(),
                    lpAttributeList = attributes,
                };
                // La riga deve essere scrivibile: CreateProcessW puo' modificarla.
                var line = (commandLine + "\0").ToCharArray();
                if (!CreateProcessW(null, line, 0, 0, true, ExtendedStartupInfoPresent | CreateNoWindow, 0, null, ref si, out var pi))
                    throw new Win32Exception();
                CloseHandle(pi.hThread);
                return new SafeProcessHandle(pi.hProcess, ownsHandle: true);
            }
            finally { DeleteProcThreadAttributeList(attributes); }
        }
        finally
        {
            for (var i = 0; i < 3; i++) if (added[i]) refs[i].DangerousRelease();
            Marshal.FreeHGlobal(handles);
            Marshal.FreeHGlobal(attributes);
        }
    }

    private const uint HandleFlagInherit = 1;
    private const int StartfUseStdHandles = 0x100;
    private const uint ExtendedStartupInfoPresent = 0x80000;
    private const uint CreateNoWindow = 0x08000000;
    private const uint WaitTimeout = 0x102;
    private static readonly nint ProcThreadAttributeHandleList = 0x20002;

    [StructLayout(LayoutKind.Sequential)]
    private struct StartupInfoEx
    {
        public int cb;
        public nint lpReserved, lpDesktop, lpTitle;
        public int dwX, dwY, dwXSize, dwYSize, dwXCountChars, dwYCountChars, dwFillAttribute, dwFlags;
        public short wShowWindow, cbReserved2;
        public nint lpReserved2, hStdInput, hStdOutput, hStdError;
        public nint lpAttributeList;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct ProcessInformation
    {
        public nint hProcess, hThread;
        public int dwProcessId, dwThreadId;
    }

    [LibraryImport("kernel32.dll", SetLastError = true, StringMarshalling = StringMarshalling.Utf16)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool CreateProcessW(string? applicationName, char[] commandLine, nint processAttributes, nint threadAttributes,
        [MarshalAs(UnmanagedType.Bool)] bool inheritHandles, uint creationFlags, nint environment, string? currentDirectory,
        ref StartupInfoEx startupInfo, out ProcessInformation processInformation);

    [LibraryImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool InitializeProcThreadAttributeList(nint attributeList, int attributeCount, int flags, ref nint size);

    [LibraryImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool UpdateProcThreadAttribute(nint attributeList, uint flags, nint attribute, nint value, nint size, nint previousValue, nint returnSize);

    [LibraryImport("kernel32.dll")]
    private static partial void DeleteProcThreadAttributeList(nint attributeList);

    [LibraryImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool SetHandleInformation(SafeFileHandle handle, uint mask, uint flags);

    [LibraryImport("kernel32.dll", SetLastError = true)]
    private static partial uint WaitForSingleObject(SafeProcessHandle handle, uint milliseconds);

    [LibraryImport("kernel32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool GetExitCodeProcess(SafeProcessHandle handle, out uint exitCode);

    [LibraryImport("kernel32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static partial bool CloseHandle(nint handle);
}
