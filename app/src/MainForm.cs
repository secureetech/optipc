using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading.Tasks;
using System.Web.Script.Serialization;
using System.Windows.Forms;
using Microsoft.Web.WebView2.Core;
using Microsoft.Web.WebView2.WinForms;

namespace OptiPC
{
    /// <summary>
    /// Fenetre principale : sans cadre Windows, avec la barre stylisee d'OptiPC dessinee
    /// par l'interface. Le redimensionnement, l'ombre, l'ancrage (Aero Snap), la reduction
    /// et l'agrandissement restent geres par Windows.
    /// </summary>
    internal sealed class MainForm : Form
    {
        public const string Host = "optipc.local";
        const int Border = 5;

        readonly OptiApp _app;
        readonly Engine _engine;
        WebView2 _web;
        CoreWebView2Environment _env;
        bool _allowClose;
        bool _dark = true;
        Color _barColor = ColorTranslator.FromHtml("#0E0F14");
        Color _edgeColor = ColorTranslator.FromHtml("#252935");
        static readonly JavaScriptSerializer Json = new JavaScriptSerializer { MaxJsonLength = int.MaxValue };

        public MainForm(OptiApp app, Engine engine)
        {
            _app = app;
            _engine = engine;
            Text = "OptiPC";
            try { Icon = OptiApp.LoadAppIcon(); } catch { }
            FormBorderStyle = FormBorderStyle.Sizable;
            StartPosition = FormStartPosition.Manual;
            BackColor = _edgeColor;
            DoubleBuffered = true;
            AutoScaleMode = AutoScaleMode.Dpi;
            Padding = new Padding(Border, Border - 1, Border, Border);
            RestoreBounds_();

            _web = new WebView2 { Dock = DockStyle.Fill, DefaultBackgroundColor = ColorTranslator.FromHtml("#0B0C10") };
            Controls.Add(_web);
            Load += async (s, e) => await InitWebAsync();
            Resize += (s, e) => { UpdatePadding(); PostMaxState(); };
            FormClosing += OnFormClosing;
        }

        // ── Cadre personnalise ─────────────────────────────────────────────────
        protected override CreateParams CreateParams
        {
            get
            {
                var cp = base.CreateParams;
                cp.Style |= Native.WS_THICKFRAME | Native.WS_MINIMIZEBOX | Native.WS_MAXIMIZEBOX | Native.WS_SYSMENU;
                cp.Style &= ~Native.WS_CAPTION;
                return cp;
            }
        }

        protected override void OnHandleCreated(EventArgs e)
        {
            base.OnHandleCreated(e);
            try
            {
                var m = new Native.MARGINS { Left = 0, Right = 0, Top = 0, Bottom = 1 };
                Native.DwmExtendFrameIntoClientArea(Handle, ref m);
                int round = 2; // Windows 11 : coins arrondis
                Native.DwmSetWindowAttribute(Handle, 33, ref round, sizeof(int));
            }
            catch { }
        }

