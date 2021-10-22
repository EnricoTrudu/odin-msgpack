package msgpack

import "core:fmt"
import "core:mem"
import "core:unicode/utf8"
import "core:runtime"
import "core:reflect"

// custom proc which is triggered by a typeid you want to encode in your own way
// i.e. write a fixed_ext automatically to reduce size
Write_Custom_Proc :: proc(ctx: ^Write_Context, value: any) -> Write_Error

Write_Context :: struct {
	start: []byte,
	output: []byte,
	verbose: bool, // print info from marshal
	
	typeid_map: map[typeid]u8,
	typeid_any: map[typeid]Write_Custom_Proc,
}

// errors that can appear while reading
Write_Error :: enum {
	None,
	
	Overflow_Buffer,    // not enough memory provided for context
	Overflow_String,    // spec: non supported string     length  
	Overflow_Binary,    // spec: non supported binary     length
	Overflow_Array,	    // spec: non supported array      length
	Overflow_Map,       // spec: non supported array      length
	Overflow_Extension, // spec: non supported extensions length

	Type_Id_Unsupported,

	Pointer_Unsupported,
	Any_Type_Unsupported,
	Any_Type_Not_Array,
	Any_Type_Not_Matched,
}

// byte result from all the writes
write_context_result :: proc(using ctx: Write_Context) -> []byte {
	return start[:len(start) - len(output)]
}

// scoped helper
@(deferred_in=write_context_init)
write_context_scoped :: proc(cap: int) -> Write_Context {
	return write_context_init(cap)
}

// NOTE doesnt automatically resize, throws overflow errors when out of space
// init with a max capacity
write_context_init :: proc(cap: int) -> (result: Write_Context) {
	result.start = make([]byte, cap)
	result.output = result.start
	return
}

// remove dynamic memory
write_context_destroy :: proc(using ctx: Write_Context) {
	delete(start)
	delete(typeid_map)
	delete(typeid_any)
}

// add typeid extension support
write_context_add_typeid :: proc(using ctx: ^Write_Context, type: typeid) {
	typeid_map[type] = u8(len(typeid_map))
}

// add multiple typeids 
write_context_add_typeids :: proc(using ctx: ^Write_Context, types: []typeid) {
	assert(len(typeid_map) < 256)
	
	for type in types {
		typeid_map[type] = u8(len(typeid_map))
	}
}

// add custom typeid conversion to msgpack data
write_context_add_typeid_any :: proc(
	using ctx: ^Write_Context, 
	type: typeid, 
	call: Write_Custom_Proc,
) {
	if type not_in typeid_any {
		typeid_any[type] = call
	} 
}

// write a single byte into output
write_byte :: proc(using ctx: ^Write_Context, value: u8) -> Write_Error {
	if 1 > len(output) {
		return .Overflow_Buffer
	}

	output[0] = value
	output = output[1:]
	return .None
}

// write multiple bytes via adress + size into output, avoid generic ^$T
write_bytes :: proc(using ctx: ^Write_Context, ptr: rawptr, size: int) -> Write_Error {
	if size > len(output) {
		return .Overflow_Buffer
	}

	mem.copy(&output[0], ptr, size)
	output = output[size:]
	return .None
}

// helper conversion + implicit enum
write_format :: #force_inline proc(using ctx: ^Write_Context, format: Format) -> Write_Error {
	return write_byte(ctx, transmute(byte) format)	
}

// write .True or .False next
write_bool :: #force_inline proc(using ctx: ^Write_Context, state: bool) -> Write_Error {
	return write_format(ctx, state ? .True : .False)
}

// write .Nil next
write_nil :: #force_inline proc(using ctx: ^Write_Context) -> Write_Error {
	return write_format(ctx, .Nil)
}

// write .Positive_Fix_Int next with value inside Format
write_positive_fix_int :: proc(using ctx: ^Write_Context, value: u8) -> Write_Error {
	value := value
	value &= ~(value << 8)
	return write_byte(ctx, value)
}

// write .Negative_Fix_Int next with value inside Format
write_negative_fix_int :: proc(using ctx: ^Write_Context, value: u8) -> Write_Error {
	value := value
	value |= byte(Format.Negative_Fix_Int)
	return write_byte(ctx, value)
}

// write .Uint8 next + value content
write_uint8 :: proc(using ctx: ^Write_Context, value: u8) -> Write_Error {
	write_format(ctx, .Uint8) or_return
	return write_byte(ctx, value) 
}

// write .Uint16 next + value content
write_uint16 :: proc(using ctx: ^Write_Context, value: u16be) -> Write_Error {
	write_format(ctx, .Uint16) or_return
	value := value
	return write_bytes(ctx, &value, 2)
}

// write .Uint32 next + value content
write_uint32 :: proc(using ctx: ^Write_Context, value: u32be) -> Write_Error {
	write_format(ctx, .Uint32) or_return
	value := value
	return write_bytes(ctx, &value, 4)
}

