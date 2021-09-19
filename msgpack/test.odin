package msgpack

import "core:fmt"
import "core:mem"
import "core:os"

// NOTE these are tests special read / writes and the automated write_any / unmarshall  or_return

// helper to write / read back results
test_read_write :: proc(
	write: proc(ctx: ^Write_Context) -> Write_Error, 
	read: proc(ctx: ^Read_Context) -> Read_Error,
	capacity: int,
) {
	write_ctx := write_context_init(capacity)
	defer write_context_destroy(&write_ctx)
	
	err := write(&write_ctx)
	if err != .None {
		fmt.panicf("WRITE FAILED: %v", err)
	}

	bytes := write_context_result(&write_ctx)
	// NOTE temporary, can be used to inspect with a viewer
	os.write_entire_file("test.bin", bytes)

	read_ctx := read_context_init(bytes)
	read_ctx.decoding = .Strict
	defer read_context_destroy(&read_ctx)
	read_err := read(&read_ctx)
	if read_err != .None {
		fmt.panicf("READ FAILED: %v", read_err)
	}
}

test_typeid :: proc() {
	write :: proc(ctx: ^Write_Context) -> Write_Error {
		write_context_add_typeid(ctx, int)
		write_context_add_typeid(ctx, u8)
		write_typeid(ctx, u8) or_return
		return .None
	}

	read :: proc(ctx: ^Read_Context) -> Read_Error {
		read_context_add_typeid(ctx, int)
		read_context_add_typeid(ctx, u8)

		test: typeid
		fmt.println("before", test)
		read_format(ctx) or_return
		type, bytes := read_fix_ext(ctx) or_return
		test = read_typeid(ctx, type, bytes) or_return
		fmt.println("after", test)
		return .None
	}

	test_read_write(write, read, mem.kilobytes(1))
}

test_typeid_any :: proc() {
	Test :: struct {
		a: typeid,
		b: typeid,
	}

	write :: proc(ctx: ^Write_Context) -> Write_Error {
		write_context_add_typeid(ctx, int)
		write_context_add_typeid(ctx, u8)

		test := Test {
			a = int,
			b = u8,
		}

		write_any(ctx, test) or_return
		return .None
	}

	read :: proc(ctx: ^Read_Context) -> Read_Error {
		read_context_add_typeid(ctx, int)
		read_context_add_typeid(ctx, u8)

		test: Test
		fmt.println("before", test)
		unmarshall(ctx, test) or_return
		fmt.println("after", test)
		return .None
	}

	test_read_write(write, read, mem.kilobytes(1))
}

test_dynamic_array :: proc() {
	write :: proc(ctx: ^Write_Context) -> Write_Error {
		test: [dynamic]int
		defer delete(test)
		append(&test, 1)
		append(&test, 4)
		write_any(ctx, test) or_return

		return .None
	}

	read :: proc(ctx: ^Read_Context) -> Read_Error {
		test: [dynamic]int
		defer delete(test)
		fmt.println("before", test)
		unmarshall(ctx, test) or_return
		fmt.println("after", test)
		return .None
	}

	test_read_write(write, read, mem.kilobytes(1))
}

test_binary_dynamic_array :: proc() {
	write :: proc(ctx: ^Write_Context) -> Write_Error {
		test: [dynamic]u8
		defer delete(test)
		append(&test, 255)
		append(&test, 10)
		append(&test, 1)
		write_any(ctx, test) or_return

		return .None
	}

	read :: proc(ctx: ^Read_Context) -> Read_Error {
		test: [dynamic]u8
		defer delete(test)
		fmt.println("before", test)
		unmarshall(ctx, test) or_return
		fmt.println("after", test)
		return .None
	}

	test_read_write(write, read, mem.kilobytes(1))
}

