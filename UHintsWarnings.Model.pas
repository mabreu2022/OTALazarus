unit UHintsWarnings.Model;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, RegExpr, fpjson, jsonparser, UHintsWarnings.Database;

type
  { Severidade do diagnóstico FPC }
  TFPCSeverity = (msHint, msNote, msWarning, msError, msFatal);
  TFPCSeverities = set of TFPCSeverity;

const
  AllSeverities: TFPCSeverities = [msHint, msNote, msWarning, msError, msFatal];

type
  { TQuickFixKind: Tipo de correção automática suportada }
  TQuickFixKind = (
    qfkNone,
    qfkInsertParamHintDirective,   // Inserir {%H-} antes do parâmetro não usado (FPC 5023, 5024)
    qfkInsertVarHintDirective,     // Inserir {%H-} antes da variável local não usada (FPC 5025)
    qfkReplaceOrdinalCast,         // Substituir Integer/Cardinal por PtrInt/PtrUInt (FPC 4055, 4056)
    qfkSuppressLocalDirective      // Inserir diretiva de supressão local {$WARN ... OFF}
  );

  { TQuickFixInfo: Metadados da dica explicativa e ação de correção rápida }
  TQuickFixInfo = record
    CanAutoFix: boolean;
    FixKind: TQuickFixKind;
    Title: string;
    ActionCaption: string;
    Explanation: string;
    RecommendedFix: string;
    TargetIdentifier: string;
  end;

  { TFPCDiagnosticItem: Representa uma ocorrência única de diagnóstico do compilador }
  TFPCDiagnosticItem = class
  private
    FFileName: string;
    FUnitName: string;
    FLine: integer;
    FColumn: integer;
    FSeverity: TFPCSeverity;
    FMsgCode: integer;
    FMessageText: string;
    FRawLine: string;
    FDBFound: boolean;
    FDescriptionPTBR: string;
    FProbableCause: string;
    FManualSolution: string;
    FCanAutoFix: boolean;
    FAutoFixStrategy: string;
    procedure SetFileName(const AValue: string);
    function GetUnitName: string;
  public
    constructor Create;
    destructor Destroy; override;

    function SeverityToString: string;
    function GetFormattedLocation: string;
    function ToCSVRow: string;
    function ToJSONObject: TJSONObject;
    procedure EnrichFromDB;

    property FileName: string read FFileName write SetFileName;
    property UnitName: string read GetUnitName write FUnitName;
    property Line: integer read FLine write FLine;
    property Column: integer read FColumn write FColumn;
    property Severity: TFPCSeverity read FSeverity write FSeverity;
    property MsgCode: integer read FMsgCode write FMsgCode;
    property MessageText: string read FMessageText write FMessageText;
    property RawLine: string read FRawLine write FRawLine;
    property DBFound: boolean read FDBFound write FDBFound;
    property DescriptionPTBR: string read FDescriptionPTBR write FDescriptionPTBR;
    property ProbableCause: string read FProbableCause write FProbableCause;
    property ManualSolution: string read FManualSolution write FManualSolution;
    property CanAutoFix: boolean read FCanAutoFix write FCanAutoFix;
    property AutoFixStrategy: string read FAutoFixStrategy write FAutoFixStrategy;
  end;

  { TFPCDiagnosticList: Gerenciador e repositório em memória dos diagnósticos }
  TFPCDiagnosticList = class
  private
    FItems: TFPList;
    function GetCount: integer;
    function GetItem(AIndex: integer): TFPCDiagnosticItem;
  public
    constructor Create;
    destructor Destroy; override;

    function Add(AItem: TFPCDiagnosticItem): integer;
    procedure Clear;
    function CountBySeverity(ASeverity: TFPCSeverity): integer;
    procedure GetUniqueUnits(AUnits: TStrings);
    procedure Filter(AFilterSeverities: TFPCSeverities; const ASearchText: string; ATargetList: TFPCDiagnosticList);

    function ExportToCSV: string;
    function ExportToJSON: string;

    property Count: integer read GetCount;
    property Items[AIndex: integer]: TFPCDiagnosticItem read GetItem; default;
  end;

  { TFPCMessageParser: Parser especializado em saídas e logs do FPC }
  TFPCMessageParser = class
  private
    class function StringToSeverity(const AStr: string): TFPCSeverity;
  public
    class function ParseRawLine(const ALine: string): TFPCDiagnosticItem;
    class procedure ParseText(const AText: string; ATargetList: TFPCDiagnosticList);
  end;

  { TFPCQuickFixManager: Base de conhecimento de diagnósticos e motor de auto-correção }
  TFPCQuickFixManager = class
  public
    class function Analyze(AItem: TFPCDiagnosticItem): TQuickFixInfo;
    class function ApplyFixToLine(const ALineText: string; const AFixInfo: TQuickFixInfo;
      out AModifiedText: string): boolean;
  end;

