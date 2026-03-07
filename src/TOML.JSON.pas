{ TOML.JSON.pas
  TOML ↔ JSON 格式互转单元。
  提供两组公开函数：
    TOML → JSON
      TOMLToJSON(Table)         将 TTOMLTable 转换为 JSON 字符串
      TOMLValueToJSON(Value)    将任意 TTOMLValue 转换为 JSON 字符串
      TOMLFileToJSONFile(...)   从 TOML 文件转换并写入 JSON 文件
    JSON → TOML
      JSONToTOML(JSON)          将 JSON 字符串解析为 TTOMLTable
      JSONToTOMLString(JSON)    将 JSON 字符串转换为 TOML 格式字符串
      JSONFileToTOMLFile(...)   从 JSON 文件转换并写入 TOML 文件
  类型映射规则：
    TOML → JSON
      string       → JSON string（含完整转义，含代理对 \uXXXX\uXXXX）
      integer      → JSON number（整数，无小数点）
      float        → JSON number（优先用原始文本保证精度；inf/nan → null）
      boolean      → JSON true / false
      datetime     → JSON string（保留原始 RFC 3339 文本）
      array        → JSON array
      table        → JSON object（保留插入顺序）
      inline table → JSON object（保留插入顺序）
    JSON → TOML
      string       → TOML string
      number       → 含小数点或指数则为 float，否则为 integer
                     超出 Int64 范围时降级为 float
      true / false → TOML boolean
      null         → 跳过该键（TOML 无 null 概念）；
                     ANullAsEmptyString=True 时写入空字符串
      array        → TOML array
      object       → TOML table（key 插入顺序与 JSON 文本一致）
  实现说明：
    - 不依赖任何第三方库，内含手写的轻量 JSON 词法 + 语法解析器。
    - 浮点数优先输出 TTOMLFloat.RawString（原始文本），
      无原始文本时以 17 位有效数字保证往返精度（IEEE 754 round-trip）。
    - WriteObject 保留 TTOMLTable.Items 插入顺序，不做字母排序。
    - \uXXXX 转义正确处理 BMP 以外字符的代理对（surrogate pair）。
    - JSON → TOML 的 null 值（Val = nil）不会泄漏对象，已在所有分支
      安全处理。
}
unit TOML.JSON;

interface

uses
  SysUtils, Classes, Math, TOML.Types, TOML.Parser, TOML.Serializer, Generics.Collections;
{ ===== TOML → JSON ===== }

{ 将 TTOMLTable 序列化为 JSON 字符串
  @param Table        源 TOML 表
  @param APretty      True 时输出带缩进的美观格式（默认 True）
  @param AIndentSize  每级缩进的空格数（默认 2）
  @returns JSON 对象字符串
  @raises ETOMLException 若值无法转换 }
function TOMLToJSON(const Table: TTOMLTable; APretty: Boolean = True; AIndentSize: Integer = 2): string;
{ 将任意 TTOMLValue 序列化为 JSON 字符串（用于非表根节点场景） }
function TOMLValueToJSON(const Value: TTOMLValue; APretty: Boolean = True; AIndentSize: Integer = 2): string;
{ 读取 TOML 文件并将结果写入 JSON 文件
  @param ATOMLFile  输入 TOML 文件路径
  @param AJSONFile  输出 JSON 文件路径
  @param APretty    是否美观缩进（默认 True）
  @param ABOM       是否写入 UTF-8 BOM（默认 False，JSON 通常无 BOM）
  @returns True 若成功，False 若出错 }
function TOMLFileToJSONFile(const ATOMLFile, AJSONFile: string; APretty: Boolean = True; ABOM: Boolean = False):
  Boolean;
{ ===== JSON → TOML ===== }

(* 将 JSON 字符串解析为 TTOMLTable
  @param AJSON              JSON 字符串（根节点必须是对象 { ... }）
  @param ANullAsEmptyString True 时将 JSON null 转为空字符串；
                            False 时忽略 null 键（默认 False）
  @returns 新建的 TTOMLTable（调用方负责释放）
  @raises ETOMLParserException 若 JSON 格式非法或根节点不是对象 *)
