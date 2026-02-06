unit Unit1;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, Menus,
  Process, StrUtils, Grids;

type
  { TForm1 }
  TForm1 = class(TForm)
    btnBrowse: TButton;
    btnRun: TButton;
    Button1: TButton; // Save/Merge EEPROM button
    chkProg: TCheckBox;
    chkVerify: TCheckBox;
    chkSkipEE: TCheckBox;
    chkHVP: TCheckBox;
    cmbPort: TComboBox;
    cmbMCU: TComboBox;
    edtFile: TEdit;
    Label1: TLabel;
    Label2: TLabel;
    MainMenu1: TMainMenu;
    memLog: TMemo;
    sgEEPROM: TStringGrid;
    MenuItem1: TMenuItem;
    MenuItem2: TMenuItem;
    MenuItem3: TMenuItem;
    MenuItem4: TMenuItem;
    MenuItem5: TMenuItem;
    MenuItem6: TMenuItem;
    OpenDialog1: TOpenDialog;
    procedure Button1Click(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure btnBrowseClick(Sender: TObject);
    procedure btnRunClick(Sender: TObject);
    procedure MenuItem1Click(Sender: TObject);
    procedure MenuItem3Click(Sender: TObject);
    procedure MenuItem4Click(Sender: TObject);
    procedure MenuItem5Click(Sender: TObject);
    procedure MenuItem6Click(Sender: TObject);
  private
    procedure RefreshPorts;
    procedure LoadDevices;
    procedure InitEEGrid;
    procedure LoadHexToGrid(AFileName: string);
  public
  end;

var
  Form1: TForm1;

implementation

{$R *.lfm}

{ TForm1 }

procedure TForm1.LoadHexToGrid(AFileName: string);
var
  HexLines: TStringList;
  i, r, c: Integer;
  Line, DataPart, AddrStr: string;
  TargetAddr: Integer;
begin
  if not FileExists(AFileName) then Exit;
  HexLines := TStringList.Create;
  try
    HexLines.LoadFromFile(AFileName);
    for i := 0 to HexLines.Count - 1 do begin
      Line := Trim(HexLines[i]);
      if (Line = '') or (Line[1] <> ':') then Continue;
      AddrStr := Copy(Line, 4, 4);
      TargetAddr := StrToIntDef('$' + AddrStr, -1);
      if (TargetAddr >= $E000) and (TargetAddr <= $E0F0) then begin
        r := ((TargetAddr - $E000) div 16) + 1;
        DataPart := Copy(Line, 10, 32);
        for c := 1 to 16 do
          sgEEPROM.Cells[c, r] := Copy(DataPart, (c-1)*2 + 1, 2);
      end;
    end;
  finally
    HexLines.Free;
  end;
end;

procedure TForm1.InitEEGrid;
var i, j: Integer;
begin
  sgEEPROM.ColCount := 17;
  sgEEPROM.RowCount := 17;
  sgEEPROM.DefaultColWidth := 30;
  sgEEPROM.Cells[0, 0] := 'Addr';
  for i := 0 to 15 do begin
    sgEEPROM.Cells[i + 1, 0] := IntToHex(i, 1);
    sgEEPROM.Cells[0, i + 1] := IntToHex(i * 16, 2);
    for j := 1 to 16 do sgEEPROM.Cells[j, i + 1] := 'FF';
  end;
end;

procedure TForm1.FormCreate(Sender: TObject);
begin
  RefreshPorts;
  LoadDevices;
  InitEEGrid;
  edtFile.TextHint := 'Select .hex file...';
end;

procedure TForm1.Button1Click(Sender: TObject);
var
  FullHex: TStringList;
  SaveDlg: TSaveDialog;
  i, r, c, Sum: Integer;
  Addr: Word;
  Line: string;
  FoundEE: Boolean;
begin
  if not FileExists(edtFile.Text) then begin
    ShowMessage('Please load an original HEX file first.');
    Exit;
  end;
  SaveDlg := TSaveDialog.Create(nil);
  try
    SaveDlg.Filter := 'HEX files (*.hex)|*.hex';
    SaveDlg.FileName := 'edited_' + ExtractFileName(edtFile.Text);
    if SaveDlg.Execute then begin
      FullHex := TStringList.Create;
      try
        FullHex.LoadFromFile(edtFile.Text);
        for r := 1 to 16 do begin
          Addr := (r - 1) * 16 + $E000;
          FoundEE := False;
          Line := '10' + IntToHex(Addr, 4) + '00';
          Sum := $10 + (Addr shr 8) + (Addr and $FF);
          for c := 1 to 16 do begin
            Sum := Sum + StrToIntDef('$' + sgEEPROM.Cells[c, r], $FF);
            Line := Line + IntToHex(StrToIntDef('$' + sgEEPROM.Cells[c, r], $FF), 2);
          end;
          Sum := (not (Sum and $FF) + 1) and $FF;
          Line := ':' + Line + IntToHex(Sum, 2);
          for i := 0 to FullHex.Count - 1 do begin
            if Copy(FullHex[i], 2, 8) = '10' + IntToHex(Addr, 4) + '00' then begin
              FullHex[i] := Line;
              FoundEE := True;
              Break;
            end;
          end;
          if not FoundEE then begin
            for i := 0 to FullHex.Count - 1 do begin
              if FullHex[i] = ':00000001FF' then begin
                FullHex.Insert(i, Line);
                Break;
              end;
            end;
          end;
        end;
        FullHex.SaveToFile(SaveDlg.FileName);
        edtFile.Text := SaveDlg.FileName;
        ShowMessage('File saved: ' + SaveDlg.FileName);
      finally
        FullHex.Free;
      end;
    end;
  finally
    SaveDlg.Free;
  end;
end;

procedure TForm1.RefreshPorts;
var SR: TSearchRec;
begin
  cmbPort.Items.Clear;
  if FindFirst('/dev/ttyUSB*', faAnyFile, SR) = 0 then
    repeat cmbPort.Items.Add('/dev/' + SR.Name); until FindNext(SR) <> 0;
  if FindFirst('/dev/ttyACM*', faAnyFile, SR) = 0 then
    repeat cmbPort.Items.Add('/dev/' + SR.Name); until FindNext(SR) <> 0;
  FindClose(SR);
  if cmbPort.Items.Count = 0 then cmbPort.Items.CommaText := 'COM1,COM2,COM3,COM4';
  cmbPort.ItemIndex := 0;
end;

procedure TForm1.LoadDevices;
begin
  cmbMCU.Items.Clear;
  cmbMCU.Items.CommaText := '16f1938,16lf1938,12f1840';
  cmbMCU.ItemIndex := 0;
end;

procedure TForm1.btnBrowseClick(Sender: TObject);
begin
  if OpenDialog1.Execute then begin
    edtFile.Text := OpenDialog1.FileName;
    LoadHexToGrid(edtFile.Text);
  end;
end;

procedure TForm1.btnRunClick(Sender: TObject);
var
  AProcess: TProcess;
  Buf: string;
  n: LongInt;
  FullCmd: string;
  i: Integer;
begin
  if (edtFile.Text = '') or (not FileExists(edtFile.Text)) then begin
    ShowMessage('Please select a valid .hex file.'); Exit;
  end;

  btnRun.Enabled := False;
  memLog.Clear;
  AProcess := TProcess.Create(nil);
  try
    // Logic for Linux vs Windows binary
    {$IFDEF WINDOWS}
    AProcess.Executable := 'pp3r.exe';
    {$ELSE}
    AProcess.Executable := './pp3r';
    {$ENDIF}

    if not FileExists(AProcess.Executable) then begin
       memLog.Lines.Add('Binary not found: ' + AProcess.Executable);
       Exit;
    end;

    AProcess.Parameters.Add('-c'); AProcess.Parameters.Add(cmbPort.Text);
    AProcess.Parameters.Add('-t'); AProcess.Parameters.Add(cmbMCU.Text);

    // Parameters must be added separately
    AProcess.Parameters.Add('-s'); AProcess.Parameters.Add('2000');
    AProcess.Parameters.Add('-v2');

    if not chkProg.Checked then AProcess.Parameters.Add('-p');
    if not chkVerify.Checked then AProcess.Parameters.Add('-n');
    if chkSkipEE.Checked then AProcess.Parameters.Add('-e');
    if chkHVP.Checked then AProcess.Parameters.Add('-h');
    AProcess.Parameters.Add(edtFile.Text);

    AProcess.Options := [poUsePipes, poStderrToOutPut, poNoConsole];

    FullCmd := AProcess.Executable;
    for i := 0 to AProcess.Parameters.Count - 1 do
      FullCmd := FullCmd + ' ' + AProcess.Parameters[i];

    memLog.Lines.Add('Executing: ' + FullCmd);
    memLog.Lines.Add('---------------------------------------');

    try
      AProcess.Execute;
    except
      on E: Exception do begin
        memLog.Lines.Add('Error starting process: ' + E.Message);
        Exit;
      end;
    end;

    SetLength(Buf, 1024);
    while AProcess.Running do begin
      if AProcess.Output.NumBytesAvailable > 0 then begin
        n := AProcess.Output.Read(Buf[1], Length(Buf));
        memLog.SelStart := Length(memLog.Text);
        memLog.SelText := Copy(Buf, 1, n);
      end;
      Application.ProcessMessages;
      Sleep(10);
    end;

    // Final read to ensure nothing is left in the pipe
    Sleep(100);
    while AProcess.Output.NumBytesAvailable > 0 do begin
        n := AProcess.Output.Read(Buf[1], Length(Buf));
        memLog.SelText := Copy(Buf, 1, n);
    end;

    memLog.Lines.Add('');
    memLog.Lines.Add('--- Process Finished ---');
  finally
    AProcess.Free;
    btnRun.Enabled := True;
  end;
end;

procedure TForm1.MenuItem1Click(Sender: TObject); begin end;
procedure TForm1.MenuItem3Click(Sender: TObject); begin end;
procedure TForm1.MenuItem4Click(Sender: TObject); begin Close; end;

procedure TForm1.MenuItem5Click(Sender: TObject);
begin
  if memLog.Visible then begin
    memLog.Visible := False;
    sgEEPROM.Visible := True;
    Button1.Visible := True;
    MenuItem5.Caption := 'Show Log';
  end else begin
    memLog.Visible := True;
    sgEEPROM.Visible := False;
    Button1.Visible := False;
    MenuItem5.Caption := 'Edit EEPROM';
  end;
end;

procedure TForm1.MenuItem6Click(Sender: TObject);
begin
  ShowMessage('pp3r GUI -by LB7UG' + sLineBreak + 'Supports ATU-100 & PIC16F1938');
end;

end.
