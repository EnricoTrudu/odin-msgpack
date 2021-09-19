package msgpack

import "core:fmt"
import "core:mem"
import "core:strings"
import "core:runtime"
import "core:slice"
import "core:reflect"
import "core:intrinsics"

// TODO force array values to be the same types, count up different types?
//		skip if two different types appear
// TODO force map values to be the same types

// TODO replace this with individual skips, will be faster
// read format and advance without caring about return value
_skip_any :: proc(using ctx: ^Read_Context) -> (err: Read_Error) {
	b := read_byte(ctx) or_return
	ctx.current_format = format_clamp(b)

	#partial switch ctx.current_format {
		case .Nil, .False, .True, .Positive_Fix_Int, .Negative_Fix_Int: {
			read_advance(ctx) or_return
		}

		case .Int8, .Int16, .Int32, .Int64: {
			read_int(ctx)	or_return
		}

		case .Uint8, .Uint16, .Uint32, .Uint64: {
			read_uint(ctx) or_return
		}

		case .Fix_Str, .Str8, .Str16, .Str32: {
			read_string(ctx) or_return
		}

		case .Bin8, .Bin16, .Bin32: {
			read_bin(ctx) or_return
		}

		case .Fix_Array, .Array16, .Array32: {
			length := read_array(ctx) or_return
			for i in 0..<length {
				_skip_any(ctx) or_return
			}
		}

		case .Fix_Map, .Map16, .Map32: {
			// TODO loop through array skips
			read_map(ctx) or_return
		}

		case .Fix_Ext1, .Fix_Ext2, .Fix_Ext4, .Fix_Ext8, .Fix_Ext16: {
			read_fix_ext(ctx) or_return
		}

		case .Ext8, .Ext16, .Ext32: {
			read_ext(ctx) or_return
		}
	}

	return
}

// NOTE easy copy / paste helper code following 
// most of these helpers are conversion to their respective types while trying to
// match the read context format - otherwhise data read will be skipped
// i.e. a struct member is `i8`, then its `read_*` call has to respect that

_unmarshall_i8 :: proc(using ctx: ^Read_Context, v: any) -> (err: Read_Error) {
	value := cast(^i8) v.data

	#partial switch ctx.current_format {
		case .Positive_Fix_Int: value^ = read_positive_fix_int(ctx) or_return
		case .Negative_Fix_Int: value^ = read_negative_fix_int(ctx) or_return
		case .Int8: value^ = read_int8(ctx) or_return
		case: _skip_any(ctx) or_return
	}

	return
}

_unmarshall_i16 :: proc(using ctx: ^Read_Context, v, a: any) -> (err: Read_Error) {
	if ctx.current_format != .Int16 {
		_skip_any(ctx) or_return
		return 
	}

	value := read_int16(ctx) or_return

	switch i in a {
		case i16: 	(cast(^i16) v.data)^ = cast(i16) value
		case i16be: (cast(^i16be) v.data)^ = value
		case i16le: (cast(^i16le) v.data)^ = cast(i16le) value
	}

	return
}

_unmarshall_i32 :: proc(using ctx: ^Read_Context, v, a: any) -> (err: Read_Error) {
	if ctx.current_format != .Int32 {
		_skip_any(ctx) or_return
		return
	}

	value := read_int32(ctx) or_return

	switch i in a {
		case i32: 	(cast(^i32) v.data)^ = cast(i32) value
		case i32be: (cast(^i32be) v.data)^ = value
		case i32le: (cast(^i32le) v.data)^ = cast(i32le) value
	}

	return
}

_unmarshall_i64 :: proc(using ctx: ^Read_Context, v, a: any) -> (err: Read_Error) {
	if ctx.current_format != .Int64 {
		_skip_any(ctx) or_return
		return
	}

	value := read_int64(ctx) or_return

	switch i in a {
		case i64: 	(cast(^i64) v.data)^ = cast(i64) value
		case i64be: (cast(^i64be) v.data)^ = value
		case i64le: (cast(^i64le) v.data)^ = cast(i64le) value
		case int: 	(cast(^int) v.data)^ = cast(int) value
	}

	return
}

_unmarshall_u8 :: proc(using ctx: ^Read_Context, v: any) -> (err: Read_Error) {
	#partial switch ctx.current_format {
		case .Int8: (cast(^u8) v.data)^ = read_uint8(ctx) or_return
		case: _skip_any(ctx) or_return
	}

	return
}

