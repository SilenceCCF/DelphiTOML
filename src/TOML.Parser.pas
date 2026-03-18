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
Unlike tables explicitly defined in [header]
- Use the IsInline flag for inline tables to prevent subsequent expansion of their content via the table header.
   Comment-aware parsing (optional):
     When APreserveComments = True is passed to TTOMLParser.Create / ParseTOML*,
     the parser collects comments and attaches them to the nearest TOML value:
       CommentBefore   -- blank lines + comment lines that appear BEFORE a key,
                          a section header, or an array element.
       CommentInline   -- the comment that appears on the SAME line as a value
                          (after the value, before the newline).
       CommentTrailing -- comments that appear AFTER the last item and BEFORE the
                          closing ']' (arrays) or the next section header / EOF (tables).
     For the root table:
       CommentBefore   = file-header comment (everything before the first key/section).
       CommentTrailing = file-footer comment (everything after the last key/section).
Key implementation details:
- The segments in the period key are concatenated using #31 (ASCII Unit Separator).
Avoid confusion with valid dot characters in key names (such as "tt.com").
- An intermediate table implicitly created using the IsImplicit flag.
*)

unit TOML.Parser;

interface

uses
  SysUtils, Classes, TOML.Types, Generics.Collections, TypInfo, DateUtils, Math;
{$IF CompilerVersion < 20.0}

function CharInSet(C: Char; const CharSet: TSysCharSet): Boolean; inline;
{$IFEND}

type
  { Token types }
  TTokenType = (ttEOF, ttString, ttMultilineString, ttInteger, ttFloat, ttBoolean, ttDateTime, ttEqual, ttDot,
    ttComma, ttLBracket, ttRBracket, ttLBrace, ttRBrace, ttNewLine, ttWhitespace, ttComment, ttIdentifier);

  TToken = record
    TokenType: TTokenType;
    Value: string;
    Line: Integer;
    Column: Integer;
  end;

  TTOMLKeyValuePair = TPair<string, TTOMLValue>;
  { Lexer — produces tokens including ttComment and ttNewLine tokens when in
    comment-preserving mode.  In normal mode comments are silently skipped. }

  TTOMLLexer = class
  private
    FInput: string;
    FPosition: Integer;
    FLine: Integer;
    FColumn: Integer;
    FPreserveComments: Boolean;
    function IsAtEnd: Boolean;
    function Peek: Char;
    function PeekNext: Char;
    function Advance: Char;
    { Skips horizontal whitespace (space/tab).
      In comment-preserving mode the '#...' comment is returned as a ttComment
      token instead of being discarded. }
    procedure SkipHorizontalWhitespace;
    function ScanString: TToken;
    function ScanNumber: TToken;
    function ScanIdentifier: TToken;
    function ScanDateTime: TToken;
    { Scan a comment token (assumes '#' is the current character). }
    function ScanComment: TToken;
    function IsDigit(C: Char): Boolean;
    function IsAlpha(C: Char): Boolean;
    function IsAlphaNumeric(C: Char): Boolean;
  public
    constructor Create(const AInput: string; APreserveComments: Boolean = False);
    function NextToken: TToken;
    property PreserveComments: Boolean read FPreserveComments;
  end;
  { Parser }

  TTOMLParser = class
  private
    FLexer: TTOMLLexer;
    FCurrentToken: TToken;
    FPeekedToken: TToken;
    FHasPeeked: Boolean;
    FPreserveComments: Boolean;
    { Comment accumulation buffer used when FPreserveComments = True.
      Collects comment lines (and blank lines) until a non-comment token is seen. }
    FPendingComment: string;
    procedure Advance;
    // function Peek: TToken;
    function Match(TokenType: TTokenType): Boolean;
    procedure Expect(TokenType: TTokenType);
    procedure CollectInlineComment(AValue: TTOMLValue);
    { Collect a trailing comment block (comment/blank lines) into a raw string. }
    function CollectTrailingComment: string;
    function ParseValue: TTOMLValue;
    function ParseString: TTOMLString;
    function ParseNumber: TTOMLValue;
    function ParseBoolean: TTOMLBoolean;
    function ParseDateTime: TTOMLDateTime;
    function ParseArray: TTOMLArray;
    function ParseInlineTable: TTOMLTable;
    function ParseKey: string;
    function ParseKeyValue: TTOMLKeyValuePair;
    function SplitDottedKey(const CompositeKey: string): TArray<string>;
    procedure AddKeyToPath(Path: TList<string>; const Segment: string; WasQuoted: Boolean); overload;
    procedure AddKeyToPath(Path: TStrings; const Segment: string; WasQuoted: Boolean); overload;
    procedure SetDottedKey(RootTable: TTOMLTable; const KeyParts: TArray<string>; Value: TTOMLValue);
    procedure ExpectNewLineOrEOF;
  public
    constructor Create(const AInput: string; APreserveComments: Boolean = False);
    destructor Destroy; override;
    function Parse: TTOMLTable;
  end;
{ Convenience functions }

function ParseTOMLString(const ATOML: string; APreserveComments: Boolean = False): TTOMLTable;

function ParseTOMLFile(const AFileName: string; APreserveComments: Boolean = False): TTOMLTable;

implementation
{$IF CompilerVersion < 20.0}

function CharInSet(C: Char; const CharSet: TSysCharSet): Boolean;
begin
  Result := C in CharSet;
end;
{$IFEND}
{ =========================================================================
  ParseTOML helpers
  ========================================================================= }

function ParseTOMLString(const ATOML: string; APreserveComments: Boolean): TTOMLTable;
var
  Parser: TTOMLParser;
begin
  Parser := TTOMLParser.Create(ATOML, APreserveComments);
  try
    Result := Parser.Parse;
  except
    Result := nil;
  end;
  Parser.Free;
end;

function ParseTOMLFile(const AFileName: string; APreserveComments: Boolean): TTOMLTable;
var
  Stream: TFileStream;
  BOM: array[0..2] of Byte;
  BytesRead: Integer;
  Encoding: TEncoding;
  SL: TStringList;