function FPCSeverityToString(ASeverity: TFPCSeverity): string;
function StringToFPCSeverity(const AStr: string): TFPCSeverity;

implementation

function FPCSeverityToString(ASeverity: TFPCSeverity): string;
begin
  case ASeverity of
    msHint:    Result := 'Hint';
    msNote:    Result := 'Note';
    msWarning: Result := 'Warning';
    msError:   Result := 'Error';
    msFatal:   Result := 'Fatal';
  else
    Result := 'Unknown';
  end;
end;

function StringToFPCSeverity(const AStr: string): TFPCSeverity;
var
  S: string;
begin
  S := UpperCase(Trim(AStr));
  if S = 'HINT' then
    Result := msHint
  else if S = 'NOTE' then
    Result := msNote
  else if (S = 'WARNING') or (S = 'AVISO') then
    Result := msWarning
  else if (S = 'ERROR') or (S = 'ERRO') then
    Result := msError
  else if (S = 'FATAL') then
    Result := msFatal
  else
    Result := msHint;
end;

{ TFPCDiagnosticItem }

constructor TFPCDiagnosticItem.Create;
begin
  inherited Create;
  FFileName := '';
  FUnitName := '';
  FLine := 0;
  FColumn := 0;
  FSeverity := msHint;
  FMsgCode := 0;
  FMessageText := '';
  FRawLine := '';
  FDBFound := False;
  FDescriptionPTBR := '';
  FProbableCause := '';
  FManualSolution := '';
  FCanAutoFix := False;
  FAutoFixStrategy := '';
end;

destructor TFPCDiagnosticItem.Destroy;
begin
  inherited Destroy;
end;

procedure TFPCDiagnosticItem.EnrichFromDB;
var
  Details: TFPCMessageDetails;
begin
  if FMsgCode <= 0 then Exit;
  try
    Details := FPCDatabase.GetDetails(FMsgCode);
    FDBFound := Details.FoundInDB;
    if Details.FoundInDB then
    begin
      FDescriptionPTBR := Details.DescriptionPTBR;
      FProbableCause := Details.ProbableCause;
      FManualSolution := Details.ManualSolution;
      FCanAutoFix := Details.CanAutoFix;
      FAutoFixStrategy := Details.AutoFixStrategy;
    end;
  except
    FDBFound := False;
  end;
end;

procedure TFPCDiagnosticItem.SetFileName(const AValue: string);
begin
  FFileName := AValue;
  FUnitName := ExtractFileName(AValue);
end;

function TFPCDiagnosticItem.GetUnitName: string;
begin
  if Trim(FUnitName) <> '' then
    Result := FUnitName
  else if Trim(FFileName) <> '' then
    Result := ExtractFileName(FFileName)
  else
    Result := 'Projeto / Opções Globais';
end;

function TFPCDiagnosticItem.SeverityToString: string;
begin
  Result := FPCSeverityToString(FSeverity);
end;

function TFPCDiagnosticItem.GetFormattedLocation: string;
begin
  if (FLine > 0) and (FColumn > 0) then
    Result := Format('%s(%d,%d)', [GetUnitName, FLine, FColumn])
  else if FLine > 0 then
    Result := Format('%s(%d)', [GetUnitName, FLine])
  else
    Result := GetUnitName;
end;

function TFPCDiagnosticItem.ToCSVRow: string;
var
  SanitizedMsg: string;
begin
  SanitizedMsg := StringReplace(FMessageText, '"', '""', [rfReplaceAll]);
  Result := Format('"%s";"%s";%d;%d;"%s";%d;"%s"', [
    FFileName,
    GetUnitName,
    FLine,
    FColumn,
    SeverityToString,
    FMsgCode,
    SanitizedMsg
  ]);
end;

function TFPCDiagnosticItem.ToJSONObject: TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.Add('file', FFileName);
  Result.Add('unit', GetUnitName);
  Result.Add('line', FLine);
  Result.Add('column', FColumn);
  Result.Add('severity', SeverityToString);
  Result.Add('code', FMsgCode);
  Result.Add('message', FMessageText);
  Result.Add('raw', FRawLine);
end;

{ TFPCDiagnosticList }

constructor TFPCDiagnosticList.Create;
begin
  inherited Create;
  FItems := TFPList.Create;
end;

