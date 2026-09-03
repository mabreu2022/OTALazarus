unit UHintsWarnings.View;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, ExtCtrls, StdCtrls,
  ComCtrls, Menus, Clipbrd, Types,
  UHintsWarnings.Model, UHintsWarnings.Config, UHintsWarnings.Database,
  UHintsWarnings.QuickFix, UHintsWarnings.Ollama, UHintsWarnings.Gemini,
  LazIDEIntf, IDEMsgIntf, IDEExternToolIntf, IDEWindowIntf, CompOptsIntf, SrcEditorIntf;

type
  { THintsWarningsViewForm }
  THintsWarningsViewForm = class(TForm)
    pnlTop: TPanel;
    pnlMetricTotal: TPanel;
    lblTotalVal: TLabel;
    lblTotalCaption: TLabel;
    pnlMetricWarnings: TPanel;
    lblWarningsVal: TLabel;
    lblWarningsCaption: TLabel;
    pnlMetricHints: TPanel;
    lblHintsVal: TLabel;
    lblHintsCaption: TLabel;
    pnlMetricNotes: TPanel;
    lblNotesVal: TLabel;
    lblNotesCaption: TLabel;
    pnlMetricErrors: TPanel;
    lblErrorsVal: TLabel;
    lblErrorsCaption: TLabel;
    pnlActionsRight: TPanel;
    lblProjectInfo: TLabel;
    btnBuildNow: TButton;
    btnPasteLog: TButton;
    pnlToolbar: TPanel;
    chkFilterWarnings: TCheckBox;
    chkFilterHints: TCheckBox;
    chkFilterNotes: TCheckBox;
    chkFilterErrors: TCheckBox;
    chkGroupByFile: TCheckBox;
    edtSearch: TEdit;
    btnReload: TButton;
    btnClear: TButton;
    btnExport: TButton;
    tvDiagnostics: TTreeView;
    splInspector: TSplitter;
    pnlInspector: TPanel;
    pnlInspHeader: TPanel;
    lblInspLocation: TLabel;
    lblInspMessage: TLabel;
    lblDBStatus: TLabel;
    lblAIStatus: TLabel;
    pgcInspector: TPageControl;
    tsFirebird: TTabSheet;
    memoFullGuide: TMemo;
    tsOllama: TTabSheet;
    pnlAIToolbar: TPanel;
    btnApplyAICode: TButton;
    btnCopyAICode: TButton;
    memoAIResult: TMemo;
    pnlInspButtons: TPanel;
    btnQuickFix: TButton;
    btnOllamaAI: TButton;
    btnGeminiAI: TButton;
    btnGoToCode: TButton;
    btnCopyDetails: TButton;
    btnConfigDB: TButton;
    btnReconnectDB: TButton;
    saveDialogExport: TSaveDialog;
    popExport: TPopupMenu;
    miExportCSV: TMenuItem;
    miExportJSON: TMenuItem;
    popTree: TPopupMenu;
    miTreeQuickFix: TMenuItem;
    miTreeOllamaAI: TMenuItem;
    miTreeGeminiAI: TMenuItem;
    miTreeGoToCode: TMenuItem;
    miTreeSep1: TMenuItem;
    miTreeCopyMsg: TMenuItem;
    procedure FormCreate({%H-}Sender: TObject);
    procedure FormDestroy({%H-}Sender: TObject);
    procedure OnFilterChanged({%H-}Sender: TObject);
    procedure btnReloadClick({%H-}Sender: TObject);
    procedure btnClearClick({%H-}Sender: TObject);
    procedure btnExportClick({%H-}Sender: TObject);
    procedure btnBuildNowClick({%H-}Sender: TObject);
    procedure btnPasteLogClick({%H-}Sender: TObject);
    procedure btnQuickFixClick({%H-}Sender: TObject);
    procedure btnOllamaAIClick({%H-}Sender: TObject);
    procedure btnGeminiAIClick({%H-}Sender: TObject);
    procedure btnCopyDetailsClick({%H-}Sender: TObject);
    procedure btnConfigDBClick({%H-}Sender: TObject);
    procedure btnReconnectDBClick({%H-}Sender: TObject);
    procedure miExportCSVClick({%H-}Sender: TObject);
    procedure miExportJSONClick({%H-}Sender: TObject);
    procedure tvDiagnosticsDblClick({%H-}Sender: TObject);
    procedure tvDiagnosticsSelectionChanged({%H-}Sender: TObject);
    procedure btnGoToCodeClick({%H-}Sender: TObject);
    procedure btnApplyAICodeClick({%H-}Sender: TObject);
    procedure btnCopyAICodeClick({%H-}Sender: TObject);
  private
    FMasterList: TFPCDiagnosticList;
    FFilteredList: TFPCDiagnosticList;
    function GetSelectedDiagnostic: TFPCDiagnosticItem;
    function GetActiveFilterSeverities: TFPCSeverities;
    procedure PopulateTreeView;
    procedure UpdateDetailsView(AItem: TFPCDiagnosticItem);
    procedure NavigateToItem(AItem: TFPCDiagnosticItem);
    procedure UpdateDBStatusBadge;
    function GetCodeContext(const AFileName: string; ALineNumber: integer): string;
    procedure OnOllamaAnalysisFinished(const AResult: string; const AError: string);
    procedure OnGeminiAnalysisFinished(const AResult: string; const AError: string);
  public
    procedure LoadFromIDE;
    procedure UpdateMetrics;
    procedure ApplyFilters;
    procedure UpdateProjectInfo;

    property MasterList: TFPCDiagnosticList read FMasterList;
  end;

