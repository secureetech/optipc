# OptiPC

OptiPC — logiciel d'entretien et de protection de Windows par SecureeTech (édité par H2OCONSULTING - FZCO).
Téléchargement officiel : https://api.secureetech.com/v1/optipc/download

## OptiPC 2.0 (dossier `app/`)
- Logiciel Windows natif (C# .NET Framework 4.7.2 + WebView2), moteur PowerShell intégré (`app/src/engine`).
- Interface : `app/src/ui` (thème sombre par défaut, mode clair).
- Installateur Inno Setup : `installer/OptiPC.iss` (même AppId que la V1 : la 2.0 remplace la V1).
- Compilation, signature SSL.com et publication : workflow « OptiPC release » du dépôt privé
  `secureetech-pdf` (qui contient déjà les codes de signature). Lancement : onglet Actions > OptiPC release > Run workflow.
- Téléchargement public : https://api.secureetech.com/v1/optipc/download (toujours la dernière version).
- Mises à jour des PC : `updates/stable.json` du dépôt `optipc-api` (version, url, sha256, size — valeurs dans
  `update.json` joint à la release) ; Railway redéploie et chaque OptiPC se met à jour.
