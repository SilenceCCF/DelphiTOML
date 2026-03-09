(* TOML.Parser.pas
TOML parser unit (lexical analysis + syntax analysis).
This unit implements a complete parser conforming to the TOML v1.1.0 specification, using a two-stage design:
1. TTOMLLexer — Lexical analysis that converts raw text into a sequence of tokens.
2. TTOMLParser — Syntax analysis, converting token sequences into TOML data structures.
Supported features:
- Key-value pairs (bare keys, basic string keys, literal string keys, dot keys)
- Tables and arrays
- Inline table { key = value, ... }
- Array [...] (supports trailing commas and multi-line formatting)
- Basic strings and literal strings (including multi-line forms)
- Decimal, hexadecimal (0x), octal (0o), binary (0b) integers
- Floating-point numbers (including exponents, inf, nan)
- Boolean value (true / false)
- Date and time (with time zone offset, local date and time, local date, local time)
Key implementation details:
- The segments in the period key are concatenated using #31 (ASCII Unit Separator).
Avoid confusion with valid dot characters in key names (such as "tt.com").
- An intermediate table implicitly created using the IsImplicit flag.
Unlike tables explicitly defined in [header]
- Use the IsInline flag for inline tables to prevent subsequent expansion of their content via the table header.
*)
unit TOML.Parser;

interface

uses
  SysUtils, Classes, TOML.Types, Generics.Collections, TypInfo, DateUtils, Math;
{$IF CompilerVersion < 20.0}

function CharInSet(C: Char; const CharSet: TSysCharSet): Boolean; inline;
{$IFEND}

