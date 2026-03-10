🇺🇸 [English](TOML_Helper_Documentation.md) | 🇨🇳 [简体中文](TOML_Helper_Documentation_CN.md)
# TOML.Helper.pas 功能说明文档

## 📋 概述

`TOML.Helper.pas` 是为 TOML 库添加的辅助单元，提供了一套简洁易用的 API，极大地简化了 TOML 配置文件的读写操作。本单元通过 Class Helper 技术扩展了 `TTOMLTable` 和 `TTOMLArray` 类的功能，无需修改原始类定义。

**主要特性：**
- ✅ 类型安全的读写方法
- ✅ 默认值支持
- ✅ 异常安全（不会崩溃）
- ✅ 流畅的构建器模式
- ✅ 覆盖保护机制
- ✅ 文件和字符串操作
- ✅ 高精度浮点数支持
- ✅ 高精度日期时间支持
- ✅ 点分隔路径访问
- ✅ 与 JSON 格式的相互转换

---

## 🎯 核心功能

### 1. 类型安全的读取方法

所有的 get 类读取方法都提供默认值支持，确保程序不会因为键不存在而崩溃。


#### GetStr - 字符串读取

```pascal
function GetStr(const Key: string; const DefaultValue: string = ''): string;
```

**功能：** 获取字符串值，支持点分隔路径

**示例：**
```pascal
// 基本使用
title := Config.GetStr('title', 'Untitled');

// 嵌套路径
owner := Config.GetStr('database.owner', 'admin');

// 引号键（包含点的键名）
site := Config.GetStr('"google.com"', 'unknown');
```

#### GetInt - 整数读取

```pascal
function GetInt(const Key: string; const DefaultValue: Int64 = 0): Int64;
```

**示例：**
```pascal
port := Config.GetInt('server.port', 8080);
timeout := Config.GetInt('timeout', 30);
```

#### GetFloat - 浮点数读取

```pascal
function GetFloat(const Key: string; const DefaultValue: Double = 0.0): Double;
```

**示例：**
```pascal
pi := Config.GetFloat('math.pi', 3.14159);
rate := Config.GetFloat('conversion.rate', 1.0);
```
#### GetFloatValue - 高精度浮点数读取
保留 TOML 文件中的精确表示，如 "3.14"、"6.626e-34"、"inf"
```pascal
function GetFloatValue(const Key: string; const DefaultValue: String = ''): String;
```

#### GetBool - 布尔值读取

```pascal
function GetBool(const Key: string; const DefaultValue: Boolean = False): Boolean;
```

**示例：**
```pascal
debug := Config.GetBool('debug', False);
enabled := Config.GetBool('features.logging', True);
```

#### GetDateTime - 日期时间读取

```pascal
function GetDateTime(const Key: string; const DefaultValue: TDateTime = 0): TDateTime;
```

**示例：**
```pascal
lastModified := Config.GetDateTime('metadata.modified', Now);
```

#### GetDateTimeValue - 高精度日期时间

```pascal
function GetDateTimeValue(const Key: string; const DefaultValue: String = ''): String;
```

**功能：** 返回原始日期时间字符串，保留微秒/纳秒精度

**示例：**
```pascal
// 读取高精度时间戳
timestamp := Config.GetDateTimeValue('created_at', '');
// 返回: "1979-05-27T00:32:00.999999Z" （保留微秒）
```

**应用场景：**
- 需要精确到微秒/纳秒的时间戳
- 需要保留原始 ISO 8601 格式
- 日志记录和时间同步

---

### 2. TryGet 安全访问方法

所有 TryGet 方法提供异常安全的访问方式，通过返回值指示成功或失败。

#### TryGetStr - 安全字符串读取

```pascal
function TryGetStr(const Key: string; out Value: string): Boolean;
```

**示例：**
```pascal
var
  name: string;
begin
  if Config.TryGetStr('user.name', name) then
    WriteLn('User: ', name)
  else
    WriteLn('User name not found');
end;
```

#### TryGetInt - 安全整数读取

```pascal
function TryGetInt(const Key: string; out Value: Integer): Boolean;
```

