{ TOML_Types.pas
  TOML 核心数据类型定义单元。
  本单元定义了表示 TOML 数据结构所需的全部类型和类，包括：
    - 基本类型（字符串、整数、浮点数、布尔值、日期时间）
    - 复合类型（数组、表）
    - 类型转换与校验
    - TOML 数据结构的内存管理

  类型系统遵循 TOML v1.1.0 规范，通过运行时类型检查和显式类型转换保证类型安全。
}
unit TOML.Types;

interface

uses
  SysUtils, Generics.Collections, strutils;

type
  { TOML 值类型枚举 —— 对应 TOML 规范中所有可能的数据类型 }
  TTOMLValueType = (
    tvtString,      // 字符串（基本字符串和字面量字符串）
    tvtInteger,     // 整数（十进制、十六进制、八进制、二进制）
    tvtFloat,       // 浮点数（含指数表示法）
    tvtBoolean,     // 布尔值（true / false）
    tvtDateTime,    // 日期时间（RFC 3339）
    tvtArray,       // 数组（有序值列表）
    tvtTable,       // 表（键值对集合）
    tvtInlineTable  // 内联表（紧凑格式的表）
  );

  { TOML 日期时间子类型 —— 对应 TOML 1.0.0 规范中的四种日期时间形式 }
  TTOMLDateTimeKind = (
    tdkOffsetDateTime,  // 带时区偏移的日期时间：1979-05-27T07:32:00Z 或 1979-05-27T00:32:00-07:00
    tdkLocalDateTime,   // 本地日期时间：1979-05-27T07:32:00
    tdkLocalDate,       // 本地日期：1979-05-27
    tdkLocalTime        // 本地时间：07:32:00
  );

  { 前向声明（相互依赖类型） }
  TTOMLValue = class;
  TTOMLArray = class;
  TTOMLTable = class;

  { TOML 异常基类 }
  ETOMLException = class(Exception);
  { TOML 解析异常 }
  ETOMLParserException = class(ETOMLException);
  { TOML 序列化异常 }
  ETOMLSerializerException = class(ETOMLException);

  { TOML 表的键值字典，键为字符串，大小写敏感 }
  TTOMLTableDict = TDictionary<string, TTOMLValue>;
  { TOML 数组的值列表（有序） }
  TTOMLValueList = TList<TTOMLValue>;

  { TOML 值基类 —— 所有 TOML 值类型的抽象基类，
    提供公共接口和类型转换方法 }
  TTOMLValue = class
  private
    FValueType: TTOMLValueType;
  protected
    { 子类按需重写以下类型转换方法，不支持时抛出 ETOMLException }
    function GetAsString: string; virtual;
    function GetAsInteger: Int64; virtual;
    function GetAsFloat: Double; virtual;
    function GetAsBoolean: Boolean; virtual;
    function GetAsDateTime: TDateTime; virtual;
    function GetAsArray: TTOMLArray; virtual;
    function GetAsTable: TTOMLTable; virtual;
  public
    { 构造函数
      @param AType 该 TOML 值的类型 }
    constructor Create(AType: TTOMLValueType);
    destructor Destroy; override;

    { 值的类型 }
    property ValueType: TTOMLValueType read FValueType;
    { 以下属性读取时若类型不符将抛出 ETOMLException }
    property AsString: string read GetAsString;
    property AsInteger: Int64 read GetAsInteger;
    property AsFloat: Double read GetAsFloat;
    property AsBoolean: Boolean read GetAsBoolean;
    property AsDateTime: TDateTime read GetAsDateTime;
    property AsArray: TTOMLArray read GetAsArray;
    property AsTable: TTOMLTable read GetAsTable;
  end;

  { TOML 字符串值（基本字符串或字面量字符串） }
  TTOMLString = class(TTOMLValue)
  private
    FValue: string;
  protected
    function GetAsString: string; override;
  public
    constructor Create(const AValue: string);
    property Value: string read FValue write FValue;
  end;

  { TOML 整数值（十进制、十六进制、八进制、二进制） }
  TTOMLInteger = class(TTOMLValue)
  private
    FValue: Int64;
  protected
    function GetAsInteger: Int64; override;
    function GetAsFloat: Double; override;  // 允许隐式转换为浮点数
  public
    constructor Create(const AValue: Int64);
    property Value: Int64 read FValue write FValue;
  end;

  { TOML 浮点数值（含指数表示法、inf、nan） }
  TTOMLFloat = class(TTOMLValue)
  private
    FValue: Double;
    FRawString: string; // 保存原始文本表示，用于精确往返（round-trip）
  protected
    function GetAsFloat: Double; override;
  public
    { @param AValue      双精度浮点值
      @param ARawString  原始文本（可选，用于保持序列化精度） }
    constructor Create(const AValue: Double; const ARawString: string = '');
    property Value: Double read FValue write FValue;
    property RawString: string read FRawString write FRawString;
  end;

  { TOML 布尔值（true / false） }
  TTOMLBoolean = class(TTOMLValue)
  private
    FValue: Boolean;
  protected
    function GetAsBoolean: Boolean; override;
  public
    constructor Create(const AValue: Boolean);
    property Value: Boolean read FValue write FValue;
  end;

  { TOML 日期时间值（RFC 3339 格式），
    支持带时区偏移的日期时间、本地日期时间、本地日期和本地时间四种子类型 }
  TTOMLDateTime = class(TTOMLValue)
  private
    FValue: TDateTime;
    FRawString: string;        // 保存原始文本，确保序列化时格式精确还原
    FKind: TTOMLDateTimeKind;  // 日期时间子类型
    FTimeZoneOffset: Integer;  // 时区偏移（分钟），仅适用于 tdkOffsetDateTime
  protected
    function GetAsDateTime: TDateTime; override;
    function GetAsString: string; override;
  public
    { @param ADateTime        TDateTime 值
      @param ARawString       原始文本（可选，用于精确格式还原）
      @param AKind            日期时间子类型（默认：带时区偏移）
      @param ATimeZoneOffset  时区偏移（分钟，默认 0 = UTC） }
    constructor Create(const ADateTime: TDateTime; const ARawString: string = '';
      AKind: TTOMLDateTimeKind = tdkOffsetDateTime; ATimeZoneOffset: Integer = 0);
    property Value: TDateTime read FValue write FValue;
    property RawString: string read FRawString write FRawString;
    property Kind: TTOMLDateTimeKind read FKind write FKind;
    property TimeZoneOffset: Integer read FTimeZoneOffset write FTimeZoneOffset;
  end;

  { TOML 数组值（有序值列表，元素可为任意 TOML 类型） }
  TTOMLArray = class(TTOMLValue)
  private
    FItems: TTOMLValueList;
  protected
    function GetAsArray: TTOMLArray; override;
  public
    constructor Create;
    destructor Destroy; override;

    { 向数组末尾追加一个值（数组取得该值的所有权）
      @param AValue 要添加的 TOML 值 }
    procedure Add(AValue: TTOMLValue);

    { 获取指定位置的元素
      @param Index 从零开始的索引
      @raises EListError 若索引越界 }
    function GetItem(Index: Integer): TTOMLValue;

    { 返回数组元素数量 }
    function GetCount: Integer;

    property Items: TTOMLValueList read FItems;
    property Count: Integer read GetCount;
  end;

  { TOML 表值（键值对集合，键大小写敏感） }
  TTOMLTable = class(TTOMLValue)
  private
    FItems: TTOMLTableDict;
    FIsImplicit: Boolean; // True 表示该表由点号键路径隐式创建（如 a.b = 1 中的 a）
    FIsInline: Boolean;   // True 表示该表由内联语法定义（如 a = { b = 1 }），不可通过表头扩展
  protected
    function GetAsTable: TTOMLTable; override;
  public
    constructor Create;
    destructor Destroy; override;

    { 向表中添加键值对（取得值的所有权）
      @param AKey   键名
      @param AValue 值
      @raises ETOMLParserException 若键已存在 }
    procedure Add(const AKey: string; AValue: TTOMLValue);

    { 按键查找值
      @param AKey   要查找的键
      @param AValue 输出参数，找到时返回对应值
      @returns True 若键存在，否则 False }
    function TryGetValue(const AKey: string; out AValue: TTOMLValue): Boolean;

    property Items: TTOMLTableDict read FItems;
    { 是否为隐式创建的表（通过点号键路径自动生成） }
    property IsImplicit: Boolean read FIsImplicit write FIsImplicit;
    // 是否为内联表（通过 { } 语法定义，内容不可追加）
    property IsInline: Boolean read FIsInline write FIsInline;
  end;

