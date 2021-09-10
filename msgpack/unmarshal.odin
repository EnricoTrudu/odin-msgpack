package msgpack

import "core:fmt"
import "core:mem"
import "core:strings"
import "core:runtime"
import "core:slice"

// TODO replace this with individual skips, will be faster
// read format and advance without caring about return value
_skip_any :: proc(using ctx: ^Read_Context) {
	ctx.current_format = format_clamp(input[0])

	#partial switch ctx.current_format {
		case .Nil, .False, .True, .Positive_Fix_Int, .Negative_Fix_Int: {
			input = input[1:]
		}

		case .Int8, .Int16, .Int32, .Int64: {
			read_int(ctx)	
		}

		case .Uint8, .Uint16, .Uint32, .Uint64: {
			read_uint(ctx)
		}

		case .Fix_Str, .Str8, .Str16, .Str32: {
			read_string(ctx)
		}

		case .Bin8, .Bin16, .Bin32: {
			read_bin(ctx)
		}

		// TODO extensions

		case .Fix_Array, .Array16, .Array32: {
			length := read_array(ctx)
			for i in 0..<length {
				_skip_any(ctx)
			}
		}

		case .Fix_Map, .Map16, .Map32: {
			read_map(ctx)
		}
	}
}

// NOTE easy copy / paste helper code following 
// most of these helpers are conversion to their respective types while trying to
// match the read context format - otherwhise data read will be skipped
// i.e. a struct member is `i8`, then its `read_*` call has to respect that

_unmarshal_i8 :: proc(using ctx: ^Read_Context, v: any) {
	value := cast(^i8) v.data

	#partial switch ctx.current_format {
		case .Positive_Fix_Int: value^ = read_positive_fix_int(ctx)
		case .Negative_Fix_Int: value^ = read_negative_fix_int(ctx)
		case .Int8: value^ = read_int8(ctx)
		case: {
			_skip_any(ctx)
		}
	}
}

_unmarshal_i16 :: proc(using ctx: ^Read_Context, v, a: any) {
	if ctx.current_format != .Int16 {
		_skip_any(ctx)
		return
	}

	value := read_int16(ctx)

	switch i in a {
		case i16: 	(cast(^i16) v.data)^ = cast(i16) value
		case i16be: (cast(^i16be) v.data)^ = value
		case i16le: (cast(^i16le) v.data)^ = cast(i16le) value
	}
}

_unmarshal_i32 :: proc(using ctx: ^Read_Context, v, a: any) {
	if ctx.current_format != .Int32 {
		_skip_any(ctx)
		return
	}

	value := read_int32(ctx)

	switch i in a {
		case i32: 	(cast(^i32) v.data)^ = cast(i32) value
		case i32be: (cast(^i32be) v.data)^ = value
		case i32le: (cast(^i32le) v.data)^ = cast(i32le) value
	}
}

_unmarshal_i64 :: proc(using ctx: ^Read_Context, v, a: any) {
	if ctx.current_format != .Int64 {
		_skip_any(ctx)
		return
	}

	value := read_int64(ctx)

	switch i in a {
		case i64: 	(cast(^i64) v.data)^ = cast(i64) value
		case i64be: (cast(^i64be) v.data)^ = value
		case i64le: (cast(^i64le) v.data)^ = cast(i64le) value
		case int: 	(cast(^int) v.data)^ = cast(int) value
	}
}

_unmarshal_u8 :: proc(using ctx: ^Read_Context, v: any) {
	#partial switch ctx.current_format {
		case .Int8: (cast(^u8) v.data)^ = read_uint8(ctx)
		case: _skip_any(ctx)
	}
}

_unmarshal_u16 :: proc(using ctx: ^Read_Context, v, a: any) {
	if ctx.current_format != .Uint16 {
		_skip_any(ctx)
		return
	}

	value := read_uint16(ctx)

	switch i in a {
		case u16: 	(cast(^u16) v.data)^ = cast(u16) value
		case u16be: (cast(^u16be) v.data)^ = value
		case u16le: (cast(^u16le) v.data)^ = cast(u16le) value
	}
}

