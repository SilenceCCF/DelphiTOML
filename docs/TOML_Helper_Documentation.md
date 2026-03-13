🇺🇸 [English](TOML_Helper_Documentation.md) | 🇨🇳 [简体中文](TOML_Helper_Documentation_CN.md)

# TOML.Helper.pas Documentation

## 📋 Overview

`TOML.Helper.pas` is an auxiliary unit that provides a simplified and user-friendly API for working with TOML configuration files. This unit extends the functionality of `TTOMLTable` and `TTOMLArray` classes through Class Helper technology, without modifying the original class definitions.

**Key Features:**
- ✅ Type-safe read/write methods
- ✅ Default value support
- ✅ Exception-safe (won't crash)
- ✅ Fluent builder pattern
- ✅ Overwrite protection mechanism
- ✅ File and string operations
- ✅ High-precision floating-point support
- ✅ High-precision date/time support
- ✅ Dot-separated path access
- ✅ Bidirectional conversion with JSON format

---

## 🎯 Core Features

### 1. Type-Safe Read Methods

All get-style read methods provide default value support, ensuring the program won't crash due to missing keys.

#### GetStr - String Reading

```pascal
GetStr(const Key: string; const DefaultValue: string = ''): string;
```

**Function:** Retrieve string value with dot-separated path support

**Examples:**
```pascal
// Basic usage
title := Config.GetStr('title', 'Untitled');

// Nested path
owner := Config.GetStr('database.owner', 'admin');

// Quoted key (for keys containing dots)
site := Config.GetStr('"google.com"', 'unknown');
```

#### GetInt - Integer Reading

```pascal
GetInt(const Key: string; const DefaultValue: Int64 = 0): Int64;
```

**Examples:**
```pascal
port := Config.GetInt('server.port', 8080);
timeout := Config.GetInt('timeout', 30);
```

#### GetFloat - Float Reading

```pascal
GetFloat(const Key: string; const DefaultValue: Double = 0.0): Double;
```

**Examples:**
```pascal
pi := Config.GetFloat('math.pi', 3.14159);
rate := Config.GetFloat('conversion.rate', 1.0);
```

#### GetFloatValue - High-Precision Float Reading
Preserves exact representation from TOML file, such as "3.14", "6.626e-34", "inf"
```pascal
GetFloatValue(const Key: string; const DefaultValue: String = ''): String;
```

#### GetBool - Boolean Reading

```pascal
GetBool(const Key: string; const DefaultValue: Boolean = False): Boolean;
```

**Examples:**
```pascal
debug := Config.GetBool('debug', False);
enabled := Config.GetBool('features.logging', True);
```

#### GetDateTime - DateTime Reading

```pascal
GetDateTime(const Key: string; const DefaultValue: TDateTime = 0): TDateTime;
```

**Examples:**
```pascal
lastModified := Config.GetDateTime('metadata.modified', Now);
```

#### GetDateTimeValue - High-Precision DateTime

```pascal
GetDateTimeValue(const Key: string; const DefaultValue: String = ''): String;
```

**Function:** Returns raw datetime string, preserving microsecond/nanosecond precision

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

### 2. TryGet Safe Access Methods

All TryGet methods provide exception-safe access, indicating success or failure through return values.

#### TryGetStr - Safe String Reading

```pascal
TryGetStr(const Key: string; out Value: string): Boolean;
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

#### TryGetInt - Safe Integer Reading

```pascal
TryGetInt(const Key: string; out Value: Integer): Boolean;
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
- `TryGetFloatValue` - High-precision float
- `TryGetBool` - Boolean
- `TryGetDateTime` - DateTime
- `TryGetDateTimeValue` - High-precision datetime
- `TryGetArray` - Array
- `TryGetTable` - Table

**Advantages:**
- ✅ No exception handling mechanism (better performance)
- ✅ Clear success/failure indication
- ✅ Suitable for scenarios requiring distinction between "non-existent" and "empty"

---

### 3. Overwrite-Protected Write Methods

All Set methods support overwrite control to prevent accidental overwriting of existing configuration items.

#### SetStr - String Writing

```pascal
SetStr(const Key: string; const Value: string; 
                Overwrite: Boolean = True): Boolean;
```

**Parameters:**
- `Key` - Key name (path not supported)
- `Value` - String value
- `Overwrite` - Whether to overwrite existing value (default True)

**Return Value:**
- `True` - Value has been set
- `False` - Key exists and Overwrite=False

**Examples:**
```pascal
// Set or overwrite
if Config.SetStr('title', 'MyApp', True) then
  WriteLn('Title set');

// Protected mode: only set if key doesn't exist
if Config.SetStr('title', 'Default', False) then
  WriteLn('Set new title')
else
  WriteLn('Title already exists, not overwritten');
```

#### Complete Set Method List

- `SetStr(Key, Value, Overwrite)` - String
- `SetInt(Key, Value, Overwrite)` - Integer
- `SetFloat(Key, Value, Overwrite)` - Float
- `SetFloatValue(key, Value, Overwrite)` - High-precision float
- `SetBool(Key, Value, Overwrite)` - Boolean
- `SetDateTime(Key, Value, Overwrite)` - DateTime
- `SetDateTimeValue(key, value, Overwrite)` - High-precision datetime
- `SetArray(Key, Value, Overwrite)` - Array
- `SetTable(Key, Value, Overwrite)` - Table

**Use Cases:**
```pascal
// Scenario 1: Set default configuration
Config.SetInt('port', 8080, False);        // Only set if doesn't exist
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

Put methods support method chaining, providing an elegant configuration building approach.

#### Put - Chained Setting

```pascal
Put(const Key: string; const Value: <Type>; 
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

// Building nested structures
var Server := TTOMLTable.Create;
Server.Put('host', 'localhost')
      .Put('port', 3000);

Config.Put('server', Server)
      .Put('timeout', 30);
```

**Advantages:**
- ✅ Concise and readable code
- ✅ Reduces temporary variables
- ✅ Modern configuration library API style
- ✅ Supports overwrite control

---

### 5. File and String Operations

#### LoadFromFile - Load from File

```pascal
LoadFromFile(const FileName: string; ClearExisting: Boolean = True;
             APreserveComments: Boolean = False): Boolean;
```

**Parameters:**
- `FileName` - File path
- `ClearExisting` - Whether to clear existing content (default True)
- `APreserveComments` - Whether to read annotations (default False)

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
SaveToFile(const FileName: string; WriteBOM: Boolean = True; AWrapWidth: Integer = 0;
           APreserveComments: Boolean = False): Boolean;
```

**Parameters:**
- `FileName` - File path
- `WriteBOM` - Whether to write UTF-8 BOM (default True)
- `AWrapWidth` - The line break position when the string is too long. The default value is 0, meaning no line break.
- **Note: If the string value contains \n, it will be automatically split into a multi-line string.**
- `APreserveComments` - Whether to write comments (default False)
**Examples:**
```pascal
if Config.SaveToFile('config.toml', True) then
  WriteLn('Save successful')
else
  WriteLn('Save failed');
```

#### LoadFromString - Parse from String

```pascal
LoadFromString(const ATOML: string; ClearExisting: Boolean = True;
               APreserveComments: Boolean = False): Boolean;
```
**parameter:**
- `ATOML` - TOML string.
- `ClearExisting` - Whether to clear existing content (default True)
- `APreserveComments` - Whether to read annotations (default False)
 
**Examples:**
```pascal
var TOML := 'title = "MyApp"' + sLineBreak +
            'version = "1.0"';

if Config.LoadFromString(TOML) then
  WriteLn('Parse successful');
```

#### ToString - Serialize to String
```pascal
ToString(AWrapWidth: Integer; APreserveComments: Boolean = False): string;  
```
**parameter:**
- `AWrapWidth` - The line break position when the string is too long. The default value is 0, meaning no line break.
- **Note: If the string value contains \n, it will be automatically split into a multi-line string.**
- `APreserveComments` - Whether to write comments (default False)
**Examples:**
```pascal
var TOML := Config.ToString;
WriteLn(TOML);
// Output:
// title = "MyApp"
// version = "1.0"
```

---

### 6. TOML and JSON Format Conversion

#### ToJSON - Convert to JSON String
```pascal
ToJSON(APretty: Boolean; AIndentSize: Integer): string;
```
**Parameters:**
- `APretty` - Output formatted with indentation (default True)
- `AIndentSize` - Number of spaces per indentation level (default 2)

#### SaveToJSONFile - Save as JSON File
```pascal
SaveToJSONFile(const FileName: string; APretty: Boolean; ABOM: Boolean): Boolean;
```
**Parameters:**
- `FileName` - File path
- `APretty` - Output formatted with indentation (default True)
- `ABOM` - Whether to write UTF-8 BOM (default False, JSON typically has no BOM)

#### LoadFromJSON - Read from JSON String
```pascal
LoadFromJSON(const AJSON: string; ANullAsEmptyString: Boolean): Boolean;
```
**Parameters:**
- `AJSON` - JSON format string
- `ANullAsEmptyString` - True converts JSON null to empty string, False ignores null keys (default False)

#### LoadFromJSONFile - Read from JSON File
```pascal
LoadFromJSONFile(const FileName: string; ANullAsEmptyString: Boolean): Boolean;
```
- `Filename` - File path
- `ANullAsEmptyString` - True converts JSON null to empty string, False ignores null keys (default False)

#### Additional functions in TOML.JSON unit include TOMLFileToJSONFile, JSONFileToTOMLFile, etc.

---

### 7. Enhanced Memory Management

#### Remove - Delete Key

```pascal
Remove(const Key: string; FreeValue: Boolean = True): Boolean;
```

**Parameters:**
- `Key` - Key name
- `FreeValue` - Whether to free the value object

**Return Value:**
- `True` - Key existed and has been deleted
- `False` - Key doesn't exist

**Examples:**
```pascal
if Config.Remove('obsolete_option', True) then
  WriteLn('Option removed');
```

#### Clear - Clear All

```pascal
procedure Clear(FreeValues: Boolean = True);
```

**Parameters:**
- `FreeValues` - Whether to free all value objects

**Examples:**
```pascal
Config.Clear(True);  // Clear and free all
```

#### Count - Get Count

```pascal
Count: Integer;
```

**Examples:**
```pascal
WriteLn('Total configuration items: ', Config.Count);
```

#### HasKey - Check Key Existence

```pascal
HasKey(const Key: string): Boolean;
```

**Examples:**
```pascal
if Config.HasKey('server.port') then
  WriteLn('Port configuration exists');
```

#### GetKeys - Get All Keys

```pascal
procedure GetKeys(Keys: TStrings; Recursive: Boolean = False);
```

**Parameters:**
- `Keys` - Output string list
- `Recursive` - Whether to recursively enumerate child table keys

**Examples:**
```pascal
var Keys := TStringList.Create;
try
  Config.GetKeys(Keys, True);  // Get all keys (including nested)
  for var Key in Keys do
    WriteLn(Key);
finally
  Keys.Free;
end;
```

#### Clone - Deep Clone

```pascal
Clone: TTOMLTable;
```

**Examples:**
```pascal
var ConfigCopy := Config.Clone;
try
  // Modify ConfigCopy without affecting Config
  ConfigCopy.SetStr('temp', 'value');
finally
  ConfigCopy.Free;
end;
```

---

### 8. TTOMLArray Helper Methods

TTOMLArray also provides a complete set of helper methods.

#### Read Methods

- `GetStr(Index, DefaultValue)` - Get string at index
- `GetInt(Index, DefaultValue)` - Get integer at index
- `GetFloat(Index, DefaultValue)` - Get float at index
- `GetBool(Index, DefaultValue)` - Get boolean at index
- `GetDateTime(Index, DefaultValue)` - Get datetime at index
- `GetArray(Index)` - Get sub-array at index
- `GetTable(Index)` - Get table at index

**Examples:**
```pascal
var Names := Config.GetArray('users');
for var i := 0 to Names.Count - 1 do
  WriteLn(Names.GetStr(i, 'Unknown'));
```

#### Append Methods (Chainable)

- `AddStr(Value)` - Append string
- `AddInt(Value)` - Append integer
- `AddFloat(Value)` - Append float
- `AddBool(Value)` - Append boolean
- `AddDateTime(Value)` - Append datetime
- `AddTable(Value)` - Append table
- `AddArray(Value)` - Append array

**Examples:**
```pascal
var AllowedIPs := TTOMLArray.Create;
AllowedIPs.AddStr('192.168.1.1')
          .AddStr('10.0.0.1')
          .AddStr('172.16.0.1');
```

#### Set Methods (Modify Element at Index)

- `SetStr(Index, Value)` - Set string at index
- `SetInt(Index, Value)` - Set integer at index
- `SetFloat(Index, Value)` - Set float at index
- `SetBool(Index, Value)` - Set boolean at index
- `SetDateTime(Index, Value)` - Set datetime at index
- `SetArray(Index, Value)` - Set array at index
- `SetTable(Index, Value)` - Set table at index

**Examples:**
```pascal
var Servers := Config.GetArray('servers');
if Servers.SetStr(0, 'updated-server.com') then
  WriteLn('First server updated');
```

#### Insert Methods (Insert at Specific Position)

- `InsertStr(Index, Value)` - Insert string at position
- `InsertInt(Index, Value)` - Insert integer at position
- `InsertFloat(Index, Value)` - Insert float at position
- `InsertBool(Index, Value)` - Insert boolean at position
- `InsertDateTime(Index, Value)` - Insert datetime at position
- `InsertArray(Index, Value)` - Insert array at position
- `InsertTable(Index, Value)` - Insert table at position

**Examples:**
```pascal
var List := TTOMLArray.Create;
List.AddStr('first')
    .AddStr('third');
    
List.InsertStr(1, 'second');  // Insert at index 1
// Result: ['first', 'second', 'third']
```

#### TryGet Methods

- `TryGetStr(Index, out Value)` - Safe string read
- `TryGetInt(Index, out Value)` - Safe integer read
- `TryGetFloat(Index, out Value)` - Safe float read
- `TryGetBool(Index, out Value)` - Safe boolean read
- `TryGetDateTime(Index, out Value)` - Safe datetime read
- `TryGetArray(Index, out Value)` - Safe array read
- `TryGetTable(Index, out Value)` - Safe table read

**Examples:**
```pascal
var
  port: Integer;
  Ports: TTOMLArray;
begin
  Ports := Config.GetArray('ports');
  if Ports.TryGetInt(0, port) then
    WriteLn('First port: ', port)
  else
    WriteLn('No port configured');
end;
```

#### Utility Methods

**RemoveAt** - Remove element at index
```pascal
function RemoveAt(Index: Integer; FreeItem: Boolean = True): Boolean;
```

**Clear** - Clear all elements
```pascal
procedure Clear(FreeItems: Boolean = True);
```

**Count** - Get element count
```pascal
function Count: Integer;
```

**ForEachTable** - Iterate table elements
```pascal
procedure ForEachTable(Proc: TProc<TTOMLTable>); overload;
procedure ForEachTable(Callback: TFunc<Integer, TTOMLTable, Boolean>; 
                       SkipNonTables: Boolean = True); overload;
```

**Examples:**
- Simple ForEachTable
```pascal
    var
      parameters: TTOMLArray;
    procedure ProcessParameter(param: TTOMLTable);
      begin
        showmessage(param.GetStr('name'));
      end;    
    parameters.ForEachTable(ProcessParameter);
```

- Enhanced ForEachTable
```pascal
var
  Root: TTOMLTable;
  UsersArray: TTOMLArray;
  TargetUser: TTOMLTable;
begin
  Root := LoadTOML('users.toml');
  UsersArray := Root.GetArray('users');
  TargetUser := nil;
  
  // Use enhanced version: supports early exit
  UsersArray.ForEachTable(
    function(Index: Integer; User: TTOMLTable): Boolean
    begin
      if User.GetStr('username') = 'bob' then
      begin
        TargetUser := User;
        Result := False;  // Found it, stop iteration
      end
      else
        Result := True;  // Continue searching
    end,
    True  // Skip non-table elements
  );
  
  if Assigned(TargetUser) then
    WriteLn('Found user: ' + TargetUser.GetStr('email'))
  else
    WriteLn('User not found');
    
  Root.Free;
end;
```

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
    
    WriteLn('Server configuration:');
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
    
    // Try loading user configuration from file
    if FileExists('user_config.toml') then
    begin
      var UserConfig := TTOMLTable.Create;
      try
        if UserConfig.LoadFromFile('user_config.toml') then
        begin
          // Merge configuration (with overwrite protection)
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
    WriteLn('Font size: ', Config.GetInt('font_size'));
    
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
    
    // Access using quotes
    var Google := Config.GetStr('"google.com"', 'Unknown');
    var GitHub := Config.GetStr('"github.com"', 'Unknown');
    
    WriteLn('google.com: ', Google);
    WriteLn('github.com: ', GitHub);
    
    // Serialization automatically adds quotes
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

When you need to distinguish between "non-existent" and "empty":

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

| Method | Return Type | Default Support | Path Support | Exception Safe |
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
|--------|-------------------|--------------|-----------------|
| `TryGetStr` | string | ✓ | ✓ |
| `TryGetInt` | Integer | ✓ | ✓ |
| `TryGetFloat` | Double | ✓ | ✓ |
| `TryGetBool` | Boolean | ✓ | ✓ |
| `TryGetDateTime` | TDateTime | ✓ | ✓ |
| `TryGetDateTimeValue` | string | ✓ | ✓ |
| `TryGetArray` | TTOMLArray | ✓ | ✓ |
| `TryGetTable` | TTOMLTable | ✓ | ✓ |

### Write Methods

| Method | Overwrite Control | Returns Boolean | Chainable |
|--------|------------------|-----------------|-----------|
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
|--------|----------|-----------------|
| `LoadFromFile` | Load from file | ✓ |
| `LoadFromJSONFile` | Load from JSON file | ✓ |
| `SaveToFile` | Save to file | ✓ |
| `SaveToJSONFile` | Save to JSON file | ✓ |
| `LoadFromString` | Parse from string | ✓ |
| `LoadFromJSONString` | Parse from JSON string | ✓ |
| `ToString` | Serialize to TOML string | - |
| `ToJSONString` | Serialize to JSON string | - |
| `TOMLFileToJSONFile` | Convert TOML file to JSON file | - |
| `JSONFileToTOMLFile` | Convert JSON file to TOML file | - |

*Note: TOMLFileToJSONFile and JSONFileToTOMLFile methods are in TOML.JSON.pas unit*

---

## ⚡ Performance Tips

1. **TryGet vs Get + Try-Except**
   - TryGet methods don't use exception mechanism, better performance
   - Suitable for high-frequency call scenarios

2. **Builder Pattern Overhead**
   - Put method chaining has no additional overhead
   - Recommended for initialization scenarios

3. **Path Access Performance**
   - Dot-separated paths require multiple lookups
   - For frequent access, consider caching TTOMLTable references

---

## 🔧 Troubleshooting

### Q: GetStr returns empty string, but I'm sure the key exists

**A:** Check if you're using the correct path or quotes:
```pascal
// Wrong: key contains dot but not quoted
val := Config.GetStr('google.com');  // Tries to access path

// Correct: use quotes
val := Config.GetStr('"google.com"');  // Access single key
```

### Q: SetStr returns False, but should succeed

**A:** Check Overwrite parameter:
```pascal
// With Overwrite=False, returns False if key exists
Config.SetStr('key', 'value1');
Config.SetStr('key', 'value2', False);  // Returns False

// Use Overwrite=True to force overwrite
Config.SetStr('key', 'value2', True);  // Returns True
```

### Q: LoadFromFile returns False

**A:** Possible reasons:
- File doesn't exist
- File permission issues
- TOML syntax errors

```pascal
if not Config.LoadFromFile('config.toml') then
  WriteLn('Load failed, using default configuration');
```

---
