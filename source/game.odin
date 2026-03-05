package game

HOTLOAD :: #config(HOTLOAD, true)
MEMORY_TRACKING :: #config(MEMORY_TRACKING, true)

import "hotload_api"
import "mem_tracking"
import "config"

import "base:runtime"
import b2 "box2d"
//import rl "vendor:raylib"
import sdl "vendor:sdl3"
import im "deps:odin-imgui"
import "core:log"
import "core:c"
//import "core:math"
import "core:mem"
import "core:os"
import "core:os/os2"
import "core:strings"

when HOTLOAD {
	_ :: config
} else {
	_ :: hotload_api
}

GAME_TITLE :: "GravSling"
PIXEL_WINDOW_HEIGHT :: 1080

RENDERER_SDL_GPU :: false

// Hotload exports
when HOTLOAD {

Hotload_Memory :: struct {
	platform : ^Platform_State, // Persistent platform data. Never reset
	g_mem : ^Game_Memory, // Game data that can be hard reset
}

@(export)
game_hotload_main_loop :: proc(raw_hotload_memory : rawptr, game_api : hotload_api.Game_API, hotload_result :
hotload_api.Hotload_Result, platform_context : runtime.Context) -> (new_raw_hotload_memory : rawptr, new_game_api : hotload_api.Game_API, new_hotload_result : hotload_api.Hotload_Result) {
	context = platform_context
	hotload_memory : ^Hotload_Memory
	if hotload_result == .Launch {
		platform, g_mem := startup(platform_context.allocator)

		hotload_memory = new(Hotload_Memory)
		hotload_memory.platform = platform
		hotload_memory.g_mem = g_mem
	} else {
		hotload_memory = cast(^Hotload_Memory)raw_hotload_memory

		if hotload_result == .Full_Reset {
			hotload_memory.g_mem = g_mem_reset(hotload_memory.platform)
		}
	}

	log.info("hotload_main_loop()...")

	context.allocator = hotload_memory.g_mem.allocator
	g_context = context
	return hotload_main_loop(hotload_memory, game_api)
}

@(export)
game_memory_size :: proc() -> int {
	return size_of(Game_Memory)
}

unload :: proc() {
	im_shutdown()
}

force_hotload :: proc() -> bool {
	return keyboard_is_key_pressed(g_keyboard, .F4)
}

force_reset:: proc() -> bool {
	return keyboard_is_key_pressed(g_keyboard, .F5)
}

hotload :: proc(game_api : hotload_api.Game_API, platform_allocator : mem.Allocator) -> (hotload_api.Game_API, hotload_api.Hotload_Result) {
	context.allocator = platform_allocator

	force_hotload := force_hotload()
	force_reset := force_reset()
	reload := force_hotload || force_reset
	game_dll_mod, game_dll_mod_err := os.last_write_time_by_name(hotload_api.GAME_DLL_PATH)

	if game_dll_mod_err == os.ERROR_NONE && game_api.modification_time != game_dll_mod {
		reload = true
	}

	if reload {
		new_game_api, new_game_api_ok := hotload_api.load_game_api(game_api.api_version + 1)

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

hotload_main_loop :: proc(hotload_memory : ^Hotload_Memory, game_api : hotload_api.Game_API) -> (raw_hotload_memory : rawptr, new_game_api : hotload_api.Game_API, hotload_result : hotload_api.Hotload_Result) {
	platform := hotload_memory.platform
	g_mem := hotload_memory.g_mem

	// On hot-reload code
	im_init(platform)

	// Main loop
	g_mem.sim_ctx.current_time = hi_res_time_in_seconds()
	g_mem.sim_ctx.accumulator = 0.0
	for !game_should_close(g_mem) {

		poll_input(platform, g_mem)

		// Check for reload                                   
		new_game_api, hotload_result = hotload(game_api, platform.allocator)
		switch hotload_result {
		case .Launch:
		case .Hotload:
			unload()
			return rawptr(hotload_memory), new_game_api, hotload_result
		case .Full_Reset:
			unload()
			g_mem_shutdown(platform, g_mem)
			return rawptr(hotload_memory), new_game_api, hotload_result
		case .Load_Failed:
			log.error("Hotload game api failed")          
		case .No_Hotload:
			// Do nothing
		case .Exit:
			// Should not be returned by hotload(...)
		}

		update_and_render(platform, g_mem)

		on_frame_end(platform, g_mem)
	}

	on_shutdown(platform, g_mem)
	log.info("hotload_main_loop() .Exit")
	return nil, {}, .Exit
}
}

when !HOTLOAD {
main :: proc() {
	context = config.startup()
	platform, g_mem := startup(context.allocator)

	im_init(platform)

	g_mem.sim_ctx.current_time = hi_res_time_in_seconds()
	g_mem.sim_ctx.accumulator = 0.0
	for !game_should_close(g_mem) {
		poll_input(platform, g_mem)
		update_and_render(platform, g_mem)
		on_frame_end(platform, g_mem)
	}

	on_shutdown(platform, g_mem)
	config.shutdown(context)
}
}

startup :: proc(platform_allocator : runtime.Allocator) -> (^Platform_State, ^Game_Memory) {
	platform := platform_init(platform_allocator)
	g_mem := g_mem_reset(platform)

	return platform, g_mem
}


Wall :: struct {
	body: b2.BodyId,
	shape: b2.ShapeId,
	rect: Rect,
	rot: f32,
}

Pivot :: struct {
	body: b2.BodyId,
	shape: b2.ShapeId,
	pos: Vec2,
	radius: f32,
}

when MEMORY_TRACKING {
Memory_Tracking :: struct {
	tracking_allocator : mem.Tracking_Allocator,
}
} else {
	Memory_Tracking :: struct {}
}

// This is data that must persist across hard resets
Platform_State :: struct {

	// TODO: Can't use when here
//when RENDERER_SDL_GPU {
//gpu_device: ^sdl.GPUDevice
//} else {
//sdl_renderer: ^sdl.Renderer
//}
	renderer : ^sdl.Renderer,
	window : ^sdl.Window,

	allocator : runtime.Allocator,

	platform_memory_tracking : Memory_Tracking,
	game_memory_tracking : Memory_Tracking,
}

Game_Memory :: struct {
	sim_ctx : Sim_Ctx,

	physics_world: b2.WorldId,
	starting_pos: Vec2,
	avatar: Avatar,
	ball: Ball,
	
	pivots: [dynamic]Pivot,
	
	left_wall: Wall,
	right_wall: Wall,
	top_wall: Wall,
	bottom_wall: Wall,

	time_accumulator: f32,

	won: bool,
	won_at: f64,

	finished: bool,

	allocator : runtime.Allocator,
}

g_context : runtime.Context


Camera2D :: struct {
	offset:   Vec2,            // Camera offset (displacement from target)
	target:   Vec2,            // Camera target (rotation and zoom origin)
	rotation: f32,                // Camera rotation in degrees
	zoom:     f32,                // Camera zoom (scaling), should be 1.0f by default
}

game_camera :: proc() -> Camera2D {
	//w := f32(rl.GetScreenWidth())
	//h := f32(rl.GetScreenHeight())

	return {
		zoom = 10.0,
		//zoom = h/PIXEL_WINDOW_HEIGHT*GAME_SCALE,
		//offset = { w/2, h/2 },
	}
}

get_screen :: proc(window : ^sdl.Window) -> Vec2 {
	w, h : i32
	sdl.GetWindowSizeInPixels(window, &w, &h)
	return Vec2{f32(w), f32(h)}
}

ui_camera :: proc() -> Camera2D {
	assert(false, "unimplemented")
	return {
		//zoom = f32(rl.GetScreenHeight())/PIXEL_WINDOW_HEIGHT,
	}
}

physics_world :: proc(g_mem : ^Game_Memory) -> b2.WorldId {
	return g_mem.physics_world
}

poll_input :: proc(platform : ^Platform_State, g_mem : ^Game_Memory) {
	// Reset pressed/released
	g_gamepad.buttons_pressed = {}
	g_gamepad.buttons_released = {}

	// Poll and handle events (inputs, window resize, etc.)
	// You can read the io.WantCaptureMouse, io.WantCaptureKeyboard flags to tell if dear imgui wants to use your inputs.
	// - When io.WantCaptureMouse is true, do not dispatch mouse input data to your main application, or clear/overwrite your copy of the mouse data.
	// - When io.WantCaptureKeyboard is true, do not dispatch keyboard input data to your main application, or clear/overwrite your copy of the keyboard data.
	// Generally you may always pass all inputs to dear imgui, and hide them from your application based on those two flags.
	// [If using SDL_MAIN_USE_CALLBACKS: call ImGui_ImplSDL3_ProcessEvent() from your SDL_AppEvent() function]
	event : sdl.Event
	for sdl.PollEvent(&event) {
		ImGui_ImplSDL3_ProcessEvent(&event)
		if event.type == .QUIT {
		}
		if event.type == .WINDOW_CLOSE_REQUESTED && event.window.windowID == sdl.GetWindowID(platform.window) {
		}

		#partial switch event.type {
			case .QUIT:
				log.info(".QUIT Event. Should close now")
				g_mem.finished = true
			case .WINDOW_CLOSE_REQUESTED:
				log.info(".WINDOW_CLOSE_REQUESTED Event. Should close now")
				g_mem.finished = true
			case .GAMEPAD_ADDED:
			g_gamepad.joystick_id = event.gdevice.which
			g_gamepad.sdl_gamepad = sdl.OpenGamepad(event.gdevice.which)
			case .GAMEPAD_REMOVED:
			// TODO
			case .GAMEPAD_BUTTON_DOWN:
			fallthrough
			case .GAMEPAD_BUTTON_UP:
			if event.gbutton.down {
				g_gamepad.buttons_pressed[EGamepadButton(event.gbutton.button)] = event.gbutton.down 
				g_gamepad.buttons_down[EGamepadButton(event.gbutton.button)] = event.gbutton.down 
			} else {
				g_gamepad.buttons_released[EGamepadButton(event.gbutton.button)] = event.gbutton.down 
				g_gamepad.buttons_down[EGamepadButton(event.gbutton.button)] = event.gbutton.down 
			}

			case .GAMEPAD_AXIS_MOTION:
			g_gamepad.axes[EGamepadAxis(event.gaxis.axis)].pos = event.gaxis.value

			case .KEY_DOWN:
			fallthrough
			case .KEY_UP:
			log.info(event.key)
			g_keyboard.keys[EScancode(event.key.scancode)].pressed = event.key.down
		}
	}

	// [If using SDL_MAIN_USE_CALLBACKS: all code below would likely be your SDL_AppIterate() function]
	if .MINIMIZED in sdl.GetWindowFlags(platform.window) {
		sdl.Delay(10)
		return
	}
}

platform_init :: proc(platform_allocator : runtime.Allocator) -> ^Platform_State {
	log.info("platform_init()...")
	platform, alloc_err := new(Platform_State)
	if alloc_err != .None {
		log.error("Could not allocate platform state. Error:", alloc_err)
		os.exit(-1)
	}

	platform.allocator = platform_allocator
	if !sdl_init(platform, platform_allocator) {
		log.error("Failed to init sdl. Exit.")
		os.exit(-1)
	}

	log.info("platform_init() complete.")
	return platform
}

platform_shutdown :: proc(platform : ^Platform_State) {
	context.allocator = platform.allocator
	free(platform)
}

game_should_close :: proc(g_mem : ^Game_Memory) -> bool {
	return g_mem.finished
}

on_frame_end :: proc(platform : ^Platform_State, g_mem : ^Game_Memory) {
	free_all(context.temp_allocator)
	g_mem.sim_ctx.frame_num += 1
}

on_shutdown :: proc(platform : ^Platform_State, g_mem : ^Game_Memory) {
	im_shutdown()
	g_mem_shutdown(platform, g_mem)
	sdl_shutdown(platform, platform.allocator)
when MEMORY_TRACKING {
	if mem_tracking.reset_tracking_allocator(&platform.game_memory_tracking.tracking_allocator) {
	}
	mem.tracking_allocator_destroy(&platform.game_memory_tracking.tracking_allocator)
	platform_shutdown(platform)
}
}

update_and_render :: proc(platform : ^Platform_State, g_mem : ^Game_Memory) {
	g_mem.sim_ctx.frame_tick_num = 0

	new_time : f64 = hi_res_time_in_seconds()
	frame_time : f64 = new_time - g_mem.sim_ctx.current_time

	// TODO: Move 0.25 to config
	if frame_time > 0.25 {
		frame_time = 0.25
	}
	g_mem.sim_ctx.current_time = new_time
	g_mem.sim_ctx.accumulator += frame_time

	for g_mem.sim_ctx.accumulator >= g_mem.sim_ctx.dt {
		update(g_mem)
		g_mem.sim_ctx.t += g_mem.sim_ctx.dt
		g_mem.sim_ctx.accumulator -= g_mem.sim_ctx.dt
		g_mem.sim_ctx.tick_num += 1
		g_mem.sim_ctx.frame_tick_num += 1
	}
	alpha : f64 = g_mem.sim_ctx.accumulator / g_mem.sim_ctx.dt

	render(platform, g_mem, alpha)
		
	when MEMORY_TRACKING {
		if len(platform.game_memory_tracking.tracking_allocator.bad_free_array) > 0 {
			for b in platform.game_memory_tracking.tracking_allocator.bad_free_array {
				log.errorf("Game Bad free at: %v", b.location)
			}

			panic("Game Bad free detected")
		}
		if len(platform.platform_memory_tracking.tracking_allocator.bad_free_array) > 0 {
			for b in platform.platform_memory_tracking.tracking_allocator.bad_free_array {
				log.errorf("Exe Bad free at: %v", b.location)
			}

			panic("Exe Bad free detected")
		}
	}
}

Sim_Ctx :: struct {
	tick_num : u64,
	frame_num : u64,
	frame_tick_num : u64,
	t : f64,
	dt : f64,

	current_time : f64,
	accumulator : f64,
}

show_demo_window := false
show_another_window := false
clear_color := [3]f32{0.45, 0.55, 0.60}
update :: proc(g_mem : ^Game_Memory) {
	if g_mem.sim_ctx.frame_tick_num > 0 {
		// TODO: Is this the best way to represent not pressed this tick?
		g_gamepad.buttons_pressed = {}
	}
	b2.World_Step(physics_world(g_mem), f32(g_mem.sim_ctx.dt), 4)	
	avatar_update(g_mem, &g_mem.avatar, g_mem.sim_ctx, g_mem.pivots, g_mem.physics_world)
	ball_update(&g_mem.ball)
}

Collision_Category :: enum u32 {
	Wall,
	Avatar,
	Ball,
	Pivot,
}

wall_render :: proc(renderer : ^sdl.Renderer, wall : Wall, camera : Camera2D, screen : Vec2) {
	screen_rect := rect_world_to_screen(wall.rect, camera, screen)
	sdl.SetRenderDrawColor(renderer, 0, 255, 0, 255)
	sdl.RenderFillRect(renderer, cast(^sdl.FRect)&screen_rect)
}

pivot_render :: proc(renderer : ^sdl.Renderer, pivot: Pivot, camera : Camera2D, screen : Vec2) {
	render_circle_filled(renderer, pivot.pos, pivot.radius, camera, screen)
}

world_render :: proc(g_mem : Game_Memory, renderer : ^sdl.Renderer, camera : Camera2D, screen : Vec2, alpha : f64) {
	// Draw the origin
	//render_circle_filled(renderer, {}, 1.0, camera, screen)


	avatar_render(renderer, g_mem.avatar, camera, screen, alpha)
	wall_render(renderer, g_mem.left_wall, camera, screen)
	wall_render(renderer, g_mem.right_wall, camera, screen)
	wall_render(renderer, g_mem.top_wall, camera, screen)
	wall_render(renderer, g_mem.bottom_wall, camera, screen)
	
	for pivot in g_mem.pivots {
		pivot_render(renderer, pivot, camera, screen)
	}

	ball_render(renderer, g_mem.ball, camera, screen, alpha)
	
	// Origin
	//rl.DrawCircle(0,0, 0.5 + 0.5*((1.0 + math.sin(f32(rl.GetTime()))) / 2.0), rl.BLACK)
}

render :: proc(platform : ^Platform_State, g_mem : ^Game_Memory, alpha : f64) {
	//debug_draw()
	//rl.BeginDrawing()
	//t := f32(rl.GetTime())
	game_cam := game_camera()
	screen := get_screen(platform.window)

	//rl.DrawRectangleRec({0, 0, f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}, rl.WHITE)
	//rl.ClearBackground({0, 120, 153, 255})
	//rl.BeginMode2D(game_cam)

	sdl.SetRenderDrawColor(platform.renderer, 0, 0, 0, 255)
	sdl.RenderClear(platform.renderer)
	world_render(g_mem^, platform.renderer, game_cam, screen, alpha)
	im_render(platform, g_mem)
	sdl.RenderPresent(platform.renderer)

	//rl.EndMode2D()
	//rl.BeginMode2D(ui_camera())

	if g_mem.finished {
		//rl.DrawTextEx(font, "YOU DID IT!! YOU FOUND\nTHE THREE MAGICAL\nTUNA CANS!!!\n\nGOOD BYE", {40, 40}, 20, 0, rl.WHITE)
	} else if g_mem.won {
		//rl.DrawTextEx(font, "YAY!!! TUNA", {40, 40}, 40, 0, rl.WHITE)
	}

	//rl.EndMode2D()
	//rl.EndDrawing()

}

LEVEL_1_POS :: Vec2 {70, 70+10}
LEVEL_2_POS :: Vec2 {70, 90+10}
LEVEL_3_POS :: Vec2 {70, 110+10}
QUIT_POS :: Vec2 {70, 130+10}

MENU_BUTTON_SIZE :: Vec2 {120, 20}

get_world_mouse_pos :: proc(cam: Camera2D) -> Vec2 {
	assert(false, "unimplemented")
	return Vec2{}
	//return vec2_flip(rl.GetScreenToWorld2D(rl.GetMousePosition(), cam))
}

get_mouse_pos :: proc() -> Vec2 {
	assert(false, "unimplemented")
	return Vec2{}
	//return vec2_flip(rl.GetMousePosition())
}


vec2_flip :: proc(p: Vec2) -> Vec2 {
	return {
		p.x, -p.y,
	}
}

IS_WASM :: ODIN_ARCH == .wasm32 || ODIN_ARCH == .wasm64p32

// Note that we have one weird case where platformIO.Monitors is being allocated as a [dynamic] in
// ImGui_ImplSDL3_UpdateMonitors(), and then we directly assign to platformIO.Monitor's fields.
// This means that it's allocation won't go through this proc. However, it's freeing will go through the free_func during the
// ~ImVector<PlatformMonitor> destructor
im_mem_alloc_func : im.MemAllocFunc : proc "c" (sz: c.size_t, user_data: rawptr) -> rawptr {
	context = g_context
	// TODO: Handle alloc error
	result, _ := mem.alloc(int(sz))
	return result
}

im_mem_free_func : im.MemFreeFunc : proc "c"(ptr: rawptr, user_data: rawptr) {
	context = g_context
	mem.free(ptr)
}

im_init :: proc(platform : ^Platform_State) {
	context = g_context
	log.info("im_init()...")

	main_scale := sdl.GetDisplayContentScale(sdl.GetPrimaryDisplay())
	// Setup Dear ImGui context
	im.CHECKVERSION()
	im.SetAllocatorFunctions(im_mem_alloc_func, im_mem_free_func)
	im.CreateContext()
	io := im.GetIO()
	io.ConfigFlags += {.NavEnableKeyboard}
	io.ConfigFlags += {.NavEnableGamepad}
	io.ConfigFlags += {.DockingEnable}
	io.ConfigFlags += {.ViewportsEnable}

	// Setup Dear ImGui style
	im.StyleColorsDark()

	// Setup scaling
	style := im.GetStyle()
	im.Style_ScaleAllSizes(style, main_scale)
	style.FontScaleDpi = main_scale
	io.ConfigDpiScaleFonts = true
	io.ConfigDpiScaleViewports = true

	// When viewports are enabled we tweak WindowRounding/WindowBg so platform windows can look identical to regular ones
	if .ViewportsEnable in io.ConfigFlags {
		style.WindowRounding = 0.0
		style.Colors[im.Col.WindowBg].w = 1.0
	}

	when RENDERER_SDL_GPU {
		// Setup Platform/Renderer backends
		ImGui_ImplSDL3_InitForSDLGPU(platform.window)
		init_info : ImGui_ImplSDLGPU3_InitInfo
		init_info.device = g_gpu_device
		init_info.color_target_format = sdl.GetGPUSwapchainTextureFormat(g_gpu_device, platform.window)
		init_info.msaa_samples = ._1                      // Only used in multi-viewports mode.
		init_info.swapchain_composition = .SDR  // Only used in multi-viewports mode.
		init_info.present_mode = .VSYNC
		ImGui_ImplSDLGPU3_Init(&init_info)
	} else {
		ImGui_ImplSDL3_InitForSDLRenderer(platform.window, platform.renderer)
		ImGui_ImplSDLRenderer3_Init(platform.renderer)
	}

	// Load Fonts
    // - If no fonts are loaded, dear imgui will use the default font. You can also load multiple fonts and use ImGui::PushFont()/PopFont() to select them.
    // - AddFontFromFileTTF() will return the ImFont* so you can store it if you need to select the font among multiple.
    // - If the file cannot be loaded, the function will return a nullptr. Please handle those errors in your application (e.g. use an assertion, or display an error and quit).
    // - Use '#define IMGUI_ENABLE_FREETYPE' in your imconfig file to use Freetype for higher quality font rendering.
    // - Read 'docs/FONTS.md' for more instructions and details. If you like the default font but want it to scale better, consider using the 'ProggyVector' from the same author!
    // - Remember that in C/C++ if you want to include a backslash \ in a string literal you need to write a double backslash \\ !
    //style.FontSizeBase = 20.0f;
    //io.Fonts->AddFontDefault();
    //io.Fonts->AddFontFromFileTTF("c:\\Windows\\Fonts\\segoeui.ttf");
    //io.Fonts->AddFontFromFileTTF("../../misc/fonts/DroidSans.ttf");
    //io.Fonts->AddFontFromFileTTF("../../misc/fonts/Roboto-Medium.ttf");
    //io.Fonts->AddFontFromFileTTF("../../misc/fonts/Cousine-Regular.ttf");
    //ImFont* font = io.Fonts->AddFontFromFileTTF("c:\\Windows\\Fonts\\ArialUni.ttf");
    //IM_ASSERT(font != nullptr);

	log.info("im_init() complete.")
}


sdl_init :: proc(platform_state : ^Platform_State, platform_allocator : runtime.Allocator) -> bool {
	context.allocator = platform_allocator
	log.info("sdl_init()...")
	if !sdl.Init({.AUDIO, .VIDEO, .EVENTS, .GAMEPAD}) {
		log.error("sdl.Init() failed:", sdl.GetError())
		return false
	}

	// TODO: proper handling of display scale
	main_scale := sdl.GetDisplayContentScale(sdl.GetPrimaryDisplay())
	_ = main_scale
	window_flags := sdl.WindowFlags{.RESIZABLE, .HIDDEN, .HIGH_PIXEL_DENSITY}

	// TODO: Proper window size settings
	// TODO: Proper indow flags setting
	//g_mem.window = sdl.CreateWindow(GAME_TITLE, i32(1920 * main_scale), i32(1080 * main_scale), window_flags)
	platform_state.window = sdl.CreateWindow(GAME_TITLE, i32(1920), i32(1080), window_flags)
	if platform_state.window == nil {
		log.error("sdl.CreateWindow() failed:", sdl.GetError())
		return false
	}

	when !RENDERER_SDL_GPU {
		platform_state.renderer = sdl.CreateRenderer(platform_state.window, nil)
		sdl.SetRenderVSync(platform_state.renderer, 1)
		if platform_state.renderer == nil {
			log.error("Error: SDL_CreateRenderer(): %s\n", sdl.GetError())
			return false
		}
	}

	sdl.SetWindowPosition(platform_state.window, sdl.WINDOWPOS_CENTERED, sdl.WINDOWPOS_CENTERED)
	sdl.ShowWindow(platform_state.window)

	when RENDERER_SDL_GPU {
		// TODO: This following stuff should maybe be moved to init instead? Depends on what is needed for hot reload
		// Create GPU Device
		// TODO: disable debug mode in release builds. Name the device
		g_gpu_device = sdl.CreateGPUDevice({.SPIRV, .DXIL, .MSL, .METALLIB}, true, nil)
		if g_gpu_device == nil {
			log.error("sdl.CreateGPUDevice() failed:", sdl.GetError())
			return false
		}

		// Claim window for GPU Device
		if !sdl.ClaimWindowForGPUDevice(g_gpu_device, platform_state.window) {
			log.error("sdl.ClaimWindowForGPUDevice() failed:", sdl.GetError())
			return false
		}

		if !sdl.SetGPUSwapchainParameters(g_gpu_device, platform_state.window, .SDR, .VSYNC) {
			log.error("sdl.SetGPUSwapchainParameters() failed:", sdl.GetError())
			// TODO: Maybe it's okay to continue if setting params fails? Or try backup params?
			return false
		}
	}

	log.info("sdl_init() complete.")
	return true
}

Vec2 :: [2]f32
Rect :: struct {
	x:      f32,                  // Rectangle bottom-left corner position x
	y:      f32,                  // Rectangle bottom-left corner position y
	w:      f32,                  // Rectangle width
	h:      f32,                  // Rectangle height
}

//GRAVITY :: Vec2 {0, -9.82*10}
GRAVITY :: Vec2 {0, 0}

WORLD_SCALE :: 10.0

ATLAS_DATA :: #load("../assets/atlas.png")
HIT_SOUND :: #load("../sounds/hit.wav")
LAND_SOUND :: #load("../sounds/land.wav")
WIN_SOUND :: #load("../sounds/win.wav")
Vec3 :: [3]f32

SHADERS_DIR :: "../shaders"

BACKGROUND_SHADER_DATA :: #load(SHADERS_DIR + "/bg_shader.glsl")
GROUND_SHADER_DATA :: #load(SHADERS_DIR + "/ground_shader.glsl")
GROUND_SHADER_VS_DATA :: #load(SHADERS_DIR + "/ground_shader_vs.glsl")

temp_cstring :: proc(s: string) -> cstring {
	return strings.clone_to_cstring(s, context.temp_allocator)
}

g_mem_reset :: proc(platform : ^Platform_State) -> ^Game_Memory {
	log.info("g_mem_reset()...")
	game_allocator := os2.heap_allocator()
when MEMORY_TRACKING {
	mem.tracking_allocator_init(&platform.game_memory_tracking.tracking_allocator, game_allocator, game_allocator)
	game_allocator = mem.tracking_allocator(&platform.game_memory_tracking.tracking_allocator)
}
	context.allocator = game_allocator
	g_context = context

	g_mem, alloc_err := new(Game_Memory)
	if alloc_err != .None {
		log.error("Could not allocate game memory. Error:", alloc_err)
		os.exit(-1)
	}
	g_mem.allocator = game_allocator

	g_mem.sim_ctx = {dt=0.01}

	world_def := b2.DefaultWorldDef()
	world_def.gravity = GRAVITY
	world_def.enableContinous = true
	g_mem.physics_world = b2.CreateWorld(world_def)	
	
	g_mem.avatar = avatar_make(g_mem, {10,10}, 30.0)
	g_mem.ball = ball_make(g_mem, {0, 0})
	
	field_width ::  190
	field_height :: 106 
	wall_thickness :: 1
	
	if USE_PIVOTS {
		for y := -field_height / 2; y < field_height/2; y += 30 {
			for x := -field_width / 2; x < field_width/2; x += 30 {
				append(&g_mem.pivots, pivot_make(g_mem, Vec2{f32(x), f32(y)}, 2.0))
			}
		}
	}
	
	
	g_mem.left_wall = wall_make(g_mem, Rect{-field_width/2 - wall_thickness, -field_height/2, wall_thickness, field_height})
	g_mem.right_wall = wall_make(g_mem, Rect{field_width/2, -field_height/2, wall_thickness, field_height})
	g_mem.top_wall = wall_make(g_mem, Rect{-field_width/2, field_height/2, field_width, wall_thickness})
	g_mem.bottom_wall = wall_make(g_mem, Rect{-field_width/2, -field_height/2 - wall_thickness, field_width, wall_thickness})

	g_mem.pivots = make([dynamic]Pivot)

	log.info("g_mem_reset() complete.")
	return g_mem
}

wall_make :: proc(g_mem : ^Game_Memory, rect : Rect, rot : f32 = 0.0) -> Wall {
	w := Wall {
		rect = rect,
		rot = rot,
	}

	body_def := b2.DefaultBodyDef()
	body_def.position = b2.Vec2{rect.x + rect.w/2, rect.y + rect.h/2}
	body_def.rotation = b2.MakeRot(rot)
	w.body = b2.CreateBody(physics_world(g_mem), body_def)

	box := b2.MakeBox((rect.w/2), (rect.h/2))
	shape_def := b2.DefaultShapeDef()
	shape_def.friction = 0.7
	shape_def.filter = {
		categoryBits = u32(bit_set[Collision_Category] { .Wall }),
		maskBits = u32(bit_set[Collision_Category] { .Avatar, .Ball }),
	}

	w.shape = b2.CreatePolygonShape(w.body, shape_def, box)
	return w
}

pivot_make :: proc(g_mem: ^Game_Memory, pos : Vec2, radius : f32) -> Pivot {
	pivot := Pivot {
		pos = pos,
		radius = radius,
	}

	body_def := b2.DefaultBodyDef()
	body_def.position = pos
	pivot.body = b2.CreateBody(physics_world(g_mem), body_def)

	circle := b2.Circle{radius=radius}
	shape_def := b2.DefaultShapeDef()
	shape_def.friction = 0.7
	shape_def.filter = {
		categoryBits = u32(bit_set[Collision_Category] { .Pivot }),
		//maskBits = u32(bit_set[Collision_Category] { .Avatar }),
	}

	pivot.shape = b2.CreateCircleShape(pivot.body, shape_def, circle)
	return pivot
}

// TODO: Add this cleanup stuff from the imgui examples main.cpp
// TODO: Add cleanup from imgui example for sdl renderer 3

g_mem_shutdown :: proc(platform : ^Platform_State, g_mem : ^Game_Memory) {
	log.info("g_mem_shutdown...")
	//mem.free(g_mem.font.recs)
	//mem.free(g_mem.font.glyphs)
	mem.delete(g_mem.pivots)
	free(g_mem)

when MEMORY_TRACKING {
	mem_tracking.reset_tracking_allocator(&platform.game_memory_tracking.tracking_allocator)
}
	log.info("g_mem_shutdown complete")

}

im_shutdown :: proc() {
	context = g_context
	log.info("im_shutdown...")
	when RENDERER_SDL_GPU {
		SDL_WaitForGPUIdle(platform.gpu_device)
		ImGui_ImplSDL3_Shutdown()
		ImGui_ImplSDLGPU3_Shutdown()
		im.DestroyContext()
	} else {
		// Shutdown imgui
		ImGui_ImplSDLRenderer3_Shutdown()
		ImGui_ImplSDL3_Shutdown()
		im.DestroyContext()
	}
	log.info("im_shutdown complete.")
}

sdl_shutdown :: proc(platform : ^Platform_State, platform_allocator : runtime.Allocator) {
	context.allocator = platform_allocator
	log.info("shutdown sdl and window...")

	// Shutdown sdl
	when RENDERER_SDL_GPU {
		sdl.ReleaseWindowFromGPUDevice(platform.gpu_device, platform.window)
		sdl.DestroyGPUDevice(platform.gpu_device)
		sdl.DestroyWindow(platform.window)
		sdl.Quit()
	} else {
		sdl.DestroyRenderer(platform.renderer)
		sdl.DestroyWindow(platform.window)
		sdl.Quit()
	}
	log.info("shutdown sdl and window complete")
}