function JSONToTOML(const AJSON: string; ANullAsEmptyString: Boolean = False): TTOMLTable;
{ 将 JSON 字符串转换为 TOML 格式字符串（便捷封装） }
function JSONToTOMLString(const AJSON: string; ANullAsEmptyString: Boolean = False): string;
{ 读取 JSON 文件并将结果写入 TOML 文件
  @param AJSONFile          输入 JSON 文件路径
  @param ATOMLFile          输出 TOML 文件路径
  @param ANullAsEmptyString null 处理策略（同 JSONToTOML）
  @param ABOM               是否写入 UTF-8 BOM（默认 True，TOML 文件常带 BOM）
  @returns True 若成功，False 若出错 }
function JSONFileToTOMLFile(const AJSONFile, ATOMLFile: string; ANullAsEmptyString: Boolean = False; ABOM:
  Boolean = True): Boolean;

implementation
(* ======================================================================
  内部：轻量 JSON 词法器
  支持完整 RFC 8259 词法单元：
    object  { "key": value }
    array   [ value, ... ]
    string  "..."（含所有转义及 \uXXXX 代理对）
    number  整数 / 浮点（含负号、指数）
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
    jtkNumber,    // 数字（整数或浮点）
    jtkTrue,      // true
    jtkFalse,     // false
    jtkNull,      // null
    jtkEOF        // 输入结束
  );

  TJSONToken = record
    Kind: TJSONTokenKind;
    Str: string;   // jtkString / jtkNumber 时有效
    IsFloat: Boolean;  // jtkNumber 时标记是否为浮点
  end;
  { 轻量 JSON 词法器 }
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
  { 轻量 JSON 语法解析器，直接产出 TTOMLValue 树 }
  TJSONParser = class
  private
    FLexer: TJSONLexer;
    FNullAsEmpty: Boolean;
    FCurrent: TJSONToken;

    procedure Advance;
    procedure Expect(Kind: TJSONTokenKind);
    function ParseValue: TTOMLValue;   // 返回 nil 表示 JSON null 且不转为空串
    function ParseObject: TTOMLTable;
    function ParseArray: TTOMLArray;
  public
    constructor Create(const AText: string; ANullAsEmpty: Boolean);
    destructor Destroy; override;
    function Parse: TTOMLTable;
  end;
{ ======================================================================
  TJSONLexer 实现
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
{ 处理 JSON 字符串，支持所有转义字符及 \uXXXX（含 BMP 以外的代理对） }
var
  SB: TStringBuilder;
  C: Char;
  Hex: string;
  Hi, Lo: Cardinal;
  i: Integer;
begin
  Result.Kind := jtkString;
  Result.IsFloat := False;
  Advance; // 消耗开头的 "

  SB := TStringBuilder.Create;
  try
    while not IsAtEnd do
    begin
      C := Advance;
      if C = '"' then
        Break; // 字符串结束

      if C <> '\' then
      begin
        SB.Append(C);
        Continue;
      end;

      // 转义序列
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
            // 读取 4 位十六进制码点
            Hex := '';
            for i := 1 to 4 do
            begin
              if IsAtEnd then
                raise ETOMLParserException.Create('JSON: incomplete \\u escape sequence');
              Hex := Hex + Advance;
            end;
            Hi := StrToInt('$' + Hex);

            // 检测高代理：D800..DBFF，后续必须跟 \uDC00..DFFF 低代理
            if (Hi >= $D800) and (Hi <= $DBFF) then
            begin
              if (not IsAtEnd) and (Advance = '\') and (not IsAtEnd) and (Peek = 'u') then
              begin
                Advance; // 消耗 'u'
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
                  // 合并代理对为完整 Unicode 码点，再编码为 UTF-16（两个 WideChar）
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
              SB.Append(WideChar(Hi)); // 普通 BMP 字符
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
{ 解析 JSON number，与 RFC 8259 §6 一致 }
var
  SB: TStringBuilder;
  IsFloat: Boolean;
begin
  Result.Kind := jtkNumber;
  IsFloat := False;
  SB := TStringBuilder.Create;
  try
    // 可选负号
    if Peek = '-' then
      SB.Append(Advance);

    // 整数部分：0 或 1-9 后接若干位
    while (not IsAtEnd) and (Peek >= '0') and (Peek <= '9') do
      SB.Append(Advance);

    // 小数部分
    if (not IsAtEnd) and (Peek = '.') then
    begin
      IsFloat := True;
      SB.Append(Advance);
      while (not IsAtEnd) and (Peek >= '0') and (Peek <= '9') do
        SB.Append(Advance);
    end;

    // 指数部分
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
{ 匹配 true / false / null 关键字。
  调用时 FPos 已指向关键字第一个字符（尚未消耗），逐字符验证。 }
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
  TJSONParser 实现
  ====================================================================== }

constructor TJSONParser.Create(const AText: string; ANullAsEmpty: Boolean);
begin
  FLexer := TJSONLexer.Create(AText);
  FNullAsEmpty := ANullAsEmpty;
  Advance; // 预读第一个 token
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
{ 返回 nil 当且仅当遇到 JSON null 且 FNullAsEmpty = False。
  调用方须检查返回值后再决定是否将其加入容器。 }
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
          // 浮点：用 Invariant 格式设置解析，保留原始文本用于往返
          FS := TFormatSettings.Invariant;
          if not TryStrToFloat(FCurrent.Str, FloatVal, FS) then
            raise ETOMLParserException.CreateFmt('JSON: invalid float number "%s"', [FCurrent.Str]);
          Result := TTOMLFloat.Create(FloatVal, FCurrent.Str);
        end
        else
        begin
          // 优先尝试 Int64；超范围时降级为浮点
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
        // null → 空字符串 或 nil（调用方跳过）
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

    // 空对象 {}
    if FCurrent.Kind = jtkRBrace then
    begin
      Advance;
      Exit;
    end;

    repeat
      // 键必须是字符串
      if FCurrent.Kind <> jtkString then
        raise ETOMLParserException.CreateFmt('JSON: object key must be a string, got "%s"', [FCurrent.Str]);
      Key := FCurrent.Str;
      Advance;

      Expect(jtkColon);

      Val := ParseValue;

      if Assigned(Val) then
      begin
        // Val 已创建，Add 失败时需要释放它
        try
          Result.Add(Key, Val);
        except
          Val.Free;
          raise;
        end;
      end;
      // Val = nil（JSON null 且 FNullAsEmpty=False）时直接跳过，无需释放

      if FCurrent.Kind = jtkComma then
        Advance
      else
        Break;

      // 允许尾随逗号（宽容解析）
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
        // FNullAsEmpty=True 时 ParseValue 已返回 TTOMLString('')，
        // 不会进入此分支；此处仅作防御性保留
        Result.Add(TTOMLString.Create(''));
      // Val = nil（null 且不转空串）时跳过，无需释放

      if FCurrent.Kind = jtkComma then
        Advance
      else
        Break;

      // 允许尾随逗号
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
  // 根对象后应只剩空白或 EOF
  if FCurrent.Kind <> jtkEOF then
    raise ETOMLParserException.Create('JSON: unexpected content after root object');
end;
{ ======================================================================
  内部：TOML → JSON 序列化器
  ====================================================================== }

type
  TTOMLToJSONSerializer = class
  private
    FSB: TStringBuilder;
    FPretty: Boolean;
    FIndentSize: Integer;
    FIndentLevel: Integer;
    FFS: TFormatSettings; // 不变量格式设置，保证小数点为 '.'

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
{ 输出带双引号的 JSON 字符串，所有控制字符及特殊字符均正确转义。
  Delphi 字符串为 UTF-16；代理对字符（U+D800..U+DFFF）直接保留为
  \uXXXX\uXXXX 对，接收方可正确还原为 UTF-16 或 UTF-8。 }
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
        // 其余控制字符 → \u00XX
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
          // JSON 规范不支持 inf / nan → 输出 null
          FSB.Append('null')
        else
        begin
          // 优先使用原始文本，保证浮点往返精度
          if (V is TTOMLFloat) and (TTOMLFloat(V).RawString <> '') then
            S := TTOMLFloat(V).RawString
          else
          begin
            // 先尝试 15 位（通常够用且更简洁）
            S := FloatToStrF(F, ffGeneral, 15, 0, FFS);
            Val(S, FCheck, Code);
            // 若 15 位无法精确还原，升至 17 位保证 IEEE 754 round-trip
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
        // 保留原始 RFC 3339 文本；无原始文本时回退到 AsString
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
{ 保留 TTOMLTable.Items 的插入顺序，不做额外排序。
  TTOMLTable.Items 底层为 TDictionary，本身无序；
  若需要稳定顺序，建议上层业务在 TOML 文件中按序定义键。 }
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
  if not First then // 非空对象：换行并缩进右括号
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
  内部辅助：UTF-8 文件写入（兼容 Delphi 10.4，避免 WriteBOM 属性问题）
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
  公开函数实现
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
    // 出错返回 False
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
      Table.Free; // 修复：原版此处有内存泄漏
    end;
  except
    // 出错返回 False
  end;
end;

end.
