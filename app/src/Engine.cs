using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.IO;
using System.Linq;
using System.Management.Automation;
using System.Management.Automation.Language;
using System.Management.Automation.Runspaces;
using System.Reflection;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace OptiPC
{
    /// <summary>Resultat d'un appel au moteur : code HTTP + corps JSON.</summary>
    internal sealed class RouteResult
    {
        public int Status;
        public string Json;
    }

    /// <summary>
    /// Moteur d'OptiPC : les fonctions PowerShell eprouvees de la V1 (et les nouvelles de la 2.0)
    /// executees dans un pool de runspaces A L'INTERIEUR du logiciel. Plus de serveur HTTP,
    /// plus de port 19878, plus de fenetre PowerShell.
    /// </summary>
    internal sealed class Engine : IDisposable
    {
        RunspacePool _pool;
        readonly ManualResetEventSlim _ready = new ManualResetEventSlim(false);
        string _startError;
        string _allSource;

        const string EntryScript =
            "param($p,$m,$b,$q)\n" +
            "$ProgressPreference='SilentlyContinue'\n" +
            "if(-not (Get-Command Invoke-OptiRoute -EA SilentlyContinue)){ . ([scriptblock]::Create($OptiSrc)) }\n" +
            "Invoke-OptiRoute $p $m $b $q";

        public bool IsReady { get { return _ready.IsSet && _pool != null; } }
        public string StartError { get { return _startError; } }

        static string ReadResource(string name)
        {
            var asm = Assembly.GetExecutingAssembly();
            using (var s = asm.GetManifestResourceStream(name))
            {
                if (s == null) throw new InvalidOperationException("Ressource manquante : " + name);
                using (var r = new StreamReader(s, Encoding.UTF8)) return r.ReadToEnd();
            }
        }

        public void StartAsync()
        {
            var t = new Thread(() =>
            {
                try { Start(); }
                catch (Exception ex) { _startError = ex.Message; Log.Error("Demarrage du moteur", ex); }
                finally { _ready.Set(); }
                // Prechauffage : un premier appel leger pour que le premier clic soit rapide.
                try { if (_pool != null) Call("/api/version", "GET", "", ""); } catch { }
            });
            t.IsBackground = true;
            t.Name = "OptiPC-Engine-Start";
            t.Start();
        }

        public bool WaitReady(int ms) { return _ready.Wait(ms); }

        void Start()
        {
            var sources = new[] { "engine/functions.ps1", "engine/extra.ps1", "engine/router.ps1" }
                .Select(ReadResource).ToList();
            _allSource = string.Join("\r\n\r\n", sources);

            InitialSessionState iss = null;
            try { iss = BuildPreloadedState(_allSource); }
            catch (Exception ex) { Log.Error("Prechargement des fonctions", ex); iss = null; }

            if (iss == null)
            {
                // Repli garanti : chaque runspace charge le code source a sa premiere utilisation.
                iss = InitialSessionState.CreateDefault();
            }
            iss.Variables.Add(new SessionStateVariableEntry("OptiSrc", _allSource, ""));
            iss.ThreadOptions = PSThreadOptions.UseNewThread;

            _pool = RunspaceFactory.CreateRunspacePool(iss);
            _pool.SetMinRunspaces(1);
            _pool.SetMaxRunspaces(16);
            _pool.Open();
        }

        static InitialSessionState BuildPreloadedState(string source)
        {
            Token[] tokens; ParseError[] errors;
            var ast = Parser.ParseInput(source, out tokens, out errors);
            if (errors != null && errors.Length > 0)
                throw new InvalidOperationException("Erreur de syntaxe dans le moteur : " + errors[0].Message + " (ligne " + errors[0].Extent.StartLineNumber + ")");

            var iss = InitialSessionState.CreateDefault();
            var varStatements = new StringBuilder();
            foreach (var st in ast.EndBlock.Statements)
            {
                var fn = st as FunctionDefinitionAst;
                if (fn != null)
                {
                    var body = fn.Body.Extent.Text;
                    if (body.StartsWith("{")) body = body.Substring(1, body.Length - 2);
                    if (fn.Parameters != null && fn.Parameters.Count > 0)
                    {
                        var pl = string.Join(",", fn.Parameters.Select(p => p.Extent.Text));
                        body = "param(" + pl + ")\r\n" + body;
                    }
                    iss.Commands.Add(new SessionStateFunctionEntry(fn.Name, body));
                }
                else
                {
                    varStatements.AppendLine(st.Extent.Text);
                }
            }

            // Variables globales (definitions des phases d'analyse) : evaluees une fois.
            if (varStatements.Length > 0)
            {
                using (var rs = RunspaceFactory.CreateRunspace(iss))
                {
                    rs.Open();
                    using (var ps = PowerShell.Create())
                    {
                        ps.Runspace = rs;
                        ps.AddScript(varStatements.ToString());
                        ps.Invoke();
                        foreach (var name in new[] { "SCAN_DEF", "SCAN_PHASES", "OPTI_OUI" })
                        {
                            var v = rs.SessionStateProxy.GetVariable(name);
                            if (v != null) iss.Variables.Add(new SessionStateVariableEntry(name, v, ""));
                        }
                    }
                }
            }

            // Auto-verification, comme la V1 : si le prechargement ne se comporte pas
            // exactement comme prevu, on revient au chargement classique.
            using (var rs = RunspaceFactory.CreateRunspace(iss))
            {
                rs.Open();
                using (var ps = PowerShell.Create())
                {
                    ps.Runspace = rs;
                    ps.AddScript("(Format-Size 1048576) + '|' + (Format-Size 0) + '|' + @(Get-ScanPlan 'quick').Count + '|' + [bool](Get-Command Invoke-OptiRoute -EA SilentlyContinue)");
                    var r = ps.Invoke();
                    var s = r.Count > 0 && r[0] != null ? r[0].ToString() : "";
                    if (s != "1 MB|0 B|15|True")
                        throw new InvalidOperationException("Auto-verification du moteur inattendue : " + s);
                }
            }
            return iss;
        }

        public Task<RouteResult> CallAsync(string path, string method, string body, string query)
        {
            return Task.Run(() => Call(path, method, body, query));
        }

        public RouteResult Call(string path, string method, string body, string query)
        {
            if (!_ready.Wait(120000) || _pool == null)
                return new RouteResult { Status = 503, Json = "{\"error\":\"moteur_indisponible\",\"message\":\"" + Esc(_startError ?? "Le moteur d'OptiPC n'a pas demarre.") + "\"}" };
            try
            {
                using (var ps = PowerShell.Create())
                {
                    ps.RunspacePool = _pool;
                    ps.AddScript(EntryScript).AddArgument(path).AddArgument(method ?? "GET").AddArgument(body ?? "").AddArgument(query ?? "");
                    Collection<PSObject> output = ps.Invoke();
                    for (int i = output.Count - 1; i >= 0; i--)
                    {
                        var o = output[i];
                        if (o == null) continue;
                        var sp = o.Properties["s"];
                        var jp = o.Properties["j"];
                        if (sp != null && jp != null)
                        {
                            int st = 200;
                            try { st = Convert.ToInt32(sp.Value); } catch { }
                            return new RouteResult { Status = st, Json = jp.Value == null ? "null" : jp.Value.ToString() };
                        }
                    }
                    var err = ps.Streams.Error.Count > 0 ? ps.Streams.Error[0].ToString() : "aucune reponse";
                    Log.Write("ROUTE " + path + " : " + err);
                    return new RouteResult { Status = 500, Json = "{\"error\":\"erreur_interne\",\"message\":\"" + Esc(err) + "\"}" };
                }
            }
            catch (Exception ex)
            {
                Log.Error("ROUTE " + path, ex);
                return new RouteResult { Status = 500, Json = "{\"error\":\"erreur_interne\",\"message\":\"" + Esc(ex.Message) + "\"}" };
            }
        }

        /// <summary>Execute un script PowerShell libre dans le pool (planification, rappels...).</summary>
        public Collection<PSObject> RunScript(string script, params object[] args)
        {
            if (!_ready.Wait(120000) || _pool == null) return new Collection<PSObject>();
            using (var ps = PowerShell.Create())
            {
                ps.RunspacePool = _pool;
                var full = "if(-not (Get-Command Invoke-OptiRoute -EA SilentlyContinue)){ . ([scriptblock]::Create($OptiSrc)) }\n" + script;
                ps.AddScript(full);
                foreach (var a in args) ps.AddArgument(a);
                return ps.Invoke();
            }
        }

        static string Esc(string s)
        {
            if (s == null) return "";
            var sb = new StringBuilder();
            foreach (var c in s)
            {
                switch (c)
                {
                    case '"': sb.Append("\\\""); break;
                    case '\\': sb.Append("\\\\"); break;
                    case '\n': sb.Append("\\n"); break;
                    case '\r': break;
                    case '\t': sb.Append(' '); break;
                    default:
                        if (c < 32) sb.Append(' '); else sb.Append(c);
                        break;
                }
            }
            return sb.ToString();
        }

        public void Dispose()
        {
            try { if (_pool != null) { _pool.Close(); _pool.Dispose(); } } catch { }
        }
    }
}
