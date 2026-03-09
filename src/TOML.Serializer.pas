(* TOML.Serializer.pas
   TOML data structure serialization unit.
   This unit converts TOML objects into text format conforming to the TOML v1.1.0 specification, supporting:
    - Key-value pairs (including keys with automatic quotation marks and escaping)
    - Normal table [table] and array table [[array]]
    - 内联表 { key = value, ... }
    - Array [...]
    - Base strings (with escapes)
    - Integers and floating-point numbers (including inf/nan, preserving original precision)）
    - Boolean
    - Date and time (RFC 3339, raw text preferred)
  Key features:
    - Efficient string building using TStringBuilder
    - Sort the table keys before traversing to ensure a definite output order.
    - Key-value pairs are output before sublists and arrays (compliant with TOML specifications)
    - The path of each segment is traced via FCurrentPath, used to generate the [abc] header.
*)
unit TOML.Serializer;

interface

uses
  SysUtils, Classes, Math, TOML.Types, Generics.Collections;
{$IF CompilerVersion < 20.0}
function CharInSet(C: Char; const CharSet: TSysCharSet): Boolean; inline;
{$IFEND}

type
  { Key-Value pair type for TOML tables }
  TTOMLKeyValuePair = TPair<string, TTOMLValue>;
  { TOML serializer class that converts TOML data to text format
    This class handles the conversion of TOML data structures into properly
    formatted TOML text, following the TOML v1.0.0 specification }
  TTOMLSerializer = class
  private
    FStringBuilder: TStringBuilder;   // StringBuilder for efficient string building
    FIndentLevel: Integer;            // Current indentation level
    FCurrentPath: TStringList;        // Tracks current table path for proper nesting
    FFormatSettings: TFormatSettings; // Invariant formatting (decimal point is '.', unaffected by localization)

    { Writes indentation at current level
      Used to maintain consistent formatting }
    procedure WriteIndent;

    { Writes a line with optional content and newline
      @param ALine Optional string content to write }
    procedure WriteLine(const ALine: string = '');

    { Writes a TOML key with proper quoting
      @param AKey The key to write
      Handles escaping and quoting of keys as needed }
    procedure WriteKey(const AKey: string);

    { Writes a TOML string value with proper escaping
      @param AValue The string to write
      Handles all required string escaping per TOML spec }
    procedure WriteString(const AValue: string);

    { Writes any TOML value based on its type
      @param AValue The value to write
      Dispatches to appropriate write method based on value type }
    procedure WriteValue(const AValue: TTOMLValue);

    { Writes a TOML table
      @param ATable The table to write
      @param AInline Whether to write as inline table
      Handles both standard and inline table formats }
    procedure WriteTable(const ATable: TTOMLTable; const AInline: Boolean = False);

    { Writes a TOML array
      @param AArray The array to write
      Handles arrays of any valid TOML type }
    procedure WriteArray(const AArray: TTOMLArray);

    { Write a TOML datetime value (preferably use raw text,
      otherwise output in Kind format). }
    procedure WriteDateTime(const ADateTimeValue: TTOMLValue);

    { Construct the current complete table path string, in the form of "ab\"cd\"".
      For use in the [path] or [[path]] header}
    function BuildTablePath(const NewKey: string): string;

    { Determine if a key name needs to be enclosed in quotes. (Keys containing
      only AZ, az, 0-9, _, and - do not need to be enclosed in quotes) }
    function NeedsQuoting(const AKey: string): Boolean;

  public
    { Creates a new TOML serializer instance }
    constructor Create;

    { Cleans up the serializer instance }
    destructor Destroy; override;

    { Serializes a TOML value to string format
      @param AValue The value to serialize
      @returns The serialized TOML string
      @raises ETOMLSerializerException if value cannot be serialized }
    function Serialize(const AValue: TTOMLValue): string;
  end;

{ Serializes a TOML value to string format
  @param AValue The value to serialize
  @returns The serialized TOML string
  @raises ETOMLSerializerException if value cannot be serialized }
