package game

import "core:log"
import "base:runtime"

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
game_poll_input :: proc() {
	context = g_context
	poll_input()
}

Sim_Ctx :: struct {
	tick_num : u64,
	frame_num : u64,
	frame_tick_num : u64,
	t : f64,
	dt : f64,
}

@(export)
game_update :: proc(tick_num : u64, frame_num : u64, frame_tick_num : u64, t : f64, dt : f64) {
	context = g_context
	update(Sim_Ctx{tick_num, frame_num, frame_tick_num, t, dt})
}

@(export)
game_render :: proc(alpha : f64) {
	context = g_context
	render(alpha)
}

// TODO: Should this move into platform?
@(export)
game_hi_res_time_in_seconds :: proc "contextless" () -> f64 {
	return hi_res_time_in_seconds()
}

@(export)
game_should_close :: proc "contextless" () -> bool {
	return g_mem.finished
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
