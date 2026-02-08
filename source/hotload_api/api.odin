package hotload_api

import "core:fmt"
import "core:log"
import "core:mem"
import "core:os"
import "core:os/os2"
import "base:runtime"
import "core:dynlib"

_ :: fmt
_ :: log
_ :: mem
_ :: os
_ :: os2
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
	copy_err := os2.copy_file(to, GAME_DLL_PATH)

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

	if os.remove(fmt.tprintf("game_{0}" + DLL_EXT, api.api_version)) != nil {
		fmt.printfln("Failed to remove game_{0}" + DLL_EXT + " copy", api.api_version)
	}
}


Hotload_Result :: enum {
	Hotload,
	Full_Reset,
	Load_Failed,
	No_Hotload,
	Exit,
}

Game_API :: struct {
	lib: dynlib.Library,
	platform_init : proc(platform_allocator : ^mem.Allocator) -> rawptr,
	mem_reset: proc(raw_platform_memory : rawptr) -> rawptr,
	reset: proc(),
	hotload_main_loop: proc(raw_platform_memory : rawptr, raw_game_memory : rawptr, game_api : Game_API) -> (Game_API, Hotload_Result),
	memory_size: proc() -> int,
	unload: proc(),
	shutdown: proc(raw_game_memory : rawptr),
	modification_time: os.File_Time,
	api_version: int,
}

}
