package msgpack

import "core:fmt"
import "core:strings"
import "core:runtime"

Read_Context :: struct {
	start: []byte,
	input: []byte,
	current_format: Format,
}

read_context_init :: proc(input: []byte) -> Read_Context {
	return {
		start = input,
		input = input, 
	}
}

// clamps input to Format ranges
// i.e. .Positive_Fix_Int from 0x00 - 0x80, to 0x00 only, to allow switching better
format_clamp :: proc(supposed_format: byte) -> Format {
	switch supposed_format {
		case byte(Format.Positive_Fix_Int)..<byte(Format.Fix_Map): {
			return .Positive_Fix_Int
		}
		
		case byte(Format.Negative_Fix_Int)..0xff: {
			return .Negative_Fix_Int
		}

		case byte(Format.Fix_Str)..<byte(Format.Nil): {
			return .Fix_Str
		}

		case byte(Format.Fix_Map)..<byte(Format.Fix_Array): {
			return .Fix_Map
		}

		case byte(Format.Fix_Array)..<byte(Format.Fix_Str): {
			return .Fix_Array
		}
	}

	return Format(supposed_format)
}

read_bool	:: proc(using ctx: ^Read_Context) -> bool {
	value := input[0] == byte(Format.True)
	input = input[1:]
	return value
}

read_uint8 :: proc(using ctx: ^Read_Context) -> u8 {
	value := input[1]
	input = input[2:]
	return value
}

read_uint16 :: proc(using ctx: ^Read_Context) -> u16be {
	value := (cast(^u16be) &input[1])^
	input = input[3:]
	return value
}

read_uint32 :: proc(using ctx: ^Read_Context) -> u32be {
	value := (cast(^u32be) &input[1])^
	input = input[5:]
	return value
}

read_uint64 :: proc(using ctx: ^Read_Context) -> u64be {
	value := (cast(^u64be) &input[1])^
	input = input[9:]
	return value
}

// read to odin type, input format .Uint8, .Uint16, .Uint32, .Uint64
read_uint :: proc(using ctx: ^Read_Context) -> uint {
	#partial switch current_format {
		case .Uint8: return cast(uint) read_uint8(ctx)
		case .Uint16: return cast(uint) read_uint16(ctx)
		case .Uint32: return cast(uint) read_uint32(ctx)
		case .Uint64: return cast(uint) read_uint64(ctx)
	}	

	panic("READ_INT WRONG FORMAT")
}

// NOTE should be return i8 or u8 in fix_int?

read_positive_fix_int :: proc(using ctx: ^Read_Context) -> i8 {
	value := cast(i8) input[0]
	input = input[1:]
	return value
}

read_negative_fix_int :: proc(using ctx: ^Read_Context) -> i8 {
	value := input[0]
	// subtract header from value
	value &= ~(cast(byte) Format.Negative_Fix_Int)
	input = input[1:]
	return cast(i8) value
}

read_int8 :: proc(using ctx: ^Read_Context) -> i8 {
	value := cast(i8) input[1]
	input = input[2:]
	return value
}

read_int16 :: proc(using ctx: ^Read_Context) -> i16be {
	value := (cast(^i16be) &input[1])^
	input = input[3:]
	return value
}

read_int32 :: proc(using ctx: ^Read_Context) -> i32be {
	value := (cast(^i32be) &input[1])^
	input = input[5:]
	return value
}

read_int64 :: proc(using ctx: ^Read_Context) -> i64be {
	value := (cast(^i64be) &input[1])^
	input = input[9:]
	return value
}

// read to odin type, input format .*_Fix_Int, .Int8, .Int16, .Int32, .Int64
read_int :: proc(using ctx: ^Read_Context) -> int {
	#partial switch current_format {
		case .Positive_Fix_Int: return cast(int) read_positive_fix_int(ctx)
		case .Negative_Fix_Int: return cast(int) read_negative_fix_int(ctx)
		case .Int8: return cast(int) read_int8(ctx)
		case .Int16: return cast(int) read_int16(ctx)
		case .Int32: return cast(int) read_int32(ctx)
		case .Int64: return cast(int) read_int64(ctx)
	}	

	panic("READ_INT WRONG FORMAT")
}

read_float32 :: proc(using ctx: ^Read_Context) -> f32 {
	value := (cast(^f32) &input[1])^
	input = input[5:]
	return value
}

