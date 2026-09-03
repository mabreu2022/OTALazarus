unit UHintsWarnings.Register;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  LazIDEIntf, MenuIntf, IDEWindowIntf, ProjectIntf,
  UHintsWarnings.Model, UHintsWarnings.View;

type
  { THintsWarningsIDEListener: Monitor passivo do ciclo de compilação da IDE }
  THintsWarningsIDEListener = class
  public
    function OnProjectOpened({%H-}Sender: TObject; {%H-}AProject: TLazProject): TModalResult;
    procedure OnProjectBuildingFinished({%H-}Sender: TObject; {%H-}BuildSuccessful: Boolean);
    procedure OnShowHintsWarningsView({%H-}Sender: TObject);
  end;

procedure Register;

implementation

var
  GListener: THintsWarningsIDEListener = nil;

{ Criação da janela pelo gerenciador de janelas e docking da IDE }
procedure CreateHintsWarningsView({%H-}Sender: TObject; aFormName: string;
  var AForm: TCustomForm; DoDisableAutoSizing: boolean);
begin
  if CompareText(aFormName, 'HintsWarningsViewForm') = 0 then
  begin
    IDEWindowCreators.CreateForm(AForm, THintsWarningsViewForm, DoDisableAutoSizing, Application);
  end;
end;

{ THintsWarningsIDEListener }

procedure THintsWarningsIDEListener.OnShowHintsWarningsView(Sender: TObject);
var
  Frm: TCustomForm;
begin
  Frm := IDEWindowCreators.ShowForm('HintsWarningsViewForm', True);
  if (Frm is THintsWarningsViewForm) then
    THintsWarningsViewForm(Frm).LoadFromIDE;
end;

function THintsWarningsIDEListener.OnProjectOpened(Sender: TObject; AProject: TLazProject): TModalResult;
var
  Frm: TCustomForm;
begin
  Result := mrOk;
  // Se a janela já estiver aberta ou criada, atualiza informações do projeto
  Frm := IDEWindowCreators.GetForm('HintsWarningsViewForm', False);
  if (Frm is THintsWarningsViewForm) then
  begin
    THintsWarningsViewForm(Frm).UpdateProjectInfo;
    THintsWarningsViewForm(Frm).LoadFromIDE;
  end;
end;

procedure THintsWarningsIDEListener.OnProjectBuildingFinished(Sender: TObject; BuildSuccessful: Boolean);
var
  Frm: TCustomForm;
  ViewForm: THintsWarningsViewForm;
begin
  // Obtém ou instancia a janela de visualização via IDEWindowCreators
  Frm := IDEWindowCreators.GetForm('HintsWarningsViewForm', True);
  if (Frm is THintsWarningsViewForm) then
  begin
    ViewForm := THintsWarningsViewForm(Frm);
    ViewForm.LoadFromIDE;

    // Se houver qualquer alerta (Warnings, Hints, Notes ou Erros), foca/exibe a janela
    if ViewForm.MasterList.Count > 0 then
      IDEWindowCreators.ShowForm(ViewForm, True);
  end;
end;

procedure Register;
begin
  // 1. Instancia o listener global do pacote
  if GListener = nil then
    GListener := THintsWarningsIDEListener.Create;

  // 2. Registro da janela de métricas no gerenciador dockable do Lazarus
  IDEWindowCreators.Add('HintsWarningsViewForm', @CreateHintsWarningsView, nil,
    '100', '100', '+920', '+580', '', alNone);

  // 3. Inclusão de entrada direta no menu Ferramentas (Tools) da IDE
  RegisterIDEMenuCommand(itmSecondaryTools, 'mnuAnalisadorHintsWarnings',
    'Analisador de Hints & Warnings', @GListener.OnShowHintsWarningsView);

  // 4. Injeção do listener nos eventos da IDE: Abertura de projeto e Fim de compilação
  LazarusIDE.AddHandlerOnProjectOpened(@GListener.OnProjectOpened);
  LazarusIDE.AddHandlerOnProjectBuildingFinished(@GListener.OnProjectBuildingFinished);
end;

initialization

finalization
  if (LazarusIDE <> nil) and (GListener <> nil) then
  begin
    LazarusIDE.RemoveHandlerOnProjectBuildingFinished(@GListener.OnProjectBuildingFinished);
    LazarusIDE.RemoveHandlerOnProjectOpened(@GListener.OnProjectOpened);
  end;
  FreeAndNil(GListener);

end.
