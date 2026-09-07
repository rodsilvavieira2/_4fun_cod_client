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

; VC++ redist (VCRUNTIME140.dll etc.) — baixado pelo CI em installer/vendor
; (ver release-desktop.yml). Build manual via IDE sem o arquivo compila igual.
#if FileExists("vendor\vc_redist.x64.exe")
Source: "vendor\vc_redist.x64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall
#endif

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
; Runtime MSVC — flutter build windows nao embarca VCRUNTIME140/MSVCP140.
; Instala silencioso so se ausente (NeedsVCRedist) e so se o payload existir.
Filename: "{tmp}\vc_redist.x64.exe"; \
    Parameters: "/install /quiet /norestart"; \
    StatusMsg: "Installing Visual C++ Redistributable..."; \
    Check: NeedsVCRedist; \
    Flags: waituntilterminated

Filename: "{app}\{#AppExeName}"; \
    Description: "Launch {#AppName}"; \
    Flags: nowait postinstall skipifsilent

[Code]
{ Verifica o runtime MSVC x64 pela chave que o proprio redist grava. }
function NeedsVCRedist(): Boolean;
var
  Version: String;
begin
  Result :=
    FileExists(ExpandConstant('{tmp}\vc_redist.x64.exe')) and
    (not RegQueryStringValue(
      HKLM,
      'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64',
      'Version',
      Version));
end;
