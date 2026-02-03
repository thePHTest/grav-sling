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

Sim_Ctx :: struct {
	tick_num : u64,
	frame_num : u64,
	frame_tick_num : u64,
	t : f64,
	dt : f64,
}

@(export)
game_update :: proc(tick_num : u64, frame_num : u64, frame_tick_num : u64, t : f64, dt : f64) {
	update(Sim_Ctx{tick_num, frame_num, frame_tick_num, t, dt})
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
game_on_hot_reload :: proc(mem: rawptr) {
	g_mem = (^Game_Memory)(mem)
	on_hot_reload()
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