var
  HintsWarningsViewForm: THintsWarningsViewForm = nil;

implementation

{$R *.lfm}

{ THintsWarningsViewForm }

procedure THintsWarningsViewForm.FormCreate(Sender: TObject);
begin
  FMasterList := TFPCDiagnosticList.Create;
  FFilteredList := TFPCDiagnosticList.Create;
  HintsWarningsViewForm := Self;

  HintsWarningsConfig.Load;
  if HintsWarningsConfig.AutoConnect then
    FPCDatabase.Connect;

  UpdateDBStatusBadge;
  UpdateMetrics;
  UpdateProjectInfo;
  UpdateDetailsView(nil);
end;

procedure THintsWarningsViewForm.FormDestroy(Sender: TObject);
begin
  if HintsWarningsViewForm = Self then
    HintsWarningsViewForm := nil;
  FreeAndNil(FFilteredList);
  FreeAndNil(FMasterList);
end;

procedure THintsWarningsViewForm.UpdateDBStatusBadge;
var
  AIStatusMsg: string;
begin
  // Status Firebird 5.0
  if FPCDatabase.IsConnected then
  begin
    lblDBStatus.Caption := '🔥 Firebird 5.0: Conectado';
    lblDBStatus.Font.Color := 16737792; // Teal
  end
  else if FPCDatabase.IsOffline then
  begin
    lblDBStatus.Caption := '⚠️ Firebird: Offline (Modo Local)';
    lblDBStatus.Font.Color := clMaroon;
  end
  else
  begin
    lblDBStatus.Caption := '⚪ Firebird: Desconectado';
    lblDBStatus.Font.Color := clGray;
  end;

  // Status Ollama IA
  if OllamaService.CheckAvailability(AIStatusMsg) then
  begin
    lblAIStatus.Caption := '🤖 Ollama: ' + HintsWarningsConfig.OllamaModel + ' (Pronto)';
    lblAIStatus.Font.Color := 32768; // Verde
  end
  else
  begin
    lblAIStatus.Caption := '🤖 Ollama: ' + HintsWarningsConfig.OllamaModel + ' (Offline)';
    lblAIStatus.Font.Color := clGray;
  end;
end;

procedure THintsWarningsViewForm.UpdateProjectInfo;
var
  ProjName: string;
begin
  if (LazarusIDE <> nil) and (LazarusIDE.ActiveProject <> nil) then
  begin
    ProjName := ExtractFileName(LazarusIDE.ActiveProject.ProjectInfoFile);
    if ProjName = '' then
      ProjName := ExtractFileName(LazarusIDE.ActiveProject.MainFile.Filename);
    if ProjName = '' then
      ProjName := 'Projeto Sem Título';

    lblProjectInfo.Caption := 'Projeto Ativo: ' + ProjName;
  end
  else
    lblProjectInfo.Caption := 'Projeto: (Nenhum projeto ativo carregado)';
end;

function THintsWarningsViewForm.GetActiveFilterSeverities: TFPCSeverities;
begin
  Result := [];
  if chkFilterWarnings.Checked then
    Include(Result, msWarning);
  if chkFilterHints.Checked then
    Include(Result, msHint);
  if chkFilterNotes.Checked then
    Include(Result, msNote);
  if chkFilterErrors.Checked then
  begin
    Include(Result, msError);
    Include(Result, msFatal);
  end;
end;

function THintsWarningsViewForm.GetSelectedDiagnostic: TFPCDiagnosticItem;
var
  SelNode: TTreeNode;
begin
  Result := nil;
  SelNode := tvDiagnostics.Selected;
  if (SelNode <> nil) and (SelNode.Data <> nil) then
    Result := TFPCDiagnosticItem(SelNode.Data);
end;

procedure THintsWarningsViewForm.UpdateMetrics;
var
  Tot, Warn, Hints, Notes, Errs: integer;
begin
  Tot := FMasterList.Count;
  Warn := FMasterList.CountBySeverity(msWarning);
  Hints := FMasterList.CountBySeverity(msHint);
  Notes := FMasterList.CountBySeverity(msNote);
  Errs := FMasterList.CountBySeverity(msError) + FMasterList.CountBySeverity(msFatal);

  lblTotalVal.Caption := IntToStr(Tot);
  lblWarningsVal.Caption := IntToStr(Warn);
  lblHintsVal.Caption := IntToStr(Hints);
  lblNotesVal.Caption := IntToStr(Notes);
  lblErrorsVal.Caption := IntToStr(Errs);

  chkFilterWarnings.Caption := Format('Warnings (%d)', [Warn]);
  chkFilterHints.Caption := Format('Hints (%d)', [Hints]);
  chkFilterNotes.Caption := Format('Notes (%d)', [Notes]);
  chkFilterErrors.Caption := Format('Erros (%d)', [Errs]);