        protected override void WndProc(ref Message m)
        {
            if (m.Msg == Native.WM_NCCALCSIZE && m.WParam != IntPtr.Zero)
            {
                if (WindowState == FormWindowState.Maximized)
                {
                    var p = (Native.NCCALCSIZE_PARAMS)Marshal.PtrToStructure(m.LParam, typeof(Native.NCCALCSIZE_PARAMS));
                    int fx = Native.GetSystemMetrics(Native.SM_CXFRAME) + Native.GetSystemMetrics(Native.SM_CXPADDEDBORDER);
                    int fy = Native.GetSystemMetrics(Native.SM_CYFRAME) + Native.GetSystemMetrics(Native.SM_CXPADDEDBORDER);
                    p.rgrc0.Left += fx; p.rgrc0.Right -= fx; p.rgrc0.Top += fy; p.rgrc0.Bottom -= fy;
                    Marshal.StructureToPtr(p, m.LParam, false);
                }
                m.Result = IntPtr.Zero;
                return;
            }
            if (m.Msg == Native.WM_GETMINMAXINFO)
            {
                // Fenetre sans cadre : sans ceci, « Agrandir » recouvre la barre des taches.
                base.WndProc(ref m);
                try
                {
                    var mon = Native.MonitorFromWindow(Handle, 2 /* MONITOR_DEFAULTTONEAREST */);
                    var mi = new Native.MONITORINFO { cbSize = Marshal.SizeOf(typeof(Native.MONITORINFO)) };
                    if (mon != IntPtr.Zero && Native.GetMonitorInfo(mon, ref mi))
                    {
                        var mmi = (Native.MINMAXINFO)Marshal.PtrToStructure(m.LParam, typeof(Native.MINMAXINFO));
                        int fx = Native.GetSystemMetrics(Native.SM_CXFRAME) + Native.GetSystemMetrics(Native.SM_CXPADDEDBORDER);
                        int fy = Native.GetSystemMetrics(Native.SM_CYFRAME) + Native.GetSystemMetrics(Native.SM_CXPADDEDBORDER);
                        var w = mi.rcWork; var mo = mi.rcMonitor;
                        int workH = w.Bottom - w.Top;
                        // Barre des taches masquee automatiquement : on laisse 1 pixel pour qu'elle puisse apparaitre.
                        if (w.Left == mo.Left && w.Top == mo.Top && w.Right == mo.Right && w.Bottom == mo.Bottom) workH -= 1;
                        mmi.ptMaxPosition.X = w.Left - mo.Left - fx;
                        mmi.ptMaxPosition.Y = w.Top - mo.Top - fy;
                        mmi.ptMaxSize.X = (w.Right - w.Left) + 2 * fx;
                        mmi.ptMaxSize.Y = workH + 2 * fy;
                        if (mmi.ptMaxTrackSize.X < mmi.ptMaxSize.X) mmi.ptMaxTrackSize.X = mmi.ptMaxSize.X;
                        if (mmi.ptMaxTrackSize.Y < mmi.ptMaxSize.Y) mmi.ptMaxTrackSize.Y = mmi.ptMaxSize.Y;
                        Marshal.StructureToPtr(mmi, m.LParam, false);
                    }
                }
                catch { }
                m.Result = IntPtr.Zero;
                return;
            }
            if (m.Msg == Native.WM_NCHITTEST)
            {
                base.WndProc(ref m);
                if (WindowState == FormWindowState.Normal)
                {
                    var pt = PointToClient(new Point(unchecked((short)(long)m.LParam), unchecked((short)((long)m.LParam >> 16))));
                    int b = Border + 2;
                    bool l = pt.X < b, r = pt.X >= ClientSize.Width - b, t = pt.Y < b, bo = pt.Y >= ClientSize.Height - b;
                    int ht = 0;
                    if (t && l) ht = Native.HTTOPLEFT; else if (t && r) ht = Native.HTTOPRIGHT;
                    else if (bo && l) ht = Native.HTBOTTOMLEFT; else if (bo && r) ht = Native.HTBOTTOMRIGHT;
                    else if (l) ht = Native.HTLEFT; else if (r) ht = Native.HTRIGHT;
                    else if (t) ht = Native.HTTOP; else if (bo) ht = Native.HTBOTTOM;
                    if (ht != 0) m.Result = (IntPtr)ht;
                }
                return;
            }
            base.WndProc(ref m);
        }

        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            if (Padding.All == 0 && Padding.Top == 0) return;
            using (var edge = new SolidBrush(_edgeColor))
            using (var bar = new SolidBrush(_barColor))
            {
                e.Graphics.FillRectangle(edge, ClientRectangle);
                e.Graphics.FillRectangle(bar, 0, 0, ClientSize.Width, Math.Max(Padding.Top, 1));
            }
        }

        FormWindowState _lastState = FormWindowState.Normal;
        void PostMaxState()
        {
            if (WindowState == _lastState || WindowState == FormWindowState.Minimized) return;
            _lastState = WindowState;
            try
            {
                if (_web != null && _web.CoreWebView2 != null)
                    _web.CoreWebView2.PostWebMessageAsJson("{\"cmd\":\"maxstate\",\"max\":" + (WindowState == FormWindowState.Maximized ? "true" : "false") + "}");
            }
            catch { }
        }

        void UpdatePadding()
        {
            var want = WindowState == FormWindowState.Maximized ? new Padding(0) : new Padding(Border, Border - 1, Border, Border);
            if (Padding != want) { Padding = want; Invalidate(); }
        }

        void SetThemeColors(bool dark)
        {
            _dark = dark;
            _barColor = ColorTranslator.FromHtml("#0E0F14");
            _edgeColor = ColorTranslator.FromHtml(dark ? "#252935" : "#DAD6DF");
            BackColor = _edgeColor;
            try { _web.DefaultBackgroundColor = ColorTranslator.FromHtml(dark ? "#0B0C10" : "#F3F2EF"); } catch { }
            Invalidate();
        }

