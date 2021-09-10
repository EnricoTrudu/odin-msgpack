package main

import "core:fmt"
import "core:os"
import "core:mem"
import "core:time"
import "core:strings"
import "core:container"
import msgpack "msgpack"

test_write :: proc(ctx: ^msgpack.Write_Context) -> msgpack.Write_Error {
	// msgpack.write_bool(ctx, true) or_return
	// msgpack.write_bool(ctx, false) or_return
	// msgpack.write_any(ctx, []u8 { 0, 1, 3, 4 }) or_return
	
	// msgpack.write_any(ctx, [?][2]f32 { { 0, 1 }, { 1, 0 }}) or_return
	
	// some_map: map[string]int
	// defer delete(some_map)
	// some_map["yo"] = 10
	// some_map["how you doin"] = 20
	// some_map["dam son"] = 50
	// some_map["wat"] = 20

	// msgpack.write_any(ctx, some_map) or_return
	// msgpack.write_int8(ctx, 10) or_return
	// msgpack.write_nil(ctx) or_return
	
	// msgpack.write_any(ctx, nil) or_return
	// msgpack.write_int8(ctx, 20) or_return
	// msgpack.write_any(ctx, 10) or_return
	// msgpack.write_str8(ctx, "yo guys") or_return

	// Inner_Struct :: struct {
	// 	a, b, c: int,
	// }
	// Test :: struct {
	// 	a: int,
	// 	b: f32,
	// 	d: [4]u8,
	// 	e: Inner_Struct,
	// 	c: string,
	// 	f: [3][2]f32,
	// };
	// test := Test { 
	// 	a = 0, 
	// 	b = 1.0, 
	// 	c = "odin",
	// 	d = { 1, 2, 3, 4 },
	// 	e = { 3, 2, 1 },
	// 	f = { 1.+0, 0.4, -1 },
	// }
	// msgpack.write_any(ctx, test)

	// msgpack.write_any(ctx, []int { 0, 1, 3 }) or_return
	// msgpack.write_any(ctx, []int { 0, 1, 3 }) or_return
	// msgpack.write_any(ctx, "damn son") or_return
	// msgpack.write_str8(ctx, "sup") or_return

	test := Test_A {
		a = 1,
		b = 24,
		c = "damn son",
		d = [4]i8 { 1, 2, 3, 4 },
	}
	msgpack.write_any(ctx, test)

	// msgpack.write_any(ctx, [4]i8 { 1, 2, 3, 4 })

	return .None
}

Test_A :: struct {
	a: uint,
	b: i8,
	c: string,
	d: [4]i8,
	// b: f32,
}

Test_B :: struct {
	a: uint,
	b: f32,
	c: string,
	// d: [dynamic]i8,
	// b: f32,
}
	
main :: proc() {
	ctx := msgpack.write_context_scoped(mem.kilobytes(1))
	result := test_write(&ctx)
	if result != .None {
		fmt.println("FAILED:", result)
	}
	
	ok := os.write_entire_file("test.bin", msgpack.write_context_result(&ctx))
	assert(ok)

	{
		read_ctx := msgpack.read_context_init(msgpack.write_context_result(&ctx))
		// test: Test_B
		// fmt.println("before", test)
		// msgpack.unmarshal(&read_ctx, test)
		// fmt.println("after", test)
		test := msgpack.unmarshal_new(&read_ctx, Test_B)
		fmt.println(test)
		// test := msgpack.unmarshal_new(ctx, i8)
	}

	// {
	// 	read_ctx := msgpack.read_context_init(msgpack.write_context_result(&ctx))
	// 	test: [4]i8
	// 	fmt.println("before", test)
	// 	msgpack.unmarshal(&read_ctx, test)
	// 	fmt.println("after", test)
	// }
}