// write .Uint64 next + value content
write_uint64 :: proc(using ctx: ^Write_Context, value: u64be) -> Write_Error {
	write_format(ctx, .Uint64) or_return
	value := value
	return write_bytes(ctx, &value, 8)
}

write_uint :: proc {
	write_uint8,
	write_uint16,
	write_uint32,
	write_uint64,
}

// write .Int8 next + value content
write_int8 :: proc(using ctx: ^Write_Context, value: i8) -> Write_Error {
	write_format(ctx, .Int8) or_return
	value := value
	return write_bytes(ctx, &value, 1)
}

// write .Int16 next + value content
write_int16 :: proc(using ctx: ^Write_Context, value: i16be) -> Write_Error {
	write_format(ctx, .Int16) or_return
	value := value
	return write_bytes(ctx, &value, 2)
}

// write .Int32 next + value content
write_int32 :: proc(using ctx: ^Write_Context, value: i32be) -> Write_Error {
	write_format(ctx, .Int32) or_return
	value := value
	return write_bytes(ctx, &value, 4)
}

// write .Int64 next + value content
write_int64 :: proc(using ctx: ^Write_Context, value: i64be) -> Write_Error {
	write_format(ctx, .Int64) or_return
	value := value
	return write_bytes(ctx, &value, 8)
}

write_int :: proc {
	write_int8,
	write_int16,
	write_int32,
	write_int64,
}

// write .Float32 + value content
write_float32 :: proc(using ctx: ^Write_Context, value: f32) -> Write_Error {
	write_format(ctx, .Float32) or_return
	value := value
	return write_bytes(ctx, &value, 4)
}

// write .Float64 + value content
write_float64 :: proc(using ctx: ^Write_Context, value: f64) -> Write_Error {
	write_format(ctx, .Float64) or_return
	value := value
	return write_bytes(ctx, &value, 8)
}

write_float :: proc {
	write_float32,
	write_float64,
}

// TODO inspect strings len(str) usage - use utf8.rune_count instead

// write .Fix_Str with string length included first 5 bits + string content clamped 
write_fix_str :: proc(using ctx: ^Write_Context, text: string) -> Write_Error {
	clamped_length := clamp(len(text), 0, 31)
	value := u8(clamped_length)
	value |= byte(Format.Fix_Str)
	write_byte(ctx, value) or_return

	data := mem.raw_string_data(text)
	return write_bytes(ctx, data, clamped_length)
}

// helper for odin runes
write_rune :: proc(using ctx: ^Write_Context, r: rune) -> Write_Error {
	bytes, length := utf8.encode_rune(r)

	value := u8(length)
	value |= byte(Format.Fix_Str)
	write_byte(ctx, value) or_return

	return write_bytes(ctx, &bytes[0], length)
}

// write .Str8 + string length as u8 + string content clamped 
write_str8 :: proc(using ctx: ^Write_Context, text: string) -> Write_Error {
	write_format(ctx, .Str8) or_return
	
	// clamp to 2^8-1
	clamped_length := clamp(len(text), 0, 255)
	write_byte(ctx, u8(clamped_length)) or_return

	data := mem.raw_string_data(text)
	return write_bytes(ctx, data, clamped_length)	
}

// write .Str16 + string length as u16be + string content clamped
write_str16 :: proc(using ctx: ^Write_Context, text: string) -> Write_Error {
	write_format(ctx, .Str16) or_return

	// clamp to 2^16-1
	clamped_length := clamp(len(text), 0, 65_535)
	value := u16be(clamped_length)
	write_bytes(ctx, &value, 2) or_return

	data := mem.raw_string_data(text)
	return write_bytes(ctx, data, clamped_length)	
}

// write .Str32 + string length as u32be + string content clamped
write_str32 :: proc(using ctx: ^Write_Context, text: string) -> Write_Error {
	write_format(ctx, .Str32) or_return

	// clamp to 2^32-1
	clamped_length := clamp(len(text), 0, 4_294_967_295)
	value := u32be(clamped_length)
	write_bytes(ctx, &value, 4) or_return

	data := mem.raw_string_data(text)
	return write_bytes(ctx, data, clamped_length)	
}

// write string and choose format automaticall based on length
write_string :: proc(using ctx: ^Write_Context, text: string) -> Write_Error {
	length := len(text)
	data := mem.raw_string_data(text)
	
	if length < 32 {
		value := u8(length)
		value |= byte(Format.Fix_Str)
		write_byte(ctx, value) or_return
	} else if length < 256 {
		write_format(ctx, .Str8) or_return
		write_byte(ctx, u8(length)) or_return
	} else if length < 65_536 {
		write_format(ctx, .Str8) or_return
		value := u16be(length)
		write_bytes(ctx, &value, 2) or_return
	} else if length < 4_294_967_296 {
		write_format(ctx, .Str8) or_return
		value := u32be(length)
		write_bytes(ctx, &value, 4) or_return
	} else {
		return .Overflow_String
	}

	return write_bytes(ctx, data, length) 
}