        // ── Position et taille memorisees ──────────────────────────────────────
        string WindowFile { get { return Path.Combine(Log.DataDir, "window.json"); } }

        void RestoreBounds_()
        {
            var wa = Screen.PrimaryScreen.WorkingArea;
            int w = Math.Min(1440, (int)(wa.Width * 0.92)), h = Math.Min(900, (int)(wa.Height * 0.92));
            MinimumSize = new Size(Math.Min(1040, wa.Width), Math.Min(660, wa.Height));
            var rect = new Rectangle(wa.Left + (wa.Width - w) / 2, wa.Top + (wa.Height - h) / 2, w, h);
            bool max = false;
            try
            {
                if (File.Exists(WindowFile))
                {
                    var d = Json.Deserialize<System.Collections.Generic.Dictionary<string, object>>(File.ReadAllText(WindowFile));
                    var r = new Rectangle(Convert.ToInt32(d["x"]), Convert.ToInt32(d["y"]), Convert.ToInt32(d["w"]), Convert.ToInt32(d["h"]));
                    foreach (var s in Screen.AllScreens)
                        if (s.WorkingArea.IntersectsWith(r) && r.Width >= 600 && r.Height >= 400) { rect = r; break; }
                    max = d.ContainsKey("max") && Convert.ToBoolean(d["max"]);
                }
            }
            catch { }
            Bounds = rect;
            if (max) WindowState = FormWindowState.Maximized;
        }

        void SaveBounds()
        {
            try
            {
                var r = WindowState == FormWindowState.Normal ? Bounds : RestoreBounds;
                File.WriteAllText(WindowFile, Json.Serialize(new { x = r.X, y = r.Y, w = r.Width, h = r.Height, max = WindowState == FormWindowState.Maximized }));
            }
            catch { }
        }

        // ── Fermeture : la croix garde OptiPC actif pres de l'horloge ──────────
        void OnFormClosing(object sender, FormClosingEventArgs e)
        {
            SaveBounds();
            if (!_allowClose && e.CloseReason == CloseReason.UserClosing)
            {
                e.Cancel = true;
                Hide();
                return;
            }
        }

        public void CloseForReal()
        {
            _allowClose = true;
            SaveBounds();
            try { Close(); } catch { }
        }

        public void BringToFront_()
        {
            if (!Visible) Show();
            if (WindowState == FormWindowState.Minimized) WindowState = FormWindowState.Normal;
            Activate();
            try { Native.SetForegroundWindow(Handle); } catch { }
        }

