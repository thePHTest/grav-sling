package game

import sdl "vendor:sdl3"

hi_res_time_in_seconds :: proc() -> f64 {
	@(static) start_counter : u64
	@(static) frequency : u64
	// TODO: Way to avoid this if check overhead? Does it matter?
	if start_counter == 0 {
		start_counter = sdl.GetPerformanceCounter()
		frequency = sdl.GetPerformanceFrequency()
	}

	current_counter := sdl.GetPerformanceCounter()
	return f64(current_counter - start_counter) / f64(frequency)
}