**示例：**
```pascal
var
  port: Integer;
begin
  if Config.TryGetInt('server.port', port) then
    Server.Port := port
  else
    Server.Port := 8080; // 默认端口
end;
```

#### 完整的 TryGet 方法列表

- `TryGetStr` - 字符串
- `TryGetInt` - 整数
- `TryGetFloat` - 浮点数
- `TryGetFloatValue` - 高精度浮点数
- `TryGetBool` - 布尔值
- `TryGetDateTime` - 日期时间
- `TryGetDateTimeValue` - 高精度日期时间
- `TryGetArray` - 数组
- `TryGetTable` - 表

**优势：**
- ✅ 不使用异常处理机制（性能更好）
- ✅ 明确的成功/失败指示
- ✅ 适合需要区分"不存在"和"空值"的场景

---

### 3. 覆盖保护的写入方法

所有 Set 方法都支持覆盖控制，可以防止意外覆盖已存在的配置项。

#### SetStr - 字符串写入

```pascal
function SetStr(const Key: string; const Value: string; 
                Overwrite: Boolean = True): Boolean;
```

**参数：**
- `Key` - 键名（不支持路径）
- `Value` - 字符串值
- `Overwrite` - 是否覆盖已存在的值（默认 True）

**返回值：**
- `True` - 值已设置
- `False` - 键已存在且 Overwrite=False

**示例：**
```pascal
// 设置或覆盖
if Config.SetStr('title', 'MyApp', True) then
  WriteLn('Title set');

// 保护模式：仅当键不存在时设置
if Config.SetStr('title', 'Default', False) then
  WriteLn('Set new title')
else
  WriteLn('Title already exists, not overwritten');
```

#### 完整的 Set 方法列表

- `SetStr(Key, Value, Overwrite)` - 字符串
- `SetInt(Key, Value, Overwrite)` - 整数
- `SetFloat(Key, Value, Overwrite)` - 浮点数
- `SetFloatValue(key, Value, Overwrite)` - 高精度浮点数
- `SetBool(Key, Value, Overwrite)` - 布尔值
- `SetDateTime(Key, Value, Overwrite)` - 日期时间
- `SetDateTimeValue(key, value, Overwrite)` - 高精度日期时间
- `SetArray(Key, Value, Overwrite)` - 数组
- `SetTable(Key, Value, Overwrite)` - 表

**应用场景：**
```pascal
// 场景1：设置默认配置
Config.SetInt('port', 8080, False);        // 仅当不存在时设置
Config.SetStr('host', '0.0.0.0', False);   // 不覆盖用户配置

// 场景2：批量更新并检测失败
var Success := True;
Success := Success and Config.SetStr('name', Name, True);
Success := Success and Config.SetInt('age', Age, True);
if not Success then
  ShowMessage('配置更新失败');
```

---

### 4. 流畅的构建器模式

Put 方法支持链式调用，提供简洁优雅的配置构建方式。

#### Put - 链式设置

```pascal
function Put(const Key: string; const Value: <Type>; 
             Overwrite: Boolean = True): TTOMLTable;
```

**支持的类型：**
- `string` - 字符串
- `Int64`, `Integer` - 整数
- `Double` - 浮点数
- `Boolean` - 布尔值
- `TDateTime` - 日期时间
- `TTOMLArray` - 数组
- `TTOMLTable` - 表

**示例：**
```pascal
// 流畅的链式调用
Config := TTOMLTable.Create;
Config.Put('app_name', 'MyApp')
      .Put('version', '1.0.0')
      .Put('port', 8080)
      .Put('debug', False)
      .Put('max_connections', 100);

// 带覆盖控制的链式调用
Config.Put('width', 1920, True)      // 覆盖
      .Put('height', 1080, False)    // 不覆盖
      .Put('title', 'App', True);

// 构建嵌套结构
var Server := TTOMLTable.Create;
Server.Put('host', 'localhost')
      .Put('port', 3000);

Config.Put('server', Server)
      .Put('timeout', 30);
```

**优势：**
- ✅ 代码简洁易读
- ✅ 减少临时变量
- ✅ 类似现代配置库的 API 风格
- ✅ 支持覆盖控制

---

### 5. 文件和字符串操作

#### LoadFromFile - 从文件加载

