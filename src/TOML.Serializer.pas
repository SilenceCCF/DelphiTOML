(* TOML_Serializer.pas
  TOML 数据结构序列化单元。
  本单元将 TOML 对象转换为符合 TOML v1.1.0 规范的文本格式，支持：
    - 键值对（含键名自动引号与转义）
    - 普通表 [table] 和数组表 [[array]]
    - 内联表 { key = value, ... }
    - 数组 [ ... ]
    - 基本字符串（含转义）
    - 整数和浮点数（含 inf / nan，保持原始精度）
    - 布尔值
    - 日期时间（RFC 3339，优先使用原始文本）
  实现要点：
    - 使用 TStringBuilder 高效构建字符串
    - 遍历表键时先排序，保证输出顺序确定
    - 键值对先于子表和数组表输出（符合 TOML 规范要求）
    - 每个表段的路径通过 FCurrentPath 跟踪，用于生成 [a.b.c] 头部
*)
unit TOML.Serializer;

interface

uses
  SysUtils, Classes, Math, TOML.Types, Generics.Collections;
{$IF CompilerVersion < 20.0}
function CharInSet(C: Char; const CharSet: TSysCharSet): Boolean; inline;
{$IFEND}

type
  { 键值对类型（用于表字典的枚举） }
  TTOMLKeyValuePair = TPair<string, TTOMLValue>;
  { TOML 序列化器 —— 将 TOML 数据结构转换为文本格式 }
  TTOMLSerializer = class
  private
    FStringBuilder: TStringBuilder;   // 输出缓冲区
    FIndentLevel: Integer;            // 当前缩进层次
    FCurrentPath: TStringList;        // 当前表路径（用于生成表头）
    FFormatSettings: TFormatSettings; // 不变量格式设置（小数点为 '.'，不受本地化影响）

    { 写入当前缩进空格 }
    procedure WriteIndent;

    { 写入一行文本（含尾部换行），ALine 为空时只写换行 }
    procedure WriteLine(const ALine: string = '');

    { 写入单个键，必要时加引号并转义 }
    procedure WriteKey(const AKey: string);

    { 写入带引号的字符串值（含 TOML 规范转义） }
    procedure WriteString(const AValue: string);

    { 根据值类型分派到对应的写入方法 }
    procedure WriteValue(const AValue: TTOMLValue);

    //{ 写入表（AInline=True 时输出内联格式 { ... }，否则输出标准块格式） }
    procedure WriteTable(const ATable: TTOMLTable; const AInline: Boolean = False);

    { 写入数组，始终输出 [ ... ] 格式（是否用 [[header]] 由 WriteTable 决定） }
    procedure WriteArray(const AArray: TTOMLArray);

    { 写入日期时间值（优先使用原始文本，否则按 Kind 格式化输出） }
    procedure WriteDateTime(const ADateTimeValue: TTOMLValue);

    { 构建当前完整表路径字符串，形如 "a.b.\"c.d\""，
      供 [path] 或 [[path]] 头部使用 }
    function BuildTablePath(const NewKey: string): string;

    { 判断键名是否需要加引号
      （仅包含 A-Z、a-z、0-9、_ 和 - 的键无需引号） }
    function NeedsQuoting(const AKey: string): Boolean;

  public
    constructor Create;
    destructor Destroy; override;

    { 将 TOML 值序列化为字符串
      @param AValue 要序列化的值
      @returns TOML 格式文本
      @raises ETOMLSerializerException 若值无法序列化 }
    function Serialize(const AValue: TTOMLValue): string;
  end;
{ 将 TOML 值序列化为字符串（高层封装）
  @raises ETOMLSerializerException 若值无法序列化 }
function SerializeTOML(const AValue: TTOMLValue): string;
{ 将 TOML 值序列化并写入文件（高层封装）
  @param BOM 是否写入 UTF-8 BOM（默认 True）
  @returns True 若成功，否则 False }
function SerializeTOMLToFile(const AValue: TTOMLValue; const AFileName: string; BOM: Boolean = True): Boolean;

implementation
{$IF CompilerVersion < 20.0}

function CharInSet(C: Char; const CharSet: TSysCharSet): Boolean;
begin
  Result := C in CharSet;
end;
{$IFEND}

