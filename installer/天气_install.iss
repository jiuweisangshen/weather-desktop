; 天气 安装程序脚本（Inno Setup 6/7）
; 编译：ISCC.exe installer\天气_install.iss（先执行 PyInstaller 生成 dist\天气）
; 说明：升级时保留用户 config.json 与 .cache，安装前自动关闭正在运行的旧版本

[Setup]
AppId={{7C4E1F3A-2D8B-4E5A-9B1C-6A2F0D3E8B47}
AppName=天气
AppVersion=1.0.0
AppVerName=天气 1.0.0
AppPublisher=天气
DefaultDirName={autopf}\天气
DefaultGroupName=天气
DisableProgramGroupPage=yes
OutputDir=dist_installer
OutputBaseFilename=天气_安装程序
Compression=lzma2/max
SolidCompression=yes
LZMAUseSeparateProcess=yes
WizardStyle=modern
ArchitecturesInstallIn64BitMode=x64compatible
ArchitecturesAllowed=x64compatible
SetupIconFile=assets\appicon\app_icon.ico
UninstallDisplayIcon={app}\天气.exe
UninstallDisplayName=天气
CloseApplications=yes
CloseApplicationsFilter=*.exe
RestartApplications=no
UsePreviousAppDir=yes
PrivilegesRequired=admin

[Languages]
Name: "chinesesimp"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "创建桌面快捷方式"; GroupDescription: "附加任务："; Flags: checkedonce

[Files]
; 排除用户数据：升级覆盖安装时不覆盖 config.json、不删本地缓存
Source: "dist\天气\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs; Excludes: "config.json,.cache\*"

[Icons]
Name: "{autoprograms}\天气"; Filename: "{app}\天气.exe"; IconFilename: "{app}\天气.exe"
Name: "{autodesktop}\天气"; Filename: "{app}\天气.exe"; IconFilename: "{app}\天气.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\天气.exe"; Description: "立即运行天气"; Flags: nowait postinstall skipifsilent

[UninstallDelete]
Type: filesandordirs; Name: "{app}\.cache"