_unmarshall_u16 :: proc(using ctx: ^Read_Context, v, a: any) -> (err: Read_Error) {
	if ctx.current_format != .Uint16 {
		_skip_any(ctx) or_return
		return
	}

	value := read_uint16(ctx) or_return

	switch i in a {
		case u16: 	(cast(^u16) v.data)^ = cast(u16) value
		case u16be: (cast(^u16be) v.data)^ = value
		case u16le: (cast(^u16le) v.data)^ = cast(u16le) value
	}

	return
}

_unmarshall_u32 :: proc(using ctx: ^Read_Context, v, a: any) -> (err: Read_Error) {
	if ctx.current_format != .Uint32 {
		_skip_any(ctx) or_return
		return
	}

	value := read_uint32(ctx) or_return

	switch i in a {
		case u32: 	(cast(^u32) v.data)^ = cast(u32) value
		case u32be: (cast(^u32be) v.data)^ = value
		case u32le: (cast(^u32le) v.data)^ = cast(u32le) value
	}

	return
}

_unmarshall_u64 :: proc(using ctx: ^Read_Context, v, a: any) -> (err: Read_Error) {
	if ctx.current_format != .Uint64 {
		_skip_any(ctx) or_return
		return
	}

	value := read_uint64(ctx) or_return

	switch i in a {
		case u64: 	(cast(^u64) v.data)^ = cast(u64) value
		case u64be: (cast(^u64be) v.data)^ = value
		case u64le: (cast(^u64le) v.data)^ = cast(u64le) value
		case uint: 	(cast(^uint) v.data)^ = cast(uint) value
	}

	return
}

current_is_binary :: proc(ctx: ^Read_Context) -> bool {
	#partial switch ctx.current_format {
		case .Bin8, .Bin16, .Bin32: return true
	}

	return false	
}

current_is_array :: proc(ctx: ^Read_Context) -> bool {
	#partial switch ctx.current_format {
		case .Fix_Array, .Array16, .Array32: return true
	}

	return false	
}

current_is_map :: proc(ctx: ^Read_Context) -> bool {
	#partial switch ctx.current_format {
		case .Fix_Map, .Map16, .Map32: return true
	}

	return false	
}

current_is_string :: proc(ctx: ^Read_Context) -> bool {
	#partial switch ctx.current_format {
		case .Fix_Str, .Str8, .Str16, .Str32: return true
	}

	return false	
}

current_is_fix_ext :: proc(ctx: ^Read_Context) -> bool {
	#partial switch ctx.current_format {
		case .Fix_Ext1, .Fix_Ext2, .Fix_Ext4, .Fix_Ext8, .Fix_Ext16: return true
	}

	return false	
}

current_is_ext :: proc(ctx: ^Read_Context) -> bool {
	#partial switch ctx.current_format {
		case .Ext8, .Ext16, .Ext32: return true
	}

	return false	
}

// iterate through array content uintptrs
// similar to _write_array_any
_unmarshall_array :: proc(ctx: ^Read_Context, length: int, root: uintptr, offset_size: int, id: typeid, allocator := context.allocator) -> Read_Error {
	for i in 0..<length {
		data := root + uintptr(i * offset_size)
		unmarshall(ctx, any { rawptr(data), id }, allocator) or_return
	}

	return .None
}

// assumes current_is_array previously
// length of array read previously
array_has_same_types :: proc(ctx: ^Read_Context, length: int) -> (ok: bool, err: Read_Error) {
	old := ctx.input
	ok = true

	if length == 1 {
		return
	}

	previous_format: Format
	for i in 0..<length {
		previous_format = ctx.current_format
		_skip_any(ctx) or_return
		
		if i != 0 && previous_format != ctx.current_format {
			fmt.println("prev", previous_format, ctx.current_format)
			ok = false
		}
	}

	if !ok {
		return
	}

	// if all the same, reset input
	ctx.input = old
	return 
}

// avoid duplicate code _Array and _Enumerated_Array
_unmarshall_array_check :: proc(
	ctx: ^Read_Context, 
	array_length: int, 
	element_type: typeid, 
	element_size: int, 
	v: any,
) -> (err: Read_Error) {
	// NOTE BINARY support: only allow exact array size match with binary
	if element_type == byte {
		// validate current is binary
		if current_is_binary(ctx) {
			binary_bytes := read_bin(ctx) or_return

			if array_length == len(binary_bytes) {
				mem.copy(v.data, &binary_bytes[0], array_length)
			}
		} else {
			_skip_any(ctx) or_return
		}
	} else {
		if current_is_array(ctx) {
			length := read_array(ctx) or_return

			// NOTE read has to match array count
			if array_length == length {
				// when values arent the same type, skip all content
				if ctx.decoding == .Strict {
					same := array_has_same_types(ctx, length) or_return
					if !same {
						return
					}
				}

				_unmarshall_array(ctx, length, uintptr(v.data), element_size, element_type) or_return
			} else {
				// else skip each any
				for i in 0..<array_length {
					_skip_any(ctx) or_return
				}
			}
		} else {
			_skip_any(ctx) or_return
		}
	}

	return .None
}

// unmarshall incoming any to exact type in ctx.current_format
// when ti.id doesnt match ctx.current_format, it will be skipped
unmarshall :: proc(using ctx: ^Read_Context, v: any, allocator := context.allocator) -> (err: Read_Error) {
	ti := runtime.type_info_base(type_info_of(v.id))
	a := any { v.data, ti.id }

	if len(input) == 0 {
		return
	}

	b := read_byte(ctx) or_return
	ctx.current_format = format_clamp(b)
	fmt.println("current:", ctx.current_format, v, ti.id)

	#partial switch info in ti.variant {
		case runtime.Type_Info_Pointer: {
			// return .Unsupported_Pointer
		}

		// input any is integer, match integer type to read format, parse value
		case runtime.Type_Info_Integer: {
			#partial switch ctx.current_format {
				case .Positive_Fix_Int, .Negative_Fix_Int, .Int8, .Int16, .Int32, .Int64: {
					switch i in a {
						case i8: _unmarshall_i8(ctx, v) or_return
						case i16, i16le, i16be: _unmarshall_i16(ctx, v, a) or_return
						case i32, i32le, i32be: _unmarshall_i32(ctx, v, a) or_return
						case i64, i64le, i64be, int: _unmarshall_i64(ctx, v, a) or_return
					}
				}

				case .Uint8, .Uint16, .Uint32, .Uint64: {
					switch i in a {
						case u8: _unmarshall_u8(ctx, v) or_return
						case u16, u16le, u16be: _unmarshall_u16(ctx, v, a) or_return
						case u32, u32le, u32be: _unmarshall_u32(ctx, v, a) or_return
						case u64, u64le, u64be, uint: _unmarshall_u64(ctx, v, a) or_return
					}
				}

				case: {
					_skip_any(ctx) or_return
				}
			}
		}
	
		// input any is float, match read format, parse value, throw away f16
		case runtime.Type_Info_Float: {
			if a.id == f32 && ctx.current_format == .Float32 {
				(cast(^f32) v.data)^ = read_float32(ctx) or_return
				return
			}

			if a.id == f64 && ctx.current_format == .Float64 {
				(cast(^f64) v.data)^ = read_float64(ctx) or_return
				return
			}

			// f16 NOT SUPPORTED BY SPEC
			_skip_any(ctx) or_return
		}

		// different sized booleans NON spec compliant
		// but write_bool converts odin bool types to 1 byte
		// so read returns 1 byte and unmarshallling should be allowed
		case runtime.Type_Info_Boolean: {
			if ctx.current_format == .True || ctx.current_format == .False {
				value := read_bool(ctx) or_return

				switch b in a {
					case bool:	(cast(^bool) v.data)^ = value
					case b8:		(cast(^b8) v.data)^ = cast(b8) value
					case b16: 	(cast(^b16) v.data)^ = cast(b16) value
					case b32: 	(cast(^b32) v.data)^ = cast(b32) value
					case b64: 	(cast(^b64) v.data)^ = cast(b64) value
				}
			} else {
				_skip_any(ctx) or_return
			}
		}

		// NOTE allocates memor
		case runtime.Type_Info_String: {
			if current_is_string(ctx) {
				text := read_string(ctx) or_return

				switch s in a {
					case string: {
						old_string := (cast(^string) v.data)
						// NOTE maybe bad
						delete(old_string^)
						old_string^ = strings.clone(text)
					}

					case cstring: {
						old_string := (cast(^cstring) v.data)
						// NOTE maybe bad
						delete(old_string^)
						old_string^ = strings.clone_to_cstring(text)
					}
				}
			} else {
				_skip_any(ctx) or_return
			}
		}

		case runtime.Type_Info_Rune: {
			if current_is_string(ctx) {
				r := cast(^rune) v.data
				result := read_rune(ctx) or_return
				r^ = result
			} else {
				_skip_any(ctx) or_return				
			}
		}

		case runtime.Type_Info_Array: {
			_unmarshall_array_check(ctx, info.count, info.elem.id, info.elem_size, v) or_return
		}

		case runtime.Type_Info_Enumerated_Array: {
			_unmarshall_array_check(ctx, info.count, info.elem.id, info.elem_size, v) or_return
		}

		case runtime.Type_Info_Slice: {
			raw_slice := (^mem.Raw_Slice)(a.data)

			if info.elem.id == byte {
				// validate current is binary
				if current_is_binary(ctx) {
					binary_bytes := read_bin(ctx) or_return

					// delete old slice content if existed, replace with copied bytes
					if raw_slice != nil {
						// TODO pass loc?
						free(raw_slice.data, allocator)
					} 

					cloned_result := slice.clone(binary_bytes)
					raw_slice.data = &cloned_result[0]
					raw_slice.len = len(binary_bytes)
				} else {
					_skip_any(ctx) or_return
				}
			} else {
				if current_is_array(ctx) {
					length := read_array(ctx) or_return
		
					if length == 0 {
						return
					}

					if raw_slice != nil {
						free(raw_slice.data, allocator)
					}

					// create new slice with element id, unmarshall content
					make_slice_raw(raw_slice, info.elem.id, length, info.elem.align, allocator)
					_unmarshall_array(ctx, length, uintptr(raw_slice.data), info.elem_size, info.elem.id) or_return
				} else {
					_skip_any(ctx) or_return
				}
			}	
		}

		// may resize underlying array to new size
		// sets new size of array and unmarshalls inner values
		case runtime.Type_Info_Dynamic_Array: {
			raw_array := (^mem.Raw_Dynamic_Array)(a.data)

			if info.elem.id == byte {
				// validate current is binary
				if current_is_binary(ctx) {
					binary_bytes := read_bin(ctx) or_return
					size := len(binary_bytes)

					// reserve till size, set size, mem copy region
					_reserve_memory_any_dynamic_array(raw_array, byte, size)
					raw_array.len = size
					mem.copy(raw_array.data, &binary_bytes[0], size)
				} else {
					_skip_any(ctx) or_return
				}
			} else {
				if current_is_array(ctx) {
					length := read_array(ctx) or_return

					// TODO restrict to odin only single type		

					// NOTE resets raw array size
					raw_array.len = length
					_reserve_memory_any_dynamic_array(raw_array, info.elem.id, length)
					_unmarshall_array(ctx, length, uintptr(raw_array.data), info.elem_size, info.elem.id) or_return
				} else {
					_skip_any(ctx) or_return
				}
			}
		}

		case runtime.Type_Info_Map: {
			m := (^runtime.Raw_Map)(a.data)
			
			if m == nil || info.generated_struct == nil || !current_is_map(ctx) {
				_skip_any(ctx) or_return
				return
			}

			length := read_map(ctx) or_return
			if length == 0 {
				// NOTE no skip needed
				return
			}

			// TODO match msgpack key + value to this map

			entries := &m.entries
			gs := runtime.type_info_base(info.generated_struct).variant.(runtime.Type_Info_Struct)
			ed := runtime.type_info_base(gs.types[1]).variant.(runtime.Type_Info_Dynamic_Array)
			entry_type := ed.elem.variant.(runtime.Type_Info_Struct)
			entry_size := ed.elem_size
			// entry_align := gs.align

			fmt.println("INSIDE MAP", entry_type, entry_size, ed.elem)

			if entries.len != 0 {
				// clear map
			}

			header := runtime.Map_Header {m = m}
			// header.equal = intrinsics.type_equal_proc(info.key.id)

			header.entry_size    = entry_size
			// header.entry_align   = entry_type.align
			header.entry_align   = 0

			header.key_offset    = entry_type.offsets[2]
			key_size := info.key.size
			header.key_size      = key_size

			value_size := info.value.size
			header.value_offset  = entry_type.offsets[3]
			header.value_size    = value_size

			runtime.__dynamic_map_reserve(header, length)
			// runtime.__dynamic_map_grow(header)

			// entry_header := runtime.Map_Entry_Header(header,)

			// for i in 0..<length {
			// 	data := uintptr(entries.data) + uintptr(i * entry_size)
			// 	key := rawptr(data + entry_type.offsets[2])
			// 	value := rawptr(data + entry_type.offsets[3])
			
			// 	unmarshall(ctx, any { key, info.key.id }, allocator)
			// 	unmarshall(ctx, any { value, info.value.id }, allocator)
			// }


			// // write key value pair per entry
			// for i in 0..<entries.len {
			// 	data := uintptr(entries.data) + uintptr(i * entry_size)
			// 	key := rawptr(data + entry_type.offsets[2])
			// 	value := rawptr(data + entry_type.offsets[3])

			// 	unmarshall(ctx, any{ key, info.key.id }, allocator)
			// 	unmarshall(ctx, any{ value, info.value.id }, allocator)
			// }
		}

		// fixed extension type id
		case runtime.Type_Info_Type_Id: {
			if current_is_fix_ext(ctx) {
				type, bytes := read_fix_ext(ctx) or_return

				if type == i8(Extension.Type_Id) {
					ptr := cast(^typeid) a.data
					type := read_typeid(ctx, type, bytes) or_return
					ptr^ = type
				}
			} else {
				_skip_any(ctx) or_return
			}
		}

		case runtime.Type_Info_Struct: {
			// allow only map format for a struct match
			if !current_is_map(ctx) {
				_skip_any(ctx) or_return
				return
			}

			tags_empty := len(info.tags) == 0 
			length := read_map(ctx) or_return
			length_count: int

			length_loop: for length_count != length {
				ctx.current_format = format_clamp(input[0])

				// has to be a valid string value, otherwhise doesnt match struct write_any  
				if current_is_string(ctx) {
					text := read_string(ctx) or_return
					// fmt.println("SEARCH", text, length_count)

					name_search: for name, i in info.names {
						// if !tags_empty && info.tags[i] == "skip" {
						// 	continue length_loop
						// }

						if name == text {
							data := rawptr(uintptr(v.data) + info.offsets[i])
							id := info.types[i].id
							unmarshall(ctx, any { data, id }, allocator) or_return

							length_count += 1
							continue length_loop
						}
					}			
				} else {
					// skip non string key without count increase
					_skip_any(ctx) or_return
				}

				// no matching parameter found
				length_count += 1
				_skip_any(ctx) or_return
			}
		}

		case: {
			_skip_any(ctx) or_return
		}
	}

	return
}

