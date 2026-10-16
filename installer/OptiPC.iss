; ============================================================
;  OptiPC 2.0 - Installateur Inno Setup (SecureeTech)
;  Compile automatiquement par GitHub Actions (.github/workflows/release.yml) :
;    ISCC.exe /DAppVersion=2.0.0 installer\OptiPC.iss
;  Remplace proprement OptiPC V1 (meme AppId, meme dossier Program Files).
; ============================================================
#define AppName      "OptiPC"
#ifndef AppVersion
  #define AppVersion "2.0.0"
#endif
#define AppPublisher "H2OCONSULTING - FZCO (SecureeTech)"
#define AppURL       "https://secureetech.com/logiciel-optimisation-pc/"
#define AppExe       "OptiPC.exe"

[Setup]
; Meme AppId que la V1 : Windows voit une mise a jour, pas un second logiciel.
AppId={{8E5B2C41-7D3A-4F6B-9A1E-3C7D5F20B914}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}
VersionInfoVersion={#AppVersion}
VersionInfoCompany=H2OCONSULTING - FZCO
VersionInfoDescription=Installation d'OptiPC
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
DisableDirPage=auto
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
OutputDir=..\Setup
OutputBaseFilename=OptiPC-Setup-{#AppVersion}
SetupIconFile=OptiPC.ico
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
CloseApplications=no
RestartApplications=no

[Languages]
Name: "french"; MessagesFile: "compiler:Languages\French.isl"

[Tasks]
Name: "desktopicon"; Description: "Créer un raccourci sur le Bureau"; GroupDescription: "Raccourcis :"

[Files]
Source: "..\build\OptiPC.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "..\build\OptiPC.exe.config"; DestDir: "{app}"; Flags: ignoreversion
Source: "OptiPC.ico"; DestDir: "{app}"; Flags: ignoreversion
; Moteur d'affichage de Windows (WebView2) : installe seulement s'il manque.
Source: "MicrosoftEdgeWebview2Setup.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall; Check: NeedsWebView2

[InstallDelete]
; Restes de la V1 devenus inutiles
Type: files; Name: "{app}\OptiPC.ps1"
Type: files; Name: "{app}\ui.html"

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{group}\Désinstaller {#AppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

; Le demarrage automatique (tache planifiee "OptiPC" -AuDemarrage) est cree
; par OptiPC lui-meme au premier lancement.

[Run]
Filename: "{tmp}\MicrosoftEdgeWebview2Setup.exe"; Parameters: "/silent /install"; StatusMsg: "Installation du moteur d'affichage de Windows…"; Flags: waituntilterminated; Check: NeedsWebView2
Filename: "{app}\{#AppExe}"; Description: "Lancer {#AppName}"; Flags: nowait postinstall skipifsilent runascurrentuser
; Mise a jour silencieuse lancee par OptiPC : on le relance automatiquement
Filename: "{app}\{#AppExe}"; Flags: nowait runascurrentuser; Check: WizardSilent

[UninstallRun]
Filename: "{sys}\taskkill.exe"; Parameters: "/F /T /IM {#AppExe}"; Flags: runhidden; RunOnceId: "KillOptiPC"
Filename: "{sys}\schtasks.exe"; Parameters: "/Delete /TN ""OptiPC"" /F"; Flags: runhidden; RunOnceId: "DelTask"
Filename: "{sys}\reg.exe"; Parameters: "delete ""HKCU\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"" /v OptiPC /f"; Flags: runhidden; RunOnceId: "DelRun"

[UninstallDelete]
Type: filesandordirs; Name: "{commonappdata}\OptiPC"

[Code]
function NeedsWebView2(): Boolean;
var
  V: String;
begin
  Result := True;
  if RegQueryStringValue(HKLM, 'SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}', 'pv', V) and (V <> '') and (V <> '0.0.0.0') then Result := False
  else if RegQueryStringValue(HKCU, 'Software\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}', 'pv', V) and (V <> '') and (V <> '0.0.0.0') then Result := False;
end;

procedure StopOptiPC();
var
  Code: Integer;
begin
  { Fermer OptiPC (V1 ou 2.0) s'il tourne, sinon OptiPC.exe est verrouille }
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /T /IM OptiPC.exe', '', SW_HIDE, ewWaitUntilTerminated, Code);
  Sleep(1000);
end;

function PrepareToInstall(var NeedsRestart: Boolean): String;
begin
  StopOptiPC();
  Result := '';
end;

{ Si une ancienne version avait ete installee avec un autre identifiant,
  on retire son entree en double dans « Applications installees ».
  Ses fichiers sont deja remplaces : on ne lance PAS son desinstalleur. }
procedure RemoveDuplicateEntries(Root: Integer; const Base: String);
var
  Keys: TArrayOfString;
  I: Integer;
  Name, Mine: String;
begin
  Mine := '{8E5B2C41-7D3A-4F6B-9A1E-3C7D5F20B914}_is1';
  if RegGetSubkeyNames(Root, Base, Keys) then
    for I := 0 to GetArrayLength(Keys) - 1 do
      if (CompareText(Keys[I], Mine) <> 0) and RegQueryStringValue(Root, Base + '\' + Keys[I], 'DisplayName', Name) then
        if (CompareText(Name, 'OptiPC') = 0) or (Pos('OptiPC version', Name) = 1) then
          RegDeleteKeyIncludingSubkeys(Root, Base + '\' + Keys[I]);
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    RemoveDuplicateEntries(HKLM, 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall');
    RemoveDuplicateEntries(HKLM, 'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall');
    RemoveDuplicateEntries(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Uninstall');
  end;
end;
