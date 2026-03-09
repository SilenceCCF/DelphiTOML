{ TOML.JSON.pas
  TOML ↔ JSON format conversion unit.
  Two sets of public functions are provided:
  TOML → JSON
  The TOMLToJSON(Table) method converts a TTOMLTable table into a JSON string.
  The `TOMLValueToJSON(Value)` method converts any `TOMLValue` string into a JSON string.
  TOMLFileToJSONFile(...) converts a TOML file to a JSON file and writes it to that file.
  JSON → TOML
  JSONToTOML(JSON) parses a JSON string into a TTOMLTable.
  The JSONToTOMLString(JSON) method converts a JSON string to a TOML format string.
  JSONFileToTOMLFile(...) converts a JSON file to a TOML file and writes it to a TOML file.
  Type mapping rules:
  TOML → JSON
  string → JSON string (including complete escaping, including surrogate pairs \uXXXX\uXXXX)
  integer → JSON number (integer, without decimal point)
  float → JSON number (preferably using raw text to ensure precision; inf/nan → null)
  boolean → JSON true / false
  datetime → JSON string (preserves the original RFC 3339 text)
  array → JSON array
  table → JSON object (preserves insertion order)
  inline table → JSON object (preserves insertion order)

  JSON → TOML
  string → TOML string
  Number → If it contains a decimal point or exponent, it is a float; otherwise, it is an integer.
  Degraded to float when outside the range of Int64
  true / false → TOML boolean
  null → Skip the key (TOML has no null concept);
  An empty string is written when ANullAsEmptyString=True.
  array → TOML array
  object → TOML table (key insertion order is consistent with JSON text)
  Implementation details:
  - It does not depend on any third-party libraries and includes a hand-written,
    lightweight JSON lexical and syntax parser.
  - Floating-point numbers are output first, using TTOMLFloat.RawString (raw text).
    In the absence of original text, round-trip accuracy is guaranteed with
    17 significant digits (IEEE 754 round-trip).
  - WriteObject preserves the insertion order of TTOMLTable.Items, without alphabetical sorting.
  - \uXXXX escaping correctly handles surrogate pairs of characters other than BMP.
  - In JSON to TOML, null values ​​(Val = nil) do not leak objects,
    as has been implemented in all branches. Safe handling.
}
unit TOML.JSON;

interface

uses
  SysUtils, Classes, Math, TOML.Types, TOML.Parser, TOML.Serializer, Generics.Collections;
{ ===== TOML → JSON ===== }

{ Serialize TTOMLTable into a JSON string
  @param Table: Source TOML table
  @param APretty: True outputs a nicely formatted layout with indentation (default is True).
  @param AIndentSize: The number of spaces per indentation level (default 2)
  @returns: JSON object string
  @raises ETOMLException: if the value cannot be converted }
function TOMLToJSON(const Table: TTOMLTable; APretty: Boolean = True; AIndentSize: Integer = 2): string;
{Serialize any TTOMLValue into a JSON string (for non-root table nodes) }
function TOMLValueToJSON(const Value: TTOMLValue; APretty: Boolean = True; AIndentSize: Integer = 2): string;
{ Read the TOML file and write the result to a JSON file.
  @param ATOMLFile: Enter the path to the TOML file.
  @param AJSONFile: Path to the output JSON file
  @param APretty: Whether to use aesthetically pleasing indentation (default is True)
  @param ABOM: Whether to write the UTF-8 BOM (default is False, JSON usually does not have a BOM)
  @returns True: if successful, False: if an error occurs.}
function TOMLFileToJSONFile(const ATOMLFile, AJSONFile: string; APretty: Boolean = True; ABOM: Boolean = False):
  Boolean;
{ ===== JSON → TOML ===== }

(* Parse the JSON string into TTOMLTable
  @param AJSON: JSON string (the root node must be an object { ... })
  @param ANullAsEmptyString: True converts JSON null to an empty string;
                             Ignore null keys when set to False (default is False)
  @returns: creates a new TTOMLTable (the caller is responsible for releasing it).
  @raises ETOMLParserException: if the JSON format is invalid or the root node is not an object. *)
