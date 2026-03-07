(* TOML_Parser.pas
  TOML 解析器单元（词法分析 + 语法分析）。
  本单元实现了符合 TOML v1.0.0 规范的完整解析器，采用两阶段设计：
    1. TTOMLLexer  —— 词法分析，将原始文本转换为 Token 序列
    2. TTOMLParser —— 语法分析，将 Token 序列转换为 TOML 数据结构
  支持的特性：
    - 键值对（裸键、基本字符串键、字面量字符串键、点号键）
    - 表 [table] 和数组表 [[array]]
    - 内联表 { key = value, ... }
    - 数组 [ ... ]（支持尾随逗号和多行格式）
    - 基本字符串和字面量字符串（含多行形式）
    - 十进制、十六进制（0x）、八进制（0o）、二进制（0b）整数
    - 浮点数（含指数、inf、nan）
    - 布尔值（true / false）
    - 日期时间（带时区偏移、本地日期时间、本地日期、本地时间）
  关键实现细节：
    - 点号键中的各段使用 #31（ASCII Unit Separator）拼接，
      避免与键名中合法的点号（如 "tt.com"）混淆
    - 使用 IsImplicit 标记隐式创建的中间表，
      区别于 [header] 显式定义的表
    - 使用 IsInline 标记内联表，禁止后续通过表头扩展其内容
*)
unit TOML.Parser;

interface

uses
  SysUtils, Classes, TOML.Types, Generics.Collections, TypInfo, DateUtils, Math;
{$IF CompilerVersion < 20.0}
function CharInSet(C: Char; const CharSet: TSysCharSet): Boolean; inline;
{$IFEND}