type
  { Token types used during lexical analysis
    Each token represents a meaningful unit in the TOML syntax }
  TTokenType = (ttEOF,              // End of file marker
    ttString,           // String literal (basic or literal)
    ttMultilineString,  // Multi-line string
    ttInteger,          // Integer number (decimal, hex, octal, binary)
    ttFloat,            // Floating point number (with optional exponent)）
    ttBoolean,          // Boolean value (true/false)）
    ttDateTime,         // Date/time value (RFC 3339)）
    ttEqual,            // Equal sign (=)
    ttDot,              // Dot for nested keys (.)
    ttComma,            // Comma separator (,)
    ttLBracket,         // Left bracket ([)
    ttRBracket,         // Right bracket (])
    ttLBrace,           // Left brace ({)
    ttRBrace,           // Right brace (})
    ttNewLine,          // Line break
    ttWhitespace,       // Whitespace characters
    ttComment,          // Comment (# or ##)）
    ttIdentifier        // Key identifier
  );
  { Token record that stores lexical token information }

  TToken = record
    TokenType: TTokenType;  // Type of the token
    Value: string;          // String value of the token
    Line: Integer;          // Line number (1-based)）
    Column: Integer;        // Column number (1-based)）
  end;
  { Key-Value pair type for TOML tables） }

  TTOMLKeyValuePair = TPair<string, TTOMLValue>;
  { Lexer class that performs lexical analysis of TOML input
    Converts raw TOML text into a sequence of tokens }

  TTOMLLexer = class
  private
    FInput: string;      // Input string to tokenize
    FPosition: Integer;  // Current position in input）
    FLine: Integer;      // Current line number (1-based)
    FColumn: Integer;    // Current column number (1-based)

    { Checks if we've reached the end of input
      @returns True if at end, False otherwise }
    function IsAtEnd: Boolean;

    { Peeks at current character without advancing position
      @returns Current character or #0 if at end }
    function Peek: Char;

    { Peeks at next character without advancing position
      @returns Next character or #0 if at end }
    function PeekNext: Char;

    { Advances position and returns current character
      @returns Current character or #0 if at end }
    function Advance: Char;

    { Skips whitespace and comments in the input }
    procedure SkipWhitespace;

    { Scans a string token (basic or literal)
      @returns The scanned string token
      @raises ETOMLParserException if string is malformed }
    function ScanString: TToken;

    { Scans a number token (integer or float)
      @returns The scanned number token
      @raises ETOMLParserException if number is malformed }
    function ScanNumber: TToken;

    { Scans an identifier token
      @returns The scanned identifier token }
    function ScanIdentifier: TToken;

    { Scans a datetime token
      @returns The scanned datetime token
      @raises ETOMLParserException if datetime is malformed }
    function ScanDateTime: TToken;

    { Character classification helper functions }

    { Checks if character is a digit (0-9)
      @param C Character to check
      @returns True if digit, False otherwise }
    function IsDigit(C: Char): Boolean;

    { Checks if character is alphabetic (a-z, A-Z)
    @param C Character to check
    @returns True if alphabetic, False otherwise }
    function IsAlpha(C: Char): Boolean;

    { Checks if character is alphanumeric (a-z, A-Z, 0-9)
      @param C Character to check
      @returns True if alphanumeric, False otherwise }
    function IsAlphaNumeric(C: Char): Boolean;
  public
    { Creates a new lexer instance
      @param AInput The TOML input string to tokenize }
    constructor Create(const AInput: string);

    { Gets the next token from input
      @returns The next token
      @raises ETOMLParserException if invalid input encountered }
    function NextToken: TToken;
  end;
  { Parser class that performs syntactic analysis of TOML input
    Converts tokens into TOML data structures }

  TTOMLParser = class
  private
    FLexer: TTOMLLexer;       // Lexer instance
    FCurrentToken: TToken;    // Current token being processed
    FPeekedToken: TToken;     // Next token (if peeked)
    FHasPeeked: Boolean;      // Whether we have a peeked token

    { Advances to next token }
    procedure Advance;

    { Peeks at next token without advancing
      @returns The next token }
    function Peek: TToken;

    { Checks if current token matches expected type
      @param TokenType Expected token type
      @returns True and advances if matches, False otherwise }
    function Match(TokenType: TTokenType): Boolean;

    { Expects current token to be of specific type
      @param TokenType Expected token type
      @raises ETOMLParserException if token doesn't match }
    procedure Expect(TokenType: TTokenType);

    { Parsing methods for different TOML constructs }

    { Parses a TOML value
      @returns The parsed value
      @raises ETOMLParserException on parse error }
    function ParseValue: TTOMLValue;

    { Parses a string value
      @returns The parsed string value
      @raises ETOMLParserException on parse error }
    function ParseString: TTOMLString;

    { Parses a number value (integer or float)
      @returns The parsed number value
      @raises ETOMLParserException on parse error }
    function ParseNumber: TTOMLValue;

    { Parses a boolean value
      @returns The parsed boolean value
      @raises ETOMLParserException on parse error }
    function ParseBoolean: TTOMLBoolean;

    { Parses a datetime value
      @returns The parsed datetime value
      @raises ETOMLParserException on parse error }
    function ParseDateTime: TTOMLDateTime;

    { Parses an array value
      @returns The parsed array value
      @raises ETOMLParserException on parse error }
    function ParseArray: TTOMLArray;

    { Parses an inline table value
      @returns The parsed table value
      @raises ETOMLParserException on parse error }
    function ParseInlineTable: TTOMLTable;

    { Parses a key (bare or quoted)
      @returns The parsed key string
      @raises ETOMLParserException on parse error }
    function ParseKey: string;

    { Parses a key-value pair
      @returns The parsed key-value pair
      @raises ETOMLParserException on parse error }
    function ParseKeyValue: TTOMLKeyValuePair;

    function SplitDottedKey(const CompositeKey: string): TArray<string>;

    { Add a key field to the path list. If the segment is not enclosed
      in quotes and contains a period (due to Lexer's greedy matching
      using ttFloat), it will be further split. }
    procedure AddKeyToPath(Path: TList<string>; const Segment: string; WasQuoted: Boolean); overload;
    procedure AddKeyToPath(Path: TStrings; const Segment: string; WasQuoted: Boolean); overload;

    { Create/navigate tables level by level using the dot key path,
      and write values ​​at the final positions. @raises ETOMLParserException
      if there is a path conflict or a duplicate key definition. }
    procedure SetDottedKey(RootTable: TTOMLTable; const KeyParts: TArray<string>; Value: TTOMLValue);


    { The current token must be a newline character or EOF; otherwise,
      an exception will be thrown. If it's a newline character,
      it's consumed to prepare for the next statement. }
    procedure ExpectNewLineOrEOF;

  public
    { Creates a new parser instance
      @param AInput The TOML input string to parse }
    constructor Create(const AInput: string);
    destructor Destroy; override;

    { Parses the input and returns a TOML table
      @returns The parsed TOML table
      @raises ETOMLParserException on parse error }
    function Parse: TTOMLTable;
  end;

{ Helper functions }

{ Parses a TOML string into a table
  @param ATOML The TOML string to parse
  @returns The parsed TOML table
  @raises ETOMLParserException on parse error }
function ParseTOMLString(const ATOML: string): TTOMLTable;

{ Parses a TOML file into a table
  @param AFileName The file to parse
  @returns The parsed TOML table
  @raises ETOMLParserException on parse error
  @raises EFileStreamError if file cannot be opened }
function ParseTOMLFile(const AFileName: string): TTOMLTable;

implementation
{$IF CompilerVersion < 20.0}

function CharInSet(C: Char; const CharSet: TSysCharSet): Boolean;
begin
  Result := C in CharSet;
end;
{$IFEND}

{ Helper functions }

function ParseTOMLString(const ATOML: string): TTOMLTable;
var
  Parser: TTOMLParser;
begin
  Parser := TTOMLParser.Create(ATOML);
  try
    Result := Parser.Parse;
  finally
    Parser.Free;
  end;
end;

function ParseTOMLFile(const AFileName: string): TTOMLTable;
var
  Stream: TFileStream;
  Encoding: TEncoding;
  BOM: array[0..2] of Byte;
  BytesRead: Integer;
  StringList: TStringList;
begin
  Stream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
  try
    // Read the first 3 bytes to detect the BOM encoding mark.
    BytesRead := Stream.Read(BOM, 3);
    Stream.Position := 0;

    if (BytesRead >= 3) and (BOM[0] = $EF) and (BOM[1] = $BB) and (BOM[2] = $BF) then
      Encoding := TEncoding.UTF8
    else if (BytesRead >= 2) and (BOM[0] = $FF) and (BOM[1] = $FE) then
      Encoding := TEncoding.Unicode
    else if (BytesRead >= 2) and (BOM[0] = $FE) and (BOM[1] = $FF) then
      Encoding := TEncoding.BigEndianUnicode
    else
      // When there is no BOM, the default encoding is UTF-8
      // (as required by the TOML specification).）
      Encoding := TEncoding.UTF8;

    StringList := TStringList.Create;
    try
      StringList.LoadFromStream(Stream, Encoding);
      Result := ParseTOMLString(StringList.Text);
    finally
      StringList.Free;
    end;
  finally
    Stream.Free;
  end;
end;

{ TTOMLParser Auxiliary methods }

procedure TTOMLParser.ExpectNewLineOrEOF;
begin
  // Only newline or end-of-file is allowed after the top-level expression.
  if not (FCurrentToken.TokenType in [ttNewLine, ttEOF]) then
    raise ETOMLParserException.CreateFmt('Only one expression allowed per line. Unexpected "%s" at line %d, column %d',
      [FCurrentToken.Value, FCurrentToken.Line, FCurrentToken.Column]);

  if FCurrentToken.TokenType = ttNewLine then
    Advance;
end;
{ TTOMLLexer }

constructor TTOMLLexer.Create(const AInput: string);
begin
  inherited Create;
  FInput := AInput;
  FPosition := 1;
  FLine := 1;
  FColumn := 1;
end;

function TTOMLLexer.IsAtEnd: Boolean;
begin
  Result := FPosition > Length(FInput);
end;

function TTOMLLexer.Peek: Char;
begin
  if IsAtEnd then
    Result := #0
  else
    Result := FInput[FPosition];
end;

function TTOMLLexer.PeekNext: Char;
begin
  if FPosition + 1 > Length(FInput) then
    Result := #0
  else
    Result := FInput[FPosition + 1];
end;

function TTOMLLexer.Advance: Char;
begin
  if not IsAtEnd then
  begin
    Result := FInput[FPosition];
    Inc(FPosition);
    Inc(FColumn);
    if Result = #10 then
    begin
      Inc(FLine);
      FColumn := 1;
    end;
  end
  else
    Result := #0;
end;

procedure TTOMLLexer.SkipWhitespace;
var
  Ch: Char;
  OrdCh: Integer;
begin
  while not IsAtEnd do
  begin
    case Peek of
      ' ', #9, #$FEFF:
        // Spaces, tabs, and UTF-8 BOMs are all considered blank.
        Advance;
      '#':
        begin
          // Skip comments until the end of the line, while checking
          // for illegal control characters.
          Advance; // 消耗 '#'
          while (not IsAtEnd) and (Peek <> #10) and (Peek <> #13) do
          begin
            Ch := Peek;
            OrdCh := Ord(Ch);
            // The comments must not contain U+0000-U+0008, U+000B-U+001F,
            // or U+007F.
            if (OrdCh <= 8) or ((OrdCh >= 11) and (OrdCh <= 31)) or (OrdCh = 127) then
              raise ETOMLParserException.CreateFmt('Control character U+%.4X is not allowed in comments', [OrdCh]);
            Advance;
          end;
        end;
    else
      Break;
    end;
  end;
end;

function TTOMLLexer.IsDigit(C: Char): Boolean;
begin
  Result := CharInSet(C, ['0'..'9']);
end;

function TTOMLLexer.IsAlpha(C: Char): Boolean;
begin
  Result := CharInSet(C, ['a'..'z']) or CharInSet(C, ['A'..'Z']) or (C = '_');
end;

function TTOMLLexer.IsAlphaNumeric(C: Char): Boolean;
begin
  Result := IsAlpha(C) or IsDigit(C);
end;

function TTOMLLexer.ScanString: TToken;
var
  QuoteChar: Char;
  IsLiteral: Boolean;
  IsMultiline: Boolean;
  StartColumn: Integer;
  TempValue: string;
  FoundClosing: Boolean;
  QuoteCount, LookPos, j: Integer;
begin
  StartColumn := FColumn;
  QuoteChar := Peek;
  IsLiteral := (QuoteChar = '''');
  IsMultiline := False;
  FoundClosing := False;

  Advance;
  // Detect triple quotes (multi-line strings)
  if (Peek = QuoteChar) and (PeekNext = QuoteChar) then
  begin
    IsMultiline := True;
    Advance;
    Advance;
    // The first newline character at the beginning of a multi-line string
    // (if immediately followed) is ignored.
    if (Peek = #13) or (Peek = #10) then
    begin
      if Peek = #13 then
      begin
        Advance;
        if Peek = #10 then
          Advance;
      end
      else
        Advance;
    end;
  end;

  TempValue := '';
  while not IsAtEnd do
  begin
    // 1. Detecting closed delimiters
    if IsMultiline then
    begin
      if Peek = QuoteChar then
      begin
        // Detect the number of consecutive quotation marks (TOML allows a
        // maximum of 2 consecutive quotation marks within a multi-line string).
        QuoteCount := 0;
        LookPos := FPosition;
        while (LookPos <= Length(FInput)) and (FInput[LookPos] = QuoteChar) do
        begin
          Inc(QuoteCount);
          Inc(LookPos);
        end;

        if QuoteCount >= 3 then
        begin
          if QuoteCount <= 5 then
          begin
            // 3–5 quotation marks: the first (QuoteCount-3) are the content,
            // and the last 3 are delimiters.
            for j := 1 to QuoteCount - 3 do
              TempValue := TempValue + Advance;
            Advance;
            Advance;
            Advance;
            FoundClosing := True;
            Break;
          end
          else
          begin
            Advance;
            Advance;
            Advance;
            FoundClosing := True;
            Break;
          end;
        end;
      end;
    end
    else if Peek = QuoteChar then
    begin
      Advance;
      FoundClosing := True;
      Break;
    end;

    // 2. Handling escape sequences (only applies to basic strings;
    // literal strings are not escaped).
    if (not IsLiteral) and (Peek = '\') then
    begin
      // In a multi-line basic string, the backslash (\) at the end
      // of a line is used to ignore newlines and subsequent whitespace.
      if IsMultiline then
      begin
        var SlashPos := FPosition + 1;
        while (SlashPos <= Length(FInput)) and CharInSet(FInput[SlashPos], [' ', #9]) do
          Inc(SlashPos);
        if (SlashPos <= Length(FInput)) and CharInSet(FInput[SlashPos], [#10, #13]) then
        begin
          Advance; // 消耗 '\'
          while (not IsAtEnd) and CharInSet(Peek, [' ', #9, #10, #13]) do
            Advance;
          Continue;
        end;
      end;

      Advance; // 消耗反斜杠
      case Peek of
        'b':
          TempValue := TempValue + #8;    // Backspace
        'f':
          TempValue := TempValue + #12;   // Page break
        'n':
          TempValue := TempValue + #10;   // Line break
        'r':
          TempValue := TempValue + #13;   // Return
        't':
          TempValue := TempValue + #9;    // Tab
        '\':
          TempValue := TempValue + '\';
        '"':
          TempValue := TempValue + '"';
        '''':
          TempValue := TempValue + '''';  // Allow escaped single quotes
        'e':
          TempValue := TempValue + #27;   // ESC（TOML v1.1.0）
        'x':
          begin
            // \xHH —— 2-digit hexadecimal escape sequence
            Advance;
            var HexStr := '';
            for j := 1 to 2 do
            begin
              if IsAtEnd or (not CharInSet(Peek, ['0'..'9', 'A'..'F', 'a'..'f'])) then
                raise ETOMLParserException.Create('Invalid hex escape');
              HexStr := HexStr + Advance;
            end;
            TempValue := TempValue + Char(StrToInt('$' + HexStr));
            Continue;
          end;
        'u', 'U':
          begin
            // \uHHHH 或 \UHHHHHHHH —— Unicode escape sequences
            var UChar := Peek;
            Advance;
            var HexLen := IfThen(UChar = 'U', 8, 4);
            var HexStr := '';
            for j := 1 to HexLen do
            begin
              if not CharInSet(Peek, ['0'..'9', 'A'..'F', 'a'..'f']) then
                raise ETOMLParserException.Create('Invalid unicode escape');
              HexStr := HexStr + Advance;
            end;
            var CP := Cardinal(StrToInt('$' + HexStr));
            if (CP > $10FFFF) or ((CP >= $D800) and (CP <= $DFFF)) then
              raise ETOMLParserException.Create('Invalid unicode code point');
            {$IF CompilerVersion >= 20.0}
            if CP <= $FFFF then
              TempValue := TempValue + WideChar(CP)
            else
            begin
              CP := CP - $10000;
              TempValue := TempValue + WideChar($D800 or (CP shr 10)) + WideChar($DC00 or (CP and $3FF));
            end;
            {$IFEND}
            Continue;
          end;
      else
        raise ETOMLParserException.Create('Invalid escape sequence');
      end;
      Advance; // Consume escaped characters (b/f/n/r/t/\/"/e, etc.)）
    end
    else
    begin
      // 3. Ordinary character processing and illegal control character checking
      var Ch := Peek;

      // Line break processing
      if (Ch = #10) or (Ch = #13) then
      begin
        if not IsMultiline then
          raise ETOMLParserException.Create('Newlines are not allowed in single-line strings');

        if Ch = #13 then
        begin
          Advance;
          if Peek = #10 then
            Advance
          else
            raise ETOMLParserException.Create('Bare CR is not allowed in multi-line strings');
        end
        else
          Advance;

        // Line breaks in multi-line strings are uniformly normalized as LF.
        TempValue := TempValue + #10;
      end
      else
      begin
        // Other control character checks: Tab (0x09) is valid, the rest
        // (0x00-0x1F and 0x7F) are invalid.
        var OrdCh := Ord(Ch);
        if (OrdCh < 32) and (OrdCh <> 9) then
          raise ETOMLParserException.CreateFmt('Control character U+%.4X is not allowed', [OrdCh]);
        if OrdCh = 127 then
          raise ETOMLParserException.Create('Control character U+007F is not allowed');

        TempValue := TempValue + Advance;
      end;
    end;
  end;

  if not FoundClosing then
    raise ETOMLParserException.Create('Unterminated string');

  if IsMultiline then
    Result.TokenType := ttMultilineString
  else
    Result.TokenType := ttString;
  Result.Value := TempValue;
  Result.Line := FLine;
  Result.Column := StartColumn;
end;

function TTOMLLexer.ScanNumber: TToken;
var
  IsFloat: Boolean;
  StartColumn: Integer;
  TempValue: string;
  Ch: Char;
  HasSign: Boolean;
  { Consumes consecutive numeric characters (AllowedDigits specifies the
    valid character set), including underscore delimiter checking. }

  procedure ConsumeDigits(const AllowedDigits: TSysCharSet);
  begin
    while (not IsAtEnd) and (CharInSet(Peek, AllowedDigits) or (Peek = '_')) do
    begin
      if Peek = '_' then
      begin
        { The underscore must be preceded and followed by valid numbers
         (it is forbidden to use it at the beginning, end, or consecutively).}
        if (TempValue = '') or (not CharInSet(TempValue[Length(TempValue)], AllowedDigits)) then
          raise ETOMLParserException.Create('Invalid underscore placement');
        TempValue := TempValue + Advance;
        if IsAtEnd or (not CharInSet(Peek, AllowedDigits)) then
          raise ETOMLParserException.Create('Invalid underscore placement');
      end
      else
        TempValue := TempValue + Advance;
    end;
  end;

begin
  IsFloat := False;
  HasSign := False;
  StartColumn := FColumn;
  TempValue := '';

  // 1. Handle positive and negative signs
  if CharInSet(Peek, ['+', '-']) then
  begin
    HasSign := True;
    TempValue := TempValue + Advance;
  end;

  // 2. Detect special floating-point values inf / nan (with symbols allowed.)
  if (Peek = 'i') or (Peek = 'n') then
  begin
    var StartLine := FLine;
    var Ident := ScanIdentifier;
    var FullVal := TempValue + Ident.Value;
    if (FullVal = 'inf') or (FullVal = '+inf') or (FullVal = '-inf') or (FullVal = 'nan') or (FullVal = '+nan')
      or (FullVal = '-nan') then
    begin
      Result.TokenType := ttFloat;
      Result.Value := FullVal;
      Result.Line := StartLine;
      Result.Column := StartColumn;
      Exit;
    end
    else
      raise ETOMLParserException.CreateFmt('Invalid identifier starting with sign: %s', [FullVal]);
  end;

  // 3. 检测进制前缀 0x / 0o / 0b
  if (Peek = '0') and (not IsAtEnd) and CharInSet(PeekNext, ['x', 'o', 'b']) then
  begin
    // Integers in base 1 are not allowed to have signs.
    if HasSign then
      raise ETOMLParserException.Create('Signs are not allowed for hex, octal, or binary integers');

    Ch := PeekNext;
    TempValue := TempValue + Advance; // '0'
    TempValue := TempValue + Advance; // 'x' / 'o' / 'b'
    case Ch of
      'x':
        ConsumeDigits(['0'..'9', 'A'..'F', 'a'..'f']);
      'o':
        ConsumeDigits(['0'..'7']);
      'b':
        ConsumeDigits(['0', '1']);
    end;
    Result.TokenType := ttInteger;
    Result.Value := TempValue;
    Result.Line := FLine;
    Result.Column := StartColumn;
    Exit;
  end;

  // 4. Decimal integer part
  ConsumeDigits(['0'..'9']);

  // 5. The decimal part (a dot must be followed by a number;
  // otherwise, it is not a floating-point number)
  if (Peek = '.') and IsDigit(PeekNext) then
  begin
    IsFloat := True;
    TempValue := TempValue + Advance;
    ConsumeDigits(['0'..'9']);
  end;

  // 6. Index section
  if CharInSet(Peek, ['e', 'E']) then
  begin
    IsFloat := True;
    TempValue := TempValue + Advance;
    if CharInSet(Peek, ['+', '-']) then
      TempValue := TempValue + Advance;
    ConsumeDigits(['0'..'9']);
  end;

  if IsFloat then
    Result.TokenType := ttFloat
  else
    Result.TokenType := ttInteger;
  Result.Value := TempValue;
  Result.Line := FLine;
  Result.Column := StartColumn;
end;

function TTOMLLexer.ScanIdentifier: TToken;
var
  StartColumn: Integer;
begin
  StartColumn := FColumn;
  Result.Value := '';
  // Bare keys allow: letters, numbers, underscores, hyphens
  while not IsAtEnd and (IsAlphaNumeric(Peek) or (Peek = '-')) do
    Result.Value := Result.Value + Advance;

  Result.TokenType := ttIdentifier;
  Result.Line := FLine;
  Result.Column := StartColumn;
end;

function TTOMLLexer.ScanDateTime: TToken;
var
  StartColumn, StartPos, StartLine: Integer;
  HasTime: Boolean;
  HasTimezone: Boolean;
  HasDate: Boolean;
  TempValue: string;

  { Attempt to scan Count consecutive numbers;
    return True on success, False on failure. }
  function ScanDigits(Count: Integer): Boolean;
  var
    i: Integer;
  begin
    Result := True;
    for i := 1 to Count do
    begin
      if not IsDigit(Peek) then
      begin
        Result := False;
        Exit;
      end;
      TempValue := TempValue + Advance;
    end;
  end;

begin
  StartPos := FPosition;
  StartLine := FLine;
  StartColumn := FColumn;
  TempValue := '';
  HasDate := False;
  HasTime := False;
  HasTimezone := False;

  // Attempting to parse the date portion: YYYY-MM-DD
  if ScanDigits(4) and (Peek = '-') then
  begin
    TempValue := TempValue + Advance; // '-'
    if ScanDigits(2) and (Peek = '-') then
    begin
      TempValue := TempValue + Advance; // '-'
      if ScanDigits(2) then
        HasDate := True;
    end;
  end;

  { After the date, attempt to parse the time portion
   (separated by T or space; spaces require lookahead
   confirmation that the following format is HH:MM). }
  if HasDate and ((UpCase(Peek) = 'T') or (Peek = ' ')) then
  begin
    var CanContinue := False;
    if UpCase(Peek) = 'T' then
      CanContinue := True
    else if Peek = ' ' then
    begin
      // Space-separated: Lookahead check to ensure subsequent
      // elements conform to HH:MM format
      var NextPos := FPosition + 1;
      if NextPos + 4 <= Length(FInput) then
        CanContinue := IsDigit(FInput[NextPos]) and IsDigit(FInput[NextPos + 1]) and (FInput[NextPos + 2] =
          ':') and IsDigit(FInput[NextPos + 3]) and IsDigit(FInput[NextPos + 4]);
    end;

    if CanContinue then
    begin
      TempValue := TempValue + Advance; // Consume 'T' or ' '
      if ScanDigits(2) and (Peek = ':') then
      begin
        TempValue := TempValue + Advance; // ':'
        if ScanDigits(2) then             // Minutes (required)
        begin
          HasTime := True;
          // Seconds are optional
          if Peek = ':' then
          begin
            TempValue := TempValue + Advance; // ':'
            if ScanDigits(2) then            // Secound
            begin
              // Decimal seconds selectable
              if Peek = '.' then
              begin
                TempValue := TempValue + Advance; // '.'
                while IsDigit(Peek) do
                  TempValue := TempValue + Advance;
              end;
            end;
          end;
        end;
      end;
    end;
  end
  else if not HasDate then
  begin
    // When no date is specified, attempt to parse pure time: HH:MM[:SS[.frac]]
    FPosition := StartPos;
    FLine := StartLine;
    FColumn := StartColumn;
    TempValue := '';

    if ScanDigits(2) and (Peek = ':') then
    begin
      TempValue := TempValue + Advance; // ':'
      if ScanDigits(2) then
      begin
        HasTime := True;
        if Peek = ':' then
        begin
          TempValue := TempValue + Advance;
          if ScanDigits(2) then
          begin
            if Peek = '.' then
            begin
              TempValue := TempValue + Advance;
              while IsDigit(Peek) do
                TempValue := TempValue + Advance;
            end;
          end;
        end;
      end;
    end;
  end;

  // Attempt to resolve the time zone portion (Z or +/-HH:MM)）
  if HasTime and (CharInSet(UpCase(Peek), ['Z', '+', '-'])) then
  begin
    if UpCase(Peek) = 'Z' then
    begin
      TempValue := TempValue + Advance;
      HasTimezone := True;
    end
    else
    begin
      TempValue := TempValue + Advance; // '+' 或 '-'
      while (not IsAtEnd) and CharInSet(Peek, ['0'..'9', ':']) do
        TempValue := TempValue + Advance;
    end;
  end;

  // Determine the Token type based on the parsing results.
  if HasDate or HasTime then
    Result.TokenType := ttDateTime
  else
    Result.TokenType := ttInteger; // Rollback: Let ScanNumber reprocess.

  Result.Value := TempValue;
  Result.Line := FLine;
  Result.Column := StartColumn;
end;

function TTOMLLexer.NextToken: TToken;
var
  SavePos, SaveLine, SaveCol: Integer;
begin
  SkipWhitespace;

  Result.Line := FLine;
  Result.Column := FColumn;

  if IsAtEnd then
  begin
    Result.TokenType := ttEOF;
    Result.Value := '';
    Exit;
  end;

  case Peek of
    '=':
      begin
        Advance;
        Result.TokenType := ttEqual;
        Result.Value := '=';
      end;
    '.':
      begin
        Advance;
        Result.TokenType := ttDot;
        Result.Value := '.';
      end;
    ',':
      begin
        Advance;
        Result.TokenType := ttComma;
        Result.Value := ',';
      end;
    '[':
      begin
        Advance;
        Result.TokenType := ttLBracket;
        Result.Value := '[';
      end;
    ']':
      begin
        Advance;
        Result.TokenType := ttRBracket;
        Result.Value := ']';
      end;
    '{':
      begin
        Advance;
        Result.TokenType := ttLBrace;
        Result.Value := '{';
      end;
    '}':
      begin
        Advance;
        Result.TokenType := ttRBrace;
        Result.Value := '}';
      end;
    #10, #13:
      begin
        // Line break handling: CR+LF and a single LF are uniformly
        // treated as a single line break token.
        if Peek = #13 then
        begin
          Advance;
          if Peek = #10 then
            Advance
          else
            raise ETOMLParserException.Create('Bare CR not allowed');
        end
        else
          Advance;
        Result.TokenType := ttNewLine;
        Result.Value := #10;
      end;
    '"', '''':
      Exit(ScanString);
    '0'..'9':
      begin
        // Try scanning the date and time first; if that fails,
        // revert to scanning numbers.
        SavePos := FPosition;
        SaveLine := FLine;
        SaveCol := FColumn;
        Result := ScanDateTime;
        if Result.TokenType = ttDateTime then
          Exit;

        FPosition := SavePos;
        FLine := SaveLine;
        FColumn := SaveCol;
        Result := ScanNumber;
        // If a number is immediately followed by a letter or hyphen,
        // the entire key is treated as an identifier (e.g., a bare key
        // in the form of a 2024-key).）
        if (not IsAtEnd) and (IsAlpha(Peek) or (Peek = '-')) then
        begin
          FPosition := SavePos;
          FLine := SaveLine;
          FColumn := SaveCol;
          Result := ScanIdentifier;
        end;
        Exit;
      end;
    '+', '-':
      begin
        // Prioritize scanning for signed numbers; if only a sign
        // or a letter remains, treat it as an identifier.
        SavePos := FPosition;
        SaveLine := FLine;
        SaveCol := FColumn;
        Result := ScanNumber;
        if (Result.Value = '+') or (Result.Value = '-') or IsAlpha(Peek) then
        begin
          FPosition := SavePos;
          FLine := SaveLine;
          FColumn := SaveCol;
          Result := ScanIdentifier;
        end;
        Exit;
      end;
  else
    if IsAlpha(Peek) then
      Exit(ScanIdentifier)
    else
      raise ETOMLParserException.CreateFmt('Unexpected character: %s at line %d, column %d', [Peek, Result.Line,
        Result.Column]);
  end;
end;
{ TTOMLParser }

constructor TTOMLParser.Create(const AInput: string);
begin
  inherited Create;
  FLexer := TTOMLLexer.Create(AInput);
  FHasPeeked := False;
  Advance;
end;

destructor TTOMLParser.Destroy;
begin
  FLexer.Free;
  inherited;
end;

procedure TTOMLParser.Advance;
begin
  if FHasPeeked then
  begin
    FCurrentToken := FPeekedToken;
    FHasPeeked := False;
  end
  else
    FCurrentToken := FLexer.NextToken;
end;

function TTOMLParser.Peek: TToken;
begin
  if not FHasPeeked then
  begin
    FPeekedToken := FLexer.NextToken;
    FHasPeeked := True;
  end;
  Result := FPeekedToken;
end;

function TTOMLParser.Match(TokenType: TTokenType): Boolean;
begin
  if FCurrentToken.TokenType = TokenType then
  begin
    Advance;
    Result := True;
  end
  else
    Result := False;
end;

procedure TTOMLParser.Expect(TokenType: TTokenType);
begin
  if FCurrentToken.TokenType <> TokenType then
    raise ETOMLParserException.CreateFmt('Expected token type %s but got %s at line %d, column %d', [GetEnumName
      (TypeInfo(TTokenType), Ord(TokenType)), GetEnumName(TypeInfo(TTokenType), Ord(FCurrentToken.TokenType)),
      FCurrentToken.Line, FCurrentToken.Column]);
  Advance;
end;

function TTOMLParser.ParseValue: TTOMLValue;
begin
  case FCurrentToken.TokenType of
    ttString, ttMultilineString:
      Result := ParseString;
    ttDateTime:
      Result := ParseDateTime;
    ttInteger, ttFloat:
      Result := ParseNumber;
    ttIdentifier:
      begin
        var Val := FCurrentToken.Value;
        if (Val = 'true') or (Val = 'false') then
          Result := ParseBoolean
        else if (Val = 'inf') or (Val = 'nan') then
          Result := ParseNumber
        else
          raise ETOMLParserException.CreateFmt('Unexpected identifier: %s at line %d, column %d', [Val,
            FCurrentToken.Line, FCurrentToken.Column]);
      end;
    ttLBracket:
      Result := ParseArray;
    ttLBrace:
      Result := ParseInlineTable;
  else
    raise ETOMLParserException.CreateFmt('Unexpected token type: %s at line %d, column %d', [GetEnumName(TypeInfo
      (TTokenType), Ord(FCurrentToken.TokenType)), FCurrentToken.Line, FCurrentToken.Column]);
  end;
end;

function TTOMLParser.ParseString: TTOMLString;
begin
  Result := TTOMLString.Create(FCurrentToken.Value);
  Advance;
end;

function TTOMLParser.ParseNumber: TTOMLValue;
var
  RawValue, CleanValue, BaseValue: string;
  Code: Integer;
  IntValue: Int64;
  FloatValue: Double;
  i: Integer;
  SForCheck: string;
  IsHexOctBin: Boolean;
begin
  RawValue := FCurrentToken.Value;

  // 1. Handling special floating-point values ​inf / nan (including signed form)
  if SameText(RawValue, 'inf') or SameText(RawValue, '+inf') or SameText(RawValue, '-inf') or SameText(RawValue,
    'nan') or SameText(RawValue, '+nan') or SameText(RawValue, '-nan') then
  begin
    if SameText(RawValue, '-inf') then
      FloatValue := NegInfinity
    else if SameText(RawValue, 'inf') or SameText(RawValue, '+inf') then
      FloatValue := Infinity
    else
      FloatValue := NaN;
    Result := TTOMLFloat.Create(FloatValue, RawValue);
    Advance;
    Exit;
  end;

  // 2. Removing the underscore delimiter yields a clean string
  // of numbers for parsing.
  CleanValue := '';
  for i := 1 to Length(RawValue) do
    if RawValue[i] <> '_' then
      CleanValue := CleanValue + RawValue[i];

  IntValue := 0;
  Code := 0;
  Result := nil;

  // 3. Determine if it is a hexadecimal/octal/binary integer.
  IsHexOctBin := (Length(CleanValue) >= 2) and (CleanValue[1] = '0') and CharInSet(CleanValue[2], ['x', 'o', 'b']);

  if IsHexOctBin then
  begin
    case UpCase(CleanValue[2]) of
      'X': // hexadecimal
        begin
          BaseValue := '$' + Copy(CleanValue, 3, Length(CleanValue));
          Val(BaseValue, IntValue, Code);
        end;
      'O': // Octal
        begin
          BaseValue := Copy(CleanValue, 3, Length(CleanValue));
          IntValue := 0;
          Code := 0;
          if BaseValue = '' then
            Code := 1
          else
            for i := 1 to Length(BaseValue) do
            begin
              if not (BaseValue[i] in ['0'..'7']) then
              begin
                Code := i;
                Break;
              end;
              IntValue := (IntValue shl 3) or (Ord(BaseValue[i]) - Ord('0'));
            end;
        end;
      'B': // binary
        begin
          BaseValue := Copy(CleanValue, 3, Length(CleanValue));
          IntValue := 0;
          Code := 0;
          if BaseValue = '' then
            Code := 1
          else
            for i := 1 to Length(BaseValue) do
            begin
              if not (BaseValue[i] in ['0'..'1']) then
              begin
                Code := i;
                Break;
              end;
              IntValue := (IntValue shl 1) or (Ord(BaseValue[i]) - Ord('0'));
            end;
        end;
    end;

    if Code = 0 then
      Result := TTOMLInteger.Create(IntValue)
    else
      raise ETOMLParserException.CreateFmt('Invalid hex/oct/bin integer: %s', [RawValue]);
  end
  else
  begin
    // 4. Decimal numbers (integers or floating-point numbers)
    SForCheck := CleanValue;
    if (Length(SForCheck) > 0) and CharInSet(SForCheck[1], ['+', '-']) then
      Delete(SForCheck, 1, 1);

    // Decimal numbers must begin with a numeric character
    // (excluding illegal formats such as -.123 or .123).
    if (Length(SForCheck) = 0) or (not CharInSet(SForCheck[1], ['0'..'9'])) then
      raise ETOMLParserException.CreateFmt('Numbers must have an integer part: %s at line %d', [RawValue,
        FCurrentToken.Line]);

    // Leading zeros are prohibited (e.g., 01, 007).
    if (Length(SForCheck) > 1) and (SForCheck[1] = '0') and CharInSet(SForCheck[2], ['0'..'9']) then
      raise ETOMLParserException.CreateFmt('Leading zeros are not allowed in decimal integers: %s', [RawValue]);

    if FCurrentToken.TokenType = ttFloat then
    begin
      Val(CleanValue, FloatValue, Code);
      if Code <> 0 then
        raise ETOMLParserException.CreateFmt('Invalid float: %s', [RawValue]);
      Result := TTOMLFloat.Create(FloatValue, CleanValue);
    end
    else
    begin
      Val(CleanValue, IntValue, Code);
      if Code = 0 then
        Result := TTOMLInteger.Create(IntValue)
      else
        raise ETOMLParserException.CreateFmt('Invalid integer: %s', [RawValue]);
    end;
  end;

  if not Assigned(Result) then
    raise ETOMLParserException.CreateFmt('Failed to parse number: %s', [RawValue]);

  Advance;
end;

function TTOMLParser.ParseBoolean: TTOMLBoolean;
begin
  Result := TTOMLBoolean.Create(FCurrentToken.Value = 'true');
  Advance;
end;

function TTOMLParser.ParseDateTime: TTOMLDateTime;
var
  DateStr: string;
  Year, Month, Day, Hour, Minute, Second, MilliSecond: Word;
  TZHour, TZMinute, TZOffsetMinutes: Integer;
  P: Integer;
  FracStr: string;
  DT: TDateTime;
  HasDate, HasTime, HasTimezone: Boolean;
  DateTimeKind: TTOMLDateTimeKind;
  HasSep: Boolean;
begin
  if FCurrentToken.TokenType <> ttDateTime then
    raise ETOMLParserException.CreateFmt('Expected DateTime but got %s at line %d, column %d', [GetEnumName(TypeInfo
      (TTokenType), Ord(FCurrentToken.TokenType)), FCurrentToken.Line, FCurrentToken.Column]);

  DateStr := FCurrentToken.Value;
  HasDate := False;
  HasTime := False;
  HasTimezone := False;
  TZOffsetMinutes := 0;

  try
    Year := 0;
    Month := 0;
    Day := 0;
    Hour := 0;
    Minute := 0;
    Second := 0;
    MilliSecond := 0;
    P := 1;

    // Parsing the date portion: YYYY-MM-DD
    if (Length(DateStr) >= 10) and (DateStr[5] = '-') and (DateStr[8] = '-') then
    begin
      Year := StrToInt(Copy(DateStr, 1, 4));
      Month := StrToInt(Copy(DateStr, 6, 2));
      Day := StrToInt(Copy(DateStr, 9, 2));
      if (Month < 1) or (Month > 12) then
        raise ETOMLParserException.CreateFmt('Invalid month: %d', [Month]);
      if (Day < 1) or (Day > 31) then
        raise ETOMLParserException.CreateFmt('Invalid day: %d', [Day]);
      HasDate := True;
      P := 11;
    end;

    // Parse the time portion (separated by T or space,
    // or directly parse if there is no date).
    if (P <= Length(DateStr)) and ((UpCase(DateStr[P]) = 'T') or (DateStr[P] = ' ') or (not HasDate)) then
    begin
      HasSep := (UpCase(DateStr[P]) = 'T') or (DateStr[P] = ' ');
      if HasSep then
        Inc(P);

      if (P + 4 <= Length(DateStr)) and (DateStr[P + 2] = ':') then
      begin
        Hour := StrToInt(Copy(DateStr, P, 2));
        Minute := StrToInt(Copy(DateStr, P + 3, 2));
        if Hour > 23 then
          raise ETOMLParserException.CreateFmt('Invalid hour: %d', [Hour]);
        if Minute > 59 then
          raise ETOMLParserException.CreateFmt('Invalid minute: %d', [Minute]);
        HasTime := True;
        P := P + 5;

        // Seconds are optional
        if (P <= Length(DateStr)) and (DateStr[P] = ':') then
        begin
          Inc(P);
          if P + 1 <= Length(DateStr) then
          begin
            Second := StrToInt(Copy(DateStr, P, 2));
            P := P + 2;
            // Decimal seconds optional
            if (P <= Length(DateStr)) and (DateStr[P] = '.') then
            begin
              Inc(P);
              var FracStartPos := P;
              FracStr := '';
              while (P <= Length(DateStr)) and CharInSet(DateStr[P], ['0'..'9']) do
              begin
                FracStr := FracStr + DateStr[P];
                Inc(P);
              end;
              if P = FracStartPos then
                raise ETOMLParserException.Create('Fractional seconds missing digits');
              if Length(FracStr) > 0 then
                MilliSecond := StrToInt(Copy(FracStr + '000', 1, 3));
            end;
          end;
        end;
      end
      else if HasSep then
        // The presence of a 'T' or space separator followed by an invalid
        // time format is considered an error.
        raise ETOMLParserException.Create('DateTime separator must be followed by valid time');
    end;

    // Analyze the time zone portion (Z or +/-HH:MM)
    if P <= Length(DateStr) then
    begin
      if UpCase(DateStr[P]) = 'Z' then
      begin
        HasTimezone := True;
        TZOffsetMinutes := 0;
        Inc(P);
      end
      else if (DateStr[P] = '+') or (DateStr[P] = '-') then
      begin
        var SignChar := DateStr[P];
        // Fixed time zone offset format: [+-]HH:MM (6 characters)
        if P + 5 <= Length(DateStr) then
        begin
          if DateStr[P + 3] <> ':' then
            raise ETOMLParserException.Create('Missing colon in timezone offset');
          if not (CharInSet(DateStr[P + 1], ['0'..'9']) and CharInSet(DateStr[P + 2], ['0'..'9']) and
            CharInSet(DateStr[P + 4], ['0'..'9']) and CharInSet(DateStr[P + 5], ['0'..'9'])) then
            raise ETOMLParserException.Create('Invalid digits in timezone offset');

          TZHour := StrToInt(Copy(DateStr, P + 1, 2));
          TZMinute := StrToInt(Copy(DateStr, P + 4, 2));
          if TZHour > 23 then
            raise ETOMLParserException.CreateFmt('Timezone offset hour out of range: %d', [TZHour]);
          if TZMinute > 59 then
            raise ETOMLParserException.CreateFmt('Timezone offset minute out of range: %d', [TZMinute]);

          TZOffsetMinutes := TZHour * 60 + TZMinute;
          if SignChar = '-' then
            TZOffsetMinutes := -TZOffsetMinutes;
          HasTimezone := True;
          P := P + 6;
        end
        else
          raise ETOMLParserException.Create('Incomplete timezone offset (must be HH:MM)');
      end;
    end;

    // If a string contains any remaining unparsed parts, its format is invalid.
    if P <= Length(DateStr) then
      raise ETOMLParserException.CreateFmt('Malformed datetime trailing characters: "%s"', [Copy(DateStr, P, MaxInt)]);

    // Determine date and time subtypes
    if HasDate and HasTime and HasTimezone then
      DateTimeKind := tdkOffsetDateTime
    else if HasDate and HasTime then
      DateTimeKind := tdkLocalDateTime
    else if HasDate then
      DateTimeKind := tdkLocalDate
    else if HasTime then
      DateTimeKind := tdkLocalTime
    else
      raise ETOMLParserException.Create('Invalid datetime format');

    // Constructing TDateTime Values
    if HasDate then
      DT := EncodeDate(Year, Month, Day)
    else
      DT := 0;

    if HasTime then
      DT := DT + EncodeTime(Hour, Minute, Second, MilliSecond);

    Result := TTOMLDateTime.Create(DT, DateStr, DateTimeKind, TZOffsetMinutes);

  except
    on E: Exception do
      raise ETOMLParserException.CreateFmt('Error parsing datetime: %s at line %d, column %d', [E.Message,
        FCurrentToken.Line, FCurrentToken.Column]);
  end;

  Advance;
end;

function TTOMLParser.ParseArray: TTOMLArray;
begin
  Result := TTOMLArray.Create;
  try
    Expect(ttLBracket);

    while True do
    begin
      // Skip all newlines before elements
      // (TOML allows arrays to span multiple lines).
      while Match(ttNewLine) do
        ;

      // Handling empty arrays [] or ] after a comma at the end.
      if FCurrentToken.TokenType = ttRBracket then
        Break;

      Result.Add(ParseValue);

      while Match(ttNewLine) do
        ;

      // The text ends if there is no comma
      // (single elements without a trailing comma are allowed).
      if not Match(ttComma) then
      begin
        while Match(ttNewLine) do
          ;
        Break;
      end;
      // If a comma is present, continue parsing the next element.
    end;

    Expect(ttRBracket);
  except
    Result.Free;
    raise;
  end;
end;

function TTOMLParser.ParseInlineTable: TTOMLTable;
var
  KeyPair: TTOMLKeyValuePair;
  KeyParts: TArray<string>;
begin
  Result := TTOMLTable.Create;
  Result.IsInline := True; // Inline tables cannot be expanded via table headers.
  try
    Expect(ttLBrace);

    // Skip optional line breaks
    // (TOML 1.1.0 allows line breaks within inline tables)
    while FCurrentToken.TokenType = ttNewLine do
      Advance;

    if FCurrentToken.TokenType <> ttRBrace then
    begin
      repeat
        while FCurrentToken.TokenType = ttNewLine do
          Advance;
        if FCurrentToken.TokenType = ttRBrace then
          Break;

        KeyPair := ParseKeyValue;
        try
          // Composite keys containing the #31 separator
          // require navigation through the key levels.
          if (Pos(#31, KeyPair.Key) > 0) or (KeyPair.Key = #31) then
          begin
            KeyParts := SplitDottedKey(KeyPair.Key);
            SetDottedKey(Result, KeyParts, KeyPair.Value);
          end
          else
            Result.Add(KeyPair.Key, KeyPair.Value);
        except
          KeyPair.Value.Free;
          raise;
        end;

        while FCurrentToken.TokenType = ttNewLine do
          Advance;
      until not Match(ttComma);

      while FCurrentToken.TokenType = ttNewLine do
        Advance;
    end;

    Expect(ttRBrace);
  except
    Result.Free;
    raise;
  end;
end;

function TTOMLParser.ParseKey: string;
var
  i: Integer;
begin
  if FCurrentToken.TokenType = ttString then
  begin
    Result := FCurrentToken.Value;
    Advance;
  end
  else if FCurrentToken.TokenType = ttIdentifier then
  begin
    Result := FCurrentToken.Value;
    Advance;
  end
  else if (FCurrentToken.TokenType = ttInteger) or (FCurrentToken.TokenType = ttFloat) then
  begin
    // Numeric literals can be used as raw keys (e.g., 1 = "one").
    Result := FCurrentToken.Value;
    Advance;
  end
  else if FCurrentToken.TokenType = ttDateTime then
  begin
    // Raw keys for date-like formats: Only [A-Za-z0-9_-] are allowed.
    // Characters containing TZ + . must be enclosed in quotes.
    for i := 1 to Length(FCurrentToken.Value) do
      if not CharInSet(FCurrentToken.Value[i], ['0'..'9', 'a'..'z', 'A'..'Z', '_', '-']) then
        raise ETOMLParserException.CreateFmt('Invalid character "%s" in bare key at line %d, column %d. ' +
          'Did you forget to quote the date-like key?', [FCurrentToken.Value[i], FCurrentToken.Line,
          FCurrentToken.Column]);
    Result := FCurrentToken.Value;
    Advance;
  end
  else
    raise ETOMLParserException.CreateFmt('Expected key (string, identifier, number or date-like) but got %s '
      + 'at line %d, column %d', [GetEnumName(TypeInfo(TTokenType), Ord(FCurrentToken.TokenType)),
      FCurrentToken.Line, FCurrentToken.Column]);
end;

function TTOMLParser.SplitDottedKey(const CompositeKey: string): TArray<string>;
var
  i, Count, Start: Integer;
begin
  // An empty string is treated as a single key.
  if CompositeKey = '' then
  begin
    SetLength(Result, 1);
    Result[0] := '';
    Exit;
  end;

  // Count the number of delimiters to determine the size of the result array.
  Count := 1;
  for i := 1 to Length(CompositeKey) do
    if CompositeKey[i] = #31 then
      Inc(Count);

  SetLength(Result, Count);

  // Manually split the string using #31,
  // keeping the first, last, and empty strings in between.
  Start := 1;
  Count := 0;
  for i := 1 to Length(CompositeKey) do
    if CompositeKey[i] = #31 then
    begin
      Result[Count] := Copy(CompositeKey, Start, i - Start);
      Inc(Count);
      Start := i + 1;
    end;
  Result[Count] := Copy(CompositeKey, Start, Length(CompositeKey) - Start + 1);
end;

procedure TTOMLParser.AddKeyToPath(Path: TList<string>; const Segment: string; WasQuoted: Boolean);
var
  SubParts: TArray<string>;
  j: Integer;
begin
  // When the data is not enclosed in quotes and contains periods
  // (usually generated by Lexer's greedy scan of ttFloat),
  // further splitting is required.
  if (not WasQuoted) and (Pos('.', Segment) > 0) then
  begin
    SubParts := Segment.Split(['.']);
    for j := 0 to High(SubParts) do
      if SubParts[j] <> '' then
        Path.Add(SubParts[j]);
  end
  else
    Path.Add(Segment);
end;

procedure TTOMLParser.AddKeyToPath(Path: TStrings; const Segment: string; WasQuoted: Boolean);
var
  i, Start: Integer;
begin
  if (not WasQuoted) and (Pos('.', Segment) > 0) then
  begin
    Start := 1;
    for i := 1 to Length(Segment) do
      if Segment[i] = '.' then
      begin
        Path.Add(Copy(Segment, Start, i - Start));
        Start := i + 1;
      end;
    Path.Add(Copy(Segment, Start, Length(Segment) - Start + 1));
  end
  else
    Path.Add(Segment);
end;

procedure TTOMLParser.SetDottedKey(RootTable: TTOMLTable; const KeyParts: TArray<string>; Value: TTOMLValue);
var
  CurrentTable: TTOMLTable;
  ExistingValue: TTOMLValue;
  NewTable: TTOMLTable;
  LastKey, KeyPath: string;
  i: Integer;
begin
  if Length(KeyParts) = 0 then
    raise ETOMLParserException.Create('Empty key path');

  CurrentTable := RootTable;
  KeyPath := '';

  // 1. Process each level in the path (except for the last key).
  for i := 0 to High(KeyParts) - 1 do
  begin
    if i > 0 then
      KeyPath := KeyPath + '.'
    else
      KeyPath := '';
    KeyPath := KeyPath + KeyParts[i];

    if CurrentTable.TryGetValue(KeyParts[i], ExistingValue) then
    begin
      if ExistingValue is TTOMLTable then
      begin
        // Inline tables cannot be expanded using the dot key.
        if TTOMLTable(ExistingValue).IsInline then
          raise ETOMLParserException.CreateFmt('Cannot extend inline table "%s"', [KeyParts[i]]);

        // Tables that have been explicitly defined (such as [a])
        // are not allowed to have content appended using ab = 1.
        if not TTOMLTable(ExistingValue).IsImplicit then
          raise ETOMLParserException.CreateFmt('Cannot extend explicitly defined table "%s"', [KeyParts[i]]);

        CurrentTable := TTOMLTable(ExistingValue);
      end
      else
        raise ETOMLParserException.CreateFmt('Cannot navigate through "%s" because it is not a table (type: %s)',
          [KeyPath, GetEnumName(TypeInfo(TTOMLValueType), Ord(ExistingValue.ValueType))]);
    end
    else
    begin
      // An implicit table is created if the path does not exist,
      // allowing subsequent dot keys to continue navigation.
      NewTable := TTOMLTable.Create;
      NewTable.IsImplicit := True;
      try
        CurrentTable.Add(KeyParts[i], NewTable);
        CurrentTable := NewTable;
      except
        NewTable.Free;
        raise;
      end;
    end;
  end;

  // 2. Write the final key value
  LastKey := KeyParts[High(KeyParts)];

  if CurrentTable.TryGetValue(LastKey, ExistingValue) then
  begin
    if KeyPath <> '' then
      KeyPath := KeyPath + '.' + LastKey
    else
      KeyPath := LastKey;
    raise ETOMLParserException.CreateFmt('Cannot redefine key "%s"', [KeyPath]);
  end;

  try
    CurrentTable.Add(LastKey, Value);
  except
    Value.Free;
    raise;
  end;
end;

function TTOMLParser.ParseKeyValue: TTOMLKeyValuePair;
var
  KeyParts: TList<string>;
  Value: TTOMLValue;
  FullKey: string;
  i: Integer;
  IsQuoted: Boolean;
begin
  { Parse key-value pairs.
    Each segment of the key is retrieved separately by ParseKey
    (the lexer has removed the quotes and returned the original content).
    Then concatenate with #31 (ASCII Unit Separator)
    – this adds a valid dot to the key name.
    (e.g., "tt.com") can be preserved intact.
    SplitDottedKey restores each segment using the same #31 delimiter. }
  KeyParts := TList<string>.Create;
  try
    repeat
      IsQuoted := FCurrentToken.TokenType = ttString;
      AddKeyToPath(KeyParts, ParseKey, IsQuoted);
    until not Match(ttDot);

    if KeyParts.Count = 1 then
      FullKey := KeyParts[0]
    else
    begin
      FullKey := KeyParts[0];
      for i := 1 to KeyParts.Count - 1 do
        FullKey := FullKey + #31 + KeyParts[i];
    end;

    Expect(ttEqual);
    Value := ParseValue;
    Result := TTOMLKeyValuePair.Create(FullKey, Value);
  finally
    KeyParts.Free;
  end;
end;

function TTOMLParser.Parse: TTOMLTable;
var
  CurrentTable: TTOMLTable;
  TablePath: TStringList;
  DefinedTables: TStringList;  // The explicitly defined collection of [table] header paths
  DefinedArrays: TStringList;  // The explicitly defined [[array]] header path collection
  i: Integer;
  Key: string;
  Value: TTOMLValue;
  KeyPair: TTOMLKeyValuePair;
  IsArrayOfTables: Boolean;
  ArrayValue: TTOMLArray;
  NewTable: TTOMLTable;
  HeaderKey: string; // The current [header] normalized dot path (separated by #31)

  { Concatenate the TablePath list into a path string separated by #31. }

  function TablePathToKey: string;
  var
    j: Integer;
  begin
    Result := '';
    for j := 0 to TablePath.Count - 1 do
    begin
      if j > 0 then
        Result := Result + #31;
      Result := Result + TablePath[j];
    end;
  end;

begin
  Result := TTOMLTable.Create;
  try
    CurrentTable := Result;
    TablePath := TStringList.Create;
    DefinedTables := TStringList.Create;
    DefinedArrays := TStringList.Create;

    TablePath.CaseSensitive := True;
    DefinedTables.CaseSensitive := True;
    DefinedTables.Sorted := True;
    DefinedArrays.CaseSensitive := True;
    DefinedArrays.Sorted := True;

    try
      while FCurrentToken.TokenType <> ttEOF do
      begin
        case FCurrentToken.TokenType of

          ttLBracket:
            begin
              IsArrayOfTables := False;
              var FirstBracket := FCurrentToken;
              Advance;

              // Detecting [[array]] — the second [ must immediately follow the first [
              if FCurrentToken.TokenType = ttLBracket then
              begin
                if (FCurrentToken.Line <> FirstBracket.Line) or (FCurrentToken.Column <> FirstBracket.Column + 1) then
                  raise ETOMLParserException.Create('Spaces are not allowed between brackets in [[table]] header');
                IsArrayOfTables := True;
                Advance;
              end;

              // Parse the header path
              TablePath.Clear;
              repeat
                var IsQ := (FCurrentToken.TokenType = ttString);
                AddKeyToPath(TablePath, ParseKey, IsQ);
              until not Match(ttDot);

              // Parse the ending brackets
              var FirstClosing := FCurrentToken;
              Expect(ttRBracket);
              if IsArrayOfTables then
              begin
                if FCurrentToken.TokenType <> ttRBracket then
                  raise ETOMLParserException.Create('Expected second "]" for Array of Tables header');
                // The second ] must immediately follow the first ]
                if (FCurrentToken.Line <> FirstClosing.Line) or (FCurrentToken.Column <> FirstClosing.Column + 1) then
                  raise ETOMLParserException.Create('Spaces are not allowed between brackets in [[table]] header');
                Advance;
              end;

              // The header must be followed by a newline or the end of the file must be reached.
              ExpectNewLineOrEOF;

              // Calculate the unique identifier path for this header.
              HeaderKey := TablePathToKey;

              // Check for conflicts with existing definitions.
              if IsArrayOfTables then
              begin
                if DefinedTables.IndexOf(HeaderKey) >= 0 then
                  raise ETOMLParserException.CreateFmt('Cannot define [[%s]] - already a regular table', [HeaderKey.Replace
                    (#31, '.')]);
              end
              else
              begin
                if DefinedTables.IndexOf(HeaderKey) >= 0 then
                  raise ETOMLParserException.CreateFmt('Duplicate table header [%s]', [HeaderKey.Replace(#31, '.')]);
                if DefinedArrays.IndexOf(HeaderKey) >= 0 then
                  raise ETOMLParserException.CreateFmt('Cannot define [%s] - already an array of tables', [HeaderKey.Replace
                    (#31, '.')]);
              end;

              // Path navigation: Entering level by level from the root
              CurrentTable := Result;
              var PathTracker: string := '';

              for i := 0 to TablePath.Count - 1 do
              begin
                Key := TablePath[i];
                if i > 0 then
                  PathTracker := PathTracker + #31
                else
                  PathTracker := '';
                PathTracker := PathTracker + Key;

                var IsLast := (i = TablePath.Count - 1);

                if IsLast and IsArrayOfTables then
                begin
                  // The final section of [[abc]]: Append the new table to the array
                  if CurrentTable.TryGetValue(Key, Value) then
                  begin
                    // Existing arrays must be defined using [[]]
                    // (they cannot be static arrays like a = []).
                    if (Value is TTOMLArray) and (DefinedArrays.IndexOf(PathTracker) < 0) then
                      raise ETOMLParserException.Create('Cannot extend static array');
                    if not (Value is TTOMLArray) then
                      raise ETOMLParserException.Create('Key conflict');
                  end
                  else
                  begin
                    Value := TTOMLArray.Create;
                    CurrentTable.Add(Key, Value);
                  end;

                  NewTable := TTOMLTable.Create;
                  TTOMLArray(Value).Add(NewTable);
                  CurrentTable := NewTable;
                end
                else
                begin
                  // The intermediate level of the path or the final
                  // segment of a normal [abc] sequence.
                  if not CurrentTable.TryGetValue(Key, Value) then
                  begin
                    Value := TTOMLTable.Create;
                    CurrentTable.Add(Key, Value);
                  end;

                  if Value is TTOMLArray then
                  begin
                    // Only arrays defined by [[]] are allowed
                    // to be accessed via the header navigation.
                    if DefinedArrays.IndexOf(PathTracker) < 0 then
                      raise ETOMLParserException.CreateFmt('Cannot navigate into static array "%s"', [Key]);

                    ArrayValue := TTOMLArray(Value);
                    if ArrayValue.Count = 0 then
                      raise ETOMLParserException.Create('Internal error: empty AoT');

                    // Navigate to the latest entry in this array table
                    CurrentTable := TTOMLTable(ArrayValue.Items[ArrayValue.Count - 1]);
                  end
                  else if Value is TTOMLTable then
                  begin
                    // Inline tables cannot be expanded via table headers.
                    if TTOMLTable(Value).IsInline then
                      raise ETOMLParserException.CreateFmt('Cannot extend inline table "%s"', [Key]);

                    CurrentTable := TTOMLTable(Value);
                    // When the final segment is reached,
                    // mark the table as explicitly defined.
                    if IsLast and (not IsArrayOfTables) then
                      CurrentTable.IsImplicit := False;
                  end
                  else
                    raise ETOMLParserException.CreateFmt('Key "%s" is already defined as a scalar', [Key]);
                end;
              end;

              // Record this explicit definition
              if IsArrayOfTables then
              begin
                // Clear the existing sub-table definitions under this AoT
                // (AoT restarts every iteration).
                var SubPrefix := HeaderKey + #31;
                for i := DefinedTables.Count - 1 downto 0 do
                  if Pos(SubPrefix, DefinedTables[i]) = 1 then
                    DefinedTables.Delete(i);
                if DefinedArrays.IndexOf(HeaderKey) < 0 then
                  DefinedArrays.Add(HeaderKey);
              end
              else
                DefinedTables.Add(HeaderKey);
            end;

          ttIdentifier, ttString, ttInteger, ttFloat, ttDateTime:
            begin
              try
                KeyPair := ParseKeyValue;
                ExpectNewLineOrEOF;

                // Record the table path implicitly created by key-value pairs
                // to prevent subsequent redefinition of table headers.
                var KVKeyParts := SplitDottedKey(KeyPair.Key);
                var KVRunningPath := HeaderKey;

                // Record the levels between the dot keys
                // (they correspond to implicitly created tables).
                for i := 0 to High(KVKeyParts) - 1 do
                begin
                  if KVRunningPath <> '' then
                    KVRunningPath := KVRunningPath + #31;
                  KVRunningPath := KVRunningPath + KVKeyParts[i];
                  if DefinedTables.IndexOf(KVRunningPath) < 0 then
                    DefinedTables.Add(KVRunningPath);
                end;

                // If the value itself is an inline table,
                // then the key also defines a table.
                if KeyPair.Value is TTOMLTable then
                begin
                  var FullKVPath := KVRunningPath;
                  if FullKVPath <> '' then
                    FullKVPath := FullKVPath + #31;
                  FullKVPath := FullKVPath + KVKeyParts[High(KVKeyParts)];
                  if DefinedTables.IndexOf(FullKVPath) < 0 then
                    DefinedTables.Add(FullKVPath);
                end;

                // Write the key-value pairs to the current table.W
                try
                  if (Pos(#31, KeyPair.Key) > 0) or (KeyPair.Key = #31) then
                  begin
                    var KeyParts: TArray<string>;
                    KeyParts := SplitDottedKey(KeyPair.Key);
                    SetDottedKey(CurrentTable, KeyParts, KeyPair.Value);
                  end
                  else
                    CurrentTable.Add(KeyPair.Key, KeyPair.Value);
                except
                  KeyPair.Value.Free;
                  raise;
                end;

              except
                on E: ETOMLParserException do
                  raise;
                on E: Exception do
                  raise ETOMLParserException.CreateFmt('Error adding key-value pair: %s at line %d, column %d',
                    [E.Message, FCurrentToken.Line, FCurrentToken.Column]);
              end;
            end;

          ttNewLine:
            Advance;

        else
          raise ETOMLParserException.CreateFmt('Unexpected token type: %s at line %d, column %d', [GetEnumName
            (TypeInfo(TTokenType), Ord(FCurrentToken.TokenType)), FCurrentToken.Line, FCurrentToken.Column]);
        end;
      end;
    finally
      TablePath.Free;
      DefinedTables.Free;
      DefinedArrays.Free;
    end;
  except
    Result.Free;
    raise;
  end;
end;

end.
