{ This file was automatically created by Lazarus. Do not edit!
  This source is only used to compile and install the package.
 }

unit LazarusHintsWarnings;

{$warn 5023 off : no warning about unused units}
interface

uses
  UHintsWarnings.Config, UHintsWarnings.Database, UHintsWarnings.Model, 
  UHintsWarnings.Ollama, UHintsWarnings.Gemini, UHintsWarnings.QuickFix,
  UHintsWarnings.View, UHintsWarnings.Register, LazarusPackageIntf;

implementation

procedure Register;
begin
  RegisterUnit('UHintsWarnings.Register', @UHintsWarnings.Register.Register);
end;

initialization
  RegisterPackage('LazarusHintsWarnings', @Register);
end.
