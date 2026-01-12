[Setup]
AppId={{COM.HAITANG.GUANYING}}
AppName=观影
AppVersion={#AppVersion}
AppPublisher=HaiTang-8
AppPublisherURL=https://github.com/HaiTang-8/video-player-client
AppSupportURL=https://github.com/HaiTang-8/video-player-client
AppUpdatesURL=https://github.com/HaiTang-8/video-player-client/releases
DefaultDirName={autopf}\Guanying
DefaultGroupName=观影
DisableProgramGroupPage=yes
OutputDir=..\dist
OutputBaseFilename=guanying-windows-setup
SetupIconFile=runner\resources\app_icon.ico
Compression=lzma
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
ArchitecturesInstallIn64BitMode=x64compatible

[Languages]
Name: "chinesesimplified"; MessagesFile: "compiler:Languages\ChineseSimplified.isl"
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\观影"; Filename: "{app}\guanying.exe"
Name: "{group}\{cm:UninstallProgram,观影}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\观影"; Filename: "{app}\guanying.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\guanying.exe"; Description: "{cm:LaunchProgram,观影}"; Flags: nowait postinstall skipifsilent
