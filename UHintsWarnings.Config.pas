unit UHintsWarnings.Config;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, IniFiles, LazIDEIntf;

type
  { THintsWarningsConfig: Gerencia configuracoes de persistencia, Firebird e Ollama }
  THintsWarningsConfig = class
  private
    FHostName: string;
    FPort: integer;
    FDatabasePath: string;
    FUserName: string;
    FPassword: string;
    FAutoConnect: boolean;

    // Configuracoes do Ollama IA
    FOllamaURL: string;
    FOllamaModel: string;
    FOllamaTimeoutSec: integer;
    FOllamaEnabled: boolean;

    // Configuracoes do Google Gemini
    FGeminiAPIKey: string;
    FGeminiModel: string;

    function GetConfigFilePath: string;
  public
    constructor Create;
    procedure Load;
    procedure Save;

    // Firebird
    property HostName: string read FHostName write FHostName;
    property Port: integer read FPort write FPort;
    property DatabasePath: string read FDatabasePath write FDatabasePath;
    property UserName: string read FUserName write FUserName;
    property Password: string read FPassword write FPassword;
    property AutoConnect: boolean read FAutoConnect write FAutoConnect;

    // Ollama
    property OllamaURL: string read FOllamaURL write FOllamaURL;
    property OllamaModel: string read FOllamaModel write FOllamaModel;
    property OllamaTimeoutSec: integer read FOllamaTimeoutSec write FOllamaTimeoutSec;
    property OllamaEnabled: boolean read FOllamaEnabled write FOllamaEnabled;

    // Gemini
    property GeminiAPIKey: string read FGeminiAPIKey write FGeminiAPIKey;
    property GeminiModel: string read FGeminiModel write FGeminiModel;
  end;

function HintsWarningsConfig: THintsWarningsConfig;

implementation

var
  GConfig: THintsWarningsConfig = nil;

function HintsWarningsConfig: THintsWarningsConfig;
begin
  if GConfig = nil then
  begin
    GConfig := THintsWarningsConfig.Create;
    GConfig.Load;
  end;
  Result := GConfig;
end;

{ THintsWarningsConfig }

constructor THintsWarningsConfig.Create;
begin
  inherited Create;
  // Padrao 127.0.0.1 evita problemas de resolucao IPv6 ::1 no Linux
  FHostName := '127.0.0.1';
  FPort := 3050;
  FDatabasePath := '/home/mauricio/Projetos Antigravity/OTa Lazarus/database/fpc_diagnostics.fdb';
  FUserName := 'SYSDBA';
  FPassword := 'masterkey';
  FAutoConnect := True;

  // Ollama
  FOllamaURL := 'http://localhost:11434';
  FOllamaModel := 'qwen2.5-coder:3b';
  FOllamaTimeoutSec := 90;
  FOllamaEnabled := True;

  // Gemini
  FGeminiAPIKey := '';
  FGeminiModel := 'gemini-2.0-flash';
end;

function THintsWarningsConfig.GetConfigFilePath: string;
var
  CfgDir: string;
begin
  if LazarusIDE <> nil then
    CfgDir := LazarusIDE.GetPrimaryConfigPath
  else
    CfgDir := GetUserDir + '.lazarus';

  Result := IncludeTrailingPathDelimiter(CfgDir) + 'fpc_hints_warnings.ini';
end;

procedure THintsWarningsConfig.Load;
var
  Ini: TIniFile;
  ConfigFile: string;
begin
  ConfigFile := GetConfigFilePath;
  if not FileExists(ConfigFile) then Exit;

  Ini := TIniFile.Create(ConfigFile);
  try
    FHostName := Ini.ReadString('Firebird', 'HostName', FHostName);
    if FHostName = 'localhost' then
      FHostName := '127.0.0.1'; // Migra para IPv4 explícito
    FPort := Ini.ReadInteger('Firebird', 'Port', FPort);
    FDatabasePath := Ini.ReadString('Firebird', 'DatabasePath', FDatabasePath);
    FUserName := Ini.ReadString('Firebird', 'UserName', FUserName);
    FPassword := Ini.ReadString('Firebird', 'Password', FPassword);
    FAutoConnect := Ini.ReadBool('Firebird', 'AutoConnect', FAutoConnect);

    // Ollama
    FOllamaURL := Ini.ReadString('Ollama', 'BaseURL', FOllamaURL);
    FOllamaModel := Ini.ReadString('Ollama', 'Model', FOllamaModel);
    FOllamaTimeoutSec := Ini.ReadInteger('Ollama', 'TimeoutSec', FOllamaTimeoutSec);
    FOllamaEnabled := Ini.ReadBool('Ollama', 'Enabled', FOllamaEnabled);

    // Gemini
    FGeminiAPIKey := Ini.ReadString('Gemini', 'APIKey', FGeminiAPIKey);
    FGeminiModel := Ini.ReadString('Gemini', 'Model', FGeminiModel);
  finally
    Ini.Free;
  end;
end;

procedure THintsWarningsConfig.Save;
var
  Ini: TIniFile;
  ConfigFile: string;
begin
  ConfigFile := GetConfigFilePath;
  Ini := TIniFile.Create(ConfigFile);
  try
    Ini.WriteString('Firebird', 'HostName', FHostName);
    Ini.WriteInteger('Firebird', 'Port', FPort);
    Ini.WriteString('Firebird', 'DatabasePath', FDatabasePath);
    Ini.WriteString('Firebird', 'UserName', FUserName);
    Ini.WriteString('Firebird', 'Password', FPassword);
    Ini.WriteBool('Firebird', 'AutoConnect', FAutoConnect);

    // Ollama
    Ini.WriteString('Ollama', 'BaseURL', FOllamaURL);
    Ini.WriteString('Ollama', 'Model', FOllamaModel);
    Ini.WriteInteger('Ollama', 'TimeoutSec', FOllamaTimeoutSec);
    Ini.WriteBool('Ollama', 'Enabled', FOllamaEnabled);

    // Gemini
    Ini.WriteString('Gemini', 'APIKey', FGeminiAPIKey);
    Ini.WriteString('Gemini', 'Model', FGeminiModel);
  finally
    Ini.Free;
  end;
end;

initialization

finalization
  FreeAndNil(GConfig);

end.
