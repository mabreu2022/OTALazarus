unit UHintsWarnings.Database;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fgl, IBConnection, sqldb, db, UHintsWarnings.Config;

type
  { TFPCMessageDetails: Registro de dados consultados do catálogo Firebird }
  TFPCMessageDetails = record
    FoundInDB: boolean;
    Code: integer;
    Severity: string;
    MessagePattern: string;
    DescriptionPTBR: string;
    ProbableCause: string;
    ManualSolution: string;
    CanAutoFix: boolean;
    AutoFixStrategy: string;
  end;

  { Cache em memoria para evitar requisicoes repetidas ao banco }
  TFPCDetailsMap = specialize TFPGMap<Integer, TFPCMessageDetails>;

  { TFPCDatabaseManager: Singleton responsavel pela conexao, pool e cache }
  TFPCDatabaseManager = class
  private
    FConnection: TIBConnection;
    FTransaction: TSQLTransaction;
    FQuery: TSQLQuery;
    FCache: TFPCDetailsMap;
    FIsOffline: boolean;
    FLastError: string;
    procedure ConfigureConnection;
    procedure CreateComponents;
    procedure DestroyComponents;
  public
    constructor Create;
    destructor Destroy; override;

    function Connect: boolean;
    procedure Disconnect;
    procedure ResetConnection;
    function IsConnected: boolean;
    procedure ClearCache;

    { Consulta detalhes de um codigo numerico FPC, utilizando cache e query parametrizada }
    function GetDetails(const ACode: integer): TFPCMessageDetails;

    property IsOffline: boolean read FIsOffline;
    property LastError: string read FLastError;
  end;

function FPCDatabase: TFPCDatabaseManager;

implementation

var
  GDatabase: TFPCDatabaseManager = nil;

function FPCDatabase: TFPCDatabaseManager;
begin
  if GDatabase = nil then
    GDatabase := TFPCDatabaseManager.Create;
  Result := GDatabase;
end;

{ TFPCDatabaseManager }

procedure TFPCDatabaseManager.CreateComponents;
begin
  FConnection := TIBConnection.Create(nil);
  FTransaction := TSQLTransaction.Create(nil);
  FQuery := TSQLQuery.Create(nil);

  FConnection.LoginPrompt := False;
  FConnection.Transaction := FTransaction;
  FTransaction.DataBase := FConnection;
  FQuery.DataBase := FConnection;
  FQuery.Transaction := FTransaction;
end;

procedure TFPCDatabaseManager.DestroyComponents;
begin
  try
    if FQuery <> nil then
    begin
      if FQuery.Active then FQuery.Close;
      FreeAndNil(FQuery);
    end;
    if FTransaction <> nil then
    begin
      if FTransaction.Active then FTransaction.Rollback;
      FreeAndNil(FTransaction);
    end;
    if FConnection <> nil then
    begin
      if FConnection.Connected then FConnection.Close;
      FreeAndNil(FConnection);
    end;
  except
    // Suprime excecoes durante destruicao de componentes danificados
  end;
end;

constructor TFPCDatabaseManager.Create;
begin
  inherited Create;
  FCache := TFPCDetailsMap.Create;
  FIsOffline := False;
  FLastError := '';
  CreateComponents;
end;

destructor TFPCDatabaseManager.Destroy;
begin
  Disconnect;
  DestroyComponents;
  FreeAndNil(FCache);
  inherited Destroy;
end;

procedure TFPCDatabaseManager.ResetConnection;
begin
  Disconnect;
  DestroyComponents;
  CreateComponents;
  FLastError := '';
  FIsOffline := False;
end;

procedure TFPCDatabaseManager.ConfigureConnection;
var
  Cfg: THintsWarningsConfig;
  TargetHost: string;
begin
  Cfg := HintsWarningsConfig;
  TargetHost := Trim(Cfg.HostName);
  if (TargetHost = '') or (TargetHost = 'localhost') then
    TargetHost := '127.0.0.1';

  FConnection.HostName := TargetHost;
  FConnection.DatabaseName := Trim(Cfg.DatabasePath);
  FConnection.UserName := Trim(Cfg.UserName);
  FConnection.Password := Trim(Cfg.Password);
  FConnection.Port := Cfg.Port;
  FConnection.CharSet := 'UTF8';
  FConnection.LoginPrompt := False;
