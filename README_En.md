# DelphiTOML

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Delphi](https://img.shields.io/badge/Delphi2005%20and%20high-green.svg)](https://www.embarcadero.com/products/delphi/)
[![TOML](https://img.shields.io/badge/TOML-1.1.0-green.svg)](https://toml.io/)

A unit for parsing the [TOML](https://toml.io/) version 1.1.0 format, rewritten from [ikelaiah's TOML Parser for Free Pascal](https://github.com/ikelaiah/toml-fp) version 1.0.3, compatible with Delphi 2005 and later, with significant revisions and enhancements.
1. Fully supports the [TOML V1.1.0](https://toml.io/en/v1.1.0) specification, and has passed all 894 tests (V 1.1.0 version) of the [TOML official test program](https://github.com/toml-lang/toml-test).
2. Added the TOML.Helper.pas unit, adding a large number of functions and methods to simplify read and write operations.
3. Added the TOML.Json.pas unit to support mutual conversion between TOML and JSON formats.
4. Floating-point and date data types are supported for output in raw precision format: RawString.
5. With slight modifications, it can also support lower versions of Delphi and Free Pascal.
6. Test unit usage: Compile the tomldecoder and TOMLEncoder units into exe files, and then download and run the [official test program](https://github.com/toml-lang/toml-test/releases):

The following are the new methods compared to the original unit:
- Read
     
```
      // load from file
      Config := NewTable.LoadFromFile('config.toml');
      // or：
      Config := LoadToml('config.toml');
      // Basic types
      Config.GetStr(Key, Default);       // string
      Config.GetInt(Key, Default);       // integer
      Config.GetFloat(Key, Default);     // float
      Config.GetFloatValue(Key, Default); // float with raw precision string 
      Config.GetBool(Key, Default);      // boolean
      Config.GetDateTime(Key, Default);  // datetime
      Config.GetDateTimeValue(Key, Default);  // Date and time raw precision string

      Config.TryGetStr(Key, Value);      // string
      Config.TryGetInt(Key, Value);      // integer
      Config.TryGetFloat(Key, Value);    // float
      Config.TryGetFloatValue(Key, Value) // float with raw precision string
      Config.TryGetBool(Key, Value);     // boolean
      Config.TryetDateTime(Key, Value);  // datetime
      Config.TryGetDateTimeValue(Key, Value);  // Date and time raw precision string
      // Complex types
      Config.GetArray(Key);              // array
      Config.TryGetArray(Key, value);    // array
      Config.GetTable(Key);              // table
      Config.TryGetTable(Key, value);    // table

      // Array methods
      Array.GetStr(Index, Default);
      Array.GetInt(Index, Default);
      Array.GetTable(Index);
      Array.ForEachTable(Procedure);     // Traversing the array
```
- 写入
```
      // Types of set，The default value overrides the original value.
      Config.SetStr(key, value, [Overwrite]);
      Config.SetInt(key, value, [Overwrite]);
      Config.SetFloat(key, value, [Overwrite]);
      Config.SetFloatValue(Key, value, [Overwrite]);
      Config.SetBool(key, value, [Overwrite]);
      Config.SetDateTime(key, value, [Overwrite]);
      Config.SetDateTimeValue(key, value, [Overwrite]);
      Config.SetArray(key, value, [Overwrite]);
      Config.SetTable(key, value, [Overwrite]);

      // The `Put` method supports overloading, automatically identifies the type, and overrides the original value by default.
      Config := NewTable
        .Put(key1, value1, [Overwrite])
        .Put(key2, value2, [Overwrite])
        .Put(key3, value3, [Overwrite]);

      // The Add method of an array
      Tags := NewArray
        .AddStr('value1')
        .AddStr('value2')
        .AddStr('value3');

      Ports := NewArray
        .AddInt(8080)
        .AddInt(8081)
        .AddInt(8082);
      // Also supports：AddFloat、AddBool、AddDateTime、AddTable
      // Delete data from array by index
      Array.RemoveAt(idx);
      // Empty a array
      Array.Clear;

      // Create a table or array
      Config := NewTable;
      Tags := NewArray;
      // or:
      Config := Table;
      Tags := Arr;

      // 其它工具方法    
      Config.SaveToFile('config.toml');  // save to file
      Config.LoadFromString(ATOML,True); // load from string
      Config.ToString;                   // convert to string
      Config.Count;                      // get the total number of keys
      Config.HasKey(Key);                // check if the key exists
      Config.GetKeys(List, Recursive);   // get all key names
      Config.REmove('key');              // delete a key

      ParseTOML(ATOML);                  // load from string
      LoadTOML(FileName);                // load from file

```  
- Example：
```
    // Open a toml file
    Config := NewTable.LoadFromFile('config.toml');
    // or:
    Config := LoadToml('config.toml');
    // Read
    width := Config.GetInt('width', 800);
    title := Config.GetStr('title');
    debug := Config.GetBool('debug',False);
    name := Config.GetStr('server.host', 'localhost');  // supports dot-separated paths
    name := Config.GetStr('"google.com"', 'localhost');
    if Config.TryGetStr('name',value) then
    showmessage(value);

    // Create a table or array
    Config := NewTable;
    Tags := NewArray;

    //Create and assign values ​​simultaneously：
    Config := NewTable
      .SetStr('app_name', 'My Application')
      .SetStr('version', '1.0.0')
      .SetInt('port', 8080)
      .SetBool('debug', False);
    Tags := NewArray
      .AddStr('pascal')
      .AddStr('delphi')
      .AddStr('toml');

    // Create nested structures：
    Config := NewTable
      .Put('server',
        NewTable
          .Put('host', 'localhost')
          .Put('port', 8080)
      )
      .Put('database',
        NewTable
          .Put('host', 'localhost')
          .Put('port', 5432)
          .Put('pool_size', 10)
      );
  
    // Write (by default, overwrite the original value)
    Config.SetStr('title', 'My App');
    Config.SetInt('width', 1920, True);
    Config.SetBool('debug', False);
    Config.SetFloat('version', 1.1, False);

    // Automatically identify the type and write (by default, overwrite the original value).
    Config.Put('width', 1920)
          .Put('height', 1080)
          .Put('title', 'My App', False);
    // Save to file
    Config.SaveToFile('config.toml');

    //Create table array
    Servers := NewArray
      .AddTable(
        NewTable
          .Put('name', 'web-01')
          .Put('ip', '192.168.1.10')
      )
      .AddTable(
        NewTable
          .Put('name', 'db-01')
          .Put('ip', '192.168.1.20')
      );
    Config.SetArray('servers', Servers);
  
    // Method 1 for traversing an array
    parameters.ForEachTable(
      procedure(param: TTOMLTable)
        begin
          showmessage(param.GetStr('name'));
        end
    );
    // Method 2 for traversing an array
    procedure ProcessParameter(param: TTOMLTable);
      begin
        showmessage(param.GetStr('name'));
      end;    
    parameters.ForEachTable(ProcessParameter);  // load
```

----

The following is the original documentation for ikelaiah's TOML Parser for Free Pascal project:

----

# TOML Parser for Free Pascal

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Free Pascal](https://img.shields.io/badge/Free%20Pascal-3.2.2-blue.svg)](https://www.freepascal.org/)
[![Lazarus](https://img.shields.io/badge/Lazarus-4.0-orange.svg)](https://www.lazarus-ide.org/)
[![TOML](https://img.shields.io/badge/TOML-1.0.0-green.svg)](https://toml.io/)
[![Version](https://img.shields.io/badge/Version-1.0.3-blueviolet.svg)]()

A robust [TOML (Tom's Obvious, Minimal Language)](https://toml.io/) parser and serializer for Free Pascal, _almost_ fully compliant with the TOML v1.0.0 specification.
> [!NOTE] 
> 
> Our extensive test suite (60 tests) ensures that TOML-FP adheres to the TOML v1.0.0 specification, covering all essential data types, structures, and edge cases.

## Table of Contents

- [TOML Parser for Free Pascal](#toml-parser-for-free-pascal)
  - [Table of Contents](#table-of-contents)
  - [Overview](#overview)
  - [Features](#features)
  - [To Do / In Progress](#to-do--in-progress)
  - [Requirements](#requirements)
  - [Installation](#installation)
    - [Steps](#steps)
  - [Quick Start](#quick-start)
    - [Basic Usage](#basic-usage)
    - [Writing TOML Files](#writing-toml-files)
  - [Documentation](#documentation)
    - [Common Use Cases](#common-use-cases)
      - [Working with Arrays](#working-with-arrays)
      - [Nested Tables](#nested-tables)
      - [Hierarchical Paths vs Literal Dotted Keys](#hierarchical-paths-vs-literal-dotted-keys)
      - [Serializing Complex Structures](#serializing-complex-structures)
    - [Memory Management](#memory-management)
      - [Creating Tables](#creating-tables)
      - [Adding Nested Tables or Values](#adding-nested-tables-or-values)
      - [Freeing Tables:](#freeing-tables)
      - [Avoid Explicitly Freeing Nested Objects:](#avoid-explicitly-freeing-nested-objects)
  - [API Reference](#api-reference)
    - [Types](#types)
    - [Helper Functions for Creating TOML Values](#helper-functions-for-creating-toml-values)
    - [Parsing Functions](#parsing-functions)
    - [Serialization Functions](#serialization-functions)
  - [Testing](#testing)
    - [Test Coverage Overview](#test-coverage-overview)
    - [Sample Test Output](#sample-test-output)
  - [Examples](#examples)
  - [Contributing](#contributing)
  - [License](#license)
  - [Acknowledgments](#acknowledgments)



## Overview

TOML-FP provides a complete solution for working with TOML configuration files in Free Pascal applications. Whether you need to read configuration files or generate them, TOML-FP offers an intuitive API with comprehensive type support and robust error handling.

## Features

- **Full TOML v1.0.0 Compliance:** Supports all TOML data types and structures, including proper serialization of nested (dotted) tables.
- **Type-Safe API:** Strong typing with compile-time checks
- **Memory Management:** Automatic cleanup with proper object lifecycle management
- **Error Handling:** Detailed error messages and exception handling
- **Serialization:** Convert Pascal objects to TOML and back
- **Documentation:** Comprehensive examples and API documentation
- **Test Suite:** Comprehensive test suite (60 items)

## To Do / In Progress

- [ ] More tests for error handling: Robust testing of invalid inputs and ensuring appropriate error messages or handling mechanisms.
- [ ] Performance optimization for large TOML files
- [ ] Additional examples for common use cases

## Requirements

- Free Pascal Compiler 3.2.2 or later
- Lazarus IDE 4.0 (for running tests)

## Installation


### Steps

1. Clone the repository:
   
   ```bash
   git clone https://github.com/ikelaiah/toml-fp.git
   ```

2. Add to your project:
   - Copy the `src` directory to your project.
   - Add the `src` directory to your project's unit search path.
   - Add the main `TOML` unit to your `uses` clause:
     ```pascal
     uses
       TOML; 
     ```
   - For direct access to specific types like `TTOMLValueType` or if you prefer explicit qualification, you might also include `TOML.Types`:
     ```pascal
     uses
       TOML, TOML.Types; // If needing TTOMLValueType, etc.
     ```
     However, for most common operations (parsing, serializing, using helper functions like `TOMLTable`), `uses TOML;` is sufficient.

## Quick Start

### Basic Usage

```pascal
program BasicParseTOML;

{$mode objfpc}{$H+}{$J-}

uses
  TOML;

var
  Config: TTOMLTable;
  RevisionValue, ProjectValue, ProjectName: TTOMLValue;
  ProjectTable: TTOMLTable;

begin
  // Parse TOML from file
  Config := ParseTOMLFromFile('config.toml');
  try

    // Access a string value
    if (Config.TryGetValue('revision', RevisionValue)) then
      WriteLn('The value of ''revision'' is ', RevisionValue.AsString);

    // Access nested values safely
    if Config.TryGetValue('project', ProjectValue) and
      (ProjectValue is TTOMLTable) then
    begin
      ProjectTable := TTOMLTable(ProjectValue);
      if ProjectTable.TryGetValue('name', ProjectName) then
        WriteLn('Project Name: ', ProjectName.AsString)
      else
        WriteLn('Project name not found');
    end
    else
      WriteLn('Project configuration not found');
  finally
    Config.Free;
  end;
end.
```

Example `config.toml`:

```toml
# config.toml

revision = "1.2.1af"

[project]
name = "My Amazing Project"
version = "1.0.0"
```


### Writing TOML Files
```pascal
program BasicSerializeTOML;

{$mode objfpc}{$H+}{$J-}

uses
  TOML;

var
  Config: TTOMLTable;
  Database: TTOMLTable;
begin
  Config := TOMLTable;
  try
    Database := TOMLTable;
    Database.Add('host', TOMLString('localhost'));
    Database.Add('port', TOMLInteger(5432));
    Config.Add('database', Database);

    if SerializeTOMLToFile(Config, 'config.toml') then
      WriteLn('Configuration saved successfully')
    else
      WriteLn('Error saving configuration');
  finally
    Config.Free;
  end.
end.
```

## Documentation

### Common Use Cases

#### Working with Arrays
```pascal
var
  Config: TTOMLTable;
  Tags: TTOMLArray;
begin
  Config := TOMLTable;
  try
    Tags := TOMLArray;
    Tags.Add(TOMLString('pascal'));
    Tags.Add(TOMLString('toml'));
    Config.Add('tags', Tags);
    
    WriteLn(SerializeTOML(Config));
  finally
    Config.Free;
  end.
end.
```

#### Nested Tables
```pascal
var
  Config: TTOMLTable;
  Database, Server: TTOMLTable;
  SerializedTOML: string;
begin
  Config := TOMLTable;
  try
    Database := TOMLTable;
    Database.Add('host', TOMLString('localhost'));
    Database.Add('port', TOMLInteger(5432));
    
    Server := TOMLTable;
    Server.Add('database', Database); // Nest Database table under Server
    
    Config.Add('server', Server);     // Nest Server table under Config
    
    SerializedTOML := SerializeTOML(Config);
    WriteLn(SerializedTOML);
    // Expected output:
    // [server.database]
    // host = "localhost"
    // port = 5432
  finally
    Config.Free; // Frees Config, Server, and Database tables
  end.
end.
```

#### Hierarchical Paths vs Literal Dotted Keys

TOML-FP correctly handles the distinction between hierarchical paths and literal dotted keys as per the TOML specification:

1. **Hierarchical Table Paths**:
   ```pascal
   // This creates a nested hierarchy: [server.database]
   ServerTable := TOMLTable;
   DatabaseTable := TOMLTable;
   DatabaseTable.Add('port', TOMLInteger(5432));
   
   ServerTable.Add('database', DatabaseTable);
   Config.Add('server', ServerTable);
   ```
   Serializes to:
   ```toml
   [server.database]
   port = 5432
   ```

2. **Literal Dotted Keys**:
   ```pascal
   // This creates a literal dotted key: ["server.database"]
   LiteralTable := TOMLTable;
   LiteralTable.Add('port', TOMLInteger(5432));
   
   Config.Add('server.database', LiteralTable);
   ```
   Serializes to:
   ```toml
   ["server.database"]
   port = 5432
   ```

The serializer automatically determines whether to quote key components based on the TOML specification rules.

> [!TIP]  
> According to the TOML specification: "Quoted keys follow the exact same rules as either basic strings or literal strings and allow you to use a much broader set of key names. **Best practice is to use bare keys except when absolutely necessary.**"
>
> In practice, this means you should design your configuration to use hierarchical nesting with simple key names rather than relying on keys with dots or special characters.

#### Serializing Complex Structures
```pascal
program BasicSerializeTOML;

{$mode objfpc}{$H+}{$J-}

uses
  TOML, SysUtils;

var
  Config, ServerConfig: TTOMLTable;
  Ports: TTOMLArray;
  SerializedTOML: string;
begin
  Config := TOMLTable;
  try
    // Create a nested table
    ServerConfig := TOMLTable;
    ServerConfig.Add('host', TOMLString('127.0.0.1'));
    ServerConfig.Add('enabled', TOMLBoolean(True));

    // Create and populate an array
    Ports := TOMLArray;
    Ports.Add(TOMLInteger(80));
    Ports.Add(TOMLInteger(443));
    ServerConfig.Add('ports', Ports);

    // Add the server config to main config
    Config.Add('server', ServerConfig);

    // Add some basic metadata
    Config.Add('version', TOMLFloat(1.0));
    Config.Add('last_updated', TOMLDateTime(Now));

    // Serialize to TOML format
    SerializedTOML := SerializeTOML(Config);
    WriteLn('Generated TOML:');
    WriteLn(SerializedTOML);

    // Save to file
    if SerializeTOMLToFile(Config, 'config.toml') then
      WriteLn('Successfully saved to file')
    else
      WriteLn('Error saving to file');

  finally
    Config.Free;
  end.
end.
```

This will generate TOML like:
```toml
version = 1.0
last_updated = 2024-03-20T15:30:45Z

[server]
host = "127.0.0.1"
enabled = true
ports = [ 80, 443 ]
```

Note: All values are properly type-checked and memory-managed. The library ensures that:
- Each value has the correct TOML type
- Arrays maintain type consistency
- All objects are properly freed
- Type conversions are validated


### Memory Management

> [!NOTE]
>
> **Only free the top-level owner table** to avoid memory management issues.

- Proper memory management is essential to prevent memory leaks in your applications. TOML-FP follows a clear ownership hierarchy where parent tables own their nested tables and values. Here's how it works:

#### Creating Tables
- When you create a `TTOMLTable`, it acts as an owner for any nested tables or values you add to it.

#### Adding Nested Tables or Values
- Use the `Add` method to insert nested tables or values into a parent table.
- Example:

```pascal
var
  Config: TTOMLTable;
  Database: TTOMLTable;
begin
  Config := TOMLTable;
  Database := TOMLTable;
  Config.Add('database', Database);
  // ...
  Config.Free; // This frees all nested tables and values
end.
``` 

#### Freeing Tables:
- **Only free the top-level owner table**.
- Frees all nested tables and values automatically.
- Example:

```pascal
var
  Config: TTOMLTable;
begin
  Config := TOMLTable;
  // ... add nested tables and values ...
  Config.Free; // This frees all nested tables and values
end.
```

#### Avoid Explicitly Freeing Nested Objects:

- Do not manually free nested tables or values to prevent memory management issues.

## API Reference

### Types

- `TTOMLValue` - Base type for all TOML values
- `TTOMLTable` - Represents a TOML table
- `TTOMLArray` - Represents a TOML array
- `TTOMLString` - Represents a TOML string value
- `TTOMLInteger` - Represents a TOML integer value
- `TTOMLFloat` - Represents a TOML float value
- `TTOMLBoolean` - Represents a TOML boolean value
- `TTOMLDateTime` - Represents a TOML datetime value

### Helper Functions for Creating TOML Values

- `TOMLString`

```pascal
  function TOMLString(const AValue: string): TTOMLString;
```
Creates a TOML string value.

- `TOMLInteger`

```pascal
  function TOMLInteger(const AValue: Int64): TTOMLInteger;
```
Creates a TOML integer value.

- `TOMLFloat`

```pascal
  function TOMLFloat(const AValue: Double): TTOMLFloat;
```
Creates a TOML float value.

- `TOMLBoolean` 

```pascal
    function TOMLBoolean(const AValue: Boolean): TTOMLBoolean;
```
Creates a TOML boolean value.

- `TOMLDateTime`

```pascal
    function TOMLDateTime(const AValue: TDateTime): TTOMLDateTime;
```
Creates a TOML datetime value.

- `TOMLArray` 

```pascal
  function TOMLArray: TTOMLArray;
```
Creates a TOML array.

- `TOMLTable`

```pascal
  function TOMLTable: TTOMLTable;
```
Creates a TOML table.

### Parsing Functions

- `ParseTOML`

```pascal
  function ParseTOML(const ATOML: string): TTOMLTable;
```
Parses a TOML-formatted string into a `TTOMLTable` object. Raises `ETOMLParserException` on error.

- `ParseTOMLFromFile`

```pascal
  function ParseTOMLFromFile(const AFileName: string): TTOMLTable;
```
Parses a TOML file into a `TTOMLTable` object. Reads the file content and then parses it. Raises `ETOMLParserException` on parsing errors or file system errors.

### Serialization Functions
- `SerializeTOML`

```pascal
  function SerializeTOML(const AValue: TTOMLValue): string;
```
Serializes a `TTOMLValue` (typically a `TTOMLTable` for a whole document) into a TOML-formatted string.

- `SerializeTOMLToFile`

```pascal
  function SerializeTOMLToFile(const AValue: TTOMLValue; const AFileName: string): Boolean;
```
Serializes a `TTOMLValue` and saves it to the specified file. Returns `True` on success, `False` on failure (e.g., file I/O error).

## Testing

The library includes a comprehensive test suite (60 items). 

To run the tests:

1. Open `tests/TestRunner.lpi` in Lazarus
2. Build and run the project

### Test Coverage Overview

See [Test-Coverage-Overview.md](docs/Test-Coverage-Overview.md) for details.

- Basic Types:
  - Strings, Integers, Floats, Booleans, DateTime
- Advanced Structures:
  - Multiline and Literal Strings
  - Homogeneous and Mixed-Type Arrays
  - Nested and Inline Tables
- Serialization:
  - Accurate conversion of Pascal objects to TOML format and vice versa
- Error Handling:
  - Robust tests for invalid inputs, duplicate keys, and other edge cases

### Sample Test Output

```bash
$ ./TestRunner.exe -a --format=plain
 Time:00.049 N:60 E:0 F:0 I:0
  TTOMLTestCase Time:00.049 N:60 E:0 F:0 I:0
    Test01_StringValue
    Test02_IntegerValue
    ...
    Test72_LiteralDottedKeyTable

Number of run tests: 60
Number of errors:    0
Number of failures:  0

Heap dump by heaptrc unit of path\to\TestRunner.exe
3871 memory blocks allocated : 248475/265224
3871 memory blocks freed     : 248475/265224
0 unfreed memory blocks : 0
True heap size : 294912 (256 used in System startup)
True free heap : 294656
``` 

## Examples

Check out the `examples` directory and the test cases, `tests/TestCaseTOML.pas`, for more detailed usage examples:

- Basic Configuration Reading
- Writing Complex Data Structures
- Error Handling Patterns
- Integration Examples

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

Please ensure:

- Code follows the project's style guidelines
- All tests pass
- New features include appropriate tests
- Documentation is updated

## License

This project is licensed under the MIT License - see the [LICENSE.md](LICENSE.md) file for details.

## Acknowledgments

- TOML specification creators and maintainers
- Free Pascal and Lazarus communities
- [SilenceCCF](https://github.com/SilenceCCF)
- All contributors to this project
