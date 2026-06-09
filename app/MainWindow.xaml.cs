using System;
using System.ComponentModel;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using NextAITranslator.Core;
using NextAITranslator.Interop;

namespace NextAITranslator
{
    public partial class MainWindow : Window
    {
        private bool _reallyExit = false;
        private CancellationTokenSource? _cts;

        public MainWindow()
        {
            InitializeComponent();
            SelectLang(App.Config.LastTargetLang);
            DarkTitleBar.Apply(this);
            ApplyScale();
            PreviewKeyDown += OnPreviewKeyDown;
        }

        // ----- UI scale -----

        public void ApplyScale()
        {
            var s = App.Config.UiScale;
            ScaleXform.ScaleX = s;
            ScaleXform.ScaleY = s;
        }

        private void SetScale(double s)
        {
            s = Math.Clamp(Math.Round(s, 2), 1.0, 2.0);
            App.Config.UiScale = s;
            App.Config.Save();
            ApplyScale();
        }

        private void OnPreviewKeyDown(object sender, System.Windows.Input.KeyEventArgs e)
        {
            if ((Keyboard.Modifiers & ModifierKeys.Control) == 0)
                return;

            switch (e.Key)
            {
                case Key.OemPlus or Key.Add:
                    SetScale(App.Config.UiScale + 0.1); e.Handled = true; break;
                case Key.OemMinus or Key.Subtract:
                    SetScale(App.Config.UiScale - 0.1); e.Handled = true; break;
                case Key.D0 or Key.NumPad0:
                    SetScale(1.0); e.Handled = true; break;
            }
        }

        private void SelectLang(string code)
        {
            foreach (ComboBoxItem item in TargetLang.Items)
            {
                if ((string)item.Tag == code)
                {
                    TargetLang.SelectedItem = item;
                    return;
                }
            }
            if (TargetLang.Items.Count > 0)
                TargetLang.SelectedIndex = 0;
        }

        public string SelectedLang =>
            (TargetLang.SelectedValue as string) ?? "zh-Hant";

        /// <summary>Bring the window to front (from tray / hotkey) and focus the input box.</summary>
        public void ShowAndFocus()
        {
            Show();
            if (WindowState == WindowState.Minimized)
                WindowState = WindowState.Normal;

            Activate();
            Topmost = true;
            Topmost = false;
            Focus();

            Dispatcher.BeginInvoke(new System.Action(() =>
            {
                InputBox.Focus();
                InputBox.SelectAll();
            }), System.Windows.Threading.DispatcherPriority.Input);
        }

        /// <summary>Invoked by the global hotkey: show the window and, if enabled, auto-translate the clipboard.</summary>
        public void SummonForHotkey()
        {
            ShowAndFocus();

            if (!App.Config.AutoTranslate)
                return;

            string clip = "";
            try
            {
                if (System.Windows.Clipboard.ContainsText())
                    clip = System.Windows.Clipboard.GetText();
            }
            catch { /* clipboard busy */ }

            if (!string.IsNullOrWhiteSpace(clip))
            {
                InputBox.Text = clip;
                _ = TranslateAsync();
            }
        }

        public void ExitForReal()
        {
            _reallyExit = true;
            Close();
        }

        protected override void OnClosing(CancelEventArgs e)
        {
            // Closing the window just hides it; the app keeps living in the tray.
            if (!_reallyExit)
            {
                e.Cancel = true;
                Hide();
            }
            base.OnClosing(e);
        }

        private void CopyButton_Click(object sender, RoutedEventArgs e)
        {
            if (!string.IsNullOrEmpty(OutputBox.Text))
            {
                try { System.Windows.Clipboard.SetText(OutputBox.Text); } catch { /* clipboard busy */ }
            }
        }

        private void ClearButton_Click(object sender, RoutedEventArgs e)
        {
            InputBox.Clear();
            InputBox.Focus();
        }

        private void SettingsButton_Click(object sender, RoutedEventArgs e)
        {
            var win = new SettingsWindow { Owner = this };
            win.ShowDialog();
            // Scale may have changed in settings.
            ApplyScale();
        }

        private async void TranslateButton_Click(object sender, RoutedEventArgs e)
        {
            await TranslateAsync();
        }

        public async Task TranslateAsync()
        {
            var text = InputBox.Text?.Trim() ?? "";
            if (text.Length == 0)
            {
                InputBox.Focus();
                return;
            }

            // Persist the chosen language so the choice survives restarts.
            App.Config.LastTargetLang = SelectedLang;
            App.Config.Save();

            var provider = App.Config.CurrentProvider();
            if (string.IsNullOrWhiteSpace(provider.ApiKey))
            {
                OutputBox.Text = $"尚未設定 API key（供應商：{App.Config.Provider}）。\n請開啟「設定」填入後再試。";
                return;
            }

            // Cancel any in-flight translation.
            _cts?.Cancel();
            _cts = new CancellationTokenSource();
            var ct = _cts.Token;

            TranslateButton.IsEnabled = false;
            OutputBox.Text = "";

            // Coalesce streamed tokens: accumulate on the network thread and flush to
            // the UI in batches (non-blocking) so reading isn't stalled per token.
            lock (_bufLock) { _pending.Clear(); _flushQueued = false; }

            try
            {
                await TranslateService.TranslateAsync(
                    App.Config, SelectedLang, text,
                    OnDelta,
                    ct);
                FlushPending(); // ensure the tail is rendered
            }
            catch (OperationCanceledException)
            {
                // Superseded by a newer translation; ignore.
            }
            catch (Exception ex)
            {
                OutputBox.Text = "翻譯失敗：" + ex.Message;
            }
            finally
            {
                TranslateButton.IsEnabled = true;
            }
        }

        // ----- streaming buffer (coalesced UI updates) -----

        private readonly object _bufLock = new();
        private readonly System.Text.StringBuilder _pending = new();
        private bool _flushQueued;

        private void OnDelta(string delta)
        {
            lock (_bufLock)
            {
                _pending.Append(delta);
                if (_flushQueued) return;
                _flushQueued = true;
            }
            Dispatcher.BeginInvoke(new Action(FlushPending), System.Windows.Threading.DispatcherPriority.Background);
        }

        private void FlushPending()
        {
            string chunk;
            lock (_bufLock)
            {
                chunk = _pending.ToString();
                _pending.Clear();
                _flushQueued = false;
            }
            if (chunk.Length == 0) return;
            OutputBox.AppendText(chunk);
            OutputBox.ScrollToEnd();
        }
    }
}
