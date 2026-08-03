package hotload_api

import "base:runtime"
import "core:fmt"
import "core:log"
import "core:mem"
import "core:os"
import "core:time"
import "core:dynlib"

_ :: fmt
_ :: log
_ :: mem
_ :: os
_ :: runtime
_ :: dynlib

HOTLOAD :: #config(HOTLOAD, true)

when HOTLOAD {

GAME_DLL_DIR :: "build/hot_reload/"
GAME_DLL_PATH :: GAME_DLL_DIR + "game" + DLL_EXT
when ODIN_OS == .Windows {
	DLL_EXT :: ".dll"
} else when ODIN_OS == .Darwin {
	DLL_EXT :: ".dylib"
} else {
	DLL_EXT :: ".so"
}

// We copy the DLL because using it directly would lock it, which would prevent
// the compiler from writing to it.
copy_dll :: proc(to: string) -> bool {
	copy_err := os.copy_file(to, GAME_DLL_PATH)

	if copy_err != nil {
		fmt.printfln("Failed to copy " + GAME_DLL_PATH + " to {0}: %v", to, copy_err)
		return false
	}

	return true
}


load_game_api :: proc(api_version: int) -> (api: Game_API, ok: bool) {
	mod_time, mod_time_error := os.last_write_time_by_name(GAME_DLL_PATH)
	if mod_time_error != os.ERROR_NONE {
		log.errorf(
			"Failed getting last write time of " + GAME_DLL_PATH + ", error code: {1}\n",
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

	if os.remove(fmt.tprintf(GAME_DLL_DIR + "game_{0}" + DLL_EXT, api.api_version)) != nil {
		fmt.printfln("Failed to remove " + GAME_DLL_DIR + "game_{0}" + DLL_EXT + " copy", api.api_version)
	}
}

Reload :: enum {
	None,
	Hot,
	Reset,
}

Game_API :: struct {
	lib: dynlib.Library,
	init: proc(platform_ctx: runtime.Context) -> rawptr, // returns opaque ^Hotload_Memory
	tick: proc(handle: rawptr),
	should_quit: proc(handle: rawptr) -> bool,
	unload_for_hotload: proc(handle: rawptr),
	unload_for_reset: proc(handle: rawptr),
	rebuild_memory: proc(handle: rawptr, platform_ctx: runtime.Context), // full reset. Rebuilds g_mem in place
	shutdown: proc(handle: rawptr, platform_ctx: runtime.Context),
	hot_reloaded: proc(handle: rawptr, platform_ctx: runtime.Context), // rebind after a hot swap 
	force_reload: proc(handle: rawptr) -> bool,
	force_reset: proc(handle: rawptr) -> bool,
	memory_size: proc() -> int,
	platform_size: proc() -> int,
	modification_time: time.Time,
	api_version: int,
}

check_for_reload :: proc(cur_api: Game_API, handle: rawptr) -> (Game_API, Reload){
	changed := false
	mod_time, err := os.last_write_time_by_name(GAME_DLL_PATH)
	if err == os.ERROR_NONE && cur_api.modification_time != mod_time {
		changed = true
	}

	force_hot := cur_api.force_reload(handle)
	force_reset := cur_api.force_reset(handle)
	if !(changed || force_hot || force_reset) {
		return {}, .None
	}

	new_api, ok := load_game_api(cur_api.api_version + 1)
	if !ok {
		// Keep running the old dll on load failure
		return {}, .None
	}

	if force_reset || (new_api.memory_size() != cur_api.memory_size()) || (new_api.platform_size() != cur_api.platform_size()) {
		return new_api, .Reset
	}

	return new_api, .Hot
}

}
