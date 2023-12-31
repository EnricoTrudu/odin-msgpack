# odin-msgpack
Implementation of [msgpack](https://msgpack.org/) in [odin](https://odin-lang.org/)
Suport for `Writer` & `Reader` & `Un/Marshal` & `Extensions` 

# Tests
Basic test code can be found in `test.odin`, prints out `write` / `read` results mostly useful to check `un/marshal` support

# Basic Example 
```go
package main

import "core:fmt"
import msgpack "shared:odin-msgpack"

// or_return checks the call for a possible error, leaves early on error
// reader would have to read these in the same order
write :: proc(ctx: ^msgpack.Write_Context) -> (err: msgpack.Write_Error) {
	msgpack.write_int8(ctx, 10) or_return
	msgpack.write_nil(ctx) or_return
	msgpack.write_string(ctx, "test") or_return
	return
}

main :: proc() {
	ctx := msgpack.write_context_init(1024)
	defer msgpack.write_context_destroy(ctx)
    
	err := write(&ctx)
	if err != .None {
		fmt.panic("error: %v", err)
	}
    
	fmt.println(msgpack.write_context_result(ctx))
}
```

# Magic
```go
package main

import "core:fmt"
import msgpack "shared:odin-msgpack"

main :: proc() {
	Struct_A :: struct {
		a: int,
		b: bool,
	}

	// write write_data automatically into msgpack data
	write_data := Struct_A { a = 1, b = true }
	bytes, write_err := msgpack.marshal(write_data, 1024)
	defer delete(bytes)
	assert(write_err == .None)

	// read data automatically back into read_data
	read_data: Struct_A
	read_err := msgpack.unmarshal(read_data, bytes)
	assert(read_err == .None)

	// both are equal
	assert(write_data == read_data)
}
```

# Warning
msgpack is ***dynamic***, meaning you could have `array`s with different types or `map`s with different key / value pairs
odin does not support this, so whenever you expect dynamic results in arrays / maps you have to explicitly us the `reader` / `writer`

# Exception
`marshal` & `unmarshal` do read  / write dynamic msgpack data, i.e. a struct will be written to msgpack as a `string` + any odin data type
If you encounter issues with these, please write issues / pull requests
