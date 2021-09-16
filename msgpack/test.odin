package msgpack

import "core:fmt"
import "core:mem"
import "core:os"

// helper to write / read back results
test_read_write :: proc(
	write: proc(ctx: ^Write_Context) -> Write_Error, 
	read: proc(ctx: ^Read_Context),
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
	defer read_context_destroy(&read_ctx)
	read(&read_ctx)
}

test_typeid :: proc() {
	write :: proc(ctx: ^Write_Context) -> Write_Error {
		write_context_add_typeid(ctx, int)
		write_context_add_typeid(ctx, u8)
		write_typeid(ctx, u8) or_return
		return .None
	}

	read :: proc(ctx: ^Read_Context) {
		read_context_add_typeid(ctx, int)
		read_context_add_typeid(ctx, u8)

		test: typeid
		fmt.println("before", test)
		test = read_typeid(ctx)
		fmt.println("after", test)
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

	read :: proc(ctx: ^Read_Context) {
		read_context_add_typeid(ctx, int)
		read_context_add_typeid(ctx, u8)

		test: Test
		fmt.println("before", test)
		unmarshal(ctx, test)
		fmt.println("after", test)
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

	read :: proc(ctx: ^Read_Context) {
		test: [dynamic]int
		fmt.println("before", test)
		unmarshal(ctx, test)
		fmt.println("after", test)
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
// 		msgpack.unmarshal(&read_ctx, test)
// 		fmt.println("after", test, len(test), cap(test))
// 	}
// }