read_float64 :: proc(using ctx: ^Read_Context) -> f64 {
	value := (cast(^f64) &input[1])^
	input = input[5:]
	return value
}

// NOTE temp string, memory belongs to bytes
read_fix_str :: proc(using ctx: ^Read_Context) -> string {
	length := input[0]
	length &= ~(byte(Format.Fix_Str))
	text := strings.string_from_ptr(&input[1], int(length))
	input = input[int(length) + 1:]
	return text	
}

// NOTE temp string, memory belongs to bytes
read_str8 :: proc(using ctx: ^Read_Context) -> string {
	length := int(input[1])
	text := strings.string_from_ptr(&input[2], length)
	input = input[length + 2:]
	return text
}

// NOTE temp string, memory belongs to bytes
read_str16 :: proc(using ctx: ^Read_Context) -> string {
	length := int((cast(^u16be) &input[1])^)
	text := strings.string_from_ptr(&input[3], length)
	input = input[length + 3:]
	return text
}

// NOTE temp string, memory belongs to bytes
read_str32 :: proc(using ctx: ^Read_Context) -> string {
	length := int((cast(^u32be) &input[1])^)
	text := strings.string_from_ptr(&input[5], length)
	input = input[length + 5:]
	return text
}

// helper
read_string :: proc(using ctx: ^Read_Context) -> string {
	#partial switch current_format {
		case .Fix_Str: return read_fix_str(ctx)
		case .Str8: return read_str8(ctx)
		case .Str16: return read_str16(ctx)
		case .Str32: return read_str32(ctx)
	}

	panic("READ STRING WRONG FORMAT")
}

// NOTE temp slice
read_bin :: proc(using ctx: ^Read_Context) -> []byte {
	length: int
	#partial switch ctx.current_format {
		case .Bin8: {
			length = int((cast(^u8) &input[1])^)
			input = input[2:]
		}

		case .Bin16: {
			length = int((cast(^u16be) &input[1])^)
			input = input[3:]
		}

		case .Bin32: {
			length = int((cast(^u32be) &input[1])^)
			input = input[5:]
		}
	}

	data := input[:length]
	input = input[length:]
	return data
}

// NOTE temp byte slice 
read_fix_ext :: proc(using ctx: ^Read_Context) -> (type: i8, data: []byte) {
	type = (cast(^i8) &input[1])^
	size := _fix_ext_size(current_format)
	data = input[2:2 + size]
	input = input[2 + size:]
	return
}

// NOTE temp byte slice
read_ext :: proc(using ctx: ^Read_Context) -> (type: i8, data: []byte) {
	length: int
	#partial switch current_format {
		case .Ext8: {
			length = int((cast(^u8) &input[1])^)
			input = input[2:]
		}
		
		case .Ext16: {
			length = int((cast(^u16be) &input[1])^)
			input = input[3:]
		}
		
		case .Ext32: {
			length = int((cast(^u32be) &input[1])^)
			input = input[5:]
		}

		case: panic("WRONG FORMAT")
	}

	type = (cast(^i8) &input[0])^
	data = input[1:1 + length]
	input = input[1 + length:]
	return
}

// array length per format type
read_array :: proc(using ctx: ^Read_Context) -> (length: int) {
	#partial switch current_format {
		case .Fix_Array: {
			value := input[0]
			value &= ~(byte(Format.Fix_Array))
			input = input[1:]
			return int(value)
		}

		case .Array16: {
			length = int((cast(^u16be) &input[1])^)
			input = input[3:]
			return
		}

		case .Array32: {
			length = int((cast(^u32be) &input[1])^)
			input = input[5:]
			return
		}
	}

	panic("READ ARRAY WRONG FORMAT")
}

// map length per format type 
// NOTE length is key + value, i.e. N * 2
read_map :: proc(using ctx: ^Read_Context) -> (length: int) {
	#partial switch current_format {
		case .Fix_Map: {
			value := input[0]
			value &= ~(byte(Format.Fix_Map))
			input = input[1:]
			return int(value)
		}

		case .Map16: {
			length = int((cast(^u16be) &input[1])^)
			input = input[3:]
			return
		}

		case .Map32: {
			length = int((cast(^u32be) &input[1])^)
			input = input[5:]
			return
		}
	}

	panic("READ MAP WRONG FORMAT")
}