        // ── WebView2 ───────────────────────────────────────────────────────────
        async Task InitWebAsync()
        {
            try
            {
                var exeDir = Path.GetDirectoryName(Application.ExecutablePath);
                if (!File.Exists(Path.Combine(exeDir, "WebView2Loader.dll")))
                {
                    var loaderDir = Deps.Dir != null && File.Exists(Path.Combine(Deps.Dir, "WebView2Loader.dll")) ? Deps.Dir : Path.Combine(exeDir, "runtimes", "win-x64", "native");
                    CoreWebView2Environment.SetLoaderDllFolderPath(loaderDir);
                }
            }
            catch { }
            try
            {
                CoreWebView2Environment.GetAvailableBrowserVersionString();
            }
            catch (Exception)
            {
                MessageBox.Show(this,
                    "OptiPC a besoin du composant Microsoft Edge WebView2, absent de ce PC.\r\n\r\n" +
                    "La page de téléchargement officielle de Microsoft va s'ouvrir : installez « Evergreen Bootstrapper », puis relancez OptiPC.\r\n\r\n" +
                    "Besoin d'aide : 05 54 54 23 43",
                    "OptiPC", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                try { Process.Start("https://developer.microsoft.com/microsoft-edge/webview2/"); } catch { }
                return;
            }
            try
            {
                var udf = Path.Combine(Log.DataDir, "WebView2");
                var opts = new CoreWebView2EnvironmentOptions();
                _env = await CoreWebView2Environment.CreateAsync(null, udf, opts);
                await _web.EnsureCoreWebView2Async(_env);
                var core = _web.CoreWebView2;
                var st = core.Settings;
                bool debug = Environment.GetEnvironmentVariable("OPTIPC_DEBUG") == "1";
                st.AreDevToolsEnabled = debug;
                st.AreDefaultContextMenusEnabled = debug;
                st.IsStatusBarEnabled = false;
                st.IsZoomControlEnabled = false;
                st.AreBrowserAcceleratorKeysEnabled = debug;
                st.IsGeneralAutofillEnabled = false;
                st.IsPasswordAutosaveEnabled = false;
                try { st.IsNonClientRegionSupportEnabled = true; } catch { }

                core.AddWebResourceRequestedFilter("https://" + Host + "/*", CoreWebView2WebResourceContext.All);
                core.WebResourceRequested += OnWebResourceRequested;
                core.WebMessageReceived += OnWebMessage;
                core.NewWindowRequested += (s, e) => { e.Handled = true; OpenExternal(e.Uri); };
                core.NavigationStarting += (s, e) =>
                {
                    Uri u;
                    if (Uri.TryCreate(e.Uri, UriKind.Absolute, out u) && !string.Equals(u.Host, Host, StringComparison.OrdinalIgnoreCase) && u.Scheme != "about" && u.Scheme != "data")
                    {
                        e.Cancel = true;
                        OpenExternal(e.Uri);
                    }
                };
                core.ProcessFailed += (s, e) =>
                {
                    Log.Write("WebView2 ProcessFailed : " + e.ProcessFailedKind);
                    try { if (e.ProcessFailedKind == CoreWebView2ProcessFailedKind.RenderProcessExited || e.ProcessFailedKind == CoreWebView2ProcessFailedKind.RenderProcessUnresponsive) core.Reload(); } catch { }
                };
                core.NavigationCompleted += (s2, e2) => { _lastState = FormWindowState.Normal; PostMaxState(); };
                core.Navigate("https://" + Host + "/index.html");
            }
            catch (Exception ex)
            {
                Log.Error("Initialisation WebView2", ex);
                MessageBox.Show(this, "OptiPC n'a pas pu afficher son interface : " + ex.Message + "\r\n\r\nBesoin d'aide : 05 54 54 23 43", "OptiPC", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }

        static void OpenExternal(string url)
        {
            try
            {
                Uri u;
                if (Uri.TryCreate(url, UriKind.Absolute, out u) && (u.Scheme == "https" || u.Scheme == "http" || u.Scheme == "mailto" || u.Scheme == "tel"))
                {
                    // Passer par l'Explorateur : le navigateur s'ouvre avec les droits normaux de
                    // l'utilisateur, et non avec les droits administrateur d'OptiPC.
                    try { Process.Start(new ProcessStartInfo("explorer.exe", "\"" + u.AbsoluteUri + "\"") { UseShellExecute = false }); }
                    catch { Process.Start(new ProcessStartInfo(u.AbsoluteUri) { UseShellExecute = true }); }
                }
            }
            catch { }
        }

        void OnWebMessage(object sender, CoreWebView2WebMessageReceivedEventArgs e)
        {
            try
            {
                var d = Json.Deserialize<System.Collections.Generic.Dictionary<string, object>>(e.WebMessageAsJson);
                var cmd = d.ContainsKey("cmd") ? Convert.ToString(d["cmd"]) : "";
                switch (cmd)
                {
                    case "drag":
                        if (WindowState == FormWindowState.Maximized) break;
                        Native.ReleaseCapture();
                        Native.SendMessage(Handle, Native.WM_NCLBUTTONDOWN, (IntPtr)Native.HTCAPTION, IntPtr.Zero);
                        break;
                    case "min": WindowState = FormWindowState.Minimized; break;
                    case "max": WindowState = WindowState == FormWindowState.Maximized ? FormWindowState.Normal : FormWindowState.Maximized; break;
                    case "close": Close(); break;
                    case "quit": _app.Quit(); break;
                    case "theme":
                        SetThemeColors(d.ContainsKey("dark") && Convert.ToBoolean(d["dark"]));
                        break;
                }
            }
            catch (Exception ex) { Log.Error("Message interface", ex); }
        }

        async void OnWebResourceRequested(object sender, CoreWebView2WebResourceRequestedEventArgs e)
        {
            var deferral = e.GetDeferral();
            try
            {
                var uri = new Uri(e.Request.Uri);
                var path = uri.AbsolutePath;
                if (path.StartsWith("/api/", StringComparison.OrdinalIgnoreCase))
                {
                    string body = null;
                    try
                    {
                        if (e.Request.Content != null)
                            using (var sr = new StreamReader(e.Request.Content, Encoding.UTF8)) body = sr.ReadToEnd();
                    }
                    catch { }
                    RouteResult rr;
                    if (path == "/api/browse") rr = await BrowseAsync(ParseQuery(uri.Query, "type"));
                    else if (path == "/api/app/info") rr = new RouteResult { Status = 200, Json = Json.Serialize(AppInfo()) };
                    else if (path == "/api/quit") { rr = new RouteResult { Status = 200, Json = "{\"ok\":true}" }; BeginInvoke(new Action(() => _app.Quit())); }
                    else rr = await _engine.CallAsync(path, e.Request.Method, body, uri.Query);
                    var bytes = Encoding.UTF8.GetBytes(rr.Json ?? "null");
                    e.Response = _env.CreateWebResourceResponse(new MemoryStream(bytes), rr.Status, rr.Status == 200 ? "OK" : "Error",
                        "Content-Type: application/json; charset=utf-8\r\nCache-Control: no-store");
                }
                else
                {
                    var name = path.TrimStart('/');
                    if (name.Length == 0) name = "index.html";
                    var res = GetUiResource(name);
                    if (res == null)
                        e.Response = _env.CreateWebResourceResponse(null, 404, "Not Found", "");
                    else
                        e.Response = _env.CreateWebResourceResponse(new MemoryStream(res), 200, "OK",
                            "Content-Type: " + Mime(name) + "\r\nCache-Control: no-store");
                }
            }
            catch (Exception ex)
            {
                Log.Error("Requete interface", ex);
                try { e.Response = _env.CreateWebResourceResponse(new MemoryStream(Encoding.UTF8.GetBytes("{\"error\":\"erreur_interne\"}")), 500, "Error", "Content-Type: application/json"); } catch { }
            }
            finally { deferral.Complete(); }
        }

        static string ParseQuery(string q, string key)
        {
            if (string.IsNullOrEmpty(q)) return "";
            foreach (var kv in q.TrimStart('?').Split('&'))
            {
                var p = kv.Split(new[] { '=' }, 2);
                if (p.Length == 2 && Uri.UnescapeDataString(p[0]) == key) return Uri.UnescapeDataString(p[1]);
            }
            return "";
        }

        object AppInfo()
        {
            var exe = Application.ExecutablePath;
            var pf = Environment.GetFolderPath(Environment.SpecialFolder.ProgramFiles);
            return new
            {
                version = Application.ProductVersion,
                exe = exe,
                installed = exe.StartsWith(pf + "\\", StringComparison.OrdinalIgnoreCase),
                engineReady = _engine.IsReady,
                engineError = _engine.StartError
            };
        }

        Task<RouteResult> BrowseAsync(string kind)
        {
            var tcs = new TaskCompletionSource<RouteResult>();
            BeginInvoke(new Action(() =>
            {
                string res = null;
                try
                {
                    if (kind == "file")
                    {
                        using (var d = new OpenFileDialog { Title = "OptiPC - Sélectionnez un fichier", Filter = "Tous les fichiers (*.*)|*.*", CheckFileExists = true, InitialDirectory = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile) })
                            if (d.ShowDialog(this) == DialogResult.OK) res = d.FileName;
                    }
                    else
                    {
                        using (var d = new FolderBrowserDialog { Description = kind == "dest" ? "OptiPC - Choisissez où déplacer les fichiers (clé USB, disque externe...)" : "OptiPC - Sélectionnez un dossier", ShowNewFolderButton = kind == "dest", SelectedPath = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile) })
                            if (d.ShowDialog(this) == DialogResult.OK) res = d.SelectedPath;
                    }
                }
                catch (Exception ex) { Log.Error("Selecteur", ex); }
                var json = res == null ? "{\"success\":false,\"cancelled\":true}" : Json.Serialize(new { success = true, path = res });
                tcs.TrySetResult(new RouteResult { Status = 200, Json = json });
            }));
            return tcs.Task;
        }

        static byte[] GetUiResource(string name)
        {
            if (name.Contains("..")) return null;
            var asm = Assembly.GetExecutingAssembly();
            using (var s = asm.GetManifestResourceStream("ui/" + name))
            {
                if (s == null) return null;
                using (var ms = new MemoryStream()) { s.CopyTo(ms); return ms.ToArray(); }
            }
        }

        static string Mime(string name)
        {
            var ext = Path.GetExtension(name).ToLowerInvariant();
            switch (ext)
            {
                case ".html": return "text/html; charset=utf-8";
                case ".css": return "text/css; charset=utf-8";
                case ".js": return "application/javascript; charset=utf-8";
                case ".png": return "image/png";
                case ".svg": return "image/svg+xml";
                case ".ico": return "image/x-icon";
                case ".woff2": return "font/woff2";
                default: return "application/octet-stream";
            }
        }
    }
}
