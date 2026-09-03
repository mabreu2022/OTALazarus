unit UHintsWarnings.QuickFix;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Controls,
  LazIDEIntf, SrcEditorIntf, CodeToolManager, CodeCache,
  UHintsWarnings.Model, UHintsWarnings.Database;

type
  { TFPCQuickFixService: Motor de refatoracao segura integrado ao CodeTools e SrcEditorIntf }
  TFPCQuickFixService = class
  public
    // Aplica a estrategia de Quick Fix apropriada para a ocorrencia
    class function ExecuteQuickFix(AItem: TFPCDiagnosticItem;
      out AResultMessage: string): boolean;

    // Codigo 5025: Remove unit nao utilizada de todas as secoes uses via CodeToolBoss
    class function Fix5025_RemoveUnit(const AFileName, AUnitName: string): boolean;

    // Codigo 5023: Injeta diretiva de supressao {%H-} ou Unused(Param) na assinatura
    class function Fix5023_ParameterNotUsed(const AFileName, AParamName: string;
      ALineNumber: integer): boolean;

    // Codigo 5024: Remove declaracao de variavel local nao utilizada na secao var
    class function Fix5024_RemoveVariable(const AFileName, AVarName: string;
      ALineNumber: integer): boolean;

    // Codigo 4055/4056: Substitui typecasts ordinais/ponteiros por PtrInt/PtrUInt
    class function Fix4055_ReplaceOrdinalCast(const AFileName: string;
      ALineNumber: integer): boolean;

    // Extrai o bloco de codigo limpo da resposta de IA (Ollama ou Gemini)
    class function ExtractCodeBlockFromAI(const AAIResponse: string): string;

    // Aplica o codigo sugerido pela IA diretamente no editor da IDE com suporte a Undo
    class function ApplyAICodeFix(AItem: TFPCDiagnosticItem;
      const AAICode: string; out AResultMessage: string): boolean;
  end;

implementation

{ TFPCQuickFixService }

class function TFPCQuickFixService.Fix5025_RemoveUnit(const AFileName, AUnitName: string): boolean;
var
  Code: TCodeBuffer;
  CleanUnit: string;
  Editor: TSourceEditorInterface;
  I, P: integer;
  LineText: string;
begin
  Result := False;
  CleanUnit := Trim(AUnitName);
  if CleanUnit = '' then Exit;

  // 1. Tenta refatoração nativa via CodeToolBoss
  try
    Code := CodeToolBoss.LoadFile(AFileName, True, False);
    if Code <> nil then
    begin
      if CodeToolBoss.RemoveUnitFromAllUsesSections(Code, CleanUnit) then
      begin
        CodeToolBoss.SourceChangeCache.Apply;
        Exit(True);
      end;
    end;
  except
    // Continua para fallback no buffer do editor se o CodeTools falhar
  end;

  // 2. Fallback resiliente no buffer ativo do editor caso o CodeTools não localize o nó
  if LazarusIDE.DoOpenEditorFile(AFileName, -1, -1, [ofRegularFile]) = mrOk then
  begin
    Editor := SourceEditorManagerIntf.SourceEditorIntfWithFilename(AFileName);
    if Editor = nil then
      Editor := SourceEditorManagerIntf.ActiveEditor;

    if Editor <> nil then
    begin
      Editor.BeginUndoBlock;
      try
        for I := 0 to Editor.Lines.Count - 1 do
        begin
          LineText := Editor.Lines[I];
          P := Pos(LowerCase(CleanUnit), LowerCase(LineText));
          if P > 0 then
          begin
            // Remove a unit da linha de uses
            LineText := StringReplace(LineText, CleanUnit + ',', '', [rfIgnoreCase]);
            LineText := StringReplace(LineText, ',' + CleanUnit, '', [rfIgnoreCase]);
            LineText := StringReplace(LineText, CleanUnit, '', [rfIgnoreCase]);
            Editor.Lines[I] := LineText;
            Editor.Modified := True;
            Result := True;
            Break;
          end;
        end;
      finally
        Editor.EndUndoBlock;
      end;
    end;
  end;
end;

class function TFPCQuickFixService.Fix5023_ParameterNotUsed(const AFileName,
  AParamName: string; ALineNumber: integer): boolean;
var
  Editor: TSourceEditorInterface;
  LineIdx: integer;
  LineText: string;
  P, EndP: integer;
  LeadChar, TrailChar: char;