```pascal
function LoadFromFile(const FileName: string; 
                      ClearExisting: Boolean = True): Boolean;
```

**参数：**
- `FileName` - 文件路径
- `ClearExisting` - 是否清空现有内容（默认 True）

**返回值：**
- `True` - 加载成功
- `False` - 加载失败

**示例：**
```pascal
Config := TTOMLTable.Create;
try
  if Config.LoadFromFile('config.toml') then
    WriteLn('配置加载成功')
  else
    WriteLn('配置加载失败');
finally
  Config.Free;
end;
```

#### SaveToFile - 保存到文件

```pascal
function SaveToFile(const FileName: string; 
                    WriteBOM: Boolean = True): Boolean;
```

**参数：**
- `FileName` - 文件路径
- `WriteBOM` - 是否写入 UTF-8 BOM（默认 True）

**示例：**
```pascal
if Config.SaveToFile('config.toml', True) then
  WriteLn('保存成功')
else
  WriteLn('保存失败');
```

#### LoadFromString - 从字符串解析（新增）

```pascal
function LoadFromString(const ATOML: string; 
                        ClearExisting: Boolean = True): Boolean;
```

**示例：**
```pascal
var TOML := 'title = "MyApp"' + sLineBreak +
            'version = "1.0"';

if Config.LoadFromString(TOML) then
  WriteLn('解析成功');
```

#### ToString - 序列化为字符串
```pascal
function ToString: string; 
```

**示例：**
```pascal
var TOML := Config.ToString;
WriteLn(TOML);
// 输出:
// title = "MyApp"
// version = "1.0"
```
---
### 6. TOML 与 JSON 格式转换
#### ToJSON - 转换为 JSON 字符串
```pascal
ToJSON(APretty: Boolean; AIndentSize: Integer): string;
```
**参数：**
- `APretty` - 输出带缩进的美观格式（默认 True）
- `AIndentSize` - 每级缩进的空格数（默认 2）

#### SaveToJSONFile - 保存为 JSON 格式文件
```pascal
SaveToJSONFile(const FileName: string; APretty: Boolean; ABOM: Boolean): Boolean;
```
**参数：**
- `FileName` - 文件路径
- `APretty` - 输出带缩进的美观格式（默认 True）
- `ABOM` - 是否写入 UTF-8 BOM（默认 False，JSON 通常无 BOM）

#### LoadFromJSON - 从 JSON 字符串读取
```pascal
LoadFromJSON(const AJSON: string; ANullAsEmptyString: Boolean): Boolean;
```
**参数：**
- `AJSON` - JSON 格式字符串
- `ANullAsEmptyString` - True 时将 JSON null 转为空字符串，False 时忽略 null 键（默认 False）

#### LoadFromJSONFile 从 JSON 格式文件读取
```pascal
LoadFromJSONFile(const FileName: string; ANullAsEmptyString: Boolean): Boolean;
```
- `Filename` - 文件路径
- `ANullAsEmptyString` - True 时将 JSON null 转为空字符串，False 时忽略 null 键（默认 False）

#### TOML.JSON 单元中还有 TOMLFileToJSONFile、JSONFileToTOMLFile 等函数。
---

### 7. 内存管理增强

#### Remove - 删除键

```pascal
function Remove(const Key: string; FreeValue: Boolean = True): Boolean;
```

**参数：**
- `Key` - 要删除的键
- `FreeValue` - 是否释放值对象（默认 True）

**示例：**
```pascal
// 删除并自动释放
if Config.Remove('old_setting', True) then
  WriteLn('已删除');

// 删除但保留对象（由调用者管理）
var Value := Config.Items['temp'];
Config.Remove('temp', False);
// 稍后手动释放 Value
```

#### Clear - 清空表

```pascal
procedure Clear(FreeValues: Boolean = True);
```

**参数：**
- `FreeValues` - 是否释放所有值对象（默认 True）

**示例：**
```pascal
// 清空并释放所有内容
Config.Clear(True);

// 清空但保留对象
Config.Clear(False);
```
---

### 7. 数组操作辅助方法或函数

#### AddXXX - 链式添加元素

所有 Add 方法都返回 Self，支持链式调用：