test_array_any :: proc() {
	write :: proc(ctx: ^Write_Context) -> Write_Error {
		test: [10]int
		test[0] = 255
		test[1] = 10
		write_any(ctx, test) or_return

		return .None
	}

	read_bad_size :: proc(ctx: ^Read_Context) -> Read_Error {
		test: [8]int
		fmt.println("before", test)
		unmarshall(ctx, test) or_return
		fmt.println("after", test)
		return .None
	}
	
	read_same_size :: proc(ctx: ^Read_Context) -> Read_Error {
		test: [10]int
		fmt.println("before", test)
		unmarshall(ctx, test) or_return
		fmt.println("after", test)
		return .None
	}

	test_read_write(write, read_bad_size, mem.kilobytes(1))		
	test_read_write(write, read_same_size, mem.kilobytes(1))		
}

test_enum_array_any :: proc() {
	Some_Enum :: enum {
		A = 3,
		B,
		C,
	}

	write :: proc(ctx: ^Write_Context) -> Write_Error {
		test: [Some_Enum]int
		test[.A] = 1
		test[.B] = 10
		test[.C] = 254
		write_any(ctx, test) or_return
		return .None
	}
	
	read :: proc(ctx: ^Read_Context) -> Read_Error {
		test: [Some_Enum]int
		fmt.println("before", test)
		unmarshall(ctx, test) or_return
		fmt.println("after", test)
		return .None
	}

	test_read_write(write, read, mem.kilobytes(1))		
}

test_binary_array :: proc() {
	write :: proc(ctx: ^Write_Context) -> Write_Error {
		test: [10]u8
		test[0] = 255
		test[1] = 10
		write_any(ctx, test) or_return
		return .None
	}

	read :: proc(ctx: ^Read_Context) -> Read_Error {
		test: [10]u8
		fmt.println("before", test)
		unmarshall(ctx, test) or_return
		fmt.println("after", test)
		return .None
	}

	test_read_write(write, read, mem.kilobytes(1))		
}

test_slice_any :: proc() {
	write :: proc(ctx: ^Write_Context) -> Write_Error {
		test := make([]int, 2)
		defer delete(test)
		test[0] = 255
		test[1] = 10
		write_any(ctx, test) or_return
		return .None
	}

	read :: proc(ctx: ^Read_Context) -> Read_Error {
		test: []int
		defer delete(test)
		fmt.println("before", test)
		unmarshall(ctx, test) or_return
		fmt.println("after", test)
		return .None
	}

	test_read_write(write, read, mem.kilobytes(1))		
}

test_binary_slice_any :: proc() {
	write :: proc(ctx: ^Write_Context) -> Write_Error {
		test := make([]u8, 3)
		defer delete(test)
		test[0] = 255
		test[1] = 10
		test[2] = 1
		write_any(ctx, test) or_return
		return .None
	}

	read :: proc(ctx: ^Read_Context) -> Read_Error {
		test: []u8
		defer delete(test)
		fmt.println("before", test)
		unmarshall(ctx, test) or_return
		fmt.println("after", test)
		return .None
	}

	test_read_write(write, read, mem.kilobytes(1))
}

test_different_types_array :: proc() {
	write :: proc(ctx: ^Write_Context) -> Write_Error {
		_write_array_format(ctx, 3) or_return
		write_nil(ctx) or_return
		write_int(ctx, i8(10)) or_return
		write_uint(ctx, u8(20)) or_return
		return .None
	}

	read :: proc(ctx: ^Read_Context) -> Read_Error {
		test: [3]i8
		fmt.println("before", test)
		unmarshall(ctx, test) or_return
		fmt.println("after", test)
		return .None
	}

	test_read_write(write, read, mem.kilobytes(1))
}

test_map :: proc() {
	write :: proc(ctx: ^Write_Context) -> Write_Error {
		if true {
			test: map[i8]u8
			test[0] = 255
			test[1] = 254
			write_any(ctx, test) or_return
		} else {
			_write_map_format(ctx, 2) or_return
			write_int8(ctx, 0) or_return 
			write_uint8(ctx, 255) or_return
			write_int8(ctx, 1) or_return 
			write_uint8(ctx, 254) or_return
		}

		return .None
	}

	read :: proc(ctx: ^Read_Context) -> Read_Error {
		// test: map[int]string
		// test: map[string]int
		test: map[i8]u8
		
		read_format(ctx) or_return
		length := read_map(ctx) or_return

		for i in 0..<length {
			read_format(ctx)
			key := read_int8(ctx) or_return
			read_format(ctx)
			value := read_uint8(ctx) or_return
			test[key] = value
		}
		
		fmt.println("after", test, len(test), cap(test))
		return .None
	}

	test_read_write(write, read, mem.kilobytes(1))
}