begin
  Stream := TFileStream.Create(AFileName, fmOpenRead or fmShareDenyNone);
  try
    BytesRead := Stream.Read(BOM, 3);
    Stream.Position := 0;
    if (BytesRead >= 3) and (BOM[0] = $EF) and (BOM[1] = $BB) and (BOM[2] = $BF) then
      Encoding := TEncoding.UTF8
    else if (BytesRead >= 2) and (BOM[0] = $FF) and (BOM[1] = $FE) then
      Encoding := TEncoding.Unicode
    else if (BytesRead >= 2) and (BOM[0] = $FE) and (BOM[1] = $FF) then
      Encoding := TEncoding.BigEndianUnicode
    else
      Encoding := TEncoding.UTF8;
    SL := TStringList.Create;
    try
      SL.LoadFromStream(Stream, Encoding);
      Result := ParseTOMLString(SL.Text, APreserveComments);
    except
      Result := nil;
    end;
    SL.Free;
  except
    Result := nil;
  end;
  Stream.Free;
end;
{ =========================================================================
  TTOMLLexer
  ========================================================================= }

constructor TTOMLLexer.Create(const AInput: string; APreserveComments: Boolean);
begin
  inherited Create;
  FInput := AInput;
  FPosition := 1;
  FLine := 1;
  FColumn := 1;
  FPreserveComments := APreserveComments;
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

