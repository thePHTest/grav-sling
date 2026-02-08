/*
Development game exe. Loads build/hot_reload/game.dll and reloads it whenever it
changes.
*/

package main

HOTLOAD :: #config(HOTLOAD, true)
MEMORY_TRACKING :: #config(MEMORY_TRACKING, true)

import "../hotload_api"
import "../mem_tracking"

import "core:os"
import "core:os/os2"
import "core:log"
import "core:mem"
import "core:path/filepath"


main :: proc() {
	// Set working dir to dir of executable.
	exe_path := os.args[0]
	exe_dir := filepath.dir(string(exe_path), context.temp_allocator)
	os.set_current_directory(exe_dir)

	context.logger = log.create_console_logger()
	log.info("Console logger created")

	platform_allocator := os2.heap_allocator()
when MEMORY_TRACKING {
	platform_tracking_allocator : mem.Tracking_Allocator
	mem.tracking_allocator_init(&platform_tracking_allocator, platform_allocator)
	platform_allocator = mem.tracking_allocator(&platform_tracking_allocator)
}
	context.allocator = platform_allocator

	game_api, game_api_ok := hotload_api.load_game_api(0)

	if !game_api_ok {
		log.error("Failed to load Game API")
		return
	}

	// We need to keep the old game dlls around so that things like string literals
	// and source code lcations (used by the tracking allocator) stick around
	old_game_apis := make([dynamic]hotload_api.Game_API)

	log.info("before platform_init")
	raw_platform_memory := game_api.platform_init(&platform_allocator)
	raw_game_memory := game_api.mem_reset(raw_platform_memory)

	loop: for {
		new_game_api, hotload_result := game_api.hotload_main_loop(raw_platform_memory, raw_game_memory, game_api)
		switch hotload_result {
		case .Hotload: {
			append(&old_game_apis, game_api)
			//game_api.unload()
			game_api = new_game_api
		}
		case .Full_Reset: {
			//game_api.unload()
			//game_api.shutdown(raw_game_memory)
			for &old_game_api in old_game_apis {
				hotload_api.unload_game_api(&old_game_api)
			}
			clear(&old_game_apis)
			hotload_api.unload_game_api(&game_api)
			game_api = new_game_api
			raw_game_memory = game_api.mem_reset(raw_platform_memory)
		}
		case .Exit: {
			break loop
		}
		case .Load_Failed:
			log.error("Should not receive .Load_Failed in hotload host exe")
		case .No_Hotload:
			log.error("Should not receive .No_Hotload in hotload host exe")
		}
	}

	when MEMORY_TRACKING {
		if len(platform_tracking_allocator.bad_free_array) > 0 {
			for b in platform_tracking_allocator.bad_free_array {
				log.errorf("Exe Bad free at: %v", b.location)
			}

			panic("Exe Bad free detected")
		}
	}

	free_all(context.temp_allocator)

	for &old_game_api in old_game_apis {
		hotload_api.unload_game_api(&old_game_api)
	}
	delete(old_game_apis)
	hotload_api.unload_game_api(&game_api)

when MEMORY_TRACKING {
	if mem_tracking.reset_tracking_allocator(&platform_tracking_allocator) {
	}
}
	mem.tracking_allocator_destroy(&platform_tracking_allocator)
	log.info("exit")
}

// Make game use good GPU on laptops.

@(export)
NvOptimusEnablement: u32 = 1

@(export)
AmdPowerXpressRequestHighPerformance: i32 = 1
