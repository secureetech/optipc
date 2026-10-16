# OptiPC

OptiPC — logiciel d'entretien et de protection de Windows par SecureeTech (édité par H2OCONSULTING - FZCO).
Téléchargements officiels dans l'onglet **Releases** : https://github.com/secureetech/optipc/releases/latest/download/OptiPC-Setup.exe

## OptiPC 2.0 (dossier `app/`)
- Logiciel Windows natif (C# .NET Framework 4.7.2 + WebView2), moteur PowerShell intégré (`app/src/engine`).
- Interface : `app/src/ui` (thème sombre par défaut, mode clair).
- Installateur Inno Setup : `installer/OptiPC.iss` (même AppId que la V1 : la 2.0 remplace la V1).
- Compilation, signature SSL.com eSigner et publication : `.github/workflows/release.yml`
  (créer un tag `vX.Y.Z`). Secrets requis : `ES_USERNAME`, `ES_PASSWORD`, `ES_CREDENTIAL_ID`, `ES_TOTP_SECRET`.
- Mises à jour des PC : après publication, recopier le contenu de `update.json` (joint à la release)
  dans `updates/stable.json` du dépôt `optipc-api` ; Railway redéploie et chaque OptiPC se met à jour.
