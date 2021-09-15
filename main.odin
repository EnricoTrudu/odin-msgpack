package main

import "core:fmt"
import "core:os"
import "core:mem"
import "core:time"
import "core:strings"
import "core:container"
import msgpack "msgpack"

// dynamic array insertion
// test_dynamic_array_insertion :: proc() {
// 	write :: proc() -> (bytes: []byte, err: msgpack.Write_Error) {
// 		ctx := msgpack.write_context_scoped(mem.kilobytes(1))

// 		test: [dynamic]int
// 		append(&test, 1)
// 		append(&test, 4)
// 		msgpack.write_any(&ctx, test) or_return

// 		return msgpack.write_context_result(&ctx), .None
// 	}

// 	bytes, err := write()
// 	assert(err == .None)

// 	{
// 		read_ctx := msgpack.read_context_init(bytes)
// 		test: [dynamic]int
// 		fmt.println("before", test)
// 		msgpack.unmarshal(&read_ctx, test)
// 		fmt.println("after", test)
// 	}
// }

main :: proc() {
	write :: proc() -> (bytes: []byte, err: msgpack.Write_Error) {
		ctx := msgpack.write_context_scoped(mem.megabytes(1))

		// test: map[string]int
		// test["asd"] = 1
		// test["xyz"] = 2
		// test: map[int]string
		// test[0] = "hello"
		// test[1] = "damn"
		test: map[int]u8
		test[0] = 255
		test[1] = 254
		msgpack.write_any(&ctx, test) or_return

		return msgpack.write_context_result(&ctx), .None
	}

	bytes, err := write()
	if err != .None {
		fmt.panicf("WRITE FAILED: %v", err)
	}

	os.write_entire_file("test.bin", bytes)

	{
		read_ctx := msgpack.read_context_init(bytes)
		// test: map[int]string
		// test: map[string]int
		test: map[int]u8
		fmt.println("before", test)
		msgpack.unmarshal(&read_ctx, test)
		fmt.println("after", test)
	}
}