procedure TTOMLLexer.SkipHorizontalWhitespace;
begin
  while not IsAtEnd and CharInSet(Peek, [' ', #9, #$FEFF]) do
    Advance;
end;

function TTOMLLexer.ScanComment: TToken;
var
  CommentText: string;
  Ch: Char;
  OrdCh: Integer;
begin
  // Current character is '#'
  CommentText := '#';
  Advance; // consume '#'
  while not IsAtEnd and (Peek <> #10) and (Peek <> #13) do
  begin
    Ch := Peek;
    OrdCh := Ord(Ch);
    if (OrdCh <= 8) or ((OrdCh >= 11) and (OrdCh <= 31)) or (OrdCh = 127) then
      raise ETOMLParserException.CreateFmt('Control character U+%.4X is not allowed in comments', [OrdCh]);
    CommentText := CommentText + Advance;
  end;
  Result.TokenType := ttComment;
  Result.Value := CommentText;
  Result.Line := FLine;
  Result.Column := FColumn;
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
  if (Peek = QuoteChar) and (PeekNext = QuoteChar) then
  begin
    IsMultiline := True;
    Advance;
    Advance;
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
    if IsMultiline then
    begin
      if Peek = QuoteChar then
      begin
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
    if (not IsLiteral) and (Peek = '\') then
    begin
      if IsMultiline then
      begin
        var SlashPos := FPosition + 1;
        while (SlashPos <= Length(FInput)) and CharInSet(FInput[SlashPos], [' ', #9]) do
          Inc(SlashPos);
        if (SlashPos <= Length(FInput)) and CharInSet(FInput[SlashPos], [#10, #13]) then
        begin
          Advance;
          while not IsAtEnd and CharInSet(Peek, [' ', #9, #10, #13]) do
            Advance;
          Continue;
        end;
      end;
      Advance;
      case Peek of
        'b':
          TempValue := TempValue + #8;
        'f':
          TempValue := TempValue + #12;
        'n':
          TempValue := TempValue + #10;
        'r':
          TempValue := TempValue + #13;
        't':
          TempValue := TempValue + #9;
        '\':
          TempValue := TempValue + '\';
        '"':
          TempValue := TempValue + '"';
        '''':
          TempValue := TempValue + '''';
        'e':
          TempValue := TempValue + #27;
        'x':
          begin
            Advance;
            var HexStr := '';
            for j := 1 to 2 do
            begin
              if IsAtEnd or not CharInSet(Peek, ['0'..'9', 'A'..'F', 'a'..'f']) then
                raise ETOMLParserException.Create('Invalid hex escape');
              HexStr := HexStr + Advance;
            end;
            TempValue := TempValue + Char(StrToInt('$' + HexStr));
            Continue;
          end;
        'u', 'U':
          begin
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
      Advance;
    end
    else
    begin
      var Ch := Peek;
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
        TempValue := TempValue + #10;
      end
      else
      begin
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

  procedure ConsumeDigits(const AllowedDigits: TSysCharSet);
  begin
    while (not IsAtEnd) and (CharInSet(Peek, AllowedDigits) or (Peek = '_')) do
    begin
      if Peek = '_' then
      begin
        if (TempValue = '') or not CharInSet(TempValue[Length(TempValue)], AllowedDigits) then
          raise ETOMLParserException.Create('Invalid underscore placement');
        TempValue := TempValue + Advance;
        if IsAtEnd or not CharInSet(Peek, AllowedDigits) then
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
  if CharInSet(Peek, ['+', '-']) then
  begin
    HasSign := True;
    TempValue := TempValue + Advance;
  end;
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
      raise ETOMLParserException.CreateFmt('Invalid identifier: %s', [FullVal]);
  end;
  if (Peek = '0') and not IsAtEnd and CharInSet(PeekNext, ['x', 'o', 'b']) then
  begin
    if HasSign then
      raise ETOMLParserException.Create('Signs not allowed for hex/octal/binary integers');
    Ch := PeekNext;
    TempValue := TempValue + Advance;
    TempValue := TempValue + Advance;
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
  ConsumeDigits(['0'..'9']);
  if (Peek = '.') and IsDigit(PeekNext) then
  begin
    IsFloat := True;
    TempValue := TempValue + Advance;
    ConsumeDigits(['0'..'9']);
  end;
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
  while not IsAtEnd and (IsAlphaNumeric(Peek) or (Peek = '-')) do
    Result.Value := Result.Value + Advance;
  Result.TokenType := ttIdentifier;
  Result.Line := FLine;
  Result.Column := StartColumn;
end;

function TTOMLLexer.ScanDateTime: TToken;
var
  StartColumn, StartPos, StartLine: Integer;
  HasTime, HasTimezone, HasDate: Boolean;
  TempValue: string;

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
  if ScanDigits(4) and (Peek = '-') then
  begin
    TempValue := TempValue + Advance;
    if ScanDigits(2) and (Peek = '-') then
    begin
      TempValue := TempValue + Advance;
      if ScanDigits(2) then
        HasDate := True;
    end;
  end;
  if HasDate and ((UpCase(Peek) = 'T') or (Peek = ' ')) then
  begin
    var CanContinue := False;
    if UpCase(Peek) = 'T' then
      CanContinue := True
    else if Peek = ' ' then
    begin
      var NextPos := FPosition + 1;
      if NextPos + 4 <= Length(FInput) then
        CanContinue := IsDigit(FInput[NextPos]) and IsDigit(FInput[NextPos + 1]) and (FInput[NextPos + 2] =
          ':') and IsDigit(FInput[NextPos + 3]) and IsDigit(FInput[NextPos + 4]);
    end;
    if CanContinue then
    begin
      TempValue := TempValue + Advance;
      if ScanDigits(2) and (Peek = ':') then
      begin
        TempValue := TempValue + Advance;
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
  end
  else if not HasDate then
  begin
    FPosition := StartPos;
    FLine := StartLine;
    FColumn := StartColumn;
    TempValue := '';
    if ScanDigits(2) and (Peek = ':') then
    begin
      TempValue := TempValue + Advance;
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
  if HasTime and CharInSet(UpCase(Peek), ['Z', '+', '-']) then
  begin
    if UpCase(Peek) = 'Z' then
    begin
      TempValue := TempValue + Advance;
      HasTimezone := True;
    end
    else
    begin
      TempValue := TempValue + Advance;
      while not IsAtEnd and CharInSet(Peek, ['0'..'9', ':']) do
        TempValue := TempValue + Advance;
    end;
  end;
  if HasDate or HasTime then
    Result.TokenType := ttDateTime
  else
    Result.TokenType := ttInteger;
  Result.Value := TempValue;
  Result.Line := FLine;
  Result.Column := StartColumn;
end;

function TTOMLLexer.NextToken: TToken;
var
  SavePos, SaveLine, SaveCol: Integer;
begin
  { Skip horizontal whitespace unconditionally. }
  SkipHorizontalWhitespace;
  Result.Line := FLine;
  Result.Column := FColumn;
  if IsAtEnd then
  begin
    Result.TokenType := ttEOF;
    Result.Value := '';
    Exit;
  end;
  case Peek of
    '#':
      begin
        if FPreserveComments then
          Exit(ScanComment)
        else
        begin
          // Discard the comment
          while not IsAtEnd and (Peek <> #10) and (Peek <> #13) do
          begin
            var Ch := Peek;
            var OrdCh := Ord(Ch);
            if (OrdCh <= 8) or ((OrdCh >= 11) and (OrdCh <= 31)) or (OrdCh = 127) then
              raise ETOMLParserException.CreateFmt('Control character U+%.4X is not allowed in comments', [OrdCh]);
            Advance;
          end;
          // Recurse to get the next real token
          Exit(NextToken);
        end;
      end;
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
        if not IsAtEnd and (IsAlpha(Peek) or (Peek = '-')) then
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
{ =========================================================================
  TTOMLParser
  ========================================================================= }

constructor TTOMLParser.Create(const AInput: string; APreserveComments: Boolean);
begin
  inherited Create;
  FPreserveComments := APreserveComments;
  FLexer := TTOMLLexer.Create(AInput, APreserveComments);
  FHasPeeked := False;
  FPendingComment := '';
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
//function TTOMLParser.Peek: TToken;
//begin
//  if not FHasPeeked then
//  begin
//    FPeekedToken := FLexer.NextToken;
//    FHasPeeked := True;
//  end;
//  Result := FPeekedToken;
//end;

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
    raise ETOMLParserException.CreateFmt('Expected %s but got %s at line %d, column %d', [GetEnumName(TypeInfo
      (TTokenType), Ord(TokenType)), GetEnumName(TypeInfo(TTokenType), Ord(FCurrentToken.TokenType)),
      FCurrentToken.Line, FCurrentToken.Column]);
  Advance;
end;

procedure TTOMLParser.CollectInlineComment(AValue: TTOMLValue);
begin
  if not FPreserveComments then
  begin
    // Discard any comment that might follow on the same line
    if FCurrentToken.TokenType = ttComment then
      Advance;
    Exit;
  end;
  if FCurrentToken.TokenType = ttComment then
  begin
    if Assigned(AValue) then
      AValue.CommentInline := FCurrentToken.Value;
    Advance;
  end;
end;

function TTOMLParser.CollectTrailingComment: string;
begin
  Result := '';
  if not FPreserveComments then
  begin
    while FCurrentToken.TokenType in [ttNewLine, ttComment] do
      Advance;
    Exit;
  end;
  while FCurrentToken.TokenType in [ttNewLine, ttComment] do
  begin
    if FCurrentToken.TokenType = ttComment then
    begin
      if Result = '' then
        Result := FCurrentToken.Value
      else if Result[Length(Result)] = #10 then
        Result := Result + FCurrentToken.Value
      else
        Result := Result + #10 + FCurrentToken.Value;
    end
    else // ttNewLine
    begin
      if Result <> '' then
        Result := Result + #10;
    end;
    Advance;
  end;
end;

procedure TTOMLParser.ExpectNewLineOrEOF;
begin
  if FCurrentToken.TokenType = ttComment then
    CollectInlineComment(nil); // discard; the caller sets inline after this
  if not (FCurrentToken.TokenType in [ttNewLine, ttEOF]) then
    raise ETOMLParserException.CreateFmt('Only one expression per line. Unexpected "%s" at line %d, column %d',
      [FCurrentToken.Value, FCurrentToken.Line, FCurrentToken.Column]);
  if FCurrentToken.TokenType = ttNewLine then
    Advance;
end;
{ -------------------------------------------------------------------------
  Value parsers
  ------------------------------------------------------------------------- }

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
    raise ETOMLParserException.CreateFmt('Unexpected token %s at line %d, column %d', [GetEnumName(TypeInfo(TTokenType),
      Ord(FCurrentToken.TokenType)), FCurrentToken.Line, FCurrentToken.Column]);
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
  CleanValue := '';
  for i := 1 to Length(RawValue) do
    if RawValue[i] <> '_' then
      CleanValue := CleanValue + RawValue[i];
  IntValue := 0;
  Code := 0;
  Result := nil;
  IsHexOctBin := (Length(CleanValue) >= 2) and (CleanValue[1] = '0') and CharInSet(CleanValue[2], ['x', 'o', 'b']);
  if IsHexOctBin then
  begin
    case UpCase(CleanValue[2]) of
      'X':
        begin
          BaseValue := '$' + Copy(CleanValue, 3, MaxInt);
          Val(BaseValue, IntValue, Code);
        end;
      'O':
        begin
          BaseValue := Copy(CleanValue, 3, MaxInt);
          IntValue := 0;
          Code := 0;
          if BaseValue = '' then
            Code := 1
          else
            for i := 1 to Length(BaseValue) do
            begin
//              if not (BaseValue[i] in ['0'..'7']) then
              if not CharInSet(BaseValue[i], ['0'..'7']) then
              begin
                Code := i;
                Break;
              end;
              IntValue := (IntValue shl 3) or (Ord(BaseValue[i]) - Ord('0'));
            end;
        end;
      'B':
        begin
          BaseValue := Copy(CleanValue, 3, MaxInt);
          IntValue := 0;
          Code := 0;
          if BaseValue = '' then
            Code := 1
          else
            for i := 1 to Length(BaseValue) do
            begin
           // if not (BaseValue[i] in ['0', '1']) then
              if not CharInSet(BaseValue[i], ['0'..'1']) then
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
    SForCheck := CleanValue;
    if (Length(SForCheck) > 0) and CharInSet(SForCheck[1], ['+', '-']) then
      Delete(SForCheck, 1, 1);
    if (Length(SForCheck) = 0) or not CharInSet(SForCheck[1], ['0'..'9']) then
      raise ETOMLParserException.CreateFmt('Numbers must have an integer part: %s', [RawValue]);
    if (Length(SForCheck) > 1) and (SForCheck[1] = '0') and CharInSet(SForCheck[2], ['0'..'9']) then
      raise ETOMLParserException.CreateFmt('Leading zeros not allowed: %s', [RawValue]);
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
  Year, Month, Day: Word;
  Hour, Minute: Word;
  Second, MilliSec: Word;
  TZHour, TZMin: Integer;
  TZOffset: Integer;
  P: Integer;
  FracStr: string;
  DT: TDateTime;
  HasDate, HasTime, HasTZ: Boolean;
  Kind: TTOMLDateTimeKind;
  HasSep: Boolean;
begin
  if FCurrentToken.TokenType <> ttDateTime then
    raise ETOMLParserException.CreateFmt('Expected DateTime but got %s at line %d', [GetEnumName(TypeInfo(TTokenType),
      Ord(FCurrentToken.TokenType)), FCurrentToken.Line]);
  DateStr := FCurrentToken.Value;
  HasDate := False;
  HasTime := False;
  HasTZ := False;
  TZOffset := 0;
  try
    Year := 0;
    Month := 0;
    Day := 0;
    Hour := 0;
    Minute := 0;
    Second := 0;
    MilliSec := 0;
    P := 1;
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
    if (P <= Length(DateStr)) and ((UpCase(DateStr[P]) = 'T') or (DateStr[P] = ' ') or not HasDate) then
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
        if (P <= Length(DateStr)) and (DateStr[P] = ':') then
        begin
          Inc(P);
          if P + 1 <= Length(DateStr) then
          begin
            Second := StrToInt(Copy(DateStr, P, 2));
            P := P + 2;
            if (P <= Length(DateStr)) and (DateStr[P] = '.') then
            begin
              Inc(P);
              var FracStart := P;
              FracStr := '';
              while (P <= Length(DateStr)) and CharInSet(DateStr[P], ['0'..'9']) do
              begin
                FracStr := FracStr + DateStr[P];
                Inc(P);
              end;
              if P = FracStart then
                raise ETOMLParserException.Create('Fractional seconds missing digits');
              if Length(FracStr) > 0 then
                MilliSec := StrToInt(Copy(FracStr + '000', 1, 3));
            end;
          end;
        end;
      end
      else if HasSep then
        raise ETOMLParserException.Create('DateTime separator must be followed by valid time');
    end;
    if P <= Length(DateStr) then
    begin
      if UpCase(DateStr[P]) = 'Z' then
      begin
        HasTZ := True;
        TZOffset := 0;
        Inc(P);
      end
      else if (DateStr[P] = '+') or (DateStr[P] = '-') then
      begin
        var SignCh := DateStr[P];
        if P + 5 <= Length(DateStr) then
        begin
          if DateStr[P + 3] <> ':' then
            raise ETOMLParserException.Create('Missing colon in timezone offset');
          if not (CharInSet(DateStr[P + 1], ['0'..'9']) and CharInSet(DateStr[P + 2], ['0'..'9']) and
            CharInSet(DateStr[P + 4], ['0'..'9']) and CharInSet(DateStr[P + 5], ['0'..'9'])) then
            raise ETOMLParserException.Create('Invalid digits in timezone offset');

          TZHour := StrToInt(Copy(DateStr, P + 1, 2));
          TZMin := StrToInt(Copy(DateStr, P + 4, 2));

            // TOML/RFC3339 hour: 00-23, minute: 00-59
          if (TZHour < 0) or (TZHour > 23) then
            raise ETOMLParserException.CreateFmt('Timezone offset hour out of range [00-23]: %d', [TZHour]);

          if (TZMin < 0) or (TZMin > 59) then
            raise ETOMLParserException.CreateFmt('Timezone offset minute out of range [00-59]: %d', [TZMin]);

          TZOffset := TZHour * 60 + TZMin;
          if SignCh = '-' then
            TZOffset := -TZOffset;
          HasTZ := True;
          P := P + 6;
        end
        else
          raise ETOMLParserException.Create('Incomplete timezone offset (must be HH:MM)');
      end;
    end;
    if P <= Length(DateStr) then
      raise ETOMLParserException.CreateFmt('Trailing chars in datetime: "%s"', [Copy(DateStr, P, MaxInt)]);
    if HasDate and HasTime and HasTZ then
      Kind := tdkOffsetDateTime
    else if HasDate and HasTime then
      Kind := tdkLocalDateTime
    else if HasDate then
      Kind := tdkLocalDate
    else if HasTime then
      Kind := tdkLocalTime
    else
      raise ETOMLParserException.Create('Invalid datetime format');
    if HasDate then
      DT := EncodeDate(Year, Month, Day)
    else
      DT := 0;
    if HasTime then
      DT := DT + EncodeTime(Hour, Minute, Second, MilliSec);
    Result := TTOMLDateTime.Create(DT, DateStr, Kind, TZOffset);
  except
    on E: Exception do
      raise ETOMLParserException.CreateFmt('Error parsing datetime: %s at line %d', [E.Message, FCurrentToken.Line]);
  end;
  Advance;
end;
{ -------------------------------------------------------------------------
  Array parser — with comment preservation
  TOML v1.1.0: arrays may span multiple lines; trailing comma is allowed;
  comments are allowed after each element (before the newline) and inside
  multi-line arrays.
  ------------------------------------------------------------------------- }

function TTOMLParser.ParseArray: TTOMLArray;
var
  Elem: TTOMLValue;
  ElemCommentBefore: string;
begin
  Result := TTOMLArray.Create;
  try
    Expect(ttLBracket);
    while True do
    begin
      // Skip newlines / collect inter-element comments
      ElemCommentBefore := '';
      if FPreserveComments then
      begin
        while FCurrentToken.TokenType in [ttNewLine, ttComment] do
        begin
          if FCurrentToken.TokenType = ttComment then
          begin
            if ElemCommentBefore <> '' then
              ElemCommentBefore := ElemCommentBefore + #10;
            ElemCommentBefore := ElemCommentBefore + FCurrentToken.Value;
          end
          else
          begin
            if ElemCommentBefore <> '' then
              ElemCommentBefore := ElemCommentBefore + #10;
          end;
          Advance;
        end;
      end
      else
        while Match(ttNewLine) do
        ;
      // Trailing comment or ']'
      if FCurrentToken.TokenType = ttRBracket then
      begin
        // Absorb any comment before ']' as trailing
        if FPreserveComments and (ElemCommentBefore <> '') then
          Result.CommentTrailing := ElemCommentBefore;
        Break;
      end;
      Elem := ParseValue;
      if FPreserveComments and (ElemCommentBefore <> '') then
        Elem.CommentBefore := ElemCommentBefore;
      // Collect inline comment after the element value (before comma/newline)
      if FPreserveComments then
        CollectInlineComment(Elem);
      // Skip newlines after the element
      while Match(ttNewLine) do
        ;
      Result.Add(Elem);
      // Trailing comma?
      if not Match(ttComma) then
      begin
        // No comma: collect trailing comments until ']'
        if FPreserveComments then
        begin
          var TC := CollectTrailingComment;
          if TC <> '' then
            Result.CommentTrailing := TC;
        end
        else
          while Match(ttNewLine) do
          ;
        Break;
      end;
      // After comma, there may be a comment on the same line
      if FPreserveComments and (FCurrentToken.TokenType = ttComment) then
      begin
        // Attach to the element just parsed (override inline if needed)
        if Elem.CommentInline = '' then
          Elem.CommentInline := FCurrentToken.Value;
        Advance;
      end;
    end;
    Expect(ttRBracket);
  except
    Result.Free;
    raise;
  end;
end;
{ -------------------------------------------------------------------------
  Inline-table parser — with comment preservation
  TOML v1.1.0: inline tables may span multiple lines; trailing comma is allowed;
  comments are allowed after each key-value pair.
  ------------------------------------------------------------------------- }

function TTOMLParser.ParseInlineTable: TTOMLTable;
(* Design notes
  ─────────────────────────────────────────────────────────────────────────────
  FPendingComment is a *shared* parser-level field used by the top-level Parse
  loop and also reset inside ParseInlineTable in the previous implementation.
  That caused two classes of bugs:
    A) Nesting bug – when an inner ParseInlineTable recursion is triggered via
       ParseValue → ParseInlineTable, the inner call wiped FPendingComment that
       the outer call had just accumulated for the current key's CommentBefore.
    B) Trailing-comment loss – after the last comma (trailing comma) the loop
       jumped back to the top, reset FPendingComment := '', consumed the
       following comments into it, then hit '}' and broke out — discarding
       everything that had been accumulated.
  Fix: ParseInlineTable uses *only local variables* for comment accumulation.
  FPendingComment is saved on entry and restored on exit so that any outer
  context (top-level Parse loop or outer ParseInlineTable call) is unaffected.
  ─────────────────────────────────────────────────────────────────────────────
*)
var
  KeyPair: TTOMLKeyValuePair;
  KeyParts: TArray<string>;
  // All comment buffers are LOCAL — never touch FPendingComment directly.
  LocalPending: string;    // pre-key comment block (CommentBefore candidate)
  OpenBraceCmt: string;    // comment on the '{' opening line
  TrailingCmt: string;    // comment after last entry, before '}'
  SavedPending: string;    // FPendingComment value on entry — restored on exit

  { Append a token's contribution to a local comment buffer, using the same
    accumulation rules as the rest of the parser. }

  procedure AppendToLocal(var Buf: string; const Tok: TToken);
  begin
    if Tok.TokenType = ttComment then
    begin
      if Buf = '' then
        Buf := Tok.Value
      else if Buf[Length(Buf)] = #10 then
        Buf := Buf + Tok.Value
      else
        Buf := Buf + #10 + Tok.Value;
    end
    else // ttNewLine
    begin
      if Buf <> '' then
        Buf := Buf + #10;
    end;
  end;
  { Collect comment/newline tokens into Buf; stop at the first token that is
    neither a comment nor a newline. }

  procedure CollectLocal(var Buf: string);
  begin
    while FCurrentToken.TokenType in [ttNewLine, ttComment] do
    begin
      AppendToLocal(Buf, FCurrentToken);
      Advance;
    end;
  end;
  { Collect comment/newline tokens into a local trailing-comment buffer.
    Blank lines at the very start are included (unlike CollectLocal which
    skips leading blank lines — actually both behave the same here because
    AppendToLocal for ttNewLine only appends when Buf is non-empty). }

  function CollectLocalTrailing: string;
  begin
    Result := '';
    while FCurrentToken.TokenType in [ttNewLine, ttComment] do
    begin
      AppendToLocal(Result, FCurrentToken);
      Advance;
    end;
    // Trim a trailing #10 that the last newline token may have added (it
    // would produce a spurious blank line at the end of the block).
    while (Result <> '') and (Result[Length(Result)] = #10) do
      SetLength(Result, Length(Result) - 1);
  end;

begin
  Result := TTOMLTable.Create;
  Result.IsInline := True;

  // Save and neutralise FPendingComment so that recursive calls cannot
  // clobber the outer accumulation context.
  SavedPending := FPendingComment;
  FPendingComment := '';

  try
    Expect(ttLBrace);

    // ── Comment on the '{' line ────────────────────────────────────────────
    // e.g.  key = { # this comment
    //          inner = 1
    //        }
    // The comment travels as the first key's CommentBefore (serialiser will
    // output it on the line after '{', i.e. "moved to next line").
    OpenBraceCmt := '';
    if FPreserveComments and (FCurrentToken.TokenType = ttComment) then
    begin
      OpenBraceCmt := FCurrentToken.Value;
      Advance;
    end;

    // Skip the newline that ends the '{' line (or any leading blank lines).
    while FCurrentToken.TokenType = ttNewLine do
      Advance;

    if FCurrentToken.TokenType = ttRBrace then
    begin
      // Empty inline table  {}  — the open-brace comment (if any) becomes
      // the trailing comment so the serialiser can round-trip it.
      if FPreserveComments and (OpenBraceCmt <> '') then
        Result.CommentTrailing := OpenBraceCmt;
    end
    else
    begin
      var IsFirst := True;
      repeat
        // ── Pre-key comment block (CommentBefore) ─────────────────────────
        LocalPending := '';
        if FPreserveComments then
        begin
          // On the first iteration, seed LocalPending with the open-brace
          // comment so it ends up as the first key's CommentBefore.
          if IsFirst and (OpenBraceCmt <> '') then
          begin
            LocalPending := OpenBraceCmt;
            OpenBraceCmt := '';
          end;
          // Now collect any further comment/blank lines before the key.
          CollectLocal(LocalPending);
        end
        else
          while FCurrentToken.TokenType = ttNewLine do
            Advance;

        // If we consumed everything and hit '}', the accumulated LocalPending
        // is trailing content (last-comma case: trailing comma then comments
        // then '}'). Save it as CommentTrailing and stop.
        if FCurrentToken.TokenType = ttRBrace then
        begin
          if FPreserveComments and (LocalPending <> '') then
            Result.CommentTrailing := LocalPending;
          Break;
        end;

        // ── Parse the key = value pair ────────────────────────────────────
        // ParseKeyValue may recurse into ParseValue → ParseInlineTable.
        // That inner call saves/restores FPendingComment itself, so we are
        // safe.  After it returns, FPendingComment is still '' (we cleared
        // it on entry and the inner call restores its own saved value).
        KeyPair := ParseKeyValue;
        IsFirst := False;
        try
          // Attach the accumulated pre-key comments.
          if FPreserveComments and (LocalPending <> '') then
            KeyPair.Value.CommentBefore := LocalPending;

          // ── Inline comment directly after the value ────────────────────
          // e.g.  key = val # inline comment
          // Note: CollectInlineComment uses FCurrentToken, not FPendingComment.
          if FPreserveComments then
            CollectInlineComment(KeyPair.Value);

          // Skip the newline that ends the value line.
          if FPreserveComments then
            while FCurrentToken.TokenType = ttNewLine do
              Advance;

          // Store the key-value in the table.
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

        // In non-preserve mode skip any trailing newlines before the comma.
        if not FPreserveComments then
          while FCurrentToken.TokenType = ttNewLine do
            Advance;

        // ── Comma (optional trailing comma in TOML 1.1) ───────────────────
        if not Match(ttComma) then
        begin
          // No comma — collect everything up to '}' as CommentTrailing.
          if FPreserveComments then
          begin
            while FCurrentToken.TokenType = ttNewLine do
              Advance;
            TrailingCmt := CollectLocalTrailing;
            if TrailingCmt <> '' then
              Result.CommentTrailing := TrailingCmt;
          end
          else
            while FCurrentToken.TokenType = ttNewLine do
              Advance;
          Break;
        end;

        // ── Comment after the comma (same line) ───────────────────────────
        // e.g.  key = val, # comment after comma
        // This belongs to the just-parsed value as CommentInline.
        if FPreserveComments and (FCurrentToken.TokenType = ttComment) then
        begin
          if KeyPair.Value.CommentInline = '' then
            KeyPair.Value.CommentInline := FCurrentToken.Value;
          Advance;
        end;

        // Skip the newline after the comma (or after the post-comma comment).
        if FPreserveComments then
          while FCurrentToken.TokenType = ttNewLine do
            Advance;

      until False;
    end;

    Expect(ttRBrace);
  except
    Result.Free;
    // Restore FPendingComment even on exception so the outer context is clean.
    FPendingComment := SavedPending;
    raise;
  end;

  // Restore the outer FPendingComment context.
  FPendingComment := SavedPending;
end;
{ -------------------------------------------------------------------------
  Key / key-value parsers (unchanged from original)
  ------------------------------------------------------------------------- }

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
  else if FCurrentToken.TokenType in [ttInteger, ttFloat] then
  begin
    Result := FCurrentToken.Value;
    Advance;
  end
  else if FCurrentToken.TokenType = ttDateTime then
  begin
    for i := 1 to Length(FCurrentToken.Value) do
      if not CharInSet(FCurrentToken.Value[i], ['0'..'9', 'a'..'z', 'A'..'Z', '_', '-']) then
        raise ETOMLParserException.CreateFmt('Invalid character "%s" in bare key at line %d, column %d', [FCurrentToken.Value
          [i], FCurrentToken.Line, FCurrentToken.Column]);
    Result := FCurrentToken.Value;
    Advance;
  end
  else
    raise ETOMLParserException.CreateFmt('Expected key but got %s at line %d, column %d', [GetEnumName(TypeInfo
      (TTokenType), Ord(FCurrentToken.TokenType)), FCurrentToken.Line, FCurrentToken.Column]);
end;

function TTOMLParser.SplitDottedKey(const CompositeKey: string): TArray<string>;
var
  i, Count, Start: Integer;
begin
  if CompositeKey = #31 then
  begin
    SetLength(Result, 2);
    Result[0] := '';
    Result[1] := '';
    Exit;
  end;
  if CompositeKey = '' then
  begin
    SetLength(Result, 1);
    Result[0] := '';
    Exit;
  end;
  Count := 1;
  for i := 1 to Length(CompositeKey) do
    if CompositeKey[i] = #31 then
      Inc(Count);
  SetLength(Result, Count);
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
  if (not WasQuoted) and (Pos('.', Segment) > 0) then
  begin
    SubParts := Segment.Split(['.']);
    for j := 0 to High(SubParts) do
//      if SubParts[j] <> '' then
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
  for i := 0 to High(KeyParts) - 1 do
  begin
    if i > 0 then
      KeyPath := KeyPath + '.';
    KeyPath := KeyPath + KeyParts[i];
    if CurrentTable.TryGetValue(KeyParts[i], ExistingValue) then
    begin
      if ExistingValue is TTOMLTable then
      begin
        if TTOMLTable(ExistingValue).IsInline then
          raise ETOMLParserException.CreateFmt('Cannot extend inline table "%s"', [KeyParts[i]]);
        if not TTOMLTable(ExistingValue).IsImplicit then
          raise ETOMLParserException.CreateFmt('Cannot extend explicitly defined table "%s"', [KeyParts[i]]);
        CurrentTable := TTOMLTable(ExistingValue);
      end
      else
        raise ETOMLParserException.CreateFmt('"%s" is not a table', [KeyPath]);
    end
    else
    begin
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
  LastKey := KeyParts[High(KeyParts)];
  if CurrentTable.TryGetValue(LastKey, ExistingValue) then
    raise ETOMLParserException.CreateFmt('Cannot redefine key "%s"', [LastKey]);
  try
    CurrentTable.Add(LastKey, Value);
  except
    Value.Free;
    raise;
  end;
end;

function TTOMLParser.ParseKeyValue: TTOMLKeyValuePair;
var
  KeyPath: TList<string>;
  Value: TTOMLValue;
  FullKey: string;
  i: Integer;
  IsQuoted: Boolean;
begin
  KeyPath := TList<string>.Create;
  try
    repeat
      IsQuoted := FCurrentToken.TokenType = ttString;
      AddKeyToPath(KeyPath, ParseKey, IsQuoted);
    until not Match(ttDot);
    if KeyPath.Count = 1 then
      FullKey := KeyPath[0]
    else
    begin
      FullKey := KeyPath[0];
      for i := 1 to KeyPath.Count - 1 do
        FullKey := FullKey + #31 + KeyPath[i];
    end;
    Expect(ttEqual);
    Value := ParseValue;
    Result := TTOMLKeyValuePair.Create(FullKey, Value);
  finally
    KeyPath.Free;
  end;
end;
{ -------------------------------------------------------------------------
  Top-level Parse
  ------------------------------------------------------------------------- }

function TTOMLParser.Parse: TTOMLTable;
var
  CurrentTable: TTOMLTable;
  TablePath: TStringList;
  DefinedTables: TStringList;
  DefinedArrays: TStringList;
  i: Integer;
  Key: string;
  Value: TTOMLValue;
  KeyPair: TTOMLKeyValuePair;
  IsArrayOfTables: Boolean;
  ArrayValue: TTOMLArray;
  NewTable: TTOMLTable;
  HeaderKey: string;

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
  Result.IsImplicit := True;
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
      // Collect file-header comment (before first key / section)
      if FPreserveComments then
      begin
        FPendingComment := '';
        while FCurrentToken.TokenType in [ttNewLine, ttComment] do
        begin
          if FCurrentToken.TokenType = ttComment then
          begin
            if FPendingComment = '' then
              FPendingComment := FCurrentToken.Value
            else if FPendingComment[Length(FPendingComment)] = #10 then
              FPendingComment := FPendingComment + FCurrentToken.Value
            else
              FPendingComment := FPendingComment + #10 + FCurrentToken.Value;
          end
          else
          begin
            if FPendingComment <> '' then
              FPendingComment := FPendingComment + #10;
          end;
          Advance;
        end;
        if FPendingComment <> '' then
        begin
          Result.CommentBefore := FPendingComment;
          FPendingComment := '';
        end;
      end;
      while FCurrentToken.TokenType <> ttEOF do
      begin
        case FCurrentToken.TokenType of
          ttLBracket:
            begin
              // Collect pre-section comment
              var SectionCommentBefore := FPendingComment;
              FPendingComment := '';
              IsArrayOfTables := False;
              var FirstBracket := FCurrentToken;
              Advance;
              if FCurrentToken.TokenType = ttLBracket then
              begin
                if (FCurrentToken.Line <> FirstBracket.Line) or (FCurrentToken.Column <> FirstBracket.Column + 1) then
                  raise ETOMLParserException.Create('Spaces not allowed between [[ brackets');
                IsArrayOfTables := True;
                Advance;
              end;
              TablePath.Clear;
              repeat
                var IsQ := (FCurrentToken.TokenType = ttString);
                AddKeyToPath(TablePath, ParseKey, IsQ);
              until not Match(ttDot);
              var FirstClosing := FCurrentToken;
              Expect(ttRBracket);
              if IsArrayOfTables then
              begin
                if FCurrentToken.TokenType <> ttRBracket then
                  raise ETOMLParserException.Create('Expected second "]" for Array of Tables');
                if (FCurrentToken.Line <> FirstClosing.Line) or (FCurrentToken.Column <> FirstClosing.Column + 1) then
                  raise ETOMLParserException.Create('Spaces not allowed between ]] brackets');
                Advance;
              end;
              // Collect inline comment on the header line
              var HeaderInlineComment := '';
              if FPreserveComments and (FCurrentToken.TokenType = ttComment) then
              begin
                HeaderInlineComment := FCurrentToken.Value;
                Advance;
              end;
              ExpectNewLineOrEOF;
              HeaderKey := TablePathToKey;
              if IsArrayOfTables then
              begin
                if DefinedTables.IndexOf(HeaderKey) >= 0 then
                  raise ETOMLParserException.CreateFmt('Cannot define [[%s]] — already a regular table', [HeaderKey.Replace
                    (#31, '.')]);
              end
              else
              begin
                if DefinedTables.IndexOf(HeaderKey) >= 0 then
                  raise ETOMLParserException.CreateFmt('Duplicate table header [%s]', [HeaderKey.Replace(#31, '.')]);
                if DefinedArrays.IndexOf(HeaderKey) >= 0 then
                  raise ETOMLParserException.CreateFmt('Cannot define [%s] — already an array of tables', [HeaderKey.Replace
                    (#31, '.')]);
              end;
              CurrentTable := Result;
              var PathTracker := '';
              for i := 0 to TablePath.Count - 1 do
              begin
                Key := TablePath[i];
                if i > 0 then
                  PathTracker := PathTracker + #31;
                PathTracker := PathTracker + Key;
                var IsLast := (i = TablePath.Count - 1);
                if IsLast and IsArrayOfTables then
                begin
                  if CurrentTable.TryGetValue(Key, Value) then
                  begin
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
                  if not CurrentTable.TryGetValue(Key, Value) then
                  begin
                    var TempTable := TTOMLTable.Create;
                    TempTable.IsImplicit := True;
                    Value := TempTable;
                    CurrentTable.Add(Key, Value);
                  end;
                  if Value is TTOMLArray then
                  begin
                    if DefinedArrays.IndexOf(PathTracker) < 0 then
                      raise ETOMLParserException.CreateFmt('Cannot navigate into static array "%s"', [Key]);
                    ArrayValue := TTOMLArray(Value);
                    if ArrayValue.Count = 0 then
                      raise ETOMLParserException.Create('Internal error: empty AoT');
                    CurrentTable := TTOMLTable(ArrayValue.Items[ArrayValue.Count - 1]);
                  end
                  else if Value is TTOMLTable then
                  begin
                    if TTOMLTable(Value).IsInline then
                      raise ETOMLParserException.CreateFmt('Cannot extend inline table "%s"', [Key]);
                    CurrentTable := TTOMLTable(Value);
                    if IsLast and not IsArrayOfTables then
                      CurrentTable.IsImplicit := False;
                  end
                  else
                    raise ETOMLParserException.CreateFmt('"%s" is already a scalar', [Key]);
                end;
              end;
              // Attach comments to the target table
              if FPreserveComments then
              begin
                if SectionCommentBefore <> '' then
                  CurrentTable.CommentBefore := SectionCommentBefore;
                if HeaderInlineComment <> '' then
                  CurrentTable.CommentInline := HeaderInlineComment;
              end;
              // Collect the pre-next-key pending comments
              if FPreserveComments then
              begin
                FPendingComment := '';
                while FCurrentToken.TokenType in [ttNewLine, ttComment] do
                begin
                  if FCurrentToken.TokenType = ttComment then
                  begin
                    if FPendingComment = '' then
                      FPendingComment := FCurrentToken.Value
                    else if FPendingComment[Length(FPendingComment)] = #10 then
                      FPendingComment := FPendingComment + FCurrentToken.Value
                    else
                      FPendingComment := FPendingComment + #10 + FCurrentToken.Value;
                  end
                  else
                  begin
                    if FPendingComment <> '' then
                      FPendingComment := FPendingComment + #10;
                  end;
                  Advance;
                end;
              end;
              if IsArrayOfTables then
              begin
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
                // Attach any accumulated pending comment to the first value's CommentBefore
                var CommentForThisKey := FPendingComment;
                FPendingComment := '';
                KeyPair := ParseKeyValue;
                if FPreserveComments and (CommentForThisKey <> '') then
                  KeyPair.Value.CommentBefore := CommentForThisKey;
                // Collect inline comment on the value line
                if FPreserveComments then
                  CollectInlineComment(KeyPair.Value);
                ExpectNewLineOrEOF;
                // Record implicit tables from dotted keys
                var KVKeyParts := SplitDottedKey(KeyPair.Key);
                var KVRunningPath := HeaderKey;
                for i := 0 to High(KVKeyParts) - 1 do
                begin
                  if KVRunningPath <> '' then
                    KVRunningPath := KVRunningPath + #31;
                  KVRunningPath := KVRunningPath + KVKeyParts[i];
                  if DefinedTables.IndexOf(KVRunningPath) < 0 then
                    DefinedTables.Add(KVRunningPath);
                end;
                if KeyPair.Value is TTOMLTable then
                begin
                  var FullKVPath := KVRunningPath;
                  if FullKVPath <> '' then
                    FullKVPath := FullKVPath + #31;
                  FullKVPath := FullKVPath + KVKeyParts[High(KVKeyParts)];
                  if DefinedTables.IndexOf(FullKVPath) < 0 then
                    DefinedTables.Add(FullKVPath);
                end;
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
                // Collect blank-line / comment block after the key-value pair
                if FPreserveComments then
                begin
                  FPendingComment := '';
                  while FCurrentToken.TokenType in [ttNewLine, ttComment] do
                  begin
                    if FCurrentToken.TokenType = ttComment then
                    begin
                      if FPendingComment = '' then
                        FPendingComment := FCurrentToken.Value
                      else if FPendingComment[Length(FPendingComment)] = #10 then
                        FPendingComment := FPendingComment + FCurrentToken.Value
                      else
                        FPendingComment := FPendingComment + #10 + FCurrentToken.Value;
                    end
                    else
                    begin
                      if FPendingComment <> '' then
                        FPendingComment := FPendingComment + #10;
                    end;
                    Advance;
                  end;
                end;
              except
                on E: ETOMLParserException do
                  raise;
                on E: Exception do
                  raise ETOMLParserException.CreateFmt('Error adding key-value: %s at line %d, column %d', [E.Message,
                    FCurrentToken.Line, FCurrentToken.Column]);
              end;
            end;
          ttNewLine:
            begin
              if FPreserveComments then
              begin
                if FPendingComment <> '' then
                  FPendingComment := FPendingComment + #10;
              end;
              Advance;
            end;
          ttComment:
            begin
              if FPreserveComments then
              begin
                if FPendingComment = '' then
                  FPendingComment := FCurrentToken.Value
                else if FPendingComment[Length(FPendingComment)] = #10 then
                  FPendingComment := FPendingComment + FCurrentToken.Value
                else
                  FPendingComment := FPendingComment + #10 + FCurrentToken.Value;
              end;
              Advance;
            end;
        else
          raise ETOMLParserException.CreateFmt('Unexpected token %s at line %d, column %d', [GetEnumName(TypeInfo
            (TTokenType), Ord(FCurrentToken.TokenType)), FCurrentToken.Line, FCurrentToken.Column]);
        end;
      end; // while
      // Anything remaining in FPendingComment becomes the file-footer comment
      if FPreserveComments and (FPendingComment <> '') then
      begin
        Result.CommentTrailing := FPendingComment;
        FPendingComment := '';
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
