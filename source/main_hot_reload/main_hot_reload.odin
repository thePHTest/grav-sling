/*
Development game exe. Loads build/hot_reload/game.dll and reloads it whenever it
changes.
*/

package main

HOTLOAD :: #config(HOTLOAD, true)
MEMORY_TRACKING :: #config(MEMORY_TRACKING, true)

import "../hotload_api"
import "../mem_tracking"
import "../config"

import "core:fmt"
import "core:os"
import "core:log"
import "core:mem"


main :: proc() {
	host_exe_allocator := os.heap_allocator()
when MEMORY_TRACKING {
	host_exe_tracking_allocator : mem.Tracking_Allocator
	mem.tracking_allocator_init(&host_exe_tracking_allocator, host_exe_allocator)
	host_exe_allocator = mem.tracking_allocator(&host_exe_tracking_allocator)
}
	context.allocator = host_exe_allocator


	game_api, game_api_ok := hotload_api.load_game_api(0)
	if !game_api_ok {
		fmt.println("Failed to load Game API")
		return
	}

	// We need to keep the old game dlls around so that things like string literals
	// and source code lcations (used by the tracking allocator) stick around
	old_game_apis := make([dynamic]hotload_api.Game_API)

	platform_context := config.startup()
	raw_hotload_memory : rawptr
	new_game_api : hotload_api.Game_API
	hotload_result := hotload_api.Hotload_Result.Launch
	loop: for {
		raw_hotload_memory, new_game_api, hotload_result = game_api.hotload_main_loop(raw_hotload_memory, game_api, hotload_result, platform_context)
		switch hotload_result {
		case .Launch:
		case .Hotload: {
			append(&old_game_apis, game_api)
			game_api = new_game_api
		}
		case .Full_Reset: {
			for &old_game_api in old_game_apis {
				hotload_api.unload_game_api(&old_game_api)
			}
			clear(&old_game_apis)
			hotload_api.unload_game_api(&game_api)
			game_api = new_game_api
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
		if len(host_exe_tracking_allocator.bad_free_array) > 0 {
			for b in host_exe_tracking_allocator.bad_free_array {
				log.errorf("Host exe Bad free at: %v", b.location)
			}

			panic("Host exe Bad free detected")
		}
	}

	free_all(context.temp_allocator)

	for &old_game_api in old_game_apis {
		hotload_api.unload_game_api(&old_game_api)
	}
	delete(old_game_apis)
	hotload_api.unload_game_api(&game_api)

when MEMORY_TRACKING {
	if mem_tracking.reset_tracking_allocator(&host_exe_tracking_allocator) {
	}
}
	mem.tracking_allocator_destroy(&host_exe_tracking_allocator)
	fmt.println("exit")
}

// Make game use good GPU on laptops.

@(export)
NvOptimusEnablement: u32 = 1

@(export)
AmdPowerXpressRequestHighPerformance: i32 = 1