implementation

{ TTOMLValue }

constructor TTOMLValue.Create(AType: TTOMLValueType);
begin
  inherited Create;
  FValueType := AType;
end;

destructor TTOMLValue.Destroy;
begin
  inherited Destroy;
end;

function TTOMLValue.GetAsString: string;
begin
  Result := '';
  raise ETOMLException.Create('Cannot convert this TOML value to string');
end;

function TTOMLValue.GetAsInteger: Int64;
begin
  Result := 0;
  raise ETOMLException.Create('Cannot convert this TOML value to integer');
end;

function TTOMLValue.GetAsFloat: Double;
begin
  Result := 0.0;
  raise ETOMLException.Create('Cannot convert this TOML value to float');
end;

function TTOMLValue.GetAsBoolean: Boolean;
begin
  Result := False;
  raise ETOMLException.Create('Cannot convert this TOML value to boolean');
end;

function TTOMLValue.GetAsDateTime: TDateTime;
begin
  Result := 0;
  raise ETOMLException.Create('Cannot convert this TOML value to datetime');
end;

function TTOMLValue.GetAsArray: TTOMLArray;
begin
  Result := nil;
  raise ETOMLException.Create('Cannot convert this TOML value to array');
end;

function TTOMLValue.GetAsTable: TTOMLTable;
begin
  Result := nil;
  raise ETOMLException.Create('Cannot convert this TOML value to table');
