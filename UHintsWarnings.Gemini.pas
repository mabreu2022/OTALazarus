unit UHintsWarnings.Gemini;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Process, fpjson, jsonparser,
  UHintsWarnings.Config, UHintsWarnings.Model;

type
  TGeminiCallback = procedure(const AResult: string; const AError: string) of object;

  { TGeminiAsyncThread: Executa o Gemini CLI em segundo plano sem travar a IDE }
  TGeminiAsyncThread = class(TThread)
  private
    FItem: TFPCDiagnosticItem;
    FContextCode: string;
    FResult: string;
    FError: string;
    FCallback: TGeminiCallback;
    procedure DoSyncCallback;
  protected
    procedure Execute; override;
  public
    constructor Create(AItem: TFPCDiagnosticItem; const AContextCode: string; ACallback: TGeminiCallback);
  end;

  { TGeminiService: Servico de integracao com Gemini CLI e Google AI }
  TGeminiService = class
  private
    FLastError: string;
    function GetGeminiBinaryPath: string;
  public
    constructor Create;
    destructor Destroy; override;

    // Verifica se o binario do Gemini CLI esta instalado
    function IsCLIInstalled: boolean;

    // Executa analise sincrona
    function AnalyzeDiagnostic(AItem: TFPCDiagnosticItem;
      const AContextCode: string): string;

    // Executa analise assincrona em thread para a IDE nunca travar
    procedure AnalyzeDiagnosticAsync(AItem: TFPCDiagnosticItem;
      const AContextCode: string; ACallback: TGeminiCallback);

    property LastError: string read FLastError;
  end;

function GeminiService: TGeminiService;

implementation

var
  GGeminiService: TGeminiService = nil;

function GeminiService: TGeminiService;
begin
  if GGeminiService = nil then
    GGeminiService := TGeminiService.Create;
  Result := GGeminiService;
end;

{ TGeminiAsyncThread }

constructor TGeminiAsyncThread.Create(AItem: TFPCDiagnosticItem;
  const AContextCode: string; ACallback: TGeminiCallback);
begin
  inherited Create(True); // Suspended
  FreeOnTerminate := True;
  FItem := AItem;
  FContextCode := AContextCode;
  FCallback := ACallback;
  FResult := '';
  FError := '';
  Start;
end;

procedure TGeminiAsyncThread.DoSyncCallback;
begin
  if Assigned(FCallback) then
    FCallback(FResult, FError);
end;

procedure TGeminiAsyncThread.Execute;
begin
  try
    FResult := GeminiService.AnalyzeDiagnostic(FItem, FContextCode);
    FError := GeminiService.LastError;
  except
    on E: Exception do
      FError := E.Message;
  end;
  Synchronize(@DoSyncCallback);
end;

{ TGeminiService }

constructor TGeminiService.Create;
begin
  inherited Create;
  FLastError := '';
end;

destructor TGeminiService.Destroy;
begin
  inherited Destroy;
end;

function TGeminiService.GetGeminiBinaryPath: string;
var
  HomeDir, Candidate: string;
begin
  HomeDir := GetUserDir;
  // 1. Caminho integrado no binario do Antigravity IDE
  Candidate := HomeDir + '.gemini/antigravity-ide/bin/gemini';
  if FileExists(Candidate) then Exit(Candidate);

  // 2. Caminho instalado via npm local
  Candidate := HomeDir + '.local/bin/gemini';
  if FileExists(Candidate) then Exit(Candidate);

  // 3. Caminho padrao do sistema
  if FileExists('/usr/local/bin/gemini') then Exit('/usr/local/bin/gemini');
  if FileExists('/usr/bin/gemini') then Exit('/usr/bin/gemini');

  Result := 'gemini';
end;

function TGeminiService.IsCLIInstalled: boolean;
var
  BinPath: string;
begin
  BinPath := GetGeminiBinaryPath;
  Result := FileExists(BinPath) or (BinPath = 'gemini');
end;

procedure TGeminiService.AnalyzeDiagnosticAsync(AItem: TFPCDiagnosticItem;
  const AContextCode: string; ACallback: TGeminiCallback);
begin
  TGeminiAsyncThread.Create(AItem, AContextCode, ACallback);
end;

function TGeminiService.AnalyzeDiagnostic(AItem: TFPCDiagnosticItem;
  const AContextCode: string): string;
