unit UHintsWarnings.Ollama;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fphttpclient, fpjson, jsonparser,
  UHintsWarnings.Config, UHintsWarnings.Model;

type
  TOllamaCallback = procedure(const AResult: string; const AError: string) of object;

  { TOllamaAsyncThread: Thread em segundo plano para nao congelar a IDE durante inferencia }
  TOllamaAsyncThread = class(TThread)
  private
    FItem: TFPCDiagnosticItem;
    FContextCode: string;
    FResult: string;
    FError: string;
    FCallback: TOllamaCallback;
    procedure DoSyncCallback;
  protected
    procedure Execute; override;
  public
    constructor Create(AItem: TFPCDiagnosticItem; const AContextCode: string; ACallback: TOllamaCallback);
  end;

  { TOllamaService: Integracao com servidor local Ollama para diagnostico por IA }
  TOllamaService = class
  private
    FLastError: string;
    FIsAvailable: boolean;
  public
    constructor Create;
    destructor Destroy; override;

    // Verifica se o servico Ollama esta rodando localmente
    function CheckAvailability(out AStatusMsg: string): boolean;

    // Obtem lista de modelos instalados no Ollama
    function GetInstalledModels(AModelList: TStrings): boolean;

    // Executa analise sincrona
    function AnalyzeDiagnostic(AItem: TFPCDiagnosticItem;
      const AContextCode: string): string;

    // Executa analise assincrona em thread para a IDE nunca travar
    procedure AnalyzeDiagnosticAsync(AItem: TFPCDiagnosticItem;
      const AContextCode: string; ACallback: TOllamaCallback);

    property LastError: string read FLastError;
    property IsAvailable: boolean read FIsAvailable;
  end;

function OllamaService: TOllamaService;

implementation

var
  GOllamaService: TOllamaService = nil;

function OllamaService: TOllamaService;
begin
  if GOllamaService = nil then
    GOllamaService := TOllamaService.Create;
  Result := GOllamaService;
end;

{ TOllamaAsyncThread }

constructor TOllamaAsyncThread.Create(AItem: TFPCDiagnosticItem;
  const AContextCode: string; ACallback: TOllamaCallback);
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

procedure TOllamaAsyncThread.DoSyncCallback;
begin
  if Assigned(FCallback) then
    FCallback(FResult, FError);
end;

procedure TOllamaAsyncThread.Execute;
begin
  try
    FResult := OllamaService.AnalyzeDiagnostic(FItem, FContextCode);
    FError := OllamaService.LastError;
  except
    on E: Exception do
      FError := E.Message;
  end;
  Synchronize(@DoSyncCallback);
end;

{ TOllamaService }

constructor TOllamaService.Create;
begin
  inherited Create;
  FLastError := '';
  FIsAvailable := False;
end;

destructor TOllamaService.Destroy;
begin
  inherited Destroy;
end;

function TOllamaService.CheckAvailability(out AStatusMsg: string): boolean;
var
  Client: TFPHTTPClient;
  Resp: string;
  JsonData: TJSONData;
  Cfg: THintsWarningsConfig;
  URL: string;
begin
  Result := False;
  FLastError := '';
  AStatusMsg := '';
  Cfg := HintsWarningsConfig;
  URL := Cfg.OllamaURL;
  if URL = '' then URL := 'http://localhost:11434';
  if URL[Length(URL)] = '/' then
    URL := Copy(URL, 1, Length(URL) - 1);

  Client := TFPHTTPClient.Create(nil);
  try
    try
      Client.IOTimeout := 2000;
      Resp := Client.Get(URL + '/api/tags');
      JsonData := GetJSON(Resp);
      try
        if (JsonData <> nil) and (JsonData.JSONType = jtObject) then
        begin
          FIsAvailable := True;
          AStatusMsg := 'Online (' + Cfg.OllamaModel + ')';
          Result := True;
        end;
      finally
        JsonData.Free;
      end;
    except
      on E: Exception do
      begin
        FIsAvailable := False;
        FLastError := E.Message;
        AStatusMsg := 'Offline (Ollama nao responde em ' + URL + ')';
      end;
    end;
  finally
    Client.Free;
  end;
end;

function TOllamaService.GetInstalledModels(AModelList: TStrings): boolean;
var
  Client: TFPHTTPClient;
  Resp: string;
  JsonObj: TJSONObject;
  ModelsArr: TJSONArray;
  I: integer;
  ModelObj: TJSONObject;
  Cfg: THintsWarningsConfig;
  URL: string;
