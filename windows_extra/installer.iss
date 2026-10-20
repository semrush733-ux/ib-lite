; Windows installer (Inno Setup 6), made by .github/workflows/windows.yml:
;   ISCC /DAppName="..." /DAppVersion=1.0.N /DAppExe=Name /DAppSite=https://... /DSourceDir=... installer.iss
; Installs for the current user only (no administrator question), adds Start menu and desktop
; shortcuts and an uninstaller. Settings, login and playlists live in the user's AppData, so an
; update (the app runs the new installer with /SILENT) keeps them; uninstalling keeps them too.

#ifndef AppName
  #define AppName "Lite Player"
#endif
#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif
#ifndef AppExe
  #define AppExe "LitePlayer"
#endif
#ifndef AppSite
  #define AppSite ""
#endif
#ifndef SourceDir
  #define SourceDir "app"
#endif
#ifndef OutDir
  #define OutDir "."
#endif
#ifndef IconFile
  #define IconFile "app_icon.ico"
#endif

[Setup]
; Never change AppId: Windows recognises the installed app (and its updates) by it.
AppId={{5B7E2C14-6A0D-4E1B-9C2F-7D3A8E41B1F6}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppName}
AppPublisherURL={#AppSite}
AppSupportURL={#AppSite}
DefaultDirName={localappdata}\Programs\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
DisableDirPage=yes
PrivilegesRequired=lowest
ArchitecturesAllowed=x64
ArchitecturesInstallIn64BitMode=x64
OutputDir={#OutDir}
OutputBaseFilename={#AppExe}-Setup
SetupIconFile={#IconFile}
UninstallDisplayIcon={app}\{#AppExe}.exe
UninstallDisplayName={#AppName}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes
RestartApplications=no
MinVersion=10.0

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"

[Files]
Source: "{#SourceDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}.exe"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}.exe"; Tasks: desktopicon

[Run]
; Also after a silent update (started by the app itself): the new version opens by itself.
Filename: "{app}\{#AppExe}.exe"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall
