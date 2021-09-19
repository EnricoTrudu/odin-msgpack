package msgpack

import "core:fmt"
import "core:mem"
import "core:unicode/utf8"
import "core:runtime"
import "core:reflect"

Write_Context :: struct {
	start: []byte,
	output: []byte,
	typeid_map: map[typeid]u8,
}

Write_Error :: enum {
	None,
	
	Overflow_Buffer,    // not enough memory provided for context
	Overflow_String,    // spec: non supported string     length  
	Overflow_Binary,    // spec: non supported binary     length
	Overflow_Array,	    // spec: non supported array      length
	Overflow_Map,       // spec: non supported array      length
	Overflow_Extension, // spec: non supported extensions length

	Type_Id_Unsupported,

	Any_Type_Unsupported,
	Any_Type_Not_Array,
	Any_Type_Not_Matched,
}

write_context_result :: proc(using ctx: ^Write_Context) -> []byte {
	return start[:len(start) - len(output)]
}

@(deferred_in=write_context_init)
write_context_scoped :: proc(cap: int) -> Write_Context {
	return write_context_init(cap)
}

write_context_init :: proc(cap: int) -> (result: Write_Context) {
	result.start = make([]byte, cap)
	result.output = result.start
	return
}

write_context_destroy :: proc(ctx: ^Write_Context) {
	delete(ctx.start)
	delete(ctx.typeid_map)
}

