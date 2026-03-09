{ TOML.Helper.pas
TOML auxiliary extension units, through class helpers,
provide TTOMLLTable and TTOMLArray with...
Provides a simpler and more secure read/write API.

Main functions:
- TTOMLTableHelper: Reading (GetXxx / TryGetXxx) and writing (SetXxx) tables.
Chained calls (Put), file operations (LoadFromFile / SaveToFile),
Key management (HasKey / GetKeys / Remove / Clear / Clone / Count)
- TTOMLArrayHelper: Reads array elements (GetXxx) and appends them (AddXxx).
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
  { TOML Table Assistant – Adding convenient read and write operations to TTOMLTable }
  TTOMLTableHelper = class helper for TTOMLTable
  public

    { ===== Read method ===== }

    { Read string values, supporting dotted paths (e.g., "server.host")
      @param Key Key name or dotted path
      @param DefaultValue The default value returned when the key does not exist.
      @returns string value or default value }
    function GetStr(const Key: string; const DefaultValue: string = ''): string;
    function TryGetStr(const Key: string; out Value: string): Boolean;

    { Read integer values (supports dotted paths) }
    function GetInt(const Key: string; const DefaultValue: Int64 = 0): Int64;
    function TryGetInt(const Key: string; out Value: Integer): Boolean;

    { Read floating-point values (supports dot path) }
    function GetFloat(const Key: string; const DefaultValue: Double = 0.0): Double;
    function TryGetFloat(const Key: string; out Value: Double): Boolean;

    { Read the raw text of floating-point numbers (preserving the exact
      representation in the TOML file, such as "3.14", "6.626e-34", "inf")
      Difference from GetFloat: GetFloat returns the converted Double,
      which may suffer from precision loss due to IEEE 754;
      GetFloatValue returns the raw string from the file, which can be safely
      used for display or high-precision scenarios. @param DefaultValue The default value returned when the key does not exist or is not a floating-point type. }
    function GetFloatValue(const Key: string; const DefaultValue: string = ''): string;
    function TryGetFloatValue(const Key: string; out Value: string): Boolean;

    { Read Boolean values (supports dotted paths) }
    function GetBool(const Key: string; const DefaultValue: Boolean = False): Boolean;
    function TryGetBool(const Key: string; out Value: Boolean): Boolean;

    { Read date and time value (returns TDateTime) }
    function GetDateTime(const Key: string; const DefaultValue: TDateTime = 0): TDateTime;
    function TryGetDateTime(const Key: string; out Value: TDateTime): Boolean;

    { Read date and time values (returns the raw string, preserving the exact format) }
    function GetDateTimeValue(const Key: string; const DefaultValue: string = ''): string;
    function TryGetDateTimeValue(const Key: string; out Value: string): Boolean;

    { Get array reference; return nil if it does not exist. }
    function GetArray(const Key: string): TTOMLArray;
    function TryGetArray(const Key: string; out Value: TTOMLArray): Boolean;

    { Retrieves a reference to the sub-table; returns nil if it does not exist. }
    function GetTable(const Key: string): TTOMLTable;
    function TryGetTable(const Key: string; out Value: TTOMLTable): Boolean;

    { Check if the key exists (supports dotted paths) }
    function HasKey(const Key: string): Boolean;

    { Get all key names
      @param Keys The list of keys to be output (does not need to be cleared
      before calling, it will be cleared inside the method).
      @param Recursive Whether to recursively enumerate the keys of child tables
      (prefixed with the parent key, such as "server.host") }
    procedure GetKeys(Keys: TStrings; Recursive: Boolean = False);

    { ===== Write methods (including overwrite control) ===== }

    { Write string value }
    function SetStr(const Key: string; const Value: string; Overwrite: Boolean = True): Boolean;

    { Write integer value }
    function SetInt(const Key: string; const Value: Int64; Overwrite: Boolean = True): Boolean;

    { Write float value }
    function SetFloat(const Key: string; const Value: Double; Overwrite: Boolean = True): Boolean;

    { Writes the raw text of the floating-point number (directly stores the specified string
      representation without Double conversion).
      Suitable for scenarios that require precise control over the TOML output format, such as
      retaining "6.626e-34", "inf", and "nan".
      @param RawValue The raw text, which must be a valid TOML floating-point number representation.
      @returns True: If the write is successful，False: If the key already exists and Overwrite=False }
    function SetFloatValue(const Key: string; const RawValue: string; Overwrite: Boolean = True): Boolean;

    { Write Boolean value }
    function SetBool(const Key: string; const Value: Boolean; Overwrite: Boolean = True): Boolean;

    { Write DateTime value }
    function SetDateTime(const Key: string; const Value: TDateTime; Overwrite: Boolean = True): Boolean;

    { Write the raw text of the date and time (directly store the specified string representation
      without TDateTime conversion).
      The original text must conform to the TOML 1.1.0 specification
      and supports the following four formats (Seconds can be omitted):
        "1979-05-27T07:32:00Z"          Date and time with time zone offset
        "1979-05-27T07:32:00.999999"    Local date and time (including decimal seconds)
        "1979-05-27"                    Local date
        "07:32:00"                      Local time
      Returns False if the format is invalid.
      @param RawValue: The original text must be a valid TOML date and time literal.
      @returns True: If successful write; False: If the format is invalid or the key already exists and Overwrite=False }
    function SetDateTimeValue(const Key: string; const RawValue: string; Overwrite: Boolean = True): Boolean;

    { Write to an array (ownership is transferred on success, and the caller retains ownership on failure).
      @returns True: If successful write; False: If the key already exists and Overwrite=False }
    function SetArray(const Key: string; Value: TTOMLArray; Overwrite: Boolean = True): Boolean;

    { Write to the sub-table (ownership transferred on success, ownership retained by the caller on failure) }
    function SetTable(const Key: string; Value: TTOMLTable; Overwrite: Boolean = True): Boolean;

    { ===== Chained write (Builder pattern) ===== }

    { Chained writing of strings, returning Self to support consecutive calls. }
    function Put(const Key: string; const Value: string; Overwrite: Boolean = True): TTOMLTable; overload;
    function Put(const Key: string; const Value: Int64; Overwrite: Boolean = True): TTOMLTable; overload;
    function Put(const Key: string; const Value: Integer; Overwrite: Boolean = True): TTOMLTable; overload;
    function Put(const Key: string; const Value: Double; Overwrite: Boolean = True): TTOMLTable; overload;
    function Put(const Key: string; const Value: Boolean; Overwrite: Boolean = True): TTOMLTable; overload;
    function Put(const Key: string; const Value: TDateTime; Overwrite: Boolean = True): TTOMLTable; overload;
    function Put(const Key: string; Value: TTOMLArray; Overwrite: Boolean = True): TTOMLTable; overload;
    function Put(const Key: string; Value: TTOMLTable; Overwrite: Boolean = True): TTOMLTable; overload;

    { ===== File operations ===== }

    { Load TOML data from a file into this table.
      @param ClearExisting: If True, the current content will be cleared first.
      @returns}
    function LoadFromFile(const FileName: string; ClearExisting: Boolean = True): Boolean;

    { Load TOML data from a string into this table.
      @param ClearExisting: If True, the current content will be cleared first.
      @returns True }
    function LoadFromString(const ATOML: string; ClearExisting: Boolean = True): Boolean;

    { Serialize this table and save it to a file.
      @param WriteBOM: Whether to write to a UTF-8 BOM
      @returns }
    function SaveToFile(const FileName: string; WriteBOM: Boolean = True): Boolean;

    { ===== Serialization ===== }

    { Serialize this table into a TOML string; return an empty string on error. }
    function toString: string; reintroduce;

    { ===== Tools and methods ===== }

    { Delete specified key
      @param FreeValue: When True, the corresponding value object is also released.
      @returns: True: If the key exists and has been deleted; False: If the key does not exist. }
    function Remove(const Key: string; FreeValue: Boolean = True): Boolean;

    { Clear all key-value pairs in the table
      @param FreeValues: When True, all value objects are released simultaneously. }
    procedure Clear(FreeValues: Boolean = True);

    { Return the number of key-value pairs in the table. }
    function Count: Integer;

    { Deep clone this table (achieved through serialization and then parsing; returns nil on error). }
    function Clone: TTOMLTable;

    { ===== TOML and JSON conversion ===== }

    { Serialize this table into a JSON string.
      @param APretty: Output beautiful format with indentation when true (default True)
      @param AIndentSize: Number of spaces per indentation level (default 2)
      @returns JSON string; returns an empty string on error. }
    function ToJSON(APretty: Boolean = True; AIndentSize: Integer = 2): string;

    { Load data from a JSON string (overwriting the current content).
      @param AJSON              Valid JSON object string
      @param ANullAsEmptyString When True, writes an empty string to the JSON null value.
                                Ignore null keys when set to False (default is False)
      @returns }
    function LoadFromJSON(const AJSON: string; ANullAsEmptyString: Boolean = False): Boolean;

    { Serialize this table into JSON and write it to a file.
      @param FileName    Target file path
      @param APretty     Whether to perform aesthetic indentation
      @param ABOM        Whether to write a UTF-8 BOM (JSON files usually do not include a BOM)
      @returns }
    function SaveToJSONFile(const FileName: string; APretty: Boolean = True; ABOM: Boolean = False): Boolean;

    { Load data from a JSON file (overwriting current content)
      @param FileName           Source JSON file path
      @param ANullAsEmptyString null handling strategy (same as LoadFromJSON)
      @returns }
    function LoadFromJSONFile(const FileName: string; ANullAsEmptyString: Boolean = False): Boolean;
  end;

  { TOML Array Helper – Adds convenient read and write operations to TTOMLArray }
  TTOMLArrayHelper = class helper for TTOMLArray
  public

    { ===== Read method ===== }

    function GetStr(Index: Integer; const DefaultValue: string = ''): string;
    function GetInt(Index: Integer; const DefaultValue: Int64 = 0): Int64;
    function GetFloat(Index: Integer; const DefaultValue: Double = 0.0): Double;

    { Get the raw text of floating-point numbers
      (preserving the exact representation in the TOML file)
      @param DefaultValue: The default value is returned
       when the index is out of bounds or the element
       is not a floating-point type. }
    function GetFloatValue(Index: Integer; const DefaultValue: string = ''): string;

    function GetBool(Index: Integer; const DefaultValue: Boolean = False): Boolean;
    function GetDateTime(Index: Integer; const DefaultValue: TDateTime = 0): TDateTime;
    function GetDateTimeValue(Index: Integer; const DefaultValue: string = ''): string;
    { Retrieves the table element at the specified index;
      returns nil if the element does not exist or its type does not match. }
    function GetTable(Index: Integer): TTOMLTable;

    { Iterate through all table-type elements in the array
      @param Proc: Anonymous procedure performed for each TTOMLTable }
    procedure ForEachTable(Proc: TProc<TTOMLTable>);

    { == Add method (returns Self, supports chaining, returns nil on error) == }

    function AddStr(const Value: string): TTOMLArray;
    function AddInt(const Value: Int64): TTOMLArray;
    function AddFloat(const Value: Double): TTOMLArray;

    { Add raw text to floating-point numbers
      (directly store the specified string representation,
       suitable for precision-sensitive or special value scenarios).
      @param RawValue: The original text must be a valid TOML floating-point
       representation (such as "6.626e-34", "inf"). }
    function AddFloatValue(const RawValue: string): TTOMLArray;

    function AddBool(const Value: Boolean): TTOMLArray;
    function AddDateTime(const Value: TDateTime): TTOMLArray;

    { Add raw text of date and time
     (directly store the specified string representation,
      with the same formatting rules as SetDateTimeValue).
      Returning nil when the format is invalid allows
      the caller to determine whether the call was successful. }
    function AddDateTimeValue(const RawValue: string): TTOMLArray;

    { Add table element (transfer ownership)
      @note If nil is returned, the caller retains ownership of Value
       and must release it manually. }
    function AddTable(Value: TTOMLTable): TTOMLArray;

    { Add nested array elements (transfer ownership) }
    function AddArray(Value: TTOMLArray): TTOMLArray;

    { ===== Serialization ===== }

    { Serialize this array into a TOML string; return an empty string on error.}
    function toString: string; reintroduce;

    { ===== Tool methods ===== }

    { Empty all elements in the array
      @param FreeItems: True to release all element objects at the same time }
    procedure Clear(FreeItems: Boolean = True);

    { Delete elements at the specified index
      @param FreeItem When True, the deleted element objects are also released.
      @returns }
    function RemoveAt(Index: Integer; FreeItem: Boolean = True): Boolean;

    { Securely retrieve the element at the specified index
      @param Value: Output parameters, return the corresponding element on success.
      @returns }
    function TryGetItem(Index: Integer; out Value: TTOMLValue): Boolean;
  end;

{ ===== Global factory function ===== }

{ Create an empty TOML table }
function NewTable: TTOMLTable;

{ Create an empty TOML array }
function NewArray: TTOMLArray;

{ Load TOML from file, return nil when error occurs (no exception thrown) }
function LoadTOML(const FileName: string): TTOMLTable;

{ Parse TOML from string, return nil on error (no exception thrown) }
function ParseTOML(const ATOML: string): TTOMLTable;

{ Parsing TOML from a string
  @param Config: Returns the parsing result on success, and nil on failure.
  @returns }
function TryParseTOML(const ATOML: string; out Config: TTOMLTable): Boolean;

{ == Path helper functions (for internal use, but can also be called externally). == }

{ Split the dot path with quotation marks and correctly handle the dots
  within the quotation marks
  Example：site."tt.com".owner -> ["site", "tt.com", "owner"] }
function SplitPath(const Path: string): TArray<string>;

{ Navigate to the target table along the dotted path;
  return nil if the table does not exist. }
function NavigateToTable(Root: TTOMLTable; const Path: string): TTOMLTable;

{ Retrieve the value along the dotted path;
  return nil if the value does not exist. }
function GetValueFromPath(Root: TTOMLTable; const Path: string): TTOMLValue;

implementation

uses
  StrUtils, Math;

{ ===== Global factory function implementation ===== }

function NewTable: TTOMLTable;
begin
  Result := TTOMLTable.Create;
end;

function NewArray: TTOMLArray;
begin
  Result := TTOMLArray.Create;
end;

function LoadTOML(const FileName: string): TTOMLTable;
begin
  try
    Result := TOML.Parser.ParseTOMLFile(FileName);
  except
    Result := nil;
  end;
end;

function ParseTOML(const ATOML: string): TTOMLTable;
begin
  try
    Result := TOML.Parser.ParseTOMLString(ATOML);
  except
    Result := nil;
  end;
end;

function TryParseTOML(const ATOML: string; out Config: TTOMLTable): Boolean;
begin
  try
    Config := TOML.Parser.ParseTOMLString(ATOML);
    Result := Assigned(Config);
  except
    Config := nil;
    Result := False;
  end;
end;

{ ===== Path helper function implementation ===== }

function SplitPath(const Path: string): TArray<string>;
var
  Parts: TList<string>;
  Current: string;
  i: Integer;
  InBasic, InLiteral: Boolean;
  Ch: Char;
begin
  { Split dotted paths and correctly handle segments enclosed
    in double and single quotes.
    The quotation mark character itself is not included in the output segment.
    Example：site."tt.com".owner -> ["site", "tt.com", "owner"] }
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
        Continue; // Do not add quotation marks to the current paragraph
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

  // An empty path directly returns the root table.
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

{ ===== Write path helper functions (for internal use) ===== }

{ Navigate along Parts[0..High-1] (non-existent intermediate
  levels are automatically created as tables).
  Then write NewValue at Parts[High].
  Returns True on success; on failure,
  NewValue is not released and is handled by the caller. }
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

{ ===== TTOMLTableHelper —— Read method implementation ===== }

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
  Pair: TPair<string, TTOMLValue>;
  SubTable: TTOMLTable;
  SubKeys: TStringList;
  i: Integer;
begin
  if not Assigned(Keys) then
    Exit;
  try
    Keys.Clear;
    for Pair in Self.Items do
    begin
      Keys.Add(Pair.Key);
      if Recursive and (Pair.Value is TTOMLTable) then
      begin
        SubTable := TTOMLTable(Pair.Value);
        SubKeys := TStringList.Create;
        try
          SubTable.GetKeys(SubKeys, True);
          for i := 0 to SubKeys.Count - 1 do
            Keys.Add(Pair.Key + '.' + SubKeys[i]);
        finally
          SubKeys.Free;
        end;
      end;
    end;
  except
    // Silent failure, maintaining interface robustness
  end;
end;

function TTOMLTableHelper.Clone: TTOMLTable;
var
  ATOML: string;
begin
  // Deep cloning achieved through serialization and re-parsing.
  try
    ATOML := Self.ToString;
    Result := ParseTOML(ATOML);
  except
    Result := nil;
  end;
end;

{ ===== TTOMLTableHelper —— Write method implementation ===== }

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
  { Parse the original text into a Double while preserving the original text.
    This ensures that the format in RawValue is accurately restored during serialization.
    Special values ​​inf / +inf / -inf / nan are handled according to TOML specifications. }
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
  { The original text is wrapped into complete TOML lines,
    and the Parser is delegated to perform format validation and parsing.
    At the same time, retain the RawString to ensure that it is restored
    exactly as it was during serialization. }
  try
    Temp := ParseTOMLString('__dt__ = ' + RawValue);
    try
      if not Temp.TryGetValue('__dt__', RawVal) then
        raise ETOMLParserException.Create('SetDateTimeValue: parse returned no value');
      if not (RawVal is TTOMLDateTime) then
        raise ETOMLParserException.CreateFmt('SetDateTimeValue: "%s" is not a TOML datetime literal', [RawValue]);

      NewValue := TTOMLDateTime.Create(TTOMLDateTime(RawVal).Value, RawValue,
        TTOMLDateTime(RawVal).Kind, TTOMLDateTime(RawVal).TimeZoneOffset);
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

{ ===== TTOMLTableHelper —— Builder pattern implementation ===== }

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

{ ===== TTOMLTableHelper —— File operation implementation ===== }

function TTOMLTableHelper.LoadFromFile(const FileName: string; ClearExisting: Boolean): Boolean;
var
  LoadedTable: TTOMLTable;
  Pair: TPair<string, TTOMLValue>;
begin
  Result := False;
  try
    LoadedTable := TOML.Parser.ParseTOMLFile(FileName);
    if not Assigned(LoadedTable) then
      Exit;
    try
      if ClearExisting then
        Self.Clear(True);
      for Pair in LoadedTable.Items do
        Self.Items.Add(Pair.Key, Pair.Value);
      LoadedTable.Items.Clear;
      Result := True;
    finally
      LoadedTable.Free;
    end;
  except
    Result := False;
  end;
end;

function TTOMLTableHelper.LoadFromString(const ATOML: string; ClearExisting: Boolean): Boolean;
var
  LoadedTable: TTOMLTable;
  Pair: TPair<string, TTOMLValue>;
begin
  Result := False;
  try
    LoadedTable := TOML.Parser.ParseTOMLString(ATOML);
    if not Assigned(LoadedTable) then
      Exit;
    try
      if ClearExisting then
        Self.Clear(True);
      for Pair in LoadedTable.Items do
        Self.Items.Add(Pair.Key, Pair.Value);
      LoadedTable.Items.Clear;
      Result := True;
    finally
      LoadedTable.Free;
    end;
  except
    Result := False;
  end;
end;

function TTOMLTableHelper.SaveToFile(const FileName: string; WriteBOM: Boolean): Boolean;
begin
  try
    Result := TOML.Serializer.SerializeTOMLToFile(Self, FileName, WriteBOM);
  except
    Result := False;
  end;
end;

{ ===== TTOMLTableHelper —— Serialization implementation ===== }

function TTOMLTableHelper.toString: string;
begin
  try
    Result := TOML.Serializer.SerializeTOML(Self);
  except
    Result := '';
  end;
end;

{ ===== TTOMLTableHelper —— Tool method implementation ===== }

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
  Value: TTOMLValue;
begin
  try
    if FreeValues then
      for Value in Self.Items.Values do
        if Assigned(Value) then
          Value.Free;
    Self.Items.Clear;
  except
    // Silence on failure
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

{ ===== TTOMLArrayHelper —— Read method implementation ===== }

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
          Result := Item.AsInteger // Allow implicit integer conversion
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

function TTOMLArrayHelper.GetDateTime(Index: Integer; const DefaultValue: TDateTime = 0): TDateTime;
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


function TTOMLArrayHelper.GetDateTimeValue(Index: Integer; const DefaultValue: string = ''): string;
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
    // Silence on failure
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

{ ===== TTOMLArrayHelper —— Add method implementation ===== }

function TTOMLArrayHelper.AddStr(const Value: string): TTOMLArray;
var
  NewValue: TTOMLString;
begin
  Result := Self;
  try
    NewValue := TTOMLString.Create(Value);
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

function TTOMLArrayHelper.AddInt(const Value: Int64): TTOMLArray;
var
  NewValue: TTOMLInteger;
begin
  Result := Self;
  try
    NewValue := TTOMLInteger.Create(Value);
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

function TTOMLArrayHelper.AddFloat(const Value: Double): TTOMLArray;
var
  NewValue: TTOMLFloat;
begin
  Result := Self;
  try
    NewValue := TTOMLFloat.Create(Value);
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

function TTOMLArrayHelper.AddFloatValue(const RawValue: string): TTOMLArray;
var
  NewValue: TTOMLFloat;
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

    NewValue := TTOMLFloat.Create(F, RawValue);
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

function TTOMLArrayHelper.AddBool(const Value: Boolean): TTOMLArray;
var
  NewValue: TTOMLBoolean;
begin
  Result := Self;
  try
    NewValue := TTOMLBoolean.Create(Value);
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

function TTOMLArrayHelper.AddDateTime(const Value: TDateTime): TTOMLArray;
var
  NewValue: TTOMLDateTime;
begin
  Result := Self;
  try
    NewValue := TTOMLDateTime.Create(Value);
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

function TTOMLArrayHelper.AddDateTimeValue(const RawValue: string): TTOMLArray;
var
  Temp: TTOMLTable;
  RawVal: TTOMLValue;
  NewValue: TTOMLDateTime;
begin
  Result := Self;
  try
    Temp := ParseTOMLString('__dt__ = ' + RawValue);
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

{ ===== TTOMLArrayHelper —— Serialization implementation ===== }

function TTOMLArrayHelper.toString: string;
begin
  try
    Result := TOML.Serializer.SerializeTOML(Self);
  except
    Result := '';
  end;
end;

{ ===== TTOMLArrayHelper —— Tool method implementation ===== }

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
    // Silence on failure
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

{ ===== TTOMLTableHelper：Implement the interconversion method with JSON ===== }

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
  Pair: TPair<string, TTOMLValue>;
begin
  Result := False;
  try
    Parsed := JSONToTOML(AJSON, ANullAsEmptyString);
    try
      Self.Clear(True);
      for Pair in Parsed.Items do
        Self.Add(Pair.Key, Pair.Value);
      Parsed.Items.Clear;
    finally
      Parsed.Free;
    end;
    Result := True;
  except
    // Return False if an error occurs，Self has been cleared, so it remains an empty table.
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
    // Return False if an error occurs
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
    // Return False if an error occurs
  end;
end;

end.
