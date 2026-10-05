using System;
using System.ComponentModel;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Threading;
using NextAITranslator.Core;
using NextAITranslator.Interop;

namespace NextAITranslator
{
    public partial class MainWindow : Window
    {
        private bool _reallyExit = false;
        private bool _loaded;
        private CancellationTokenSource? _cts;
        private string _selectedLang = "zh-Hant";
        private readonly DispatcherTimer _flushTimer = new(DispatcherPriority.Background)
        {
            Interval = TimeSpan.FromMilliseconds(40),
        };

        public MainWindow()
        {
            InitializeComponent();
            Width = App.Config.WindowWidth;
            Height = App.Config.WindowHeight;
            SelectLang(App.Config.LastTargetLang);
            SelectTone(App.Config.Tone);
            UpdateModelLabel();
            DarkTitleBar.Apply(this);
            ApplyScale();
            ApplyContentFont();
            ApplySplit();
            PreviewKeyDown += OnPreviewKeyDown;
            KeyDown += OnKeyDown;
            InputBox.PreviewMouseWheel += OnContentWheel;
            OutputBox.PreviewMouseWheel += OnContentWheel;
            _flushTimer.Tick += (_, _) => FlushPending(_gen);
            _loaded = true;
        }

        private void SelectTone(string tone)
        {
            foreach (ComboBoxItem item in ToneBox.Items)
            {
                if ((string)item.Tag == tone) { ToneBox.SelectedItem = item; return; }
            }
            ToneBox.SelectedIndex = 0;
        }

        private void ToneBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
        {
            if (!_loaded) return;
            if (ToneBox.SelectedValue is string tone)
            {
                App.Config.Tone = tone;
                App.Config.RequestSave();
            }
        }

        public void UpdateModelLabel()
        {
            var m = App.Config.CurrentProvider().Model;
            ModelLabel.Text = string.IsNullOrWhiteSpace(m) ? "（未設定模型）" : "模型：" + m;
        }

        // ----- translation content font size (independent of overall UI scale) -----

        public void ApplyContentFont()
        {
            InputBox.FontSize = App.Config.ContentFontSize;
            OutputBox.FontSize = App.Config.ContentFontSize;
        }

        private void SetContentFont(double size)
        {
            size = Math.Clamp(Math.Round(size), 12.0, 40.0);
            if (size == App.Config.ContentFontSize) return; // e.g. wheel past the clamp edge
            App.Config.ContentFontSize = size;
            App.Config.RequestSave();
            ApplyContentFont();
        }

        private void OnContentWheel(object sender, System.Windows.Input.MouseWheelEventArgs e)
        {
            if ((Keyboard.Modifiers & ModifierKeys.Control) == 0)
                return;
            SetContentFont(App.Config.ContentFontSize + (e.Delta > 0 ? 1 : -1));
            e.Handled = true;
        }

        // ----- input/output split ratio (dragging the middle control bar) -----

        private void ApplySplit()
        {
            var r = App.Config.SplitRatio;
            InputRow.Height = new GridLength(r, GridUnitType.Star);
            OutputRow.Height = new GridLength(1 - r, GridUnitType.Star);
        }

        private void Splitter_DragCompleted(object sender, System.Windows.Controls.Primitives.DragCompletedEventArgs e)
        {
            // After a drag both rows are still star-sized; persist their proportion.
            var total = InputRow.Height.Value + OutputRow.Height.Value;
            if (total <= 0) return;
            var r = Math.Clamp(InputRow.Height.Value / total, 0.15, 0.85);
            if (r == App.Config.SplitRatio) return;
            App.Config.SplitRatio = r;
            App.Config.RequestSave();
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
            if (s == App.Config.UiScale) return; // e.g. Ctrl+'+' past the clamp edge
            App.Config.UiScale = s;
            App.Config.RequestSave();
            ApplyScale();
        }

        private void OnPreviewKeyDown(object sender, System.Windows.Input.KeyEventArgs e)
        {
            if ((Keyboard.Modifiers & ModifierKeys.Control) == 0)
                return;

            switch (e.Key)
            {
                // Preview (tunneling) so the input box can't turn Ctrl+Enter into a newline.
                case Key.Enter:
                    _ = TranslateAsync(); e.Handled = true; break;
                case Key.OemPlus or Key.Add:
                    SetScale(App.Config.UiScale + 0.1); e.Handled = true; break;
                case Key.OemMinus or Key.Subtract:
                    SetScale(App.Config.UiScale - 0.1); e.Handled = true; break;
                case Key.D0 or Key.NumPad0:
                    SetScale(1.0); e.Handled = true; break;
            }
        }

        private void OnKeyDown(object sender, System.Windows.Input.KeyEventArgs e)
        {
            if (e.Key == Key.Escape)
            {
                Hide();
                e.Handled = true;
            }
        }