write_context_add_typeid :: proc(using ctx: ^Write_Context, type: typeid) {
	typeid_map[type] = u8(len(typeid_map))
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

// write array info based on any recursive
_write_array_any :: proc(ctx: ^Write_Context, length: int, root: uintptr, offset_size: int, id: typeid) -> Write_Error {
	for i in 0..<length {
		data := root + uintptr(i * offset_size)

		result := write_any(ctx, any { rawptr(data), id })
		if result	!= .None {
			return result
		}
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

write_any :: proc(using ctx: ^Write_Context, v: any) -> Write_Error {
	if v == nil {
		return write_nil(ctx)
	}

	ti := runtime.type_info_base(type_info_of(v.id))
	a := any { v.data, ti.id }

	#partial switch info in ti.variant {
		case runtime.Type_Info_Integer: {
			switch i in a {
				case i8: return write_int8(ctx, i)
				case i32: return write_int32(ctx, i32be(i))
				case i64: return write_int64(ctx, i64be(i))
				case int: return write_int64(ctx, i64be(i))
				
				case u8: return write_uint8(ctx, i)
				case u16: return write_uint16(ctx, u16be(i))
				case u32: return write_uint32(ctx, u32be(i))
				case u64: return write_uint64(ctx, u64be(i))
				case uint: return write_uint64(ctx, u64be(i))

				case i16le: return write_int16(ctx, i16be(i))
				case i32le: return write_int32(ctx, i32be(i))
				case i64le: return write_int64(ctx, i64be(i))
				case u16le: return write_uint16(ctx, u16be(i))
				case u32le: return write_uint32(ctx, u32be(i))
				case u64le: return write_uint64(ctx, u64be(i))
				
				case i16be: return write_int16(ctx, i)
				case i32be: return write_int32(ctx, i)
				case i64be: return write_int64(ctx, i)
				case u16be: return write_uint16(ctx, i)
				case u32be: return write_uint32(ctx, i)
				case u64be: return write_uint64(ctx, i)
			}
		}

		case runtime.Type_Info_Float: {
			switch f in a {
				case f16: return write_float32(ctx, f32(f))
				case f32: return write_float32(ctx, f)
				case f64: return write_float64(ctx, f)
			}
		} 

		case runtime.Type_Info_String: {
			switch s in a {
				case string: {
					return write_string(ctx, s)
				}
				case cstring: return write_string(ctx, string(s))
			}
		}

		case runtime.Type_Info_Rune: {
			some_rune := a.(rune)
			write_rune(ctx, some_rune) or_return
			return .None
		}

		case runtime.Type_Info_Boolean: {
			switch b in a {
				case bool: return write_bool(ctx, bool(b))
				case b8: return write_bool(ctx, bool(b))
				case b16: return write_bool(ctx, bool(b))
				case b32: return write_bool(ctx, bool(b))
				case b64: return write_bool(ctx, bool(b))
			}
		}

		// write array format and fill data per inner any element
		case runtime.Type_Info_Array: {
			length := info.count
			
			// skip array element is byte and write .Bin*
			if info.elem.id == byte {
				_write_bin_format(ctx, length) or_return
				return write_bytes(ctx, v.data, length)
			} else {
				_write_array_format(ctx, length) or_return
				return _write_array_any(ctx, length, uintptr(v.data), info.elem_size, info.elem.id) 
			}
		}

		// same as array
		case runtime.Type_Info_Enumerated_Array: {
			length := info.count 

			if info.elem.id == byte {
				_write_bin_format(ctx, length) or_return
				return write_bytes(ctx, v.data, length)
			} else {
				_write_array_format(ctx, length) or_return
				return _write_array_any(ctx, length, uintptr(v.data), info.elem_size, info.elem.id)
			}
		}

		// write array format and fill data per inner any element
		case runtime.Type_Info_Slice: {
			slice := (^mem.Raw_Slice)(a.data)
			length := slice.len
			
			// skip array element is byte and write .Bin*
			if info.elem.id == byte {
				_write_bin_format(ctx, length) or_return
				return write_bytes(ctx, slice.data, length)
			} else {
				_write_array_format(ctx, length) or_return
				return _write_array_any(ctx, length, uintptr(slice.data), info.elem_size, info.elem.id) 
			}
		}

		// write array format and fill data per inner any element
		case runtime.Type_Info_Dynamic_Array: {
			array := (^mem.Raw_Dynamic_Array)(a.data)
			length := array.len
			
			if info.elem.id == byte {
				_write_bin_format(ctx, length) or_return
				return write_bytes(ctx, array.data, length) 
			} else {
				_write_array_format(ctx, length) or_return
				return _write_array_any(ctx, length, uintptr(array.data), info.elem_size, info.elem.id) 
			}	
		}

		// similar to `core:encoding/json`
		case runtime.Type_Info_Map: {
			m := (^mem.Raw_Map)(a.data)
			
			if m == nil || info.generated_struct == nil {
				return .Any_Type_Unsupported
			}

			entries := &m.entries
			gs := runtime.type_info_base(info.generated_struct).variant.(runtime.Type_Info_Struct)
			ed := runtime.type_info_base(gs.types[1]).variant.(runtime.Type_Info_Dynamic_Array)
			entry_type := ed.elem.variant.(runtime.Type_Info_Struct)
			entry_size := ed.elem_size
			// fmt.println("entries", entries, ed.elem.id, ed.elem_size)
			// fmt.println(info.key.id, info.value.id)

			// write entry info formats
			_write_map_format(ctx, entries.len) or_return

			if entries.len == 0 {
				return .None
			}

			// write key value pair per entry
			for i in 0..<entries.len {
				data := uintptr(entries.data) + uintptr(i * entry_size)
				key := rawptr(data + entry_type.offsets[2])
				value := rawptr(data + entry_type.offsets[3])

				// write key value
				write_any(ctx, any{ key, info.key.id }) or_return
				write_any(ctx, any{ value, info.value.id }) or_return
			}

			return .None
		}

		case runtime.Type_Info_Struct: {
			end_map_length := len(info.names)
			tags_empty := len(info.tags) == 0
			if !tags_empty {
				for tag in info.tags {
					if tag == "skip" {
						end_map_length -= 1	
					}
				}
			}

			_write_map_format(ctx, end_map_length) or_return

			struct_loop: for name, i in info.names {
				if !tags_empty {
					if info.tags[i] == "skip" {
						fmt.println("skip", info.tags[i], info.names[i], info.types[i])
						continue struct_loop
					}
				}

				write_string(ctx, name) or_return

				id := info.types[i].id
				data := rawptr(uintptr(v.data) + info.offsets[i])
				write_any(ctx, any { data, id }) or_return
			}

			return .None
		}

		case runtime.Type_Info_Type_Id: {
			type := a.(typeid)
			write_typeid(ctx, type) or_return
			return .None
		}

		case: {
			fmt.println("ANY_TYPE_UNSUPPORTED", v, a)
			return .Any_Type_Unsupported
		}
	}

	return .Any_Type_Not_Matched
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

write_ext :: proc(ctx: ^Write_Context, type: i8, value: any, length: u32) -> Write_Error {
	write_ext_format(ctx, type, length) or_return
	return write_bytes(ctx, value.data, size_of(value.id) * int(length))
}

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

write_typeid :: proc(using ctx: ^Write_Context, type: typeid) -> Write_Error {
	assert(len(typeid_map) != 0)

	if type not_in typeid_map {
		return .Type_Id_Unsupported
	}

	id := typeid_map[type]
	return write_fix_ext(ctx, Format.Fix_Ext1, i8(Extension.Type_Id), id)
}