using System;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading;

namespace OptiPCDemarrage
{
    // Lanceur d'OptiPC a l'ouverture de session Windows.
    //
    // OptiPC demande les droits administrateur : inscrit directement dans la cle Run,
    // Windows le bloquerait (ou afficherait une fenetre de confirmation) a chaque demarrage.
    // Ce petit lanceur, sans droits, est inscrit dans la cle Run (il apparait donc dans
    // Gestionnaire des taches > Applications de demarrage, ou le client peut le desactiver)
    // et demarre la tache planifiee « OptiPC », qui lance OptiPC avec les droits, sans fenetre.
    internal static class Program
    {
        const string NomTache = "OptiPC";
        const int AttenteMaxMs = 45000;
        const int PasMs = 3000;
        const int EssaisLancement = 3;

        static int Main()
        {
            // La tache planifiee a peut-etre deja demarre OptiPC a l'ouverture de session.
            if (AttendreOptiPC(AttenteMaxMs)) return 0;
            for (int i = 0; i < EssaisLancement; i++)
            {
                LancerTache();
                if (AttendreOptiPC(15000)) return 0;
            }
            return 1;
        }

        static bool OptiPCLance()
        {
            int session = Process.GetCurrentProcess().SessionId;
            return Process.GetProcessesByName("OptiPC").Any(p =>
            {
                try { return p.SessionId == session; } catch { return false; }
            });
        }

        static bool AttendreOptiPC(int delaiMs)
        {
            var fin = DateTime.UtcNow.AddMilliseconds(delaiMs);
            while (true)
            {
                if (OptiPCLance()) return true;
                if (DateTime.UtcNow >= fin) return false;
                Thread.Sleep(PasMs);
            }
        }

        static void LancerTache()
        {
            try
            {
                var psi = new ProcessStartInfo(Path.Combine(Environment.SystemDirectory, "schtasks.exe"),
                                               "/run /tn \"" + NomTache + "\"")
                {
                    CreateNoWindow = true,
                    UseShellExecute = false,
                    WindowStyle = ProcessWindowStyle.Hidden
                };
                using (var p = Process.Start(psi)) { p.WaitForExit(15000); }
            }
            catch { }
        }
    }
}