        private void SelectLang(string code)
        {
            _selectedLang = code == "en" ? "en" : "zh-Hant";
            TraditionalChineseButton.Style = (Style)FindResource(
                _selectedLang == "zh-Hant" ? "PrimaryButton" : "SecondaryButton");
            EnglishButton.Style = (Style)FindResource(
                _selectedLang == "en" ? "PrimaryButton" : "SecondaryButton");
        }

        private void LanguageButton_Click(object sender, RoutedEventArgs e)
        {
            if (sender is System.Windows.Controls.Button button && button.Tag is string code)
                SelectLang(code);
        }

        public string SelectedLang => _selectedLang;

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
            // Save window size so the next open restores it.
            App.Config.WindowWidth = Width;
            App.Config.WindowHeight = Height;
            if (!App.Config.TrySave(out var error))
                System.Windows.MessageBox.Show(this, "無法儲存設定：" + error,
                    "NextAI 翻譯", MessageBoxButton.OK, MessageBoxImage.Warning);

            // Closing the window just hides it; the app keeps living in the tray.
            if (!_reallyExit)
            {
                e.Cancel = true;
                Hide();
            }
            base.OnClosing(e);
        }

        protected override void OnClosed(EventArgs e)
        {
            CancelTranslation();
            base.OnClosed(e);
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
            // Scale / content font / model may have changed in settings.
            ApplyScale();
            ApplyContentFont();
            UpdateModelLabel();
        }

        private async void TranslateButton_Click(object sender, RoutedEventArgs e)
        {
            await TranslateAsync();
        }

        public async Task TranslateAsync()
        {
            var text = InputBox.Text.Trim();
            if (text.Length == 0)
            {
                InputBox.Focus();
                return;
            }

            // Persist the chosen language so the choice survives restarts.
            if (App.Config.LastTargetLang != SelectedLang)
            {
                App.Config.LastTargetLang = SelectedLang;
                App.Config.RequestSave();
            }

            CancelTranslation();
            var provider = App.Config.CurrentProvider();
            if (string.IsNullOrWhiteSpace(provider.ApiKey))
            {
                OutputBox.Text = $"尚未設定 API key（供應商：{App.Config.Provider}）。\n請開啟「設定」填入後再試。";
                return;
            }

            var cts = new CancellationTokenSource();
            _cts = cts;
            var ct = cts.Token;

            TranslateButton.IsEnabled = false;
            OutputBox.Text = "";

            // Coalesce streamed tokens: accumulate on the network thread and flush to
            // the UI in batches (non-blocking) so reading isn't stalled per token.
            // The generation stamp keeps a superseded translation's late deltas out
            // of the new translation's buffer.
            var gen = _gen;
            _flushTimer.Start();

            try
            {
                await TranslateService.TranslateAsync(
                    App.Config, SelectedLang, text,
                    delta => OnDelta(delta, gen),
                    ct);
                if (!ct.IsCancellationRequested)
                    FlushPending(gen); // render the tail immediately on completion
            }
            catch (Exception) when (ct.IsCancellationRequested)
            {
                // Superseded by a newer translation; ignore.
            }
            catch (Exception ex)
            {
                if (gen == _gen)
                {
                    lock (_bufLock) { ++_gen; _pending.Clear(); }
                    OutputBox.Text = ex is OperationCanceledException or TimeoutException
                        ? "翻譯逾時，請稍後重試或檢查網路連線。"
                        : "翻譯失敗：" + ex.Message;
                }
            }
            finally
            {
                // Only the latest translation may re-enable the button; a superseded
                // one finishing late must not re-enable it mid-stream.
                if (ReferenceEquals(_cts, cts))
                {
                    _flushTimer.Stop();
                    _cts = null;
                    TranslateButton.IsEnabled = true;
                }
                cts.Dispose();
            }
        }

        private void CancelTranslation()
        {
            lock (_bufLock) { ++_gen; _pending.Clear(); }
            _flushTimer.Stop();
            _cts?.Cancel();
            _cts = null; // the owning async method disposes its source
            TranslateButton.IsEnabled = true;
        }

        // ----- streaming buffer (coalesced UI updates) -----

        private readonly object _bufLock = new();
        private readonly System.Text.StringBuilder _pending = new();
        private int _gen;

        private void OnDelta(string delta, int gen)
        {
            lock (_bufLock)
            {
                if (gen != _gen) return; // stale delta from a superseded translation
                _pending.Append(delta);
            }
        }

        private void FlushPending(int gen)
        {
            string chunk;
            lock (_bufLock)
            {
                if (gen != _gen) return;
                chunk = _pending.ToString();
                _pending.Clear();
            }
            if (chunk.Length == 0) return;
            OutputBox.AppendText(chunk);
            OutputBox.ScrollToEnd();
        }
    }
}
