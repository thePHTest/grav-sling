/*
Development game exe. Loads build/hot_reload/game.dll and reloads it whenever it
changes.
*/

package main

import "base:runtime"
import "core:dynlib"
import "core:fmt"
//import "core:c/libc"
import "core:os"
import "core:os/os2"
import "core:log"
import "core:mem"
import "core:path/filepath"
import "core:slice"
import "core:strings"

when ODIN_OS == .Windows {
	DLL_EXT :: ".dll"
} else when ODIN_OS == .Darwin {
	DLL_EXT :: ".dylib"
} else {
	DLL_EXT :: ".so"
}

GAME_DLL_DIR :: "build/hot_reload/"
GAME_DLL_PATH :: GAME_DLL_DIR + "game" + DLL_EXT

MEMORY_TRACKING :: true

// We copy the DLL because using it directly would lock it, which would prevent
// the compiler from writing to it.
copy_dll :: proc(to: string) -> bool {
	copy_err := os2.copy_file(to, GAME_DLL_PATH)

	if copy_err != nil {
		fmt.printfln("Failed to copy " + GAME_DLL_PATH + " to {0}: %v", to, copy_err)
		return false
	}

	return true
}

Game_API :: struct {
	lib: dynlib.Library,
	init_memory : proc(game_memory : rawptr),
	init: proc(game_allocator : runtime.Allocator),
	reset: proc(),
	poll_input : proc(),
	update: proc(tick_num : u64, frame_num : u64, frame_tick_num : u64, t : f64, dt : f64),
	render: proc(alpha : f64),
	hi_res_time_in_seconds : proc() -> f64,
	should_close: proc() -> bool,
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

load_game_api :: proc(api_version: int) -> (api: Game_API, ok: bool) {
	mod_time, mod_time_error := os.last_write_time_by_name(GAME_DLL_PATH)
	if mod_time_error != os.ERROR_NONE {
		fmt.printfln(
			"Failed getting last write time of " + GAME_DLL_PATH + ", error code: {1}",
			mod_time_error,
		)
		return
	}

	game_dll_name := fmt.tprintf(GAME_DLL_DIR + "game_{0}" + DLL_EXT, api_version)
	copy_dll(game_dll_name) or_return

	// This proc matches the names of the fields in Game_API to symbols in the
	// game DLL. It actually looks for symbols starting with `game_`, which is
	// why the argument `"game_"` is there.
	_, ok = dynlib.initialize_symbols(&api, game_dll_name, "game_", "lib")
	if !ok {
		fmt.printfln("Failed initializing symbols: {0}", dynlib.last_error())
	}

	api.api_version = api_version
	api.modification_time = mod_time
	ok = true

	return
}

unload_game_api :: proc(api: ^Game_API) {
	if api.lib != nil {
		if !dynlib.unload_library(api.lib) {
			fmt.printfln("Failed unloading lib: {0}", dynlib.last_error())
		}
	}

	if os.remove(fmt.tprintf("game_{0}" + DLL_EXT, api.api_version)) != nil {
		fmt.printfln("Failed to remove game_{0}" + DLL_EXT + " copy", api.api_version)
	}
}

Hotload_Result :: enum {
	No_Hotload,
	Load_Failed,
	Hotload,
	Full_Reset,
}

game_hotload :: proc(game_api : ^Game_API) -> (Game_API, Hotload_Result) {
	force_hotload := game_api.force_hotload()
	force_reset := game_api.force_reset()
	reload := force_hotload || force_reset
	game_dll_mod, game_dll_mod_err := os.last_write_time_by_name(GAME_DLL_PATH)

	if game_dll_mod_err == os.ERROR_NONE && game_api.modification_time != game_dll_mod {
		reload = true
	}

	if reload {
		new_game_api, new_game_api_ok := load_game_api(game_api.api_version + 1)

		if new_game_api_ok {
			force_reset = force_reset || game_api.memory_size() != new_game_api.memory_size()

			if !force_reset {
				// This does the normal hot reload
				return new_game_api, .Hotload
			} else {
				// This does a full reset. That's basically like opening and
				// closing the game, without having to restart the executable.
				//
				// You end up in here if the game requests a full reset OR
				// if the size of the game memory has changed. That would
				// probably lead to a crash anyways.
				return new_game_api, .Full_Reset
			}

		}
		return {}, .Load_Failed
	}
	return {}, .No_Hotload
}

reset_tracking_allocator :: proc(a: ^mem.Tracking_Allocator) -> bool {
	err := false

	for _, value in a.allocation_map {
		fmt.printf("%v: [Leaked %v bytes]\n    [String]: \"%s\"\n    [Bytes]:  \"%v\"\n", value.location, value.size,
		strings.string_from_ptr(cast([^]u8)value.memory, value.size), slice.bytes_from_ptr(value.memory, value.size))
		err = true
	}

	mem.tracking_allocator_clear(a)
	return err
}

main :: proc() {
	exe_allocator := os2.heap_allocator()
when MEMORY_TRACKING {
	exe_tracking_allocator : mem.Tracking_Allocator
	mem.tracking_allocator_init(&exe_tracking_allocator, exe_allocator)
	exe_allocator = mem.tracking_allocator(&exe_tracking_allocator)
}
	context.allocator = exe_allocator

	// Set working dir to dir of executable.
	exe_path := os.args[0]
	exe_dir := filepath.dir(string(exe_path), context.temp_allocator)
	os.set_current_directory(exe_dir)

	context.logger = log.create_console_logger()
	log.info("Console logger created")

	game_allocator := os2.heap_allocator()
when MEMORY_TRACKING {
	game_tracking_allocator: mem.Tracking_Allocator
	mem.tracking_allocator_init(&game_tracking_allocator, game_allocator)
	game_allocator = mem.tracking_allocator(&game_tracking_allocator)
}

	game_api, game_api_ok := load_game_api(0)

	if !game_api_ok {
		fmt.println("Failed to load Game API")
		return
	}

	game_memory, alloc_err := mem.alloc(game_api.memory_size(), allocator = game_allocator)
	if alloc_err != .None {
		log.error("Could not allocate game memory. Error:", alloc_err)
		os.exit(-1)
	}
	game_api.init_memory(game_memory)
	game_api.init(game_allocator)
	game_api.reset()

	tick_num, frame_num, frame_tick_num : u64 = 0, 0, 0
	t : f64 = 0.0
	dt : f64 = 0.01
	current_time : f64 = game_api.hi_res_time_in_seconds()
	accumulator : f64 = 0.0

	// We need to keep the old game dlls around so that things like string literals
	// and source code lcations (used by the tracking allocator) stick around
	old_game_apis := make([dynamic]Game_API)
	for !game_api.should_close() {
		frame_tick_num = 0

		game_api.poll_input()

		new_time : f64
		frame_time : f64
		// Check for reload
		if new_game_api, hotload_result := game_hotload(&game_api); hotload_result != .No_Hotload {
			switch hotload_result {
			case .No_Hotload:
			case .Load_Failed:
				log.error("Hotload game api failed")
			case .Hotload:
				append(&old_game_apis, game_api)
				game_api.unload()
				game_api = new_game_api
				game_api.on_hot_reload(game_memory, game_allocator)
			case .Full_Reset:
				game_api.shutdown()
			when MEMORY_TRACKING {
				reset_tracking_allocator(&game_tracking_allocator)
			}
				for &old_game_api in old_game_apis {
					unload_game_api(&old_game_api)
				}
				clear(&old_game_apis)
				unload_game_api(&game_api)
				game_api = new_game_api
				game_api.init(game_allocator)
			}
			new_time = game_api.hi_res_time_in_seconds()
			// Let's just reset frame_time to 0.0  when a reload happens
			frame_time = 0.0
		} else {
			new_time = game_api.hi_res_time_in_seconds()
			frame_time = new_time - current_time
		}

		// TODO: Move 0.25 to config
		if frame_time > 0.25 {
			frame_time = 0.25
		}
		current_time = new_time
		accumulator += frame_time

		for accumulator >= dt {
			game_api.update(tick_num, frame_num, frame_tick_num, t, dt)
			t += dt
			accumulator -= dt
			tick_num += 1
			frame_tick_num += 1
		}
		alpha : f64 = accumulator / dt
		game_api.render(alpha)

		
	when MEMORY_TRACKING {
		if len(game_tracking_allocator.bad_free_array) > 0 {
			for b in game_tracking_allocator.bad_free_array {
				log.errorf("Game Bad free at: %v", b.location)
			}

			panic("Game Bad free detected")
		}
		if len(exe_tracking_allocator.bad_free_array) > 0 {
			for b in exe_tracking_allocator.bad_free_array {
				log.errorf("Exe Bad free at: %v", b.location)
			}

			panic("Exe Bad free detected")
		}
	}

		free_all(context.temp_allocator)
		frame_num += 1
	}

	free_all(context.temp_allocator)
	game_api.shutdown()
	game_api.shutdown_window()

when MEMORY_TRACKING {
	if reset_tracking_allocator(&game_tracking_allocator) {
	}
	mem.tracking_allocator_destroy(&game_tracking_allocator)

	for &old_game_api in old_game_apis {
		unload_game_api(&old_game_api)
	}
	delete(old_game_apis)
	unload_game_api(&game_api)

	if reset_tracking_allocator(&exe_tracking_allocator) {
	}
}

	mem.tracking_allocator_destroy(&exe_tracking_allocator)
	log.info("exit")
}

// Make game use good GPU on laptops.

@(export)
NvOptimusEnablement: u32 = 1

@(export)
AmdPowerXpressRequestHighPerformance: i32 = 1