begin
  Result := False;
  if Trim(AParamName) = '' then Exit;

  if LazarusIDE.DoOpenEditorFile(AFileName, -1, -1, [ofRegularFile]) <> mrOk then
    Exit;

  Editor := SourceEditorManagerIntf.SourceEditorIntfWithFilename(AFileName);
  if Editor = nil then
    Editor := SourceEditorManagerIntf.ActiveEditor;
  if Editor = nil then Exit;

  LineIdx := ALineNumber - 1;
  if (LineIdx < 0) or (LineIdx >= Editor.Lines.Count) then Exit;

  LineText := Editor.Lines[LineIdx];

  // Se já possui {%H-}, não duplica
  if Pos('{%H-}' + AParamName, LineText) > 0 then
    Exit(True);

  // Procura o identificador isolado do parâmetro na linha da assinatura
  P := 1;
  while P <= Length(LineText) do
  begin
    P := Pos(LowerCase(AParamName), LowerCase(LineText), P);
    if P = 0 then Break;

    LeadChar := ' ';
    if P > 1 then LeadChar := LineText[P - 1];

    EndP := P + Length(AParamName);
    TrailChar := ' ';
    if EndP <= Length(LineText) then TrailChar := LineText[EndP];

    if (not (LeadChar in ['a'..'z', 'A'..'Z', '0'..'9', '_'])) and
       (not (TrailChar in ['a'..'z', 'A'..'Z', '0'..'9', '_'])) then
    begin
      Editor.BeginUndoBlock;
      try
        // Insere a diretiva canônica {%H-} do Free Pascal antes do parâmetro
        LineText := Copy(LineText, 1, P - 1) + '{%H-}' + Copy(LineText, P, Length(LineText));
        Editor.Lines[LineIdx] := LineText;
        Editor.CursorTextXY := Point(P, ALineNumber);
      finally
        Editor.EndUndoBlock;
      end;
      Editor.Modified := True;
      Exit(True);
    end;
    Inc(P);
  end;
end;

class function TFPCQuickFixService.Fix5024_RemoveVariable(const AFileName,
  AVarName: string; ALineNumber: integer): boolean;
var
  Editor: TSourceEditorInterface;
  LineIdx: integer;
  LineText: string;
begin
  Result := False;
  if Trim(AVarName) = '' then Exit;

  if LazarusIDE.DoOpenEditorFile(AFileName, -1, -1, [ofRegularFile]) <> mrOk then
    Exit;

  Editor := SourceEditorManagerIntf.SourceEditorIntfWithFilename(AFileName);
  if Editor = nil then
    Editor := SourceEditorManagerIntf.ActiveEditor;
  if Editor = nil then Exit;

  LineIdx := ALineNumber - 1;
  if (LineIdx < 0) or (LineIdx >= Editor.Lines.Count) then Exit;

  LineText := Trim(Editor.Lines[LineIdx]);

  Editor.BeginUndoBlock;
  try
    // Se a linha declarar apenas essa variável (ex: "X: Integer;"), remove a linha inteira
    if (Pos(LowerCase(AVarName) + ':', LowerCase(LineText)) = 1) or
       (Pos(LowerCase(AVarName) + ' :', LowerCase(LineText)) = 1) then
    begin
      Editor.Lines.Delete(LineIdx);
      Result := True;
    end
    else
    begin
      // Caso haja mais de uma variável declarada na mesma linha (ex: "X, Y: Integer;"), remove o identificador
      LineText := StringReplace(Editor.Lines[LineIdx], AVarName + ',', '', [rfIgnoreCase]);
      LineText := StringReplace(LineText, ',' + AVarName, '', [rfIgnoreCase]);
      LineText := StringReplace(LineText, ', ' + AVarName, '', [rfIgnoreCase]);
      Editor.Lines[LineIdx] := LineText;
      Result := True;
    end;
  finally
    Editor.EndUndoBlock;
  end;
  Editor.Modified := True;
end;

class function TFPCQuickFixService.Fix4055_ReplaceOrdinalCast(const AFileName: string;
  ALineNumber: integer): boolean;
var
  Editor: TSourceEditorInterface;
  LineIdx: integer;
  LineText, NewText: string;
begin
  Result := False;

  if LazarusIDE.DoOpenEditorFile(AFileName, -1, -1, [ofRegularFile]) <> mrOk then
    Exit;

  Editor := SourceEditorManagerIntf.SourceEditorIntfWithFilename(AFileName);
  if Editor = nil then
    Editor := SourceEditorManagerIntf.ActiveEditor;
  if Editor = nil then Exit;

  LineIdx := ALineNumber - 1;
  if (LineIdx < 0) or (LineIdx >= Editor.Lines.Count) then Exit;

  LineText := Editor.Lines[LineIdx];
  NewText := LineText;

  if Pos('Integer(', NewText) > 0 then
    NewText := StringReplace(NewText, 'Integer(', 'PtrInt(', [])
  else if Pos('Cardinal(', NewText) > 0 then
    NewText := StringReplace(NewText, 'Cardinal(', 'PtrUInt(', [])
  else if Pos('LongInt(', NewText) > 0 then
    NewText := StringReplace(NewText, 'LongInt(', 'PtrInt(', [])
  else if Pos('DWord(', NewText) > 0 then
    NewText := StringReplace(NewText, 'DWord(', 'PtrUInt(', []);

  if NewText <> LineText then
  begin
    Editor.BeginUndoBlock;
    try
      Editor.Lines[LineIdx] := NewText;
    finally
      Editor.EndUndoBlock;
    end;
    Editor.Modified := True;
    Result := True;
  end;