_unmarshal_u32 :: proc(using ctx: ^Read_Context, v, a: any) {
	if ctx.current_format != .Uint32 {
		_skip_any(ctx)
		return
	}

	value := read_uint32(ctx)

	switch i in a {
		case u32: 	(cast(^u32) v.data)^ = cast(u32) value
		case u32be: (cast(^u32be) v.data)^ = value
		case u32le: (cast(^u32le) v.data)^ = cast(u32le) value
	}
}

_unmarshal_u64 :: proc(using ctx: ^Read_Context, v, a: any) {
	if ctx.current_format != .Uint64 {
		_skip_any(ctx)
		return
	}

	value := read_uint64(ctx)

	switch i in a {
		case u64: 	(cast(^u64) v.data)^ = cast(u64) value
		case u64be: (cast(^u64be) v.data)^ = value
		case u64le: (cast(^u64le) v.data)^ = cast(u64le) value
		case uint: 	(cast(^uint) v.data)^ = cast(uint) value
	}
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

// iterate through array content uintptrs
// similar to _write_array_any
_unmarshal_array :: proc(ctx: ^Read_Context, length: int, root: uintptr, offset_size: int, id: typeid, allocator := context.allocator) {
	for i in 0..<length {
		data := root + uintptr(i * offset_size)
		unmarshal(ctx, any { rawptr(data), id }, allocator)
	}
}

// unmarshal incoming any to exact type in ctx.current_format
// when ti.id doesnt match ctx.current_format, it will be skipped
unmarshal :: proc(using ctx: ^Read_Context, v: any, allocator := context.allocator) {
	ti := runtime.type_info_base(type_info_of(v.id))
	a := any { v.data, ti.id }

	ctx.current_format = format_clamp(input[0])
	fmt.println(ctx.current_format, v, ti.id)

	#partial switch info in ti.variant {
		case runtime.Type_Info_Pointer: {
			fmt.println("POINTER")
			unmarshal(ctx, a, allocator)
		}

		// input any is integer, match integer type to read format, parse value
		case runtime.Type_Info_Integer: {
			#partial switch ctx.current_format {
				case .Positive_Fix_Int, .Negative_Fix_Int, .Int8, .Int16, .Int32, .Int64: {
					switch i in a {
						case i8: _unmarshal_i8(ctx, v)
						case i16, i16le, i16be: _unmarshal_i16(ctx, v, a)
						case i32, i32le, i32be: _unmarshal_i32(ctx, v, a)
						case i64, i64le, i64be, int: _unmarshal_i64(ctx, v, a)
					}
				}

				case .Uint8, .Uint16, .Uint32, .Uint64: {
					switch i in a {
						case u8: _unmarshal_u8(ctx, v)
						case u16, u16le, u16be: _unmarshal_u16(ctx, v, a)
						case u32, u32le, u32be: _unmarshal_u32(ctx, v, a)
						case u64, u64le, u64be, uint: _unmarshal_u64(ctx, v, a)
					}
				}

				case: {
					_skip_any(ctx)
				}
			}
		}
	
		// input any is float, match read format, parse value, throw away f16
		case runtime.Type_Info_Float: {
			if a.id == f32 && ctx.current_format == .Float32 {
				(cast(^f32) v.data)^ = read_float32(ctx)
				return
			}

			if a.id == f64 && ctx.current_format == .Float64 {
				(cast(^f64) v.data)^ = read_float64(ctx)
				return
			}

			// f16 NOT SUPPORTED BY SPEC
			_skip_any(ctx)
		}

		// different sized booleans NON spec compliant
		// but write_bool converts odin bool types to 1 byte
		// so read returns 1 byte and unmarshalling should be allowed
		case runtime.Type_Info_Boolean: {
			if ctx.current_format == .True || ctx.current_format == .False {
				value := read_bool(ctx)

				switch b in a {
					case bool:	(cast(^bool) v.data)^ = value
					case b8:		(cast(^b8) v.data)^ = cast(b8) value
					case b16: 	(cast(^b16) v.data)^ = cast(b16) value
					case b32: 	(cast(^b32) v.data)^ = cast(b32) value
					case b64: 	(cast(^b64) v.data)^ = cast(b64) value
				}
			} else {
				_skip_any(ctx)
			}
		}

		// NOTE allocates memory
		case runtime.Type_Info_String: {
			#partial switch ctx.current_format {
				case .Fix_Str, .Str8, .Str16, .Str32: {
					text := read_string(ctx)

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
				}

				case: {
					_skip_any(ctx)
				}
			}
		}

		case runtime.Type_Info_Array: {
			// NOTE BINARY support: only allow exact array size match with binary
			if info.elem.id == byte {
				// validate current is binary
				if current_is_binary(ctx) {
					binary_bytes := read_bin(ctx)
					if info.count == len(binary_bytes) {
						mem.copy(v.data, &binary_bytes[0], info.count)
					}
				} else {
					_skip_any(ctx)
				}
			} else {
				if current_is_array(ctx) {
					length := read_array(ctx)
					_unmarshal_array(ctx, length, uintptr(v.data), info.elem_size, info.elem.id)
				} else {
					_skip_any(ctx)
				}
			}
		}

		case runtime.Type_Info_Slice: {
			raw_slice := (^mem.Raw_Slice)(a.data)

			if info.elem.id == byte {
				// validate current is binary
				if current_is_binary(ctx) {
					binary_bytes := read_bin(ctx)

					// delete old slice content if existed, replace with copied bytes
					if raw_slice != nil {
						// TODO pass loc?
						free(raw_slice.data, allocator)
					} 

					cloned_result := slice.clone(binary_bytes)
					raw_slice.data = &cloned_result[0]
					raw_slice.len = len(binary_bytes)
				} else {
					_skip_any(ctx)
				}
			} else {
				if current_is_array(ctx) {
					length := read_array(ctx)
					_unmarshal_array(ctx, length, uintptr(raw_slice.data), info.elem_size, info.elem.id)
				} else {
					_skip_any(ctx)
				}
			}	
		}

		case runtime.Type_Info_Dynamic_Array: {
			raw_array := (^mem.Raw_Dynamic_Array)(a.data)

			if info.elem.id == byte {
				// validate current is binary
				if current_is_binary(ctx) {
					binary_bytes := read_bin(ctx)

					// delete old slice content if existed, replace with copied bytes
					if raw_array != nil {
						// TODO pass loc?
						free(raw_array.data, allocator)
					} 

					cloned_result := slice.clone(binary_bytes)
					raw_array.data = &cloned_result[0]
					raw_array.len = len(binary_bytes)
				} else {
					_skip_any(ctx)
				}
			} else {
				if current_is_array(ctx) {
					length := read_array(ctx)
					_unmarshal_array(ctx, length, uintptr(raw_array.data), info.elem_size, info.elem.id)
				} else {
					_skip_any(ctx)
				}
			}
		}

		case runtime.Type_Info_Struct: {
			// allow only map format for a struct match
			if !current_is_map(ctx) {
				_skip_any(ctx)
				return
			}

			length := read_map(ctx)
			length_count: int

			length_loop: for length_count != length {
				ctx.current_format = format_clamp(input[0])
				text := read_string(ctx)
				fmt.println("SEARCH", text, length_count)

				name_search: for name, i in info.names {
					if name == text {
						data := rawptr(uintptr(v.data) + info.offsets[i])
						id := info.types[i].id
						unmarshal(ctx, any { data, id }, allocator)

						length_count += 1
						continue length_loop
					}
				}			

				// no matching parameter found
				length_count += 1
				_skip_any(ctx)
			}
		}

		case: {
			_skip_any(ctx)
		}
	}
}

// unmarshal_new :: proc(ctx: ^Read_Context, some_type: $T, allocator := context.allocator) -> ^T {
// 	result := new(T, allocator)
// 	unmarshal(ctx, result, allocator)
// 	return result
// }

unmarshal_new :: proc(ctx: ^Read_Context, $T: typeid, allocator := context.allocator) -> T {
    // result := new(T, allocator)
    result: T
    unmarshal(ctx, result, allocator)
    return result
}