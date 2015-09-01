-- EMACS settings: -*-  tab-width: 2; indent-tabs-mode: t -*-
-- vim: tabstop=2:shiftwidth=2:noexpandtab
-- kate: tab-width 2; replace-tabs off; indent-width 2;
-- 
-- =============================================================================
--       _ ____   ___  _   _        __              __     ___   _ ____  _     
--      | / ___| / _ \| \ | |      / _| ___  _ __   \ \   / / | | |  _ \| |    
--   _  | \___ \| | | |  \| |_____| |_ / _ \| '__|___\ \ / /| |_| | | | | |    
--  | |_| |___) | |_| | |\  |_____|  _| (_) | | |_____\ V / |  _  | |_| | |___ 
--   \___/|____/ \___/|_| \_|     |_|  \___/|_|        \_/  |_| |_|____/|_____|
--
-- =============================================================================
-- Authors:					Patrick Lehmann
-- 
-- Package:					JSON parser and query routines
--
-- Description:
-- ------------------------------------
--		For detailed documentation see below.
--
-- License:
-- ============================================================================
-- Copyright 2007-2015 Patrick Lehmann - Dresden, Germany
-- 
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
-- 
--		http://www.apache.org/licenses/LICENSE-2.0
-- 
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
-- ============================================================================

library Std;
use			Std.TextIO.all;

library	IEEE;
use			IEEE.STD_LOGIC_1164.all;


package JSON is
	constant C_JSON_VERBOSE		: BOOLEAN		:= FALSE;
	constant C_JSON_NUL				: CHARACTER	:= '`';

	subtype T_UINT16 is NATURAL range 0 to 2**16-1;
	type T_NATVEC is array(NATURAL range <>) of NATURAL;

	type T_ELEMENT_TYPE is (ELEM_KEY, ELEM_OBJECT, ELEM_LIST, ELEM_STRING, ELEM_NUMBER, ELEM_NULL, ELEM_TRUE, ELEM_FALSE);

	type T_JSON_INDEX_ELEMENT	is record
		Index				: T_UINT16;
		ChildIndex	: T_UINT16;
		NextIndex		: T_UINT16;
		StringStart	: T_UINT16;
		StringEnd		: T_UINT16;
		ElementType	: T_ELEMENT_TYPE;
	end record;

	type T_JSON_INDEX is array(NATURAL range <>) of T_JSON_INDEX_ELEMENT;

	constant C_JSON_ERROR_MESSAGE_LENGTH	: NATURAL		:= 64;

	type T_JSON is record
		Content			: STRING(1 to T_UINT16'high);
		Index				: T_JSON_INDEX(0 to 1023);
		Error				: STRING(1 to C_JSON_ERROR_MESSAGE_LENGTH);
	end record;
	
	type T_JSON_PATH_ELEMENT_TYPE is (PATH_ELEM_KEY, PATH_ELEM_INDEX);
	
	type T_JSON_PATH_ELEMENT is record
		StringStart		: T_UINT16;
		StringEnd			: T_UINT16;
		ElementType		: T_JSON_PATH_ELEMENT_TYPE;
	end record;
	
	type T_JSON_PATH is array(NATURAL range <>) of T_JSON_PATH_ELEMENT;
	
	impure function jsonLoadFile(FileName : STRING) return T_JSON;
	
	function jsonParsePath(Path : STRING) return T_JSON_PATH;
	
	function jsonGetElementIndex(JSONContext : T_JSON; Path : STRING) return T_UINT16;
	function jsonGetBoolean(JSONContext : T_JSON; Path : STRING) return BOOLEAN;
	function jsonGetString(JSONContext : T_JSON; Path : STRING) return STRING;
end package;


package body JSON is
	-- inlined function from PoC.utils, to break dependency
	function ite(cond : BOOLEAN; value1 : STRING; value2 : STRING) return STRING is begin
		if cond then	return value1;	else	return value2;	end if;
	end function;
	function imin(arg1 : integer; arg2 : integer) return integer is begin
		if arg1 < arg2 then return arg1;	else	return arg2;	end if;
	end function;
	function imax(arg1 : integer; arg2 : integer) return integer is begin
		if arg1 > arg2 then return arg1;	else	return arg2;	end if;
	end function;

	-- chr_is* function
	function chr_isDigit(chr : CHARACTER) return BOOLEAN is
	begin
		return (CHARACTER'pos('0') <= CHARACTER'pos(chr)) and (CHARACTER'pos(chr) <= CHARACTER'pos('9'));
	end function;
	
--	function chr_isLowerHexDigit(chr : CHARACTER) return BOOLEAN is
--	begin
--		return (CHARACTER'pos('a') <= CHARACTER'pos(chr)) and (CHARACTER'pos(chr) <= CHARACTER'pos('f'));
--	end function;
--	
--	function chr_isUpperHexDigit(chr : CHARACTER) return BOOLEAN is
--	begin
--		return (CHARACTER'pos('A') <= CHARACTER'pos(chr)) and (CHARACTER'pos(chr) <= CHARACTER'pos('F'));
--	end function;
--
--	function chr_isHexDigit(chr : CHARACTER) return BOOLEAN is
--	begin
--		return chr_isDigit(chr) or chr_isLowerHexDigit(chr) or chr_isUpperHexDigit(chr);
--	end function;

	function chr_isLowerAlpha(chr : CHARACTER) return BOOLEAN is
	begin
		return (CHARACTER'pos('a') <= CHARACTER'pos(chr)) and (CHARACTER'pos(chr) <= CHARACTER'pos('z'));
	end function;

	function chr_isUpperAlpha(chr : CHARACTER) return BOOLEAN is
	begin
		return (CHARACTER'pos('A') <= CHARACTER'pos(chr)) and (CHARACTER'pos(chr) <= CHARACTER'pos('Z'));
	end function;
	
	function chr_isAlpha(chr : CHARACTER) return BOOLEAN is
	begin
		return chr_isLowerAlpha(chr) or chr_isUpperAlpha(chr);
	end function;

	function chr_isSpecial(chr : CHARACTER) return BOOLEAN is
	begin
		return (chr = '_') or (chr = '-') or (chr = '.') or (chr = '#') or (chr = '!') or (chr = '$');
	end function;
	
	function chr_isIdentifier(chr : CHARACTER) return BOOLEAN is
	begin
		return	chr_isAlpha(chr) or chr_isDigit(chr) or chr_isSpecial(chr);
	end function;
	
	function str_match(str1 : STRING; str2 : STRING) return BOOLEAN is
		constant len	: NATURAL 		:= imin(str1'length, str2'length);
	begin
		-- if both strings are empty
		if ((str1'length = 0 ) and (str2'length = 0)) then		return TRUE;	end if;
		-- compare char by char
		for i in str1'low to str1'low + len - 1 loop
			if (str1(i) /= str2(str2'low + (i - str1'low))) then
				return FALSE;
			elsif ((str1(i) = C_JSON_NUL) xor (str2(str2'low + (i - str1'low)) = C_JSON_NUL)) then
				return FALSE;
			elsif ((str1(i) = C_JSON_NUL) and (str2(str2'low + (i - str1'low)) = C_JSON_NUL)) then
				return TRUE;
			end if;
		end loop;
		-- check special cases, 
		return (((str1'length = len) and (str2'length = len)) or									-- both strings are fully consumed and equal
						((str1'length > len) and (str1(str1'low + len) = C_JSON_NUL)) or	-- str1 is longer, but str_length equals len
						((str2'length > len) and (str2(str2'low + len) = C_JSON_NUL)));		-- str2 is longer, but str_length equals len
	end function;
	
	function to_natural_dec(str : STRING) return INTEGER is
		variable Result			: NATURAL;
		variable Digit			: INTEGER;
	begin
		for i in str'range loop
			Result	:= Result * 10 + (character'pos(str(i)) - character'pos('0'));
		end loop;
		return Result;