end;

procedure THintsWarningsViewForm.PopulateTreeView;
var
  I, J: integer;
  UnitsList: TStringList;
  UnitNode, ItemNode: TTreeNode;
  Item: TFPCDiagnosticItem;
  CurrentUnit: string;
  CodePrefix, QuickFixTag, NodeText: string;
  UnitCount: integer;
begin
  tvDiagnostics.BeginUpdate;
  try
    tvDiagnostics.Items.Clear;

    if chkGroupByFile.Checked then
    begin
      UnitsList := TStringList.Create;
      try
        FFilteredList.GetUniqueUnits(UnitsList);
        UnitsList.Sort;

        for I := 0 to UnitsList.Count - 1 do
        begin
          CurrentUnit := UnitsList[I];
          UnitCount := 0;

          for J := 0 to FFilteredList.Count - 1 do
          begin
            if FFilteredList[J].UnitName = CurrentUnit then
              Inc(UnitCount);
          end;

          UnitNode := tvDiagnostics.Items.Add(nil, Format('%s (%d)', [CurrentUnit, UnitCount]));
          UnitNode.Data := nil;

          for J := 0 to FFilteredList.Count - 1 do
          begin
            Item := FFilteredList[J];
            if Item.UnitName = CurrentUnit then
            begin
              if Item.MsgCode > 0 then
                CodePrefix := Format('(%d) ', [Item.MsgCode])
              else
                CodePrefix := '';

              if Item.CanAutoFix then
                QuickFixTag := '[⚡ QuickFix] '
              else
                QuickFixTag := '';

              NodeText := Format('%s[%s] %sLinha %d, Col %d: %s', [
                QuickFixTag,
                Item.SeverityToString,
                CodePrefix,
                Item.Line,
                Item.Column,
                Item.MessageText
              ]);

              ItemNode := tvDiagnostics.Items.AddChild(UnitNode, NodeText);
              ItemNode.Data := Item;
            end;
          end;

          UnitNode.Expand(True);
        end;
      finally
        UnitsList.Free;
      end;
    end
    else
    begin
      for I := 0 to FFilteredList.Count - 1 do
      begin
        Item := FFilteredList[I];
        if Item.MsgCode > 0 then
          CodePrefix := Format('(%d) ', [Item.MsgCode])
        else
          CodePrefix := '';

        if Item.CanAutoFix then
          QuickFixTag := '[⚡ QuickFix] '
        else
          QuickFixTag := '';

        NodeText := Format('%s%s - [%s] %sL:%d, C:%d: %s', [
          QuickFixTag,
          Item.UnitName,
          Item.SeverityToString,
          CodePrefix,
          Item.Line,
          Item.Column,
          Item.MessageText
        ]);

        ItemNode := tvDiagnostics.Items.Add(nil, NodeText);
        ItemNode.Data := Item;
      end;
    end;
  finally
    tvDiagnostics.EndUpdate;
  end;
end;

procedure THintsWarningsViewForm.ApplyFilters;
begin
  FMasterList.Filter(GetActiveFilterSeverities, edtSearch.Text, FFilteredList);
  PopulateTreeView;
  UpdateDetailsView(nil);
end;

function THintsWarningsViewForm.GetCodeContext(const AFileName: string;
  ALineNumber: integer): string;
var
  Editor: TSourceEditorInterface;
  Lines: TStrings;
  I, StartL, EndL: integer;
  Prefix: string;
begin
  Result := '';
  if (AFileName = '') or not FileExists(AFileName) then Exit;

  Lines := nil;
  if SourceEditorManagerIntf <> nil then
  begin
    Editor := SourceEditorManagerIntf.SourceEditorIntfWithFilename(AFileName);
    if Editor <> nil then
      Lines := Editor.Lines;
  end;

  if (Lines = nil) and FileExists(AFileName) then
  begin
    Lines := TStringList.Create;
    try
      TStringList(Lines).LoadFromFile(AFileName);
    except
      Lines.Free;
      Lines := nil;
    end;
  end;

  if Lines = nil then Exit;

  try
    StartL := ALineNumber - 5;
    if StartL < 1 then StartL := 1;
    EndL := ALineNumber + 5;
    if EndL > Lines.Count then EndL := Lines.Count;

    for I := StartL to EndL do
    begin
      if I = ALineNumber then
        Prefix := '>> '
      else
        Prefix := '   ';
      Result := Result + Format('%s%4d: %s', [Prefix, I, Lines[I - 1]]) + LineEnding;
    end;
  finally
    if Lines is TStringList then
      Lines.Free;
  end;
end;

