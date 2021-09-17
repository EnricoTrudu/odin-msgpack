package main

import "core:fmt"
import "core:os"
import "core:mem"
import "core:time"
import "core:strings"
import "core:container"
import msgpack "msgpack"

// try write_any with []any, dynamic array of dynamic types? possible by msgpack

main :: proc() {
	// msgpack.test_typeid()
	// msgpack.test_typeid_any()
	// msgpack.test_dynamic_array()
	// msgpack.test_array_any()
	// msgpack.test_binary_array()
	// msgpack.test_slice_any()
	// msgpack.test_binary_dynamic_array()
	// msgpack.test_binary_slice_any()
	msgpack.test_different_types_array()
}
