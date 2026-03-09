🇺🇸 [English](TOML_Helper_Documentation.md) | 🇨🇳 [简体中文](TOML_Helper_Documentation_CN.md)
# TOML.Helper.pas Feature Documentation

## 📋 Overview

`TOML.Helper.pas` is an auxiliary unit added to the TOML library, providing a concise and easy-to-use API that greatly simplifies reading and writing TOML configuration files. This unit extends the functionality of `TTOMLTable` and `TTOMLArray` classes through Class Helper technology without modifying the original class definitions.

**Key Features:**
- ✅ Type-safe read/write methods
- ✅ Default value support
- ✅ Exception-safe (won't crash)
- ✅ Fluent builder pattern
- ✅ Overwrite protection mechanism
- ✅ File and string operations
- ✅ High-precision datetime support
- ✅ Dot-separated path access

---

## 🎯 Core Features

### 1. Type-Safe Read Methods

All read methods provide default value support, ensuring the program won't crash due to missing keys.

#### GetStr - String Retrieval

```pascal
function GetStr(const Key: string; const DefaultValue: string = ''): string;
```

**Description:** Retrieves string value with support for dot-separated paths

**Examples:**
```pascal
// Basic usage
title := Config.GetStr('title', 'Untitled');

// Nested path
owner := Config.GetStr('database.owner', 'admin');

// Quoted keys (keys containing dots)
site := Config.GetStr('"google.com"', 'unknown');
```

#### GetInt - Integer Retrieval

```pascal
function GetInt(const Key: string; const DefaultValue: Int64 = 0): Int64;
```

**Examples:**
```pascal
port := Config.GetInt('server.port', 8080);
timeout := Config.GetInt('timeout', 30);
```

#### GetFloat - Float Retrieval

```pascal
function GetFloat(const Key: string; const DefaultValue: Double = 0.0): Double;
```

**Examples:**
```pascal
pi := Config.GetFloat('math.pi', 3.14159);
rate := Config.GetFloat('conversion.rate', 1.0);
```

#### GetBool - Boolean Retrieval

```pascal
function GetBool(const Key: string; const DefaultValue: Boolean = False): Boolean;
```

**Examples:**
```pascal
debug := Config.GetBool('debug', False);
enabled := Config.GetBool('features.logging', True);
```

#### GetDateTime - DateTime Retrieval

```pascal
function GetDateTime(const Key: string; const DefaultValue: TDateTime = 0): TDateTime;
```

**Examples:**
```pascal
lastModified := Config.GetDateTime('metadata.modified', Now);
```

#### GetDateTimeValue - High-Precision DateTime (New)

```pascal
function GetDateTimeValue(const Key: string; const DefaultValue: String = ''): String;
```

**Description:** Returns raw datetime string, preserving microsecond/nanosecond precision

**Examples:**
```pascal
// Read high-precision timestamp
timestamp := Config.GetDateTimeValue('created_at', '');
// Returns: "1979-05-27T00:32:00.999999Z" (preserves microseconds)
```

**Use Cases:**
- Timestamps requiring microsecond/nanosecond precision
- Preserving original ISO 8601 format
- Logging and time synchronization

---

### 2. TryGet Safe Access Methods (New)

All TryGet methods provide exception-safe access, indicating success or failure through return values.

#### TryGetStr - Safe String Retrieval

```pascal
function TryGetStr(const Key: string; out Value: string): Boolean;
```

**Examples:**
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

#### TryGetInt - Safe Integer Retrieval

```pascal
function TryGetInt(const Key: string; out Value: Integer): Boolean;
```

**Examples:**
```pascal
var
  port: Integer;
begin
  if Config.TryGetInt('server.port', port) then
    Server.Port := port
  else
    Server.Port := 8080; // Default port
end;
```

#### Complete TryGet Method List

- `TryGetStr` - String
- `TryGetInt` - Integer
- `TryGetFloat` - Float
- `TryGetBool` - Boolean
- `TryGetDateTime` - DateTime
- `TryGetDateTimeValue` - High-precision datetime
- `TryGetArray` - Array
- `TryGetTable` - Table

**Advantages:**
- ✅ Doesn't use exception mechanism (better performance)
- ✅ Explicit success/failure indication
- ✅ Suitable for scenarios requiring distinction between "not exists" and "empty value"

---

### 3. Overwrite-Protected Write Methods (New)

All Set methods support overwrite control, preventing accidental overwriting of existing configuration items.

#### SetStr - String Write

```pascal
function SetStr(const Key: string; const Value: string; 
                Overwrite: Boolean = True): Boolean;
```

**Parameters:**
- `Key` - Key name (paths not supported)
- `Value` - String value
- `Overwrite` - Whether to overwrite existing value (default True)

**Return Value:**
- `True` - Value was set
- `False` - Key exists and Overwrite=False

**Examples:**
```pascal
// Set or overwrite
if Config.SetStr('title', 'MyApp', True) then
  WriteLn('Title set');

// Protection mode: set only if key doesn't exist
if Config.SetStr('title', 'Default', False) then
  WriteLn('Set new title')
else
  WriteLn('Title already exists, not overwritten');
```

#### Complete Set Method List

- `SetStr(Key, Value, Overwrite)` - String
- `SetInt(Key, Value, Overwrite)` - Integer
- `SetFloat(Key, Value, Overwrite)` - Float
- `SetBool(Key, Value, Overwrite)` - Boolean
- `SetDateTime(Key, Value, Overwrite)` - DateTime
- `SetArray(Key, Value, Overwrite)` - Array
- `SetTable(Key, Value, Overwrite)` - Table

**Use Cases:**
```pascal
// Scenario 1: Set default configuration
Config.SetInt('port', 8080, False);        // Set only if doesn't exist
Config.SetStr('host', '0.0.0.0', False);   // Don't overwrite user config

// Scenario 2: Batch update with failure detection
var Success := True;
Success := Success and Config.SetStr('name', Name, True);
Success := Success and Config.SetInt('age', Age, True);
if not Success then
  ShowMessage('Configuration update failed');
```

---

### 4. Fluent Builder Pattern

Put methods support method chaining, providing concise and elegant configuration construction.

#### Put - Chained Setting

```pascal
function Put(const Key: string; const Value: <Type>; 
             Overwrite: Boolean = True): TTOMLTable;
```

**Supported Types:**
- `string` - String
- `Int64`, `Integer` - Integer
- `Double` - Float
- `Boolean` - Boolean
- `TDateTime` - DateTime
- `TTOMLArray` - Array
- `TTOMLTable` - Table

**Examples:**
```pascal
// Fluent method chaining
Config := TTOMLTable.Create;
Config.Put('app_name', 'MyApp')
      .Put('version', '1.0.0')
      .Put('port', 8080)
      .Put('debug', False)
      .Put('max_connections', 100);

// Chaining with overwrite control
Config.Put('width', 1920, True)      // Overwrite
      .Put('height', 1080, False)    // Don't overwrite
      .Put('title', 'App', True);

// Build nested structure
var Server := TTOMLTable.Create;
Server.Put('host', 'localhost')
      .Put('port', 3000);

Config.Put('server', Server)
      .Put('timeout', 30);
```

**Advantages:**
- ✅ Clean and readable code
- ✅ Reduces temporary variables
- ✅ Modern configuration library API style
- ✅ Supports overwrite control

---

### 5. File and String Operations

#### LoadFromFile - Load from File

```pascal
function LoadFromFile(const FileName: string; 
                      ClearExisting: Boolean = True): Boolean;
```

**Parameters:**
- `FileName` - File path
- `ClearExisting` - Whether to clear existing content (default True)

**Return Value:**
- `True` - Load successful
- `False` - Load failed

**Examples:**
```pascal
Config := TTOMLTable.Create;
try
  if Config.LoadFromFile('config.toml') then
    WriteLn('Configuration loaded successfully')
  else
    WriteLn('Configuration load failed');
finally
  Config.Free;
end;
```

#### SaveToFile - Save to File

```pascal
function SaveToFile(const FileName: string; 
                    WriteBOM: Boolean = True): Boolean;
```

**Parameters:**
- `FileName` - File path
- `WriteBOM` - Whether to write UTF-8 BOM (default True)

**Examples:**
```pascal
if Config.SaveToFile('config.toml', True) then
  WriteLn('Save successful')
else
  WriteLn('Save failed');
```

#### LoadFromString - Parse from String (New)

```pascal
function LoadFromString(const ATOML: string; 
                        ClearExisting: Boolean = True): Boolean;
```

**Examples:**
```pascal
var TOML := 'title = "MyApp"' + sLineBreak +
            'version = "1.0"';

if Config.LoadFromString(TOML) then
  WriteLn('Parse successful');
```

#### ToString - Serialize to String

```pascal
function ToString: string; reintroduce;
```

**Examples:**
```pascal
var TOML := Config.ToString;
WriteLn(TOML);
// Output:
// title = "MyApp"
// version = "1.0"
```

---

### 6. Enhanced Memory Management

#### Remove - Delete Key

```pascal
function Remove(const Key: string; FreeValue: Boolean = True): Boolean;
```

**Parameters:**
- `Key` - Key to delete
- `FreeValue` - Whether to free value object (default True)

**Examples:**
```pascal
// Delete and auto-free
if Config.Remove('old_setting', True) then
  WriteLn('Deleted');

// Delete but keep object (managed by caller)
var Value := Config.Items['temp'];
Config.Remove('temp', False);
// Manually free Value later
```

#### Clear - Clear Table

```pascal
procedure Clear(FreeValues: Boolean = True);
```

**Parameters:**
- `FreeValues` - Whether to free all value objects (default True)

**Examples:**
```pascal
// Clear and free all content
Config.Clear(True);

// Clear but keep objects
Config.Clear(False);
```

#### RemoveAt - Delete Array Element

```pascal
function RemoveAt(Index: Integer; FreeItem: Boolean = True): Boolean;
```

**Examples:**
```pascal
// Delete 3rd element in array
Arr := Config.GetArray('items');
if Arr.RemoveAt(2, True) then
  WriteLn('Element deleted');
```

---

### 7. Array Operation Helper Methods

#### AddXXX - Chained Element Addition

All Add methods return Self, supporting method chaining:

```pascal
Arr := TTOMLArray.Create;
Arr.AddStr('apple')
   .AddStr('banana')
   .AddStr('cherry');

Config.SetArray('fruits', Arr);
```

**Available Methods:**
- `AddStr(Value)` - Add string
- `AddInt(Value)` - Add integer
- `AddFloat(Value)` - Add float
- `AddBool(Value)` - Add boolean
- `AddDateTime(Value)` - Add datetime
- `AddTable(Value)` - Add table
- `AddArray(Value)` - Add array

#### GetXXX - Type-Safe Access

```pascal
// Get array elements
fruit := Arr.GetStr(0, 'unknown');
count := Arr.GetInt(1, 0);
enabled := Arr.GetBool(2, False);
```
### 8. 其它
#### clone - 克隆表

table2 :=table1.clone;
---

## 📚 Complete Usage Examples

### Example 1: Application Configuration Management

```pascal
uses
  TOML.Types, TOML.Helper;

var
  Config: TTOMLTable;
begin
  // Create configuration
  Config := TTOMLTable.Create;
  try
    // Use builder pattern to set configuration
    Config.Put('app_name', 'MyApplication')
          .Put('version', '2.1.0')
          .Put('debug', False);
    
    // Set server configuration
    var Server := TTOMLTable.Create;
    Server.Put('host', '0.0.0.0')
          .Put('port', 8080)
          .Put('ssl', True);
    
    Config.Put('server', Server);
    
    // Set array
    var AllowedIPs := TTOMLArray.Create;
    AllowedIPs.AddStr('192.168.1.1')
              .AddStr('10.0.0.1');
    
    Config.Put('allowed_ips', AllowedIPs);
    
    // Save to file
    if Config.SaveToFile('app_config.toml') then
      WriteLn('Configuration saved');
    
    // Read configuration
    var AppName := Config.GetStr('app_name', 'Unknown');
    var Port := Config.GetInt('server.port', 3000);
    var Debug := Config.GetBool('debug', False);
    
    WriteLn('Application: ', AppName);
    WriteLn('Port: ', Port);
    WriteLn('Debug: ', Debug);
    
  finally
    Config.Free;
  end;
end;
```

### Example 2: Safe Configuration Reading

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
    
    // Use TryGet for safe access
    if not Config.TryGetStr('server.host', Host) then
      Host := 'localhost'; // Default value
    
    if not Config.TryGetInt('server.port', Port) then
      Port := 8080;
    
    if not Config.TryGetFloat('server.timeout', Timeout) then
      Timeout := 30.0;
    
    WriteLn('Server Configuration:');
    WriteLn('  Host: ', Host);
    WriteLn('  Port: ', Port);
    WriteLn('  Timeout: ', Timeout:0:1, ' seconds');
    
  finally
    Config.Free;
  end;
end;
```

### Example 3: Overwrite Protection

```pascal
var
  Config: TTOMLTable;
begin
  Config := TTOMLTable.Create;
  try
    // Set default configuration
    Config.SetStr('theme', 'dark', False);
    Config.SetInt('font_size', 12, False);
    
    // Try to load user configuration from file
    if FileExists('user_config.toml') then
    begin
      var UserConfig := TTOMLTable.Create;
      try
        if UserConfig.LoadFromFile('user_config.toml') then
        begin
          // Merge configuration (using overwrite protection)
          var Keys: TStringList := TStringList.Create;
          try
            UserConfig.GetKeys(Keys);
            for var Key in Keys do
            begin
              var Value: TTOMLValue;
              if UserConfig.TryGetValue(Key, Value) then
                Config.SetStr(Key, Value.AsString, True); // User config overrides default
            end;
          finally
            Keys.Free;
          end;
        end;
      finally
        UserConfig.Free;
      end;
    end;
    
    // Now Config contains merged configuration
    WriteLn('Theme: ', Config.GetStr('theme'));
    WriteLn('Font Size: ', Config.GetInt('font_size'));
    
  finally
    Config.Free;
  end;
end;
```

### Example 4: High-Precision Timestamps

```pascal
uses
  TOML.Types, TOML.Helper;

var
  Config: TTOMLTable;
  Timestamp: string;
begin
  Config := TTOMLTable.Create;
  try
    // Parse TOML with high-precision timestamps
    var TOML := 'created = 2024-01-15T10:30:45.123456Z' + sLineBreak +
                'modified = 2024-01-16T14:22:33.999999Z';
    
    Config.LoadFromString(TOML);
    
    // Get high-precision timestamp (preserves microseconds)
    Timestamp := Config.GetDateTimeValue('created', '');
    WriteLn('Created: ', Timestamp);
    // Output: 2024-01-15T10:30:45.123456Z
    
    Timestamp := Config.GetDateTimeValue('modified', '');
    WriteLn('Modified: ', Timestamp);
    // Output: 2024-01-16T14:22:33.999999Z
    
  finally
    Config.Free;
  end;
end;
```

### Example 5: Quoted Key Handling

```pascal
var
  Config: TTOMLTable;
begin
  Config := TTOMLTable.Create;
  try
    // Directly add keys containing dots
    Config.Items.Add('google.com', TTOMLString.Create('Search Engine'));
    Config.Items.Add('github.com', TTOMLString.Create('Code Hosting'));
    
    // Access with quotes
    var Google := Config.GetStr('"google.com"', 'Unknown');
    var GitHub := Config.GetStr('"github.com"', 'Unknown');
    
    WriteLn('google.com: ', Google);
    WriteLn('github.com: ', GitHub);
    
    // Automatically adds quotes when serializing
    var TOML := Config.ToString;
    WriteLn(TOML);
    // Output:
    // "google.com" = "Search Engine"
    // "github.com" = "Code Hosting"
    
  finally
    Config.Free;
  end;
end;
```

---

## 🎯 Best Practices

### 1. Always Use Try-Finally

```pascal
Config := TTOMLTable.Create;
try
  // Use Config
finally
  Config.Free;
end;
```

### 2. Prefer TryGet Methods

When you need to distinguish between "not exists" and "empty value":

```pascal
if Config.TryGetStr('optional_field', Value) then
  // Field exists
else
  // Field doesn't exist
```

### 3. Use Overwrite Protection to Avoid Accidental Modifications

```pascal
// Set default values (don't overwrite user configuration)
Config.SetStr('theme', 'default', False);
Config.SetInt('timeout', 30, False);
```

### 4. Leverage Builder Pattern for Code Readability

```pascal
Config.Put('name', 'App')
      .Put('version', '1.0')
      .Put('enabled', True);
```

### 5. Check File Operation Return Values

```pascal
if not Config.LoadFromFile('config.toml') then
begin
  // Load failed, use default configuration
  Config.Put('default', True);
end;
```

### 6. Use High-Precision Timestamps to Preserve Complete Information

```pascal
// For scenarios requiring precise time like logging, auditing
var Timestamp := Config.GetDateTimeValue('log.timestamp', '');
// Preserves microsecond precision
```

---

## 📋 API Quick Reference

### Read Methods

| Method | Return Type | Default Support | Path Support | Exception-Safe |
|--------|------------|----------------|--------------|----------------|
| `GetStr` | string | ✓ | ✓ | ✓ |
| `GetInt` | Int64 | ✓ | ✓ | ✓ |
| `GetFloat` | Double | ✓ | ✓ | ✓ |
| `GetBool` | Boolean | ✓ | ✓ | ✓ |
| `GetDateTime` | TDateTime | ✓ | ✓ | ✓ |
| `GetDateTimeValue` | string | ✓ | ✓ | ✓ |
| `GetArray` | TTOMLArray | - | ✓ | ✓ |
| `GetTable` | TTOMLTable | - | ✓ | ✓ |

### TryGet Methods

| Method | Out Parameter Type | Path Support | Returns Boolean |
|--------|-------------------|--------------|----------------|
| `TryGetStr` | string | ✓ | ✓ |
| `TryGetInt` | Integer | ✓ | ✓ |
| `TryGetFloat` | Double | ✓ | ✓ |
| `TryGetBool` | Boolean | ✓ | ✓ |
| `TryGetDateTime` | TDateTime | ✓ | ✓ |
| `TryGetDateTimeValue` | string | ✓ | ✓ |
| `TryGetArray` | TTOMLArray | ✓ | ✓ |
| `TryGetTable` | TTOMLTable | ✓ | ✓ |

### Write Methods

| Method | Overwrite Control | Returns Boolean | Method Chaining |
|--------|------------------|----------------|-----------------|
| `SetStr` | ✓ | ✓ | - |
| `SetInt` | ✓ | ✓ | - |
| `SetFloat` | ✓ | ✓ | - |
| `SetBool` | ✓ | ✓ | - |
| `SetDateTime` | ✓ | ✓ | - |
| `SetArray` | ✓ | ✓ | - |
| `SetTable` | ✓ | ✓ | - |
| `Put` (all types) | ✓ | - | ✓ |

### File Operations

| Method | Function | Returns Boolean |
|--------|----------|----------------|
| `LoadFromFile` | Load from file | ✓ |
| `SaveToFile` | Save to file | ✓ |
| `LoadFromString` | Parse from string | ✓ |
| `ToString` | Serialize to string | - |

---

## ⚡ Performance Tips

1. **TryGet vs Get + Try-Except**
   - TryGet methods don't use exception mechanism, better performance
   - Suitable for high-frequency call scenarios

2. **Builder Pattern Overhead**
   - Put method chaining has no extra overhead
   - Recommended for initialization scenarios

3. **Path Access Performance**
   - Dot-separated paths require multiple lookups
   - Cache TTOMLTable references for frequent access

---

## 🔧 Troubleshooting

### Q: GetStr returns empty string, but I'm sure the key exists

**A:** Check if you're using the correct path or quotes:
```pascal
// Wrong: key contains dot but no quotes
val := Config.GetStr('google.com');  // Tries to access path

// Correct: use quotes
val := Config.GetStr('"google.com"');  // Access single key
```

### Q: SetStr returns False, but should succeed

**A:** Check Overwrite parameter:
```pascal
// When Overwrite=False, returns False if key exists
Config.SetStr('key', 'value1');
Config.SetStr('key', 'value2', False);  // Returns False

// Use Overwrite=True to force overwrite
Config.SetStr('key', 'value2', True);  // Returns True
```

### Q: LoadFromFile returns False

**A:** Possible causes:
- File doesn't exist
- File permission issues
- TOML syntax error

```pascal
if not Config.LoadFromFile('config.toml') then
  WriteLn('Load failed, using default configuration');
```

---