end;

function TFPCDatabaseManager.Connect: boolean;
begin
  Result := False;
  FLastError := '';
  try
    if (FConnection <> nil) and FConnection.Connected then
      Exit(True);

    // Se os componentes estiverem em estado incerto, recria limpo
    if (FConnection = nil) or (FTransaction = nil) or (FQuery = nil) then
      CreateComponents;

    ConfigureConnection;

    if FConnection.DatabaseName = '' then
    begin
      FIsOffline := True;
      FLastError := 'Caminho do banco de dados Firebird nao configurado.';
      Exit(False);
    end;

    FConnection.Open;
    FIsOffline := not FConnection.Connected;
    Result := FConnection.Connected;
  except
    on E: Exception do
    begin
      FIsOffline := True;
      FLastError := E.Message;
      Result := False;
    end;
  end;
end;

procedure TFPCDatabaseManager.Disconnect;
begin
  try
    if (FQuery <> nil) and FQuery.Active then
      FQuery.Close;
    if (FTransaction <> nil) and FTransaction.Active then
      FTransaction.Rollback;
    if (FConnection <> nil) and FConnection.Connected then
      FConnection.Close;
  except
    // Evita excecoes durante desconexao
  end;
end;

function TFPCDatabaseManager.IsConnected: boolean;
begin
  Result := (FConnection <> nil) and FConnection.Connected;
end;

procedure TFPCDatabaseManager.ClearCache;
begin
  if FCache <> nil then
    FCache.Clear;
end;

function TFPCDatabaseManager.GetDetails(const ACode: integer): TFPCMessageDetails;
var
  CacheIdx: integer;
begin
  // 1. Verifica se ja esta em cache na memoria
  CacheIdx := FCache.IndexOf(ACode);
  if CacheIdx >= 0 then
    Exit(FCache.Data[CacheIdx]);

  // Inicializa estrutura padrao (fallback)
  Result.FoundInDB := False;
  Result.Code := ACode;
  Result.Severity := '';
  Result.MessagePattern := '';
  Result.DescriptionPTBR := '';
  Result.ProbableCause := '';
  Result.ManualSolution := '';
  Result.CanAutoFix := False;
  Result.AutoFixStrategy := '';

  // 2. Se o banco nao estiver conectado, tenta conectar
  if not IsConnected then
  begin
    if not Connect then
    begin
      FCache.Add(ACode, Result);
      Exit;
    end;
  end;

  // 3. Executa a consulta SQL parametrizada
  try
    FQuery.Close;
    FQuery.SQL.Text :=
      'SELECT CODE, SEVERITY, MESSAGE_PATTERN, DESCRIPTION_PTBR, ' +
      '       PROBABLE_CAUSE, MANUAL_SOLUTION, CAN_AUTO_FIX, AUTO_FIX_STRATEGY ' +
      'FROM FPC_MESSAGES ' +
      'WHERE CODE = :CODE';
    FQuery.ParamByName('CODE').AsInteger := ACode;
    FQuery.Open;

    if not FQuery.EOF then
    begin
      Result.FoundInDB := True;
      Result.Code := FQuery.FieldByName('CODE').AsInteger;
      Result.Severity := FQuery.FieldByName('SEVERITY').AsString;
      Result.MessagePattern := FQuery.FieldByName('MESSAGE_PATTERN').AsString;
      Result.DescriptionPTBR := FQuery.FieldByName('DESCRIPTION_PTBR').AsString;
      Result.ProbableCause := FQuery.FieldByName('PROBABLE_CAUSE').AsString;
      Result.ManualSolution := FQuery.FieldByName('MANUAL_SOLUTION').AsString;
      Result.CanAutoFix := (FQuery.FieldByName('CAN_AUTO_FIX').AsString = 'S');
      Result.AutoFixStrategy := FQuery.FieldByName('AUTO_FIX_STRATEGY').AsString;
    end;
  except
    on E: Exception do
    begin
      FIsOffline := True;
      FLastError := E.Message;
    end;
  end;
  FQuery.Close;

  // 4. Salva no cache
  FCache.Add(ACode, Result);
end;

initialization

finalization
  FreeAndNil(GDatabase);

end.
