package main

import "core:fmt"
import "core:os"
import "core:mem"
import "core:time"
import "core:strings"
import "core:container"
import msgpack "msgpack"
import rl "vendor:raylib"

last_modification_time: time.Time
modify_last_time :: proc(name: string) -> bool {
	fi, err := os.stat("test.bin", context.temp_allocator)
	if err == os.ERROR_NONE  {
		if last_modification_time != fi.modification_time {
			last_modification_time = fi.modification_time
			return true
		}
	} 

	return false
}

main :: proc() {
	// ctx := msgpack.write_context_scoped(mem.kilobytes(1))
	// result := test_write(&ctx)
	// if result != .None {
	// 	fmt.println("FAILED:", result)
	// }

	file_name := "test.bin"
	data, ok := os.read_entire_file(file_name)
	defer delete(data)
	assert(ok)

	modify_last_time(file_name)

	rl.SetTraceLogLevel(.WARNING)
	// rl.SetConfigFlags({ .VSYNC_HINT })
	rl.InitWindow(400, 800, "msgpack viewer")
	defer rl.CloseWindow()
	rl.SetTargetFPS(30)

	container.array_init_len_cap(&indents, 0, 32)
	y_offset: i32 = 20

	for !rl.WindowShouldClose() {
		rl.BeginDrawing()
		defer rl.EndDrawing()
	
		value := rl.GetMouseWheelMove()
		if value != 0 {
			y_offset += cast(i32) (value * 50)
		}
		
		rl.ClearBackground(rl.WHITE)

		if modify_last_time(file_name) {
			if new_data, ok := os.read_entire_file(file_name); ok {
				delete(data)
				data = new_data
				rl.DrawRectangle(0, 0, rl.GetScreenWidth(), rl.GetScreenHeight(), rl.RED)
			} else {
				panic("failed reading updated file")
			}
		}

		read_and_draw(data, 20, y_offset)

		// rl.DrawRectangle(0, 0, 100, 100, rl.RED)
		// rl.DrawText("yo guys", 100, 100, 20, rl.RED)		
	}
}

// attach 0 manually and use built string
cheat_cstring :: proc(builder: ^strings.Builder) -> cstring {
	strings.write_byte(builder, 0)
	return cstring(&builder.buf[0])
}

Indentation :: struct {
	is_array: bool,
	start: int,
	end: int,
}

indents: container.Array(Indentation)

indentation_check_step :: proc(y: ^i32, x_off: i32, step: int, text_size: i32) {
	if indents.len != 0 {
		current_indent := container.array_get(indents, indents.len - 1)
		
		// fmt.println(current_indent)
		if step > current_indent.end {
			indent := container.array_pop_back(&indents)
			
			y^ += text_size
			x := x_off + i32(indents.len) * text_size
			
			text: cstring = indent.is_array ? "]" : "}"
			color := indent.is_array ? rl.RED : rl.GREEN
			rl.DrawText(text, x, y^, text_size, color)

			indentation_check_step(y, x_off, step, text_size)
		}
	}
}

indentation_push :: proc(length: int, step: int, is_array: bool) {
	// increase length of previous indentation
	if indents.len != 0 {
		last_indent := container.array_get_ptr(indents, indents.len - 1)
		last_indent.end += length
	}

	// push new indentation
	container.array_push_back(&indents, Indentation { 
		is_array = is_array,
		start = step, 
		end = step + length,
	})
}

read_and_draw :: proc(bytes: []byte, x_off, y_off: i32) {
	x := x_off
	y := y_off
	measure_text: cstring
	measured_text_size: i32
	text_color := rl.BLACK
	text_size: i32 = 20
	ctx := msgpack.read_context_init(bytes)
	builder := strings.make_builder_len_cap(0, 64, context.temp_allocator)
	current_step: int

	container.array_clear(&indents)

	// fmt.println("----")
	for len(ctx.input) != 0 {
		b := ctx.input[0]
		
		format := msgpack.format_clamp(b)
		ctx.current_format = format
		
		x = x_off + i32(indents.len) * text_size

		indent: ^Indentation		
		if indents.len != 0 {
			indent = container.array_get_ptr(indents, indents.len - 1)
			step := current_step - indent.start

			if !indent.is_array && step % 2 == 0 {
				x += measured_text_size + text_size
				y -= text_size
			} 
		}

		// on scope end increase y and clear builder
		defer {
			current_step += 1
			indentation_check_step(&y, x_off, current_step, text_size)
			y += text_size

			if indent != nil && !indent.is_array && measure_text != "" {
				measured_text_size = rl.MeasureText(measure_text, text_size)
			}

			strings.reset_builder(&builder)	
		}

		#partial switch format {
			case .Fix_Array, .Array16, .Array32: {
				length := msgpack.read_array(&ctx)
				indentation_push(length, current_step, true)
				rl.DrawText("[", x, y, text_size, rl.RED)
				measure_text = "["
			}

			case .Fix_Map, .Map16, .Map32: {
				length := msgpack.read_map(&ctx)
				indentation_push(length * 2, current_step, false)
				rl.DrawText("{", x, y, text_size, rl.GREEN)
				measure_text = "{"
			}

			case .Nil: {
				rl.DrawText("nil", x, y, text_size, text_color)
				ctx.input = ctx.input[1:]
				measure_text = "nil"
			}

			case .Positive_Fix_Int, .Negative_Fix_Int, .Int8, .Int16, .Int32, .Int64: {
				value := msgpack.read_int(&ctx)
				fmt.sbprintf(&builder, "%d", value)
				text := cheat_cstring(&builder)
				rl.DrawText(text, x, y, text_size, text_color)
				measure_text = text
			}

			case .Uint8, .Uint16, .Uint32, .Uint64: {
				value := msgpack.read_uint(&ctx)
				fmt.sbprintf(&builder, "%d", value)
				text := cheat_cstring(&builder)
				rl.DrawText(text, x, y, text_size, text_color)
				measure_text = text
			}

			case .True, .False: {
				value := msgpack.read_bool(&ctx)
				text: cstring = value ? "true" : "false"
				rl.DrawText(text, x, y, text_size, text_color)
				measure_text = text
			}

			case .Fix_Str, .Str8, .Str16, .Str32: {
				text := msgpack.read_string(&ctx)
				strings.write_quoted_string(&builder, text)
				
				final_text := cheat_cstring(&builder)
				rl.DrawText(final_text, x, y, text_size, text_color)
				measure_text = final_text
			}

			case .Float32, .Float64: {
				if format == .Float32 {
					value := msgpack.read_float32(&ctx)
					fmt.sbprintf(&builder, "%f", value)
				} else {
					value := msgpack.read_float64(&ctx)
					fmt.sbprintf(&builder, "%f", value)
				}

				text := cheat_cstring(&builder)
				rl.DrawText(text, x, y, text_size, text_color)
				measure_text = text
			}

			case .Bin8, .Bin16, .Bin32: {
				data := msgpack.read_bin(&ctx)
				fmt.sbprintf(&builder, "%v", data)
				
				text := cheat_cstring(&builder)
				rl.DrawText(text, x, y, text_size, text_color)
				measure_text = text
			}

			// TODO extensions

			case: {
				panic("STOP WHAT YOURE DOING")
				// ctx.input = ctx.input[1:]
			}
		}

		// default 
	} 
}
