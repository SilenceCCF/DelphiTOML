program TOMLDecoder;
{$APPTYPE CONSOLE}

uses
  SysUtils,
  System.Generics.Collections,
  Winapi.Windows,
  Classes,
  System.JSON,
  Math,
  System.DateUtils,
  TOML,
  TOML.Types in 'TOML.Types.pas',
  TOML.Parser in 'TOML.Parser.pas',
  TOML.Serializer in 'TOML.Serializer.pas',
  TOML.Helper in 'TOML.Helper.pas';

function IsValidUTF8(const Bytes: TBytes): Boolean;
var
  i, len: Integer;
  b1: Byte;
begin
  i := 0;
  len := Length(Bytes);
  // 跳过可能的 UTF-8 BOM (EF BB BF)
  if (len >= 3) and (Bytes[0] = $EF) and (Bytes[1] = $BB) and (Bytes[2] = $BF) then
    i := 3;

  while i < len do
  begin
    b1 := Bytes[i];
    if b1 <= $7F then // 1 byte: 00-7F
      Inc(i)
    else if (b1 >= $C2) and (b1 <= $DF) then // 2 bytes: C2-DF + 80-BF
    begin
      if (i + 1 >= len) or ((Bytes[i + 1] and $C0) <> $80) then
        Exit(False);
      Inc(i, 2);
    end
    else if (b1 >= $E0) and (b1 <= $EF) then // 3 bytes
    begin
      if (i + 2 >= len) or ((Bytes[i + 1] and $C0) <> $80) or ((Bytes[i + 2] and $C0) <> $80) then
        Exit(False);
      // Overlong: E0 A0..
      if (b1 = $E0) and (Bytes[i + 1] < $A0) then
        Exit(False);
      // Surrogates: ED A0..
      if (b1 = $ED) and (Bytes[i + 1] >= $A0) then
        Exit(False);
      Inc(i, 3);
    end
    else if (b1 >= $F0) and (b1 <= $F4) then // 4 bytes
    begin
      if (i + 3 >= len) or ((Bytes[i + 1] and $C0) <> $80) or ((Bytes[i + 2] and $C0) <> $80) or ((Bytes[i + 3]
        and $C0) <> $80) then
        Exit(False);
      // Overlong: F0 90..
      if (b1 = $F0) and (Bytes[i + 1] < $90) then
        Exit(False);
      // ✨ 修复点：上限是 F4 8F BF BF，所以只有 > $8F 才是非法的
      if (b1 = $F4) and (Bytes[i + 1] > $8F) then
        Exit(False);
      Inc(i, 4);
    end
    else
      Exit(False);
  end;
  Result := True;
end;

{ 手动将 TTOMLValue 序列化为 toml-test 要求的符合规范的 JSON 字符串 }
{ 这样可以避开 System.JSON 过滤空键名的 Bug }
function RenderTOMLValueToJSON(AValue: TTOMLValue): string;
var
  SB: TStringBuilder;
  I: Integer;
  Keys: TList<string>;
  K: string;
//  JV: TJSONValue; // 用于安全转义字符串

  // 内部辅助：安全地将字符串转为 JSON 编码格式

  function EscapeJSON(const S: string): string;
  var
    JS: TJSONString;
  begin
    JS := TJSONString.Create(S);
    try
      Result := JS.ToJSON;
    finally
      JS.Free;
    end;
  end;

