using System;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;

namespace NextAITranslator.Interop
{
    /// <summary>Switches a window's OS title bar to dark mode (Windows 10 1809+).</summary>
    public static class DarkTitleBar
    {
        private const int DWMWA_USE_IMMERSIVE_DARK_MODE = 20;

        [DllImport("dwmapi.dll")]
        private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);

        public static void Apply(Window window)
        {
            void Set()
            {
                var hwnd = new WindowInteropHelper(window).Handle;
                if (hwnd == IntPtr.Zero) return;
                int on = 1;
                try { DwmSetWindowAttribute(hwnd, DWMWA_USE_IMMERSIVE_DARK_MODE, ref on, sizeof(int)); }
                catch { /* older Windows: ignore */ }
            }

            if (new WindowInteropHelper(window).Handle != IntPtr.Zero)
                Set();
            else
                window.SourceInitialized += (_, _) => Set();
        }
    }
}