```pascal
Arr := TTOMLArray.Create;
Arr.AddStr('apple')
   .AddStr('banana')
   .AddStr('cherry');

Config.SetArray('fruits', Arr);
```

**可用函数：**
- `AddStr(Value)` - 添加字符串
- `AddInt(Value)` - 添加整数
- `AddFloat(Value)` - 添加浮点数
- `AddFloatValue(value)` - 添加高精度浮点数
- `AddBool(Value)` - 添加布尔值
- `AddDateTime(Value)` - 添加日期时间
- `AddDateTimeValue(value)` - 添加高精度日期时间
- `AddTable(Value)` - 添加表
- `AddArray(Value)` - 添加数组

#### GetXXX - 类型安全访问

```pascal
// 获取数组元素
fruit := Arr.GetStr(0, 'unknown');
count := Arr.GetInt(1, 0);
enabled := Arr.GetBool(2, False);
```
**可用函数：**
- `GetStr(Index,DefaultValue)` - 获取字符串
- `GetInt(Index,DefaultValue)` - 获取整数
- `GetFloat(Index,DefaultValue)` - 获取浮点数
- `GetFloatValue(Index,DefaultValue)` - 获取高精度浮点数
- `GetBool(Index,DefaultValue)` - 获取布尔值
- `GetDateTime(Index,DefaultValue)` - 获取日期时间
- `GetDateTimeValue(Index,DefaultValue)` - 获取高精度日期时间
- `GetTable(Index,DefaultValue)` - 获取表
- `GetArray(Index,DefaultValue)` - 获取数组
  
#### TryGetXXX - 类型安全访问
```pascal
if Arr.TryGetStr(1,str) then
showmessage(str);
```
**可用函数：**

- `TryGetStr(Index,Value)` - 获取字符串
- `TryGetInt(Index,Value)` - 获取整数
- `TryGetFloat(Index,Value)` - 获取浮点数
- `TryGetFloatValue(Index,Value)` - 获取高精度浮点数
- `TryGetBool(Index,Value)` - 获取布尔值
- `TryGetDateTime(Index,Value)` - 获取日期时间
- `TryGetDateTimeValue(Index,Value)` - 获取高精度日期时间
- `TryGetTable(Index,Value)` - 获取表
- `TryGetArray(Index,Value)` - 获取数组

#### SetXXX - 修改数组成员
```pascal
  str := 'tomato';
  if Arr.SetStr(1,str) then
  showmessage(Arr.GetStr(1));
```

**可用函数：**
- `SetStr(Index,Value)` - 修改字符串
- `SetInt(Index,Value)` - 修改整数
- `SetFloat(Index,Value)` - 修改浮点数
- `SetFloatValue(Index,Value)` - 修改高精度浮点数
- `SetBool(Index,Value)` - 修改布尔值
- `SetDateTime(Index,Value)` - 修改日期时间
- `SetDateTimeValue(Index,Value)` - 修改高精度日期时间
- `SetTable(Index,Value)` - 修改表
- `SetArray(Index,Value)` - 修改数组

#### InsertXXX - 插入数组成员
```pascal
  str := 'tomato';
  if InsertStr.SetStr(1,str) then
  showmessage(Arr.GetStr(1));
```

**可用函数：**
- `InsertStr(Index,Value)` - 插入字符串
- `InsertInt(Index,Value)` - 插入整数
- `InsertFloat(Index,Value)` - 插入浮点数
- `InsertFloatValue(Index,Value)` - 插入高精度浮点数
- `InsertBool(Index,Value)` - 插入布尔值
- `InsertDateTime(Index,Value)` - 插入日期时间
- `InsertDateTimeValue(Index,Value)` - 插入高精度日期时间
- `InsertTable(Index,Value)` - 插入表
- `InsertArray(Index,Value)` - 插入数组
- 
#### RemoveAt - 删除数组成员

```pascal
function RemoveAt(Index: Integer; FreeItem: Boolean = True): Boolean;
```

**示例：**
```pascal
// 删除数组中的第3个元素
Arr := Config.GetArray('items');
if Arr.RemoveAt(2, True) then
  WriteLn('元素已删除');
```

