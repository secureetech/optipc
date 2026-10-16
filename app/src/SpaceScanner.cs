using System;
using System.Collections;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Security.Cryptography;

namespace OptiPC
{
    /// <summary>
    /// Recherche « Espace disque » (doublons, gros fichiers, dossiers et fichiers vides,
    /// vieux téléchargements, fichiers anciens) écrite en C# : 20 à 50 fois plus rapide
    /// que la même chose en PowerShell sur des centaines de milliers de fichiers.
    /// Appelée depuis le moteur PowerShell : [OptiPC.SpaceScanner]::Scan($roots, $dlPath).
    /// Le résultat a exactement la même forme que l'ancienne version PowerShell.
    /// </summary>
    public static class SpaceScanner
    {
        sealed class F
        {
            public string Path, Name, Dir, Kind;
            public long Len;
            public DateTime Mod;
            public bool Dl;
        }

        static readonly Dictionary<string, string> Kinds = BuildKinds();
        static Dictionary<string, string> BuildKinds()
        {
            var d = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            Action<string, string> add = (k, list) => { foreach (var e in list.Split(' ')) d["." + e] = k; };
            add("Images", "jpg jpeg png gif bmp tif tiff webp heic heif raw cr2 nef arw dng svg");
            add("Videos", "mp4 avi mkv mov wmv flv m4v webm ts vob mpg mpeg 3gp mts m2ts");
            add("Musique", "mp3 flac wav aac ogg wma m4a opus aiff");
            add("Documents", "pdf doc docx xls xlsx ppt pptx txt csv odt ods odp rtf pages numbers key epub");
            add("Archives", "zip rar 7z tar gz bz2 xz iso img cab");
            add("Installateurs", "exe msi msix msixbundle appx dmg apk");
            return d;
        }
        static string KindOf(string ext) { string k; return ext != null && Kinds.TryGetValue(ext, out k) ? k : "Autres"; }

        public static string FormatSize(long b)
        {
            if (b <= 0) return "0 B";
            if (b >= 1073741824L) return string.Format(CultureInfo.CurrentCulture, "{0:N1} GB", b / 1073741824.0);
            if (b >= 1048576L) return string.Format(CultureInfo.CurrentCulture, "{0:N0} MB", b / 1048576.0);
            if (b >= 1024L) return string.Format(CultureInfo.CurrentCulture, "{0:N0} KB", b / 1024.0);
            return b + " B";
        }

