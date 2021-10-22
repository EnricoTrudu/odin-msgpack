package msgpack

import "core:fmt"
import "core:mem"
import "core:runtime"

// write array info based on any recursive
_marshal_array_any :: proc(ctx: ^Write_Context, length: int, root: uintptr, offset_size: int, id: typeid) -> Write_Error {
	for i in 0..<length {
		data := root + uintptr(i * offset_size)

		result := marshal_ctx(ctx, any { rawptr(data), id })
		if result	!= .None {
			return result
		}
	}

	return .None
}

marshal :: proc(v: any, cap: int) -> (data: []byte, err: Write_Error) {
	ctx := write_context_scoped(cap)
	marshal_ctx(&ctx, v) or_return
	data = write_context_result(ctx)
	return
}

marshal_ctx :: proc(using ctx: ^Write_Context, v: any) -> Write_Error {
	if v == nil {
		return write_nil(ctx)
	}

	ti := runtime.type_info_base(type_info_of(v.id))

	// check custom typeid writers
	if len(typeid_any) != 0 {
		if call, ok := typeid_any[ti.id]; ok {
			call(ctx, v) or_return
			return .None
		} 
	}

	#partial switch info in ti.variant {
		case runtime.Type_Info_Pointer: {
			return .Pointer_Unsupported
		}

		case runtime.Type_Info_Integer: {
			switch i in v {
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
			switch f in v {
				case f16: return write_float32(ctx, f32(f))
				case f32: return write_float32(ctx, f)
				case f64: return write_float64(ctx, f)
			}
		} 

		case runtime.Type_Info_String: {
			switch s in v {
				case string: {
					return write_string(ctx, s)
				}
				case cstring: return write_string(ctx, string(s))
			}
		}

		case runtime.Type_Info_Rune: {
			some_rune := v.(rune)
			write_rune(ctx, some_rune) or_return
			return .None
		}

		case runtime.Type_Info_Boolean: {
			switch b in v {
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
				return _marshal_array_any(ctx, length, uintptr(v.data), info.elem_size, info.elem.id) 
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
				return _marshal_array_any(ctx, length, uintptr(v.data), info.elem_size, info.elem.id)
			}
		}

		// write array format and fill data per inner any element
		case runtime.Type_Info_Slice: {
			slice := (^mem.Raw_Slice)(v.data)
			length := slice.len
			
			// skip array element is byte and write .Bin*
			if info.elem.id == byte {
				_write_bin_format(ctx, length) or_return
				return write_bytes(ctx, slice.data, length)
			} else {
				_write_array_format(ctx, length) or_return
				return _marshal_array_any(ctx, length, uintptr(slice.data), info.elem_size, info.elem.id) 
			}
		}

		// write array format and fill data per inner any element
		case runtime.Type_Info_Dynamic_Array: {
			array := (^mem.Raw_Dynamic_Array)(v.data)
			length := array.len
			
			if info.elem.id == byte {
				_write_bin_format(ctx, length) or_return
				return write_bytes(ctx, array.data, length) 
			} else {
				_write_array_format(ctx, length) or_return
				return _marshal_array_any(ctx, length, uintptr(array.data), info.elem_size, info.elem.id) 
			}	
		}

		// similar to `core:encoding/json`
		case runtime.Type_Info_Map: {
			m := (^mem.Raw_Map)(v.data)
			
			if m == nil || info.generated_struct == nil {
				return .Any_Type_Unsupported
			}

			entries := &m.entries
			gs := runtime.type_info_base(info.generated_struct).variant.(runtime.Type_Info_Struct)
			ed := runtime.type_info_base(gs.types[1]).variant.(runtime.Type_Info_Dynamic_Array)
			entry_type := ed.elem.variant.(runtime.Type_Info_Struct)
			entry_size := ed.elem_size

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
				marshal_ctx(ctx, any{ key, info.key.id }) or_return
				marshal_ctx(ctx, any{ value, info.value.id }) or_return
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
					// add custom tag behaviour
					if info.tags[i] == "skip" {
						continue struct_loop
					}
				}

				write_string(ctx, name) or_return

				id := info.types[i].id
				data := rawptr(uintptr(v.data) + info.offsets[i])
				marshal_ctx(ctx, any { data, id }) or_return
			}

			return .None
		}

		case runtime.Type_Info_Type_Id: {
			type := v.(typeid)
			write_typeid(ctx, type) or_return
			return .None
		}

		case: {
			if ctx.verbose {
				fmt.println("ANY_TYPE_UNSUPPORTED", v)
			}

			return .Any_Type_Unsupported
		}
	}

	return .Any_Type_Not_Matched
}