### 8. 其它
#### ToString - 序列化为字符串
```pascal
function ToString: string; 
```
#### clone - 克隆表
```pascal
table2 :=table1.clone;
```
#### ForEachTable - 循环表数组
```pascal
ForEachTable(Proc: TProc<TTOMLTable>);
ForEachTable(Callback: TFunc<Integer, TTOMLTable, Boolean>; SkipNonTables: Boolean = True);
```
示例：
- 遍历数组方式一
```
parameters.ForEachTable(
  procedure(param: TTOMLTable)
    begin
      showmessage(param.GetStr('name'));
    end
 );
```
- 遍历数组方式二
```pascal
    procedure ProcessParameter(param: TTOMLTable);
      begin
        showmessage(param.GetStr('name'));
      end;    
    parameters.ForEachTable(ProcessParameter);
```
- 增强版 ForEachTable
```pascal
var
  Root: TTOMLTable;
  UsersArray: TTOMLArray;
  TargetUser: TTOMLTable;
begin
  Root := LoadTOML('users.toml');
  UsersArray := Root.GetArray('users');
  TargetUser := nil;
  
  // 使用改进版本：支持提前退出
  UsersArray.ForEachTable(
    function(Index: Integer; User: TTOMLTable): Boolean
    begin
      if User.GetStr('username') = 'bob' then
      begin
        TargetUser := User;
        Result := False;  // 找到了，停止遍历
      end
      else
        Result := True;  // 继续查找
    end,
    True  // 跳过非表元素
  );
  
  if Assigned(TargetUser) then
    WriteLn('Found user: ' + TargetUser.GetStr('email'))
  else
    WriteLn('User not found');
    
  Root.Free;
end;
```    
## 📚 完整使用示例

### 示例 1: 应用配置管理

```pascal
uses
  TOML.Types, TOML.Helper;

var
  Config: TTOMLTable;
begin
  // 创建配置
  Config := TTOMLTable.Create;
  try
    // 使用构建器模式设置配置
    Config.Put('app_name', 'MyApplication')
          .Put('version', '2.1.0')
          .Put('debug', False);
    
    // 设置服务器配置
    var Server := TTOMLTable.Create;
    Server.Put('host', '0.0.0.0')
          .Put('port', 8080)
          .Put('ssl', True);
    
    Config.Put('server', Server);
    
    // 设置数组
    var AllowedIPs := TTOMLArray.Create;
    AllowedIPs.AddStr('192.168.1.1')
              .AddStr('10.0.0.1');
    
    Config.Put('allowed_ips', AllowedIPs);
    
    // 保存到文件
    if Config.SaveToFile('app_config.toml') then
      WriteLn('配置已保存');
    
    // 读取配置
    var AppName := Config.GetStr('app_name', 'Unknown');
    var Port := Config.GetInt('server.port', 3000);
    var Debug := Config.GetBool('debug', False);
    
    WriteLn('应用: ', AppName);
    WriteLn('端口: ', Port);
    WriteLn('调试: ', Debug);
    
  finally
    Config.Free;
  end;
end;
```

### 示例 2: 安全的配置读取

```pascal
var
  Config: TTOMLTable;
  Host: string;
  Port: Integer;
  Timeout: Double;
begin
  Config := TTOMLTable.Create;
  try
    Config.LoadFromFile('config.toml');
    
    // 使用 TryGet 进行安全访问
    if not Config.TryGetStr('server.host', Host) then
      Host := 'localhost'; // 默认值
    
    if not Config.TryGetInt('server.port', Port) then
      Port := 8080;
    
    if not Config.TryGetFloat('server.timeout', Timeout) then
      Timeout := 30.0;
    
    WriteLn('服务器配置:');
    WriteLn('  主机: ', Host);
    WriteLn('  端口: ', Port);
    WriteLn('  超时: ', Timeout:0:1, '秒');
    
  finally
    Config.Free;
  end;
end;
```

### 示例 3: 覆盖保护

