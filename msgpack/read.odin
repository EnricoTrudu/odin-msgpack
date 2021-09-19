package msgpack

import "core:fmt"
import "core:strings"
import "core:runtime"
import "core:unicode/utf8"

Read_Context :: struct {
	start: []byte,
	input: []byte,
	current_format: Format,
	typeids: [dynamic]typeid,
	decoding: Unmarshall_Decoding,
}

Unmarshall_Decoding :: enum {
	Loose, // default
	Strict, // disallows different types when decoding arrays / maps
}

Read_Error :: enum {
	None,

	Bounds_Buffer_Byte,
	Bounds_Buffer_Byte_Ptr,
	Bounds_Buffer_Advance,
	Bounds_Buffer_Slice,

	Wrong_Array_Format,
	Wrong_Map_Format,

	Type_Id_Not_Supported,
	Wrong_Current_Format,

	// not a bad error...
	Unmarshall_Pointer, // not supported
}

read_context_init :: proc(input: []byte) -> Read_Context {
	return {
		start = input,
		input = input, 
	}
}

read_context_destroy :: proc(using ctx: ^Read_Context) {
	delete(typeids)
}

read_context_add_typeid :: proc(using ctx: ^Read_Context, type: typeid) {
	append(&typeids, type)
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

// return byte at input index, error when out of bounds
read_byte :: proc(using ctx: ^Read_Context, index := 0) -> (res: byte, err: Read_Error) {
	if len(input) > index {
		return input[index], .None
	}

	return 0, .Bounds_Buffer_Byte
}

// advance input slice by input size, error when out of bounds
read_advance :: proc(using ctx: ^Read_Context, size := 1) -> (err: Read_Error) {
	if len(input) >= size {
		input = input[size:]
		return
	}

	return .Bounds_Buffer_Advance
}

// return slice from input slice `from` and `to`, error when out of bounds
read_slice :: proc(using ctx: ^Read_Context, from, to: int) -> (res: []byte, err: Read_Error) {
	if from >= 0 && to > from && len(input) >= to {
		res = input[from:to]
		return
	}

	return nil, .Bounds_Buffer_Slice
}

// read current byte, set and clamp current format
read_format :: proc(using ctx: ^Read_Context) -> (err: Read_Error) {
	b := read_byte(ctx) or_return
	ctx.current_format = format_clamp(b)
	return
}

// return bound checked byte ptr, additional size check for how far you're going to cast 
read_byte_ptr :: proc(using ctx: ^Read_Context, index := 1, size := 1) -> (res: ^byte, err: Read_Error) {
	if len(input) > index && len(input) >= index + size {
		return &input[index], .None
	}

	return nil, .Bounds_Buffer_Byte_Ptr
}

read_bool	:: proc(using ctx: ^Read_Context) -> (res: bool, err: Read_Error) {
	b := read_byte(ctx) or_return
	read_advance(ctx) or_return
	return b == byte(Format.True), .None
}

read_uint8 :: proc(using ctx: ^Read_Context) -> (res: u8, err: Read_Error) {
	res = read_byte(ctx, 1) or_return
	read_advance(ctx, 2) or_return
	return
}

read_uint16 :: proc(using ctx: ^Read_Context) -> (res: u16be, err: Read_Error) {
	ptr := read_byte_ptr(ctx, 1, 2) or_return
	res = (cast(^u16be) ptr)^
	read_advance(ctx, 3) or_return
	return
}

read_uint32 :: proc(using ctx: ^Read_Context) -> (res: u32be, err: Read_Error) {
	ptr := read_byte_ptr(ctx, 1, 4) or_return
	res = (cast(^u32be) ptr)^
	read_advance(ctx, 5) or_return
	return
}

read_uint64 :: proc(using ctx: ^Read_Context) -> (res: u64be, err: Read_Error) {
	ptr := read_byte_ptr(ctx, 1, 8) or_return
	res = (cast(^u64be) ptr)^
	read_advance(ctx, 9) or_return
	return
}

// read to odin type, input format .Uint8, .Uint16, .Uint32, .Uint64
read_uint :: proc(using ctx: ^Read_Context) -> (res: uint, err: Read_Error) {
	#partial switch current_format {
		case .Uint8: {
			value := read_uint8(ctx) or_return
			return uint(value), .None
		}
		case .Uint16: {
			value := read_uint16(ctx) or_return
			return uint(value), .None
		}
		case .Uint32: {
			value := read_uint32(ctx) or_return
			return uint(value), .None
		}
		case .Uint64: {
			value := read_uint64(ctx) or_return
			return uint(value), .None
		}
	}	

	return 0, .Wrong_Current_Format
}

// NOTE should be return i8 or u8 in fix_int?

read_positive_fix_int :: proc(using ctx: ^Read_Context) -> (res: i8, err: Read_Error) {
	b := read_byte(ctx) or_return
	res = i8(b)
	read_advance(ctx) or_return
	return
}

