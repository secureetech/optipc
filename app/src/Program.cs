using System;
using System.Linq;
using System.Threading;
using System.Windows.Forms;

namespace OptiPC
{
    internal static class Program
    {
        [STAThread]
        static void Main(string[] args)
        {
            Native.FixShortPathEnvironment();
            Deps.Install();
            bool atLogon = args.Any(a => string.Equals(a, "-AuDemarrage", StringComparison.OrdinalIgnoreCase));
            bool silent = args.Any(a => string.Equals(a, "-Silent", StringComparison.OrdinalIgnoreCase));

            // Le client a desactive OptiPC dans Gestionnaire des taches > Applications de demarrage :
            // on respecte son choix (la tache planifiee de l'ouverture de session ne passe pas outre).
            if (atLogon && DemarrageDesactiveParLeClient()) return;

            bool created;
            using (var mutex = new Mutex(true, "Local\\OptiPC2_Instance", out created))
            {
                if (!created)
                {
                    // OptiPC tourne deja (souvent discret pres de l'horloge) : on affiche sa fenetre.
                    if (!atLogon && !silent)
                    {
                        try { using (var ev = EventWaitHandle.OpenExisting(OptiApp.ShowEventName)) ev.Set(); } catch { }
                    }
                    return;
                }

                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                Application.SetUnhandledExceptionMode(UnhandledExceptionMode.CatchException);
                Application.ThreadException += (s, e) => Log.Error("Interface", e.Exception);
                AppDomain.CurrentDomain.UnhandledException += (s, e) => Log.Error("Processus", e.ExceptionObject as Exception);
                System.Threading.Tasks.TaskScheduler.UnobservedTaskException += (s, e) => { e.SetObserved(); try { foreach (var ie in e.Exception.Flatten().InnerExceptions) Log.Error("Tache (detail)", ie); } catch { Log.Error("Tache", e.Exception); } };

                try { System.Net.ServicePointManager.SecurityProtocol |= System.Net.SecurityProtocolType.Tls12; } catch { }

                Application.Run(new OptiApp(atLogon, silent));
                GC.KeepAlive(mutex);
            }
        }

        // Entree « OptiPC » de la cle Run desactivee dans le Gestionnaire des taches :
        // StartupApproved\Run contient alors une valeur dont le premier octet est impair (03).
        static bool DemarrageDesactiveParLeClient()
        {
            const string Cle = @"Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run";
            foreach (var racine in new[] { Microsoft.Win32.Registry.CurrentUser, Microsoft.Win32.Registry.LocalMachine })
            {
                try
                {
                    using (var k = racine.OpenSubKey(Cle))
                    {
                        if (k?.GetValue("OptiPC") is byte[] etat && etat.Length > 0 && (etat[0] & 1) == 1) return true;
                    }
                }
                catch { }
            }
            return false;
        }
    }
}
