using System;
using System.Collections.Generic;
using System.Globalization;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using NextAITranslator.Core;
using NextAITranslator.Interop;
using NextAITranslator.Storage;

namespace NextAITranslator
{
    public partial class SettingsWindow : Window
    {
        // Working copies so that "取消" never mutates the live config.
        private readonly Dictionary<string, ProviderConfig> _work = new();
        private string _currentKey = "gemini";
        private bool _loaded;
        private bool _scaleTouched;
        private bool _fontTouched;
        private CancellationTokenSource? _modelCts;

        public SettingsWindow()
        {
            InitializeComponent();
            DarkTitleBar.Apply(this);

            foreach (var kv in App.Config.Providers)
                _work[kv.Key] = new ProviderConfig
                {
                    ApiKey = kv.Value.ApiKey,
                    BaseUrl = kv.Value.BaseUrl,
                    Model = kv.Value.Model,
                };

            HotkeyBox.Text = App.Config.Hotkey;
            AutoTranslateBox.IsChecked = App.Config.AutoTranslate;
            StartupBox.IsChecked = GetStartup();
            SelectScale(App.Config.UiScale);
            SelectFontSize(App.Config.ContentFontSize);
            PromptBox.Text = App.Config.PromptTemplate;

            SelectProvider(App.Config.Provider);
            _currentKey = SelectedProviderKey();
            LoadProviderFields(_currentKey);
            _loaded = true;
        }

        private string SelectedProviderKey() =>
            (ProviderBox.SelectedItem as ComboBoxItem)?.Tag as string ?? "gemini";

        private void SelectProvider(string key)
        {
            foreach (ComboBoxItem item in ProviderBox.Items)
            {
                if ((string)item.Tag == key) { ProviderBox.SelectedItem = item; return; }
            }
            ProviderBox.SelectedIndex = 0;
        }

        private void SelectScale(double scale)
        {
            foreach (ComboBoxItem item in ScaleBox.Items)
            {
                if (double.TryParse((string)item.Tag, NumberStyles.Float, CultureInfo.InvariantCulture, out var v) &&
                    Math.Abs(v - scale) < 0.001)
                {
                    ScaleBox.SelectedItem = item;
                    return;
                }
            }
            ScaleBox.SelectedIndex = 0;
        }

        private void SelectFontSize(double size)
        {
            foreach (ComboBoxItem item in FontSizeBox.Items)
            {
                if (double.TryParse((string)item.Tag, NumberStyles.Float, CultureInfo.InvariantCulture, out var v) &&
                    Math.Abs(v - size) < 0.001)
                {
                    FontSizeBox.SelectedItem = item;
                    return;
                }
            }
            FontSizeBox.SelectedIndex = -1; // a custom (wheel-set) value not in the list
        }

        private void ResetPrompt_Click(object sender, RoutedEventArgs e)
        {
            PromptBox.Text = AppConfig.DefaultPromptTemplate;
        }

        private void ScaleBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
        {
            if (_loaded) _scaleTouched = true;
        }

        private void FontSizeBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
        {
            if (_loaded) _fontTouched = true;
        }

        private void LoadProviderFields(string key)
        {
            if (!_work.TryGetValue(key, out var p))
            {
                p = new ProviderConfig();
                _work[key] = p;
            }
            ApiKeyBox.Text = p.ApiKey;
            BaseUrlBox.Text = p.BaseUrl;
            ModelBox.Items.Clear();
            if (!string.IsNullOrWhiteSpace(p.Model))
                ModelBox.Items.Add(p.Model);
            ModelBox.Text = p.Model;
            ModelStatus.Text = "貼上 API Key 後會自動列出可用模型，或按「重新整理」。";
        }

        private void FlushProviderFields(string key)
        {
            if (!_work.TryGetValue(key, out var p))
            {
                p = new ProviderConfig();
                _work[key] = p;
            }
            p.ApiKey = ApiKeyBox.Text.Trim();
            p.BaseUrl = BaseUrlBox.Text.Trim();
            p.Model = ModelBox.Text.Trim();
        }

        private void ProviderBox_SelectionChanged(object sender, SelectionChangedEventArgs e)
        {
            if (!_loaded) return;
            // An in-flight fetch for the old provider must not fill the new one's list.
            _modelCts?.Cancel();
            FlushProviderFields(_currentKey);
            _currentKey = SelectedProviderKey();
            LoadProviderFields(_currentKey);
        }

        // ----- model listing -----

        private async void RefreshButton_Click(object sender, RoutedEventArgs e) => await FetchModelsAsync();

        private async void ApiKeyBox_LostFocus(object sender, RoutedEventArgs e)
        {
            if (_loaded && !string.IsNullOrWhiteSpace(ApiKeyBox.Text))
                await FetchModelsAsync();
        }

        private async Task FetchModelsAsync()
        {
            var key = ApiKeyBox.Text.Trim();
            if (key.Length == 0)
            {
                ModelStatus.Text = "請先填入 API Key。";
                return;
            }

            var provider = SelectedProviderKey();
            var cfg = new ProviderConfig
            {
                ApiKey = key,
                BaseUrl = BaseUrlBox.Text.Trim(),
                Model = ModelBox.Text.Trim(),
            };

            _modelCts?.Cancel();
            var cts = new CancellationTokenSource();
            _modelCts = cts;
            var ct = cts.Token;

            RefreshButton.IsEnabled = false;
            ModelStatus.Text = "正在取得模型清單…";

            try
            {
                var models = await ModelService.ListAsync(provider, cfg, ct);
                ct.ThrowIfCancellationRequested(); // superseded while completing
                var current = ModelBox.Text;
                ModelBox.Items.Clear();
                foreach (var m in models)
                    ModelBox.Items.Add(m);
                ModelBox.Text = current; // preserve the user's current choice / typed text
                ModelStatus.Text = models.Count > 0
                    ? $"找到 {models.Count} 個模型，可從下拉選擇。"
                    : "沒有取得到任何模型，可手動輸入模型名稱。";
            }
            catch (OperationCanceledException) { }
            catch (Exception ex) when (!ct.IsCancellationRequested)
            {
                ModelStatus.Text = "取得模型失敗：" + ex.Message;
            }
            catch
            {
                // A cancelled fetch must not overwrite the status of a newer one.
            }
            finally
            {
                // Only the latest fetch may re-enable the button.
                if (_modelCts == cts)
                    RefreshButton.IsEnabled = true;
            }
        }

        // ----- startup registry -----

        private const string StartupRegKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
        private const string StartupRegName = "NextAITranslator";

        private static bool GetStartup()
        {
            using var key = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(StartupRegKey);
            return key?.GetValue(StartupRegName) != null;
        }

        private static void SetStartup(bool enable)
        {
            using var key = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(StartupRegKey, writable: true);
            if (key == null) return;
            if (enable)
                key.SetValue(StartupRegName,
                    $"\"{System.Diagnostics.Process.GetCurrentProcess().MainModule!.FileName}\" --silently");
            else
                key.DeleteValue(StartupRegName, throwOnMissingValue: false);
        }

        // ----- save / cancel -----

        private void Save_Click(object sender, RoutedEventArgs e)
        {
            FlushProviderFields(_currentKey);

            var hotkey = HotkeyBox.Text.Trim();
            if (!HotKeyManager.TryParse(hotkey, out _, out _))
            {
                System.Windows.MessageBox.Show(this,
                    "熱鍵格式無效。需要至少一個修飾鍵（Ctrl/Alt/Shift/Win）加一個按鍵，例如 Ctrl+Alt+Z。",
                    "設定", MessageBoxButton.OK, MessageBoxImage.Warning);
                HotkeyBox.Focus();
                return;
            }

            foreach (var kv in _work)
            {
                if (!App.Config.Providers.TryGetValue(kv.Key, out var dst))
                {
                    dst = new ProviderConfig();
                    App.Config.Providers[kv.Key] = dst;
                }
                dst.ApiKey = kv.Value.ApiKey;
                dst.BaseUrl = kv.Value.BaseUrl;
                dst.Model = kv.Value.Model;
            }

            App.Config.Provider = _currentKey;
            App.Config.Hotkey = hotkey;
            App.Config.AutoTranslate = AutoTranslateBox.IsChecked == true;
            SetStartup(StartupBox.IsChecked == true);

            var prompt = PromptBox.Text.Trim();
            App.Config.PromptTemplate = prompt.Length > 0 ? prompt : AppConfig.DefaultPromptTemplate;

            if (_scaleTouched && ScaleBox.SelectedValue is string scaleStr &&
                double.TryParse(scaleStr, NumberStyles.Float, CultureInfo.InvariantCulture, out var scale))
                App.Config.UiScale = scale;

            if (_fontTouched && FontSizeBox.SelectedValue is string fontStr &&
                double.TryParse(fontStr, NumberStyles.Float, CultureInfo.InvariantCulture, out var font))
                App.Config.ContentFontSize = font;

            App.Config.EnsureDefaults();
            App.Config.Save();

            if (!App.ApplyHotkey())
            {
                System.Windows.MessageBox.Show(this,
                    "設定已儲存，但全域熱鍵註冊失敗（可能已被其他程式占用）。請改用其他組合。",
                    "設定", MessageBoxButton.OK, MessageBoxImage.Warning);
            }

            DialogResult = true;
            Close();
        }

        private void Cancel_Click(object sender, RoutedEventArgs e)
        {
            DialogResult = false;
            Close();
        }
    }
}
