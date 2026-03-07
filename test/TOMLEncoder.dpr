program TOMLEncoder;
{$APPTYPE CONSOLE}
uses
  SysUtils,Winapi.Windows,System.Generics.Collections,
  Classes,
  System.JSON,
  System.Math,
  System.DateUtils,
  TOML.Types in 'TOML.Types.pas',
  TOML.Parser in 'TOML.Parser.pas',
  TOML.Serializer in 'TOML.Serializer.pas',
  TOML.Helper in 'TOML.Helper.pas';
{ 将 toml-test 的规范 JSON 转换为 TTOMLValue }
function JSONToTOMLValue(AJSON: TJSONValue): TTOMLValue;
var
  JSONObject: TJSONObject;
  JSONArray: TJSONArray;
  ValType, ValStr: string;
  I: Integer;
  NewTable: TTOMLTable;
  NewArray: TTOMLArray;
  Pair: TJSONPair;
begin
  if AJSON is TJSONObject then
  begin
    JSONObject := TJSONObject(AJSON);
    
    // 检查是否是叶子节点（带 type 和 value 的对象）
    if JSONObject.Count = 2 then
    begin
      if JSONObject.TryGetValue('type', ValType) and JSONObject.TryGetValue('value', ValStr) then
      begin
        if ValType = 'string' then
          Exit(TTOMLString.Create(ValStr))
        else if ValType = 'integer' then
          Exit(TTOMLInteger.Create(StrToInt64(ValStr)))
        else if ValType = 'float' then
        begin
          if ValStr = 'nan' then Exit(TTOMLFloat.Create(NaN, 'nan'))
          else if ValStr = 'inf' then Exit(TTOMLFloat.Create(Infinity, 'inf'))
          else if ValStr = '-inf' then Exit(TTOMLFloat.Create(NegInfinity, '-inf'))
          // ✨ 核心修复：传入 ValStr 作为第二个参数 (RawString)
          else Exit(TTOMLFloat.Create(StrToFloat(ValStr, TFormatSettings.Invariant), ValStr));
        end
        else if ValType = 'bool' then
          Exit(TTOMLBoolean.Create(ValStr = 'true'))
        else if (ValType = 'datetime') or (ValType = 'datetime-local') or 
                (ValType = 'date-local') or (ValType = 'time-local') then
        begin
          // 使用你的 Parser 逻辑解析日期字符串以获得正确的 Kind
          // 注意：这里我们构造一个临时 TOML 来利用 Parser 的日期解析能力
          var TempParser := TTOMLParser.Create('v = ' + ValStr);
          try
             // 实际上 toml-test 的日期已经是 ISO 格式，直接创建即可
             // 我们根据 type 映射 Kind
             var Kind: TTOMLDateTimeKind;
             if ValType = 'datetime' then Kind := tdkOffsetDateTime
             else if ValType = 'datetime-local' then Kind := tdkLocalDateTime
             else if ValType = 'date-local' then Kind := tdkLocalDate
             else Kind := tdkLocalTime;
             
             // 这里简化处理，直接传入原始字符串以保证序列化一致性
             Exit(TTOMLDateTime.Create(0, ValStr, Kind, 0));
          finally
            TempParser.Free;
          end;
        end;
      end;
    end;
    // 否则它是一个 Table
    NewTable := TTOMLTable.Create;
    for Pair in JSONObject do
      NewTable.Add(Pair.JsonString.Value, JSONToTOMLValue(Pair.JsonValue));
    Exit(NewTable);
  end
  else if AJSON is TJSONArray then
  begin
    JSONArray := TJSONArray(AJSON);
    NewArray := TTOMLArray.Create;
    for I := 0 to JSONArray.Count - 1 do
      NewArray.Add(JSONToTOMLValue(JSONArray.Items[I]));
    Exit(NewArray);
  end;
  Result := nil;
end;
var
  InputText: string;
  JSONValue: TJSONValue;
  TOMLValue: TTOMLValue;
  TOMLString: string;
  InputStream: THandleStream;
  Reader: TStreamReader;
begin
  SetConsoleOutputCP(CP_UTF8);
  try
    // 1. 读取 Stdin 传入的 JSON
    InputStream := THandleStream.Create(GetStdHandle(STD_INPUT_HANDLE));
    try
      Reader := TStreamReader.Create(InputStream, TEncoding.UTF8);
      try
        InputText := Reader.ReadToEnd;
      finally
        Reader.Free;
      end;
    finally
      InputStream.Free;
    end;
    if InputText.IsEmpty then Halt(0);
    // 2. 解析 JSON 结构
    JSONValue := TJSONObject.ParseJSONValue(InputText);
    if not Assigned(JSONValue) then Halt(1);
    try
      // 3. 转换为 TOML 对象模型
      TOMLValue := JSONToTOMLValue(JSONValue);
      if not Assigned(TOMLValue) then Halt(1);
      try
        // 4. 序列化为 TOML 文本并输出
        TOMLString := SerializeTOML(TOMLValue);
        // --- ✨ 核心修复：强制以 UTF-8 编码写入标准输出 ---
        var StdOutStream := THandleStream.Create(GetStdHandle(STD_OUTPUT_HANDLE));
        try
          // 使用 TEncoding.UTF8 显式转换，并且不带 BOM (toml-test 通常不需要 BOM)
          var UTF8Bytes: TBytes := TEncoding.UTF8.GetBytes(TOMLString);
          if Length(UTF8Bytes) > 0 then
            StdOutStream.WriteBuffer(UTF8Bytes[0], Length(UTF8Bytes));
        finally
          StdOutStream.Free;
        end;
      finally
        TOMLValue.Free;
      end;
    finally
      JSONValue.Free;
    end;
  except
    on E: Exception do
    begin
      Writeln(ErrOutput, 'Error: ' + E.Message);
      ExitCode := 1;
      Halt(1);
    end;
  end;
end.