```pascal
var
  Config: TTOMLTable;
begin
  Config := TTOMLTable.Create;
  try
    // 设置默认配置
    Config.SetStr('theme', 'dark', False);
    Config.SetInt('font_size', 12, False);
    
    // 尝试从文件加载用户配置
    if FileExists('user_config.toml') then
    begin
      var UserConfig := TTOMLTable.Create;
      try
        if UserConfig.LoadFromFile('user_config.toml') then
        begin
          // 合并配置（使用覆盖保护）
          var Keys: TStringList := TStringList.Create;
          try
            UserConfig.GetKeys(Keys);
            for var Key in Keys do
            begin
              var Value: TTOMLValue;
              if UserConfig.TryGetValue(Key, Value) then
                Config.SetStr(Key, Value.AsString, True); // 用户配置覆盖默认
            end;
          finally
            Keys.Free;
          end;
        end;
      finally
        UserConfig.Free;
      end;
    end;
    
    // 现在 Config 包含合并后的配置
    WriteLn('主题: ', Config.GetStr('theme'));
    WriteLn('字体大小: ', Config.GetInt('font_size'));
    
  finally
    Config.Free;
  end;
end;
```

### 示例 4: 高精度时间戳

```pascal
uses
  TOML.Types, TOML.Helper;

var
  Config: TTOMLTable;
  Timestamp: string;
begin
  Config := TTOMLTable.Create;
  try
    // 解析包含高精度时间戳的 TOML
    var TOML := 'created = 2024-01-15T10:30:45.123456Z' + sLineBreak +
                'modified = 2024-01-16T14:22:33.999999Z';
    
    Config.LoadFromString(TOML);
    
    // 获取高精度时间戳（保留微秒）
    Timestamp := Config.GetDateTimeValue('created', '');
    WriteLn('创建时间: ', Timestamp);
    // 输出: 2024-01-15T10:30:45.123456Z
    
    Timestamp := Config.GetDateTimeValue('modified', '');
    WriteLn('修改时间: ', Timestamp);
    // 输出: 2024-01-16T14:22:33.999999Z
    
  finally
    Config.Free;
  end;
end;
```

### 示例 5: 引号键处理

```pascal
var
  Config: TTOMLTable;
begin
  Config := TTOMLTable.Create;
  try
    // 直接添加包含点的键
    Config.Items.Add('google.com', TTOMLString.Create('搜索引擎'));
    Config.Items.Add('github.com', TTOMLString.Create('代码托管'));
    
    // 使用引号访问
    var Google := Config.GetStr('"google.com"', '未知');
    var GitHub := Config.GetStr('"github.com"', '未知');
    
    WriteLn('google.com: ', Google);
    WriteLn('github.com: ', GitHub);
    
    // 序列化时会自动加引号
    var TOML := Config.ToString;
    WriteLn(TOML);
    // 输出:
    // "google.com" = "搜索引擎"
    // "github.com" = "代码托管"
    
  finally
    Config.Free;
  end;
end;
```

---

## 🎯 最佳实践

### 1. 始终使用 Try-Finally

```pascal
Config := TTOMLTable.Create;
try
  // 使用 Config
finally
  Config.Free;
end;
```

### 2. 优先使用 TryGet 方法

当需要区分"不存在"和"空值"时：

```pascal
if Config.TryGetStr('optional_field', Value) then
  // 字段存在
else
  // 字段不存在
```

### 3. 使用覆盖保护避免意外修改

```pascal
// 设置默认值（不覆盖用户配置）
Config.SetStr('theme', 'default', False);
Config.SetInt('timeout', 30, False);
```

### 4. 利用构建器模式提高代码可读性

```pascal
Config.Put('name', 'App')
      .Put('version', '1.0')
      .Put('enabled', True);
```

### 5. 检查文件操作返回值

```pascal
if not Config.LoadFromFile('config.toml') then
begin
  // 加载失败，使用默认配置
  Config.Put('default', True);
end;
```

### 6. 使用高精度时间戳保留完整信息

```pascal
// 对于日志、审计等需要精确时间的场景
var Timestamp := Config.GetDateTimeValue('log.timestamp', '');
// 保留微秒精度
```

---

## 📋 API 快速参考

### 读取方法