procedure THintsWarningsViewForm.UpdateDetailsView(AItem: TFPCDiagnosticItem);
var
  FixInfo: TQuickFixInfo;
  GuideText: string;
begin
  UpdateDBStatusBadge;

  if AItem = nil then
  begin
    lblInspLocation.Caption := 'Nenhum item selecionado';
    lblInspMessage.Caption := 'Selecione uma mensagem para consultar o catálogo Firebird 5.0 ou gerar diagnóstico via IA Ollama.';
    memoFullGuide.Lines.Text :=
      '=== INSPETOR DE DIAGNÓSTICOS DO FREE PASCAL ===' + LineEnding + LineEnding +
      '• Pressione "Compilar Projeto (F9)" ou Shift+F9 para interceptar avisos e erros da compilação.' + LineEnding +
      '• O plug-in consulta automaticamente o banco Firebird 5.0 para trazer explicações ricas em Português.' + LineEnding +
      '• Pressione "🤖 Diagnóstico IA (Ollama)" para obter análise profunda com o modelo local de IA.' + LineEnding +
      '• Itens marcados com [⚡ QuickFix] possuem refatoração automatizada via CodeTools/Editor.' + LineEnding +
      '• Clique em "Configurações..." para alterar Host, Porta, Banco ou Modelo do Ollama.';
    btnGoToCode.Enabled := False;
    btnCopyDetails.Enabled := False;
    btnQuickFix.Enabled := False;
    btnOllamaAI.Enabled := False;
    btnQuickFix.Caption := '⚡ Aplicar Quick Fix';
    miTreeQuickFix.Enabled := False;
    miTreeOllamaAI.Enabled := False;
  end
  else
  begin
    lblInspLocation.Caption := Format('%s - %s [Linha %d, Coluna %d]', [
      AItem.FileName,
      AItem.SeverityToString,
      AItem.Line,
      AItem.Column
    ]);

    if AItem.MsgCode > 0 then
      lblInspMessage.Caption := Format('Código FPC (%d): %s', [AItem.MsgCode, AItem.MessageText])
    else
      lblInspMessage.Caption := AItem.MessageText;

    FixInfo := TFPCQuickFixManager.Analyze(AItem);

    GuideText := '=== ' + UpperCase(FixInfo.Title) + ' ===' + LineEnding + LineEnding;

    if AItem.DBFound then
    begin
      GuideText := GuideText +
        '📝 DESCRIÇÃO TÉCNICA (FIREBIRD 5.0):' + LineEnding +
        AItem.DescriptionPTBR + LineEnding + LineEnding +
        '🔍 CAUSAS PROVÁVEIS:' + LineEnding +
        AItem.ProbableCause + LineEnding + LineEnding +
        '🛠️ COMO CORRIGIR (MANUAL):' + LineEnding +
        AItem.ManualSolution + LineEnding;

      if AItem.CanAutoFix then
        GuideText := GuideText + LineEnding +
          '⚡ CORREÇÃO AUTOMÁTICA DISPONÍVEL:' + LineEnding +
          'Estratégia: ' + AItem.AutoFixStrategy + LineEnding +
          'Clique no botão "⚡ Aplicar Quick Fix" ou use o menu de contexto.' + LineEnding;
    end
    else
    begin
      GuideText := GuideText +
        '📝 EXPLICAÇÃO (BASE LOCAL):' + LineEnding +
        FixInfo.Explanation + LineEnding + LineEnding +
        '👉 COMO RESOLVER:' + LineEnding +
        FixInfo.RecommendedFix + LineEnding;
    end;

    memoFullGuide.Lines.Text := GuideText;

    btnGoToCode.Enabled := True;
    btnCopyDetails.Enabled := True;
    btnOllamaAI.Enabled := True;
    miTreeOllamaAI.Enabled := True;

    btnQuickFix.Enabled := FixInfo.CanAutoFix or AItem.CanAutoFix;
    miTreeQuickFix.Enabled := btnQuickFix.Enabled;

    if btnQuickFix.Enabled then
    begin
      if AItem.AutoFixStrategy <> '' then
        btnQuickFix.Caption := '⚡ ' + AItem.AutoFixStrategy
      else if FixInfo.ActionCaption <> '' then
        btnQuickFix.Caption := FixInfo.ActionCaption
      else
        btnQuickFix.Caption := '⚡ Aplicar Quick Fix';
    end
    else
      btnQuickFix.Caption := '⚡ Quick Fix Indisponível';
  end;
end;

procedure THintsWarningsViewForm.NavigateToItem(AItem: TFPCDiagnosticItem);
var
  TargetCol, TargetLine: integer;
begin
  if (AItem = nil) or (Trim(AItem.FileName) = '') then Exit;

  TargetLine := AItem.Line;
  TargetCol := AItem.Column;
  if TargetLine < 1 then TargetLine := 1;
  if TargetCol < 1 then TargetCol := 1;

  if LazarusIDE.DoOpenFileAndJumpToPos(AItem.FileName, Point(TargetCol, TargetLine), -1, -1, -1, [ofRegularFile]) <> mrOk then
  begin
    LazarusIDE.DoOpenEditorFile(AItem.FileName, -1, -1, [ofRegularFile]);
  end;