function JSONToTOML(const AJSON: string; ANullAsEmptyString: Boolean = False): TTOMLTable;
{ Convert JSON string to TOML format string (convenient encapsulation) }
function JSONToTOMLString(const AJSON: string; ANullAsEmptyString: Boolean = False): string;
{ Read a JSON file and write the result to a TOML file.
  @param AJSONFile: Path to the input JSON file
  @param ATOMLFile: Path to the output TOML file
  @param ANullAsEmptyString: null Handling strategy (same as JSONToTOML)
  @param ABOM: Whether to write the UTF-8 BOM (default is True, TOML files often include a BOM).
  @returns True: if successful, False: if an error occurs }
function JSONFileToTOMLFile(const AJSONFile, ATOMLFile: string; ANullAsEmptyString: Boolean = False; ABOM:
  Boolean = True): Boolean;

implementation
(* ======================================================================
  Internal: Lightweight JSON Lexer
  Supports the complete RFC 8259 lexical unit:
    object  { "key": value }
    array   [ value, ... ]
    string  "..." (Including all escape sequences and \uXXXX proxy pairs)
    number  Integer/Floating-point (including negative sign and exponent)
    true / false / null
  ====================================================================== *)

type
  TJSONTokenKind = (jtkLBrace,    // {
    jtkRBrace,    // }
    jtkLBracket,  // [
    jtkRBracket,  // ]
    jtkColon,     // :
    jtkComma,     // ,
    jtkString,    // "..."
    jtkNumber,    // Number (integer or floating point)）
    jtkTrue,      // true
    jtkFalse,     // false
    jtkNull,      // null
    jtkEOF        // End of input
  );

  TJSONToken = record
    Kind: TJSONTokenKind;
    Str: string;   // Valid for jtkString / jtkNumber
    IsFloat: Boolean;  // jtkNumber Whether the mark is floating point
  end;
  { Lightweight JSON Lexer }
  TJSONLexer = class
  private
    FText: string;
    FPos: Integer;
    FHasPeeked: Boolean;
    FPeekedToken: TJSONToken;

    function IsAtEnd: Boolean; inline;
    function Peek: Char; inline;
    function Advance: Char; inline;
    procedure SkipWS;
    function ScanString: TJSONToken;
    function ScanNumber: TJSONToken;
    function ScanKeyword(const Expected: string; Kind: TJSONTokenKind): TJSONToken;
  public
    constructor Create(const AText: string);
    function Next: TJSONToken;
    function PeekToken: TJSONToken;
  end;
  { A lightweight JSON parser that directly generates a TTOMLValue tree. }
  TJSONParser = class
  private
    FLexer: TJSONLexer;
    FNullAsEmpty: Boolean;
    FCurrent: TJSONToken;

    procedure Advance;
    procedure Expect(Kind: TJSONTokenKind);
    function ParseValue: TTOMLValue;   // Returning nil indicates that the JSON is null and will not be converted to an empty string.
    function ParseObject: TTOMLTable;
    function ParseArray: TTOMLArray;
  public
    constructor Create(const AText: string; ANullAsEmpty: Boolean);
    destructor Destroy; override;
    function Parse: TTOMLTable;
  end;
{ ======================================================================
  TJSONLexer implementation
  ====================================================================== }

constructor TJSONLexer.Create(const AText: string);
begin
  FText := AText;
  FPos := 1;
  FHasPeeked := False;
end;

function TJSONLexer.IsAtEnd: Boolean;
begin
  Result := FPos > Length(FText);
end;

function TJSONLexer.Peek: Char;
begin
  if IsAtEnd then
    Result := #0
  else
    Result := FText[FPos];
end;

function TJSONLexer.Advance: Char;
begin
  if IsAtEnd then
  begin
    Result := #0;
    Exit;
  end;
  Result := FText[FPos];
  Inc(FPos);
end;

procedure TJSONLexer.SkipWS;
begin
  while (not IsAtEnd) and (Peek <= ' ') do
    Advance;
end;

function TJSONLexer.ScanString: TJSONToken;
{ Processes JSON strings, supporting all escape characters
  and \uXXXX (including proxy pairs other than BMP) }
var
  SB: TStringBuilder;
  C: Char;
  Hex: string;
  Hi, Lo: Cardinal;
  i: Integer;