_write_bin_format :: proc(ctx: ^Write_Context, length: int) -> Write_Error {
	if length < 256 {
		write_format(ctx, .Bin8) or_return
		write_byte(ctx, u8(length)) or_return
	} else if length < 65_536 {
		write_format(ctx, .Bin16) or_return
		value := u16be(length)
		write_bytes(ctx, &value, 2) or_return
	} else if length < 4_294_967_296 {
		write_format(ctx, .Bin32) or_return
		value := u32be(length)
		write_bytes(ctx, &value, 4) or_return
	} else {
		return .Overflow_Binary
	}

	return .None
}

// write .Bin8 - .Bin32 + slice length + byte content
write_bin :: proc(using ctx: ^Write_Context, bytes: []byte) -> Write_Error {
	_write_bin_format(ctx, len(bytes)) or_return
	return write_bytes(ctx, &bytes[0], len(bytes))
}

// helper: write array format based on length, content has to follow
_write_array_format :: proc(ctx: ^Write_Context, length: int) -> Write_Error {
	if length < 16 {
		value := u8(length)
		value |= byte(Format.Fix_Array)
		write_byte(ctx, value) or_return
	} else if length < 65_536 {
		write_format(ctx, .Array16) or_return
		value := u16be(length)
		write_bytes(ctx, &value, 2) or_return
	} else if length < 4_294_967_296 {
		write_format(ctx, .Array32) or_return
		value := u32be(length)
		write_bytes(ctx, &value, 4) or_return
	} else {
		return .Overflow_Array
	}

	return .None
}

// helper: write map format base on map length
_write_map_format :: proc(ctx: ^Write_Context, length: int) -> Write_Error {
	if length < 16 {
		value := u8(length)
		value |= byte(Format.Fix_Map)
		write_byte(ctx, value) or_return
	} else if length < 65_536 {
		write_format(ctx, .Map16) or_return
		value := u16be(length)
		write_bytes(ctx, &value, 2) or_return
	} else if length < 4_294_967_296 {
		write_format(ctx, .Map32) or_return
		value := u32be(length)
		write_bytes(ctx, &value, 4) or_return
	} else {
		return .Overflow_Map
	}

	return .None		
}

// extension calls

// helper: create fixed ext easier
write_fix_ext :: proc(ctx: ^Write_Context, format: Format, type: i8, value: any) -> Write_Error {
	write_format(ctx, format) or_return
	type := type
	write_bytes(ctx, &type, 1) or_return
	size := _fix_ext_size(format)
	return write_bytes(ctx, value.data, size)
}

// write .Ext8 - .Ext32 format + length info + ext type + value content
write_ext_format :: proc(ctx: ^Write_Context, type: i8, length: u32) -> Write_Error {
	if length < 256 {
		write_format(ctx, .Ext8) or_return
		write_byte(ctx, u8(length)) or_return
	} else if length < 65_536 {
		write_format(ctx, .Ext16) or_return
		value := u16be(length)
		write_bytes(ctx, &value, 2) or_return
	} else if length < 4_294_967_295 {
		write_format(ctx, .Ext32) or_return
		value := u32be(length)
		write_bytes(ctx, &value, 4) or_return
	} else {
		return .Overflow_Extension
	}

	type := type
	return write_bytes(ctx, &type, 1)
}

// write extension of large size, use fixed_ext if you have small / constant sizes
write_ext :: proc(ctx: ^Write_Context, type: i8, value: any, length: u32) -> Write_Error {
	write_ext_format(ctx, type, length) or_return
	return write_bytes(ctx, value.data, size_of(value.id) * int(length))
}

// NOTE timestamps not fully supported with odin time.Time type

write_timestamp32 :: proc(ctx: ^Write_Context, time: u32) -> Write_Error {
	return write_fix_ext(ctx, .Fix_Ext4, i8(Extension.Timestamp), time)
}

write_timestamp64 :: proc(ctx: ^Write_Context, time: i64) -> Write_Error {
	return write_fix_ext(ctx, .Fix_Ext8, i8(Extension.Timestamp), time)
}

write_timestamp96 :: proc(ctx: ^Write_Context, nanoseconds: u32, seconds: u64) -> Write_Error {
	bytes: [12]byte
	write_ext_format(ctx, i8(Extension.Timestamp), len(bytes))
	return write_bytes(ctx, &bytes[0], len(bytes))
}

// custom odin extensions

// write an odin typeid to fixed extension, has to be read back properly on the reader
write_typeid :: proc(using ctx: ^Write_Context, type: typeid) -> Write_Error {
	if type not_in typeid_map {
		return .Type_Id_Unsupported
	}

	id := typeid_map[type]
	return write_fix_ext(ctx, Format.Fix_Ext1, i8(Extension.Type_Id), id)
}