begin
  if AValue = nil then
    Exit('null');
  case AValue.ValueType of
    tvtString:
      Result := Format('{"type":"string","value":%s}', [EscapeJSON(AValue.AsString)]);

    tvtInteger:
      Result := Format('{"type":"integer","value":"%s"}', [IntToStr(AValue.AsInteger)]);

    tvtFloat:
      // ... (保留之前的 tvtFloat 逻辑，但使用 EscapeJSON)
      begin
        var TF := TTOMLFloat(AValue);
        var VStr: string;
        if TF.RawString <> '' then
          VStr := TF.RawString
        else if IsNan(TF.Value) then
          VStr := 'nan'
        else if IsInfinite(TF.Value) then
        begin
          if TF.Value > 0 then
            VStr := 'inf'
          else
            VStr := '-inf';
        end
        else
          VStr := FloatToStrF(TF.Value, ffGeneral, 15, 0, TFormatSettings.Invariant);
        Result := Format('{"type":"float","value":"%s"}', [VStr]);
      end;

    tvtBoolean:
      begin
        var B: string;
        if AValue.AsBoolean then
          B := 'true'
        else
          B := 'false';
        Result := Format('{"type":"bool","value":"%s"}', [B]);
      end;

    tvtDateTime:
      begin
        var DT := TTOMLDateTime(AValue);
        var TypeStr, ValStr: string;
        var FS: TFormatSettings;
        var MS: Word;
        FS := TFormatSettings.Invariant;

        // 使用 System.DateUtils 获取毫秒
        MS := System.DateUtils.MilliSecondOf(DT.Value);

        case DT.Kind of
          tdkOffsetDateTime:
            begin
              TypeStr := 'datetime';
              // 1. 基础部分：强制包含秒数 (hh:nn:ss)，强制使用 T 分隔符
              ValStr := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', DT.Value, FS);
              // 2. 毫秒部分：按需补齐
              if MS > 0 then
                ValStr := ValStr + '.' + Format('%.3d', [MS]);

              // 3. 时区部分：处理 Z 或 ±HH:MM
              if DT.TimeZoneOffset = 0 then
                ValStr := ValStr + 'Z'
              else
              begin
                var H := Abs(DT.TimeZoneOffset) div 60;
                var M := Abs(DT.TimeZoneOffset) mod 60;
                var Sign := '+';
                if DT.TimeZoneOffset < 0 then
                  Sign := '-';
                ValStr := ValStr + Format('%s%.2d:%.2d', [Sign, H, M]);
              end;
            end;

          tdkLocalDateTime:
            begin
              TypeStr := 'datetime-local';
              // 强制归一化：包含秒数，使用 T 分隔符
              ValStr := FormatDateTime('yyyy-mm-dd"T"hh:nn:ss', DT.Value, FS);
              if MS > 0 then
                ValStr := ValStr + '.' + Format('%.3d', [MS]);
            end;

          tdkLocalDate:
            begin
              TypeStr := 'date-local';
              ValStr := FormatDateTime('yyyy-mm-dd', DT.Value, FS);
            end;

          tdkLocalTime:
            begin
              TypeStr := 'time-local';
              // 强制归一化：输入 13:37 也要变成 13:37:00
              ValStr := FormatDateTime('hh:nn:ss', DT.Value, FS);
              if MS > 0 then
                ValStr := ValStr + '.' + Format('%.3d', [MS]);
            end;
        end;
        Result := Format('{"type":"%s","value":"%s"}', [TypeStr, ValStr]);
      end;

    tvtArray:
      begin
        SB := TStringBuilder.Create;
        try
          SB.Append('[');
          for I := 0 to AValue.AsArray.Count - 1 do
          begin
            if I > 0 then
              SB.Append(',');
            SB.Append(RenderTOMLValueToJSON(AValue.AsArray.GetItem(I)));
          end;
          SB.Append(']');
          Result := SB.ToString;
        finally
          SB.Free;
        end;
      end;

    tvtTable, tvtInlineTable:
      begin
        SB := TStringBuilder.Create;
        try
          SB.Append('{');
          Keys := TList<string>.Create;
          try
            for K in AValue.AsTable.Items.Keys do
              Keys.Add(K);
            Keys.Sort;
            for I := 0 to Keys.Count - 1 do
            begin
              if I > 0 then
                SB.Append(',');
              SB.Append(EscapeJSON(Keys[I])).Append(':').Append(RenderTOMLValueToJSON(AValue.AsTable.Items[Keys[I]]));
            end;
          finally
            Keys.Free;
          end;
          SB.Append('}');
          Result := SB.ToString;
        finally
          SB.Free;
        end;
      end;
  else
    Result := 'null';
  end;
end;

var
  InputText: string;
  TOMLTable: TTOMLTable;
  JSONStr: string;
  InputBytes: TBytes;
  MemStream: TMemoryStream;
  InStream: THandleStream;
  BytesRead: Integer;
  Buffer: array[0..4095] of Byte;

begin
  try
  // 1. 从 Stdin 读取原始字节流
    MemStream := TMemoryStream.Create;
    InStream := THandleStream.Create(GetStdHandle(Winapi.Windows.STD_INPUT_HANDLE));
    try
      repeat
        BytesRead := InStream.Read(Buffer, SizeOf(Buffer));
        if BytesRead > 0 then
          MemStream.Write(Buffer, BytesRead);
      until BytesRead = 0;

      if MemStream.Size > 0 then
      begin
        SetLength(InputBytes, MemStream.Size);
        Move(MemStream.Memory^, InputBytes[0], MemStream.Size);

        if not IsValidUTF8(InputBytes) then
        begin
          Writeln(ErrOutput, 'Parse Error: Invalid UTF-8');
          Halt(1);
        end;

      // 如果有 BOM，getString 前三个字节要去掉
        var Offset := 0;
        if (Length(InputBytes) >= 3) and (InputBytes[0] = $EF) and (InputBytes[1] = $BB) and (InputBytes[2] = $BF) then
          Offset := 3;

        InputText := TEncoding.UTF8.GetString(InputBytes, Offset, Length(InputBytes) - Offset);
      end;
    finally
      InStream.Free;
      MemStream.Free;
    end;

    try
      TOMLTable := ParseTOMLString(InputText);
      try
        // ✨ 使用我们自定义的递归渲染函数
        JSONStr := RenderTOMLValueToJSON(TOMLTable);
        //Writeln(JSONStr);
      // ✨ 同样使用 StdOutStream 强制 UTF-8 输出
        var StdOutStream := THandleStream.Create(GetStdHandle(STD_OUTPUT_HANDLE));
        try
          var UTF8Bytes := TEncoding.UTF8.GetBytes(JSONStr);
          if Length(UTF8Bytes) > 0 then
            StdOutStream.WriteBuffer(UTF8Bytes[0], Length(UTF8Bytes));
        finally
          StdOutStream.Free;
        end;
      finally
        TOMLTable.Free;
      end;
    except
      on E: Exception do
      begin
        Writeln(ErrOutput, 'Parse Error: ' + E.Message);
        ExitCode := 1;
      end;
    end;
  except
    on E: Exception do
    begin
      Writeln(ErrOutput, 'Fatal Error: ' + E.Message);
      ExitCode := 1;
      Halt(1);
    end;
  end;
  Halt(0);
end.