begin
  Result.Kind := jtkString;
  Result.IsFloat := False;
  Advance;

  SB := TStringBuilder.Create;
  try
    while not IsAtEnd do
    begin
      C := Advance;
      if C = '"' then
        Break;

      if C <> '\' then
      begin
        SB.Append(C);
        Continue;
      end;

      // Escape sequences
      if IsAtEnd then
        raise ETOMLParserException.Create('JSON: unterminated escape sequence');

      C := Advance;
      case C of
        '"':
          SB.Append('"');
        '\':
          SB.Append('\');
        '/':
          SB.Append('/');
        'b':
          SB.Append(#8);
        'f':
          SB.Append(#12);
        'n':
          SB.Append(#10);
        'r':
          SB.Append(#13);
        't':
          SB.Append(#9);
        'u':
          begin
            // Read 4-digit hexadecimal code points
            Hex := '';
            for i := 1 to 4 do
            begin
              if IsAtEnd then
                raise ETOMLParserException.Create('JSON: incomplete \\u escape sequence');
              Hex := Hex + Advance;
            end;
            Hi := StrToInt('$' + Hex);

            // High proxy detection: D800..DBFF, followed by \uDC00..DFFF. Low proxy.
            if (Hi >= $D800) and (Hi <= $DBFF) then
            begin
              if (not IsAtEnd) and (Advance = '\') and (not IsAtEnd) and (Peek = 'u') then
              begin
                Advance;
                Hex := '';
                for i := 1 to 4 do
                begin
                  if IsAtEnd then
                    raise ETOMLParserException.Create('JSON: incomplete low surrogate in \\uXXXX pair');
                  Hex := Hex + Advance;
                end;
                Lo := StrToInt('$' + Hex);
                if (Lo >= $DC00) and (Lo <= $DFFF) then
                begin
                  // Merge the surrogate pairs into complete Unicode code points,
                  // then encode them into UTF-16 (two WideChar codes).
                  var CP: Cardinal := $10000 + (Hi - $D800) * $400 + (Lo - $DC00);
                  SB.Append(WideChar($D800 + (CP - $10000) shr 10));
                  SB.Append(WideChar($DC00 + (CP - $10000) and $3FF));
                end
                else
                  raise ETOMLParserException.CreateFmt('JSON: invalid low surrogate U+%.4X', [Lo]);
              end
              else
                raise ETOMLParserException.Create('JSON: high surrogate not followed by \\uXXXX low surrogate');
            end
            else if (Hi >= $DC00) and (Hi <= $DFFF) then
              raise ETOMLParserException.CreateFmt('JSON: unexpected low surrogate U+%.4X', [Hi])
            else
              SB.Append(WideChar(Hi));
          end;
      else
        raise ETOMLParserException.CreateFmt('JSON: unknown escape character "\\%s"', [C]);
      end;
    end;
    Result.Str := SB.ToString;
  finally
    SB.Free;
  end;
end;

function TJSONLexer.ScanNumber: TJSONToken;
{ Parsing JSON numbers }
var
  SB: TStringBuilder;
  IsFloat: Boolean;
begin
  Result.Kind := jtkNumber;
  IsFloat := False;
  SB := TStringBuilder.Create;
  try
    // Optional negative sign
    if Peek = '-' then
      SB.Append(Advance);

    // Integer part
    while (not IsAtEnd) and (Peek >= '0') and (Peek <= '9') do
      SB.Append(Advance);

    // Decimal part
    if (not IsAtEnd) and (Peek = '.') then
    begin
      IsFloat := True;
      SB.Append(Advance);
      while (not IsAtEnd) and (Peek >= '0') and (Peek <= '9') do
        SB.Append(Advance);
    end;

    // Exponential section
    if (not IsAtEnd) and ((Peek = 'e') or (Peek = 'E')) then
    begin
      IsFloat := True;
      SB.Append(Advance);
      if (not IsAtEnd) and ((Peek = '+') or (Peek = '-')) then
        SB.Append(Advance);
      while (not IsAtEnd) and (Peek >= '0') and (Peek <= '9') do
        SB.Append(Advance);
    end;

    Result.Str := SB.ToString;
    Result.IsFloat := IsFloat;
  finally
    SB.Free;
  end;
end;

function TJSONLexer.ScanKeyword(const Expected: string; Kind: TJSONTokenKind): TJSONToken;
{ Matches the keywords true / false / null }
var
  i: Integer;
begin
  for i := 1 to Length(Expected) do
  begin
    if IsAtEnd or (Advance <> Expected[i]) then
      raise ETOMLParserException.CreateFmt('JSON: expected keyword "%s"', [Expected]);
  end;
  Result.Kind := Kind;
  Result.Str := Expected;
  Result.IsFloat := False;
end;

function TJSONLexer.Next: TJSONToken;
begin
  if FHasPeeked then
  begin
    Result := FPeekedToken;
    FHasPeeked := False;
    Exit;
  end;

  SkipWS;

  if IsAtEnd then
  begin
    Result.Kind := jtkEOF;
    Result.Str := '';
    Result.IsFloat := False;
    Exit;
  end;

  case Peek of
    '{':
      begin
        Advance;
        Result.Kind := jtkLBrace;
        Result.Str := '{';
        Result.IsFloat := False;
      end;
    '}':
      begin
        Advance;
        Result.Kind := jtkRBrace;
        Result.Str := '}';
        Result.IsFloat := False;
      end;
    '[':
      begin
        Advance;
        Result.Kind := jtkLBracket;
        Result.Str := '[';
        Result.IsFloat := False;
      end;
    ']':
      begin
        Advance;
        Result.Kind := jtkRBracket;
        Result.Str := ']';
        Result.IsFloat := False;
      end;
    ':':
      begin
        Advance;
        Result.Kind := jtkColon;
        Result.Str := ':';
        Result.IsFloat := False;
      end;
    ',':
      begin
        Advance;
        Result.Kind := jtkComma;
        Result.Str := ',';
        Result.IsFloat := False;
      end;
    '"':
      Result := ScanString;
    't':
      Result := ScanKeyword('true', jtkTrue);
    'f':
      Result := ScanKeyword('false', jtkFalse);
    'n':
      Result := ScanKeyword('null', jtkNull);
    '-', '0'..'9':
      Result := ScanNumber;
  else
    raise ETOMLParserException.CreateFmt('JSON: unexpected character ''%s'' (U+%.4X)', [Peek, Ord(Peek)]);
  end;
end;

function TJSONLexer.PeekToken: TJSONToken;
begin
  if not FHasPeeked then
  begin
    FPeekedToken := Next;
    FHasPeeked := True;
  end;
  Result := FPeekedToken;
end;
{ ======================================================================
  TJSONParser implementation
  ====================================================================== }

constructor TJSONParser.Create(const AText: string; ANullAsEmpty: Boolean);
begin
  FLexer := TJSONLexer.Create(AText);
  FNullAsEmpty := ANullAsEmpty;
  Advance;
end;

destructor TJSONParser.Destroy;
begin
  FLexer.Free;
  inherited;
end;

procedure TJSONParser.Advance;
begin
  FCurrent := FLexer.Next;
end;

procedure TJSONParser.Expect(Kind: TJSONTokenKind);
begin
  if FCurrent.Kind <> Kind then
    raise ETOMLParserException.CreateFmt('JSON: expected token kind %d but got "%s"', [Ord(Kind), FCurrent.Str]);
  Advance;
end;

function TJSONParser.ParseValue: TTOMLValue;

var
  IntVal: Int64;
  FloatVal: Double;
  Code: Integer;
  FS: TFormatSettings;
begin
  case FCurrent.Kind of

    jtkLBrace:
      Result := ParseObject;

    jtkLBracket:
      Result := ParseArray;

    jtkString:
      begin
        Result := TTOMLString.Create(FCurrent.Str);
        Advance;
      end;

    jtkNumber:
      begin
        if FCurrent.IsFloat then
        begin
          // Floating-point: Parse using Invariant formatting,
          // preserving the original text for round trips.
          FS := TFormatSettings.Invariant;
          if not TryStrToFloat(FCurrent.Str, FloatVal, FS) then
            raise ETOMLParserException.CreateFmt('JSON: invalid float number "%s"', [FCurrent.Str]);
          Result := TTOMLFloat.Create(FloatVal, FCurrent.Str);
        end
        else
        begin
          // Prioritize Int64; downgrade to floating-point if out of range.
          Val(FCurrent.Str, IntVal, Code);
          if Code = 0 then
            Result := TTOMLInteger.Create(IntVal)
          else
          begin
            FS := TFormatSettings.Invariant;
            if not TryStrToFloat(FCurrent.Str, FloatVal, FS) then
              raise ETOMLParserException.CreateFmt('JSON: invalid number "%s"', [FCurrent.Str]);
            Result := TTOMLFloat.Create(FloatVal, FCurrent.Str);
          end;
        end;
        Advance;
      end;

    jtkTrue:
      begin
        Result := TTOMLBoolean.Create(True);
        Advance;
      end;

    jtkFalse:
      begin
        Result := TTOMLBoolean.Create(False);
        Advance;
      end;

    jtkNull:
      begin
        // null
        if FNullAsEmpty then
          Result := TTOMLString.Create('')
        else
          Result := nil;
        Advance;
      end;

  else
    raise ETOMLParserException.CreateFmt('JSON: unexpected token "%s" in value position', [FCurrent.Str]);
  end;
end;

function TJSONParser.ParseObject: TTOMLTable;
var
  Key: string;
  Val: TTOMLValue;
begin
  Result := TTOMLTable.Create;
  try
    Expect(jtkLBrace);

    // {}
    if FCurrent.Kind = jtkRBrace then
    begin
      Advance;
      Exit;
    end;

    repeat
      // The key must be a string.
      if FCurrent.Kind <> jtkString then
        raise ETOMLParserException.CreateFmt('JSON: object key must be a string, got "%s"', [FCurrent.Str]);
      Key := FCurrent.Str;
      Advance;

      Expect(jtkColon);

      Val := ParseValue;

      if Assigned(Val) then
      begin
        // Val has already been created; it needs to be released if Add fails.
        try
          Result.Add(Key, Val);
        except
          Val.Free;
          raise;
        end;
      end;
      // Val = nil (If the JSON is null and FNullAsEmpty=False, skip directly; no need to release.)

      if FCurrent.Kind = jtkComma then
        Advance
      else
        Break;

      // A trailing comma is allowed (forgiving parsing)
      if FCurrent.Kind = jtkRBrace then
        Break;
    until False;

    Expect(jtkRBrace);
  except
    Result.Free;
    raise;
  end;
end;

function TJSONParser.ParseArray: TTOMLArray;
var
  Val: TTOMLValue;
begin
  Result := TTOMLArray.Create;
  try
    Expect(jtkLBracket);

    if FCurrent.Kind = jtkRBracket then
    begin
      Advance;
      Exit;
    end;

    repeat
      Val := ParseValue;

      if Assigned(Val) then
        Result.Add(Val)
      else if FNullAsEmpty then
        Result.Add(TTOMLString.Create(''));

      if FCurrent.Kind = jtkComma then
        Advance
      else
        Break;

      // A trailing comma is allowed (forgiving parsing)
      if FCurrent.Kind = jtkRBracket then
        Break;
    until False;

    Expect(jtkRBracket);
  except
    Result.Free;
    raise;
  end;
end;

function TJSONParser.Parse: TTOMLTable;
begin
  if FCurrent.Kind <> jtkLBrace then
    raise ETOMLParserException.Create('JSON: root value must be a JSON object { ... }');
  Result := ParseObject;
  if FCurrent.Kind <> jtkEOF then
    raise ETOMLParserException.Create('JSON: unexpected content after root object');
end;
{ ======================================================================
  内部：TOML → JSON serializer
  ====================================================================== }

type
  TTOMLToJSONSerializer = class
  private
    FSB: TStringBuilder;
    FPretty: Boolean;
    FIndentSize: Integer;
    FIndentLevel: Integer;
    FFS: TFormatSettings; // Invariant formatting ensures that the decimal point is '.'.

    procedure Indent;
    procedure NewLine;
    procedure WriteJSONString(const S: string);
    procedure WriteValue(const V: TTOMLValue);
    procedure WriteObject(const T: TTOMLTable);
    procedure WriteArray(const A: TTOMLArray);
  public
    constructor Create(APretty: Boolean; AIndentSize: Integer);
    destructor Destroy; override;
    function Serialize(const V: TTOMLValue): string;
  end;

constructor TTOMLToJSONSerializer.Create(APretty: Boolean; AIndentSize: Integer);
begin
  FSB := TStringBuilder.Create;
  FPretty := APretty;
  FIndentSize := AIndentSize;
  FIndentLevel := 0;
  FFS := TFormatSettings.Invariant;
end;

destructor TTOMLToJSONSerializer.Destroy;
begin
  FSB.Free;
  inherited;
end;

procedure TTOMLToJSONSerializer.Indent;
var
  i: Integer;
begin
  if FPretty then
    for i := 1 to FIndentLevel * FIndentSize do
      FSB.Append(' ');
end;

procedure TTOMLToJSONSerializer.NewLine;
begin
  if FPretty then
    FSB.AppendLine;
end;

procedure TTOMLToJSONSerializer.WriteJSONString(const S: string);
{ Outputs a JSON string with double quotes, and all control characters
  and special characters are correctly escaped.
  Delphi strings are UTF-16; surrogate characters (U+D800..U+DFFF)
  are directly preserved as...
  Yes, the receiver can correctly restore it to UTF-16 or UTF-8. }
var
  i: Integer;
  C: Char;
  Code: Integer;
begin
  FSB.Append('"');
  i := 1;
  while i <= Length(S) do
  begin
    C := S[i];
    Code := Ord(C);
    case C of
      '"':
        FSB.Append('\"');
      '\':
        FSB.Append('\\');
      #8:
        FSB.Append('\b');
      #9:
        FSB.Append('\t');
      #10:
        FSB.Append('\n');
      #12:
        FSB.Append('\f');
      #13:
        FSB.Append('\r');
    else
      if Code < $20 then
        // other → \u00XX
        FSB.AppendFormat('\u%.4x', [Code])
      else
        FSB.Append(C);
    end;
    Inc(i);
  end;
  FSB.Append('"');
end;

procedure TTOMLToJSONSerializer.WriteValue(const V: TTOMLValue);
var
  F: Double;
  S: string;
  FCheck: Double;
  Code: Integer;
begin
  case V.ValueType of

    tvtString:
      WriteJSONString(V.AsString);

    tvtInteger:
      FSB.Append(IntToStr(V.AsInteger));

    tvtFloat:
      begin
        F := V.AsFloat;
        if IsNaN(F) or IsInfinite(F) then
          // The JSON specification does not support inf/nan → outputs null.
          FSB.Append('null')
        else
        begin
          // Use raw text first to ensure floating-point round-trip precision.
          if (V is TTOMLFloat) and (TTOMLFloat(V).RawString <> '') then
            S := TTOMLFloat(V).RawString
          else
          begin
            // Try 15 characters first (it's usually enough and more concise).
            S := FloatToStrF(F, ffGeneral, 15, 0, FFS);
            Val(S, FCheck, Code);
            // If 15 bits cannot accurately restore the data,
            // increase to 17 bits to ensure IEEE 754 round-trip.
            if (Code <> 0) or (FCheck <> F) then
              S := FloatToStrF(F, ffGeneral, 17, 0, FFS);
          end;
          FSB.Append(S);
        end;
      end;

    tvtBoolean:
      if V.AsBoolean then
        FSB.Append('true')
      else
        FSB.Append('false');

    tvtDateTime:
      begin
        // Preserve the original RFC 3339 text;
        // fall back to AsString if no original text is available.
        if (V is TTOMLDateTime) and (TTOMLDateTime(V).RawString <> '') then
          WriteJSONString(TTOMLDateTime(V).RawString)
        else
          WriteJSONString(V.AsString);
      end;

    tvtArray:
      WriteArray(V.AsArray);

    tvtTable, tvtInlineTable:
      WriteObject(V.AsTable);

  end;
end;

procedure TTOMLToJSONSerializer.WriteObject(const T: TTOMLTable);
{ Preserve the insertion order of TTOMLTable.
  Items without performing any additional sorting.
  TTOMLTable.Items is based on TDictionary and is inherently unordered.
  If a stable order is required, it is recommended that the upper-level
  business define the keys sequentially in the TOML file.}
var
  Pair: TPair<string, TTOMLValue>;
  First: Boolean;
begin
  FSB.Append('{');
  First := True;
  Inc(FIndentLevel);

  for Pair in T.Items do
  begin
    if not First then
      FSB.Append(',');
    First := False;
    NewLine;
    Indent;
    WriteJSONString(Pair.Key);
    FSB.Append(':');
    if FPretty then
      FSB.Append(' ');
    WriteValue(Pair.Value);
  end;

  Dec(FIndentLevel);
  if not First then // Non-empty objects: newline and indented closing parenthesis
  begin
    NewLine;
    Indent;
  end;
  FSB.Append('}');
end;

procedure TTOMLToJSONSerializer.WriteArray(const A: TTOMLArray);
var
  i: Integer;
begin
  FSB.Append('[');
  Inc(FIndentLevel);

  for i := 0 to A.Count - 1 do
  begin
    if i > 0 then
      FSB.Append(',');
    NewLine;
    Indent;
    WriteValue(A.GetItem(i));
  end;

  Dec(FIndentLevel);
  if A.Count > 0 then
  begin
    NewLine;
    Indent;
  end;
  FSB.Append(']');
end;

function TTOMLToJSONSerializer.Serialize(const V: TTOMLValue): string;
begin
  FSB.Clear;
  WriteValue(V);
  Result := FSB.ToString;
end;
{ ======================================================================
  Internal auxiliary function: UTF-8 file writing
  (compatible with Delphi 10.4, avoiding WriteBOM property issues)
  ====================================================================== }

procedure WriteUTF8File(const FileName, Content: string; ABOM: Boolean);
const
  UTF8BOM: array[0..2] of Byte = ($EF, $BB, $BF);
var
  FS: TFileStream;
  Raw: TBytes;
begin
  FS := TFileStream.Create(FileName, fmCreate);
  try
    if ABOM then
      FS.Write(UTF8BOM, SizeOf(UTF8BOM));
    Raw := TEncoding.UTF8.GetBytes(Content);
    if Length(Raw) > 0 then
      FS.Write(Raw[0], Length(Raw));
  finally
    FS.Free;
  end;
end;
{ ======================================================================
  Public function implementation
  ====================================================================== }

function TOMLToJSON(const Table: TTOMLTable; APretty: Boolean; AIndentSize: Integer): string;
var
  Ser: TTOMLToJSONSerializer;
begin
  Ser := TTOMLToJSONSerializer.Create(APretty, AIndentSize);
  try
    Result := Ser.Serialize(Table);
  finally
    Ser.Free;
  end;
end;

function TOMLValueToJSON(const Value: TTOMLValue; APretty: Boolean; AIndentSize: Integer): string;
var
  Ser: TTOMLToJSONSerializer;
begin
  Ser := TTOMLToJSONSerializer.Create(APretty, AIndentSize);
  try
    Result := Ser.Serialize(Value);
  finally
    Ser.Free;
  end;
end;

function TOMLFileToJSONFile(const ATOMLFile, AJSONFile: string; APretty: Boolean; ABOM: Boolean): Boolean;
var
  Table: TTOMLTable;
  JSON: string;
begin
  Result := False;
  try
    Table := ParseTOMLFile(ATOMLFile);
    try
      JSON := TOMLToJSON(Table, APretty);
    finally
      Table.Free;
    end;
    WriteUTF8File(AJSONFile, JSON, ABOM);
    Result := True;
  except
    // False
  end;
end;

function JSONToTOML(const AJSON: string; ANullAsEmptyString: Boolean): TTOMLTable;
var
  Parser: TJSONParser;
begin
  Parser := TJSONParser.Create(AJSON, ANullAsEmptyString);
  try
    Result := Parser.Parse;
  finally
    Parser.Free;
  end;
end;

function JSONToTOMLString(const AJSON: string; ANullAsEmptyString: Boolean): string;
var
  Table: TTOMLTable;
begin
  Table := JSONToTOML(AJSON, ANullAsEmptyString);
  try
    Result := SerializeTOML(Table);
  finally
    Table.Free;
  end;
end;

function JSONFileToTOMLFile(const AJSONFile, ATOMLFile: string; ANullAsEmptyString: Boolean; ABOM: Boolean): Boolean;
var
  SL: TStringList;
  JSON: string;
  Table: TTOMLTable;
begin
  Result := False;
  try
    SL := TStringList.Create;
    try
      SL.LoadFromFile(AJSONFile, TEncoding.UTF8);
      JSON := SL.Text;
    finally
      SL.Free;
    end;

    Table := JSONToTOML(JSON, ANullAsEmptyString);
    try
      Result := SerializeTOMLToFile(Table, ATOMLFile, ABOM);
    finally
      Table.Free;
    end;
  except
    //  False
  end;
end;

end.
