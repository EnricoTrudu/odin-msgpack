package main

import "core:fmt"
import "core:runtime"
import "core:mem"
import msgpack "msgpack"

// new feature: or_return by default on all functions
// #any_int documentation
// RTTI union
// RTTI bit_set
// RTTI map
// RTTI any -> any

main :: proc() {
	using msgpack
	
	track: mem.Tracking_Allocator
	mem.tracking_allocator_init(&track, context.allocator);
	context.allocator = mem.tracking_allocator(&track);
	defer check_leaks(&track);
	defer mem.tracking_allocator_destroy(&track);

	// test_temp()
	// test_enum_array_any()
	// test_typeid()
	// test_typeid_any()
	// test_dynamic_array()
	// test_array_any()
	// test_binary_array()
	// test_slice_any()
	// test_binary_dynamic_array()
	// test_binary_slice_any()
	// test_different_types_array()
	// test_map()
	test_map_any()
	// test_map_struct_any()
	// test_write()
	// test_temp()
	// test_rune()
	// test_write_struct
}

check_leaks :: proc(ta: ^mem.Tracking_Allocator) {
	if len(ta.allocation_map) > 0 {
		fmt.println("leaks:", len(ta.allocation_map));
		for _, v in ta.allocation_map {
			fmt.printf("%5d %v\n", v.size, v.location);
		}
	}
	
	if len(ta.bad_free_array) > 0 {
		fmt.println("bad frees:", len(ta.bad_free_array));
		for v in ta.bad_free_array {
			fmt.printf("%p %v\n", v.memory, v.location);
		}
	}
}