end;

{ TTOMLString }

constructor TTOMLString.Create(const AValue: string);
begin
  inherited Create(tvtString);
  FValue := AValue;
end;

function TTOMLString.GetAsString: string;
begin
  Result := FValue;
end;

{ TTOMLInteger }

constructor TTOMLInteger.Create(const AValue: Int64);
begin
  inherited Create(tvtInteger);
  FValue := AValue;
end;

function TTOMLInteger.GetAsInteger: Int64;
begin
  Result := FValue;
end;

function TTOMLInteger.GetAsFloat: Double;
begin
  Result := FValue;
end;

{ TTOMLFloat }

constructor TTOMLFloat.Create(const AValue: Double; const ARawString: string);
begin
  inherited Create(tvtFloat);
  FValue := AValue;
  FRawString := ARawString;
end;

function TTOMLFloat.GetAsFloat: Double;
begin
  Result := FValue;
end;

{ TTOMLBoolean }

constructor TTOMLBoolean.Create(const AValue: Boolean);
begin
  inherited Create(tvtBoolean);
  FValue := AValue;
end;

function TTOMLBoolean.GetAsBoolean: Boolean;
begin
  Result := FValue;
end;

{ TTOMLDateTime }

constructor TTOMLDateTime.Create(const ADateTime: TDateTime; const ARawString: string;
  AKind: TTOMLDateTimeKind; ATimeZoneOffset: Integer);
begin
  inherited Create(tvtDateTime);
  FValue := ADateTime;
  FRawString := ARawString;
  FKind := AKind;
  FTimeZoneOffset := ATimeZoneOffset;
end;

function TTOMLDateTime.GetAsString: string;
var
  Hours, Minutes: Integer;
  Sign: Char;
begin
  // 优先使用原始文本，保证序列化精确还原
  if FRawString <> '' then
  begin
    Result := FRawString;
    Exit;
  end;

  // 按日期时间子类型格式化输出
  case FKind of
    tdkLocalDate:
      Result := FormatDateTime('yyyy-mm-dd', FValue);

    tdkLocalTime:
      Result := FormatDateTime('hh:nn:ss', FValue);

    tdkLocalDateTime:
      Result := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', FValue);

    tdkOffsetDateTime:
      begin
        if FTimeZoneOffset = 0 then
          Result := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss"Z"', FValue)
        else
        begin
          Hours   := Abs(FTimeZoneOffset) div 60;
          Minutes := Abs(FTimeZoneOffset) mod 60;
          Sign    := IfThen(FTimeZoneOffset < 0, '-', '+')[1];
          Result  := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', FValue)
                   + Format('%s%.2d:%.2d', [Sign, Hours, Minutes]);
        end;
      end;
  end;
end;

function TTOMLDateTime.GetAsDateTime: TDateTime;
begin
  Result := FValue;
end;

{ TTOMLArray }

constructor TTOMLArray.Create;
begin
  inherited Create(tvtArray);
  FItems := TTOMLValueList.Create;
end;

destructor TTOMLArray.Destroy;
var
  Item: TTOMLValue;
begin
  for Item in FItems do
    Item.Free;
  FItems.Free;
  inherited Destroy;
end;

procedure TTOMLArray.Add(AValue: TTOMLValue);
begin
  FItems.Add(AValue);
end;

function TTOMLArray.GetItem(Index: Integer): TTOMLValue;
begin
  Result := FItems[Index];
end;

function TTOMLArray.GetCount: Integer;
begin
  Result := FItems.Count;
end;

function TTOMLArray.GetAsArray: TTOMLArray;
begin
  Result := Self;
end;

{ TTOMLTable }

constructor TTOMLTable.Create;
begin
  inherited Create(tvtTable);
  FItems      := TTOMLTableDict.Create;
  FIsImplicit := False;
  FIsInline   := False;
end;

destructor TTOMLTable.Destroy;
var
  Item: TTOMLValue;
begin
  for Item in FItems.Values do
    Item.Free;
  FItems.Free;
  inherited Destroy;
end;

procedure TTOMLTable.Add(const AKey: string; AValue: TTOMLValue);
var
  ExistingValue: TTOMLValue;
begin
  if FItems = nil then
    FItems := TTOMLTableDict.Create;

  if FItems.TryGetValue(AKey, ExistingValue) then
    raise ETOMLParserException.CreateFmt('Duplicate key "%s" found', [AKey]);

  FItems.AddOrSetValue(AKey, AValue);
end;

function TTOMLTable.TryGetValue(const AKey: string; out AValue: TTOMLValue): Boolean;
begin
  Result := FItems.TryGetValue(AKey, AValue);
end;

function TTOMLTable.GetAsTable: TTOMLTable;
begin
  Result := Self;
end;

end.