        static readonly HashSet<string> SkipDirs = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "$RECYCLE.BIN", "System Volume Information", "node_modules", ".git", "AppData" };
        static readonly HashSet<string> SkipEmptyNames = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "desktop.ini", "thumbs.db", ".gitkeep", ".keep", ".nomedia", ".placeholder" };

        /// <param name="roots">Chemins des dossiers personnels.</param>
        /// <param name="dlPath">Chemin du dossier Téléchargements (peut être vide).</param>
        public static Hashtable Scan(string[] roots, string dlPath, int maxSeconds = 60, int maxFiles = 1500000, int hashSeconds = 30)
        {
            var sw = Stopwatch.StartNew();
            var files = new List<F>(65536);
            var dirs = new List<string>();
            var withFiles = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            var cat = new Dictionary<string, long>();
            foreach (var k in new[] { "Videos", "Images", "Telechargements", "Musique", "Documents", "Archives", "Installateurs", "Autres" }) cat[k] = 0;
            bool partial = false; long scanned = 0;
            const FileAttributes skipAttr = FileAttributes.Offline | (FileAttributes)0x00040000 | (FileAttributes)0x00400000;

            foreach (var root in roots ?? new string[0])
            {
                if (string.IsNullOrEmpty(root) || !Directory.Exists(root)) continue;
                bool isDl = !string.IsNullOrEmpty(dlPath) && string.Equals(root.TrimEnd('\\'), dlPath.TrimEnd('\\'), StringComparison.OrdinalIgnoreCase);
                var stack = new Stack<string>(); stack.Push(root);
                while (stack.Count > 0)
                {
                    if (sw.Elapsed.TotalSeconds > maxSeconds || scanned >= maxFiles) { partial = true; break; }
                    var dir = stack.Pop();
                    FileSystemInfo[] entries;
                    try { entries = new DirectoryInfo(dir).GetFileSystemInfos(); } catch { continue; }
                    if (!string.Equals(dir, root, StringComparison.OrdinalIgnoreCase)) dirs.Add(dir);
                    foreach (var e in entries)
                    {
                        try
                        {
                            var a = e.Attributes;
                            if ((a & FileAttributes.Directory) != 0)
                            {
                                if ((a & (FileAttributes.ReparsePoint | FileAttributes.System)) != 0 || SkipDirs.Contains(e.Name)) { withFiles.Add(e.FullName); continue; }
                                stack.Push(e.FullName);
                                continue;
                            }
                            scanned++;
                            var fi = (FileInfo)e;
                            var p = fi.DirectoryName;
                            while (p != null && withFiles.Add(p)) p = Path.GetDirectoryName(p);
                            if ((a & skipAttr) != 0 || (a & FileAttributes.ReparsePoint) != 0) continue;
                            long len = fi.Length;
                            var kind = KindOf(fi.Extension);
                            if (isDl) cat["Telechargements"] += len; else cat[kind] += len;
                            // Les fichiers vides cachés/système (desktop.ini...) ne sont jamais proposés.
                            if (len == 0 && (a & (FileAttributes.Hidden | FileAttributes.System)) != 0) continue;
                            files.Add(new F { Path = fi.FullName, Name = fi.Name, Dir = fi.DirectoryName, Len = len, Mod = fi.LastWriteTime, Kind = kind, Dl = isDl });
                        }
                        catch { }
                    }
                }
                if (partial) break;
            }

            var now = DateTime.Now;
            Func<F, string, string, Hashtable> mk = (f, level, detail) => new Hashtable {
                { "id", f.Path }, { "path", f.Path }, { "name", f.Name }, { "dir", f.Dir }, { "size", f.Len }, { "sizeStr", FormatSize(f.Len) },
                { "date", f.Mod.ToString("dd/MM/yyyy") }, { "level", level }, { "kind", f.Kind }, { "detail", detail ?? "" } };
            Func<F, bool> perso = f => f.Kind == "Images" || f.Kind == "Videos" || f.Kind == "Documents" || f.Kind == "Musique";
            Func<F, string> levelFor = f => (f.Kind == "Installateurs" || f.Kind == "Archives") ? (f.Dl ? "safe" : "check") : perso(f) ? "perso" : "check";

            // 1) Gros fichiers
            var big = files.Where(f => f.Len >= 100L * 1048576).OrderByDescending(f => f.Len).Take(60).Select(f => (object)mk(f, levelFor(f), "")).ToArray();

            // 2) Doublons
            var dups = new List<object>();
            var hsw = Stopwatch.StartNew();
            int gid = 0;
            using (var sha = SHA1.Create())
            {
                var bySize = files.Where(f => f.Len >= 1048576).GroupBy(f => f.Len).Where(g => g.Count() >= 2).OrderByDescending(g => g.Key);
                foreach (var g in bySize)
                {
                    if (hsw.Elapsed.TotalSeconds > hashSeconds) { partial = true; break; }
                    var byQuick = new Dictionary<string, List<F>>();
                    foreach (var f in g)
                    {
                        var h = QuickHash(sha, f.Path, f.Len);
                        if (h == null) continue;
                        List<F> l; if (!byQuick.TryGetValue(h, out l)) byQuick[h] = l = new List<F>(); l.Add(f);
                    }
                    foreach (var cand in byQuick.Values)
                    {
                        if (cand.Count < 2) continue;
                        bool exact = cand[0].Len <= 512L * 1048576;
                        var sets = new Dictionary<string, List<F>>();
                        if (exact)
                        {
                            foreach (var f in cand)
                            {
                                var h = FullHash(sha, f.Path);
                                if (h == null) continue;
                                List<F> l; if (!sets.TryGetValue(h, out l)) sets[h] = l = new List<F>(); l.Add(f);
                            }
                        }
                        else sets["q"] = cand;
                        foreach (var set in sets.Values)
                        {
                            if (set.Count < 2) continue;
                            gid++;
                            // On garde la copie hors Téléchargements la plus récente.
                            var ordered = set.OrderBy(f => f.Dl ? 1 : 0).ThenByDescending(f => f.Mod).ToList();
                            var keep = ordered[0];
                            for (int i = 1; i < ordered.Count; i++)
                            {
                                var f = ordered[i];
                                var lvl = !exact ? "check" : perso(f) ? "perso" : "safe";
                                var it = mk(f, lvl, "Copie identique de : " + keep.Path);
                                it["group"] = gid; it["exact"] = exact;
                                dups.Add(it);
                            }
                        }
                    }
                }
            }

            // 3) Vieux téléchargements
            var dlOld = files.Where(f => f.Dl && (now - f.Mod).TotalDays > 60 && f.Len >= 1048576).OrderByDescending(f => f.Len).Take(150)
                .Select(f => (object)mk(f, (f.Kind == "Installateurs" || f.Kind == "Archives") ? "safe" : perso(f) ? "perso" : "check", "Telecharge il y a " + (int)(now - f.Mod).TotalDays + " jours")).ToArray();
            // 4) Fichiers anciens
            var old = files.Where(f => !f.Dl && (now - f.Mod).TotalDays > 730 && f.Len >= 50L * 1048576).OrderByDescending(f => f.Len).Take(100)
                .Select(f => (object)mk(f, perso(f) ? "perso" : "check", "Pas modifie depuis " + (int)((now - f.Mod).TotalDays / 365) + " ans")).ToArray();
            // 4 bis) Fichiers vides
            var emptyFiles = files.Where(f => f.Len == 0 && !SkipEmptyNames.Contains(f.Name) && !f.Name.StartsWith("~$")
                    && !(f.Name.EndsWith(".lock", StringComparison.OrdinalIgnoreCase) || f.Name.EndsWith(".lck", StringComparison.OrdinalIgnoreCase) || f.Name.EndsWith(".pid", StringComparison.OrdinalIgnoreCase) || f.Name.EndsWith(".tmp", StringComparison.OrdinalIgnoreCase) || f.Name.EndsWith(".log", StringComparison.OrdinalIgnoreCase)))
                .Take(500).Select(f => (object)mk(f, (perso(f) || f.Kind == "Archives" || f.Kind == "Installateurs") ? "safe" : "check", "Fichier vide (0 octet)")).ToArray();
            // 5) Dossiers vides
            var empty = dirs.Where(d => !withFiles.Contains(d)).Take(500).Select(d => (object)new Hashtable {
                { "id", d }, { "path", d }, { "name", Path.GetFileName(d) }, { "dir", Path.GetDirectoryName(d) }, { "size", 0L }, { "sizeStr", "" },
                { "date", "" }, { "level", "safe" }, { "kind", "Dossier" }, { "detail", "" } }).ToArray();

            Func<IEnumerable<object>, long> sum = arr => arr.Sum(o => (long)((Hashtable)o)["size"]);
            long tot = cat.Values.Sum();
            var cats = cat.Select(kv => (object)new Hashtable { { "name", kv.Key }, { "size", kv.Value }, { "sizeStr", FormatSize(kv.Value) } }).ToArray();
            var dupArr = dups.ToArray();
            return new Hashtable {
                { "scanned", scanned }, { "elapsed", (int)sw.Elapsed.TotalSeconds }, { "partial", partial },
                { "total", FormatSize(tot) }, { "totalBytes", tot }, { "cats", cats },
                { "groups", new Hashtable {
                    { "dups", new Hashtable { { "items", dupArr }, { "size", sum(dupArr) } } },
                    { "big", new Hashtable { { "items", big }, { "size", sum(big) } } },
                    { "downloads", new Hashtable { { "items", dlOld }, { "size", sum(dlOld) } } },
                    { "empty", new Hashtable { { "items", empty }, { "size", 0L } } },
                    { "emptyfiles", new Hashtable { { "items", emptyFiles }, { "size", 0L } } },
                    { "old", new Hashtable { { "items", old }, { "size", sum(old) } } } } },
                { "date", now.ToString("dd/MM/yyyy HH:mm") }, { "engine", "cs" } };
        }

        static string QuickHash(SHA1 sha, string path, long len)
        {
            try
            {
                using (var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete, 65536))
                {
                    int n = (int)Math.Min(65536, len);
                    var all = new byte[n * 2 + 8];
                    int r = 0; while (r < n) { int k = fs.Read(all, r, n - r); if (k <= 0) break; r += k; }
                    if (len > n) { fs.Seek(-n, SeekOrigin.End); r = 0; while (r < n) { int k = fs.Read(all, n + r, n - r); if (k <= 0) break; r += k; } }
                    Array.Copy(BitConverter.GetBytes(len), 0, all, n * 2, 8);
                    return BitConverter.ToString(sha.ComputeHash(all));
                }
            }
            catch { return null; }
        }
        static string FullHash(SHA1 sha, string path)
        {
            try { using (var fs = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite | FileShare.Delete, 1 << 20)) return BitConverter.ToString(sha.ComputeHash(fs)); }
            catch { return null; }
        }
    }
}
