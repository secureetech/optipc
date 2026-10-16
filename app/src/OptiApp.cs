using System;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Management.Automation;
using System.Reflection;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;

namespace OptiPC
{
    /// <summary>
    /// Cycle de vie d'OptiPC : icone pres de l'horloge, fenetre, moteur, planification
    /// du nettoyage et rappels hebdomadaires. OptiPC reste actif quand la fenetre est fermee ;
    /// seul « Quitter OptiPC » l'arrete.
    /// </summary>
    internal sealed class OptiApp : ApplicationContext
    {
        public const string ShowEventName = "Local\\OptiPC2_ShowWindow";

        readonly Engine _engine = new Engine();
        readonly NotifyIcon _tray;
        readonly System.Windows.Forms.Timer _timer;
        readonly Control _ui;
        readonly DateTime _started = DateTime.Now;
        MainForm _form;
        bool _quitting;
        int _tickBusy;
        bool _balloonOpensWindow;
        DateTime _nextSchedule = DateTime.Now.AddSeconds(5);
        DateTime _nextNudge = DateTime.Now.AddMinutes(10);
        EventWaitHandle _showEvent;

        public OptiApp(bool atLogon, bool silent)
        {
            _ui = new Control();
            _ui.CreateControl(); // marshaling vers le fil de l'interface

            _engine.StartAsync();

            _tray = new NotifyIcon { Text = "OptiPC - Actif", Visible = true };
            try { _tray.Icon = new Icon(LoadAppIcon(), SystemInformation.SmallIconSize); } catch { _tray.Icon = SystemIcons.Application; }
            var menu = new ContextMenuStrip();
            menu.Items.Add("Ouvrir OptiPC", null, (s, e) => ShowMain());
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add("Quitter OptiPC", null, (s, e) => Quit());
            _tray.ContextMenuStrip = menu;
            _tray.DoubleClick += (s, e) => ShowMain();
            _tray.BalloonTipClicked += (s, e) => { if (_balloonOpensWindow) ShowMain(); _balloonOpensWindow = false; };
            _tray.BalloonTipClosed += (s, e) => _balloonOpensWindow = false;

            // Un second lancement d'OptiPC (raccourci, menu Demarrer) affiche simplement la fenetre.
            _showEvent = new EventWaitHandle(false, EventResetMode.AutoReset, ShowEventName);
            var waiter = new Thread(() =>
            {
                while (!_quitting)
                {
                    try { if (_showEvent.WaitOne(1000) && !_quitting) _ui.BeginInvoke(new Action(ShowMain)); }
                    catch { Thread.Sleep(1000); }
                }
            }) { IsBackground = true, Name = "OptiPC-Show" };
            waiter.Start();

            // Un ancien signal « quitter » (laissé par la mise à jour qui vient de nous installer) ne doit pas nous fermer.
            try { var qf = Path.Combine(Path.GetTempPath(), "optipc_quit.flag"); if (File.Exists(qf)) File.Delete(qf); } catch { }
            _timer = new System.Windows.Forms.Timer { Interval = 1000 };
            _timer.Tick += OnTick;
            _timer.Start();

            // Inscription au demarrage de Windows (version installee uniquement).
            Task.Run(() =>
            {
                try { _engine.RunScript("param($e) Register-OptiStartup $e | Out-Null", Application.ExecutablePath); }
                catch (Exception ex) { Log.Error("Inscription au demarrage", ex); }
            });

            if (silent)
            {
                Task.Run(() => RunSilentClean());
            }
            else if (!(atLogon && !GetSetting("openAtStartup", true)))
            {
                ShowMain();
            }

            if (atLogon && GetSetting("notifStartup", true))
                ShowBalloon("OptiPC", "OptiPC veille sur votre PC. Double-cliquez sur son icône pour l'ouvrir.", ToolTipIcon.Info, false);
        }

        public static Icon LoadAppIcon()
        {
            using (var s = Assembly.GetExecutingAssembly().GetManifestResourceStream("assets/optipc.ico"))
                return new Icon(s);
        }

        static bool GetSetting(string key, bool def)
        {
            try
            {
                var f = Path.Combine(Log.DataDir, "settings.json");
                if (!File.Exists(f)) return def;
                var d = new System.Web.Script.Serialization.JavaScriptSerializer().Deserialize<System.Collections.Generic.Dictionary<string, object>>(File.ReadAllText(f));
                if (d != null && d.ContainsKey(key) && d[key] != null) return Convert.ToBoolean(d[key]);
            }
            catch { }
            return def;
        }