destructor TFPCDiagnosticList.Destroy;
begin
  Clear;
  FreeAndNil(FItems);
  inherited Destroy;
end;

procedure TFPCDiagnosticList.Clear;
var
  I: integer;
begin
  for I := 0 to FItems.Count - 1 do
    TObject(FItems[I]).Free;
  FItems.Clear;
end;

function TFPCDiagnosticList.GetCount: integer;
begin
  Result := FItems.Count;
end;

function TFPCDiagnosticList.GetItem(AIndex: integer): TFPCDiagnosticItem;
begin
  Result := TFPCDiagnosticItem(FItems[AIndex]);
end;

function TFPCDiagnosticList.Add(AItem: TFPCDiagnosticItem): integer;
begin
  Result := FItems.Add(AItem);
end;

function TFPCDiagnosticList.CountBySeverity(ASeverity: TFPCSeverity): integer;
var
  I: integer;
begin
  Result := 0;
  for I := 0 to FItems.Count - 1 do
  begin
    if TFPCDiagnosticItem(FItems[I]).Severity = ASeverity then
      Inc(Result);
  end;
end;

procedure TFPCDiagnosticList.GetUniqueUnits(AUnits: TStrings);
var
  I: integer;
  UName: string;
begin
  if AUnits = nil then Exit;
  AUnits.BeginUpdate;
  try
    AUnits.Clear;
    for I := 0 to FItems.Count - 1 do
    begin
      UName := Trim(TFPCDiagnosticItem(FItems[I]).UnitName);
      if UName = '' then
        UName := 'Projeto / Opções Globais';
      if AUnits.IndexOf(UName) = -1 then
        AUnits.Add(UName);
    end;
  finally
    AUnits.EndUpdate;
  end;
end;

procedure TFPCDiagnosticList.Filter(AFilterSeverities: TFPCSeverities;
  const ASearchText: string; ATargetList: TFPCDiagnosticList);
var
  I: integer;
  Item, ClonedItem: TFPCDiagnosticItem;
  SearchLower: string;
  MatchesSearch: boolean;
begin
  if ATargetList = nil then Exit;
  ATargetList.Clear;

  SearchLower := LowerCase(Trim(ASearchText));

  for I := 0 to FItems.Count - 1 do
  begin
    Item := TFPCDiagnosticItem(FItems[I]);

    if not (Item.Severity in AFilterSeverities) then
      Continue;

    if SearchLower <> '' then
    begin
      MatchesSearch := (Pos(SearchLower, LowerCase(Item.UnitName)) > 0) or
                       (Pos(SearchLower, LowerCase(Item.FileName)) > 0) or
                       (Pos(SearchLower, LowerCase(Item.MessageText)) > 0) or
                       (Pos(SearchLower, IntToStr(Item.MsgCode)) > 0);
      if not MatchesSearch then
        Continue;
    end;

    ClonedItem := TFPCDiagnosticItem.Create;
    ClonedItem.FileName := Item.FileName;
    ClonedItem.UnitName := Item.UnitName;
    ClonedItem.Line := Item.Line;
    ClonedItem.Column := Item.Column;
    ClonedItem.Severity := Item.Severity;
    ClonedItem.MsgCode := Item.MsgCode;
    ClonedItem.MessageText := Item.MessageText;
    ClonedItem.RawLine := Item.RawLine;

    ATargetList.Add(ClonedItem);
  end;
end;

function TFPCDiagnosticList.ExportToCSV: string;
var
  I: integer;
  Lines: TStringList;
begin
  Lines := TStringList.Create;
  try
    Lines.Add('FileName;UnitName;Line;Column;Severity;MsgCode;MessageText');
    for I := 0 to FItems.Count - 1 do
      Lines.Add(TFPCDiagnosticItem(FItems[I]).ToCSVRow);
    Result := Lines.Text;
  finally
    Lines.Free;
  end;
end;

function TFPCDiagnosticList.ExportToJSON: string;
var
  I: integer;
  RootObj: TJSONObject;
  ItemsArray: TJSONArray;
begin
  RootObj := TJSONObject.Create;
  try
    RootObj.Add('total', FItems.Count);
    RootObj.Add('hints', CountBySeverity(msHint));
    RootObj.Add('notes', CountBySeverity(msNote));
    RootObj.Add('warnings', CountBySeverity(msWarning));
    RootObj.Add('errors', CountBySeverity(msError));
    RootObj.Add('fatals', CountBySeverity(msFatal));

    ItemsArray := TJSONArray.Create;
    for I := 0 to FItems.Count - 1 do
      ItemsArray.Add(TFPCDiagnosticItem(FItems[I]).ToJSONObject);

    RootObj.Add('diagnostics', ItemsArray);
    Result := RootObj.FormatJSON;
  finally
    RootObj.Free;
  end;