end;

procedure THintsWarningsViewForm.LoadFromIDE;
var
  I, J, K: integer;
  View: TExtToolView;
  MsgLines: TMessageLines;
  MsgLine: TMessageLine;
  DiagItem, ParsedItem: TFPCDiagnosticItem;
  Tool: TAbstractExternalTool;
begin
  FMasterList.Clear;
  UpdateProjectInfo;

  if IDEMessagesWindow <> nil then
  begin
    for I := 0 to IDEMessagesWindow.ViewCount - 1 do
    begin
      View := IDEMessagesWindow.Views[I];
      if View = nil then Continue;

      MsgLines := View.Lines;
      if MsgLines = nil then Continue;

      MsgLines.EnterCriticalSection;
      try
        for J := 0 to MsgLines.Count - 1 do
        begin
          MsgLine := MsgLines[J];
          if MsgLine = nil then Continue;

          if MsgLine.Urgency in [mluHint, mluNote, mluWarning, mluError, mluFatal] then
          begin
            DiagItem := TFPCDiagnosticItem.Create;
            DiagItem.RawLine := MsgLine.OriginalLine;
            DiagItem.FileName := MsgLine.Filename;
            DiagItem.Line := MsgLine.Line;
            DiagItem.Column := MsgLine.Column;
            DiagItem.MsgCode := MsgLine.MsgID;
            DiagItem.MessageText := MsgLine.Msg;

            case MsgLine.Urgency of
              mluHint:    DiagItem.Severity := msHint;
              mluNote:    DiagItem.Severity := msNote;
              mluWarning: DiagItem.Severity := msWarning;
              mluError:   DiagItem.Severity := msError;
              mluFatal:   DiagItem.Severity := msFatal;
            else
              DiagItem.Severity := msHint;
            end;

            if (DiagItem.FileName = '') and (DiagItem.RawLine <> '') then
            begin
              ParsedItem := TFPCMessageParser.ParseRawLine(DiagItem.RawLine);
              if ParsedItem <> nil then
              begin
                DiagItem.FileName := ParsedItem.FileName;
                DiagItem.Line := ParsedItem.Line;
                DiagItem.Column := ParsedItem.Column;
                DiagItem.Severity := ParsedItem.Severity;
                if DiagItem.MsgCode = 0 then
                  DiagItem.MsgCode := ParsedItem.MsgCode;
                if DiagItem.MessageText = '' then
                  DiagItem.MessageText := ParsedItem.MessageText;
                ParsedItem.Free;
              end;
            end;

            if Trim(DiagItem.MessageText) = '' then
              DiagItem.MessageText := MsgLine.Msg;
            if Trim(DiagItem.MessageText) = '' then
              DiagItem.MessageText := MsgLine.OriginalLine;

            if Trim(DiagItem.FileName) = '' then
              DiagItem.UnitName := 'Projeto / Opções Globais';

            DiagItem.EnrichFromDB;
            FMasterList.Add(DiagItem);
          end;
        end;
      finally
        MsgLines.LeaveCriticalSection;
      end;
    end;
  end;

  if (FMasterList.Count = 0) and (ExternalToolList <> nil) then
  begin
    ExternalToolList.EnterCriticalSection;
    try
      for I := 0 to ExternalToolList.Count - 1 do
      begin
        Tool := ExternalToolList[I];
        if Tool = nil then Continue;

        Tool.EnterCriticalSection;
        try
          if Tool.WorkerMessages <> nil then
          begin
            MsgLines := Tool.WorkerMessages;
            for J := 0 to MsgLines.Count - 1 do
            begin
              MsgLine := MsgLines[J];
              if MsgLine = nil then Continue;

              if MsgLine.Urgency in [mluHint, mluNote, mluWarning, mluError, mluFatal] then
              begin
                DiagItem := TFPCDiagnosticItem.Create;
                DiagItem.RawLine := MsgLine.OriginalLine;
                DiagItem.FileName := MsgLine.Filename;
                DiagItem.Line := MsgLine.Line;
                DiagItem.Column := MsgLine.Column;
                DiagItem.MsgCode := MsgLine.MsgID;
                DiagItem.MessageText := MsgLine.Msg;

                case MsgLine.Urgency of
                  mluHint:    DiagItem.Severity := msHint;
                  mluNote:    DiagItem.Severity := msNote;
                  mluWarning: DiagItem.Severity := msWarning;
                  mluError:   DiagItem.Severity := msError;
                  mluFatal:   DiagItem.Severity := msFatal;
                else
                  DiagItem.Severity := msHint;
                end;

                if Trim(DiagItem.FileName) = '' then
                  DiagItem.UnitName := 'Projeto / Opções Globais';

                DiagItem.EnrichFromDB;
                FMasterList.Add(DiagItem);
              end;
            end;
          end;

          if (FMasterList.Count = 0) and (Tool.WorkerOutput <> nil) and (Tool.WorkerOutput.Count > 0) then
          begin
            TFPCMessageParser.ParseText(Tool.WorkerOutput.Text, FMasterList);
            for K := 0 to FMasterList.Count - 1 do
              FMasterList[K].EnrichFromDB;
          end;
        finally
          Tool.LeaveCriticalSection;
        end;
      end;
    finally
      ExternalToolList.LeaveCriticalSection;
    end;
  end;

  UpdateMetrics;
  ApplyFilters;
