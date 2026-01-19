package game

@(export)
game_init :: proc() {
	init()
}

@(export)
game_init_window :: proc() {
	init_window()
}

@(export)
game_poll_input :: proc() {
	poll_input()
}

@(export)
game_update :: proc(t : f64, dt : f64) {
	update(t, dt)
}

@(export)
game_render :: proc(alpha : f64) {
	render(alpha)
}

// TODO: Should this move into platform?
@(export)
game_hi_res_time_in_seconds :: proc() -> f64 {
	return hi_res_time_in_seconds()
}

@(export)
game_should_close :: proc() -> bool {
	// TODO
	return g_mem.finished
}

@(export)
game_shutdown :: proc() {
	shutdown()
}

@(export)
game_shutdown_window :: proc() {
	shutdown_window()
}

@(export)
game_memory :: proc() -> rawptr {
	return g_mem
}

@(export)
game_memory_size :: proc() -> int {
	return size_of(Game_Memory)
}

@(export)
game_hot_reloaded :: proc(mem: rawptr) {
	g_mem = (^Game_Memory)(mem)
	refresh_globals()
}

@(export)
game_force_reload :: proc() -> bool {
	// TODO
	return false
	//return rl.IsKeyPressed(.F5)
}

@(export)
game_force_restart :: proc() -> bool {
	// TODO
	return false
	//return rl.IsKeyPressed(.F6)
}

@(export)
parent_window_size_changed :: proc "c" (w, h: int) {
	// TODO:
	//rl.SetWindowSize(i32(w), i32(h))
}
