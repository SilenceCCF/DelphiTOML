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
    FWrapWidth: Integer;              // Max column width for multi-line string wrapping (0 = disabled)

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

    { Writes a TOML multi-line basic string using triple-quote syntax
      @param AValue The string to write (may contain newlines)
      @param AKeyWidth Width of "key = " prefix for alignment purposes
      Used when FWrapWidth > 0 and the string contains newlines or is long }
    procedure WriteMultiLineString(const AValue: string; AKeyWidth: Integer);

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
      @param AWrapWidth Maximum column width for wrapping long strings and multi-line
             strings. Strings containing newlines are always written as multi-line
             basic strings ("""). Long strings without newlines are wrapped using a
             line-ending backslash continuation. Pass 0 (default) to disable wrapping.
      @returns The serialized TOML string
      @raises ETOMLSerializerException if value cannot be serialized }
    function Serialize(const AValue: TTOMLValue; AWrapWidth: Integer = 0): string;
  end;

{ Serializes a TOML value to string format
  @param AValue The value to serialize
  @param AWrapWidth Maximum column width for wrapping. Strings with embedded
         newlines become multi-line basic strings ("""). Long strings are wrapped
         with a line-ending backslash. 0 = disabled (default).
  @returns The serialized TOML string
  @raises ETOMLSerializerException if value cannot be serialized }
function SerializeTOML(const AValue: TTOMLValue; AWrapWidth: Integer = 0): string;

{ Serializes a TOML value to a file
  @param AValue The value to serialize
  @param AFileName The output file path
  @param BOM Whether to write a UTF-8 BOM (default True)
  @param AWrapWidth Maximum column width for wrapping (0 = disabled, default)
  @returns True if successful, False otherwise
  @raises ETOMLSerializerException if value cannot be serialized
  @raises EFileStreamError if file cannot be written }
function SerializeTOMLToFile(const AValue: TTOMLValue; const AFileName: string; BOM: Boolean = True;
  AWrapWidth: Integer = 0): Boolean;

implementation
{$IF CompilerVersion < 20.0}

function CharInSet(C: Char; const CharSet: TSysCharSet): Boolean;
begin
  Result := C in CharSet;
end;
{$IFEND}

function SerializeTOML(const AValue: TTOMLValue; AWrapWidth: Integer = 0): string;
var
  Serializer: TTOMLSerializer;
begin
  Serializer := TTOMLSerializer.Create;
  try
    Result := Serializer.Serialize(AValue, AWrapWidth);
  finally
    Serializer.Free;
  end;
end;

function SerializeTOMLToFile(const AValue: TTOMLValue; const AFileName: string; BOM: Boolean = True;
  AWrapWidth: Integer = 0): Boolean;
var
  TOML: string;
begin
  Result := False;
  try
    TOML := SerializeTOML(AValue, AWrapWidth);
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
var
  SavedWrapWidth: Integer;
begin
  // Single key segment: When it contains special characters
  // (including periods), it must be enclosed in quotation marks.
  // Keys must always use basic single-line strings — disable wrap mode
  // temporarily so WriteString never emits a multi-line string for a key.
  if NeedsQuoting(AKey) then
  begin
    SavedWrapWidth := FWrapWidth;
    FWrapWidth := 0;
    try
      WriteString(AKey);
    finally
      FWrapWidth := SavedWrapWidth;
    end;
  end
  else
    FStringBuilder.Append(AKey);
end;

procedure TTOMLSerializer.WriteString(const AValue: string);
var
  i, Code: Integer;
  C: Char;
  HasNewline: Boolean;
  EscLen: Integer;
