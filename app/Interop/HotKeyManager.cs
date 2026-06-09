using System;
using System.Runtime.InteropServices;
using System.Windows.Forms;
using System.Windows.Interop;

namespace NextAITranslator.Interop
{
    /// <summary>
    /// Registers a single global hotkey on a WPF window's HWND and raises
    /// <see cref="Pressed"/> when it fires. Re-registerable at runtime.
    /// </summary>
    public sealed class HotKeyManager : IDisposable
    {
        private const int WM_HOTKEY = 0x0312;
        private const int HOTKEY_ID = 0xB001;

        [Flags]
        private enum Mods : uint
        {
            None = 0,
            Alt = 0x0001,
            Control = 0x0002,
            Shift = 0x0004,
            Win = 0x0008,
            NoRepeat = 0x4000,
        }

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);

        [DllImport("user32.dll", SetLastError = true)]
        private static extern bool UnregisterHotKey(IntPtr hWnd, int id);

        private readonly IntPtr _hwnd;
        private readonly HwndSource _source;
        private bool _registered;

        public event Action? Pressed;

        public HotKeyManager(IntPtr hwnd)
        {
            _hwnd = hwnd;
            _source = HwndSource.FromHwnd(hwnd)
                      ?? throw new InvalidOperationException("Window handle has no HwndSource.");
            _source.AddHook(WndProc);
        }

        private IntPtr WndProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
        {
            if (msg == WM_HOTKEY && wParam.ToInt32() == HOTKEY_ID)
            {
                Pressed?.Invoke();
                handled = true;
            }
            return IntPtr.Zero;
        }

        /// <summary>
        /// Register the given hotkey string (e.g. "Ctrl+Alt+Z").
        /// Returns true on success. Any previous registration is cleared first.
        /// </summary>
        public bool Register(string hotkey)
        {
            Unregister();

            if (!TryParse(hotkey, out var mods, out var vk))
                return false;

            _registered = RegisterHotKey(_hwnd, HOTKEY_ID, mods | (uint)Mods.NoRepeat, vk);
            return _registered;
        }

        public void Unregister()
        {
            if (_registered)
            {
                UnregisterHotKey(_hwnd, HOTKEY_ID);
                _registered = false;
            }
        }

        /// <summary>
        /// Parse "Ctrl+Alt+Z" / "Win+Shift+F5" / "Ctrl+Alt+1" into modifiers + virtual-key code.
        /// </summary>
        public static bool TryParse(string hotkey, out uint modifiers, out uint vk)
        {
            modifiers = 0;
            vk = 0;
            if (string.IsNullOrWhiteSpace(hotkey)) return false;

            Mods mods = Mods.None;
            string? keyToken = null;

            foreach (var raw in hotkey.Split('+'))
            {
                var t = raw.Trim();
                if (t.Length == 0) continue;

                switch (t.ToLowerInvariant())
                {
                    case "ctrl":
                    case "control":
                        mods |= Mods.Control; break;
                    case "alt":
                        mods |= Mods.Alt; break;
                    case "shift":
                        mods |= Mods.Shift; break;
                    case "win":
                    case "windows":
                    case "meta":
                        mods |= Mods.Win; break;
                    default:
                        keyToken = t; break; // last non-modifier token wins
                }
            }

            if (keyToken == null) return false;

            // Single digit -> Keys.D0..D9
            if (keyToken.Length == 1 && char.IsDigit(keyToken[0]))
                keyToken = "D" + keyToken;

            if (!Enum.TryParse<Keys>(keyToken, ignoreCase: true, out var key))
                return false;

            modifiers = (uint)mods;
            vk = (uint)key;
            return modifiers != 0 && vk != 0;
        }

        public void Dispose()
        {
            Unregister();
            _source.RemoveHook(WndProc);
        }
    }
}