// unmarshall_new :: proc(ctx: ^Read_Context, $T: typeid, allocator := context.allocator) -> T {
// 	result: T
// 	unmarshall(ctx, result, allocator)
// 	return result
// }

_reserve_memory_any_dynamic_array :: proc(array: ^mem.Raw_Dynamic_Array, type: typeid, capacity: int, loc := #caller_location) -> bool {
	if array == nil {
		return false
	}

	if capacity <= array.cap {
		return true
	}

	if array.allocator.procedure == nil {
		array.allocator = context.allocator
	}
	assert(array.allocator.procedure != nil)

	type_size := reflect.size_of_typeid(type)
	align_size := reflect.align_of_typeid(type)

	old_size  := array.cap * type_size
	new_size  := capacity * type_size
	allocator := array.allocator

	new_data, err := allocator.procedure(
		allocator.data, .Resize, new_size, align_size,
		array.data, old_size, loc,
	)
	if new_data == nil || err != nil {
		return false
	}

	array.data = raw_data(new_data)
	array.cap = capacity
	return true
}

make_slice_raw :: proc(
	raw_slice: ^mem.Raw_Slice,

	type: typeid,
	#any_int len: int, 
	alignment: int, 

	allocator := context.allocator, 
	loc := #caller_location,
) {
	runtime.make_slice_error_loc(loc, len)
	type_size := reflect.size_of_typeid(type)

	data, err := runtime.mem_alloc_bytes(type_size * len, alignment, allocator, loc)
	if data == nil && type_size != 0 {
		return
	}

	s := mem.Raw_Slice { raw_data(data), len }
	raw_slice^ = s
}