begin
  // When wrapping is enabled, check whether the string needs multi-line output:
  //   (a) contains embedded newlines, or
  //   (b) its escaped representation (including the surrounding quotes and the
  //       "key = " prefix that was already written) would exceed FWrapWidth.
  // Multi-line strings are only valid at the top-level key-value position
  // (FWrapWidth is set to 0 inside arrays and inline tables by their writers).
  if (FWrapWidth > 0) then
  begin
    HasNewline := False;
    EscLen := 2; // opening + closing quote
    for i := 1 to Length(AValue) do
    begin
      C := AValue[i];
      if (C = #10) or (C = #13) then
        HasNewline := True;
      // Tally the escaped length so we can decide whether to wrap.
      case C of
        #8, #9, #10, #12, #13, '"', '\':
          Inc(EscLen, 2);           // two-char escape sequence
      else
        if (Ord(C) <= 31) or (Ord(C) = 127) then
          Inc(EscLen, 6)            // \uXXXX
        else
          Inc(EscLen, 1);
      end;
    end;

    // Use multi-line form when the string has real newlines, or when the
    // fully-escaped single-line form (including the indent already in the
    // buffer for this line) would be longer than FWrapWidth.
    if HasNewline or (EscLen > FWrapWidth) then
    begin
      WriteMultiLineString(AValue, 0);
      Exit;
    end;
  end;

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

procedure TTOMLSerializer.WriteMultiLineString(const AValue: string; AKeyWidth: Integer);
{ Writes a TOML multi-line basic string (""" ... """).
  Strategy:
    1. Split the value on LF / CR+LF boundaries into logical lines.
    2. Each logical line is tokenised into alternating whitespace / word runs.
       All characters are escaped at tokenisation time so that column counting
       is done on the final output width, not the raw input width.
    3. When FWrapWidth > 0 the tokens are emitted greedily:
         - Spaces before a word that would overflow are replaced by a TOML
           line-ending backslash continuation (\ + newline) so the break always
           falls between words, never inside a word.
         - A single word that is longer than FWrapWidth is emitted as-is on its
           own line (cannot be broken further without changing the string value).
  The opening """ is emitted on the same line as the key (key = """\n) and the
  closing """ appears on its own indented line.
}
type
  TToken = record
    Text: string;
    IsSpace: Boolean;
  end;
var
  Lines: TStringList;
  Tokens: array of TToken;
  LineIdx: Integer;
  CharIdx: Integer;
  TokIdx: Integer;
  C: Char;
  Line: string;
  Indent: string;
  Col: Integer;
  TokenStr: string;
  IsSpace: Boolean;
  CurIsSpace: Boolean;
  NextWordLen: Integer;
  LookIdx: Integer;

  { Escape a single character for use inside a multi-line basic string.
    Real newlines are handled at the line-splitting level so we never
    emit \n or \r here. }

  function EscapeChar(Ch: Char): string;
  var
    Cd: Integer;
  begin
    Cd := Ord(Ch);
    case Ch of
      #8:
        Result := '\b';
      #9:
        Result := '\t';
      #12:
        Result := '\f';
      '\':
        Result := '\\';
    else
      if (Cd <= 31) or (Cd = 127) then
        Result := Format('\u%.4x', [Cd])
      else
        Result := Ch;
    end;
  end;

begin
  // Indentation for content lines (matches the current block-table indent level).
  Indent := StringOfChar(' ', FIndentLevel * 2);

  // Opening delimiter on the same line as "key = ".
  FStringBuilder.AppendLine('"""');

  Lines := TStringList.Create;
  try
    Lines.Text := AValue; // Splits on CR, LF, CR+LF automatically.

    for LineIdx := 0 to Lines.Count - 1 do
    begin
      Line := Lines[LineIdx];

      // ---------------------------------------------------------------
      // Phase 1: tokenise the logical line into (space | word) runs.
      //   We escape every character immediately so that Length(Token.Text)
      //   equals the number of output columns the token will occupy.
      // ---------------------------------------------------------------
      SetLength(Tokens, 0);
      CharIdx := 1;
      while CharIdx <= Length(Line) do
      begin
        C := Line[CharIdx];
        IsSpace := (C = ' ') or (C = #9);

        TokenStr := '';
        while CharIdx <= Length(Line) do
        begin
          C := Line[CharIdx];
          CurIsSpace := (C = ' ') or (C = #9);
          if CurIsSpace <> IsSpace then
            Break;

          if C = '"' then
          begin
            // Escape the first quote in any run of >= 2 consecutive quotes to
            // prevent an accidental """ closing delimiter.
            if (CharIdx < Length(Line)) and (Line[CharIdx + 1] = '"') then
              TokenStr := TokenStr + '\"'
            else
              TokenStr := TokenStr + '"';
          end
          else
            TokenStr := TokenStr + EscapeChar(C);

          Inc(CharIdx);
        end;

        SetLength(Tokens, Length(Tokens) + 1);
        Tokens[High(Tokens)].Text := TokenStr;
        Tokens[High(Tokens)].IsSpace := IsSpace;
      end;

      // ---------------------------------------------------------------
      // Phase 2: emit tokens, breaking at word boundaries when wrapping.
      // ---------------------------------------------------------------
      FStringBuilder.Append(Indent);
      Col := Length(Indent);
      TokIdx := 0;

      while TokIdx <= High(Tokens) do
      begin
        TokenStr := Tokens[TokIdx].Text;
        IsSpace := Tokens[TokIdx].IsSpace;

        if IsSpace then
        begin
          // Peek ahead: if there is a following word token, decide whether
          // the word after this space would overflow the wrap width.
          // If so, emit the space first (it is part of the string value and
          // must be preserved), then emit the line-ending backslash so the
          // parser skips the newline and the indent on the next line.
          if (FWrapWidth > 0) and (TokIdx + 1 <= High(Tokens)) then
          begin
            NextWordLen := 0;
            LookIdx := TokIdx + 1;
            while (LookIdx <= High(Tokens)) and Tokens[LookIdx].IsSpace do
              Inc(LookIdx);
            if LookIdx <= High(Tokens) then
              NextWordLen := Length(Tokens[LookIdx].Text);

            if Col + Length(TokenStr) + NextWordLen > FWrapWidth then
            begin
              // Output the space BEFORE the backslash so it is not swallowed
              // by the TOML line-ending-backslash whitespace-trim rule.
              FStringBuilder.Append(TokenStr);
              FStringBuilder.AppendLine('\');
              FStringBuilder.Append(Indent);
              Col := Length(Indent);
              Inc(TokIdx);
              // Skip any additional space tokens that would become unwanted
              // leading spaces on the continuation line.
              while (TokIdx <= High(Tokens)) and Tokens[TokIdx].IsSpace do
                Inc(TokIdx);
              Continue;
            end;
          end;

          // Space fits (or no following word): emit it normally.
          // Trailing spaces are kept as-is because they are part of the
          // string value; omitting them would silently alter the data.
          FStringBuilder.Append(TokenStr);
          Inc(Col, Length(TokenStr));
        end
        else
        begin
          // Word token.
          if (FWrapWidth > 0) and (Col + Length(TokenStr) > FWrapWidth) and (Col > Length(Indent)) then
          begin
            // The word doesn't fit and is not the first thing on this output
            // line.  Break before it.  (If it IS first, emit it anyway — we
            // cannot split a single word without altering the string value.)
            FStringBuilder.AppendLine('\');
            FStringBuilder.Append(Indent);
            Col := Length(Indent);
          end;
          FStringBuilder.Append(TokenStr);
          Inc(Col, Length(TokenStr));
        end;

        Inc(TokIdx);
      end;

      // End of logical line: emit a real newline.
      FStringBuilder.AppendLine('');
    end;
  finally
    Lines.Free;
  end;

  // Closing delimiter on its own indented line.
  FStringBuilder.Append(Indent);
  FStringBuilder.Append('"""');
  // Caller (WriteTable) will append the trailing newline via WriteLine.
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
  SavedWrapWidth: Integer;
begin
  // TOML spec: multi-line basic strings are NOT allowed inside arrays.
  // Disable wrapping for the duration of this array.
  SavedWrapWidth := FWrapWidth;
  FWrapWidth := 0;
  try
    FStringBuilder.Append('[');
    for i := 0 to AArray.Count - 1 do
    begin
      if i > 0 then
        FStringBuilder.Append(', ');
      WriteValue(AArray.GetItem(i));
    end;
    FStringBuilder.Append(']');
  finally
    FWrapWidth := SavedWrapWidth;
  end;
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
  SavedWrapWidth: Integer;
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
    // TOML spec: multi-line strings are not allowed inside inline tables.
    FStringBuilder.Append('{');
    First := True;
    SavedWrapWidth := FWrapWidth;
    FWrapWidth := 0;
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
      FWrapWidth := SavedWrapWidth;
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
          // When wrapping is enabled, emit string values as multi-line basic
          // strings (""") when they either:
          //   (a) contain embedded newlines, or
          //   (b) their escaped single-line form would exceed FWrapWidth.
          // WriteString handles the same check internally, but we need to call
          // WriteMultiLineString directly here so WriteIndent is issued first
          // and the key prefix is written before the opening """.
          if (FWrapWidth > 0) and (V.ValueType = tvtString) then
          begin
            WriteIndent;
            WriteKey(K);
            FStringBuilder.Append(' = ');
            // WriteString will detect newlines / oversized length and call
            // WriteMultiLineString automatically; we just invoke it uniformly.
            WriteString(V.AsString);
            WriteLine;
          end
          else
          begin
            WriteKey(K);
            FStringBuilder.Append(' = ');
            WriteValue(V);
            WriteLine;
          end;
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

function TTOMLSerializer.Serialize(const AValue: TTOMLValue; AWrapWidth: Integer = 0): string;
begin
  FStringBuilder.Clear;
  FCurrentPath.Clear;
  FWrapWidth := AWrapWidth;

  if AValue.ValueType = tvtTable then
    WriteTable(AValue.AsTable, False)
  else
    WriteValue(AValue);

  Result := FStringBuilder.ToString;
end;

end.