function SerializeTOML(const AValue: TTOMLValue): string;

{ Serializes a TOML value to a file
  @param AValue The value to serialize
  @param AFileName The output file path
  @returns True if successful, False otherwise
  @raises ETOMLSerializerException if value cannot be serialized
  @raises EFileStreamError if file cannot be written }
function SerializeTOMLToFile(const AValue: TTOMLValue; const AFileName: string; BOM: Boolean = True): Boolean;

implementation
{$IF CompilerVersion < 20.0}

function CharInSet(C: Char; const CharSet: TSysCharSet): Boolean;
begin
  Result := C in CharSet;
end;
{$IFEND}


function SerializeTOML(const AValue: TTOMLValue): string;
var
  Serializer: TTOMLSerializer;
begin
  Serializer := TTOMLSerializer.Create;
  try
    Result := Serializer.Serialize(AValue);
  finally
    Serializer.Free;
  end;
end;

function SerializeTOMLToFile(const AValue: TTOMLValue; const AFileName: string; BOM: Boolean = True): Boolean;
var
  TOML: string;
begin
  Result := False;
  try
    TOML := SerializeTOML(AValue);
    with TStringList.Create do
    try
      Text := TOML;
      WriteBOM := BOM;
      SaveToFile(AFileName, TEncoding.UTF8);
      Result := True;
    finally
      Free;
    end;
  except
    // False
  end;
end;
{ TTOMLSerializer }

constructor TTOMLSerializer.Create;
begin
  inherited Create;
  FStringBuilder := TStringBuilder.Create;
  FIndentLevel := 0;
  FCurrentPath := TStringList.Create;
  FCurrentPath.Delimiter := '.';
  FCurrentPath.StrictDelimiter := True;

  // Use invariant formatting to ensure that the decimal point is always '.',
  // unaffected by system locale.
  {$IF CompilerVersion >= 22.0}
  FFormatSettings := TFormatSettings.Invariant;
  {$ELSE}
  GetLocaleFormatSettings(LOCALE_USER_DEFAULT, FFormatSettings);
  FFormatSettings.DecimalSeparator := '.';
  FFormatSettings.ThousandSeparator := #0;
  FFormatSettings.DateSeparator := '-';
  FFormatSettings.TimeSeparator := ':';
  {$IFEND}
end;

destructor TTOMLSerializer.Destroy;
begin
  FStringBuilder.Free;
  FCurrentPath.Free;
  inherited;
end;

procedure TTOMLSerializer.WriteIndent;
var
  i: Integer;
begin
  for i := 1 to FIndentLevel * 2 do
    FStringBuilder.Append(' ');
end;

procedure TTOMLSerializer.WriteLine(const ALine: string = '');
begin
  if ALine <> '' then
  begin
    WriteIndent;
    FStringBuilder.Append(ALine);
  end;
  FStringBuilder.AppendLine;
end;

function TTOMLSerializer.NeedsQuoting(const AKey: string): Boolean;
var
  i: Integer;
  C: Char;
begin
  // Spaces must be enclosed in quotes.
  if AKey = '' then
    Exit(True);

  // Keys containing only A-Z, az, 0-9, _, or - do not need to be enclosed in quotes.
  for i := 1 to Length(AKey) do
  begin
    C := AKey[i];
    if not (CharInSet(C, ['A'..'Z']) or CharInSet(C, ['a'..'z']) or CharInSet(C, ['0'..'9']) or (C = '_') or (C
      = '-')) then
      Exit(True);
  end;
  Result := False;
end;

