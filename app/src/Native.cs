using System;
using System.Runtime.InteropServices;
using System.Text;

namespace OptiPC
{
    internal static class Native
    {
        public const int WM_NCCALCSIZE = 0x0083;
        public const int WM_NCHITTEST = 0x0084;
        public const int WM_NCLBUTTONDOWN = 0x00A1;
        public const int WM_SYSCOMMAND = 0x0112;
        public const int WM_GETMINMAXINFO = 0x0024;

        public const int HTCLIENT = 1;
        public const int HTCAPTION = 2;
        public const int HTLEFT = 10, HTRIGHT = 11, HTTOP = 12, HTTOPLEFT = 13, HTTOPRIGHT = 14;
        public const int HTBOTTOM = 15, HTBOTTOMLEFT = 16, HTBOTTOMRIGHT = 17;

        public const int WS_CAPTION = 0x00C00000;
        public const int WS_THICKFRAME = 0x00040000;
        public const int WS_MINIMIZEBOX = 0x00020000;
        public const int WS_MAXIMIZEBOX = 0x00010000;
        public const int WS_SYSMENU = 0x00080000;
        public const int CS_DROPSHADOW = 0x00020000;

        public const int SM_CXFRAME = 32, SM_CYFRAME = 33, SM_CXPADDEDBORDER = 92;

        [StructLayout(LayoutKind.Sequential)]
        public struct RECT { public int Left, Top, Right, Bottom; }

        [StructLayout(LayoutKind.Sequential)]
        public struct NCCALCSIZE_PARAMS
        {
            public RECT rgrc0, rgrc1, rgrc2;
            public IntPtr lppos;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct MARGINS { public int Left, Right, Top, Bottom; }

        [StructLayout(LayoutKind.Sequential)]
        public struct POINT { public int X, Y; }

        [StructLayout(LayoutKind.Sequential)]
        public struct MINMAXINFO { public POINT ptReserved, ptMaxSize, ptMaxPosition, ptMinTrackSize, ptMaxTrackSize; }

        [StructLayout(LayoutKind.Sequential)]
        public struct MONITORINFO { public int cbSize; public RECT rcMonitor, rcWork; public int dwFlags; }

        [DllImport("user32.dll")] public static extern IntPtr MonitorFromWindow(IntPtr hwnd, int flags);
        [DllImport("user32.dll")] public static extern bool GetMonitorInfo(IntPtr hMonitor, ref MONITORINFO lpmi);

        [DllImport("user32.dll")] public static extern bool ReleaseCapture();
        [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr wParam, IntPtr lParam);
        [DllImport("user32.dll")] public static extern int GetSystemMetrics(int index);
        [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
        [DllImport("dwmapi.dll")] public static extern int DwmExtendFrameIntoClientArea(IntPtr hWnd, ref MARGINS margins);
        [DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        public static extern int GetLongPathName(string shortPath, StringBuilder longPath, int bufferLength);

        /// <summary>
        /// Sur certains postes, Windows fournit USERPROFILE/APPDATA en forme courte (C:\Users\CCILE~1)
        /// quand le programme est lance en administrateur. Meme correctif que la V1.
        /// </summary>
        public static void FixShortPathEnvironment()
        {
            foreach (var name in new[] { "USERPROFILE", "LOCALAPPDATA", "APPDATA", "TEMP", "TMP", "ProgramData" })
            {
                try
                {
                    var cur = Environment.GetEnvironmentVariable(name);
                    if (string.IsNullOrEmpty(cur) || cur.IndexOf('~') < 0) continue;
                    var sb = new StringBuilder(1024);
                    int len = GetLongPathName(cur, sb, sb.Capacity);
                    if (len > 0 && len <= sb.Capacity)
                    {
                        var lng = sb.ToString(0, len);
                        if (!string.Equals(lng, cur, StringComparison.Ordinal) && System.IO.Directory.Exists(lng))
                            Environment.SetEnvironmentVariable(name, lng, EnvironmentVariableTarget.Process);
                    }
                }
                catch { }
            }
        }
    }
}
