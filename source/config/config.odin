package config

import "base:runtime"
import "core:log"
import "core:mem"
import "core:os"
import "core:path/filepath"

import "../mem_tracking"

MEMORY_TRACKING :: #config(MEMORY_TRACKING, true)
_ :: mem_tracking

g_platform_tracking_allocator : mem.Tracking_Allocator

init :: proc() -> runtime.Context {
	// Set working directory to exe
	exe_path := os.args[0]
	exe_dir := filepath.dir(string(exe_path))
	os.set_working_directory(exe_dir)

	logger := log.create_console_logger()
	context.logger = logger
	log.info("Console logger created")

	// Configure platform allocator
	platform_allocator := os.heap_allocator()
when MEMORY_TRACKING {
	mem.tracking_allocator_init(&g_platform_tracking_allocator, platform_allocator, platform_allocator)
	platform_allocator = mem.tracking_allocator(&g_platform_tracking_allocator)
}
	context.allocator = platform_allocator

	return context

}

shutdown :: proc(platform_context : runtime.Context) {
	context = platform_context

when MEMORY_TRACKING {
	if mem_tracking.reset_tracking_allocator(&g_platform_tracking_allocator) {
	}
	mem.tracking_allocator_destroy(&g_platform_tracking_allocator)
}
}