function TTOMLSerializer.BuildTablePath(const NewKey: string): string;
var
  SB: TStringBuilder;
  i: Integer;
  { When appending a single path segment, enclose it in double quotes
    and escape it if it contains special characters. }

  procedure AppendSeg(const S: string);
  var
    j, Code: Integer;
  begin
    if NeedsQuoting(S) then
    begin
      SB.Append('"');
      for j := 1 to Length(S) do
      begin
        Code := Ord(S[j]);
        case S[j] of
          #8:
            SB.Append('\b');
          #9:
            SB.Append('\t');
          #10:
            SB.Append('\n');
          #12:
            SB.Append('\f');
          #13:
            SB.Append('\r');
          '"':
            SB.Append('\"');
          '\':
            SB.Append('\\');
        else
          // Escape all control characters (0x00-0x1F and 0x7F)
          if (Code <= 31) or (Code = 127) then
            SB.AppendFormat('\u%.4x', [Code])
          else
            SB.Append(S[j]);
        end;
      end;
      SB.Append('"');
    end
    else
      SB.Append(S);
  end;

begin
  SB := TStringBuilder.Create;
  try
    for i := 0 to FCurrentPath.Count - 1 do
    begin
      if i > 0 then
        SB.Append('.');
      AppendSeg(FCurrentPath[i]);
    end;
    if FCurrentPath.Count > 0 then
      SB.Append('.');
    AppendSeg(NewKey);
    Result := SB.ToString;
  finally
    SB.Free;
  end;
end;

procedure TTOMLSerializer.WriteKey(const AKey: string);
begin
  // Single key segment: When it contains special characters
  // (including periods), it must be enclosed in quotation marks.
  if NeedsQuoting(AKey) then
    WriteString(AKey)
  else
    FStringBuilder.Append(AKey);
end;

procedure TTOMLSerializer.WriteString(const AValue: string);
var
  i, Code: Integer;
  C: Char;
begin
  FStringBuilder.Append('"');
  for i := 1 to Length(AValue) do
  begin
    C := AValue[i];
    Code := Ord(C);
    case C of
      #8:
        FStringBuilder.Append('\b');  // Backspace
      #9:
        FStringBuilder.Append('\t');  // Tab
      #10:
        FStringBuilder.Append('\n');  // Line feed
      #12:
        FStringBuilder.Append('\f');  // Page break
      #13:
        FStringBuilder.Append('\r');  // Carriage return
      '"':
        FStringBuilder.Append('\"');  // Quote
      '\':
        FStringBuilder.Append('\\');  // Backslash
    else
      // Escape all control characters (0x00-0x1F and 0x7F)
      if (Code <= 31) or (Code = 127) then
        FStringBuilder.AppendFormat('\u%.4x', [Code])
      else
        FStringBuilder.Append(C);
    end;
  end;
  FStringBuilder.Append('"');
end;

procedure TTOMLSerializer.WriteDateTime(const ADateTimeValue: TTOMLValue);
var
  DateTimeVal: TTOMLDateTime;
  Str, FracStr: string;
  Hours, Minutes: Integer;
  Sign: Char;
  FracSec, FracPart: Double;
  SecInt: Integer;
  { Calculate and append decimal seconds (if any) }

  procedure AppendFractionalSeconds;
  begin
    FracSec := Frac(DateTimeVal.Value) * 24 * 3600;
    SecInt := Trunc(FracSec);
    FracPart := FracSec - SecInt;
    if FracPart > 0.0 then
    begin
      FracStr := FloatToStrF(FracPart, ffFixed, 15, 6, FFormatSettings);
      // Remove leading zeros, keep the decimal point and subsequent digits.
      if (Length(FracStr) > 2) and (FracStr[1] = '0') and (FracStr[2] = '.') then
        Delete(FracStr, 1, 1);
      Str := Str + FracStr;
    end;
  end;