{ 高层函数实现 }

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
    // 发生任何错误时返回 False
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

  // 使用不变量格式设置，保证小数点始终为 '.'，不受系统区域影响
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
  // 空键必须加引号
  if AKey = '' then
    Exit(True);

  // 仅含 A-Z、a-z、0-9、_ 或 - 的键无需引号
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
  { 追加单个路径段，含特殊字符时加双引号并转义 }

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
          // 转义所有控制字符（0x00-0x1F 及 0x7F）
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
  // 单个键段：含特殊字符（包括点号）时需加引号
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
        FStringBuilder.Append('\b');  // 退格
      #9:
        FStringBuilder.Append('\t');  // 制表符
      #10:
        FStringBuilder.Append('\n');  // 换行
      #12:
        FStringBuilder.Append('\f');  // 换页
      #13:
        FStringBuilder.Append('\r');  // 回车
      '"':
        FStringBuilder.Append('\"');  // 双引号
      '\':
        FStringBuilder.Append('\\');  // 反斜杠
    else
      // 转义所有控制字符（0x00-0x1F 及 0x7F）
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
  { 计算并追加小数秒（如有） }

  procedure AppendFractionalSeconds;
  begin
    FracSec := Frac(DateTimeVal.Value) * 24 * 3600;
    SecInt := Trunc(FracSec);
    FracPart := FracSec - SecInt;
    if FracPart > 0.0 then
    begin
      FracStr := FloatToStrF(FracPart, ffFixed, 15, 6, FFormatSettings);
      // 去掉前导 "0"，保留小数点及后续数字
      if (Length(FracStr) > 2) and (FracStr[1] = '0') and (FracStr[2] = '.') then
        Delete(FracStr, 1, 1);
      Str := Str + FracStr;
    end;
  end;

begin
  if not (ADateTimeValue is TTOMLDateTime) then
    raise ETOMLSerializerException.Create('Invalid datetime value type');

  DateTimeVal := TTOMLDateTime(ADateTimeValue);

  // 优先使用原始文本，保证格式精确还原
  if DateTimeVal.RawString <> '' then
  begin
    FStringBuilder.Append(DateTimeVal.RawString);
    Exit;
  end;

  // 按日期时间子类型生成文本
  case DateTimeVal.Kind of
    tdkLocalDate:
      // 本地日期：1979-05-27
      Str := FormatDateTime('yyyy-mm-dd', DateTimeVal.Value);

    tdkLocalTime:
      begin
        // 本地时间：07:32:00[.999999]
        Str := FormatDateTime('hh:nn:ss', DateTimeVal.Value);
        AppendFractionalSeconds;
      end;

    tdkLocalDateTime:
      begin
        // 本地日期时间：1979-05-27T07:32:00[.999999]
        Str := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', DateTimeVal.Value);
        AppendFractionalSeconds;
      end;

    tdkOffsetDateTime:
      begin
        // 带时区偏移的日期时间：1979-05-27T07:32:00[.999999]Z 或 +HH:MM / -HH:MM
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
  // 数组始终输出 [ ... ] 格式，是否改用 [[header]] 由 WriteTable 负责判断
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

        // 处理特殊浮点值
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
          // 优先使用原始文本（保留解析时的精度）
          if (AValue is TTOMLFloat) and (TTOMLFloat(AValue).RawString <> '') then
            S := TTOMLFloat(AValue).RawString
          else
          begin
            // 智能精度：先尝试 15 位，若往返不一致则改用 17 位
            S := FloatToStrF(F, ffGeneral, 15, 0, FFormatSettings);
            Val(S, CheckV, Code);
            if (Code <> 0) or (CheckV <> F) then
              S := FloatToStrF(F, ffGeneral, 17, 0, FFormatSettings);
          end;

          // TOML 规范：浮点数文本中必须包含 '.' 或 'e'，
          // 若两者均不存在（如整数样式），则补充 ".0"
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
      // 嵌套在值位置的表始终以内联格式输出
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
  { 判断值是否为"数组表"（数组且所有元素均为 TVtTable） }

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
    // ---- 内联表：{ key = value, ... } ----
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
    // ---- 标准块表 ----
    SortedKeys := TList<string>.Create;
    try
      for K in ATable.Items.Keys do
        SortedKeys.Add(K);
      SortedKeys.Sort;

      // 第一轮：输出所有普通键值对（非子表、非数组表）
      // TOML 规范要求键值对必须出现在子表头部之前
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

      // 第二轮：输出数组表 [[key]] 和普通子表 [key]
      for K in SortedKeys do
      begin
        V := ATable.Items[K];

        // 处理数组表 [[key]]
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

        // 处理普通子表 [key]
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