| 方法 | 返回类型 | 默认值支持 | 路径支持 | 异常安全 |
|------|---------|-----------|---------|---------|
| `GetStr` | string | ✓ | ✓ | ✓ |
| `GetInt` | Int64 | ✓ | ✓ | ✓ |
| `GetFloat` | Double | ✓ | ✓ | ✓ |
| `GetBool` | Boolean | ✓ | ✓ | ✓ |
| `GetDateTime` | TDateTime | ✓ | ✓ | ✓ |
| `GetDateTimeValue` | string | ✓ | ✓ | ✓ |
| `GetArray` | TTOMLArray | - | ✓ | ✓ |
| `GetTable` | TTOMLTable | - | ✓ | ✓ |

### TryGet 方法

| 方法 | Out 参数类型 | 路径支持 | 返回 Boolean |
|------|------------|---------|-------------|
| `TryGetStr` | string | ✓ | ✓ |
| `TryGetInt` | Integer | ✓ | ✓ |
| `TryGetFloat` | Double | ✓ | ✓ |
| `TryGetBool` | Boolean | ✓ | ✓ |
| `TryGetDateTime` | TDateTime | ✓ | ✓ |
| `TryGetDateTimeValue` | string | ✓ | ✓ |
| `TryGetArray` | TTOMLArray | ✓ | ✓ |
| `TryGetTable` | TTOMLTable | ✓ | ✓ |

### 写入方法

| 方法 | 覆盖控制 | 返回 Boolean | 链式调用 |
|------|---------|-------------|---------|
| `SetStr` | ✓ | ✓ | - |
| `SetInt` | ✓ | ✓ | - |
| `SetFloat` | ✓ | ✓ | - |
| `SetBool` | ✓ | ✓ | - |
| `SetDateTime` | ✓ | ✓ | - |
| `SetArray` | ✓ | ✓ | - |
| `SetTable` | ✓ | ✓ | - |
| `Put` (所有类型) | ✓ | - | ✓ |

### 文件操作

| 方法 | 功能 | 返回 Boolean |
|------|------|-------------|
| `LoadFromFile` | 从文件加载 | ✓ |
| `LoadFromJSONFile` | 从 JSON 文件加载 | ✓ |
| `SaveToFile` | 保存为文件 | ✓ |
|`SaveToJSONFile`|保存为 JSON 文件|✓ |
| `LoadFromString` | 从字符串解析 | ✓ |
| `LoadFromJSONString` | 从 JSON 字符串解析 | ✓ |
| `ToString` | 序列化为 TOML 字符串 | - |
| `ToJSONString` | 序列化为 JSON 字符串 | - |
| `TOMLFileToJSONFile` | TOML 文件转换为 JSON 文件 | - |
| `JSONFileToTOMLFile` | JSON 文件转换为 TOML 文件 | - |
* 备注：TOMLFileToJSONFile 和 JSONFileToTOMLFile 方法在 TOML.JSON.pas 单元中
---

## ⚡ 性能提示

1. **TryGet vs Get + Try-Except**
   - TryGet 方法不使用异常机制，性能更好
   - 适合高频调用的场景

2. **构建器模式的开销**
   - Put 方法的链式调用没有额外开销
   - 推荐用于初始化场景

3. **路径访问的性能**
   - 点分隔路径需要多次查找
   - 频繁访问建议缓存 TTOMLTable 引用

---

## 🔧 故障排除

### Q: GetStr 返回空字符串，但我确定键存在

**A:** 检查是否使用了正确的路径或引号：
```pascal
// 错误：键包含点但未加引号
val := Config.GetStr('google.com');  // 尝试访问路径

// 正确：使用引号
val := Config.GetStr('"google.com"');  // 访问单个键
```

### Q: SetStr 返回 False，但应该成功

**A:** 检查 Overwrite 参数：
```pascal
// Overwrite=False 时，键已存在会返回 False
Config.SetStr('key', 'value1');
Config.SetStr('key', 'value2', False);  // 返回 False

// 使用 Overwrite=True 强制覆盖
Config.SetStr('key', 'value2', True);  // 返回 True
```

### Q: LoadFromFile 返回 False

**A:** 可能的原因：
- 文件不存在
- 文件权限问题
- TOML 语法错误

```pascal
if not Config.LoadFromFile('config.toml') then
  WriteLn('加载失败，使用默认配置');
```

---