begin
  if not (ADateTimeValue is TTOMLDateTime) then
    raise ETOMLSerializerException.Create('Invalid datetime value type');

  DateTimeVal := TTOMLDateTime(ADateTimeValue);

  // Use the original text first to ensure accurate formatting.
  if DateTimeVal.RawString <> '' then
  begin
    FStringBuilder.Append(DateTimeVal.RawString);
    Exit;
  end;

  // Generate text by date and time subtype
  case DateTimeVal.Kind of
    tdkLocalDate:
      // Local date：1979-05-27
      Str := FormatDateTime('yyyy-mm-dd', DateTimeVal.Value);

    tdkLocalTime:
      begin
        // Local time：07:32:00[.999999]
        Str := FormatDateTime('hh:nn:ss', DateTimeVal.Value);
        AppendFractionalSeconds;
      end;

    tdkLocalDateTime:
      begin
        // Local DateTime：1979-05-27T07:32:00[.999999]
        Str := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', DateTimeVal.Value);
        AppendFractionalSeconds;
      end;

    tdkOffsetDateTime:
      begin
        // Date and time with time zone offset: 1979-05-27T07:32:00[.999999]Z 或 +HH:MM / -HH:MM
        Str := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', DateTimeVal.Value);
        AppendFractionalSeconds;
        if DateTimeVal.TimeZoneOffset = 0 then
          Str := Str + 'Z'
        else
        begin
          Hours := Abs(DateTimeVal.TimeZoneOffset) div 60;
          Minutes := Abs(DateTimeVal.TimeZoneOffset) mod 60;
          if DateTimeVal.TimeZoneOffset < 0 then
            Sign := '-'
          else
            Sign := '+';
          Str := Str + Format('%s%.2d:%.2d', [Sign, Hours, Minutes]);
        end;
      end;
  end;

  FStringBuilder.Append(Str);
end;

procedure TTOMLSerializer.WriteArray(const AArray: TTOMLArray);
var
  i: Integer;
begin
  FStringBuilder.Append('[');
  for i := 0 to AArray.Count - 1 do
  begin
    if i > 0 then
      FStringBuilder.Append(', ');
    WriteValue(AArray.GetItem(i));
  end;
  FStringBuilder.Append(']');
end;

procedure TTOMLSerializer.WriteValue(const AValue: TTOMLValue);
var
  F: Double;
  S: string;
  CheckV: Double;
  Code: Integer;
begin
  case AValue.ValueType of
    tvtString:
      WriteString(AValue.AsString);

    tvtInteger:
      FStringBuilder.Append(IntToStr(AValue.AsInteger));

    tvtFloat:
      begin
        F := AValue.AsFloat;

        // Handling special floating-point values
        if IsNan(F) then
          S := 'nan'
        else if IsInfinite(F) then
        begin
          if F > 0 then
            S := 'inf'
          else
            S := '-inf';
        end
        else
        begin
          // Use the original text first (to preserve the precision during parsing)
          if (AValue is TTOMLFloat) and (TTOMLFloat(AValue).RawString <> '') then
            S := TTOMLFloat(AValue).RawString
          else
          begin
            // Intelligent precision: First try 15 bits,
            // then switch to 17 bits if the round trip is inconsistent.
            S := FloatToStrF(F, ffGeneral, 15, 0, FFormatSettings);
            Val(S, CheckV, Code);
            if (Code <> 0) or (CheckV <> F) then
              S := FloatToStrF(F, ffGeneral, 17, 0, FFormatSettings);
          end;

          // TOML specification: Floating-point literals must contain either '.' or 'e'.
          // If neither of these exists (e.g., for integer patterns), then add ".0".
          if (Pos('.', S) = 0) and (Pos('e', LowerCase(S)) = 0) then
            S := S + '.0';
        end;

        FStringBuilder.Append(S);
      end;

    tvtBoolean:
      if AValue.AsBoolean then
        FStringBuilder.Append('true')
      else
        FStringBuilder.Append('false');

    tvtDateTime:
      WriteDateTime(AValue);

    tvtArray:
      WriteArray(AValue.AsArray);

    tvtTable, tvtInlineTable:
      // Tables nested in value positions are always output in inline format.
      WriteTable(AValue.AsTable, True);
  end;
end;

