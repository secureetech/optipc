using System;
using System.IO;
using System.Text;

namespace OptiPC
{
    internal static class Log
    {
        static readonly object Gate = new object();

        public static string DataDir
        {
            get
            {
                var d = Path.Combine(Environment.GetEnvironmentVariable("LOCALAPPDATA") ?? Path.GetTempPath(), "OptiPC");
                try { Directory.CreateDirectory(d); } catch { }
                return d;
            }
        }

        public static void Error(string where, Exception ex)
        {
            Write("ERREUR " + where + " : " + (ex == null ? "" : ex.GetType().Name + " - " + ex.Message + "\r\n" + ex.StackTrace));
        }

        public static void Write(string msg)
        {
            try
            {
                lock (Gate)
                {
                    var f = Path.Combine(DataDir, "errors.log");
                    try
                    {
                        var fi = new FileInfo(f);
                        if (fi.Exists && fi.Length > 1024 * 1024) File.WriteAllText(f, "", Encoding.UTF8);
                    }
                    catch { }
                    File.AppendAllText(f, "[" + DateTime.Now.ToString("dd/MM/yyyy HH:mm:ss") + "] " + msg + "\r\n", Encoding.UTF8);
                }
            }
            catch { }
        }
    }
}