type
  { Token 类型，代表词法分析中的最小语义单元 }
  TTokenType = (ttEOF,              // 文件结束
    ttString,           // 字符串字面量（基本字符串或字面量字符串）
    ttMultilineString,  // 多行字符串
    ttInteger,          // 整数（十进制/十六进制/八进制/二进制）
    ttFloat,            // 浮点数（含指数）
    ttBoolean,          // 布尔值（true / false）
    ttDateTime,         // 日期时间（RFC 3339）
    ttEqual,            // 等号 =
    ttDot,              // 点号 .（用于点号键）
    ttComma,            // 逗号 ,
    ttLBracket,         // 左方括号 [
    ttRBracket,         // 右方括号 ]
    ttLBrace,           // 左花括号 {
    ttRBrace,           // 右花括号 }
    ttNewLine,          // 换行符
    ttWhitespace,       // 空白字符
    ttComment,          // 注释（# 开头）
    ttIdentifier        // 裸键标识符
  );
  { Token 记录，存储词法单元的完整信息 }
  TToken = record
    TokenType: TTokenType;  // 类型
    Value: string;          // 原始文本值
    Line: Integer;          // 行号（从 1 开始）
    Column: Integer;        // 列号（从 1 开始）
  end;
  { 键值对类型（用于解析器内部传递） }
  TTOMLKeyValuePair = TPair<string, TTOMLValue>;
  { TOML 词法分析器 —— 将原始 TOML 文本切分为 Token 序列 }
  TTOMLLexer = class
  private
    FInput: string;      // 输入文本
    FPosition: Integer;  // 当前读取位置（1 起始）
    FLine: Integer;      // 当前行号
    FColumn: Integer;    // 当前列号

    { 是否已到达输入末尾 }
    function IsAtEnd: Boolean;

    { 查看当前字符，不推进位置（末尾返回 #0） }
    function Peek: Char;

    { 查看下一个字符，不推进位置（末尾返回 #0） }
    function PeekNext: Char;

    { 消耗当前字符并推进位置（末尾返回 #0） }
    function Advance: Char;

    { 跳过空格、Tab 及注释（不含换行符） }
    procedure SkipWhitespace;

    { 扫描字符串 Token（单行或多行，基本或字面量）
      @raises ETOMLParserException 若字符串格式非法 }
    function ScanString: TToken;

    { 扫描数字 Token（整数或浮点数）
      @raises ETOMLParserException 若数字格式非法 }
    function ScanNumber: TToken;

    { 扫描标识符 Token（裸键或 true / false） }
    function ScanIdentifier: TToken;

    { 扫描日期时间 Token（返回 ttDateTime 或回退到 ttInteger）
      @raises ETOMLParserException 若日期时间格式非法 }
    function ScanDateTime: TToken;

    { 字符分类辅助函数 }
    function IsDigit(C: Char): Boolean;
    function IsAlpha(C: Char): Boolean;
    function IsAlphaNumeric(C: Char): Boolean;
  public
    { @param AInput 要词法分析的 TOML 文本 }
    constructor Create(const AInput: string);

    { 返回下一个 Token
      @raises ETOMLParserException 若遇到非法字符 }
    function NextToken: TToken;
  end;
  { TOML 语法分析器 —— 将 Token 序列转换为 TOML 数据结构 }
  TTOMLParser = class
  private
    FLexer: TTOMLLexer;       // 词法分析器实例
    FCurrentToken: TToken;    // 当前 Token
    FPeekedToken: TToken;     // 预读的下一个 Token
    FHasPeeked: Boolean;      // 是否已预读

    { 推进到下一个 Token }
    procedure Advance;

    { 预读下一个 Token（不消耗） }
    function Peek: TToken;

    { 若当前 Token 类型匹配则消耗并返回 True，否则返回 False }
    function Match(TokenType: TTokenType): Boolean;

    { 断言当前 Token 类型，不匹配则抛出异常并推进
      @raises ETOMLParserException }
    procedure Expect(TokenType: TTokenType);

    { 各类 TOML 语法结构的解析方法 }
    function ParseValue: TTOMLValue;
    function ParseString: TTOMLString;
    function ParseNumber: TTOMLValue;
    function ParseBoolean: TTOMLBoolean;
    function ParseDateTime: TTOMLDateTime;
    function ParseArray: TTOMLArray;
    function ParseInlineTable: TTOMLTable;
    function ParseKey: string;

    { 将复合键字符串（以 #31 分隔各段）拆分为字符串数组 }
    function SplitDottedKey(const CompositeKey: string): TArray<string>;

    { 向路径列表追加一个键段，
      若该段未加引号且含点号（Lexer 贪婪匹配为 ttFloat 所致）则进一步拆分 }
    procedure AddKeyToPath(Path: TList<string>; const Segment: string; WasQuoted: Boolean); overload;
    procedure AddKeyToPath(Path: TStrings; const Segment: string; WasQuoted: Boolean); overload;

    { 按点号键路径逐级创建/导航表，并在最终位置写入值
      @raises ETOMLParserException 若路径冲突或键重复定义 }
    procedure SetDottedKey(RootTable: TTOMLTable; const KeyParts: TArray<string>; Value: TTOMLValue);

    { 解析一个键值对（key = value）
      @returns 包含键和值的 TTOMLKeyValuePair }
    function ParseKeyValue: TTOMLKeyValuePair;

    { 校验当前 Token 必须是换行或 EOF，否则抛出异常；
      若为换行则消耗之，为下一条语句做准备 }
    procedure ExpectNewLineOrEOF;

  public
    { @param AInput 要解析的 TOML 文本 }
    constructor Create(const AInput: string);
    destructor Destroy; override;

    { 解析输入并返回根 TTOMLTable
      @raises ETOMLParserException 若输入不合法 }
    function Parse: TTOMLTable;
  end;
{ 将 TOML 字符串解析为表对象
  @raises ETOMLParserException 若输入不合法 }
function ParseTOMLString(const ATOML: string): TTOMLTable;
{ 从文件加载并解析 TOML 数据
  @raises ETOMLParserException 若内容不合法
  @raises EFileStreamError    若文件无法打开 }
function ParseTOMLFile(const AFileName: string): TTOMLTable;

implementation
{$IF CompilerVersion < 20.0}

function CharInSet(C: Char; const CharSet: TSysCharSet): Boolean;
begin
  Result := C in CharSet;
end;
{$IFEND}

{ 高层函数实现 }

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
    // 读取前 3 字节以检测 BOM 编码标记
    BytesRead := Stream.Read(BOM, 3);
    Stream.Position := 0;

    if (BytesRead >= 3) and (BOM[0] = $EF) and (BOM[1] = $BB) and (BOM[2] = $BF) then
      Encoding := TEncoding.UTF8
    else if (BytesRead >= 2) and (BOM[0] = $FF) and (BOM[1] = $FE) then
      Encoding := TEncoding.Unicode
    else if (BytesRead >= 2) and (BOM[0] = $FE) and (BOM[1] = $FF) then
      Encoding := TEncoding.BigEndianUnicode
    else
      // 无 BOM 时默认 UTF-8（TOML 规范要求）
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
{ TTOMLParser 辅助方法 }

procedure TTOMLParser.ExpectNewLineOrEOF;
begin
  // 顶层表达式后只允许换行或文件结束
  // （SkipWhitespace 已过滤空格和注释，Peek 到的只会是换行或新 Token）
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
        // 空格、Tab 和 UTF-8 BOM 均视为空白
        Advance;
      '#':
        begin
          // 跳过注释内容直到行尾，同时检查非法控制字符
          Advance; // 消耗 '#'
          while (not IsAtEnd) and (Peek <> #10) and (Peek <> #13) do
          begin
            Ch := Peek;
            OrdCh := Ord(Ch);
            // 注释中不允许出现 U+0000-U+0008、U+000B-U+001F 和 U+007F
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

  Advance; // 消耗开头引号

  // 检测三重引号（多行字符串）
  if (Peek = QuoteChar) and (PeekNext = QuoteChar) then
  begin
    IsMultiline := True;
    Advance;
    Advance;
    // 多行字符串开头的第一个换行（如果紧跟）被忽略
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
    // 1. 检测闭合定界符
    if IsMultiline then
    begin
      if Peek = QuoteChar then
      begin
        // 探测连续引号数量（TOML 允许在多行字符串内出现最多 2 个同类引号）
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
            // 3–5 个引号：前 (QuoteCount-3) 个是内容，后 3 个是定界符
            for j := 1 to QuoteCount - 3 do
              TempValue := TempValue + Advance;
            Advance;
            Advance;
            Advance; // 消耗 3 个定界符
            FoundClosing := True;
            Break;
          end
          else
          begin
            // 6 个及以上：消耗前 3 个关闭字符串，其余留给 Parser 报错
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

    // 2. 处理转义序列（仅适用于基本字符串，字面量字符串不转义）
    if (not IsLiteral) and (Peek = '\') then
    begin
      // 多行基本字符串中，行尾的 \ 用于忽略换行及后续空白
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
          TempValue := TempValue + #8;    // 退格
        'f':
          TempValue := TempValue + #12;   // 换页
        'n':
          TempValue := TempValue + #10;   // 换行
        'r':
          TempValue := TempValue + #13;   // 回车
        't':
          TempValue := TempValue + #9;    // 制表符
        '\':
          TempValue := TempValue + '\';
        '"':
          TempValue := TempValue + '"';
        '''':
          TempValue := TempValue + ''''; // 允许转义单引号
        'e':
          TempValue := TempValue + #27;   // ESC（TOML 1.1）
        'x':
          begin
            // \xHH —— 2 位十六进制转义
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
            // \uHHHH 或 \UHHHHHHHH —— Unicode 转义
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
      Advance; // 消耗被转义的字符（b/f/n/r/t/\/"/e 等）
    end
    else
    begin
      // 3. 普通字符处理及非法控制字符检查
      var Ch := Peek;

      // 换行符处理
      if (Ch = #10) or (Ch = #13) then
      begin
        if not IsMultiline then
          raise ETOMLParserException.Create('Newlines are not allowed in single-line strings');

        if Ch = #13 then
        begin
          Advance; // 消耗 CR
          if Peek = #10 then
            Advance // 消耗 LF
          else
            raise ETOMLParserException.Create('Bare CR is not allowed in multi-line strings');
        end
        else
          Advance; // 消耗 LF

        // 多行字符串中的换行统一规范化为 LF
        TempValue := TempValue + #10;
      end
      else
      begin
        // 其他控制字符检查：Tab（0x09）合法，其余 0x00-0x1F 和 0x7F 均非法
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
  { 消耗连续数字字符（AllowedDigits 指定合法字符集），含下划线分隔符检查 }

  procedure ConsumeDigits(const AllowedDigits: TSysCharSet);
  begin
    while (not IsAtEnd) and (CharInSet(Peek, AllowedDigits) or (Peek = '_')) do
    begin
      if Peek = '_' then
      begin
        // 下划线前后必须是合法数字（禁止在开头、结尾或连续使用）
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

  // 1. 处理正负号
  if CharInSet(Peek, ['+', '-']) then
  begin
    HasSign := True;
    TempValue := TempValue + Advance;
  end;

  // 2. 检测特殊浮点值 inf / nan（允许带符号）
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
    // 进制整数不允许带符号
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

  // 4. 十进制整数部分
  ConsumeDigits(['0'..'9']);

  // 5. 小数部分（. 后必须跟数字，否则不是浮点数）
  if (Peek = '.') and IsDigit(PeekNext) then
  begin
    IsFloat := True;
    TempValue := TempValue + Advance;
    ConsumeDigits(['0'..'9']);
  end;

  // 6. 指数部分
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
  // 裸键允许：字母、数字、下划线、连字符
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
  { 尝试扫描 Count 个连续数字，成功返回 True，失败返回 False }

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

  // 尝试解析日期部分 YYYY-MM-DD
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

  // 日期之后尝试解析时间部分（T 或空格分隔，空格需前瞻确认后续是 HH:MM 格式）
  if HasDate and ((UpCase(Peek) = 'T') or (Peek = ' ')) then
  begin
    var CanContinue := False;
    if UpCase(Peek) = 'T' then
      CanContinue := True
    else if Peek = ' ' then
    begin
      // 空格分隔：前瞻检查后续是否符合 HH:MM 格式
      var NextPos := FPosition + 1;
      if NextPos + 4 <= Length(FInput) then
        CanContinue := IsDigit(FInput[NextPos]) and IsDigit(FInput[NextPos + 1]) and (FInput[NextPos + 2] =
          ':') and IsDigit(FInput[NextPos + 3]) and IsDigit(FInput[NextPos + 4]);
    end;

    if CanContinue then
    begin
      TempValue := TempValue + Advance; // 消耗 'T' 或 ' '
      if ScanDigits(2) and (Peek = ':') then
      begin
        TempValue := TempValue + Advance; // ':'
        if ScanDigits(2) then             // 分钟（必须）
        begin
          HasTime := True;
          // 秒数可选
          if Peek = ':' then
          begin
            TempValue := TempValue + Advance; // ':'
            if ScanDigits(2) then            // 秒
            begin
              // 小数秒可选
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
    // 无日期时尝试解析纯时间 HH:MM[:SS[.frac]]
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

  // 尝试解析时区部分（Z 或 +/-HH:MM）
  if HasTime and (CharInSet(UpCase(Peek), ['Z', '+', '-'])) then
  begin
    if UpCase(Peek) = 'Z' then
    begin
      TempValue := TempValue + Advance;
      HasTimezone := True;
    end
    else
    begin
      // 尽可能多地消耗 [0-9:] 字符，格式校验留给 Parser
      TempValue := TempValue + Advance; // '+' 或 '-'
      while (not IsAtEnd) and CharInSet(Peek, ['0'..'9', ':']) do
        TempValue := TempValue + Advance;
      // 注意：此处不设置 HasTimezone，格式合法性由 Parser 确认
    end;
  end;

  // 根据解析结果确定 Token 类型
  if HasDate or HasTime then
    Result.TokenType := ttDateTime
  else
    Result.TokenType := ttInteger; // 回退：让 ScanNumber 重新处理

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
        // 换行处理：统一将 CR+LF 和单独 LF 视为一个换行 Token
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
        // 优先尝试扫描日期时间，失败则回退扫描数字
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
        // 若数字后紧跟字母或连字符，则整体视为标识符（如 2024-key 形式的裸键）
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
        // 优先尝试扫描带符号数字，若仅剩符号或后跟字母则视为标识符
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

  // 1. 处理特殊浮点值 inf / nan（含带符号形式）
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

  // 2. 去掉下划线分隔符，得到用于解析的纯净数字字符串
  CleanValue := '';
  for i := 1 to Length(RawValue) do
    if RawValue[i] <> '_' then
      CleanValue := CleanValue + RawValue[i];

  IntValue := 0;
  Code := 0;
  Result := nil;

  // 3. 判断是否为十六进制 / 八进制 / 二进制整数
  IsHexOctBin := (Length(CleanValue) >= 2) and (CleanValue[1] = '0') and CharInSet(CleanValue[2], ['x', 'o', 'b']);

  if IsHexOctBin then
  begin
    case UpCase(CleanValue[2]) of
      'X': // 十六进制
        begin
          BaseValue := '$' + Copy(CleanValue, 3, Length(CleanValue));
          Val(BaseValue, IntValue, Code);
        end;
      'O': // 八进制
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
      'B': // 二进制
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
    // 4. 十进制数字（整数或浮点数）
    SForCheck := CleanValue;
    if (Length(SForCheck) > 0) and CharInSet(SForCheck[1], ['+', '-']) then
      Delete(SForCheck, 1, 1);

    // 十进制数值必须以数字字符开头（排除 -.123 或 .123 等非法格式）
    if (Length(SForCheck) = 0) or (not CharInSet(SForCheck[1], ['0'..'9'])) then
      raise ETOMLParserException.CreateFmt('Numbers must have an integer part: %s at line %d', [RawValue,
        FCurrentToken.Line]);

    // 禁止前导零（如 01、007）
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

    // 解析日期部分 YYYY-MM-DD
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

    // 解析时间部分（T 或空格分隔，或无日期时直接解析）
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

        // 秒数可选
        if (P <= Length(DateStr)) and (DateStr[P] = ':') then
        begin
          Inc(P);
          if P + 1 <= Length(DateStr) then
          begin
            Second := StrToInt(Copy(DateStr, P, 2));
            P := P + 2;
            // 小数秒可选
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
        // 存在 T 或空格分隔符但后续不是合法时间格式，视为错误
        raise ETOMLParserException.Create('DateTime separator must be followed by valid time');
    end;

    // 解析时区部分（Z 或 +/-HH:MM）
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
        // 时区偏移固定格式：[+-]HH:MM（6 个字符）
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

    // 字符串若有剩余未解析部分，则格式非法
    if P <= Length(DateStr) then
      raise ETOMLParserException.CreateFmt('Malformed datetime trailing characters: "%s"', [Copy(DateStr, P, MaxInt)]);

    // 确定日期时间子类型
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

    // 构造 TDateTime 值
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
      // 跳过元素前的所有换行（TOML 允许数组跨行）
      while Match(ttNewLine) do
        ;

      // 处理空数组 [] 或末尾逗号后的 ]
      if FCurrentToken.TokenType = ttRBracket then
        Break;

      Result.Add(ParseValue);

      while Match(ttNewLine) do
        ;

      // 无逗号则结束（允许单元素无尾随逗号）
      if not Match(ttComma) then
      begin
        while Match(ttNewLine) do
          ;
        Break;
      end;
      // 有逗号则继续解析下一个元素
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
  Result.IsInline := True; // 内联表不可通过表头扩展
  try
    Expect(ttLBrace);

    // 跳过可选的换行（TOML 1.1 允许内联表内换行）
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
          // 含 #31 分隔符的复合键需要逐级导航
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
    // 数字字面量可作为裸键（如 1 = "one"）
    Result := FCurrentToken.Value;
    Advance;
  end
  else if FCurrentToken.TokenType = ttDateTime then
  begin
    // 类日期格式的裸键：仅允许 [A-Za-z0-9_-]，含 : T Z + . 等字符时必须加引号
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
  // 空字符串视为单键
  if CompositeKey = '' then
  begin
    SetLength(Result, 1);
    Result[0] := '';
    Exit;
  end;

  // 统计分隔符数量，确定结果数组大小
  Count := 1;
  for i := 1 to Length(CompositeKey) do
    if CompositeKey[i] = #31 then
      Inc(Count);

  SetLength(Result, Count);

  // 手动按 #31 切分，保留首尾和中间的空字符串
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
  // 未加引号且含点号时（通常由 Lexer 贪婪扫描 ttFloat 产生）进一步拆分
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

  // 1. 处理路径中间各层级（末尾键除外）
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
        // 内联表不可通过点号键扩展
        if TTOMLTable(ExistingValue).IsInline then
          raise ETOMLParserException.CreateFmt('Cannot extend inline table "%s"', [KeyParts[i]]);

        // 已显式定义的表（如 [a]）不允许再通过 a.b = 1 追加内容
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
      // 路径不存在时创建隐式表，允许后续点号键继续导航
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

  // 2. 写入最终键值
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
  { 解析键值对。
    键的各段由 ParseKey 单独获取（词法器已剥离引号，返回原始内容），
    再以 #31（ASCII Unit Separator）拼接——这样键名中合法的点号
    （如 "tt.com"）可完整保留。SplitDottedKey 用相同的 #31 定界符还原各段。 }
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
  DefinedTables: TStringList;  // 已显式定义的 [table] 头部路径集合
  DefinedArrays: TStringList;  // 已显式定义的 [[array]] 头部路径集合
  i: Integer;
  Key: string;
  Value: TTOMLValue;
  KeyPair: TTOMLKeyValuePair;
  IsArrayOfTables: Boolean;
  ArrayValue: TTOMLArray;
  NewTable: TTOMLTable;
  HeaderKey: string; // 当前 [header] 的规范化点号路径（以 #31 分隔）

  { 将 TablePath 列表拼接为以 #31 分隔的路径字符串 }

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

              // 检测 [[array]] —— 第二个 [ 必须紧跟第一个 [
              if FCurrentToken.TokenType = ttLBracket then
              begin
                if (FCurrentToken.Line <> FirstBracket.Line) or (FCurrentToken.Column <> FirstBracket.Column + 1) then
                  raise ETOMLParserException.Create('Spaces are not allowed between brackets in [[table]] header');
                IsArrayOfTables := True;
                Advance;
              end;

              // 解析表头路径
              TablePath.Clear;
              repeat
                var IsQ := (FCurrentToken.TokenType = ttString);
                AddKeyToPath(TablePath, ParseKey, IsQ);
              until not Match(ttDot);

              // 解析结尾括号
              var FirstClosing := FCurrentToken;
              Expect(ttRBracket);
              if IsArrayOfTables then
              begin
                if FCurrentToken.TokenType <> ttRBracket then
                  raise ETOMLParserException.Create('Expected second "]" for Array of Tables header');
                // 第二个 ] 必须紧跟第一个 ]
                if (FCurrentToken.Line <> FirstClosing.Line) or (FCurrentToken.Column <> FirstClosing.Column + 1) then
                  raise ETOMLParserException.Create('Spaces are not allowed between brackets in [[table]] header');
                Advance;
              end;

              // 表头后必须换行或到达文件末尾
              ExpectNewLineOrEOF;

              // 计算此表头的唯一标识路径
              HeaderKey := TablePathToKey;

              // 检查是否与已有定义冲突
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

              // 路径导航：从根部逐级进入
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
                  // [[a.b.c]] 的最终段：追加新表到数组
                  if CurrentTable.TryGetValue(Key, Value) then
                  begin
                    // 已存在的数组必须是由 [[]] 定义的（不能是静态数组 a = []）
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
                  // 路径中间层级或普通 [a.b.c] 的最终段
                  if not CurrentTable.TryGetValue(Key, Value) then
                  begin
                    Value := TTOMLTable.Create;
                    CurrentTable.Add(Key, Value);
                  end;

                  if Value is TTOMLArray then
                  begin
                    // 只有由 [[]] 定义的数组才允许通过表头导航进入
                    if DefinedArrays.IndexOf(PathTracker) < 0 then
                      raise ETOMLParserException.CreateFmt('Cannot navigate into static array "%s"', [Key]);

                    ArrayValue := TTOMLArray(Value);
                    if ArrayValue.Count = 0 then
                      raise ETOMLParserException.Create('Internal error: empty AoT');

                    // 导航到该数组表的最新条目
                    CurrentTable := TTOMLTable(ArrayValue.Items[ArrayValue.Count - 1]);
                  end
                  else if Value is TTOMLTable then
                  begin
                    // 内联表不可通过表头扩展
                    if TTOMLTable(Value).IsInline then
                      raise ETOMLParserException.CreateFmt('Cannot extend inline table "%s"', [Key]);

                    CurrentTable := TTOMLTable(Value);
                    // 到达最终段时将表标记为显式定义
                    if IsLast and (not IsArrayOfTables) then
                      CurrentTable.IsImplicit := False;
                  end
                  else
                    raise ETOMLParserException.CreateFmt('Key "%s" is already defined as a scalar', [Key]);
                end;
              end;

              // 记录本次显式定义
              if IsArrayOfTables then
              begin
                // 清除该 AoT 下已记录的子表定义（AoT 每轮迭代重新开始）
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

                // 记录由键值对隐式创建的表路径，防止后续表头重复定义
                var KVKeyParts := SplitDottedKey(KeyPair.Key);
                var KVRunningPath := HeaderKey;

                // 记录点号键中间各层级（它们对应隐式创建的表）
                for i := 0 to High(KVKeyParts) - 1 do
                begin
                  if KVRunningPath <> '' then
                    KVRunningPath := KVRunningPath + #31;
                  KVRunningPath := KVRunningPath + KVKeyParts[i];
                  if DefinedTables.IndexOf(KVRunningPath) < 0 then
                    DefinedTables.Add(KVRunningPath);
                end;

                // 若值本身为内联表，则该键也定义了一个表
                if KeyPair.Value is TTOMLTable then
                begin
                  var FullKVPath := KVRunningPath;
                  if FullKVPath <> '' then
                    FullKVPath := FullKVPath + #31;
                  FullKVPath := FullKVPath + KVKeyParts[High(KVKeyParts)];
                  if DefinedTables.IndexOf(FullKVPath) < 0 then
                    DefinedTables.Add(FullKVPath);
                end;

                // 将键值对写入当前表
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