end;

{ TFPCMessageParser }

class function TFPCMessageParser.StringToSeverity(const AStr: string): TFPCSeverity;
begin
  Result := StringToFPCSeverity(AStr);
end;

class function TFPCMessageParser.ParseRawLine(const ALine: string): TFPCDiagnosticItem;
var
  Regex: TRegExpr;
  Matched: boolean;
  Item: TFPCDiagnosticItem;
  PParOpen, PParClose, PColon: integer;
  CoordStr, SevStr, Remainder: string;
  CommaPos: integer;
begin
  Result := nil;
  if Trim(ALine) = '' then Exit;

  // 1. Regex de alta precisão para o padrão do Free Pascal Compiler
  // Exemplo: uprincipal.pas(145,22) Hint: (5023) Parameter "Sender" not used
  Regex := TRegExpr.Create;
  try
    Regex.Expression := '^([^\(\)]+)\((\d+)(?:,(\d+))?\)\s+(Fatal|Error|Warning|Note|Hint):\s+(?:\((\d+)\)\s+)?(.*)$';
    Regex.ModifierI := True;

    Matched := Regex.Exec(ALine);
    if Matched then
    begin
      Item := TFPCDiagnosticItem.Create;
      Item.RawLine := ALine;
      Item.FileName := Trim(Regex.Match[1]);
      Item.Line := StrToIntDef(Regex.Match[2], 0);
      if Regex.Match[3] <> '' then
        Item.Column := StrToIntDef(Regex.Match[3], 0)
      else
        Item.Column := 1;

      Item.Severity := StringToSeverity(Regex.Match[4]);

      if Regex.Match[5] <> '' then
        Item.MsgCode := StrToIntDef(Regex.Match[5], 0)
      else
        Item.MsgCode := 0;

      Item.MessageText := Trim(Regex.Match[6]);
      Result := Item;
      Exit;
    end;
  finally
    Regex.Free;
  end;

  // 2. Fallback por manipulação de strings para arquivos com caminhos especiais
  PParOpen := Pos('(', ALine);
  PParClose := Pos(')', ALine);
  if (PParOpen > 1) and (PParClose > PParOpen) then
  begin
    CoordStr := Copy(ALine, PParOpen + 1, PParClose - PParOpen - 1);
    Remainder := Trim(Copy(ALine, PParClose + 1, Length(ALine)));

    PColon := Pos(':', Remainder);
    if PColon > 0 then
    begin
      SevStr := Trim(Copy(Remainder, 1, PColon - 1));
      if (UpperCase(SevStr) = 'HINT') or (UpperCase(SevStr) = 'NOTE') or
         (UpperCase(SevStr) = 'WARNING') or (UpperCase(SevStr) = 'ERROR') or
         (UpperCase(SevStr) = 'FATAL') then
      begin
        Item := TFPCDiagnosticItem.Create;
        Item.RawLine := ALine;
        Item.FileName := Trim(Copy(ALine, 1, PParOpen - 1));

        CommaPos := Pos(',', CoordStr);
        if CommaPos > 0 then
        begin
          Item.Line := StrToIntDef(Trim(Copy(CoordStr, 1, CommaPos - 1)), 0);
          Item.Column := StrToIntDef(Trim(Copy(CoordStr, CommaPos + 1, Length(CoordStr))), 1);
        end
        else
        begin
          Item.Line := StrToIntDef(Trim(CoordStr), 0);
          Item.Column := 1;
        end;

        Item.Severity := StringToSeverity(SevStr);
        Remainder := Trim(Copy(Remainder, PColon + 1, Length(Remainder)));

        if (Length(Remainder) > 3) and (Remainder[1] = '(') then
        begin
          PParClose := Pos(')', Remainder);
          if PParClose > 2 then
          begin
            Item.MsgCode := StrToIntDef(Copy(Remainder, 2, PParClose - 2), 0);
            Item.MessageText := Trim(Copy(Remainder, PParClose + 1, Length(Remainder)));
          end
          else
            Item.MessageText := Remainder;
        end
        else
          Item.MessageText := Remainder;

        Result := Item;
        Exit;
      end;
    end;
  end;

  // 3. Fallback para avisos, notas, dicas e erros globais de projeto/pacote (sem arquivo/coordenada)
  // Exemplo: Warning: other unit files search path (aka unit path) of "zcomponent 8.0" contains ...
  //          Aviso: (1234) Mensagem global ...
  //          [Warning] Mensagem ...
  Remainder := Trim(ALine);
  PColon := Pos(':', Remainder);
  if PColon in [4..15] then
  begin
    SevStr := UpperCase(Trim(Copy(Remainder, 1, PColon - 1)));
    if (Length(SevStr) > 2) and (SevStr[1] = '[') and (SevStr[Length(SevStr)] = ']') then
      SevStr := Copy(SevStr, 2, Length(SevStr) - 2);

    if (SevStr = 'WARNING') or (SevStr = 'AVISO') or
       (SevStr = 'HINT') or (SevStr = 'DICA') or
       (SevStr = 'NOTE') or (SevStr = 'NOTA') or
       (SevStr = 'ERROR') or (SevStr = 'ERRO') or
       (SevStr = 'FATAL') then
    begin
      Item := TFPCDiagnosticItem.Create;
      Item.RawLine := ALine;
      Item.FileName := '';
      Item.UnitName := 'Projeto / Opções Globais';
      Item.Line := 0;
      Item.Column := 0;
      Item.Severity := StringToSeverity(SevStr);

      Remainder := Trim(Copy(Remainder, PColon + 1, Length(Remainder)));
      if (Length(Remainder) > 3) and (Remainder[1] = '(') then
      begin
        PParClose := Pos(')', Remainder);
        if PParClose > 2 then
        begin
          Item.MsgCode := StrToIntDef(Copy(Remainder, 2, PParClose - 2), 0);
          Item.MessageText := Trim(Copy(Remainder, PParClose + 1, Length(Remainder)));
        end
        else
          Item.MessageText := Remainder;
      end
      else
        Item.MessageText := Remainder;

      Result := Item;
    end;
  end;
