using System.IO;
using System.Text;

namespace WinGetStudio.ViewModels;

// Il log in fondo alla finestra, condiviso da tutte le schede. La vista aggiunge le righe con
// Appended invece di rilegare tutto il testo a ogni riga.
public sealed class LogViewModel(SynchronizationContext? ui = null)
{
    private readonly StringBuilder _text = new();
    private readonly int _uiThread = Environment.CurrentManagedThreadId;

    public event Action<string>? Appended;
    public event Action? Cleared;

    public string Text { get { lock (_text) return _text.ToString(); } }

    // Il tick ogni 30 s di un winget lungo arriva dal thread che lo attende: la riga passa dal
    // contesto della UI, che sola puo' toccare il TextBox.
    public void Write(string message)
    {
        var line = $"[{DateTime.Now:HH:mm:ss}] {message}\r\n";
        if (ui is not null && Environment.CurrentManagedThreadId != _uiThread) ui.Post(_ => Append(line), null);
        else Append(line);
    }

    public void Clear()
    {
        lock (_text) _text.Clear();
        Cleared?.Invoke();
    }

    // UTF-8 con BOM, come la 1.x: anche un editor vecchio legge le accentate.
    public void SaveTo(string path)
    {
        try
        {
            File.WriteAllText(path, Text, new UTF8Encoding(true));
            Write($"Log saved to {path}");
        }
        catch (Exception e) when (e is IOException or UnauthorizedAccessException)
        {
            Write($"Could not save the log: {e.Message}");
        }
    }

    private void Append(string line)
    {
        lock (_text) _text.Append(line);
        Appended?.Invoke(line);
    }
}
