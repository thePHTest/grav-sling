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

_ :: mem_tracking
_ :: log
_ :: mem


main :: proc() {
	host_exe_allocator := os.heap_allocator()
when MEMORY_TRACKING {
	host_exe_tracking_allocator : mem.Tracking_Allocator
	mem.tracking_allocator_init(&host_exe_tracking_allocator, host_exe_allocator)
	host_exe_allocator = mem.tracking_allocator(&host_exe_tracking_allocator)
}
	context.allocator = host_exe_allocator

	platform_context := config.init()
	game_api, game_api_ok := hotload_api.load_game_api(0)
	if !game_api_ok {
		fmt.println("Failed to load Game API")
		return
	}

	// We need to keep the old game dlls around so that things like string literals
	// and source code lcations (used by the tracking allocator) stick around
	old_game_apis := make([dynamic]hotload_api.Game_API)

	handle := game_api.init(platform_context)
	for !game_api.should_quit(handle) {
		game_api.tick(handle)

		new_game_api, reload_result := hotload_api.check_for_reload(game_api, handle)
		switch reload_result {
		case .None:
		case .Hot:
			append(&old_game_apis, game_api)
			game_api.unload_for_hotload(handle)
			game_api = new_game_api
			game_api.hot_reloaded(handle, platform_context)
		case .Reset:
			game_api.unload_for_reset(handle)
			prev_game_api := game_api
			game_api = new_game_api
			game_api.rebuild_memory(handle, platform_context)
			game_api.hot_reloaded(handle, platform_context)
			for &old_game_api in old_game_apis {
				hotload_api.unload_game_api(&old_game_api)
			}
			clear(&old_game_apis)
			hotload_api.unload_game_api(&prev_game_api)
		}
	}
	game_api.shutdown(handle, platform_context)
	config.shutdown(platform_context)

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
	mem.tracking_allocator_destroy(&host_exe_tracking_allocator)
}
	fmt.println("exit")
}

// Make game use good GPU on laptops.

@(export)
NvOptimusEnablement: u32 = 1

@(export)
AmdPowerXpressRequestHighPerformance: i32 = 1
