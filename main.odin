package main

import "core:fmt"
import "core:runtime"
import msgpack "msgpack"

// or_return by default on all functions
// #any_int documentation

main :: proc() {
	msgpack.test_enum_array_any()

	// msgpack.test_typeid()
	// msgpack.test_typeid_any()
	// msgpack.test_dynamic_array()
	// msgpack.test_array_any()
	// msgpack.test_binary_array()
	// msgpack.test_slice_any()
	// msgpack.test_binary_dynamic_array()
	// msgpack.test_binary_slice_any()
	// msgpack.test_different_types_array()
	// msgpack.test_map()
	// msgpack.test_map_experimental()
	// msgpack.test_write()
	// msgpack.test_temp()
	// msgpack.test_rune()

	// { // Quaternion operations
	// 	q := 1 + 2i + 3j + 4k
	// 	r := quaternion(5, 6, 7, 8)
	// 	t := q * r
	// 	fmt.printf("(%v) * (%v) = %v\n", q, r, t)
	// 	v := q / r
	// 	fmt.printf("(%v) / (%v) = %v\n", q, r, v)
	// 	u := q + r
	// 	fmt.printf("(%v) + (%v) = %v\n", q, r, u)
	// 	s := q - r
	// 	fmt.printf("(%v) - (%v) = %v\n", q, r, s)
	// }
}
