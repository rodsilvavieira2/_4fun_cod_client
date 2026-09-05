; 4Fun Cod — Windows installer (Inno Setup 6)
; Valores AppName/AppSlug/AppExeName/AppVersion são injetados pelo CI
; (release-desktop.yml). Defaults abaixo servem para build manual via Inno IDE.

#ifndef AppName
  #define AppName "4Fun Cod"
#endif

#ifndef AppSlug
  #define AppSlug "4fun-cod"
#endif

#ifndef AppExeName
  #define AppExeName "_4fun_cod_client.exe"
#endif

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

[Setup]
AppId=com.fourfun.codclient

AppName={#AppName}
AppVersion={#AppVersion}

DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}

OutputDir=..\dist\windows
OutputBaseFilename={#AppSlug}-windows-x64-{#AppVersion}-setup

Compression=lzma2
SolidCompression=yes
WizardStyle=modern

ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible

PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog

UninstallDisplayName={#AppName}

[Files]
Source: "..\build\windows\x64\runner\Release\*"; \
    DestDir: "{app}"; \
    Flags: ignoreversion recursesubdirs createallsubdirs

[Tasks]
Name: "desktopicon"; \
    Description: "Create a desktop shortcut"; \
    GroupDescription: "Additional shortcuts:"

[Icons]
Name: "{autoprograms}\{#AppName}"; \
    Filename: "{app}\{#AppExeName}"

Name: "{autodesktop}\{#AppName}"; \
    Filename: "{app}\{#AppExeName}"; \
    Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExeName}"; \
    Description: "Launch {#AppName}"; \
    Flags: nowait postinstall skipifsilent
