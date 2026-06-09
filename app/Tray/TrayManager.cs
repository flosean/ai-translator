using System;
using System.Drawing;
using System.Windows.Forms;

namespace NextAITranslator.Tray
{
    /// <summary>
    /// System-tray presence for the app: an icon, a context menu, and double-click to open.
    /// </summary>
    public sealed class TrayManager : IDisposable
    {
        private readonly NotifyIcon _icon;
        private readonly MainWindow _window;

        public TrayManager(MainWindow window)
        {
            _window = window;

            _icon = new NotifyIcon
            {
                Icon = LoadAppIcon(),
                Text = "NextAI 翻譯",
                Visible = true,
            };

            var menu = new ContextMenuStrip();
            menu.Items.Add("顯示翻譯視窗", null, (_, _) => _window.ShowAndFocus());
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add("結束", null, (_, _) => Exit());
            _icon.ContextMenuStrip = menu;

            _icon.DoubleClick += (_, _) => _window.ShowAndFocus();
        }

        private void Exit()
        {
            _icon.Visible = false;
            _window.ExitForReal();
            System.Windows.Application.Current.Shutdown();
        }

        private static Icon LoadAppIcon()
        {
            try
            {
                var uri = new Uri("pack://application:,,,/Assets/app.ico");
                var stream = System.Windows.Application.GetResourceStream(uri)?.Stream;
                if (stream != null)
                    return new Icon(stream);
            }
            catch { /* fall back below */ }
            return SystemIcons.Application;
        }

        public void Dispose()
        {
            _icon.Visible = false;
            _icon.Dispose();
        }
    }
}