procedure TTOMLSerializer.WriteTable(const ATable: TTOMLTable; const AInline: Boolean);
var
  First: Boolean;
  SubTable: TTOMLTable;
  i: Integer;
  ArrayValue: TTOMLArray;
  AllTables: Boolean;
  SortedKeys: TList<string>;
  K: string;
  V: TTOMLValue;
  { Determine if the value is an "array table" (an array where all elements are TVtTable) }

  function IsArrayOfTables(Val: TTOMLValue): Boolean;
  var
    Arr: TTOMLArray;
    j: Integer;
  begin
    Result := False;
    if Val.ValueType = tvtArray then
    begin
      Arr := Val.AsArray;
      if Arr.Count > 0 then
      begin
        Result := True;
        for j := 0 to Arr.Count - 1 do
          if Arr.GetItem(j).ValueType <> tvtTable then
          begin
            Result := False;
            Break;
          end;
      end;
    end;
  end;

begin
  if AInline then
  begin
    // ---- Inline table：{ key = value, ... } ----
    FStringBuilder.Append('{');
    First := True;
    SortedKeys := TList<string>.Create;
    try
      for K in ATable.Items.Keys do
        SortedKeys.Add(K);
      SortedKeys.Sort;
      for K in SortedKeys do
      begin
        V := ATable.Items[K];
        if not First then
          FStringBuilder.Append(', ')
        else
          First := False;
        WriteKey(K);
        FStringBuilder.Append(' = ');
        WriteValue(V);
      end;
    finally
      SortedKeys.Free;
    end;
    FStringBuilder.Append('}');
  end
  else
  begin
    // ---- Standard Block Table ----
    SortedKeys := TList<string>.Create;
    try
      for K in ATable.Items.Keys do
        SortedKeys.Add(K);
      SortedKeys.Sort;

      // Round 1: Output all ordinary key-value pairs (not sublists, not arrays).
      // The TOML specification requires that key-value pairs must appear
      // before the header of the sub-table.
      for K in SortedKeys do
      begin
        V := ATable.Items[K];
        if (V.ValueType <> tvtTable) and (not IsArrayOfTables(V)) then
        begin
          WriteKey(K);
          FStringBuilder.Append(' = ');
          WriteValue(V);
          WriteLine;
        end;
      end;

      // Second round: Output the array table [[key]] and the regular sub-table [key]
      for K in SortedKeys do
      begin
        V := ATable.Items[K];

        // Processing arrays [[key]]
        if (V.ValueType = tvtArray) and (V.AsArray.Count > 0) then
        begin
          ArrayValue := V.AsArray;
          AllTables := True;
          for i := 0 to ArrayValue.Count - 1 do
            if ArrayValue.GetItem(i).ValueType <> tvtTable then
            begin
              AllTables := False;
              Break;
            end;

          if AllTables then
          begin
            for i := 0 to ArrayValue.Count - 1 do
            begin
              WriteLine;
              WriteLine('[[' + BuildTablePath(K) + ']]');
              FCurrentPath.Add(K);
              WriteTable(ArrayValue.GetItem(i).AsTable);
              FCurrentPath.Delete(FCurrentPath.Count - 1);
            end;
            Continue;
          end;
        end;

        // Processing ordinary sub-tables [key]
        if V.ValueType = tvtTable then
        begin
          SubTable := V.AsTable;
          WriteLine;
          WriteLine('[' + BuildTablePath(K) + ']');
          if SubTable.Items.Count > 0 then
          begin
            FCurrentPath.Add(K);
            WriteTable(SubTable);
            FCurrentPath.Delete(FCurrentPath.Count - 1);
          end;
        end;
      end;
    finally
      SortedKeys.Free;
    end;
  end;
end;

function TTOMLSerializer.Serialize(const AValue: TTOMLValue): string;
begin
  FStringBuilder.Clear;
  FCurrentPath.Clear;

  if AValue.ValueType = tvtTable then
    WriteTable(AValue.AsTable, False)
  else
    WriteValue(AValue);

  Result := FStringBuilder.ToString;
end;

end.