--		return INTEGER'value(str);			-- 'value(...) is not supported by Vivado Synth 2014.1
	end function;
	
	function errorMessage(str : string) return STRING is
		constant ConstNUL		: STRING(1 to 1)				:= (others => C_JSON_NUL);
		variable Result			: STRING(1 to C_JSON_ERROR_MESSAGE_LENGTH);
	begin
		Result := (others => C_JSON_NUL);
		if (str'length > 0) then		-- workaround for Quartus II
			Result(1 to imin(C_JSON_ERROR_MESSAGE_LENGTH, imax(1, str'length))) := ite((str'length > 0), str(1 to imin(C_JSON_ERROR_MESSAGE_LENGTH, str'length)), ConstNUL);
		end if;
		return Result;
	end function;
	
	impure function jsonLoadFile(FileName : STRING) return T_JSON is
		file FileHandle				: TEXT open READ_MODE is FileName;
		variable CurrentLine	: LINE;
		variable CurrentChar	: CHARACTER;
		variable IsString			: BOOLEAN;
		
		variable Result				: T_JSON;
		
		constant VERBOSE			: BOOLEAN					:= C_JSON_VERBOSE or FALSE;
		constant C_JSON_NULL	: STRING(1 to 4)	:= "null";
		constant C_JSON_TRUE	: STRING(1 to 4)	:= "true";
		constant C_JSON_FALSE	: STRING(1 to 5)	:= "false";
		
		type T_PARSER_STATE		is (
			ST_HEADER,
				ST_OBJECT, ST_LIST,
				ST_KEY, ST_KEY_END,
				ST_DELIMITER1, ST_DELIMITER2, ST_DELIMITER3,
				ST_STRING,	ST_STRING_END,
				ST_NUMBER,	ST_NUMBER_END,
				ST_NULL_END, ST_TRUE_END, ST_FALSE_END,
			ST_CLOSED
		);
		type T_PARSER_STACK_ELEMENT is record
			State		: T_PARSER_STATE;
			Index		: T_UINT16;
		end record;
		
		type T_PARSER_STACK		is array(NATURAL range <>) of T_PARSER_STACK_ELEMENT;

		procedure printParserStack(ParserStack : T_PARSER_STACK) is
		begin
			report "  ParserStack: depth=" & INTEGER'image(ParserStack'length) severity NOTE;
			for i in ParserStack'range loop
				report "    " & INTEGER'image(i) & ": state=" & T_PARSER_STATE'image(ParserStack(i).State) & "  index=" & INTEGER'image(ParserStack(i).Index) severity NOTE;
			end loop;
		end procedure;
		
		procedure printIndex(Index : T_JSON_INDEX; Content : STRING) is
		begin
			report "  Index: depth=" & INTEGER'image(Index'length) severity NOTE;
			for i in Index'range loop
				report "    " & INTEGER'image(i) &
						": index=" & INTEGER'image(Index(i).Index) &
						"  child=" & INTEGER'image(Index(i).ChildIndex) &
						"  next=" & INTEGER'image(Index(i).NextIndex) &
						"  start=" & INTEGER'image(Index(i).StringStart) &
						"  end=" & INTEGER'image(Index(i).StringEnd) &
						"  type=" & T_ELEMENT_TYPE'image(Index(i).ElementType)
					 severity NOTE;
			end loop;
		end procedure;
		
		constant PARSER_DEPTH		: POSITIVE			:= 128;
		variable StackPointer		: NATURAL range 0 to PARSER_DEPTH - 1;
		variable ParserStack		: T_PARSER_STACK(0 to PARSER_DEPTH - 1);
		variable ContentWriter	: T_UINT16;
		variable IndexWriter		: T_UINT16;
	begin
		StackPointer										:= 0;
		ParserStack(StackPointer).State	:= ST_HEADER;
		ParserStack(StackPointer).Index	:= 0;
		ContentWriter										:= 0;
		IndexWriter											:= 0;
		
		Result.Error										:= (1 to 64 => C_JSON_NUL);
		
		loopi : for i in 0 to Result.Index'high loop
			exit when endfile(FileHandle);
			readline(FileHandle, CurrentLine);
			loopj : for j in CurrentLine.all'range loop
				read(CurrentLine, CurrentChar, IsString);
				next loopi when (IsString = FALSE);
			
				if (VERBOSE = TRUE) then report "---------------------------------------------------" & LF &
						 "Parser State:" & LF &
						 "  CurrentChar='" & CurrentChar & "'" & LF &
						 "  State=" & T_PARSER_STATE'image(ParserStack(StackPointer).State) & LF &
						 "  StackPointer=" & INTEGER'image(StackPointer)
					severity NOTE; end if;
			
				case ParserStack(StackPointer).State is
					when ST_HEADER =>
						case CurrentChar is
							when ' ' | HT =>												next loopj;
							when '{' =>
								if (VERBOSE = TRUE) then report "Found: Object - Add new IndexElement(OBJ) at pos " & INTEGER'image(IndexWriter) severity NOTE; end if;
								Result.Index(IndexWriter).Index				:= IndexWriter;
								Result.Index(IndexWriter).ElementType	:= ELEM_OBJECT;
								StackPointer													:= StackPointer + 1;
								ParserStack(StackPointer).State				:= ST_OBJECT;
								ParserStack(StackPointer).Index				:= IndexWriter;
							when '[' =>
								if (VERBOSE = TRUE) then report "Found: List - Add new IndexElement(LIST) at pos " & INTEGER'image(IndexWriter) severity NOTE; end if;
								Result.Index(IndexWriter).Index				:= IndexWriter;
								Result.Index(IndexWriter).ElementType	:= ELEM_LIST;
								StackPointer													:= StackPointer + 1;
								ParserStack(StackPointer).State				:= ST_LIST;
								ParserStack(StackPointer).Index				:= IndexWriter;
							when others =>
								Result.Error := errorMessage("Parsing Header: Char '" & CurrentChar & "' is not allowed.");
								exit loopi;
						end case;
				
					when ST_OBJECT =>
						case CurrentChar is
							when ' ' | HT =>												next loopj;
							when '"' =>
								IndexWriter														:= IndexWriter + 1;
								if (VERBOSE = TRUE) then report "Found: Key - Add new IndexElement(KEY) at pos " & INTEGER'image(IndexWriter) & " setting Start to " & INTEGER'image(ContentWriter + 1) severity NOTE; end if;
								Result.Index(IndexWriter).Index				:= IndexWriter;
								Result.Index(IndexWriter).ElementType	:= ELEM_KEY;
								Result.Index(IndexWriter).StringStart	:= ContentWriter + 1;
								
								if (VERBOSE = TRUE) then report "Linking new key to index " & INTEGER'image(ParserStack(StackPointer).Index) & " as child." severity NOTE; end if;
								Result.Index(ParserStack(StackPointer).Index).ChildIndex	:= IndexWriter;

								StackPointer													:= StackPointer + 1;
								ParserStack(StackPointer).State				:= ST_KEY;
								ParserStack(StackPointer).Index				:= IndexWriter;
							when others =>
								Result.Error := errorMessage("Parsing Object: Char '" & CurrentChar & "' is not allowed.");
								exit loopi;
						end case;
						
					when ST_LIST =>
						case CurrentChar is
							when ' ' | HT =>												next loopj;
							when '{' =>
								IndexWriter														:= IndexWriter + 1;
								if (VERBOSE = TRUE) then report "Found: Object - Add new IndexElement(OBJ) at pos " & INTEGER'image(IndexWriter) severity NOTE; end if;
								Result.Index(IndexWriter).Index				:= IndexWriter;
								Result.Index(IndexWriter).ElementType	:= ELEM_OBJECT;
								
								if (VERBOSE = TRUE) then report "Linking new key to index " & INTEGER'image(ParserStack(StackPointer).Index) & " as child." severity NOTE; end if;
								Result.Index(ParserStack(StackPointer).Index).ChildIndex	:= IndexWriter;
								
								StackPointer													:= StackPointer + 1;
								ParserStack(StackPointer).State				:= ST_OBJECT;
								ParserStack(StackPointer).Index				:= IndexWriter;
							when '[' =>
								IndexWriter														:= IndexWriter + 1;
								if (VERBOSE = TRUE) then report "Found: List - Add new IndexElement(LIST) at pos " & INTEGER'image(IndexWriter) severity NOTE; end if;
								Result.Index(IndexWriter).Index				:= IndexWriter;
								Result.Index(IndexWriter).ElementType	:= ELEM_LIST;
								
								if (VERBOSE = TRUE) then report "Linking new key to index " & INTEGER'image(ParserStack(StackPointer).Index) & " as child." severity NOTE; end if;
								Result.Index(ParserStack(StackPointer).Index).ChildIndex	:= IndexWriter;
								
								StackPointer													:= StackPointer + 1;
								ParserStack(StackPointer).State				:= ST_LIST;
								ParserStack(StackPointer).Index				:= IndexWriter;
							when '"' =>
								IndexWriter														:= IndexWriter + 1;
								if (VERBOSE = TRUE) then report "Found: String - Add new IndexElement(STR) at pos " & INTEGER'image(IndexWriter) & " setting Start to " & INTEGER'image(ContentWriter + 1) severity NOTE; end if;
								Result.Index(IndexWriter).Index				:= IndexWriter;
								Result.Index(IndexWriter).ElementType	:= ELEM_STRING;
								Result.Index(IndexWriter).StringStart	:= ContentWriter + 1;
								
								if (VERBOSE = TRUE) then report "Linking new key to index " & INTEGER'image(ParserStack(StackPointer).Index) & " as child." severity NOTE; end if;
								Result.Index(ParserStack(StackPointer).Index).ChildIndex	:= IndexWriter;
								
								StackPointer													:= StackPointer + 1;
								ParserStack(StackPointer).State				:= ST_STRING;
								ParserStack(StackPointer).Index				:= IndexWriter;
							when '-' | '0' | '1' | '2' | '3' | '4' | '5' | '6' | '7' | '8' | '9' =>
								ContentWriter													:= ContentWriter + 1;
								Result.Content(ContentWriter)					:= CurrentChar;
								
								IndexWriter														:= IndexWriter + 1;
								if (VERBOSE = TRUE) then report "Found: Number - Add new IndexElement(NUM) at pos " & INTEGER'image(IndexWriter) & " setting Start to " & INTEGER'image(ContentWriter) severity NOTE; end if;
								Result.Index(IndexWriter).Index				:= IndexWriter;
								Result.Index(IndexWriter).ElementType	:= ELEM_NUMBER;
								Result.Index(IndexWriter).StringStart	:= ContentWriter;
								
								if (VERBOSE = TRUE) then report "Linking new key to index " & INTEGER'image(ParserStack(StackPointer).Index) & " as child." severity NOTE; end if;
								Result.Index(ParserStack(StackPointer).Index).ChildIndex	:= IndexWriter;
								
								StackPointer													:= StackPointer + 1;
								ParserStack(StackPointer).State				:= ST_NUMBER;
								ParserStack(StackPointer).Index				:= IndexWriter;
							when 'n' | 'N' =>
								for k in 2 to 4 loop
									read(CurrentLine, CurrentChar, IsString);
									if (IsString = FALSE) then
										Result.Error := errorMessage("Parsing List: Keyword 'null' is not complete.");
										exit loopi;
									elsif (CurrentChar /= C_JSON_NULL(k)) then
										Result.Error := errorMessage("Parsing List: Keyword 'null' has a not allowed CHARACTERs.");
										exit loopi;
									end if;
								end loop;
								IndexWriter														:= IndexWriter + 1;
								if (VERBOSE = TRUE) then report "Found: NULL - Add new IndexElement(NULL) at pos " & INTEGER'image(IndexWriter) severity NOTE; end if;
								Result.Index(IndexWriter).Index				:= IndexWriter;
								Result.Index(IndexWriter).ElementType	:= ELEM_NULL;
								Result.Index(IndexWriter).StringStart	:= 0;
								Result.Index(IndexWriter).StringEnd		:= 0;
								
								if (VERBOSE = TRUE) then report "Linking new key to index " & INTEGER'image(ParserStack(StackPointer).Index) & " as child." severity NOTE; end if;
								Result.Index(ParserStack(StackPointer).Index).ChildIndex	:= IndexWriter;
								
								StackPointer													:= StackPointer + 1;
								ParserStack(StackPointer).State				:= ST_NULL_END;
								ParserStack(StackPointer).Index				:= IndexWriter;
							when 't' | 'T' =>
								for k in 2 to 4 loop
									read(CurrentLine, CurrentChar, IsString);
									if (IsString = FALSE) then
										Result.Error := errorMessage("Parsing Delimiter3: Keyword 'true' is not complete.");
										exit loopi;
									elsif (CurrentChar /= C_JSON_TRUE(k)) then
										Result.Error := errorMessage("Parsing Delimiter3: Keyword 'true' as not allowed CHARACTERs.");
										exit loopi;
									end if;
								end loop;
								IndexWriter														:= IndexWriter + 1;
								if (VERBOSE = TRUE) then report "Found: TRUE - Add new IndexElement(TRUE) at pos " & INTEGER'image(IndexWriter) severity NOTE; end if;
								Result.Index(IndexWriter).Index				:= IndexWriter;
								Result.Index(IndexWriter).ElementType	:= ELEM_TRUE;
								Result.Index(IndexWriter).StringStart	:= 0;
								Result.Index(IndexWriter).StringEnd		:= 0;
								
								if (VERBOSE = TRUE) then report "Linking new key to index " & INTEGER'image(ParserStack(StackPointer).Index) & " as child." severity NOTE; end if;
								Result.Index(ParserStack(StackPointer).Index).ChildIndex	:= IndexWriter;
								
								StackPointer													:= StackPointer + 1;
								ParserStack(StackPointer).State				:= ST_TRUE_END;
								ParserStack(StackPointer).Index				:= IndexWriter;
							when 'f' | 'F' =>
								for k in 2 to 5 loop
									read(CurrentLine, CurrentChar, IsString);
									if (IsString = FALSE) then
										Result.Error := errorMessage("Parsing Delimiter3: Keyword 'false' is not complete.");
										exit loopi;
									elsif (CurrentChar /= C_JSON_FALSE(k)) then
										Result.Error := errorMessage("Parsing Delimiter3: Keyword 'false' as not allowed CHARACTERs.");
										exit loopi;
									end if;
								end loop;
								IndexWriter														:= IndexWriter + 1;
								if (VERBOSE = TRUE) then report "Found: FALSE - Add new IndexElement(FALSE) at pos " & INTEGER'image(IndexWriter) severity NOTE; end if;
								Result.Index(IndexWriter).Index				:= IndexWriter;
								Result.Index(IndexWriter).ElementType	:= ELEM_FALSE;
								Result.Index(IndexWriter).StringStart	:= 0;
								Result.Index(IndexWriter).StringEnd		:= 0;
								
								if (VERBOSE = TRUE) then report "Linking new key to index " & INTEGER'image(ParserStack(StackPointer).Index) & " as child." severity NOTE; end if;
								Result.Index(ParserStack(StackPointer).Index).ChildIndex	:= IndexWriter;
								
								StackPointer													:= StackPointer + 1;
								ParserStack(StackPointer).State				:= ST_FALSE_END;
								ParserStack(StackPointer).Index				:= IndexWriter;
							when others =>
								Result.Error := errorMessage("Parsing List: Char '" & CurrentChar & "' is not allowed.");
								exit loopi;
						end case;
						
					when ST_KEY =>
						case CurrentChar is
							when '"' =>
								if (VERBOSE = TRUE) then report "Found: KeyEnd - Setting End to " & INTEGER'image(ContentWriter) severity NOTE; end if;
								Result.Index(IndexWriter).StringEnd		:= ContentWriter;
								ParserStack(StackPointer).State				:= ST_KEY_END;
							when others =>
								ContentWriter													:= ContentWriter + 1;
								Result.Content(ContentWriter)					:= CurrentChar;
						end case;
						
					when ST_KEY_END =>
						case CurrentChar is
							when ' ' | HT =>												next loopj;
							when ':' =>
								if (VERBOSE = TRUE) then report "Found: Delimiter1 (':')" severity NOTE; end if;
								ParserStack(StackPointer).State				:= ST_DELIMITER1;
							when others =>
								Result.Error := errorMessage("Parsing KeyEnd: Char '" & CurrentChar & "' is not allowed.");
								exit loopi;
						end case;
					
					-- colon
					when ST_DELIMITER1 =>
						case CurrentChar is
							when ' ' | HT =>												next loopj;
							when '{' =>
								IndexWriter														:= IndexWriter + 1;
								if (VERBOSE = TRUE) then report "Found: Object - Add new IndexElement(OBJ) at pos " & INTEGER'image(IndexWriter) severity NOTE; end if;
								Result.Index(IndexWriter).Index				:= IndexWriter;
								Result.Index(IndexWriter).ElementType	:= ELEM_OBJECT;
								
								if (VERBOSE = TRUE) then report "Linking new key to index " & INTEGER'image(ParserStack(StackPointer).Index) & " as child." severity NOTE; end if;
								Result.Index(ParserStack(StackPointer).Index).ChildIndex	:= IndexWriter;
								
								StackPointer													:= StackPointer + 1;
								ParserStack(StackPointer).State				:= ST_OBJECT;
								ParserStack(StackPointer).Index				:= IndexWriter;
							when '[' =>
								IndexWriter														:= IndexWriter + 1;
								if (VERBOSE = TRUE) then report "Found: List - Add new IndexElement(LIST) at pos " & INTEGER'image(IndexWriter) severity NOTE; end if;
								Result.Index(IndexWriter).Index				:= IndexWriter;
								Result.Index(IndexWriter).ElementType	:= ELEM_LIST;
								
								if (VERBOSE = TRUE) then report "Linking new key to index " & INTEGER'image(ParserStack(StackPointer).Index) & " as child." severity NOTE; end if;
								Result.Index(ParserStack(StackPointer).Index).ChildIndex	:= IndexWriter;
								
								StackPointer													:= StackPointer + 1;
								ParserStack(StackPointer).State				:= ST_LIST;
								ParserStack(StackPointer).Index				:= IndexWriter;
							when '"' =>		-- a single quote to restore the syntax highlighting FSM in Notepad++ "
								IndexWriter														:= IndexWriter + 1;
								if (VERBOSE = TRUE) then report "Found: String - Add new IndexElement(STR) at pos " & INTEGER'image(IndexWriter) & " setting Start to " & INTEGER'image(ContentWriter + 1) severity NOTE; end if;
								Result.Index(IndexWriter).Index				:= IndexWriter;
								Result.Index(IndexWriter).ElementType	:= ELEM_STRING;
								Result.Index(IndexWriter).StringStart	:= ContentWriter + 1;
								
								if (VERBOSE = TRUE) then report "Linking new key to index " & INTEGER'image(ParserStack(StackPointer).Index) & " as child." severity NOTE; end if;
								Result.Index(ParserStack(StackPointer).Index).ChildIndex	:= IndexWriter;
								
								StackPointer													:= StackPointer + 1;
								ParserStack(StackPointer).State				:= ST_STRING;
								ParserStack(StackPointer).Index				:= IndexWriter;
							when '-' | '0' | '1' | '2' | '3' | '4' | '5' | '6' | '7' | '8' | '9' =>
								ContentWriter													:= ContentWriter + 1;
								Result.Content(ContentWriter)					:= CurrentChar;
								
								IndexWriter														:= IndexWriter + 1;
								if (VERBOSE = TRUE) then report "Found: Number - Add new IndexElement(NUM) at pos " & INTEGER'image(IndexWriter) & " setting Start to " & INTEGER'image(ContentWriter) severity NOTE; end if;
								Result.Index(IndexWriter).Index				:= IndexWriter;
								Result.Index(IndexWriter).ElementType	:= ELEM_NUMBER;
								Result.Index(IndexWriter).StringStart	:= ContentWriter;
								
								if (VERBOSE = TRUE) then report "Linking new key to index " & INTEGER'image(ParserStack(StackPointer).Index) & " as child." severity NOTE; end if;
								Result.Index(ParserStack(StackPointer).Index).ChildIndex	:= IndexWriter;
								
								StackPointer													:= StackPointer + 1;
								ParserStack(StackPointer).State				:= ST_NUMBER;
								ParserStack(StackPointer).Index				:= IndexWriter;
							when 'n' | 'N' =>
								for k in 2 to 4 loop
									read(CurrentLine, CurrentChar, IsString);
									if (IsString = FALSE) then
										Result.Error := errorMessage("Parsing List: Keyword 'null' is not complete.");
										exit loopi;
									elsif (CurrentChar /= C_JSON_NULL(k)) then
										Result.Error := errorMessage("Parsing List: Keyword 'null' has a not allowed CHARACTERs.");
										exit loopi;
									end if;
								end loop;
								IndexWriter														:= IndexWriter + 1;
								if (VERBOSE = TRUE) then report "Found: NULL - Add new IndexElement(NULL) at pos " & INTEGER'image(IndexWriter) severity NOTE; end if;
								Result.Index(IndexWriter).Index				:= IndexWriter;
								Result.Index(IndexWriter).ElementType	:= ELEM_NULL;
								Result.Index(IndexWriter).StringStart	:= 0;
								Result.Index(IndexWriter).StringEnd		:= 0;
								
								if (VERBOSE = TRUE) then report "Linking new key to index " & INTEGER'image(ParserStack(StackPointer).Index) & " as child." severity NOTE; end if;
								Result.Index(ParserStack(StackPointer).Index).ChildIndex	:= IndexWriter;
								
								StackPointer													:= StackPointer + 1;
								ParserStack(StackPointer).State				:= ST_NULL_END;
								ParserStack(StackPointer).Index				:= IndexWriter;
							when 't' | 'T' =>
								for k in 2 to 4 loop
									read(CurrentLine, CurrentChar, IsString);
									if (IsString = FALSE) then
										Result.Error := errorMessage("Parsing Delimiter3: Keyword 'true' is not complete.");
										exit loopi;
									elsif (CurrentChar /= C_JSON_TRUE(k)) then
										Result.Error := errorMessage("Parsing Delimiter3: Keyword 'true' as not allowed CHARACTERs.");
										exit loopi;
									end if;
								end loop;
								IndexWriter														:= IndexWriter + 1;
								if (VERBOSE = TRUE) then report "Found: TRUE - Add new IndexElement(TRUE) at pos " & INTEGER'image(IndexWriter) severity NOTE; end if;
								Result.Index(IndexWriter).Index				:= IndexWriter;
								Result.Index(IndexWriter).ElementType	:= ELEM_TRUE;
								Result.Index(IndexWriter).StringStart	:= 0;
								Result.Index(IndexWriter).StringEnd		:= 0;
								
								if (VERBOSE = TRUE) then report "Linking new key to index " & INTEGER'image(ParserStack(StackPointer).Index) & " as child." severity NOTE; end if;
								Result.Index(ParserStack(StackPointer).Index).ChildIndex	:= IndexWriter;
								
								StackPointer													:= StackPointer + 1;
								ParserStack(StackPointer).State				:= ST_TRUE_END;
								ParserStack(StackPointer).Index				:= IndexWriter;
							when 'f' | 'F' =>
								for k in 2 to 5 loop
									read(CurrentLine, CurrentChar, IsString);
									if (IsString = FALSE) then
										Result.Error := errorMessage("Parsing Delimiter3: Keyword 'false' is not complete.");
										exit loopi;
									elsif (CurrentChar /= C_JSON_FALSE(k)) then
										Result.Error := errorMessage("Parsing Delimiter3: Keyword 'false' as not allowed CHARACTERs.");
										exit loopi;
									end if;
								end loop;
								IndexWriter														:= IndexWriter + 1;
								if (VERBOSE = TRUE) then report "Found: FALSE - Add new IndexElement(FALSE) at pos " & INTEGER'image(IndexWriter) severity NOTE; end if;
								Result.Index(IndexWriter).Index				:= IndexWriter;
								Result.Index(IndexWriter).ElementType	:= ELEM_FALSE;
								Result.Index(IndexWriter).StringStart	:= 0;
								Result.Index(IndexWriter).StringEnd		:= 0;
								
								if (VERBOSE = TRUE) then report "Linking new key to index " & INTEGER'image(ParserStack(StackPointer).Index) & " as child." severity NOTE; end if;
								Result.Index(ParserStack(StackPointer).Index).ChildIndex	:= IndexWriter;
								
								StackPointer													:= StackPointer + 1;
								ParserStack(StackPointer).State				:= ST_FALSE_END;
								ParserStack(StackPointer).Index				:= IndexWriter;
							when others =>
								Result.Error := errorMessage("Parsing Delimiter1: Char '" & CurrentChar & "' is not allowed.");
								exit loopi;
						end case;
					
					-- coma in objects
					when ST_DELIMITER2 =>
						case CurrentChar is
							when ' ' | HT =>												next loopj;
							when '"' =>		-- a single quote to restore the syntax highlighting FSM in Notepad++ "
								IndexWriter														:= IndexWriter + 1;
								if (VERBOSE = TRUE) then report "Found: Key - Add new IndexElement(KEY) at pos " & INTEGER'image(IndexWriter) & " setting Start to " & INTEGER'image(ContentWriter + 1) severity NOTE; end if;
								Result.Index(IndexWriter).Index				:= IndexWriter;
								Result.Index(IndexWriter).ElementType	:= ELEM_KEY;
								Result.Index(IndexWriter).StringStart	:= ContentWriter + 1;
								
								if (VERBOSE = TRUE) then report "Linking new key to index " & INTEGER'image(ParserStack(StackPointer - 2).Index) & " as next." severity NOTE; end if;
								Result.Index(ParserStack(StackPointer - 2).Index).NextIndex	:= IndexWriter;
								
								StackPointer													:= StackPointer - 2;
								ParserStack(StackPointer).State				:= ST_KEY;
								ParserStack(StackPointer).Index				:= IndexWriter;
							when others =>
								Result.Error := errorMessage("Parsing Delimiter2: Char '" & CurrentChar & "' is not allowed.");
								exit loopi;
						end case;
						
					-- coma in lists
					when ST_DELIMITER3 =>
						case CurrentChar is
							when ' ' | HT =>												next loopj;
							when '{' =>
								IndexWriter														:= IndexWriter + 1;
								if (VERBOSE = TRUE) then report "Found: Object - Add new IndexElement(OBJ) at pos " & INTEGER'image(IndexWriter) severity NOTE; end if;
								Result.Index(IndexWriter).Index				:= IndexWriter;
								Result.Index(IndexWriter).ElementType	:= ELEM_OBJECT;
								
								if (VERBOSE = TRUE) then report "Linking new key to index " & INTEGER'image(ParserStack(StackPointer - 1).Index) & " as next." severity NOTE; end if;
								Result.Index(ParserStack(StackPointer - 1).Index).NextIndex	:= IndexWriter;
								
								StackPointer													:= StackPointer - 1;
								ParserStack(StackPointer).State				:= ST_OBJECT;
								ParserStack(StackPointer).Index				:= IndexWriter;
							when '[' =>
								IndexWriter														:= IndexWriter + 1;
								if (VERBOSE = TRUE) then report "Found: List - Add new IndexElement(LIST) at pos " & INTEGER'image(IndexWriter) severity NOTE; end if;
								Result.Index(IndexWriter).Index				:= IndexWriter;
								Result.Index(IndexWriter).ElementType	:= ELEM_LIST;
								
								if (VERBOSE = TRUE) then report "Linking new key to index " & INTEGER'image(ParserStack(StackPointer - 1).Index) & " as next." severity NOTE; end if;
								Result.Index(ParserStack(StackPointer - 1).Index).NextIndex	:= IndexWriter;
								
								StackPointer													:= StackPointer - 1;
								ParserStack(StackPointer).State				:= ST_LIST;
								ParserStack(StackPointer).Index				:= IndexWriter;
							when '"' =>
								IndexWriter														:= IndexWriter + 1;
								if (VERBOSE = TRUE) then report "Found: String - Add new IndexElement(STR) at pos " & INTEGER'image(IndexWriter) & " setting Start to " & INTEGER'image(ContentWriter + 1) severity NOTE; end if;
								Result.Index(IndexWriter).Index				:= IndexWriter;
								Result.Index(IndexWriter).ElementType	:= ELEM_STRING;
								Result.Index(IndexWriter).StringStart	:= ContentWriter + 1;
								
								if (VERBOSE = TRUE) then report "Linking new key to index " & INTEGER'image(ParserStack(StackPointer - 1).Index) & " as next." severity NOTE; end if;
								Result.Index(ParserStack(StackPointer - 1).Index).NextIndex	:= IndexWriter;
								
								StackPointer													:= StackPointer - 1;
								ParserStack(StackPointer).State				:= ST_STRING;
								ParserStack(StackPointer).Index				:= IndexWriter;
							when '-' | '0' | '1' | '2' | '3' | '4' | '5' | '6' | '7' | '8' | '9' =>
								ContentWriter													:= ContentWriter + 1;
								Result.Content(ContentWriter)					:= CurrentChar;
								
								IndexWriter														:= IndexWriter + 1;
								if (VERBOSE = TRUE) then report "Found: Number - Add new IndexElement(NUM) at pos " & INTEGER'image(IndexWriter) & " setting Start to " & INTEGER'image(ContentWriter) severity NOTE; end if;
								Result.Index(IndexWriter).Index				:= IndexWriter;
								Result.Index(IndexWriter).ElementType	:= ELEM_NUMBER;
								Result.Index(IndexWriter).StringStart	:= ContentWriter;
								
								if (VERBOSE = TRUE) then report "Linking new key to index " & INTEGER'image(ParserStack(StackPointer - 1).Index) & " as next." severity NOTE; end if;
								Result.Index(ParserStack(StackPointer - 1).Index).NextIndex	:= IndexWriter;
								
								StackPointer													:= StackPointer - 1;
								ParserStack(StackPointer).State				:= ST_NUMBER;
								ParserStack(StackPointer).Index				:= IndexWriter;
							when 'n' | 'N' =>
								for k in 2 to 4 loop
									read(CurrentLine, CurrentChar, IsString);
									if (IsString = FALSE) then
										Result.Error := errorMessage("Parsing List: Keyword 'null' is not complete.");
										exit loopi;
									elsif (CurrentChar /= C_JSON_NULL(k)) then
										Result.Error := errorMessage("Parsing List: Keyword 'null' has a not allowed CHARACTERs.");
										exit loopi;
									end if;
								end loop;
								IndexWriter														:= IndexWriter + 1;
								if (VERBOSE = TRUE) then report "Found: NULL - Add new IndexElement(NULL) at pos " & INTEGER'image(IndexWriter) severity NOTE; end if;
								Result.Index(IndexWriter).Index				:= IndexWriter;
								Result.Index(IndexWriter).ElementType	:= ELEM_NULL;
								Result.Index(IndexWriter).StringStart	:= 0;
								Result.Index(IndexWriter).StringEnd		:= 0;
								
								if (VERBOSE = TRUE) then report "Linking new key to index " & INTEGER'image(ParserStack(StackPointer - 1).Index) & " as next." severity NOTE; end if;
								Result.Index(ParserStack(StackPointer - 1).Index).NextIndex	:= IndexWriter;
								
								StackPointer													:= StackPointer - 1;
								ParserStack(StackPointer).State				:= ST_NULL_END;
								ParserStack(StackPointer).Index				:= IndexWriter;
							when 't' | 'T' =>
								for k in 2 to 4 loop
									read(CurrentLine, CurrentChar, IsString);
									if (IsString = FALSE) then
										Result.Error := errorMessage("Parsing Delimiter3: Keyword 'true' is not complete.");
										exit loopi;
									elsif (CurrentChar /= C_JSON_TRUE(k)) then
										Result.Error := errorMessage("Parsing Delimiter3: Keyword 'true' as not allowed CHARACTERs.");
										exit loopi;
									end if;
								end loop;
								IndexWriter														:= IndexWriter + 1;
								if (VERBOSE = TRUE) then report "Found: TRUE - Add new IndexElement(TRUE) at pos " & INTEGER'image(IndexWriter) severity NOTE; end if;
								Result.Index(IndexWriter).Index				:= IndexWriter;
								Result.Index(IndexWriter).ElementType	:= ELEM_TRUE;
								Result.Index(IndexWriter).StringStart	:= 0;
								Result.Index(IndexWriter).StringEnd		:= 0;
								
								if (VERBOSE = TRUE) then report "Linking new key to index " & INTEGER'image(ParserStack(StackPointer - 1).Index) & " as next." severity NOTE; end if;
								Result.Index(ParserStack(StackPointer - 1).Index).NextIndex	:= IndexWriter;
								
								StackPointer													:= StackPointer - 1;
								ParserStack(StackPointer).State				:= ST_TRUE_END;
								ParserStack(StackPointer).Index				:= IndexWriter;
							when 'f' | 'F' =>
								for k in 2 to 5 loop
									read(CurrentLine, CurrentChar, IsString);
									if (IsString = FALSE) then
										Result.Error := errorMessage("Parsing Delimiter3: Keyword 'false' is not complete.");
										exit loopi;
									elsif (CurrentChar /= C_JSON_FALSE(k)) then
										Result.Error := errorMessage("Parsing Delimiter3: Keyword 'false' as not allowed CHARACTERs.");
										exit loopi;
									end if;
								end loop;
								IndexWriter														:= IndexWriter + 1;
								if (VERBOSE = TRUE) then report "Found: FALSE - Add new IndexElement(FALSE) at pos " & INTEGER'image(IndexWriter) severity NOTE; end if;
								Result.Index(IndexWriter).Index				:= IndexWriter;
								Result.Index(IndexWriter).ElementType	:= ELEM_FALSE;
								Result.Index(IndexWriter).StringStart	:= 0;
								Result.Index(IndexWriter).StringEnd		:= 0;
								
								if (VERBOSE = TRUE) then report "Linking new key to index " & INTEGER'image(ParserStack(StackPointer - 1).Index) & " as next." severity NOTE; end if;
								Result.Index(ParserStack(StackPointer - 1).Index).NextIndex	:= IndexWriter;
								
								StackPointer													:= StackPointer - 1;
								ParserStack(StackPointer).State				:= ST_FALSE_END;
								ParserStack(StackPointer).Index				:= IndexWriter;
							when others =>
								Result.Error := errorMessage("Parsing Delimiter3: Char '" & CurrentChar & "' is not allowed.");
								exit loopi;
						end case;
					
					when ST_STRING =>
						case CurrentChar is
							when '"' =>
								if (VERBOSE = TRUE) then report "Found: StringEnd - Setting End to " & INTEGER'image(ContentWriter) severity NOTE; end if;
								Result.Index(IndexWriter).StringEnd		:= ContentWriter;
								ParserStack(StackPointer).State				:= ST_STRING_END;
							when others =>
								ContentWriter													:= ContentWriter + 1;
								Result.Content(ContentWriter)					:= CurrentChar;
						end case;

					when ST_STRING_END =>
						case CurrentChar is
							when ' ' | HT =>												next loopj;
							-- check if allowed
							when '}' | ']' =>
								if (VERBOSE = TRUE) then report "Found: Closing" severity NOTE; end if;
								if (ParserStack(StackPointer - 1).State = ST_DELIMITER1) then
									StackPointer												:= StackPointer - 2;
									ParserStack(StackPointer).State			:= ST_CLOSED;
								else
									StackPointer												:= StackPointer - 1;
									ParserStack(StackPointer).State			:= ST_CLOSED;
								end if;
							-- check if allowed
							when ',' =>
								if (ParserStack(StackPointer - 1).State = ST_DELIMITER1) then
									if (VERBOSE = TRUE) then report "Found: Delimiter2 (Obj)" severity NOTE; end if;
									StackPointer												:= StackPointer + 1;
									ParserStack(StackPointer).State			:= ST_DELIMITER2;
									ParserStack(StackPointer).Index			:= 0;
								else
									if (VERBOSE = TRUE) then report "Found: Delimiter3 (List)" severity NOTE; end if;
									StackPointer												:= StackPointer + 1;
									ParserStack(StackPointer).State			:= ST_DELIMITER3;
									ParserStack(StackPointer).Index			:= 0;
								end if;
							when others =>
								Result.Error := errorMessage("Parsing StringEnd: Char '" & CurrentChar & "' is not allowed.");
								exit loopi;
						end case;
					
					when ST_NUMBER =>
						case CurrentChar is
							when ' ' | HT =>
								if (VERBOSE = TRUE) then report "Found: WS after number - Setting End to " & INTEGER'image(ContentWriter) severity NOTE; end if;
								Result.Index(IndexWriter).StringEnd		:= ContentWriter;
								ParserStack(StackPointer).State				:= ST_NUMBER_END;
							when '0' | '1' | '2' | '3' | '4' | '5' | '6' | '7' | '8' | '9' =>
								ContentWriter													:= ContentWriter + 1;
								Result.Content(ContentWriter)					:= CurrentChar;
							when '.' =>
								ContentWriter													:= ContentWriter + 1;
								Result.Content(ContentWriter)					:= CurrentChar;
							when '-' =>
								ContentWriter													:= ContentWriter + 1;
								Result.Content(ContentWriter)					:= CurrentChar;
							when 'e' | 'E' =>
								ContentWriter													:= ContentWriter + 1;
								Result.Content(ContentWriter)					:= CurrentChar;
							-- check if allowed
							when '}' | ']' =>
								if (VERBOSE = TRUE) then report "Found: Closing - Setting End to " & INTEGER'image(ContentWriter) severity NOTE; end if;
								Result.Index(IndexWriter).StringEnd		:= ContentWriter;
								if (ParserStack(StackPointer - 1).State = ST_DELIMITER1) then
									StackPointer												:= StackPointer - 2;
									ParserStack(StackPointer).State			:= ST_CLOSED;
								else
									StackPointer												:= StackPointer - 1;
									ParserStack(StackPointer).State			:= ST_CLOSED;
								end if;
							-- check if allowed
							when ',' =>
								Result.Index(IndexWriter).StringEnd		:= ContentWriter;
								if (ParserStack(StackPointer - 1).State = ST_DELIMITER1) then
									if (VERBOSE = TRUE) then report "Found: Delimiter2 (Obj)" severity NOTE; end if;
									StackPointer												:= StackPointer + 1;
									ParserStack(StackPointer).State			:= ST_DELIMITER2;
									ParserStack(StackPointer).Index			:= 0;
								else
									if (VERBOSE = TRUE) then report "Found: Delimiter3 (List)" severity NOTE; end if;
									StackPointer												:= StackPointer + 1;
									ParserStack(StackPointer).State			:= ST_DELIMITER3;
									ParserStack(StackPointer).Index			:= 0;
								end if;
							when others =>
								Result.Error := errorMessage("Parsing Number: Char '" & CurrentChar & "' is not allowed.");
								exit loopi;
						end case;

					when ST_NUMBER_END =>
						case CurrentChar is
							when ' ' | HT =>												next loopj;
							-- check if allowed
							when '}' | ']' =>
								if (VERBOSE = TRUE) then report "Found: Closing" severity NOTE; end if;
								if (ParserStack(StackPointer - 1).State = ST_DELIMITER1) then
									StackPointer												:= StackPointer - 2;
									ParserStack(StackPointer).State			:= ST_CLOSED;
								else
									StackPointer												:= StackPointer - 1;
									ParserStack(StackPointer).State			:= ST_CLOSED;
								end if;
							-- check if allowed
							when ',' =>
								if (ParserStack(StackPointer - 1).State = ST_DELIMITER1) then
									if (VERBOSE = TRUE) then report "Found: Delimiter2 (Obj)" severity NOTE; end if;
									StackPointer												:= StackPointer + 1;
									ParserStack(StackPointer).State			:= ST_DELIMITER2;
									ParserStack(StackPointer).Index			:= 0;
								else
									if (VERBOSE = TRUE) then report "Found: Delimiter3 (List)" severity NOTE; end if;
									StackPointer												:= StackPointer + 1;
									ParserStack(StackPointer).State			:= ST_DELIMITER3;
									ParserStack(StackPointer).Index			:= 0;
								end if;
							when others =>
								Result.Error := errorMessage("Parsing NumberEnd: Char '" & CurrentChar & "' is not allowed.");
								exit loopi;
						end case;
						
					when ST_NULL_END =>
						case CurrentChar is
							when ' ' | HT =>												next loopj;
							-- check if allowed
							when '}' | ']' =>
								if (VERBOSE = TRUE) then report "Found: Closing" severity NOTE; end if;
								if (ParserStack(StackPointer - 1).State = ST_DELIMITER1) then
									StackPointer												:= StackPointer - 2;
									ParserStack(StackPointer).State			:= ST_CLOSED;
								else
									StackPointer												:= StackPointer - 1;
									ParserStack(StackPointer).State			:= ST_CLOSED;
								end if;
							-- check if allowed
							when ',' =>
								if (ParserStack(StackPointer - 1).State = ST_DELIMITER1) then
									if (VERBOSE = TRUE) then report "Found: Delimiter2 (Obj)" severity NOTE; end if;
									StackPointer												:= StackPointer + 1;
									ParserStack(StackPointer).State			:= ST_DELIMITER2;
									ParserStack(StackPointer).Index			:= 0;
								else
									if (VERBOSE = TRUE) then report "Found: Delimiter3 (List)" severity NOTE; end if;
									StackPointer												:= StackPointer + 1;
									ParserStack(StackPointer).State			:= ST_DELIMITER3;
									ParserStack(StackPointer).Index			:= 0;
								end if;
							when others =>
								Result.Error := errorMessage("Parsing NullEnd: Char '" & CurrentChar & "' is not allowed.");
								exit loopi;
						end case;
					
					when ST_TRUE_END =>
						case CurrentChar is
							when ' ' | HT =>												next loopj;
							-- check if allowed
							when '}' | ']' =>
								if (VERBOSE = TRUE) then report "Found: Closing" severity NOTE; end if;
								if (ParserStack(StackPointer - 1).State = ST_DELIMITER1) then
									StackPointer												:= StackPointer - 2;
									ParserStack(StackPointer).State			:= ST_CLOSED;
								else
									StackPointer												:= StackPointer - 1;
									ParserStack(StackPointer).State			:= ST_CLOSED;
								end if;
							-- check if allowed
							when ',' =>
								if (ParserStack(StackPointer - 1).State = ST_DELIMITER1) then
									if (VERBOSE = TRUE) then report "Found: Delimiter2 (Obj)" severity NOTE; end if;
									StackPointer												:= StackPointer + 1;
									ParserStack(StackPointer).State			:= ST_DELIMITER2;
									ParserStack(StackPointer).Index			:= 0;
								else
									if (VERBOSE = TRUE) then report "Found: Delimiter3 (List)" severity NOTE; end if;
									StackPointer												:= StackPointer + 1;
									ParserStack(StackPointer).State			:= ST_DELIMITER3;
									ParserStack(StackPointer).Index			:= 0;
								end if;
							when others =>
								Result.Error := errorMessage("Parsing TrueEnd: Char '" & CurrentChar & "' is not allowed.");
								exit loopi;
						end case;
						
					when ST_FALSE_END =>
						case CurrentChar is
							when ' ' | HT =>												next loopj;
							-- check if allowed
							when '}' | ']' =>
								if (VERBOSE = TRUE) then report "Found: Closing" severity NOTE; end if;
								if (ParserStack(StackPointer - 1).State = ST_DELIMITER1) then
									StackPointer												:= StackPointer - 2;
									ParserStack(StackPointer).State			:= ST_CLOSED;
								else
									StackPointer												:= StackPointer - 1;
									ParserStack(StackPointer).State			:= ST_CLOSED;
								end if;
							-- check if allowed
							when ',' =>
								if (ParserStack(StackPointer - 1).State = ST_DELIMITER1) then
									if (VERBOSE = TRUE) then report "Found: Delimiter2 (Obj)" severity NOTE; end if;
									StackPointer												:= StackPointer + 1;
									ParserStack(StackPointer).State			:= ST_DELIMITER2;
									ParserStack(StackPointer).Index			:= 0;
								else
									if (VERBOSE = TRUE) then report "Found: Delimiter3 (List)" severity NOTE; end if;
									StackPointer												:= StackPointer + 1;
									ParserStack(StackPointer).State			:= ST_DELIMITER3;
									ParserStack(StackPointer).Index			:= 0;
								end if;
							when others =>
								Result.Error := errorMessage("Parsing FalseEnd: Char '" & CurrentChar & "' is not allowed.");
								exit loopi;
						end case;
					
					when ST_CLOSED =>
						case CurrentChar is
							when ' ' | HT =>												next loopj;
							-- check if allowed
							when '}' | ']' =>
								if (VERBOSE = TRUE) then report "Found: Closing" severity NOTE; end if;
								if (ParserStack(StackPointer - 1).State = ST_DELIMITER1) then
									StackPointer												:= StackPointer - 2;
									ParserStack(StackPointer).State			:= ST_CLOSED;
								else
									StackPointer												:= StackPointer - 1;
									ParserStack(StackPointer).State			:= ST_CLOSED;
								end if;
							-- check if allowed
							when ',' =>
								if (ParserStack(StackPointer - 1).State = ST_DELIMITER1) then
									if (VERBOSE = TRUE) then report "Found: Delimiter2 (Obj)" severity NOTE; end if;
									StackPointer												:= StackPointer + 1;
									ParserStack(StackPointer).State			:= ST_DELIMITER2;
									ParserStack(StackPointer).Index			:= 0;
								else
									if (VERBOSE = TRUE) then report "Found: Delimiter3 (List)" severity NOTE; end if;
									StackPointer												:= StackPointer + 1;
									ParserStack(StackPointer).State			:= ST_DELIMITER3;
									ParserStack(StackPointer).Index			:= 0;
								end if;
							when others =>
								Result.Error := errorMessage("Parsing NumberEnd: Char '" & CurrentChar & "' is not allowed.");
								exit loopi;
						end case;
					
				end case;
				
				if (VERBOSE = TRUE) then 
					printParserStack(ParserStack(0 to StackPointer));
					printIndex(Result.Index(0 to IndexWriter), Result.Content(1 to ContentWriter));
				end if;
			end loop;
		end loop;
		-- print complete index after parsing all input characters
		if (VERBOSE = TRUE) then printIndex(Result.Index(0 to IndexWriter), Result.Content(1 to ContentWriter));	end if;
		
		file_close(FileHandle);

		if (Result.Error(1) /= C_JSON_NUL) then
			return Result;
		elsif ((StackPointer /= 1) or (ParserStack(StackPointer).State /= ST_CLOSED)) then
			Result.Error := errorMessage("Reached end of file before end of structure.");
			return Result;
		end if;
				
		return Result;
	end function;

	function jsonParsePath(Path : STRING) return T_JSON_PATH is
		variable Result				: T_JSON_PATH(0 to 31);
		variable ResultWriter	: NATURAL;
	begin
		ResultWriter											:= 0;
		Result(ResultWriter).StringStart	:= 0;
	
		loopi : for i in Path'range loop
			if (Result(ResultWriter).StringStart = 0) then		-- determine element type
				if (chr_isAlpha(Path(i)) = TRUE) then
					Result(ResultWriter).StringStart	:= i;
					Result(ResultWriter).ElementType	:= PATH_ELEM_KEY;
				elsif (chr_isDigit(Path(i)) = TRUE) then
					Result(ResultWriter).StringStart	:= i;
					Result(ResultWriter).ElementType	:= PATH_ELEM_INDEX;
				else
					report "jsonParsePath: Unsupported character '" & Path(i) & "'in path." severity failure;
				end if;
			else
				case Result(ResultWriter).ElementType is
					when PATH_ELEM_KEY =>
						if (chr_isIdentifier(Path(i)) = TRUE) then
							next loopi;
						elsif (Path(i) = '/') then
							Result(ResultWriter).StringEnd		:= i - 1;
							ResultWriter											:= ResultWriter + 1;
							Result(ResultWriter).StringStart	:= 0;
						else
							report "jsonParsePath: Unsupported character '" & Path(i) & "' in identifier." severity failure;
						end if;
						
					when PATH_ELEM_INDEX =>
						if (chr_isDigit(Path(i)) = TRUE) then
							next loopi;
						elsif (Path(i) = '/') then
							Result(ResultWriter).StringEnd		:= i - 1;
							ResultWriter											:= ResultWriter + 1;
							Result(ResultWriter).StringStart	:= 0;
						else
							report "jsonParsePath: Unsupported character '" & Path(i) & "'in index." severity failure;
						end if;
						
				end case;
			end if;
		end loop;
		Result(ResultWriter).StringEnd		:= Path'high;
		
		return Result(0 to ResultWriter);
	end function;

	function jsonGetElementIndex(JSONContext : T_JSON; Path : STRING) return T_UINT16 is
		constant VERBOSE			: BOOLEAN								:= C_JSON_VERBOSE or FALSE;
		constant JSON_PATH		: T_JSON_PATH						:= jsonParsePath(Path);
		variable IndexElement	: T_JSON_INDEX_ELEMENT;
		variable Index				: NATURAL;
	begin
		if (VERBOSE = TRUE) then report "jsonGetElementIndex: Path='" & Path & "'  JSON_PATH elements " & INTEGER'image(JSON_PATH'length) severity NOTE; end if;
		IndexElement				:= JSONContext.Index(0);
		-- resolve objects and lists to their first child
		if (IndexElement.ElementType = ELEM_OBJECT) then
			if (VERBOSE = TRUE) then							report "jsonGetElementIndex: Resolve root element (OBJ) to first child: Index=" & INTEGER'image(IndexElement.ChildIndex)	severity NOTE;							end if;
			if (IndexElement.ChildIndex = 0) then	report "jsonGetElementIndex: Object has no child."																																				severity FAILURE;	return 0;	end if;
			IndexElement						:= JSONContext.Index(IndexElement.ChildIndex);
		elsif (IndexElement.ElementType = ELEM_LIST) then
			if (VERBOSE = TRUE) then							report "jsonGetElementIndex: Resolve root element (LIST) to first child: Index=" & INTEGER'image(IndexElement.ChildIndex)	severity NOTE;							end if;
			if (IndexElement.ChildIndex = 0) then	report "jsonGetElementIndex: List has no child."																																					severity FAILURE; return 0;	end if;
			IndexElement						:= JSONContext.Index(IndexElement.ChildIndex);
		end if;
		
		loopi : for i in JSON_PATH'range loop
			-- -------------------------------
			if (JSON_PATH(i).ElementType = PATH_ELEM_INDEX) then
				Index		:= to_natural_dec(Path(JSON_PATH(i).StringStart to JSON_PATH(i).StringEnd));
				if (Index = 0) then
					-- Go one level down
					if (IndexElement.ChildIndex = 0) then		-- no child
						if (i /= JSON_PATH'high) then					-- this was not the last path element to compare
							report "jsonGetElementIndex: Element has no child, can't process the full path." severity FAILURE;
							return 0;
						end if;
					else		-- IndexElement.ChildIndex
						if (i = JSON_PATH'high) then					-- this was the last path element to compare
							report "jsonGetElementIndex: Result is not a leaf node. Element has a child." severity NOTE;
							return IndexElement.Index;					-- found result
						else
							IndexElement		:= JSONContext.Index(IndexElement.ChildIndex);
						end if;
					end if;	-- IndexElement.ChildIndex
				end if;	-- Index = 0
				for i in 1 to Index loop
					if (IndexElement.NextIndex = 0) then
						report "jsonGetElementIndex: Reached last element in chain." severity FAILURE;
						return 0;
					end if;
					IndexElement		:= JSONContext.Index(IndexElement.NextIndex);
				end loop;
				-- resolve objects and lists to their first child
				if (IndexElement.ElementType = ELEM_OBJECT) then
					if (VERBOSE = TRUE) then							report "jsonGetElementIndex: Resolve element (OBJ) to first child: Index=" & INTEGER'image(IndexElement.ChildIndex)		severity NOTE;							end if;
					if (IndexElement.ChildIndex = 0) then	report "jsonGetElementIndex: Object has no child."																																		severity FAILURE;	return 0;	end if;
					IndexElement						:= JSONContext.Index(IndexElement.ChildIndex);
				elsif (IndexElement.ElementType = ELEM_LIST) then
					if (VERBOSE = TRUE) then							report "jsonGetElementIndex: Resolve element (LIST) to first child: Index=" & INTEGER'image(IndexElement.ChildIndex)	severity NOTE;							end if;
					if (IndexElement.ChildIndex = 0) then	report "jsonGetElementIndex: List has no child."																																			severity FAILURE; return 0;	end if;
					IndexElement						:= JSONContext.Index(IndexElement.ChildIndex);
				end if;
			-- -------------------------------
			elsif (JSON_PATH(i).ElementType = PATH_ELEM_KEY) then
				if (IndexElement.ElementType = ELEM_KEY) then
					loopj : for j in 0 to 127 loop
						if (VERBOSE = TRUE) then report "jsonGetElementIndex: Compare keys - Path='" & Path(JSON_PATH(i).StringStart to JSON_PATH(i).StringEnd) & "'  Key='" & JSONContext.Content(IndexElement.StringStart to IndexElement.StringEnd) & "'" severity NOTE; end if;
						if (str_match(Path(JSON_PATH(i).StringStart to JSON_PATH(i).StringEnd), JSONContext.Content(IndexElement.StringStart to IndexElement.StringEnd)) = TRUE) then
							if (VERBOSE = TRUE) then report "jsonGetElementIndex: -> matched - Get Child: Index=" & INTEGER'image(IndexElement.ChildIndex) severity NOTE; end if;
							-- Go one level down
							if (IndexElement.ChildIndex = 0) then		-- no child
								if (i /= JSON_PATH'high) then					-- this was not the last path element to compare
									report "jsonGetElementIndex: Element has no child, can't process the full path." severity FAILURE;
									return 0;
								end if;
							else		-- IndexElement.ChildIndex
								if (i = JSON_PATH'high) then					-- this was the last path element to compare
--									if ((IndexElement.ElementType = ELEM_OBJECT) or (IndexElement.ElementType = ELEM_LIST) or (IndexElement.ElementType = ELEM_KEY)) then
--										report "jsonGetElementIndex: Result is not a leaf node. Element has a child." severity NOTE;
--									end if;
--									return IndexElement.Index;					-- found result
									IndexElement		:= JSONContext.Index(IndexElement.ChildIndex);
								else
									IndexElement		:= JSONContext.Index(IndexElement.ChildIndex);
								end if;
							end if;	-- IndexElement.ChildIndex
							-- resolve objects and lists to their first child
							if (IndexElement.ElementType = ELEM_OBJECT) then
								if (VERBOSE = TRUE) then							report "jsonGetElementIndex: Resolve element (OBJ) to first child: Index=" & INTEGER'image(IndexElement.ChildIndex)		severity NOTE;							end if;
								if (IndexElement.ChildIndex = 0) then	report "jsonGetElementIndex: Object has no child."																																		severity FAILURE;	return 0;	end if;
								IndexElement			:= JSONContext.Index(IndexElement.ChildIndex);
							elsif (IndexElement.ElementType = ELEM_LIST) then
								if (VERBOSE = TRUE) then							report "jsonGetElementIndex: Resolve element (LIST) to first child: Index=" & INTEGER'image(IndexElement.ChildIndex)	severity NOTE;							end if;
								if (IndexElement.ChildIndex = 0) then	report "jsonGetElementIndex: List has no child."																																			severity FAILURE; return 0;	end if;
								IndexElement			:= JSONContext.Index(IndexElement.ChildIndex);
							end if;
							next loopi;
						else		-- str_match
							if (VERBOSE = TRUE) then report "jsonGetElementIndex: -> no match - Get Next: Index=" & INTEGER'image(IndexElement.NextIndex) severity NOTE; end if;
							if (IndexElement.NextIndex = 0) then
								report "jsonGetElementIndex: No more keys to compare." severity FAILURE;
								return 0;
							else		-- IndexElement.NextIndex
								IndexElement				:= JSONContext.Index(IndexElement.NextIndex);
								next loopj;
							end if;	-- IndexElement.NextIndex
						end if;	-- str_match
					end loop;	-- loopj
				else		-- IndexElement.ElementType /= ELEM_KEY
					report "jsonGetElementIndex: IndexElement is not a key." severity FAILURE;
					return 0;
				end if;	-- IndexElement.ElementType
			end if;
		end loop;
		
		return IndexElement.Index;
	end function;

	function jsonGetString(JSONContext : T_JSON; Path : STRING) return STRING is
		constant ElementIndex	: T_UINT16							:= jsonGetElementIndex(JSONContext, Path);
		constant Element			: T_JSON_INDEX_ELEMENT	:= JSONContext.Index(ElementIndex);
	begin
--		report "jsonGetString: ElementIndex=" & INTEGER'image(ElementIndex) & "  Type=" & T_ELEMENT_TYPE'image(Element.ElementType) severity NOTE;
		if (ElementIndex /= 0) then
			case Element.ElementType is
				when ELEM_NULL =>									return "NULL";
				when ELEM_TRUE =>									return "TRUE";
				when ELEM_FALSE =>								return "FALSE";
				when ELEM_STRING | ELEM_NUMBER => return JSONContext.Content(Element.StringStart to Element.StringEnd);
				when others =>										null;
			end case;
		end if;
		return "ERROR";
	end function;
	
	function jsonGetBoolean(JSONContext : T_JSON; Path : STRING) return BOOLEAN is
		constant ElementIndex	: T_UINT16							:= jsonGetElementIndex(JSONContext, Path);
	begin
		if (ElementIndex = 0) then
			return FALSE;
		end if;
		return (JSONContext.Index(ElementIndex).ElementType = ELEM_TRUE);
	end function;
end package body;