read_negative_fix_int :: proc(using ctx: ^Read_Context) -> (res: i8, err: Read_Error) {
	b := read_byte(ctx) or_return
	// subtract header from value
	b &= ~(cast(byte) Format.Negative_Fix_Int)
	res = i8(b)
	read_advance(ctx) or_return
	return
}

read_int8 :: proc(using ctx: ^Read_Context) -> (res: i8, err: Read_Error) {
	b := read_byte(ctx, 1) or_return
	res = i8(b)
	read_advance(ctx, 2) or_return
	return
}

read_int16 :: proc(using ctx: ^Read_Context) -> (res: i16be, err: Read_Error) {
	ptr := read_byte_ptr(ctx, 1, 2) or_return
	res = (cast(^i16be) ptr)^
	read_advance(ctx, 3) or_return
	return
}

read_int32 :: proc(using ctx: ^Read_Context) -> (res: i32be, err: Read_Error) {
	ptr := read_byte_ptr(ctx, 1, 4) or_return
	res = (cast(^i32be) ptr)^
	read_advance(ctx, 5) or_return
	return
}

read_int64 :: proc(using ctx: ^Read_Context) -> (res: i64be, err: Read_Error) {
	ptr := read_byte_ptr(ctx, 1, 8) or_return
	res = (cast(^i64be) ptr)^
	read_advance(ctx, 9) or_return
	return
}

// read to odin type, input format .*_Fix_Int, .Int8, .Int16, .Int32, .Int64
read_int :: proc(using ctx: ^Read_Context) -> (res: int, err: Read_Error) {
	#partial switch current_format {
		case .Positive_Fix_Int: {
			value := read_positive_fix_int(ctx) or_return
			return int(value), .None
		}
		case .Negative_Fix_Int: {
			value := read_negative_fix_int(ctx) or_return
			return int(value), .None
		}
		case .Int8: {
			value := read_int8(ctx) or_return
			return int(value), .None
		}
		case .Int16: {
			value := read_int16(ctx) or_return
			return int(value), .None
		}
		case .Int32: {
			value := read_int32(ctx) or_return
			return int(value), .None
		}
		case .Int64: {
			value := read_int64(ctx) or_return
			return int(value), .None
		}
	}	

	return 0, .Wrong_Current_Format
}

read_float32 :: proc(using ctx: ^Read_Context) -> (res: f32, err: Read_Error) {
	ptr := read_byte_ptr(ctx, 1, 4) or_return
	res = (cast(^f32) ptr)^
	read_advance(ctx, 5) or_return
	return
}

read_float64 :: proc(using ctx: ^Read_Context) -> (res: f64, err: Read_Error) {
	ptr := read_byte_ptr(ctx, 1, 8) or_return
	res = (cast(^f64) ptr)^
	read_advance(ctx, 9) or_return
	return
}

// NOTE temp string, memory belongs to bytes
read_fix_str :: proc(using ctx: ^Read_Context) -> (res: string, err: Read_Error) {
	b := read_byte(ctx) or_return
	b &= ~(byte(Format.Fix_Str))
	length := int(b)
	
	ptr := read_byte_ptr(ctx, 1, length) or_return
	res = strings.string_from_ptr(ptr, length)
	read_advance(ctx, 1 + length) or_return
	
	return	
}

// same as read_fix_str, return rune instead
read_rune :: proc(using ctx: ^Read_Context) -> (res: rune, err: Read_Error) {
	b := read_byte(ctx) or_return
	b &= ~(byte(Format.Fix_Str))
	length := int(b)
	
	bytes := read_slice(ctx, 1, 1 + length) or_return
	res, _ = utf8.decode_rune(bytes[:])
	read_advance(ctx, 1 + length) or_return
	
	return	
}

// NOTE temp string, memory belongs to bytes
read_str8 :: proc(using ctx: ^Read_Context) -> (res: string, err: Read_Error) {
	b := read_byte(ctx, 1) or_return
	length := int(b)

	ptr := read_byte_ptr(ctx, 2, length) or_return
	res = strings.string_from_ptr(ptr, length)
	read_advance(ctx, length + 2) or_return
	
	return
}

// NOTE temp string, memory belongs to bytes
read_str16 :: proc(using ctx: ^Read_Context) -> (res: string, err: Read_Error) {
	length_ptr := read_byte_ptr(ctx, 1, 2) or_return
	length := int((cast(^u16be) length_ptr)^)

	ptr := read_byte_ptr(ctx, 3, length) or_return
	res = strings.string_from_ptr(ptr, length)
	read_advance(ctx, length + 3) or_return
	
	return
}

// NOTE temp string, memory belongs to bytes
read_str32 :: proc(using ctx: ^Read_Context) -> (res: string, err: Read_Error) {
	length_ptr := read_byte_ptr(ctx, 1, 4) or_return
	length := int((cast(^u32be) length_ptr)^)

	ptr := read_byte_ptr(ctx, 5, length) or_return
	res = strings.string_from_ptr(ptr, length)
	read_advance(ctx, length + 5) or_return
	
	return
}