        public void ShowMain()
        {
            if (_quitting) return;
            try
            {
                if (_form == null || _form.IsDisposed)
                {
                    _form = new MainForm(this, _engine);
                    _form.Show();
                }
                _form.BringToFront_();
            }
            catch (Exception ex)
            {
                Log.Error("Ouverture de la fenetre", ex);
                _form = null;
                MessageBox.Show("OptiPC n'a pas pu ouvrir sa fenêtre.\n\n" + ex.Message + "\n\nAppelez SecureeTech au 05 54 54 23 43, nous réglons cela avec vous.", "OptiPC", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
        }

        void ShowBalloon(string title, string text, ToolTipIcon icon, bool opensWindow)
        {
            try
            {
                _balloonOpensWindow = opensWindow;
                _tray.ShowBalloonTip(10000, title, text, icon);
            }
            catch { }
        }

        void OnTick(object sender, EventArgs e)
        {
            // Mise a jour installee : le moteur depose un drapeau, on se ferme pour laisser l'installateur travailler.
            try
            {
                var quitFlag = Path.Combine(Path.GetTempPath(), "optipc_quit.flag");
                if (File.Exists(quitFlag)) { File.Delete(quitFlag); Quit(); return; }
            }
            catch { }

            var now = DateTime.Now;
            if (now >= _nextSchedule && Interlocked.CompareExchange(ref _tickBusy, 1, 0) == 0)
            {
                _nextSchedule = now.AddSeconds(60);
                bool nudgeDue = now >= _nextNudge;
                if (nudgeDue) _nextNudge = now.AddHours(1);
                Task.Run(() =>
                {
                    try
                    {
                        var r = _engine.RunScript("Invoke-OptiScheduleTick");
                        var o = r.LastOrDefault(x => x != null);
                        if (o != null && Prop(o, "ran") == "True")
                        {
                            var cleaned = Prop(o, "cleaned");
                            _ui.BeginInvoke(new Action(() => ShowBalloon("OptiPC - Nettoyage automatique", "Nettoyage planifié terminé : " + cleaned + " libérés.", ToolTipIcon.Info, false)));
                        }
                        if (nudgeDue && !IsWindowShown())
                        {
                            // Mise a jour automatique et silencieuse (fichier signe par H2OCONSULTING verifie avant installation),
                            // seulement quand la fenetre n'est pas ouverte pour ne pas interrompre le client.
                            try
                            {
                                var u = _engine.RunScript("$u = Get-OptiPCUpdate $false; if($u.update_available -and $u.url){ $i = Install-OptiPCUpdate $u.url $u.sha256; @{v=$u.version;ok=[bool]$i.success;err=[string]$i.error} }").LastOrDefault(x => x != null);
                                if (u != null) Log.Write("Mise a jour automatique vers " + Prop(u, "v") + " : " + (Prop(u, "ok") == "True" ? "lancee" : Prop(u, "err")));
                            }
                            catch (Exception ex) { Log.Error("Mise a jour automatique", ex); }
                        }
                        if (nudgeDue)
                        {
                            var n = _engine.RunScript("Invoke-OptiNudgeCheck").LastOrDefault(x => x != null);
                            if (n != null && Prop(n, "show") == "True")
                            {
                                var warn = Prop(n, "warn") == "True";
                                var title = Prop(n, "title"); var text = Prop(n, "text");
                                _ui.BeginInvoke(new Action(() => ShowBalloon(title, text, warn ? ToolTipIcon.Warning : ToolTipIcon.Info, true)));
                            }
                        }
                    }
                    catch (Exception ex) { Log.Error("Planification", ex); }
                    finally { Interlocked.Exchange(ref _tickBusy, 0); }
                });
            }
        }

        bool IsWindowShown()
        {
            try { return (bool)_ui.Invoke(new Func<bool>(() => _form != null && !_form.IsDisposed && _form.Visible && _form.WindowState != FormWindowState.Minimized)); }
            catch { return true; }
        }

        static string Prop(PSObject o, string name)
        {
            try
            {
                var bo = o.BaseObject as System.Collections.IDictionary;
                if (bo != null) return bo.Contains(name) && bo[name] != null ? bo[name].ToString() : "";
                var p = o.Properties[name];
                return p != null && p.Value != null ? p.Value.ToString() : "";
            }
            catch { return ""; }
        }

        void RunSilentClean()
        {
            try
            {
                var r = _engine.RunScript("$r = Invoke-Cleaning @(Get-OptiAutoCleanIds); [string]$r.cleaned").LastOrDefault(x => x != null);
                var txt = r == null ? "" : r.ToString();
                _ui.BeginInvoke(new Action(() => ShowBalloon("OptiPC - Nettoyage automatique", "Nettoyage terminé : " + txt + " libérés.", ToolTipIcon.Info, false)));
            }
            catch (Exception ex) { Log.Error("Nettoyage silencieux", ex); }
        }

        public void Quit()
        {
            if (_quitting) return;
            _quitting = true;
            try { _timer.Stop(); } catch { }
            try { _tray.Visible = false; _tray.Dispose(); } catch { }
            try { if (_form != null && !_form.IsDisposed) _form.CloseForReal(); } catch { }
            try { _engine.Dispose(); } catch { }
            try { _showEvent.Dispose(); } catch { }
            ExitThread();
            // Filet de securite : une analyse en cours ne doit pas garder le processus en vie.
            var killer = new Thread(() => { Thread.Sleep(4000); Environment.Exit(0); }) { IsBackground = true };
            killer.Start();
        }
    }
}