end;

class function TFPCQuickFixService.ExecuteQuickFix(AItem: TFPCDiagnosticItem;
  out AResultMessage: string): boolean;
var
  TargetIdent: string;
  Q1, Q2: integer;
begin
  Result := False;
  AResultMessage := '';
  if AItem = nil then Exit;

  // Extrai identificador entre aspas da mensagem (ex: Parameter "Sender" not used)
  TargetIdent := '';
  Q1 := Pos('"', AItem.MessageText);
  if Q1 > 0 then
  begin
    Q2 := Pos('"', Copy(AItem.MessageText, Q1 + 1, Length(AItem.MessageText)));
    if Q2 > 0 then
      TargetIdent := Copy(AItem.MessageText, Q1 + 1, Q2 - 1);
  end;

  case AItem.MsgCode of
    // 5025: Unit not used
    5025:
    begin
      if TargetIdent = '' then
        TargetIdent := ExtractFileName(AItem.MessageText);
      Result := Fix5025_RemoveUnit(AItem.FileName, TargetIdent);
      if Result then
        AResultMessage := Format('Unit "%s" removida com sucesso da seção uses via CodeTools!', [TargetIdent])
      else
        AResultMessage := 'Não foi possível remover automaticamente a unit da seção uses.';
    end;

    // 5023: Parameter not used
    5023:
    begin
      Result := Fix5023_ParameterNotUsed(AItem.FileName, TargetIdent, AItem.Line);
      if Result then
        AResultMessage := Format('Diretiva {%%H-} inserida no parâmetro "%s" na linha %d!', [TargetIdent, AItem.Line])
      else
        AResultMessage := 'Parâmetro já protegido ou linha da assinatura não localizada.';
    end;

    // 5024: Variable not used
    5024:
    begin
      Result := Fix5024_RemoveVariable(AItem.FileName, TargetIdent, AItem.Line);
      if Result then
        AResultMessage := Format('Declaração da variável "%s" removida com sucesso na linha %d!', [TargetIdent, AItem.Line])
      else
        AResultMessage := 'Não foi possível remover a declaração da variável.';
    end;

    // 4055, 4056: Ordinal / Pointer cast not portable
    4055, 4056:
    begin
      Result := Fix4055_ReplaceOrdinalCast(AItem.FileName, AItem.Line);
      if Result then
        AResultMessage := Format('Typecast de ponteiro 64-bit substituído por PtrInt/PtrUInt na linha %d!', [AItem.Line])
      else
        AResultMessage := 'Nenhum typecast ordinal incompatível encontrado na linha.';
    end;

  else
    AResultMessage := 'Nenhuma regra de refatoração automatizada cadastrada para este código FPC.';
  end;
end;

class function TFPCQuickFixService.ExtractCodeBlockFromAI(const AAIResponse: string): string;
var
  P1, P2: integer;
  S: string;
begin
  Result := '';
  S := AAIResponse;

  // 1. Procura blocos formatados com crases triplas
  P1 := Pos('```pascal', LowerCase(S));
  if P1 > 0 then
    P1 := P1 + Length('```pascal')
  else
  begin
    P1 := Pos('```delphi', LowerCase(S));
    if P1 > 0 then
      P1 := P1 + Length('```delphi')
    else
    begin
      P1 := Pos('```', S);
      if P1 > 0 then
        P1 := P1 + Length('```');
    end;
  end;

  if P1 > 0 then
  begin
    P2 := Pos('```', Copy(S, P1, Length(S)));
    if P2 > 0 then
    begin
      Result := Trim(Copy(S, P1, P2 - 1));
      Exit;
    end;
  end;

  // 2. Procura pela seção de CODIGO SUGERIDO
  P1 := Pos('CODIGO SUGERIDO', UpperCase(S));
  if P1 > 0 then
  begin
    P2 := Pos(':', Copy(S, P1, Length(S)));
    if P2 > 0 then
    begin
      Result := Trim(Copy(S, P1 + P2, Length(S)));
      Result := StringReplace(Result, '```pascal', '', [rfIgnoreCase]);
      Result := StringReplace(Result, '```delphi', '', [rfIgnoreCase]);
      Result := StringReplace(Result, '```', '', [rfReplaceAll]);
      Result := Trim(Result);
      Exit;
    end;
  end;

  Result := Trim(AAIResponse);
