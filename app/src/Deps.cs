using System;
using System.IO;
using System.Reflection;

namespace OptiPC
{
    /// <summary>
    /// OptiPC tient en un seul fichier : les bibliotheques WebView2 sont incluses dans l'exe
    /// et extraites dans %LOCALAPPDATA%\OptiPC\bin\&lt;version&gt; au premier lancement.
    /// Ainsi le logiciel marche meme lance seul (depuis un zip, une cle USB, le bureau...).
    /// </summary>
    internal static class Deps
    {
        public static string Dir;
        static readonly string[] Files = { "Microsoft.Web.WebView2.Core.dll", "Microsoft.Web.WebView2.WinForms.dll", "WebView2Loader.dll" };

        public static void Install()
        {
            try
            {
                var ver = Assembly.GetExecutingAssembly().GetName().Version.ToString();
                var dir = Path.Combine(Log.DataDir, "bin", ver);
                Directory.CreateDirectory(dir);
                var asm = Assembly.GetExecutingAssembly();
                foreach (var f in Files)
                {
                    using (var s = asm.GetManifestResourceStream("deps/" + f))
                    {
                        if (s == null) continue;
                        var target = Path.Combine(dir, f);
                        if (File.Exists(target) && new FileInfo(target).Length == s.Length) continue;
                        var tmp = target + ".tmp";
                        using (var o = File.Create(tmp)) s.CopyTo(o);
                        try { if (File.Exists(target)) File.Delete(target); File.Move(tmp, target); }
                        catch { try { File.Delete(tmp); } catch { } }
                    }
                }
                Dir = dir;
            }
            catch (Exception ex) { Log.Error("Extraction des bibliotheques", ex); }

            AppDomain.CurrentDomain.AssemblyResolve += (s, e) =>
            {
                try
                {
                    var name = new AssemblyName(e.Name).Name + ".dll";
                    foreach (var baseDir in new[] { AppDomain.CurrentDomain.BaseDirectory, Dir })
                    {
                        if (baseDir == null) continue;
                        var p = Path.Combine(baseDir, name);
                        if (File.Exists(p)) return Assembly.LoadFrom(p);
                    }
                }
                catch (Exception ex) { Log.Error("Chargement " + e.Name, ex); }
                return null;
            };
        }
    }
}
