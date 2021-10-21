package msgpack

import "core:fmt"
import "core:os"
import "core:mem"
import "core:strings"

// see https://github.com/msgpack/msgpack/blob/master/spec.md

// all msgpack formats stored before data is appended
// some of these include upcoming data length (i.e. Fix_Map, Fix_Array, ...)
Format :: enum u8 {
	Positive_Fix_Int = 0x00, // 0x00 - 0x80 positive 7 bit integer

	Fix_Map = 0x80,
	Fix_Array = 0x90,
	Fix_Str = 0xa0,
	
	Nil = 0xc0,
	
	False = 0xc2,
	True = 0xc3,

	Bin8 = 0xc4,
	Bin16 = 0xc5,
	Bin32 = 0xc6,

	Ext8 = 0xc7,
	Ext16 = 0xc8,
	Ext32 = 0xc9,

	Float32 = 0xca,
	Float64 = 0xcb,

	Uint8 = 0xcc,
	Uint16 = 0xcd,
	Uint32 = 0xce,
	Uint64 = 0xcf,

	Int8 = 0xd0,
	Int16 = 0xd1,
	Int32 = 0xd2,
	Int64 = 0xd3,

	Fix_Ext1 = 0xd4,
	Fix_Ext2 = 0xd5,
	Fix_Ext4 = 0xd6,
	Fix_Ext8 = 0xd7,
	Fix_Ext16 = 0xd8,

	Str8 = 0xd9,
	Str16 = 0xda,
	Str32 = 0xdb,

	Array16 = 0xdc,
	Array32 = 0xdd,
	
	Map16 = 0xde,
	Map32 = 0xdf,

	Negative_Fix_Int = 0xe0, // 0xe0 - 0xff negative 5 bit integer
}

// byte size per fix format
_fix_ext_size :: #force_inline proc(format: Format) -> int {
	#partial switch format {
		case .Fix_Ext1: return 1
		case .Fix_Ext2: return 2
		case .Fix_Ext4: return 4
		case .Fix_Ext8: return 8
		case .Fix_Ext16: return 16
	}

	fmt.panicf("WRONG FORMAT SUPPLIED %x %v", byte(format), format)
}

// custom extensions
Extension :: enum i8 {
	Timestamp = -1, // NOTE not fully supported
	
	// writer -> typeid = u8
	// reader -> u8 = typeid
	// converts typeid back and forth between u8 / typeid
	// both read / write have to know about the typeid and its number
	Type_Id = 0,
}