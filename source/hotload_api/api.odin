package hotload_api

import "core:log"
import "base:runtime"

GAME_DLL_DIR :: "build/hot_reload/"
GAME_DLL_PATH :: GAME_DLL_DIR + "game" + DLL_EXT

Hotload_Result :: enum {
	Hotload,
	Full_Reset,
	Load_Failed,
	No_Hotload,
	Exit,
}

Game_API :: struct {
	lib: dynlib.Library,
	init_memory : proc(game_memory : rawptr),
	init: proc(game_allocator : runtime.Allocator),
	reset: proc(),
	hotload_main: proc(game_api : Game_API) -> hotload_api.Hotload_Result,
	shutdown: proc(),
	shutdown_window: proc(),
	memory_size: proc() -> int,
	on_hot_reload: proc(mem: rawptr, game_allocator : runtime.Allocator),
	unload: proc(),
	force_hotload: proc() -> bool,
	force_reset: proc() -> bool,
	modification_time: os.File_Time,
	api_version: int,
}

@(export)
game_hotload_main :: proc(game_api : Game_API) -> hotload_api.Hotload_Result {
	return hotload_main(game_api)
}

@(export)
game_init_memory :: proc "contextless" (game_memory : rawptr) {
	init_memory(cast(^Game_Memory)game_memory)
}

@(export)
game_init :: proc(game_allocator : runtime.Allocator) {
	context.allocator = game_allocator
	g_context = context
	log.info("game_init...")
	init()
	log.info("game_init complete")
}

@(export)
game_reset :: proc() {
	context = g_context
	log.info("game_reset()...")
	reset()
	log.info("game_reset() complete.")
}

@(export)
game_shutdown :: proc() {
	context = g_context
	shutdown()
}

@(export)
game_shutdown_window :: proc() {
	context = g_context
	shutdown_window()
}

@(export)
game_memory_size :: proc "contextless" () -> int {
	return size_of(Game_Memory)
}

@(export)
game_on_hot_reload :: proc(mem: rawptr, game_allocator : runtime.Allocator) {
	context.allocator = game_allocator
	g_context = context

	g_mem = (^Game_Memory)(mem)
	log.info("Start on_hot_reload()")
	on_hot_reload()
	log.info("End on_hot_reload()")
}

@(export)
game_unload :: proc() {
	context = g_context
	unload()
}

@(export)
game_force_hotload :: proc() -> bool {
	return keyboard_is_key_pressed(g_keyboard, .F5)
}

@(export)
game_force_reset :: proc() -> bool {
	return keyboard_is_key_pressed(g_keyboard, .F6)
}

@(export)
parent_window_size_changed :: proc "c" (w, h: int) {
	// TODO:
	//rl.SetWindowSize(i32(w), i32(h))
}