end;

procedure THintsWarningsViewForm.OnFilterChanged(Sender: TObject);
begin
  ApplyFilters;
end;

procedure THintsWarningsViewForm.btnReloadClick(Sender: TObject);
begin
  LoadFromIDE;
end;

procedure THintsWarningsViewForm.btnClearClick(Sender: TObject);
begin
  FMasterList.Clear;
  UpdateMetrics;
  ApplyFilters;
end;

procedure THintsWarningsViewForm.btnBuildNowClick(Sender: TObject);
begin
  if LazarusIDE <> nil then
  begin
    LazarusIDE.DoBuildProject(crCompile, []);
    LoadFromIDE;
  end;
end;

procedure THintsWarningsViewForm.btnPasteLogClick(Sender: TObject);
var
  ClipStr: string;
  I: integer;
begin
  ClipStr := Clipboard.AsText;
  if Trim(ClipStr) = '' then
  begin
    ShowMessage('A área de transferência está vazia. Copie mensagens do compilador para colar.');
    Exit;
  end;

  FMasterList.Clear;
  TFPCMessageParser.ParseText(ClipStr, FMasterList);

  for I := 0 to FMasterList.Count - 1 do
    FMasterList[I].EnrichFromDB;

  UpdateMetrics;
  ApplyFilters;

  if FMasterList.Count > 0 then
    ShowMessage(Format('%d mensagem(ns) analisada(s) e consultadas no Firebird 5.0!', [FMasterList.Count]))
  else
    ShowMessage('Nenhuma linha no formato de mensagem do Free Pascal foi reconhecida no texto copiado.');
end;

procedure THintsWarningsViewForm.btnQuickFixClick(Sender: TObject);
var
  Item: TFPCDiagnosticItem;
  ResultMsg: string;
begin
  Item := GetSelectedDiagnostic;
  if Item = nil then Exit;

  // Se a aba de IA estiver ativa com resposta, prioriza a sugestão da IA!
  if (pgcInspector.ActivePage = tsOllama) and (Trim(memoAIResult.Lines.Text) <> '') then
  begin
    btnApplyAICodeClick(Sender);
    Exit;
  end;

  if TFPCQuickFixService.ExecuteQuickFix(Item, ResultMsg) then
  begin
    ShowMessage(ResultMsg + LineEnding + LineEnding +
                'Recompile o projeto (F9 ou Shift+F9) para validar a correção.');
    UpdateDetailsView(Item);
  end
  else
    ShowMessage('Falha ao aplicar correção: ' + ResultMsg);
end;

procedure THintsWarningsViewForm.btnApplyAICodeClick(Sender: TObject);
var
  Item: TFPCDiagnosticItem;
  ResultMsg, CleanCode: string;
begin
  Item := GetSelectedDiagnostic;
  if Item = nil then
  begin
    ShowMessage('Selecione um diagnóstico para aplicar a sugestão da IA.');
    Exit;
  end;

  if Trim(memoAIResult.Lines.Text) = '' then
  begin
    ShowMessage('Nenhuma sugestão da IA disponível. Clique em "Diagnóstico Ollama" ou "Diagnóstico Gemini" primeiro.');
    Exit;
  end;

  CleanCode := TFPCQuickFixService.ExtractCodeBlockFromAI(memoAIResult.Lines.Text);
  if CleanCode = '' then
  begin
    ShowMessage('Nenhum bloco de código Pascal identificado na resposta da IA.');
    Exit;
  end;

  if QuestionDlg('Aplicar Sugestão da IA no Código-Fonte',
       Format('Deseja aplicar a sugestão da IA na linha %d de %s?' + LineEnding + LineEnding +
              '--- CÓDIGO DA IA ---' + LineEnding + '%s' + LineEnding + LineEnding +
              '• A linha atual será comentada no editor.' + LineEnding +
              '• Você pode desfazer a qualquer momento com Ctrl+Z.',
              [Item.Line, Item.UnitName, CleanCode]),
       mtConfirmation, [mrYes, 'Sim, Aplicar no Editor', mrCancel, 'Cancelar'], 0) = mrYes then
  begin
    if TFPCQuickFixService.ApplyAICodeFix(Item, memoAIResult.Lines.Text, ResultMsg) then
      ShowMessage(ResultMsg)
    else
      ShowMessage('Falha ao aplicar código da IA: ' + ResultMsg);
  end;
end;

procedure THintsWarningsViewForm.btnCopyAICodeClick(Sender: TObject);
var
  CleanCode: string;
