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
    Button1: TButton; // This is your Save EEPROM button
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
    procedure LoadHexToGrid(AFileName: string); // Added this declaration
  public
  end;

var
  Form1: TForm1;

implementation

{$R *.lfm}

{ TForm1 }

// --- HEX PARSER: Reads EEPROM from file into Grid ---
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

      // PIC16F1938 EEPROM mapping offset is usually $E000
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
  InitEEGrid; // Initialize the grid on startup
  edtFile.TextHint := 'Select .hex file...';
end;

// --- SAVE GRID TO EEPROM ---
procedure TForm1.Button1Click(Sender: TObject);
var
  FullHex: TStringList;
  SaveDlg: TSaveDialog;
  i, r, c, Sum: Integer;
  Addr: Word;
  Line, DataPart: string;
  FoundEE: Boolean;
begin
  if not FileExists(edtFile.Text) then
  begin
    ShowMessage('Please load an original HEX file first.');
    Exit;
  end;

  SaveDlg := TSaveDialog.Create(nil);
  SaveDlg.Filter := 'HEX files (*.hex)|*.hex';
  SaveDlg.FileName := 'edited_' + ExtractFileName(edtFile.Text);

  if SaveDlg.Execute then
  begin
    FullHex := TStringList.Create;
    try
      FullHex.LoadFromFile(edtFile.Text);

      // We will loop through 16 rows of EEPROM data from our grid
      for r := 1 to 16 do
      begin
        Addr := (r - 1) * 16 + $E000;
        FoundEE := False;

        // Build the new HEX line for this row
        Line := '10' + IntToHex(Addr, 4) + '00';
        Sum := $10 + (Addr shr 8) + (Addr and $FF);
        for c := 1 to 16 do
        begin
          Sum := Sum + StrToIntDef('$' + sgEEPROM.Cells[c, r], $FF);
          Line := Line + IntToHex(StrToIntDef('$' + sgEEPROM.Cells[c, r], $FF), 2);
        end;
        Sum := (not (Sum and $FF) + 1) and $FF;
        Line := ':' + Line + IntToHex(Sum, 2);

        // Search for existing line in the file and replace it
        for i := 0 to FullHex.Count - 1 do
        begin
          if Copy(FullHex[i], 2, 8) = '10' + IntToHex(Addr, 4) + '00' then
          begin
            FullHex[i] := Line;
            FoundEE := True;
            Break;
          end;
        end;

        // If this EEPROM address wasn't in the original file, insert it
        // before the End-of-File marker (:00000001FF)
        if not FoundEE then
        begin
          for i := 0 to FullHex.Count - 1 do
          begin
            if FullHex[i] = ':00000001FF' then
            begin
              FullHex.Insert(i, Line);
              Break;
            end;
          end;
        end;
      end;

      FullHex.SaveToFile(SaveDlg.FileName);
      ShowMessage('File saved as: ' + SaveDlg.FileName);

      // Update the main edit box so we are now working on the new file
      edtFile.Text := SaveDlg.FileName;

    finally
      FullHex.Free;
    end;
  end;
  SaveDlg.Free;
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
var
  List: TStringList;
  i: Integer;
  Line, DeviceName: string;
begin
  cmbMCU.Items.Clear;
  if FileExists('pp3_devices.dat') then begin
    List := TStringList.Create;
    try
      List.LoadFromFile('pp3_devices.dat');
      for i := 0 to List.Count - 1 do begin
        Line := Trim(List[i]);
        if (Line = '') or (Line[1] = '#') or (Line[1] = '/') then Continue;
        DeviceName := ExtractWord(1, Line, [' ', #9]);
        cmbMCU.Items.Add(DeviceName);
      end;
    finally
      List.Free;
    end;
  end;
  if cmbMCU.Items.Count = 0 then cmbMCU.Items.CommaText := '16f1938,16lf1938,12f1840';
  cmbMCU.ItemIndex := 0;
end;

procedure TForm1.btnBrowseClick(Sender: TObject);
begin
  if OpenDialog1.Execute then begin
    edtFile.Text := OpenDialog1.FileName;
    LoadHexToGrid(edtFile.Text); // Update grid when file is selected
  end;
end;

// ACTUAL PROGRAMMING

procedure TForm1.btnRunClick(Sender: TObject);
var
  AProcess: TProcess;
  Buf: string;
  n: LongInt;
  FullCmd: string;
  i: Integer;
begin
  if (edtFile.Text = '') or (not FileExists(edtFile.Text)) then begin
    ShowMessage('Please select a valid .hex file.');
    Exit;
  end;
  btnRun.Enabled := False;
  memLog.Clear;
  AProcess := TProcess.Create(nil);
  try
    AProcess.Executable := 'pp3r.exe';
    AProcess.Parameters.Add('-c'); AProcess.Parameters.Add(cmbPort.Text);
    AProcess.Parameters.Add('-t'); AProcess.Parameters.Add(cmbMCU.Text);
    AProcess.Parameters.Add('-s 2000 -v2');
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
      memLog.Lines.Add('--- Process Finished ---');
      AProcess.Execute;
    except
      memLog.Lines.Add('Error: Could not start pp3r.');
      Exit;
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
