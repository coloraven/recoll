; Recoll Inno Setup Script

#ifndef MyAppVersion
#define MyAppVersion "1.43.13"
#endif

#define MyAppName "Recoll"
#define MyAppPublisher "Recoll"
#define MyAppURL "https://www.recoll.org/"
#define MyAppExeName "recollindex.exe"

[Setup]
AppId={{8B7E4A5F-3C2D-4E1A-9F8B-6D5C4A3B2E1F}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyAppPublisher}
AppPublisherURL={#MyAppURL}
AppSupportURL={#MyAppURL}
AppUpdatesURL={#MyAppURL}
DefaultDirName={autopf}\{#MyAppName}
DefaultGroupName={#MyAppName}
AllowNoIcons=yes
LicenseFile=..\src\COPYING
OutputDir=Output
OutputBaseFilename=recoll-{#MyAppVersion}-win64-setup
SetupIconFile=..\src\desktop\recoll.ico
Compression=lzma
SolidCompression=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible
ArchitecturesAllowed=x64compatible

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

#ifndef StagingDir
#define StagingDir "..\staging"
#endif

[Files]
; Main executables
Source: "{#StagingDir}\bin\recollindex.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#StagingDir}\bin\recollq.exe"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#StagingDir}\bin\recoll.exe"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist

; Configuration examples
Source: "{#StagingDir}\share\recoll\examples\*"; DestDir: "{app}\examples"; Flags: ignoreversion recursesubdirs

; Filters
Source: "{#StagingDir}\share\recoll\filters\*"; DestDir: "{app}\filters"; Flags: ignoreversion recursesubdirs

; Documentation
Source: "{#StagingDir}\share\recoll\doc\*"; DestDir: "{app}\doc"; Flags: ignoreversion recursesubdirs

; Any DLLs (e.g., Qt) placed in the staging bin folder by windeployqt
Source: "{#StagingDir}\bin\*.dll"; DestDir: "{app}"; Flags: ignoreversion skipifsourcedoesntexist
Source: "{#StagingDir}\bin\platforms\*"; DestDir: "{app}\platforms"; Flags: ignoreversion recursesubdirs skipifsourcedoesntexist

[Icons]
Name: "{group}\Recoll"; Filename: "{app}\recoll.exe"
Name: "{group}\Recoll Index"; Filename: "{app}\{#MyAppExeName}"
Name: "{group}\{cm:UninstallProgram,{#MyAppName}}"; Filename: "{uninstallexe}"

[Registry]
Root: HKLM; Subkey: "SYSTEM\CurrentControlSet\Control\Session Manager\Environment"; \
    ValueType: expandsz; ValueName: "Path"; ValueData: "{olddata};{app}"; \
    Check: NeedsAddPath('{app}')

[Code]
function NeedsAddPath(Param: string): boolean;
var
  OrigPath: string;
begin
  if not RegQueryStringValue(HKLM,
    'SYSTEM\CurrentControlSet\Control\Session Manager\Environment',
    'Path', OrigPath)
  then begin
    Result := True;
    exit;
  end;
  Result := Pos(';' + UpperCase(Param) + ';', ';' + UpperCase(OrigPath) + ';') = 0;
end;