test_map_experimental :: proc() {
	write :: proc(ctx: ^Write_Context) -> Write_Error {
		test: map[i8]u8
		test[0] = 255
		test[1] = 254
		write_any(ctx, test) or_return
		return .None
	}

	read :: proc(ctx: ^Read_Context) -> Read_Error {
		test: map[i8]u8

		unmarshall(ctx, test) or_return
		// fmt.println("after", test, len(test), cap(test))
		return .None
	}

	test_read_write(write, read, mem.kilobytes(1))
}

test_write :: proc() -> Write_Error {
	ctx := write_context_init(mem.kilobytes(1))
	defer write_context_destroy(&ctx)

	// test_write_basics(&ctx) or_return
	// test_write_bytes(&ctx) or_return
	test_write_arrays(&ctx) or_return
	// test_write_map(&ctx) or_return
	// test_write_ext(&ctx) or_return
	// test_write_struct(&ctx) or_return

	os.write_entire_file("test.bin", write_context_result(&ctx))

	return .None
}

test_write_basics :: proc(ctx: ^Write_Context) -> Write_Error {
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

test_write_bytes :: proc(ctx: ^Write_Context) -> Write_Error {	
	write_fix_str(ctx, "yo guyssddddddddddddddddaaaaaaaaaaaaaaddddddd") or_return
	write_fix_str(ctx, "yo guys") or_return
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

test_write_arrays :: proc(ctx: ^Write_Context) -> Write_Error {
	a := [?]i32 { 10, 30 }
	write_any(ctx, a) or_return

	b := [?]f32 { 0.4, 0.1, -0.2 }
	write_any(ctx, b[:]) or_return

	c: [dynamic]string
	defer delete(c)
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

test_write_map :: proc(ctx: ^Write_Context) -> Write_Error {
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

test_write_ext :: proc(ctx: ^Write_Context) -> Write_Error {
	write_timestamp64(ctx, 120) or_return
	return .None
}

test_write_struct :: proc(ctx: ^Write_Context) -> Write_Error {
	TestInner :: struct {
		c: u8,
		d: u32,
	}

	Testing :: struct {
		a: int,
		b: string,
		inner: TestInner,
	}

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

test_rune :: proc() {
	write :: proc(ctx: ^Write_Context) -> Write_Error {
		write_any(ctx, rune('a'))
		return .None
	}

	read :: proc(ctx: ^Read_Context) -> Read_Error {
		test: rune = 'b'
		fmt.println("before", test)
		unmarshall(ctx, test) or_return
		fmt.println("after", test)
		return .None
	}

	test_read_write(write, read, mem.kilobytes(1))
}

// test_quaternion :: proc() {
// 	write :: proc(ctx: ^Write_Context) -> Write_Error {
// 		write_any(ctx, rune('a'))
// 		return .None
// 	}

// 	read :: proc(ctx: ^Read_Context) -> Read_Error {
// 		test: rune = 'b'
// 		fmt.println("before", test)
// 		unmarshall(ctx, test) or_return
// 		fmt.println("after", test)
// 		return .None
// 	}

// 	test_read_write(write, read, mem.kilobytes(1))
// }

test_temp :: proc() {
	write :: proc(ctx: ^Write_Context) -> Write_Error {
		// write_any(ctx, test)
		return .None
	}

	read :: proc(ctx: ^Read_Context) -> Read_Error {
		// test: Some_Struct
		// test.d = new_clone(4)
		// fmt.println("before", test)
		// unmarshall(ctx, test) or_return
		// fmt.println("after", test, test.b^, test.d^, test.e^)
		return .None
	}

	test_read_write(write, read, mem.kilobytes(1))
}