begin
  CleanCode := TFPCQuickFixService.ExtractCodeBlockFromAI(memoAIResult.Lines.Text);
  if CleanCode = '' then
    CleanCode := memoAIResult.Lines.Text;

  if Trim(CleanCode) <> '' then
  begin
    Clipboard.AsText := CleanCode;
    ShowMessage('Código sugerido pela IA copiado para a área de transferência!');
  end
  else
    ShowMessage('Nenhum código disponível para copiar.');
end;

procedure THintsWarningsViewForm.btnOllamaAIClick(Sender: TObject);
var
  Item: TFPCDiagnosticItem;
  ContextCode: string;
begin
  Item := GetSelectedDiagnostic;
  if Item = nil then
  begin
    ShowMessage('Selecione um diagnóstico para analisar com a Inteligência Artificial.');
    Exit;
  end;

  pgcInspector.ActivePage := tsOllama;
  memoAIResult.Lines.Text :=
    '⏳ [Ollama IA] Consultando modelo ' + HintsWarningsConfig.OllamaModel + ' em segundo plano...' + LineEnding +
    'Aguarde enquanto a IA analisa o erro e gera a solução completa...' + LineEnding;

  btnOllamaAI.Enabled := False;
  btnOllamaAI.Caption := 'Analisando...';
  ContextCode := GetCodeContext(Item.FileName, Item.Line);

  OllamaService.AnalyzeDiagnosticAsync(Item, ContextCode, @OnOllamaAnalysisFinished);
end;

procedure THintsWarningsViewForm.OnOllamaAnalysisFinished(const AResult: string;
  const AError: string);
begin
  btnOllamaAI.Caption := '🤖 Diagnóstico Ollama';
  btnOllamaAI.Enabled := True;

  if AError <> '' then
  begin
    memoAIResult.Lines.Text :=
      '❌ [Ollama IA] Falha ao obter resposta:' + LineEnding +
      AError + LineEnding + LineEnding +
      'Verifique se o Ollama está ativo: ollama run ' + HintsWarningsConfig.OllamaModel;
  end
  else
  begin
    memoAIResult.Lines.Text := AResult;
    btnQuickFix.Enabled := True;
    btnQuickFix.Caption := '⚡ Aplicar Sugestão da IA';
  end;
  memoAIResult.SelStart := 0;
end;

procedure THintsWarningsViewForm.btnGeminiAIClick(Sender: TObject);
var
  Item: TFPCDiagnosticItem;
  ContextCode: string;
begin
  Item := GetSelectedDiagnostic;
  if Item = nil then
  begin
    ShowMessage('Selecione um diagnóstico para analisar com o Google Gemini.');
    Exit;
  end;

  pgcInspector.ActivePage := tsOllama;
  memoAIResult.Lines.Text :=
    '⏳ [Google Gemini] Consultando modelo Gemini em segundo plano...' + LineEnding +
    'Aguarde enquanto o Gemini analisa o erro e gera a solução completa...' + LineEnding;

  btnGeminiAI.Enabled := False;
  btnGeminiAI.Caption := 'Analisando...';
  ContextCode := GetCodeContext(Item.FileName, Item.Line);

  GeminiService.AnalyzeDiagnosticAsync(Item, ContextCode, @OnGeminiAnalysisFinished);
end;

procedure THintsWarningsViewForm.OnGeminiAnalysisFinished(const AResult: string;
  const AError: string);
begin
  btnGeminiAI.Caption := '✨ Diagnóstico Gemini';
  btnGeminiAI.Enabled := True;

  if AError <> '' then
  begin
    memoAIResult.Lines.Text :=
      '❌ [Google Gemini] Falha ao obter resposta:' + LineEnding +
      AError + LineEnding + LineEnding +
      'Dica: Configure sua GEMINI_API_KEY no botão "Configurações..." ou exporte a variável no sistema.';
  end
  else
  begin
    memoAIResult.Lines.Text := AResult;
    btnQuickFix.Enabled := True;
    btnQuickFix.Caption := '⚡ Aplicar Sugestão da IA';
  end;
  memoAIResult.SelStart := 0;
end;

procedure THintsWarningsViewForm.btnCopyDetailsClick(Sender: TObject);
var
  Item: TFPCDiagnosticItem;
begin
  Item := GetSelectedDiagnostic;
  if Item <> nil then
  begin
    if (pgcInspector.ActivePage = tsOllama) and (Trim(memoAIResult.Lines.Text) <> '') then
    begin
      Clipboard.AsText := memoAIResult.Lines.Text;
      ShowMessage('Solução e código gerados pela Inteligência Artificial copiados para a área de transferência!');
    end
    else
    begin
      Clipboard.AsText := memoFullGuide.Lines.Text;
      ShowMessage('Relatório e orientações do catálogo copiados para a área de transferência!');
    end;
  end;
end;

procedure THintsWarningsViewForm.btnConfigDBClick(Sender: TObject);
var
  NewHost, NewPath, NewUser, NewPass, NewModel, NewURL, NewGeminiKey: string;
  Cfg: THintsWarningsConfig;