var
  AProcess: TProcess;
  OutputStream: TStringList;
  PromptText, BinPath, ApiKey: string;
  Cfg: THintsWarningsConfig;
  I: integer;
begin
  Result := '';
  FLastError := '';
  if AItem = nil then Exit('Nenhum item selecionado para analise.');

  Cfg := HintsWarningsConfig;
  BinPath := GetGeminiBinaryPath;

  ApiKey := Trim(Cfg.GeminiAPIKey);
  if ApiKey = '' then
    ApiKey := GetEnvironmentVariable('GEMINI_API_KEY');

  if ApiKey = '' then
  begin
    FLastError := 'GEMINI_API_KEY nao configurada.';
    Exit('Chave da API do Google Gemini (GEMINI_API_KEY) nao informada.' + LineEnding + LineEnding +
         '1. Obtenha uma chave gratuita em: https://aistudio.google.com/' + LineEnding +
         '2. Clique no botao "Configuracoes..." no Analisador e insira a sua Chave da API Gemini.');
  end;

  // Monta o prompt especializado em Object Pascal / Free Pascal / Lazarus
  PromptText :=
    'Voce e um Arquiteto de Software Senior e Engenheiro Especialista em Free Pascal (FPC) e Lazarus IDE.' + LineEnding +
    'Analise o seguinte diagnostico de compilacao no Linux e forneca instrucoes diretas e claras em Portugues do Brasil.' + LineEnding + LineEnding +
    '--- DADOS DO DIAGNOSTICO ---' + LineEnding +
    Format('Arquivo: %s', [AItem.FileName]) + LineEnding +
    Format('Linha: %d, Coluna: %d', [AItem.Line, AItem.Column]) + LineEnding +
    Format('Severidade: %s', [AItem.SeverityToString]) + LineEnding +
    Format('Codigo FPC: %d', [AItem.MsgCode]) + LineEnding +
    Format('Mensagem do Compilador: %s', [AItem.MessageText]) + LineEnding;

  if Trim(AContextCode) <> '' then
  begin
    PromptText := PromptText + LineEnding +
      '--- TRECHO DE CODIGO FONTE AO REDOR DO ERRO ---' + LineEnding +
      AContextCode + LineEnding;
  end;

  PromptText := PromptText + LineEnding +
    '--- ESTRUTURA DA SUA RESPOSTA ---' + LineEnding +
    '1. 🔍 DIAGNOSTICO: O que causa o erro ou alerta.' + LineEnding +
    '2. 🛠️ COMO RESOLVER NO LAZARUS/LINUX: Solucao passo a passo (ex: compatibilidade Windows vs Linux, ShellExecute vs OpenURL/OpenDocument do LCLIntf).' + LineEnding +
    '3. 💻 CODIGO SUGERIDO: O trecho corrigido pronto para copiar e colar.';

  AProcess := TProcess.Create(nil);
  OutputStream := TStringList.Create;
  try
    AProcess.Executable := BinPath;
    AProcess.Parameters.Add('--skip-trust');
    AProcess.Parameters.Add('-p');
    AProcess.Parameters.Add(PromptText);
    AProcess.Parameters.Add('-o');
    AProcess.Parameters.Add('text');

    // Herda e injeta GEMINI_API_KEY no ambiente do processo filho
    for I := 1 to GetEnvironmentVariableCount do
      AProcess.Environment.Add(GetEnvironmentString(I));
    AProcess.Environment.Add('GEMINI_API_KEY=' + ApiKey);
    AProcess.Environment.Add('GEMINI_CLI_TRUST_WORKSPACE=true');

    AProcess.Options := [poUsePipes, poStderrToOutPut];
    AProcess.ShowWindow := swoNone;

    try
      AProcess.Execute;

      // Le a saida do processo
      while AProcess.Running do
        Sleep(100);

      OutputStream.LoadFromStream(AProcess.Output);
      Result := OutputStream.Text;

      // Remove eventuais avisos de terminal dumb do inicio
      if Pos('Error generating content', Result) > 0 then
      begin
        FLastError := Result;
        Result := 'Erro retornado pela API do Gemini:' + LineEnding + Result;
      end;
    except
      on E: Exception do
      begin
        FLastError := E.Message;
        Result := 'Erro ao executar Gemini CLI: ' + E.Message;
      end;
    end;
  finally
    OutputStream.Free;
    AProcess.Free;
  end;
end;

initialization

finalization
  FreeAndNil(GGeminiService);

end.
