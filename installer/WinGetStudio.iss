; WinGetStudio.iss — installer per macchina dello stesso exe portable (Inno Setup 6).
; Lo compila src\build.ps1: AppVersion, SourceExe e (se c'e' la chiave) SIGN arrivano da li'.
; AppId NON va mai cambiato: e' la chiave _is1 con cui l'app si riconosce installata
; (Get-InstallChannel) e con cui winget correla il pacchetto.

#ifndef AppVersion
  #error AppVersion non definita: compilare con src\build.ps1
#endif

[Setup]
AppId={{80A0A054-6278-4145-AD5A-2B3C4853019F}
AppName=WinGet Studio
AppVersion={#AppVersion}
AppPublisher=FedeB2160
AppPublisherURL=https://github.com/FedeB2160/WinGetStudio
VersionInfoVersion={#AppVersion}
VersionInfoTextVersion={#AppVersion}
VersionInfoProductTextVersion={#AppVersion}
; Solo per macchina: l'app gira sempre elevata, e un'installazione per utente aggiornata da
; un processo elevato finirebbe nel profilo dell'amministratore.
PrivilegesRequired=admin
DefaultDirName={autopf}\WinGet Studio
DisableProgramGroupPage=yes
OutputBaseFilename=WinGetStudio_Setup
SetupIconFile=..\assets\icon.ico
UninstallDisplayIcon={app}\WinGetStudio.exe
; Nome in Impostazioni > App, uguale a quello del portable: il default di Inno e'
; "WinGet Studio version X". winget correla per ProductCode (_is1), non per nome.
UninstallDisplayName=WinGet Studio
WizardStyle=modern
; Se l'app e' aperta (aggiornamento dall'app stessa) Inno la chiude prima di sostituire l'exe.
CloseApplications=yes
RestartApplications=no
; Senza chiave (niente /DSIGN) il setup esce non firmato, come l'exe.
#ifdef SIGN
SignTool=wgsign
SignedUninstaller=yes
#endif

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#SourceExe}"; DestDir: "{app}"; Flags: ignoreversion

[Icons]
Name: "{autoprograms}\WinGet Studio"; Filename: "{app}\WinGetStudio.exe"
Name: "{autodesktop}\WinGet Studio"; Filename: "{app}\WinGetStudio.exe"; Tasks: desktopicon

[Run]
; Installazione a mano: casella "Launch" a fine wizard. runascurrentuser: postinstall per
; default parte come utente originale NON elevato, e l'exe (requireAdministrator) fallirebbe
; con errore 740.
Filename: "{app}\WinGetStudio.exe"; Description: "{cm:LaunchProgram,WinGet Studio}"; Flags: nowait postinstall skipifsilent runascurrentuser
; Aggiornamento dall'app: la riapre solo se lanciato con /relaunch=1. winget non lo passa.
Filename: "{app}\WinGetStudio.exe"; Flags: nowait; Check: ShouldRelaunch

[Code]
function ShouldRelaunch: Boolean;
begin
  Result := ExpandConstant('{param:relaunch|0}') = '1';
end;