begin
  Cfg := HintsWarningsConfig;

  NewHost := InputBox('Configuração Firebird 5.0', 'Servidor / Host:', Cfg.HostName);
  if Trim(NewHost) = '' then Exit;

  NewPath := InputBox('Configuração Firebird 5.0', 'Caminho completo do banco (.fdb):', Cfg.DatabasePath);
  if Trim(NewPath) = '' then Exit;

  NewUser := InputBox('Configuração Firebird 5.0', 'Usuário:', Cfg.UserName);
  NewPass := InputBox('Configuração Firebird 5.0', 'Senha:', Cfg.Password);

  NewURL := InputBox('Configuração Ollama IA', 'URL do servidor Ollama:', Cfg.OllamaURL);
  NewModel := InputBox('Configuração Ollama IA', 'Modelo de IA (ex: qwen2.5-coder:3b, starcoder2:3b):', Cfg.OllamaModel);

  NewGeminiKey := InputBox('Configuração Google Gemini', 'Chave da API Gemini (GEMINI_API_KEY):', Cfg.GeminiAPIKey);

  Cfg.HostName := Trim(NewHost);
  Cfg.DatabasePath := Trim(NewPath);
  Cfg.UserName := Trim(NewUser);
  Cfg.Password := Trim(NewPass);
  if Trim(NewURL) <> '' then Cfg.OllamaURL := Trim(NewURL);
  if Trim(NewModel) <> '' then Cfg.OllamaModel := Trim(NewModel);
  Cfg.GeminiAPIKey := Trim(NewGeminiKey);
  Cfg.Save;

  // Reconexao Firebird
  FPCDatabase.ResetConnection;
  FPCDatabase.ClearCache;
  if FPCDatabase.Connect then
    ShowMessage('Configurações salvas e conexão com Firebird 5.0 restabelecida!')
  else
    ShowMessage('Configurações salvas. Não foi possível conectar ao Firebird: ' + FPCDatabase.LastError);

  UpdateDBStatusBadge;
end;

procedure THintsWarningsViewForm.btnReconnectDBClick(Sender: TObject);
begin
  FPCDatabase.ResetConnection;
  FPCDatabase.ClearCache;
  if FPCDatabase.Connect then
    ShowMessage('Conectado ao Firebird 5.0 com sucesso!')
  else
    ShowMessage('Falha na conexão com Firebird 5.0:' + LineEnding + FPCDatabase.LastError);
  UpdateDBStatusBadge;
end;

procedure THintsWarningsViewForm.btnExportClick(Sender: TObject);
var
  Pt: TPoint;
begin
  Pt := btnExport.ClientToScreen(Point(0, btnExport.Height));
  popExport.PopUp(Pt.X, Pt.Y);
end;

procedure THintsWarningsViewForm.miExportCSVClick(Sender: TObject);
var
  OutList: TStringList;
begin
  saveDialogExport.DefaultExt := '.csv';
  saveDialogExport.FilterIndex := 1;
  saveDialogExport.FileName := 'diagnosticos_fpc.csv';
  if saveDialogExport.Execute then
  begin
    OutList := TStringList.Create;
    try
      OutList.Text := FFilteredList.ExportToCSV;
      OutList.SaveToFile(saveDialogExport.FileName);
      ShowMessage('Relatório CSV exportado com sucesso!' + LineEnding + saveDialogExport.FileName);
    finally
      OutList.Free;
    end;
  end;
end;

procedure THintsWarningsViewForm.miExportJSONClick(Sender: TObject);
var
  OutList: TStringList;
begin
  saveDialogExport.DefaultExt := '.json';
  saveDialogExport.FilterIndex := 2;
  saveDialogExport.FileName := 'diagnosticos_fpc.json';
  if saveDialogExport.Execute then
  begin
    OutList := TStringList.Create;
    try
      OutList.Text := FFilteredList.ExportToJSON;
      OutList.SaveToFile(saveDialogExport.FileName);
      ShowMessage('Relatório JSON exportado com sucesso!' + LineEnding + saveDialogExport.FileName);
    finally
      OutList.Free;
    end;
  end;
end;

procedure THintsWarningsViewForm.tvDiagnosticsDblClick(Sender: TObject);
var
  Item: TFPCDiagnosticItem;
begin
  Item := GetSelectedDiagnostic;
  if Item <> nil then
    NavigateToItem(Item);
end;

procedure THintsWarningsViewForm.tvDiagnosticsSelectionChanged(Sender: TObject);
var
  Item: TFPCDiagnosticItem;
begin
  Item := GetSelectedDiagnostic;
  UpdateDetailsView(Item);
end;

procedure THintsWarningsViewForm.btnGoToCodeClick(Sender: TObject);
var
  Item: TFPCDiagnosticItem;
begin
  Item := GetSelectedDiagnostic;
  if Item <> nil then
    NavigateToItem(Item);
end;

end.
