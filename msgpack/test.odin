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
	write_ctx := write_context_scoped(capacity)
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
		test = read_typeid(ctx) or_return
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
		append(&test, 1)
		append(&test, 4)
		write_any(ctx, test) or_return

		return .None
	}

	read :: proc(ctx: ^Read_Context) -> Read_Error {
		test: [dynamic]int
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
		append(&test, 255)
		append(&test, 10)
		append(&test, 1)
		write_any(ctx, test) or_return

		return .None
	}

	read :: proc(ctx: ^Read_Context) -> Read_Error {
		test: [dynamic]u8
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
		test[0] = 255
		test[1] = 10
		write_any(ctx, test) or_return
		return .None
	}

	read :: proc(ctx: ^Read_Context) -> Read_Error {
		test: []int
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
		test[0] = 255
		test[1] = 10
		test[2] = 1
		write_any(ctx, test) or_return
		return .None
	}

	read :: proc(ctx: ^Read_Context) -> Read_Error {
		test: []u8
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

// test_map :: proc() {
// 	write :: proc() -> (bytes: []byte, err: msgpack.Write_Error) {
// 		ctx := msgpack.write_context_scoped(mem.megabytes(1))

// 		// test: map[string]int
// 		// test["asd"] = 1
// 		// test["xyz"] = 2
// 		// test: map[int]string
// 		// test[0] = "hello"
// 		// test[1] = "damn"
// 		test: map[int]u8
// 		test[0] = 255
// 		test[1] = 254
// 		msgpack.write_any(&ctx, test) or_return

// 		return msgpack.write_context_result(&ctx), .None
// 	}

// 	bytes, err := write()
// 	if err != .None {
// 		fmt.panicf("WRITE FAILED: %v", err)
// 	}

// 	os.write_entire_file("test.bin", bytes)

// 	{
// 		read_ctx := msgpack.read_context_init(bytes)
// 		// test: map[int]string
// 		// test: map[string]int
// 		test: map[int]u8
// 		fmt.println("before", test)
// 		msgpack.unmarshall(&read_ctx, test) or_return
// 		fmt.println("after", test, len(test), cap(test))
// 	}
// }
