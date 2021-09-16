package msgpack

import "core:fmt"
import "core:os"
import "core:mem"
import "core:strings"

// see https://github.com/msgpack/msgpack/blob/master/spec.md

Format :: enum u8 {
	Positive_Fix_Int = 0x00, // 0x00 - 0x80 positive 7 bit integer

	Fix_Map = 0x80,
	Fix_Array = 0x90,
	Fix_Str = 0xa0,
	
	Nil = 0xc0,
	
	False = 0xc2,
	True = 0xc3,

	Bin8 = 0xc4,
	Bin16 = 0xc5,
	Bin32 = 0xc6,

	Ext8 = 0xc7,
	Ext16 = 0xc8,
	Ext32 = 0xc9,

	Float32 = 0xca,
	Float64 = 0xcb,

	Uint8 = 0xcc,
	Uint16 = 0xcd,
	Uint32 = 0xce,
	Uint64 = 0xcf,

	Int8 = 0xd0,
	Int16 = 0xd1,
	Int32 = 0xd2,
	Int64 = 0xd3,

	Fix_Ext1 = 0xd4,
	Fix_Ext2 = 0xd5,
	Fix_Ext4 = 0xd6,
	Fix_Ext8 = 0xd7,
	Fix_Ext16 = 0xd8,

	Str8 = 0xd9,
	Str16 = 0xda,
	Str32 = 0xdb,

	Array16 = 0xdc,
	Array32 = 0xdd,
	
	Map16 = 0xde,
	Map32 = 0xdf,

	Negative_Fix_Int = 0xe0, // 0xe0 - 0xff negative 5 bit integer
}

// byte size per fix format
_fix_ext_size :: #force_inline proc(format: Format) -> int {
	#partial switch format {
		case .Fix_Ext1: return 1
		case .Fix_Ext2: return 2
		case .Fix_Ext4: return 4
		case .Fix_Ext8: return 8
		case .Fix_Ext16: return 16
	}

	panic("wrong format")
}

test :: proc() -> Write_Error {
	ctx := write_context_scoped(mem.kilobytes(1))

	// write_nil(&ctx)
	// test_basics(&ctx) or_return
	// test_bytes(&ctx) or_return
	// test_arrays(&ctx) or_return
	// test_map(&ctx) or_return
	// test_ext(&ctx) or_return
	test_struct(&ctx) or_return

	os.write_entire_file("test.bin", write_context_result(&ctx))

	// read(write_context_result(&ctx))

	return .None
}

test_basics :: proc(ctx: ^Write_Context) -> Write_Error {
	write_bool(ctx, false) or_return
	write_nil(ctx) or_return
	write_positive_fix_int(ctx, 127) or_return
	write_negative_fix_int(ctx, 4) or_return

	write_uint8(ctx, 10) or_return
	write_uint16(ctx, 42_312) or_return
	write_uint32(ctx, 223_123_102) or_return
	write_uint64(ctx, 223_123_102) or_return

	write_int8(ctx, 10) or_return
	write_int16(ctx, 22_312) or_return
	write_int32(ctx, 200_123_102) or_return
	write_int64(ctx, 223_123_102) or_return

	write_float32(ctx, 120.23) or_return
	write_float64(ctx, 323_231_230.23) or_return

	return .None
}

test_bytes :: proc(ctx: ^Write_Context) -> Write_Error {	
	write_fix_str(ctx, "yo guyssddddddddddddddddaaaaaaaaaaaaaaddddddd") or_return
	write_str8(ctx, "yoooooo") or_return
	write_str16(ctx, "you get it") or_return
	write_str32(ctx, "sup guys") or_return

	write_bin(ctx, { 1, 132, 123, 123 }) or_return
	
	garbage := make([]byte, 256)
	garbage[len(garbage) - 1] = 1
	defer delete(garbage)
	write_bin(ctx, garbage[:]) or_return

	return .None	
}

test_arrays :: proc(ctx: ^Write_Context) -> Write_Error {
	a := [?]i32 { 10, 30 }
	write_any(ctx, a) or_return

	b := [?]f32 { 0.4, 0.1, -0.2 }
	write_any(ctx, b[:]) or_return

	c: [dynamic]string
	append(&c, "yo")
	append(&c, "damn")
	write_any(ctx, c) or_return

	d := [?][2]f32 { {1, 0}, {0, 1}, {0, 3} }
	write_any(ctx, d) or_return

	// arrays / slices / dynamic arrays of u8 should not create array formats
	// rather .Bin* formats
	data := [?]u8 { 1, 132, 123, 123 }
	write_any(ctx, data) or_return
	write_bin(ctx, data[:]) or_return

	return .None
}

test_map :: proc(ctx: ^Write_Context) -> Write_Error {
	a: map[string]int
	defer delete(a)
	a["first"] = 1
	a["second"] = 2
	write_any(ctx, a) or_return

	b: map[int][4]u8
	defer delete(b)
	b[1] = { 1, 2, 3, 4 }
	b[2] = { 4, 3, 2, 1 }
	write_any(ctx, b) or_return

	return .None
}

test_ext :: proc(ctx: ^Write_Context) -> Write_Error {
	write_timestamp64(ctx, 120) or_return
	return .None
}

test_struct :: proc(ctx: ^Write_Context) -> Write_Error {
	TestInner :: struct {
		c: u8,
		d: u32,
	}

	Testing :: struct {
		a: int,
		b: string,
		inner: TestInner,
	};

	test := Testing { 
		a = 10, 
		b = "yo guys",
		inner = {
			c = 244,
			d = 100_000,
		},
	}
	write_any(ctx, test) or_return

	return .None
}