begin
  Result := False;
  if AModelList = nil then Exit;
  AModelList.Clear;

  Cfg := HintsWarningsConfig;
  URL := Cfg.OllamaURL;
  if URL = '' then URL := 'http://localhost:11434';
  if URL[Length(URL)] = '/' then
    URL := Copy(URL, 1, Length(URL) - 1);

  Client := TFPHTTPClient.Create(nil);
  try
    try
      Client.IOTimeout := 3000;
      Resp := Client.Get(URL + '/api/tags');
      JsonObj := TJSONObject(GetJSON(Resp));
      try
        if JsonObj <> nil then
        begin
          ModelsArr := JsonObj.Get('models', TJSONArray(nil));
          if ModelsArr <> nil then
          begin
            for I := 0 to ModelsArr.Count - 1 do
            begin
              ModelObj := TJSONObject(ModelsArr.Items[I]);
              if ModelObj <> nil then
                AModelList.Add(ModelObj.Get('name', ''));
            end;
            Result := AModelList.Count > 0;
          end;
        end;
      finally
        JsonObj.Free;
      end;
    except
      on E: Exception do
        FLastError := E.Message;
    end;
  finally
    Client.Free;
  end;
end;

procedure TOllamaService.AnalyzeDiagnosticAsync(AItem: TFPCDiagnosticItem;
  const AContextCode: string; ACallback: TOllamaCallback);
begin
  TOllamaAsyncThread.Create(AItem, AContextCode, ACallback);
end;

function TOllamaService.AnalyzeDiagnostic(AItem: TFPCDiagnosticItem;
  const AContextCode: string): string;
var
  Client: TFPHTTPClient;
  Cfg: THintsWarningsConfig;
  PromptText, ReqBody, RespBody, URL: string;
  JsonReq, JsonResp, OptionsObj: TJSONObject;
  ModelUsed: string;
begin
  Result := '';
  FLastError := '';
  if AItem = nil then Exit('Nenhum item selecionado para analise.');

  Cfg := HintsWarningsConfig;
  URL := Cfg.OllamaURL;
  if URL = '' then URL := 'http://localhost:11434';
  if URL[Length(URL)] = '/' then
    URL := Copy(URL, 1, Length(URL) - 1);

  ModelUsed := Trim(Cfg.OllamaModel);
  if ModelUsed = '' then
    ModelUsed := 'qwen2.5-coder:3b';

  // Monta o prompt especializado em Object Pascal / Free Pascal / Lazarus
  PromptText :=
    'Voce e um Arquiteto de Software Senior e Engenheiro Especialista em Free Pascal (FPC) e Lazarus IDE.' + LineEnding +
    'Analise o seguinte diagnostico reportado pelo compilador Free Pascal no Linux e forneca instrucoes claras de resolucao em Portugues do Brasil.' + LineEnding + LineEnding +
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
    'Forneca a resposta de forma direta e objetiva, seguindo este formato:' + LineEnding +
    '1. 🔍 DIAGNOSTICO: Causa exata do problema.' + LineEnding +
    '2. 🛠️ COMO RESOLVER NO LAZARUS/LINUX: Solucao passo a passo (ex: compatibilidade Windows vs Linux, ShellExecute vs OpenURL/OpenDocument do LCLIntf, units ausentes).' + LineEnding +
    '3. 💻 CODIGO SUGERIDO: O trecho corrigido pronto para copiar e colar.';

  JsonReq := TJSONObject.Create;
  try
    JsonReq.Add('model', ModelUsed);
    JsonReq.Add('prompt', PromptText);
    JsonReq.Add('stream', False);

    // Permite respostas completas com codigo sem truncamento
    OptionsObj := TJSONObject.Create;
    OptionsObj.Add('num_predict', 3000);
    OptionsObj.Add('temperature', 0.2);
    JsonReq.Add('options', OptionsObj);

    ReqBody := JsonReq.AsJSON;
  finally
    JsonReq.Free;
  end;

  Client := TFPHTTPClient.Create(nil);
  try
    try
      Client.AddHeader('Content-Type', 'application/json');
      Client.IOTimeout := Cfg.OllamaTimeoutSec * 1000;
      if Client.IOTimeout < 30000 then Client.IOTimeout := 90000;

      Client.RequestBody := TRawByteStringStream.Create(ReqBody);
      RespBody := Client.Post(URL + '/api/generate');

      JsonResp := TJSONObject(GetJSON(RespBody));
      try
        if JsonResp <> nil then
          Result := JsonResp.Get('response', '');
      finally
        JsonResp.Free;
      end;
    except
      on E: Exception do
      begin
        FLastError := E.Message;
        Result := 'Erro ao consultar Ollama (' + ModelUsed + '): ' + E.Message + LineEnding +
                  'Verifique se o Ollama esta em execucao: ollama run ' + ModelUsed;
      end;
    end;
  finally
    if Client.RequestBody <> nil then
      Client.RequestBody.Free;
    Client.Free;
  end;
end;

initialization

finalization
  FreeAndNil(GOllamaService);

end.