// helper
read_string :: proc(using ctx: ^Read_Context) -> (res: string, err: Read_Error) {
	#partial switch current_format {
		case .Fix_Str: res = read_fix_str(ctx) or_return
		case .Str8: res = read_str8(ctx) or_return
		case .Str16: res = read_str16(ctx) or_return
		case .Str32: res = read_str32(ctx) or_return
		case: return "", .Wrong_Current_Format
	}

	return
}

// NOTE temp slice
read_bin :: proc(using ctx: ^Read_Context) -> (res: []byte, err: Read_Error) {
	length: int
	
	#partial switch ctx.current_format {
		case .Bin8: {
			ptr := read_byte_ptr(ctx, 1, 1) or_return
			length = int((cast(^u8) ptr)^)
			read_advance(ctx, 2) or_return
		}

		case .Bin16: {
			ptr := read_byte_ptr(ctx, 1, 2) or_return
			length = int((cast(^u16be) ptr)^)
			read_advance(ctx, 3) or_return
		}

		case .Bin32: {
			ptr := read_byte_ptr(ctx, 1, 4) or_return
			length = int((cast(^u32be) ptr)^)
			read_advance(ctx, 5) or_return
		}
	}

	res = read_slice(ctx, 0, length) or_return
	read_advance(ctx, length) or_return
	return
}

// array length per format type
read_array :: proc(using ctx: ^Read_Context) -> (length: int, err: Read_Error) {
	#partial switch current_format {
		case .Fix_Array: {
			b := read_byte(ctx) or_return
			b &= ~(byte(Format.Fix_Array))
			length = int(b)
			read_advance(ctx) or_return
			return
		}

		case .Array16: {
			ptr := read_byte_ptr(ctx, 1, 2) or_return
			length = int((cast(^u16be) ptr)^)
			read_advance(ctx, 3) or_return
			return
		}

		case .Array32: {
			ptr := read_byte_ptr(ctx, 1, 4) or_return
			length = int((cast(^u32be) ptr)^)
			read_advance(ctx, 5) or_return
			return
		}
	}

	return 0, .Wrong_Array_Format
}

// map length per format type 
// NOTE length is key + value, i.e. N * 2
read_map :: proc(using ctx: ^Read_Context) -> (length: int, err: Read_Error) {
	#partial switch current_format {
		case .Fix_Map: {
			b := read_byte(ctx) or_return
			b &= ~(byte(Format.Fix_Map))
			length = int(b)
			read_advance(ctx) or_return
			return
		}

		case .Map16: {
			ptr := read_byte_ptr(ctx, 1, 2) or_return
			length = int((cast(^u16be) ptr)^)
			read_advance(ctx, 3) or_return
			return
		}

		case .Map32: {
			ptr := read_byte_ptr(ctx, 1, 4) or_return
			length = int((cast(^u32be) ptr)^)
			read_advance(ctx, 5) or_return
			return
		}
	}

	return 0, .Wrong_Map_Format
}

// NOTE temp byte slice 
read_fix_ext :: proc(using ctx: ^Read_Context) -> (type: i8, data: []byte, err: Read_Error) {
	b := read_byte(ctx, 1) or_return
	type = i8(b)

	// NOTE has to be valid current format
	size := _fix_ext_size(current_format)
	data = read_slice(ctx, 2, 2 + size) or_return
	read_advance(ctx, 2 + size) or_return
	return
}

// NOTE temp byte slice
read_ext :: proc(using ctx: ^Read_Context) -> (type: i8, data: []byte, err: Read_Error) {
	length: int
	
	#partial switch current_format {
		case .Ext8: {
			ptr := read_byte_ptr(ctx, 1, 1) or_return
			length = int((cast(^u8) ptr)^)
			read_advance(ctx, 2) or_return
			input = input[2:]
		}
		
		case .Ext16: {
			ptr := read_byte_ptr(ctx, 1, 2) or_return
			length = int((cast(^u16be) ptr)^)
			read_advance(ctx, 3) or_return
		}
		
		case .Ext32: {
			ptr := read_byte_ptr(ctx, 1, 4) or_return
			length = int((cast(^u32be) ptr)^)
			read_advance(ctx, 5) or_return
		}

		case: panic("WRONG FORMAT")
	}

	b := read_byte(ctx) or_return
	type = i8(b)
	data = read_slice(ctx, 1, 1 + length) or_return
	read_advance(ctx, 1 + length) or_return
	return
}

// custom odin extensions

// NOTE does not advance read
// output from read_fix_ext
read_typeid :: proc(using ctx: ^Read_Context, type: i8, bytes: []byte) -> (res: typeid, err: Read_Error) {
	assert(len(typeids) != 0 && type == i8(Extension.Type_Id))
	value := (cast(^u8) &bytes[0])^

	if int(value) < len(typeids) {
		res = typeids[value]
		return
	}

	return nil, .Type_Id_Not_Supported
}