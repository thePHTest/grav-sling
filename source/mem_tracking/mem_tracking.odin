package mem_tracking

MEMORY_TRACKING :: #config(MEMORY_TRACKING, true)

import "core:log"
import "core:mem"
import "core:slice"
import "core:strings"

_ :: log
_ :: mem
_ :: slice
_ :: strings

when MEMORY_TRACKING {
reset_tracking_allocator :: proc(a: ^mem.Tracking_Allocator) -> bool {
	err := false

	for _, value in a.allocation_map {
		log.warnf("%v: [Leaked %v bytes]\n    [String]: \"%s\"\n    [Bytes]:  \"%v\"\n", value.location, value.size,
		strings.string_from_ptr(cast([^]u8)value.memory, value.size), slice.bytes_from_ptr(value.memory, value.size))
		err = true
	}

	mem.tracking_allocator_clear(a)
	return err
}
}
