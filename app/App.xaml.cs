using System;
using System.Threading;
using System.Windows;
using System.Windows.Interop;
using NextAITranslator.Interop;
using NextAITranslator.Storage;
using NextAITranslator.Tray;

namespace NextAITranslator
{
    public partial class App : System.Windows.Application
    {
        private const string MutexName = "NextAITranslator.SingleInstance";

        private Mutex? _mutex;
        private bool _ownsMutex;
        private HotKeyManager? _hotkey;
        private TrayManager? _tray;
        private MainWindow? _window;

        private static App? _instance;

        /// <summary>Global config, loaded once at startup.</summary>
        public static AppConfig Config { get; private set; } = null!;

        /// <summary>Re-register the global hotkey from the current config. Returns false if it failed.</summary>
        public static bool ApplyHotkey() =>
            _instance?._hotkey?.Register(Config.Hotkey) ?? false;

        private void Application_Startup(object sender, StartupEventArgs e)
        {
            _instance = this;

            DispatcherUnhandledException += (_, args) =>
            {
                System.Windows.MessageBox.Show("發生未預期的錯誤：\n\n" + args.Exception,
                    "NextAI 翻譯", MessageBoxButton.OK, MessageBoxImage.Error);
                args.Handled = true;
            };

            // 1. Single instance.
            _mutex = new Mutex(true, MutexName, out _ownsMutex);
            if (!_ownsMutex)
            {
                Shutdown();
                return;
            }

            // 2. Config. Persist once so the file exists on first run (handy for manual editing).
            Config = AppConfig.Load();
            try { Config.Save(); }
            catch
            {
                // A locked/read-only config file must not abort startup: with
                // OnExplicitShutdown an exception here would leave a window-less,
                // tray-less zombie process.
            }

            bool silently = false;
            foreach (var arg in e.Args)
                if (string.Equals(arg, "--silently", StringComparison.OrdinalIgnoreCase))
                    silently = true;

            // 3. Main window (create handle without showing so the hotkey works even when hidden).
            _window = new MainWindow();
            var handle = new WindowInteropHelper(_window).EnsureHandle();

            // 4. Global hotkey.
            _hotkey = new HotKeyManager(handle);
            _hotkey.Pressed += () => _window!.SummonForHotkey();
            _hotkey.Register(Config.Hotkey);

            // 5. Tray.
            _tray = new TrayManager(_window);

            if (!silently)
                _window.ShowAndFocus();
        }

        private void Application_Exit(object sender, ExitEventArgs e)
        {
            _hotkey?.Dispose();
            _tray?.Dispose();

            if (_ownsMutex)
                _mutex?.ReleaseMutex();
            _mutex?.Dispose();
        }
    }
}
