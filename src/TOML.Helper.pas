{ TOML.Helper.pas
TOML auxiliary extension units, through class helpers,
provide TTOMLLTable and TTOMLArray with...
Provides a simpler and more secure read/write API.
Main functions:
- TTOMLTableHelper: Reading (GetXxx / TryGetXxx) and writing (SetXxx) tables.
  Chained calls (Put), file operations (LoadFromFile / SaveToFile),
  Key management (HasKey / GetKeys / Remove / Clear / Clone / Count),
  File and String Operations (ToString / SaveToFile / LoadFromFile /
                              CreateFromFile / CreateFromString),
  About JSON (ToJSON / SaveToJSONFile / LoadFromJson / LoadFromJsonFile)
- TTOMLArrayHelper: Reads array elements (GetXxx / TryGetXxx) and
  appends/insert/writing them (AddXxx / InsertXxx / SetXxx).
Traversal (ForEachTable), removal (RemoveAt / Clear), etc.
Global factory function:
- NewTable / NewArray: Create an empty object
- LoadTOML: Loads from a file; returns nil on error.
- ParseTOML: Parses a string, returns nil on error.
- TryParseTOML: Parses a string and returns a Boolean result.
Path navigation (internal helper function):
- SplitPath: Splits paths enclosed in quotes and periods
  (supports "a".bc".d format)
- NavigateToTable: Navigate to the target table along the path.
- GetValueFromPath: Retrieves the value along the path.
- SetValueAtPath: Writes a value along the path
  (intermediate levels that do not exist will be created automatically).
}

unit TOML.Helper;

interface

uses
  SysUtils, Classes, Generics.Collections, TOML.Types, TOML.Parser, TOML.Serializer, TOML.JSON;

type
  { =========================================================================
    TTOMLTableHelper
    ========================================================================= }
  TTOMLTableHelper = class helper for TTOMLTable
  public
    { ----- Read ----- }
    function GetStr(const Key: string; const DefaultValue: string = ''): string;
    function TryGetStr(const Key: string; out Value: string): Boolean;

    function GetInt(const Key: string; const DefaultValue: Int64 = 0): Int64;
    function TryGetInt(const Key: string; out Value: Integer): Boolean;

    function GetFloat(const Key: string; const DefaultValue: Double = 0.0): Double;
    function TryGetFloat(const Key: string; out Value: Double): Boolean;

    { Raw float text (preserves exact TOML representation) }
    function GetFloatValue(const Key: string; const DefaultValue: string = ''): string;
    function TryGetFloatValue(const Key: string; out Value: string): Boolean;

    function GetBool(const Key: string; const DefaultValue: Boolean = False): Boolean;
    function TryGetBool(const Key: string; out Value: Boolean): Boolean;

    function GetDateTime(const Key: string; const DefaultValue: TDateTime = 0): TDateTime;
    function TryGetDateTime(const Key: string; out Value: TDateTime): Boolean;

    { Raw datetime text }
    function GetDateTimeValue(const Key: string; const DefaultValue: string = ''): string;
    function TryGetDateTimeValue(const Key: string; out Value: string): Boolean;

    function GetArray(const Key: string): TTOMLArray;
    function TryGetArray(const Key: string; out Value: TTOMLArray): Boolean;

    function GetTable(const Key: string): TTOMLTable;
    function TryGetTable(const Key: string; out Value: TTOMLTable): Boolean;

    function HasKey(const Key: string): Boolean;

    { Enumerate keys (insertion order). }
    procedure GetKeys(Keys: TStrings; Recursive: Boolean = False);

    { ----- Write ----- }
    function SetStr(const Key: string; const Value: string; Overwrite: Boolean = True): Boolean;
    function SetInt(const Key: string; const Value: Int64; Overwrite: Boolean = True): Boolean;
    function SetFloat(const Key: string; const Value: Double; Overwrite: Boolean = True): Boolean;
    function SetFloatValue(const Key: string; const RawValue: string; Overwrite: Boolean = True): Boolean;
    function SetBool(const Key: string; const Value: Boolean; Overwrite: Boolean = True): Boolean;
    function SetDateTime(const Key: string; const Value: TDateTime; Overwrite: Boolean = True): Boolean;
    function SetDateTimeValue(const Key: string; const RawValue: string; Overwrite: Boolean = True): Boolean;
    function SetArray(const Key: string; Value: TTOMLArray; Overwrite: Boolean = True): Boolean;
    function SetTable(const Key: string; Value: TTOMLTable; Overwrite: Boolean = True): Boolean;

    { ----- Builder (chain) ----- }
    function Put(const Key: string; const Value: string; Overwrite: Boolean = True): TTOMLTable; overload;
    function Put(const Key: string; const Value: Int64; Overwrite: Boolean = True): TTOMLTable; overload;
    function Put(const Key: string; const Value: Integer; Overwrite: Boolean = True): TTOMLTable; overload;
    function Put(const Key: string; const Value: Double; Overwrite: Boolean = True): TTOMLTable; overload;
    function Put(const Key: string; const Value: Boolean; Overwrite: Boolean = True): TTOMLTable; overload;
    function Put(const Key: string; const Value: TDateTime; Overwrite: Boolean = True): TTOMLTable; overload;
    function Put(const Key: string; Value: TTOMLArray; Overwrite: Boolean = True): TTOMLTable; overload;
    function Put(const Key: string; Value: TTOMLTable; Overwrite: Boolean = True): TTOMLTable; overload;

    { ----- File / string I/O ----- }
    class function CreateFromFile(const FileName: string; APreserveComments: Boolean = False): TTOMLTable;
    function LoadFromFile(const FileName: string; ClearExisting: Boolean = True; APreserveComments: Boolean =
      False): Boolean;
    class function CreateFromString(const ATOML: string; APreserveComments: Boolean = False): TTOMLTable;
    function LoadFromString(const ATOML: string; ClearExisting: Boolean = True; APreserveComments: Boolean =
      False): Boolean;
    function SaveToFile(const FileName: string; WriteBOM: Boolean = True; AWrapWidth: Integer = 0;
      APreserveComments: Boolean = False): Boolean;

    { ----- Serialization ----- }
    function toString(AWrapWidth: Integer = 0; APreserveComments: Boolean = False): string; reintroduce;

    { ----- Tools ----- }
    function Remove(const Key: string; FreeValue: Boolean = True): Boolean;
    procedure Clear(FreeValues: Boolean = True);
    function Count: Integer;
    function Clone: TTOMLTable;

    { ----- JSON ----- }
    function ToJSON(APretty: Boolean = True; AIndentSize: Integer = 2): string;
    function LoadFromJSON(const AJSON: string; ANullAsEmptyString: Boolean = False): Boolean;
    function SaveToJSONFile(const FileName: string; APretty: Boolean = True; ABOM: Boolean = False): Boolean;
    function LoadFromJSONFile(const FileName: string; ANullAsEmptyString: Boolean = False): Boolean;
  end;
  { =========================================================================
    TTOMLArrayHelper
    ========================================================================= }

  TTOMLArrayHelper = class helper for TTOMLArray
  public
    { ----- Read ----- }
    function GetStr(Index: Integer; const DefaultValue: string = ''): string;
    function TryGetStr(Index: Integer; out Value: string): Boolean;
    function GetInt(Index: Integer; const DefaultValue: Int64 = 0): Int64;
    function TryGetInt(Index: Integer; out Value: Integer): Boolean;
    function GetFloat(Index: Integer; const DefaultValue: Double = 0.0): Double;
    function TryGetFloat(Index: Integer; out Value: Double): Boolean;
    function GetFloatValue(Index: Integer; const DefaultValue: string = ''): string;
    function TryGetFloatValue(Index: Integer; out Value: string): Boolean;
    function GetBool(Index: Integer; const DefaultValue: Boolean = False): Boolean;
    function TryGetBool(Index: Integer; out Value: Boolean): Boolean;
    function GetDateTime(Index: Integer; const DefaultValue: TDateTime = 0): TDateTime;
    function TryGetDateTime(Index: Integer; out Value: TDateTime): Boolean;
    function GetDateTimeValue(Index: Integer; const DefaultValue: string = ''): string;
    function TryGetDateTimeValue(Index: Integer; out Value: string): Boolean;
    function GetTable(Index: Integer): TTOMLTable;
    function TryGetTable(Index: Integer; out Value: TTOMLTable): Boolean;
    function TryGetItem(Index: Integer; out Value: TTOMLValue): Boolean;
    function GetArray(Index: Integer): TTOMLArray;
    function TryGetArray(Index: Integer; out Value: TTOMLArray): Boolean;

    { ----- Add (chain, nil on error) ----- }
    function AddStr(const Value: string): TTOMLArray;
    function AddInt(const Value: Int64): TTOMLArray;
    function AddFloat(const Value: Double): TTOMLArray;
    function AddFloatValue(const RawValue: string): TTOMLArray;
    function AddBool(const Value: Boolean): TTOMLArray;
    function AddDateTime(const Value: TDateTime): TTOMLArray;
    function AddDateTimeValue(const RawValue: string): TTOMLArray;
    function AddTable(Value: TTOMLTable): TTOMLArray;
    function AddArray(Value: TTOMLArray): TTOMLArray;

    { ----- Set ----- }
    function SetStr(Index: Integer; const Value: string): Boolean;
    function SetInt(Index: Integer; const Value: Int64): Boolean;
    function SetFloat(Index: Integer; const Value: Double): Boolean;
    function SetFloatValue(Index: Integer; const RawValue: string): Boolean;
    function SetBool(Index: Integer; const Value: Boolean): Boolean;
    function SetDateTime(Index: Integer; const Value: TDateTime): Boolean;
    function SetDateTimeValue(Index: Integer; const RawValue: string): Boolean;
    function SetArray(Index: Integer; Value: TTOMLArray): Boolean;
    function SetTable(Index: Integer; Value: TTOMLTable): Boolean;

    { ----- Insert ----- }
    function InsertStr(Index: Integer; const Value: string): Boolean;
    function InsertInt(Index: Integer; const Value: Int64): Boolean;
    function InsertFloat(Index: Integer; const Value: Double): Boolean;
    function InsertFloatValue(Index: Integer; const RawValue: string): Boolean;
    function InsertBool(Index: Integer; const Value: Boolean): Boolean;
    function InsertDateTime(Index: Integer; const Value: TDateTime): Boolean;
    function InsertDateTimeValue(Index: Integer; const RawValue: string): Boolean;
    function InsertArray(Index: Integer; Value: TTOMLArray): Boolean;
    function InsertTable(Index: Integer; Value: TTOMLTable): Boolean;

    { ----- Serialization ----- }
    function toString: string; reintroduce;

    { ----- Tools ----- }
    procedure Clear(FreeItems: Boolean = True);
    function RemoveAt(Index: Integer; FreeItem: Boolean = True): Boolean;

    { ----- Traversal ----- }
    procedure ForEachTable(Proc: TProc<TTOMLTable>); overload;
    procedure ForEachTable(Callback: TFunc<Integer, TTOMLTable, Boolean>; SkipNonTables: Boolean = True); overload;
  end;
{ ---- Global factory / parse helpers ---- }

function NewTable: TTOMLTable;

function NewArray: TTOMLArray;

function LoadTOML(const FileName: string; APreserveComments: Boolean = False): TTOMLTable;

function ParseTOML(const ATOML: string; APreserveComments: Boolean = False): TTOMLTable;

function TryParseTOML(const ATOML: string; out Config: TTOMLTable; APreserveComments: Boolean = False): Boolean;
{ ---- Path helpers (internal, also publicly callable) ---- }

function SplitPath(const Path: string): TArray<string>;

function NavigateToTable(Root: TTOMLTable; const Path: string): TTOMLTable;

function GetValueFromPath(Root: TTOMLTable; const Path: string): TTOMLValue;

implementation

uses
  StrUtils, Math;
{ =========================================================================
  Global helpers
  ========================================================================= }

function NewTable: TTOMLTable;
begin
  Result := TTOMLTable.Create;
end;

function NewArray: TTOMLArray;
begin
  Result := TTOMLArray.Create;
end;

function LoadTOML(const FileName: string; APreserveComments: Boolean): TTOMLTable;
begin
  try
    Result := TOML.Parser.ParseTOMLFile(FileName, APreserveComments);
  except
    Result := nil;
  end;
end;

function ParseTOML(const ATOML: string; APreserveComments: Boolean): TTOMLTable;
begin
  try
    Result := TOML.Parser.ParseTOMLString(ATOML, APreserveComments);
  except
    Result := nil;
  end;
end;

function TryParseTOML(const ATOML: string; out Config: TTOMLTable; APreserveComments: Boolean): Boolean;
begin
  try
    Config := TOML.Parser.ParseTOMLString(ATOML, APreserveComments);
    Result := Assigned(Config);
  except
    Config := nil;
    Result := False;
  end;
end;
{ =========================================================================
  Path helpers
  ========================================================================= }

function SplitPath(const Path: string): TArray<string>;
var
  Parts: TList<string>;
  Current: string;
  i: Integer;
  InBasic: Boolean;
  InLiteral: Boolean;
  Ch: Char;
begin
  Parts := TList<string>.Create;
  try
    Current := '';
    InBasic := False;
    InLiteral := False;
    for i := 1 to Length(Path) do
    begin
      Ch := Path[i];
      if (Ch = '"') and not InLiteral then
      begin
        InBasic := not InBasic;
        Continue;
      end;
      if (Ch = '''') and not InBasic then
      begin
        InLiteral := not InLiteral;
        Continue;
      end;
      if (Ch = '.') and not InBasic and not InLiteral then
      begin
        Parts.Add(Current);
        Current := '';
        Continue;
      end;
      Current := Current + Ch;
    end;
    Parts.Add(Current);
    SetLength(Result, Parts.Count);
    for i := 0 to Parts.Count - 1 do
      Result[i] := Parts[i];
  finally
    Parts.Free;
  end;
end;

function NavigateToTable(Root: TTOMLTable; const Path: string): TTOMLTable;
var
  Parts: TArray<string>;
  CurrentTable: TTOMLTable;
  Value: TTOMLValue;
  i: Integer;
begin
  Result := nil;
  if not Assigned(Root) then
    Exit;
  if Path = '' then
  begin
    Result := Root;
    Exit;
  end;
  try
    Parts := SplitPath(Path);
    CurrentTable := Root;
    for i := 0 to High(Parts) do
    begin
      if not CurrentTable.TryGetValue(Parts[i], Value) then
        Exit;
      if Value is TTOMLTable then
        CurrentTable := TTOMLTable(Value)
      else if (Value is TTOMLArray) and (i < High(Parts)) then
      begin
        if TTOMLArray(Value).Count > 0 then
          CurrentTable := TTOMLTable(TTOMLArray(Value).GetItem(TTOMLArray(Value).Count - 1))
        else
          Exit;
      end
      else
        Exit;
    end;
    Result := CurrentTable;
  except
    Result := nil;
  end;
end;

function GetValueFromPath(Root: TTOMLTable; const Path: string): TTOMLValue;
var
  Parts: TArray<string>;
  CurrentTable: TTOMLTable;
  i: Integer;
  Val: TTOMLValue;
  CleanKey: string;
begin
  Result := nil;
  if not Assigned(Root) or (Path = '') then
    Exit;
  if (Length(Path) >= 2) and (((Path[1] = '"') and (Path[Length(Path)] = '"')) or ((Path[1] = '''') and (Path[Length
    (Path)] = ''''))) then
  begin
    CleanKey := Copy(Path, 2, Length(Path) - 2);
    if Root.TryGetValue(CleanKey, Result) then
      Exit;
  end;
  try
    Parts := SplitPath(Path);
    if Length(Parts) = 0 then
      Exit;
    CurrentTable := Root;
    for i := 0 to High(Parts) do
    begin
      CleanKey := Parts[i];
      if (Length(CleanKey) >= 2) and (((CleanKey[1] = '"') and (CleanKey[Length(CleanKey)] = '"')) or ((CleanKey
        [1] = '''') and (CleanKey[Length(CleanKey)] = ''''))) then
        CleanKey := Copy(CleanKey, 2, Length(CleanKey) - 2);
      if not CurrentTable.TryGetValue(CleanKey, Val) then
      begin
        Result := nil;
        Exit;
      end;
      if i = High(Parts) then
      begin
        Result := Val;
        Exit;
      end;
      if Val is TTOMLTable then
        CurrentTable := TTOMLTable(Val)
      else if (Val is TTOMLArray) and (TTOMLArray(Val).Count > 0) then
      begin
        Val := TTOMLArray(Val).GetItem(TTOMLArray(Val).Count - 1);
        if Val is TTOMLTable then
          CurrentTable := TTOMLTable(Val)
        else
          Exit;
      end
      else
        Exit;
    end;
  except
    Result := nil;
  end;
end;
{ Write a value at the given path (creates intermediate tables as needed).
  Ownership of NewValue is transferred on success; caller retains it on failure. }

function SetValueAtPath(Root: TTOMLTable; const Parts: TArray<string>; NewValue: TTOMLValue; Overwrite:
  Boolean): Boolean;
var
  CurrentTable: TTOMLTable;
  ExistingValue: TTOMLValue;
  NewTable: TTOMLTable;
  LastKey: string;
  i: Integer;
begin
  Result := False;
  if (Length(Parts) = 0) or not Assigned(Root) then
    Exit;
  CurrentTable := Root;
  for i := 0 to High(Parts) - 1 do
  begin
    if CurrentTable.Items.TryGetValue(Parts[i], ExistingValue) then
    begin
      if ExistingValue is TTOMLTable then
        CurrentTable := TTOMLTable(ExistingValue)
      else if (ExistingValue is TTOMLArray) and (TTOMLArray(ExistingValue).Count > 0) and (TTOMLArray(ExistingValue).GetItem
        (TTOMLArray(ExistingValue).Count - 1) is TTOMLTable) then
        CurrentTable := TTOMLTable(TTOMLArray(ExistingValue).GetItem(TTOMLArray(ExistingValue).Count - 1))
      else
        Exit;
    end
    else
    begin
      NewTable := TTOMLTable.Create;
      try
        CurrentTable.Items.AddOrSetValue(Parts[i], NewTable);
      except
        NewTable.Free;
        Exit;
      end;
      CurrentTable := NewTable;
    end;
  end;

  LastKey := Parts[High(Parts)];
  if CurrentTable.Items.TryGetValue(LastKey, ExistingValue) then
  begin
    if not Overwrite then
      Exit(False);
    ExistingValue.Free;
  end;
  CurrentTable.Items.AddOrSetValue(LastKey, NewValue);
  Result := True;
end;
{ =========================================================================
  TTOMLTableHelper — Read
  ========================================================================= }

function TTOMLTableHelper.GetStr(const Key: string; const DefaultValue: string): string;
var
  Value: TTOMLValue;
begin
  try
    Value := GetValueFromPath(Self, Key);
    if Assigned(Value) and (Value is TTOMLString) then
      Result := Value.AsString
    else
      Result := DefaultValue;
  except
    Result := DefaultValue;
  end;
end;

function TTOMLTableHelper.TryGetStr(const Key: string; out Value: string): Boolean;
var
  TOMLVal: TTOMLValue;
begin
  try
    TOMLVal := GetValueFromPath(Self, Key);
    Result := Assigned(TOMLVal) and (TOMLVal is TTOMLString);
    if Result then
      Value := TOMLVal.AsString;
  except
    Result := False;
  end;
end;

function TTOMLTableHelper.GetInt(const Key: string; const DefaultValue: Int64): Int64;
var
  Value: TTOMLValue;
begin
  try
    Value := GetValueFromPath(Self, Key);
    if Assigned(Value) and (Value is TTOMLInteger) then
      Result := Value.AsInteger
    else
      Result := DefaultValue;
  except
    Result := DefaultValue;
  end;
end;

function TTOMLTableHelper.TryGetInt(const Key: string; out Value: Integer): Boolean;
var
  TOMLVal: TTOMLValue;
begin
  try
    TOMLVal := GetValueFromPath(Self, Key);
    Result := Assigned(TOMLVal) and (TOMLVal is TTOMLInteger);
    if Result then
      Value := TOMLVal.AsInteger;
  except
    Result := False;
  end;
end;

function TTOMLTableHelper.GetFloat(const Key: string; const DefaultValue: Double): Double;
var
  Value: TTOMLValue;
begin
  try
    Value := GetValueFromPath(Self, Key);
    if Assigned(Value) then
    begin
      if Value is TTOMLFloat then
        Result := Value.AsFloat
      else if Value is TTOMLInteger then
        Result := Value.AsInteger
      else
        Result := DefaultValue;
    end
    else
      Result := DefaultValue;
  except
    Result := DefaultValue;
  end;
end;

function TTOMLTableHelper.TryGetFloat(const Key: string; out Value: Double): Boolean;
var
  TOMLVal: TTOMLValue;
begin
  try
    TOMLVal := GetValueFromPath(Self, Key);
    Result := Assigned(TOMLVal) and (TOMLVal is TTOMLFloat);
    if Result then
      Value := TOMLVal.AsFloat;
  except
    Result := False;
  end;
end;

function TTOMLTableHelper.GetFloatValue(const Key: string; const DefaultValue: string): string;
var
  Value: TTOMLValue;
begin
  try
    Value := GetValueFromPath(Self, Key);
    if Assigned(Value) and (Value is TTOMLFloat) then
      Result := TTOMLFloat(Value).RawString
    else
      Result := DefaultValue;
  except
    Result := DefaultValue;
  end;
end;

function TTOMLTableHelper.TryGetFloatValue(const Key: string; out Value: string): Boolean;
var
  TOMLVal: TTOMLValue;
begin
  try
    TOMLVal := GetValueFromPath(Self, Key);
    Result := Assigned(TOMLVal) and (TOMLVal is TTOMLFloat);
    if Result then
      Value := TTOMLFloat(TOMLVal).RawString;
  except
    Result := False;
  end;
end;

function TTOMLTableHelper.GetBool(const Key: string; const DefaultValue: Boolean): Boolean;
var
  Value: TTOMLValue;
begin
  try
    Value := GetValueFromPath(Self, Key);
    if Assigned(Value) and (Value is TTOMLBoolean) then
      Result := Value.AsBoolean
    else
      Result := DefaultValue;
  except
    Result := DefaultValue;
  end;
end;

function TTOMLTableHelper.TryGetBool(const Key: string; out Value: Boolean): Boolean;
var
  TOMLVal: TTOMLValue;
begin
  try
    TOMLVal := GetValueFromPath(Self, Key);
    Result := Assigned(TOMLVal) and (TOMLVal is TTOMLBoolean);
    if Result then
      Value := TOMLVal.AsBoolean;
  except
    Result := False;
  end;
end;

function TTOMLTableHelper.GetDateTime(const Key: string; const DefaultValue: TDateTime): TDateTime;
var
  Value: TTOMLValue;
begin
  try
    Value := GetValueFromPath(Self, Key);
    if Assigned(Value) and (Value is TTOMLDateTime) then
      Result := Value.AsDateTime
    else
      Result := DefaultValue;
  except
    Result := DefaultValue;
  end;
end;

function TTOMLTableHelper.TryGetDateTime(const Key: string; out Value: TDateTime): Boolean;
var
  TOMLVal: TTOMLValue;
begin
  try
    TOMLVal := GetValueFromPath(Self, Key);
    Result := Assigned(TOMLVal) and (TOMLVal is TTOMLDateTime);
    if Result then
      Value := TOMLVal.AsDateTime;
  except
    Result := False;
  end;
end;

function TTOMLTableHelper.GetDateTimeValue(const Key: string; const DefaultValue: string): string;
var
  Value: TTOMLValue;
begin
  try
    Value := GetValueFromPath(Self, Key);
    if Assigned(Value) and (Value is TTOMLDateTime) then
      Result := TTOMLDateTime(Value).RawString
    else
      Result := DefaultValue;
  except
    Result := DefaultValue;
  end;
end;

function TTOMLTableHelper.TryGetDateTimeValue(const Key: string; out Value: string): Boolean;
var
  TOMLVal: TTOMLValue;
begin
  try
    TOMLVal := GetValueFromPath(Self, Key);
    Result := Assigned(TOMLVal) and (TOMLVal is TTOMLDateTime);
    if Result then
      Value := TTOMLDateTime(TOMLVal).RawString;
  except
    Result := False;
  end;
end;

function TTOMLTableHelper.GetArray(const Key: string): TTOMLArray;
var
  Value: TTOMLValue;
begin
  try
    Value := GetValueFromPath(Self, Key);
    if Assigned(Value) and (Value is TTOMLArray) then
      Result := Value.AsArray
    else
      Result := nil;
  except
    Result := nil;
  end;
end;

function TTOMLTableHelper.TryGetArray(const Key: string; out Value: TTOMLArray): Boolean;
var
  TOMLVal: TTOMLValue;
begin
  try
    TOMLVal := GetValueFromPath(Self, Key);
    Result := Assigned(TOMLVal) and (TOMLVal is TTOMLArray);
    if Result then
      Value := TOMLVal.AsArray;
  except
    Result := False;
  end;
end;

function TTOMLTableHelper.GetTable(const Key: string): TTOMLTable;
begin
  try
    Result := NavigateToTable(Self, Key);
  except
    Result := nil;
  end;
end;

function TTOMLTableHelper.TryGetTable(const Key: string; out Value: TTOMLTable): Boolean;
begin
  Value := NavigateToTable(Self, Key);
  Result := Assigned(Value);
end;

function TTOMLTableHelper.HasKey(const Key: string): Boolean;
var
  Value: TTOMLValue;
begin
  try
    Value := GetValueFromPath(Self, Key);
    Result := Assigned(Value);
  except
    Result := False;
  end;
end;

procedure TTOMLTableHelper.GetKeys(Keys: TStrings; Recursive: Boolean);
var
  AllKeys: TArray<string>;
  K: string;
  SubTable: TTOMLTable;
  SubKeys: TStringList;
  i: Integer;
  V: TTOMLValue;
begin
  if not Assigned(Keys) then
    Exit;
  try
    Keys.Clear;
    AllKeys := Self.Items.Keys;
    for K in AllKeys do
    begin
      Keys.Add(K);
      if Recursive then
      begin
        if Self.TryGetValue(K, V) and (V is TTOMLTable) then
        begin
          SubTable := TTOMLTable(V);
          SubKeys := TStringList.Create;
          try
            SubTable.GetKeys(SubKeys, True);
            for i := 0 to SubKeys.Count - 1 do
              Keys.Add(K + '.' + SubKeys[i]);
          finally
            SubKeys.Free;
          end;
        end;
      end;
    end;
  except
  end;
end;
{ =========================================================================
  TTOMLTableHelper — Write
  ========================================================================= }

function TTOMLTableHelper.SetStr(const Key: string; const Value: string; Overwrite: Boolean): Boolean;
var
  NewValue: TTOMLString;
begin
  try
    NewValue := TTOMLString.Create(Value);
    Result := SetValueAtPath(Self, SplitPath(Key), NewValue, Overwrite);
    if not Result then
      NewValue.Free;
  except
    Result := False;
  end;
end;

function TTOMLTableHelper.SetInt(const Key: string; const Value: Int64; Overwrite: Boolean): Boolean;
var
  NewValue: TTOMLInteger;
begin
  try
    NewValue := TTOMLInteger.Create(Value);
    Result := SetValueAtPath(Self, SplitPath(Key), NewValue, Overwrite);
    if not Result then
      NewValue.Free;
  except
    Result := False;
  end;
end;

function TTOMLTableHelper.SetFloat(const Key: string; const Value: Double; Overwrite: Boolean): Boolean;
var
  NewValue: TTOMLFloat;
begin
  try
    NewValue := TTOMLFloat.Create(Value);
    Result := SetValueAtPath(Self, SplitPath(Key), NewValue, Overwrite);
    if not Result then
      NewValue.Free;
  except
    Result := False;
  end;
end;

function TTOMLTableHelper.SetFloatValue(const Key: string; const RawValue: string; Overwrite: Boolean): Boolean;
var
  NewValue: TTOMLFloat;
  FS: TFormatSettings;
  F: Double;
begin
  try
    FS := TFormatSettings.Invariant;
    if SameText(RawValue, 'inf') or SameText(RawValue, '+inf') then
      F := Infinity
    else if SameText(RawValue, '-inf') then
      F := NegInfinity
    else if SameText(RawValue, 'nan') then
      F := NaN
    else if not TryStrToFloat(RawValue, F, FS) then
      raise ETOMLException.CreateFmt('SetFloatValue: "%s" is not a valid TOML float', [RawValue]);
    NewValue := TTOMLFloat.Create(F, RawValue);
    Result := SetValueAtPath(Self, SplitPath(Key), NewValue, Overwrite);
    if not Result then
      NewValue.Free;
  except
    Result := False;
  end;
end;

function TTOMLTableHelper.SetBool(const Key: string; const Value: Boolean; Overwrite: Boolean): Boolean;
var
  NewValue: TTOMLBoolean;
begin
  try
    NewValue := TTOMLBoolean.Create(Value);
    Result := SetValueAtPath(Self, SplitPath(Key), NewValue, Overwrite);
    if not Result then
      NewValue.Free;
  except
    Result := False;
  end;
end;

function TTOMLTableHelper.SetDateTime(const Key: string; const Value: TDateTime; Overwrite: Boolean): Boolean;
var
  NewValue: TTOMLDateTime;
begin
  try
    NewValue := TTOMLDateTime.Create(Value);
    Result := SetValueAtPath(Self, SplitPath(Key), NewValue, Overwrite);
    if not Result then
      NewValue.Free;
  except
    Result := False;
  end;
end;

function TTOMLTableHelper.SetDateTimeValue(const Key: string; const RawValue: string; Overwrite: Boolean): Boolean;
var
  Temp: TTOMLTable;
  RawVal: TTOMLValue;
  NewValue: TTOMLDateTime;
begin
  try
    Temp := TOML.Parser.ParseTOMLString('__dt__ = ' + RawValue);
    try
      if not Temp.TryGetValue('__dt__', RawVal) then
        raise ETOMLParserException.Create('SetDateTimeValue: no value returned');
      if not (RawVal is TTOMLDateTime) then
        raise ETOMLParserException.CreateFmt('SetDateTimeValue: "%s" is not a datetime', [RawValue]);
      NewValue := TTOMLDateTime.Create(TTOMLDateTime(RawVal).Value, RawValue, TTOMLDateTime(RawVal).Kind,
        TTOMLDateTime(RawVal).TimeZoneOffset);
    finally
      Temp.Free;
    end;
    Result := SetValueAtPath(Self, SplitPath(Key), NewValue, Overwrite);
    if not Result then
      NewValue.Free;
  except
    Result := False;
  end;
end;

function TTOMLTableHelper.SetArray(const Key: string; Value: TTOMLArray; Overwrite: Boolean): Boolean;
begin
  Result := False;
  if not Assigned(Value) then
    Exit;
  try
    Result := SetValueAtPath(Self, SplitPath(Key), Value, Overwrite);
  except
    Result := False;
  end;
end;

function TTOMLTableHelper.SetTable(const Key: string; Value: TTOMLTable; Overwrite: Boolean): Boolean;
begin
  Result := False;
  if not Assigned(Value) then
    Exit;
  try
    Result := SetValueAtPath(Self, SplitPath(Key), Value, Overwrite);
  except
    Result := False;
  end;
end;
{ =========================================================================
  TTOMLTableHelper — Builder
  ========================================================================= }

function TTOMLTableHelper.Put(const Key: string; const Value: string; Overwrite: Boolean): TTOMLTable;
begin
  SetStr(Key, Value, Overwrite);
  Result := Self;
end;

function TTOMLTableHelper.Put(const Key: string; const Value: Int64; Overwrite: Boolean): TTOMLTable;
begin
  SetInt(Key, Value, Overwrite);
  Result := Self;
end;

function TTOMLTableHelper.Put(const Key: string; const Value: Integer; Overwrite: Boolean): TTOMLTable;
begin
  SetInt(Key, Value, Overwrite);
  Result := Self;
end;

function TTOMLTableHelper.Put(const Key: string; const Value: Double; Overwrite: Boolean): TTOMLTable;
begin
  SetFloat(Key, Value, Overwrite);
  Result := Self;
end;

function TTOMLTableHelper.Put(const Key: string; const Value: Boolean; Overwrite: Boolean): TTOMLTable;
begin
  SetBool(Key, Value, Overwrite);
  Result := Self;
end;

function TTOMLTableHelper.Put(const Key: string; const Value: TDateTime; Overwrite: Boolean): TTOMLTable;
begin
  SetDateTime(Key, Value, Overwrite);
  Result := Self;
end;

function TTOMLTableHelper.Put(const Key: string; Value: TTOMLArray; Overwrite: Boolean): TTOMLTable;
begin
  SetArray(Key, Value, Overwrite);
  Result := Self;
end;

function TTOMLTableHelper.Put(const Key: string; Value: TTOMLTable; Overwrite: Boolean): TTOMLTable;
begin
  SetTable(Key, Value, Overwrite);
  Result := Self;
end;
{ =========================================================================
  TTOMLTableHelper — File / string I/O
  ========================================================================= }

class function TTOMLTableHelper.CreateFromFile(const FileName: string; APreserveComments: Boolean): TTOMLTable;
begin
  try
    Result := TOML.Parser.ParseTOMLFile(FileName, APreserveComments);
  except
    Result := nil;
  end;
end;

function TTOMLTableHelper.LoadFromFile(const FileName: string; ClearExisting, APreserveComments: Boolean): Boolean;
var
  Loaded: TTOMLTable;
  i: Integer;
begin
  Result := False;
  try
    Loaded := TOML.Parser.ParseTOMLFile(FileName, APreserveComments);
    if not Assigned(Loaded) then
      Exit;
    try
      if ClearExisting then
        Self.Clear(True);
      for i := 0 to Loaded.Items.Count - 1 do
        Self.Items.AddOrSetValue(Loaded.Items.GetKey(i), Loaded.Items.GetValue(i));
      Loaded.Items.Clear; // don't free values — ownership transferred
      Result := True;
    finally
      Loaded.Free;
    end;
  except
    Result := False;
  end;
end;

class function TTOMLTableHelper.CreateFromString(const ATOML: string; APreserveComments: Boolean = False): TTOMLTable;
begin
  try
    Result := TOML.Parser.ParseTOMLString(ATOML, APreserveComments);
  except
    Result := nil;
  end;
end;

function TTOMLTableHelper.LoadFromString(const ATOML: string; ClearExisting, APreserveComments: Boolean): Boolean;
var
  Loaded: TTOMLTable;
  i: Integer;
begin
  Result := False;
  try
    Loaded := TOML.Parser.ParseTOMLString(ATOML, APreserveComments);
    if not Assigned(Loaded) then
      Exit;
    try
      if ClearExisting then
        Self.Clear(True);
      for i := 0 to Loaded.Items.Count - 1 do
        Self.Items.AddOrSetValue(Loaded.Items.GetKey(i), Loaded.Items.GetValue(i));
      Loaded.Items.Clear;
      Result := True;
    finally
      Loaded.Free;
    end;
  except
    Result := False;
  end;
end;

function TTOMLTableHelper.SaveToFile(const FileName: string; WriteBOM: Boolean; AWrapWidth: Integer;
  APreserveComments: Boolean): Boolean;
begin
  try
    Result := TOML.Serializer.SerializeTOMLToFile(Self, FileName, WriteBOM, AWrapWidth, APreserveComments);
  except
    Result := False;
  end;
end;
{ =========================================================================
  TTOMLTableHelper — Serialization
  ========================================================================= }

function TTOMLTableHelper.toString(AWrapWidth: Integer; APreserveComments: Boolean): string;
begin
  try
    Result := TOML.Serializer.SerializeTOML(Self, AWrapWidth, APreserveComments);
  except
    Result := '';
  end;
end;
{ =========================================================================
  TTOMLTableHelper — Tools
  ========================================================================= }

function TTOMLTableHelper.Remove(const Key: string; FreeValue: Boolean): Boolean;
var
  Value: TTOMLValue;
begin
  try
    Result := Self.Items.TryGetValue(Key, Value);
    if Result then
    begin
      if FreeValue and Assigned(Value) then
        Value.Free;
      Self.Items.Remove(Key);
    end;
  except
    Result := False;
  end;
end;

procedure TTOMLTableHelper.Clear(FreeValues: Boolean);
var
  i: Integer;
begin
  try
    if FreeValues then
      for i := 0 to Self.Items.Count - 1 do
      begin
        var V := Self.Items.GetValue(i);
        if Assigned(V) then
          V.Free;
      end;
    Self.Items.Clear;
  except
  end;
end;

function TTOMLTableHelper.Count: Integer;
begin
  try
    Result := Self.Items.Count;
  except
    Result := 0;
  end;
end;

function TTOMLTableHelper.Clone: TTOMLTable;
begin
  try
    Result := ParseTOML(Self.toString);
  except
    Result := nil;
  end;
end;
{ =========================================================================
  TTOMLTableHelper — JSON
  ========================================================================= }

function TTOMLTableHelper.ToJSON(APretty: Boolean; AIndentSize: Integer): string;
begin
  try
    Result := TOMLToJSON(Self, APretty, AIndentSize);
  except
    Result := '';
  end;
end;

function TTOMLTableHelper.LoadFromJSON(const AJSON: string; ANullAsEmptyString: Boolean): Boolean;
var
  Parsed: TTOMLTable;
  i: Integer;
begin
  Result := False;
  try
    Parsed := JSONToTOML(AJSON, ANullAsEmptyString);
    try
      Self.Clear(True);
      for i := 0 to Parsed.Items.Count - 1 do
        Self.Add(Parsed.Items.GetKey(i), Parsed.Items.GetValue(i));
      Parsed.Items.Clear;
    finally
      Parsed.Free;
    end;
    Result := True;
  except
  end;
end;

function TTOMLTableHelper.SaveToJSONFile(const FileName: string; APretty: Boolean; ABOM: Boolean): Boolean;
var
  JSON: string;
  SL: TStringList;
begin
  Result := False;
  try
    JSON := TOMLToJSON(Self, APretty);
    SL := TStringList.Create;
    try
      SL.Text := JSON;
      SL.SaveToFile(FileName, TEncoding.UTF8);
      Result := True;
    finally
      SL.Free;
    end;
  except
  end;
end;

function TTOMLTableHelper.LoadFromJSONFile(const FileName: string; ANullAsEmptyString: Boolean): Boolean;
var
  SL: TStringList;
  JSON: string;
begin
  Result := False;
  try
    SL := TStringList.Create;
    try
      SL.LoadFromFile(FileName, TEncoding.UTF8);
      JSON := SL.Text;
    finally
      SL.Free;
    end;
    Result := LoadFromJSON(JSON, ANullAsEmptyString);
  except
  end;
end;
{ =========================================================================
  TTOMLArrayHelper — Read
  ========================================================================= }

function TTOMLArrayHelper.GetStr(Index: Integer; const DefaultValue: string): string;
var
  Item: TTOMLValue;
begin
  try
    if (Index >= 0) and (Index < Self.Count) then
    begin
      Item := Self.GetItem(Index);
      if Assigned(Item) and (Item is TTOMLString) then
        Result := Item.AsString
      else
        Result := DefaultValue;
    end
    else
      Result := DefaultValue;
  except
    Result := DefaultValue;
  end;
end;

function TTOMLArrayHelper.TryGetStr(Index: Integer; out Value: string): Boolean;
var
  Item: TTOMLValue;
begin
  try
    Result := (Index >= 0) and (Index < Self.Count);
    if Result then
    begin
      Item := Self.Items[Index];
      Result := Assigned(Item) and (Item is TTOMLString);
      if Result then
        Value := TTOMLString(Item).Value;
    end;
  except
    Result := False;
  end;
end;

function TTOMLArrayHelper.GetInt(Index: Integer; const DefaultValue: Int64): Int64;
var
  Item: TTOMLValue;
begin
  try
    if (Index >= 0) and (Index < Self.Count) then
    begin
      Item := Self.GetItem(Index);
      if Assigned(Item) and (Item is TTOMLInteger) then
        Result := Item.AsInteger
      else
        Result := DefaultValue;
    end
    else
      Result := DefaultValue;
  except
    Result := DefaultValue;
  end;
end;

function TTOMLArrayHelper.TryGetInt(Index: Integer; out Value: Integer): Boolean;
var
  Item: TTOMLValue;
begin
  try
    Result := (Index >= 0) and (Index < Self.Count);
    if Result then
    begin
      Item := Self.Items[Index];
      Result := Assigned(Item) and (Item is TTOMLInteger);
      if Result then
        Value := TTOMLInteger(Item).Value;
    end;
  except
    Result := False;
  end;
end;

function TTOMLArrayHelper.GetFloat(Index: Integer; const DefaultValue: Double): Double;
var
  Item: TTOMLValue;
begin
  try
    if (Index >= 0) and (Index < Self.Count) then
    begin
      Item := Self.GetItem(Index);
      if Assigned(Item) then
      begin
        if Item is TTOMLFloat then
          Result := Item.AsFloat
        else if Item is TTOMLInteger then
          Result := Item.AsInteger
        else
          Result := DefaultValue;
      end
      else
        Result := DefaultValue;
    end
    else
      Result := DefaultValue;
  except
    Result := DefaultValue;
  end;
end;

function TTOMLArrayHelper.TryGetFloat(Index: Integer; out Value: Double): Boolean;
var
  Item: TTOMLValue;
begin
  try
    Result := (Index >= 0) and (Index < Self.Count);
    if Result then
    begin
      Item := Self.Items[Index];
      Result := Assigned(Item) and (Item is TTOMLFloat);
      if Result then
        Value := TTOMLFloat(Item).Value;
    end;
  except
    Result := False;
  end;
end;

function TTOMLArrayHelper.GetFloatValue(Index: Integer; const DefaultValue: string): string;
var
  Item: TTOMLValue;
begin
  try
    if (Index >= 0) and (Index < Self.Count) then
    begin
      Item := Self.GetItem(Index);
      if Assigned(Item) and (Item is TTOMLFloat) then
        Result := TTOMLFloat(Item).RawString
      else
        Result := DefaultValue;
    end
    else
      Result := DefaultValue;
  except
    Result := DefaultValue;
  end;
end;

function TTOMLArrayHelper.TryGetFloatValue(Index: Integer; out Value: string): Boolean;
var
  Item: TTOMLValue;
begin
  try
    Result := (Index >= 0) and (Index < Self.Count);
    if Result then
    begin
      Item := Self.Items[Index];
      Result := Assigned(Item) and (Item is TTOMLFloat);
      if Result then
        Value := TTOMLFloat(Item).RawString;
    end;
  except
    Result := False;
  end;
end;

function TTOMLArrayHelper.GetBool(Index: Integer; const DefaultValue: Boolean): Boolean;
var
  Item: TTOMLValue;
begin
  try
    if (Index >= 0) and (Index < Self.Count) then
    begin
      Item := Self.GetItem(Index);
      if Assigned(Item) and (Item is TTOMLBoolean) then
        Result := Item.AsBoolean
      else
        Result := DefaultValue;
    end
    else
      Result := DefaultValue;
  except
    Result := DefaultValue;
  end;
end;

function TTOMLArrayHelper.TryGetBool(Index: Integer; out Value: Boolean): Boolean;
var
  Item: TTOMLValue;
begin
  try
    Result := (Index >= 0) and (Index < Self.Count);
    if Result then
    begin
      Item := Self.Items[Index];
      Result := Assigned(Item) and (Item is TTOMLBoolean);
      if Result then
        Value := TTOMLBoolean(Item).Value;
    end;
  except
    Result := False;
  end;
end;

function TTOMLArrayHelper.GetDateTime(Index: Integer; const DefaultValue: TDateTime): TDateTime;
var
  Item: TTOMLValue;
begin
  try
    if (Index >= 0) and (Index < Self.Count) then
    begin
      Item := Self.GetItem(Index);
      if Assigned(Item) and (Item is TTOMLDateTime) then
        Result := Item.AsDateTime
      else
        Result := DefaultValue;
    end
    else
      Result := DefaultValue;
  except
    Result := DefaultValue;
  end;
end;

function TTOMLArrayHelper.TryGetDateTime(Index: Integer; out Value: TDateTime): Boolean;
var
  Item: TTOMLValue;
begin
  try
    Result := (Index >= 0) and (Index < Self.Count);
    if Result then
    begin
      Item := Self.Items[Index];
      Result := Assigned(Item) and (Item is TTOMLDateTime);
      if Result then
        Value := TTOMLDateTime(Item).Value;
    end;
  except
    Result := False;
  end;
end;

function TTOMLArrayHelper.GetDateTimeValue(Index: Integer; const DefaultValue: string): string;
var
  Item: TTOMLValue;
begin
  try
    if (Index >= 0) and (Index < Self.Count) then
    begin
      Item := Self.GetItem(Index);
      if Assigned(Item) and (Item is TTOMLDateTime) then
        Result := TTOMLDateTime(Item).RawString
      else
        Result := DefaultValue;
    end
    else
      Result := DefaultValue;
  except
    Result := DefaultValue;
  end;
end;

function TTOMLArrayHelper.TryGetDateTimeValue(Index: Integer; out Value: string): Boolean;
var
  Item: TTOMLValue;
begin
  try
    Result := (Index >= 0) and (Index < Self.Count);
    if Result then
    begin
      Item := Self.Items[Index];
      Result := Assigned(Item) and (Item is TTOMLDateTime);
      if Result then
        Value := TTOMLDateTime(Item).RawString;
    end;
  except
    Result := False;
  end;
end;

function TTOMLArrayHelper.TryGetArray(Index: Integer; out Value: TTOMLArray): Boolean;
var
  Item: TTOMLValue;
begin
  try
    Result := (Index >= 0) and (Index < Self.Count);
    if Result then
    begin
      Item := Self.Items[Index];
      Result := Assigned(Item) and (Item is TTOMLArray);
      if Result then
        Value := TTOMLArray(Item);
    end;
  except
    Result := False;
  end;
end;

function TTOMLArrayHelper.GetArray(Index: Integer): TTOMLArray;
var
  Item: TTOMLValue;
begin
  try
    if (Index >= 0) and (Index < Self.Count) then
    begin
      Item := Self.Items[Index];
      if Assigned(Item) and (Item is TTOMLArray) then
        Result := TTOMLArray(Item)
      else
        Result := nil;
    end
    else
      Result := nil;
  except
    Result := nil;
  end;
end;

function TTOMLArrayHelper.GetTable(Index: Integer): TTOMLTable;
var
  Item: TTOMLValue;
begin
  try
    if (Index >= 0) and (Index < Self.Count) then
    begin
      Item := Self.GetItem(Index);
      if Assigned(Item) and (Item is TTOMLTable) then
        Result := TTOMLTable(Item)
      else
        Result := nil;
    end
    else
      Result := nil;
  except
    Result := nil;
  end;
end;

function TTOMLArrayHelper.TryGetTable(Index: Integer; out Value: TTOMLTable): Boolean;
var
  Item: TTOMLValue;
begin
  try
    Result := (Index >= 0) and (Index < Self.Count);
    if Result then
    begin
      Item := Self.Items[Index];
      Result := Assigned(Item) and (Item is TTOMLTable);
      if Result then
        Value := TTOMLTable(Item);
    end;
  except
    Result := False;
  end;
end;

function TTOMLArrayHelper.TryGetItem(Index: Integer; out Value: TTOMLValue): Boolean;
begin
  try
    Result := (Index >= 0) and (Index < Self.Count);
    if Result then
      Value := Self.GetItem(Index)
    else
      Value := nil;
  except
    Value := nil;
    Result := False;
  end;
end;
{ =========================================================================
  TTOMLArrayHelper — Add
  ========================================================================= }

function TTOMLArrayHelper.AddStr(const Value: string): TTOMLArray;
var
  N: TTOMLString;
begin
  Result := Self;
  try
    N := TTOMLString.Create(Value);
    try
      Self.Add(N);
    except
      N.Free;
      Result := nil;
    end;
  except
    Result := nil;
  end;
end;

function TTOMLArrayHelper.AddInt(const Value: Int64): TTOMLArray;
var
  N: TTOMLInteger;
begin
  Result := Self;
  try
    N := TTOMLInteger.Create(Value);
    try
      Self.Add(N);
    except
      N.Free;
      Result := nil;
    end;
  except
    Result := nil;
  end;
end;

function TTOMLArrayHelper.AddFloat(const Value: Double): TTOMLArray;
var
  N: TTOMLFloat;
begin
  Result := Self;
  try
    N := TTOMLFloat.Create(Value);
    try
      Self.Add(N);
    except
      N.Free;
      Result := nil;
    end;
  except
    Result := nil;
  end;
end;

function TTOMLArrayHelper.AddFloatValue(const RawValue: string): TTOMLArray;
var
  N: TTOMLFloat;
  FS: TFormatSettings;
  F: Double;
begin
  Result := Self;
  try
    FS := TFormatSettings.Invariant;
    if SameText(RawValue, 'inf') or SameText(RawValue, '+inf') then
      F := Infinity
    else if SameText(RawValue, '-inf') then
      F := NegInfinity
    else if SameText(RawValue, 'nan') then
      F := NaN
    else if not TryStrToFloat(RawValue, F, FS) then
    begin
      Result := nil;
      Exit;
    end;
    N := TTOMLFloat.Create(F, RawValue);
    try
      Self.Add(N);
    except
      N.Free;
      Result := nil;
    end;
  except
    Result := nil;
  end;
end;

function TTOMLArrayHelper.AddBool(const Value: Boolean): TTOMLArray;
var
  N: TTOMLBoolean;
begin
  Result := Self;
  try
    N := TTOMLBoolean.Create(Value);
    try
      Self.Add(N);
    except
      N.Free;
      Result := nil;
    end;
  except
    Result := nil;
  end;
end;

function TTOMLArrayHelper.AddDateTime(const Value: TDateTime): TTOMLArray;
var
  N: TTOMLDateTime;
begin
  Result := Self;
  try
    N := TTOMLDateTime.Create(Value);
    try
      Self.Add(N);
    except
      N.Free;
      Result := nil;
    end;
  except
    Result := nil;
  end;
end;

function TTOMLArrayHelper.AddDateTimeValue(const RawValue: string): TTOMLArray;
var
  Temp: TTOMLTable;
  RawVal: TTOMLValue;
  NewValue: TTOMLDateTime;
begin
  Result := Self;
  try
    Temp := TOML.Parser.ParseTOMLString('__dt__ = ' + RawValue);
    try
      if not Temp.TryGetValue('__dt__', RawVal) or not (RawVal is TTOMLDateTime) then
      begin
        Result := nil;
        Exit;
      end;
      NewValue := TTOMLDateTime.Create(TTOMLDateTime(RawVal).Value, RawValue, TTOMLDateTime(RawVal).Kind,
        TTOMLDateTime(RawVal).TimeZoneOffset);
    finally
      Temp.Free;
    end;
    try
      Self.Add(NewValue);
    except
      NewValue.Free;
      Result := nil;
    end;
  except
    Result := nil;
  end;
end;

function TTOMLArrayHelper.AddTable(Value: TTOMLTable): TTOMLArray;
begin
  Result := Self;
  if not Assigned(Value) then
    Exit;
  try
    Self.Add(Value);
  except
    Result := nil;
  end;
end;

function TTOMLArrayHelper.AddArray(Value: TTOMLArray): TTOMLArray;
begin
  Result := Self;
  if not Assigned(Value) then
    Exit;
  try
    Self.Add(Value);
  except
    Result := nil;
  end;
end;
{ =========================================================================
  TTOMLArrayHelper — Set
  ========================================================================= }

function TTOMLArrayHelper.SetStr(Index: Integer; const Value: string): Boolean;
var
  OldItem: TTOMLValue;
  NewValue: TTOMLString;
begin
  Result := False;
  try
    if (Index < 0) or (Index >= Self.Count) then
      Exit;
    NewValue := TTOMLString.Create(Value);
    OldItem := Self.Items[Index];
    try
      Self.Items[Index] := NewValue;
      if Assigned(OldItem) then
        OldItem.Free;
      Result := True;
    except
      NewValue.Free;
      Self.Items[Index] := OldItem;
    end;
  except
    Result := False;
  end;
end;

function TTOMLArrayHelper.SetInt(Index: Integer; const Value: Int64): Boolean;
var
  OldItem: TTOMLValue;
  NewValue: TTOMLInteger;
begin
  Result := False;
  try
    if (Index < 0) or (Index >= Self.Count) then
      Exit;
    NewValue := TTOMLInteger.Create(Value);
    OldItem := Self.Items[Index];
    try
      Self.Items[Index] := NewValue;
      if Assigned(OldItem) then
        OldItem.Free;
      Result := True;
    except
      NewValue.Free;
      Self.Items[Index] := OldItem;
    end;
  except
    Result := False;
  end;
end;

function TTOMLArrayHelper.SetFloat(Index: Integer; const Value: Double): Boolean;
var
  OldItem: TTOMLValue;
  NewValue: TTOMLFloat;
begin
  Result := False;
  try
    if (Index < 0) or (Index >= Self.Count) then
      Exit;
    NewValue := TTOMLFloat.Create(Value);
    OldItem := Self.Items[Index];
    try
      Self.Items[Index] := NewValue;
      if Assigned(OldItem) then
        OldItem.Free;
      Result := True;
    except
      NewValue.Free;
      Self.Items[Index] := OldItem;
    end;
  except
    Result := False;
  end;
end;

function TTOMLArrayHelper.SetFloatValue(Index: Integer; const RawValue: string): Boolean;
var
  OldItem: TTOMLValue;
  Temp: TTOMLTable;
  RawVal: TTOMLValue;
  NewValue: TTOMLFloat;
begin
  Result := False;
  try
    if (Index < 0) or (Index >= Self.Count) then
      Exit;
    Temp := TOML.Parser.ParseTOMLString('__f__ = ' + RawValue);
    try
      if not Temp.TryGetValue('__f__', RawVal) or not (RawVal is TTOMLFloat) then
        Exit;
      NewValue := TTOMLFloat.Create(TTOMLFloat(RawVal).Value, RawValue);
    finally
      Temp.Free;
    end;
    OldItem := Self.Items[Index];
    try
      Self.Items[Index] := NewValue;
      if Assigned(OldItem) then
        OldItem.Free;
      Result := True;
    except
      NewValue.Free;
      Self.Items[Index] := OldItem;
    end;
  except
    Result := False;
  end;
end;

function TTOMLArrayHelper.SetBool(Index: Integer; const Value: Boolean): Boolean;
var
  OldItem: TTOMLValue;
  NewValue: TTOMLBoolean;
begin
  Result := False;
  try
    if (Index < 0) or (Index >= Self.Count) then
      Exit;
    NewValue := TTOMLBoolean.Create(Value);
    OldItem := Self.Items[Index];
    try
      Self.Items[Index] := NewValue;
      if Assigned(OldItem) then
        OldItem.Free;
      Result := True;
    except
      NewValue.Free;
      Self.Items[Index] := OldItem;
    end;
  except
    Result := False;
  end;
end;

function TTOMLArrayHelper.SetDateTime(Index: Integer; const Value: TDateTime): Boolean;
var
  OldItem: TTOMLValue;
  NewValue: TTOMLDateTime;
begin
  Result := False;
  try
    if (Index < 0) or (Index >= Self.Count) then
      Exit;
    NewValue := TTOMLDateTime.Create(Value);
    OldItem := Self.Items[Index];
    try
      Self.Items[Index] := NewValue;
      if Assigned(OldItem) then
        OldItem.Free;
      Result := True;
    except
      NewValue.Free;
      Self.Items[Index] := OldItem;
    end;
  except
    Result := False;
  end;
end;

function TTOMLArrayHelper.SetDateTimeValue(Index: Integer; const RawValue: string): Boolean;
var
  OldItem: TTOMLValue;
  Temp: TTOMLTable;
  RawVal: TTOMLValue;
  NewValue: TTOMLDateTime;
begin
  Result := False;
  try
    if (Index < 0) or (Index >= Self.Count) then
      Exit;
    Temp := TOML.Parser.ParseTOMLString('__dt__ = ' + RawValue);
    try
      if not Temp.TryGetValue('__dt__', RawVal) or not (RawVal is TTOMLDateTime) then
        Exit;
      NewValue := TTOMLDateTime.Create(TTOMLDateTime(RawVal).Value, RawValue, TTOMLDateTime(RawVal).Kind,
        TTOMLDateTime(RawVal).TimeZoneOffset);
    finally
      Temp.Free;
    end;
    OldItem := Self.Items[Index];
    try
      Self.Items[Index] := NewValue;
      if Assigned(OldItem) then
        OldItem.Free;
      Result := True;
    except
      NewValue.Free;
      Self.Items[Index] := OldItem;
    end;
  except
    Result := False;
  end;
end;

function TTOMLArrayHelper.SetArray(Index: Integer; Value: TTOMLArray): Boolean;
var
  OldItem: TTOMLValue;
begin
  Result := False;
  if not Assigned(Value) then
    Exit;
  try
    if (Index < 0) or (Index >= Self.Count) then
      Exit;
    OldItem := Self.Items[Index];
    try
      Self.Items[Index] := Value;
      if Assigned(OldItem) then
        OldItem.Free;
      Result := True;
    except
      Self.Items[Index] := OldItem;
    end;
  except
    Result := False;
  end;
end;

function TTOMLArrayHelper.SetTable(Index: Integer; Value: TTOMLTable): Boolean;
var
  OldItem: TTOMLValue;
begin
  Result := False;
  if not Assigned(Value) then
    Exit;
  try
    if (Index < 0) or (Index >= Self.Count) then
      Exit;
    OldItem := Self.Items[Index];
    try
      Self.Items[Index] := Value;
      if Assigned(OldItem) then
        OldItem.Free;
      Result := True;
    except
      Self.Items[Index] := OldItem;
    end;
  except
    Result := False;
  end;
end;
{ =========================================================================
  TTOMLArrayHelper — Insert
  ========================================================================= }

function TTOMLArrayHelper.InsertStr(Index: Integer; const Value: string): Boolean;
var
  N: TTOMLString;
begin
  Result := False;
  try
    if (Index < 0) or (Index > Self.Count) then
      Exit;
    N := TTOMLString.Create(Value);
    try
      Self.Items.Insert(Index, N);
      Result := True;
    except
      N.Free;
    end;
  except
    Result := False;
  end;
end;

function TTOMLArrayHelper.InsertInt(Index: Integer; const Value: Int64): Boolean;
var
  N: TTOMLInteger;
begin
  Result := False;
  try
    if (Index < 0) or (Index > Self.Count) then
      Exit;
    N := TTOMLInteger.Create(Value);
    try
      Self.Items.Insert(Index, N);
      Result := True;
    except
      N.Free;
    end;
  except
    Result := False;
  end;
end;

function TTOMLArrayHelper.InsertFloat(Index: Integer; const Value: Double): Boolean;
var
  N: TTOMLFloat;
begin
  Result := False;
  try
    if (Index < 0) or (Index > Self.Count) then
      Exit;
    N := TTOMLFloat.Create(Value);
    try
      Self.Items.Insert(Index, N);
      Result := True;
    except
      N.Free;
    end;
  except
    Result := False;
  end;
end;

function TTOMLArrayHelper.InsertFloatValue(Index: Integer; const RawValue: string): Boolean;
var
  Temp: TTOMLTable;
  RawVal: TTOMLValue;
  NewValue: TTOMLFloat;
begin
  Result := False;
  try
    if (Index < 0) or (Index > Self.Count) then
      Exit;
    Temp := TOML.Parser.ParseTOMLString('__f__ = ' + RawValue);
    try
      if not Temp.TryGetValue('__f__', RawVal) or not (RawVal is TTOMLFloat) then
        Exit;
      NewValue := TTOMLFloat.Create(TTOMLFloat(RawVal).Value, RawValue);
    finally
      Temp.Free;
    end;
    try
      Self.Items.Insert(Index, NewValue);
      Result := True;
    except
      NewValue.Free;
    end;
  except
    Result := False;
  end;
end;

function TTOMLArrayHelper.InsertBool(Index: Integer; const Value: Boolean): Boolean;
var
  N: TTOMLBoolean;
begin
  Result := False;
  try
    if (Index < 0) or (Index > Self.Count) then
      Exit;
    N := TTOMLBoolean.Create(Value);
    try
      Self.Items.Insert(Index, N);
      Result := True;
    except
      N.Free;
    end;
  except
    Result := False;
  end;
end;

function TTOMLArrayHelper.InsertDateTime(Index: Integer; const Value: TDateTime): Boolean;
var
  N: TTOMLDateTime;
begin
  Result := False;
  try
    if (Index < 0) or (Index > Self.Count) then
      Exit;
    N := TTOMLDateTime.Create(Value);
    try
      Self.Items.Insert(Index, N);
      Result := True;
    except
      N.Free;
    end;
  except
    Result := False;
  end;
end;

function TTOMLArrayHelper.InsertDateTimeValue(Index: Integer; const RawValue: string): Boolean;
var
  Temp: TTOMLTable;
  RawVal: TTOMLValue;
  NewValue: TTOMLDateTime;
begin
  Result := False;
  try
    if (Index < 0) or (Index > Self.Count) then
      Exit;
    Temp := TOML.Parser.ParseTOMLString('__dt__ = ' + RawValue);
    try
      if not Temp.TryGetValue('__dt__', RawVal) or not (RawVal is TTOMLDateTime) then
        Exit;
      NewValue := TTOMLDateTime.Create(TTOMLDateTime(RawVal).Value, RawValue, TTOMLDateTime(RawVal).Kind,
        TTOMLDateTime(RawVal).TimeZoneOffset);
    finally
      Temp.Free;
    end;
    try
      Self.Items.Insert(Index, NewValue);
      Result := True;
    except
      NewValue.Free;
    end;
  except
    Result := False;
  end;
end;

function TTOMLArrayHelper.InsertArray(Index: Integer; Value: TTOMLArray): Boolean;
begin
  Result := False;
  if not Assigned(Value) then
    Exit;
  try
    if (Index < 0) or (Index > Self.Count) then
      Exit;
    try
      Self.Items.Insert(Index, Value);
      Result := True;
    except
    end;
  except
    Result := False;
  end;
end;

function TTOMLArrayHelper.InsertTable(Index: Integer; Value: TTOMLTable): Boolean;
begin
  Result := False;
  if not Assigned(Value) then
    Exit;
  try
    if (Index < 0) or (Index > Self.Count) then
      Exit;
    try
      Self.Items.Insert(Index, Value);
      Result := True;
    except
    end;
  except
    Result := False;
  end;
end;
{ =========================================================================
  TTOMLArrayHelper — Tools / Traversal / Serialization
  ========================================================================= }

procedure TTOMLArrayHelper.Clear(FreeItems: Boolean);
var
  Item: TTOMLValue;
begin
  try
    if FreeItems then
      for Item in Self.Items do
        if Assigned(Item) then
          Item.Free;
    Self.Items.Clear;
  except
  end;
end;

function TTOMLArrayHelper.RemoveAt(Index: Integer; FreeItem: Boolean): Boolean;
var
  Item: TTOMLValue;
begin
  try
    Result := (Index >= 0) and (Index < Self.Count);
    if Result then
    begin
      Item := Self.Items[Index];
      if FreeItem and Assigned(Item) then
        Item.Free;
      Self.Items.Delete(Index);
    end;
  except
    Result := False;
  end;
end;

procedure TTOMLArrayHelper.ForEachTable(Proc: TProc<TTOMLTable>);
var
  i: Integer;
  Item: TTOMLValue;
begin
  if not Assigned(Proc) then
    Exit;
  try
    for i := 0 to Self.Count - 1 do
    begin
      Item := Self.GetItem(i);
      if Assigned(Item) and (Item is TTOMLTable) then
        Proc(TTOMLTable(Item));
    end;
  except
  end;
end;

procedure TTOMLArrayHelper.ForEachTable(Callback: TFunc<Integer, TTOMLTable, Boolean>; SkipNonTables: Boolean);
var
  i: Integer;
  Item: TTOMLValue;
  Cont: Boolean;
begin
  if not Assigned(Callback) then
    Exit;
  try
    for i := 0 to Self.Count - 1 do
    begin
      Item := Self.Items[i];
      if Assigned(Item) and (Item is TTOMLTable) then
      begin
        Cont := Callback(i, TTOMLTable(Item));
        if not Cont then
          Break;
      end
      else if not SkipNonTables then
        Break;
    end;
  except
  end;
end;

function TTOMLArrayHelper.toString: string;
begin
  try
    Result := TOML.Serializer.SerializeTOML(Self);
  except
    Result := '';
  end;
end;

end.