end;

class procedure TFPCMessageParser.ParseText(const AText: string;
  ATargetList: TFPCDiagnosticList);
var
  Lines: TStringList;
  I: integer;
  Item: TFPCDiagnosticItem;
begin
  if ATargetList = nil then Exit;
  Lines := TStringList.Create;
  try
    Lines.Text := AText;
    for I := 0 to Lines.Count - 1 do
    begin
      Item := ParseRawLine(Lines[I]);
      if Item <> nil then
        ATargetList.Add(Item);
    end;
  finally
    Lines.Free;
  end;
end;

{ TFPCQuickFixManager }

class function TFPCQuickFixManager.Analyze(AItem: TFPCDiagnosticItem): TQuickFixInfo;
var
  Q1, Q2: integer;
  Identifier: string;
  MsgLower: string;
begin
  Result.CanAutoFix := False;
  Result.FixKind := qfkNone;
  Result.Title := 'Diagnóstico do Compilador';
  Result.ActionCaption := '';
  Result.Explanation := '';
  Result.RecommendedFix := '';
  Result.TargetIdentifier := '';

  if AItem = nil then Exit;

  MsgLower := LowerCase(AItem.MessageText);

  // Extrai identificador entre aspas se houver (ex: Parameter "Sender" not used)
  Q1 := Pos('"', AItem.MessageText);
  if Q1 > 0 then
  begin
    Q2 := Pos('"', Copy(AItem.MessageText, Q1 + 1, Length(AItem.MessageText)));
    if Q2 > 0 then
      Identifier := Copy(AItem.MessageText, Q1 + 1, Q2 - 1);
  end;
  Result.TargetIdentifier := Identifier;

  // Se o item já tiver sido localizado e enriquecido pelo banco Firebird 5.0
  if AItem.DBFound then
  begin
    Result.Title := Format('[FPC %d] %s', [AItem.MsgCode, AItem.MessageText]);
    Result.Explanation := AItem.DescriptionPTBR + LineEnding + LineEnding +
                          '🔍 CAUSA PROVÁVEL:' + LineEnding + AItem.ProbableCause;
    Result.RecommendedFix := AItem.ManualSolution;
    Result.CanAutoFix := AItem.CanAutoFix;
    if AItem.CanAutoFix then
    begin
      case AItem.MsgCode of
        5025: Result.FixKind := qfkNone; // tratado pelo CodeTools
        5023: Result.FixKind := qfkInsertParamHintDirective;
        5024: Result.FixKind := qfkInsertVarHintDirective;
        4055, 4056: Result.FixKind := qfkReplaceOrdinalCast;
      else
        Result.FixKind := qfkNone;
      end;
      Result.ActionCaption := '⚡ Aplicar Correção Automática (' + AItem.AutoFixStrategy + ')';
    end;
    Exit;
  end;

  case AItem.MsgCode of
    // 5023 / 5024: Parâmetro não utilizado
    5023, 5024:
    begin
      Result.Title := 'Parâmetro Não Utilizado (' + Identifier + ')';
      Result.Explanation :=
        Format('O parâmetro "%s" foi declarado na assinatura do método/procedimento, mas nenhuma instrução interna o utiliza.' + LineEnding +
               'Em manipuladores de eventos da LCL (ex: OnClick com "Sender"), a assinatura é mandatória e não pode ser removida.', [Identifier]);
      Result.RecommendedFix :=
        '1. Insira a diretiva padrão do Free Pascal {%H-} imediatamente antes do parâmetro na declaração para silenciar o aviso.' + LineEnding +
        '   Exemplo: procedure TForm1.Click({%H-}' + Identifier + ': TObject);' + LineEnding +
        '2. Ou utilize o valor do parâmetro caso tenha sido esquecido na lógica.' + LineEnding +
        '3. Ou remova o parâmetro se for um método particular da sua aplicação.';
      if Identifier <> '' then
      begin
        Result.CanAutoFix := True;
        Result.FixKind := qfkInsertParamHintDirective;
        Result.ActionCaption := Format('⚡ Inserir {%%H-} no parâmetro "%s"', [Identifier]);
      end;
    end;

    // 5025: Variável local não utilizada
    5025:
    begin
      Result.Title := 'Variável Local Não Utilizada (' + Identifier + ')';
      Result.Explanation :=
        Format('A variável local "%s" foi alocada na seção "var", mas não é lida nem alterada.' + LineEnding +
               'Isto consome espaço desnecessário na pilha (stack) e polui o código-fonte.', [Identifier]);
      Result.RecommendedFix :=
        '1. Remova ou comente a linha da declaração da variável na seção "var".' + LineEnding +
        '2. Caso queira mantê-la temporariamente durante o desenvolvimento, insira a diretiva {%H-} antes do nome:' + LineEnding +
        '   Exemplo: {%H-}' + Identifier + ': Integer;';
      if Identifier <> '' then
      begin
        Result.CanAutoFix := True;
        Result.FixKind := qfkInsertVarHintDirective;
        Result.ActionCaption := Format('⚡ Inserir {%%H-} na variável "%s"', [Identifier]);
      end;
    end;

    // 5027, 5029: Variável não inicializada
    5027, 5029:
    begin
      Result.Title := 'Variável Não Inicializada (' + Identifier + ')';
      Result.Explanation :=
        Format('A variável "%s" parece estar sendo lida antes de receber um valor inicial atribuído com certeza.' + LineEnding +
               'No Free Pascal, variáveis locais da pilha contêm valores residuais imprevisíveis (lixo de memória), podendo gerar falhas silenciosas ou crashes esporádicos.', [Identifier]);
      Result.RecommendedFix :=
        '1. Atribua um valor inicial seguro logo no início do bloco begin/end da rotina.' + LineEnding +
        '   Exemplos: ' + Identifier + ' := 0;  ou  ' + Identifier + ' := '''';  ou  ' + Identifier + ' := nil;' + LineEnding +
        '2. Para records complexos, utilize: FillChar(' + Identifier + ', SizeOf(' + Identifier + '), 0);';
    end;

    // 4055, 4056: Conversão não portável de ponteiro e ordinal
    4055, 4056:
    begin
      Result.Title := 'Conversão Não Portável entre Ordinal e Ponteiro';
      Result.Explanation :=
        'Typecast direto entre tipo inteiro fixo (como Integer ou Cardinal) e Pointer.' + LineEnding +
        'CRÍTICO: Em sistemas 64-bit, ponteiros possuem 8 bytes (64 bits), enquanto Integer/Cardinal possuem 4 bytes (32 bits).' + LineEnding +
        'Esse typecast provoca perda dos 32 bits superiores do endereço, corrompendo a memória e causando "Access Violation" ao executar em 64 bits.';
      Result.RecommendedFix :=
        '1. Substitua o typecast "Integer(P)" ou "Cardinal(P)" pelo tipo nativo sensível à arquitetura:' + LineEnding +
        '   Use: PtrInt(P)  (para inteiros com sinal do tamanho do ponteiro)' + LineEnding +
        '   Use: PtrUInt(P) (para inteiros sem sinal do tamanho do ponteiro)' + LineEnding +
        '2. Para converter inteiro de volta para ponteiro:' + LineEnding +
        '   Use: Pointer(PtrUInt(Valor))  ou  Pointer(PtrInt(Valor))';
      Result.CanAutoFix := True;
      Result.FixKind := qfkReplaceOrdinalCast;
      Result.ActionCaption := '⚡ Substituir Integer/Cardinal por PtrInt/PtrUInt';
    end;

    // 4035: Construção de classe com métodos abstratos
    4035:
    begin
      Result.Title := 'Instanciação de Classe com Métodos Abstratos';
      Result.Explanation :=
        'A classe instanciada possui métodos virtuais marcados como "virtual; abstract;" que não foram implementados na subclasse.' + LineEnding +
        'Se o código tentar executar qualquer um desses métodos, o programa será abortado em tempo de execução com "Runtime Error 211 (Abstract Error)".';
      Result.RecommendedFix :=
        '1. Adicione a implementação do método na classe descendente utilizando a diretiva "override;".' + LineEnding +
        '2. Ou verifique se você deveria instanciar uma subclasse concreta especializada em vez desta classe base.';
    end;

    // 3100, 4046, 4047: Retorno da função não inicializado
    3100, 4046, 4047:
    begin
      Result.Title := 'Resultado da Função Não Atribuído (Result)';
      Result.Explanation :=
        'A função pode encerrar sem que a variável intrínseca "Result" tenha sido definida em todos os caminhos de execução.' + LineEnding +
        'O chamador da função receberá lixo de memória residual da pilha.';
      Result.RecommendedFix :=
        '1. Atribua um valor padrão na primeira linha da função (ex: Result := False; ou Result := ''''; ou Result := nil;).' + LineEnding +
        '2. Inspecione seus blocos "if/then/else" ou "case" para garantir que todas as ramificações definem Result.';
    end;

    // 5000, 5004: Identificador não encontrado
    5000, 5004:
    begin
      Result.Title := 'Identificador Não Encontrado';
      Result.Explanation :=
        Format('O compilador não localizou a declaração de "%s".', [Identifier]);
      Result.RecommendedFix :=
        '1. Verifique a grafia do nome (erros de digitação).' + LineEnding +
        '2. Adicione a unit responsável na cláusula "uses" da interface ou implementation.' + LineEnding +
        '3. Se o identificador pertencer a um componente ou classe, certifique-se de qualificar com o objeto (ex: Form1.' + Identifier + ').';
    end;

    // 10022: Unit não encontrada
    10022:
    begin
      Result.Title := 'Unit Não Encontrada pelo Compilador';
      Result.Explanation :=
        'O compilador Free Pascal não conseguiu localizar os arquivos fonte (.pas/.pp) ou compilados (.ppu) da unit indicada.';
      Result.RecommendedFix :=
        '1. Vá no menu do Lazarus: Projeto > Opções do Projeto > Opções do Compilador > Caminhos.' + LineEnding +
        '   Adicione a pasta contendo a unit no campo "Caminho de outras units (-Fu)".' + LineEnding +
        '2. Se a unit pertencer a uma biblioteca/pacote externo, vá em: Inspetor de Projeto > Adicionar > Novo Requisito e selecione o pacote correspondente.';
    end;

    // 3018: Erro de sintaxe
    3018:
    begin
      Result.Title := 'Erro de Sintaxe no Código';
      Result.Explanation :=
        'O compilador encontrou um símbolo inesperado na estrutura gramatical do Pascal.';
      Result.RecommendedFix :=
        '1. Verifique a linha IMEDIATAMENTE ANTERIOR: na maioria das vezes, o erro é causado por um ponto e vírgula ";" faltando na linha de cima.' + LineEnding +
        '2. Verifique se parênteses, colchetes ou aspas foram abertos e não fechados.' + LineEnding +
        '3. Verifique se não há blocos "begin" sem o respectivo "end".';
    end;

  else
    // Análise heurística caso o código FPC não esteja no cadastro específico
    if (Pos('parameter', MsgLower) > 0) and (Pos('not used', MsgLower) > 0) then
    begin
      Result.Title := 'Parâmetro Não Utilizado';
      Result.Explanation := 'O parâmetro informado não é referenciado no corpo do método.';
      Result.RecommendedFix := 'Insira a diretiva {%H-} antes do parâmetro para silenciar o aviso no Lazarus.';
      if Identifier <> '' then
      begin
        Result.CanAutoFix := True;
        Result.FixKind := qfkInsertParamHintDirective;
        Result.ActionCaption := Format('⚡ Inserir {%%H-} no parâmetro "%s"', [Identifier]);
      end;
    end
    else if (Pos('variable', MsgLower) > 0) and (Pos('not used', MsgLower) > 0) then
    begin
      Result.Title := 'Variável Não Utilizada';
      Result.Explanation := 'A variável local declarada não é lida nem gravada.';
      Result.RecommendedFix := 'Remova a variável ou utilize {%H-}NomeVar na seção "var".';
      if Identifier <> '' then
      begin
        Result.CanAutoFix := True;
        Result.FixKind := qfkInsertVarHintDirective;
        Result.ActionCaption := Format('⚡ Inserir {%%H-} na variável "%s"', [Identifier]);
      end;
    end
    else if Pos('not portable', MsgLower) > 0 then
    begin
      Result.Title := 'Código Não Portável (32/64-bit)';
      Result.Explanation := 'Conversão entre ponteiros e números inteiros pode causar perda de bits em sistemas de 64 bits.';
      Result.RecommendedFix := 'Utilize os tipos universais de ponteiro: PtrInt ou PtrUInt em vez de Integer/Cardinal.';
      Result.CanAutoFix := True;
      Result.FixKind := qfkReplaceOrdinalCast;
      Result.ActionCaption := '⚡ Substituir Integer/Cardinal por PtrInt/PtrUInt';
    end
    else
    begin
      Result.Title := 'Diagnóstico Geral FPC [' + AItem.SeverityToString + ']';
      case AItem.Severity of
        msError, msFatal:
        begin
          Result.Explanation := 'Erro impeditivo de compilação. O compilador não pôde gerar o binário.';
          Result.RecommendedFix := 'Inspecione a linha indicada e o contexto anterior. Verifique compatibilidade de tipos e declarações.';
        end;
        msWarning:
        begin
          Result.Explanation := 'Aviso de possível comportamento anômalo ou perda de desempenho/portabilidade.';
          Result.RecommendedFix := 'Corrija o código para prevenir bugs em execução ou suprima pontualmente se for comportamento intencional.';
        end;
        msNote, msHint:
        begin
          Result.Explanation := 'Dica ou observação do compilador para melhoria de estilo ou otimização de código.';
          Result.RecommendedFix := 'Verifique se há código morto, variáveis redundantes ou parâmetros desnecessários.';
        end;
      end;
    end;
  end;
