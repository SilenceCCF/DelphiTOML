{ TOML.pas
  Main unit for the TOML library.
  Re-exports core types and provides high-level parse / serialize helpers.
  Conforms to the TOML v1.1.0 specification.

  Comment support (optional):
    ParseTOML / ParseTOMLFromFile now accept an APreserveComments parameter.
    SerializeTOML / SerializeTOMLToFile now accept an APreserveComments parameter.
    When both are used round-trip comment fidelity is achieved.
}
unit TOML;

interface

uses
  SysUtils, Classes, TOML.Types, TOML.Parser, TOML.Serializer;

type
  { Re-export main types }
  TTOMLValue    = TOML.Types.TTOMLValue;
  TTOMLString   = TOML.Types.TTOMLString;
  TTOMLInteger  = TOML.Types.TTOMLInteger;
  TTOMLFloat    = TOML.Types.TTOMLFloat;
  TTOMLBoolean  = TOML.Types.TTOMLBoolean;
  TTOMLDateTime = TOML.Types.TTOMLDateTime;
  TTOMLArray    = TOML.Types.TTOMLArray;
  TTOMLTable    = TOML.Types.TTOMLTable;

  { Re-export exception types }
  ETOMLException           = TOML.Types.ETOMLException;
  ETOMLParserException     = TOML.Types.ETOMLParserException;
  ETOMLSerializerException = TOML.Types.ETOMLSerializerException;

{ ---- Factory helpers ---- }

{ Creates a new TOML string value. }
function TOMLString(const AValue: string): TTOMLString;

{ Creates a new TOML integer value. }
function TOMLInteger(const AValue: Int64): TTOMLInteger;

{ Creates a new TOML float value. }
function TOMLFloat(const AValue: Double): TTOMLFloat;

{ Creates a new TOML boolean value. }
function TOMLBoolean(const AValue: Boolean): TTOMLBoolean;

{ Creates a new TOML datetime value. }
function TOMLDateTime(const AValue: TDateTime): TTOMLDateTime;

{ Creates a new empty TOML array. }
function TOMLArray: TTOMLArray;

{ Creates a new empty TOML table. }
function TOMLTable: TTOMLTable;

{ ---- Parsing ---- }

{ Parses a TOML-formatted string into a TTOMLTable.
  @param ATOML             The TOML text to parse.
  @param APreserveComments When True, comments are read and stored on the
                           resulting nodes (CommentBefore / CommentInline /
                           CommentTrailing).  Default False.
  @returns A new TTOMLTable.  Caller must free it.
  @raises ETOMLParserException on invalid TOML input. }
function ParseTOML(const ATOML: string;
                   APreserveComments: Boolean = False): TTOMLTable;

{ Parses a TOML file into a TTOMLTable.
  @param AFileName         Path to the TOML file (UTF-8 or UTF-16 with BOM).
  @param APreserveComments Preserve comments when True.
  @returns A new TTOMLTable.  Caller must free it.
  @raises ETOMLParserException on invalid TOML input.
  @raises EFileStreamError if the file cannot be opened. }
function ParseTOMLFromFile(const AFileName: string;
                            APreserveComments: Boolean = False): TTOMLTable;

{ ---- Serialization ---- }

{ Serializes a TOML value to a string.
  @param AValue            The value to serialize (usually a TTOMLTable).
  @param AWrapWidth        Maximum column width for long-string wrapping.
                           Strings with embedded newlines become multi-line
                           basic strings (""").  0 = disabled (default).
  @param APreserveComments When True, comment properties stored on each node
                           are emitted in the output.  Default False.
  @returns The serialized TOML text.
  @raises ETOMLSerializerException if the value cannot be serialized. }
function SerializeTOML(const AValue: TTOMLValue;
                       AWrapWidth: Integer = 0;
                       APreserveComments: Boolean = False): string;

{ Serializes a TOML value to a file.
  @param AValue            The value to serialize.
  @param AFileName         Output file path.
  @param BOM               Write a UTF-8 BOM (default True).
  @param AWrapWidth        Max column width for wrapping (0 = disabled).
  @param APreserveComments Emit comment nodes when True.
  @returns True if successful, False on error. }
function SerializeTOMLToFile(const AValue: TTOMLValue;
                              const AFileName: string;
                              BOM: Boolean = True;
                              AWrapWidth: Integer = 0;
                              APreserveComments: Boolean = False): Boolean;

implementation

{ ---- Factory ---- }

function TOMLString(const AValue: string): TTOMLString;
begin Result := TTOMLString.Create(AValue); end;

function TOMLInteger(const AValue: Int64): TTOMLInteger;
begin Result := TTOMLInteger.Create(AValue); end;

function TOMLFloat(const AValue: Double): TTOMLFloat;
begin Result := TTOMLFloat.Create(AValue); end;

function TOMLBoolean(const AValue: Boolean): TTOMLBoolean;
begin Result := TTOMLBoolean.Create(AValue); end;

function TOMLDateTime(const AValue: TDateTime): TTOMLDateTime;
begin Result := TTOMLDateTime.Create(AValue); end;

function TOMLArray: TTOMLArray;
begin Result := TTOMLArray.Create; end;

function TOMLTable: TTOMLTable;
begin Result := TTOMLTable.Create; end;

{ ---- Parsing ---- }

function ParseTOML(const ATOML: string; APreserveComments: Boolean): TTOMLTable;
begin
  Result := TOML.Parser.ParseTOMLString(ATOML, APreserveComments);
end;

function ParseTOMLFromFile(const AFileName: string; APreserveComments: Boolean): TTOMLTable;
begin
  Result := TOML.Parser.ParseTOMLFile(AFileName, APreserveComments);
end;

{ ---- Serialization ---- }

function SerializeTOML(const AValue: TTOMLValue;
                       AWrapWidth: Integer;
                       APreserveComments: Boolean): string;
begin
  Result := TOML.Serializer.SerializeTOML(AValue, AWrapWidth, APreserveComments);
end;

function SerializeTOMLToFile(const AValue: TTOMLValue;
                              const AFileName: string;
                              BOM: Boolean;
                              AWrapWidth: Integer;
                              APreserveComments: Boolean): Boolean;
begin
  Result := TOML.Serializer.SerializeTOMLToFile(AValue, AFileName, BOM, AWrapWidth, APreserveComments);
end;

end.