end;

class function TFPCQuickFixService.ApplyAICodeFix(AItem: TFPCDiagnosticItem;
  const AAICode: string; out AResultMessage: string): boolean;
var
  Editor: TSourceEditorInterface;
  NewLines: TStringList;
  LineIdx, I: integer;
  OriginalLine, IndentStr: string;
  CleanAICode: string;
  Code: TCodeBuffer;
begin
  Result := False;
  AResultMessage := '';
  if (AItem = nil) or (Trim(AItem.FileName) = '') or (AItem.Line <= 0) then
  begin
    AResultMessage := 'Diagnóstico sem arquivo ou linha válidos para aplicar correção no código.';
    Exit;
  end;

  CleanAICode := ExtractCodeBlockFromAI(AAICode);
  if CleanAICode = '' then
  begin
    AResultMessage := 'Nenhum código sugerido pôde ser extraído da resposta da IA.';
    Exit;
  end;

  // Abre e posiciona no editor da IDE
  if LazarusIDE.DoOpenFileAndJumpToPos(AItem.FileName, Point(AItem.Column, AItem.Line), -1, -1, -1, [ofRegularFile]) <> mrOk then
  begin
    LazarusIDE.DoOpenEditorFile(AItem.FileName, -1, -1, [ofRegularFile]);
  end;

  Editor := SourceEditorManagerIntf.SourceEditorIntfWithFilename(AItem.FileName);
  if Editor = nil then
    Editor := SourceEditorManagerIntf.ActiveEditor;

  if Editor = nil then
  begin
    AResultMessage := 'Não foi possível acessar o editor de código da IDE para: ' + AItem.FileName;
    Exit;
  end;

  LineIdx := AItem.Line - 1;
  if (LineIdx < 0) or (LineIdx >= Editor.Lines.Count) then
  begin
    AResultMessage := Format('Linha %d fora do intervalo do arquivo (%d linhas).', [AItem.Line, Editor.Lines.Count]);
    Exit;
  end;

  OriginalLine := Editor.Lines[LineIdx];

  // Identifica indentação original da linha
  IndentStr := '';
  for I := 1 to Length(OriginalLine) do
  begin
    if OriginalLine[I] in [' ', #9] then
      IndentStr := IndentStr + OriginalLine[I]
    else
      Break;
  end;

  NewLines := TStringList.Create;
  try
    NewLines.Text := CleanAICode;

    // Preserva a indentação para cada linha inserida
    for I := 0 to NewLines.Count - 1 do
    begin
      if (IndentStr <> '') and (Pos(IndentStr, NewLines[I]) <> 1) and (Trim(NewLines[I]) <> '') then
        NewLines[I] := IndentStr + NewLines[I];
    end;

    Editor.BeginUndoBlock;
    try
      // Comenta a linha original problemática e insere o código novo
      Editor.Lines[LineIdx] := IndentStr + '// [Substituído por IA]: ' + Trim(OriginalLine);
      for I := NewLines.Count - 1 downto 0 do
        Editor.Lines.Insert(LineIdx + 1, NewLines[I]);

      Editor.CursorTextXY := Point(Length(IndentStr) + 1, AItem.Line + 1);
    finally
      Editor.EndUndoBlock;
    end;
    Editor.Modified := True;

    // Se o código fizer referência a OpenURL ou LCLIntf, garante LCLIntf na cláusula uses
    if (Pos('openurl', LowerCase(CleanAICode)) > 0) or (Pos('lclintf', LowerCase(CleanAICode)) > 0) then
    begin
      try
        Code := CodeToolBoss.LoadFile(AItem.FileName, True, False);
        if Code <> nil then
        begin
          if CodeToolBoss.AddUnitToMainUsesSectionIfNeeded(Code, 'LCLIntf', '', []) then
            CodeToolBoss.SourceChangeCache.Apply;
        end;
      except
        // Ignora caso CodeTools não consiga parsear
      end;
    end;

    Result := True;
    AResultMessage := Format('Código sugerido pela IA aplicado com sucesso nas linhas %d-%d!' + LineEnding +
      'A linha original foi comentada para segurança.' + LineEnding +
      'Pressione Ctrl+Z no editor se desejar desfazer.', [AItem.Line, AItem.Line + NewLines.Count]);
  finally
    NewLines.Free;
  end;
end;

end.