end;

class function TFPCQuickFixManager.ApplyFixToLine(const ALineText: string;
  const AFixInfo: TQuickFixInfo; out AModifiedText: string): boolean;
var
  Target: string;
  P, EndP: integer;
  LeadChar, TrailChar: char;
begin
  Result := False;
  AModifiedText := ALineText;
  Target := AFixInfo.TargetIdentifier;

  case AFixInfo.FixKind of
    qfkInsertParamHintDirective, qfkInsertVarHintDirective:
    begin
      if Target = '' then Exit;

      // Se já possui a diretiva {%H-}, não duplica
      if Pos('{%H-}' + Target, ALineText) > 0 then Exit;

      // Procura a ocorrência exata do identificador como palavra inteira
      P := 1;
      while P <= Length(ALineText) do
      begin
        P := Pos(LowerCase(Target), LowerCase(ALineText), P);
        if P = 0 then Break;

        LeadChar := ' ';
        if P > 1 then LeadChar := ALineText[P - 1];

        EndP := P + Length(Target);
        TrailChar := ' ';
        if EndP <= Length(ALineText) then TrailChar := ALineText[EndP];

        // Confirma delimitadores de identificador Pascal (não alfanumérico e não sublinhado)
        if (not (LeadChar in ['a'..'z', 'A'..'Z', '0'..'9', '_'])) and
           (not (TrailChar in ['a'..'z', 'A'..'Z', '0'..'9', '_'])) then
        begin
          // Insere {%H-} antes do nome
          AModifiedText := Copy(ALineText, 1, P - 1) + '{%H-}' + Copy(ALineText, P, Length(ALineText));
          Result := True;
          Exit;
        end;
        Inc(P);
      end;
    end;

    qfkReplaceOrdinalCast:
    begin
      // Substitui Integer( por PtrInt( ou Cardinal( por PtrUInt(
      if Pos('Integer(', ALineText) > 0 then
      begin
        AModifiedText := StringReplace(ALineText, 'Integer(', 'PtrInt(', []);
        Result := True;
      end
      else if Pos('Cardinal(', ALineText) > 0 then
      begin
        AModifiedText := StringReplace(ALineText, 'Cardinal(', 'PtrUInt(', []);
        Result := True;
      end
      else if Pos('LongInt(', ALineText) > 0 then
      begin
        AModifiedText := StringReplace(ALineText, 'LongInt(', 'PtrInt(', []);
        Result := True;
      end
      else if Pos('DWord(', ALineText) > 0 then
      begin
        AModifiedText := StringReplace(ALineText, 'DWord(', 'PtrUInt(', []);
        Result := True;
      end;
    end;

  else
    Result := False;
  end;
end;

end.
