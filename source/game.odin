package game

HOTLOAD :: #config(HOTLOAD, true)
MEMORY_TRACKING :: #config(MEMORY_TRACKING, true)

import "mem_tracking"
import "config"

import "base:runtime"
import b2 "vendor:box2d"
//import rl "vendor:raylib"
import sdl "vendor:sdl3"
import im "deps:odin-imgui"
import "core:log"
import "core:c"
//import "core:math"
import "core:mem"
import "core:os"
import "core:strings"

when HOTLOAD {
	_ :: config
} else {
	_ :: hotload_api
}

_ :: mem_tracking

GAME_TITLE :: "GravSling"
PIXEL_WINDOW_HEIGHT :: 1080

RENDERER_SDL_GPU :: false

g_context : runtime.Context
g_platform : ^Platform_State

establish_game_context :: proc(game_allocator: runtime.Allocator, platform_ctx: runtime.Context) -> runtime.Context {
	ctx := platform_ctx
	ctx.allocator = game_allocator 
	g_context = ctx
	return ctx
}

establish_globals :: proc(platform : ^Platform_State) {
	g_platform = platform
}


// Gets the allocator that backs all game memory.
// Stubs out using the platform as a param as in the future we should
// store game allocator state on it
game_backing_allocator :: proc(platform: ^Platform_State) -> runtime.Allocator {
	return os.heap_allocator()
}

game_backing_reset :: proc(platform: ^Platform_State) {
	// no-op with os.heap_allocator()
}

// Hotload exports
when HOTLOAD {

Hotload_Memory :: struct {
	platform : ^Platform_State, // Persistent platform data. Never reset
	g_mem : ^Game_Memory, // Game data that can be hard reset
	reload_requested : bool,
	reset_requested : bool,
}

@(export)
game_init :: proc(platform_ctx: runtime.Context) -> rawptr {
	context = platform_ctx
	platform, g_mem := init(platform_ctx)
	hotload_memory := new(Hotload_Memory)
	hotload_memory.platform = platform
	hotload_memory.g_mem = g_mem

	return rawptr(hotload_memory)
}


@(export)
game_tick :: proc(handle: rawptr) {
	hotload_memory := cast(^Hotload_Memory)handle
	context = g_context

	poll_input(hotload_memory.platform, hotload_memory.g_mem)

	hotload_memory.reload_requested = keyboard_is_key_pressed(g_keyboard, .F4)
	hotload_memory.reset_requested = keyboard_is_key_pressed(g_keyboard, .F5)

	update_and_render(hotload_memory.platform, hotload_memory.g_mem)
	on_frame_end(hotload_memory.platform, hotload_memory.g_mem)
}

@(export)
game_should_quit :: proc(handle: rawptr) -> bool {
	hotload_memory := cast(^Hotload_Memory)handle
	context = g_context
	return should_quit(hotload_memory.g_mem)
}

@(export)
game_shutdown :: proc(handle: rawptr, platform_ctx: runtime.Context) {
	hotload_memory := cast(^Hotload_Memory)handle
	context = g_context
	shutdown(hotload_memory.platform, hotload_memory.g_mem)
	context = platform_ctx
	free(hotload_memory)
}

@(export)
game_unload_for_hotload :: proc(handle: rawptr) {
	//hotload_memory := cast(^Hotload_Memory)handle
	context = g_context
	im_shutdown()
}

@(export)
game_unload_for_reset :: proc(handle: rawptr) {
	hotload_memory := cast(^Hotload_Memory)handle
	context = g_context
	im_shutdown()
	g_mem_shutdown(hotload_memory.platform, hotload_memory.g_mem)
}

@(export)
game_rebuild_memory :: proc(handle: rawptr, platform_ctx: runtime.Context) {
	hotload_memory := cast(^Hotload_Memory)handle
	context = platform_ctx
	hotload_memory.g_mem = g_mem_reset(hotload_memory.platform)
}

@(export)
game_memory_size :: proc() -> int {
	return size_of(Game_Memory)
}

@(export)
game_platform_size :: proc() -> int {
	return size_of(Platform_State)
}

@(export)
game_force_reload :: proc(handle: rawptr) -> bool {
	hotload_memory := cast(^Hotload_Memory)handle
	context = g_context
	return hotload_memory.reload_requested
}

@(export)
game_force_reset:: proc(handle: rawptr) -> bool {
	hotload_memory := cast(^Hotload_Memory)handle
	context = g_context
	return hotload_memory.reset_requested
}

@(export)
game_hot_reloaded :: proc(handle: rawptr, platform_ctx: runtime.Context) {
	hotload_memory := cast(^Hotload_Memory)handle
	context = establish_game_context(hotload_memory.g_mem.allocator, platform_ctx)
	establish_globals(hotload_memory.platform)
	im_init(hotload_memory.platform)
	rebind_callbacks(hotload_memory.g_mem)
	hotload_memory.g_mem.sim_ctx.current_time = hi_res_time_in_seconds()
	hotload_memory.g_mem.sim_ctx.accumulator = 0
}

// TODO: Better name for this that is more generic? Maybe just do a on_hot_reload proc per system? idk atm
rebind_callbacks :: proc(g_mem: ^Game_Memory) {
	g_mem.b2_debug_draw.DrawPolygonFcn = b2_debug_draw_polygon
	g_mem.b2_debug_draw.DrawSolidPolygonFcn = b2_debug_draw_solid_polygon
	g_mem.b2_debug_draw.DrawCircleFcn = b2_debug_draw_circle
	g_mem.b2_debug_draw.DrawSolidCircleFcn = b2_debug_draw_solid_circle
	g_mem.b2_debug_draw.DrawSolidCapsuleFcn = b2_debug_draw_solid_capsule
	g_mem.b2_debug_draw.DrawSegmentFcn = b2_debug_draw_segment
	g_mem.b2_debug_draw.DrawTransformFcn = b2_debug_draw_transform
	g_mem.b2_debug_draw.DrawPointFcn = b2_debug_draw_point
	g_mem.b2_debug_draw.DrawStringFcn = b2_debug_draw_string
}

}

init :: proc(platform_ctx : runtime.Context) -> (^Platform_State, ^Game_Memory) {
	context = platform_ctx
	platform := platform_init(platform_ctx.allocator)
	g_mem := g_mem_reset(platform)
	context = establish_game_context(g_mem.allocator, platform_ctx)
	establish_globals(platform)
	im_init(platform)

	return platform, g_mem
}


Wall :: struct {
	body: b2.BodyId,
	shape: b2.ShapeId,
	rect: Rect,
	rot: f32,
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
	
	left_wall: Wall,
	right_wall: Wall,
	top_wall: Wall,
	bottom_wall: Wall,

	b2_debug_draw : b2.DebugDraw,

	time_accumulator: f32,

	won: bool,
	won_at: f64,

	finished: bool,

	allocator : runtime.Allocator,
}



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
		zoom = 60.0,
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
				g_gamepad.buttons_released[EGamepadButton(event.gbutton.button)] = true 
				g_gamepad.buttons_down[EGamepadButton(event.gbutton.button)] = event.gbutton.down 
			}

			case .GAMEPAD_AXIS_MOTION:
			g_gamepad.axes[EGamepadAxis(event.gaxis.axis)].pos = event.gaxis.value

			case .KEY_DOWN:
			fallthrough
			case .KEY_UP:
			if event.key.down {
				if event.key.scancode == .SPACE {
					log.info("SPACE down")
				}
				// TODO> Better way to handle key state? Maybe have a repeat flag on a KeyState etc
				g_keyboard.keys_pressed[EScancode(event.key.scancode)] = event.key.down && !event.key.repeat
				g_keyboard.keys_down[EScancode(event.key.scancode)] = event.key.down
			} else {
				g_keyboard.keys_released[EScancode(event.key.scancode)] = true 
				g_keyboard.keys_down[EScancode(event.key.scancode)] = event.key.down
			}
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

should_quit :: proc(g_mem : ^Game_Memory) -> bool {
	return g_mem.finished
}

on_frame_end :: proc(platform : ^Platform_State, g_mem : ^Game_Memory) {
	free_all(context.temp_allocator)
	g_mem.sim_ctx.frame_num += 1
}

shutdown :: proc(platform : ^Platform_State, g_mem : ^Game_Memory) {
	im_shutdown()
	g_mem_shutdown(platform, g_mem)
	sdl_shutdown(platform, platform.allocator)
	platform_shutdown(platform)
}

clear_edge_events :: proc() {
	// TODO: Is this the best way to represent not pressed this tick?
	g_gamepad.buttons_pressed = {}
	g_gamepad.buttons_released = {}
	g_keyboard.keys_pressed = {}
	g_keyboard.keys_released = {}
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
		clear_edge_events()
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
	avatar_tick_pre_physics(g_mem, &g_mem.avatar, g_mem.sim_ctx, g_mem.physics_world)
	ball_tick_pre_physics(&g_mem.ball)
	b2.World_Step(physics_world(g_mem), f32(g_mem.sim_ctx.dt), 4)	
	avatar_tick_post_physics(g_mem, &g_mem.avatar, g_mem.sim_ctx, g_mem.physics_world)
	ball_tick_post_physics(&g_mem.ball)
}

Collision_Category :: enum u64 {
	Wall,
	Avatar,
	Ball,
}

wall_render :: proc(wall : Wall, ref_def: Ref_Def) {
	// TODO:  Maybe put a render_state on the static wall and use render_rect(...) instead?
	screen_rect := rect_world_to_screen(wall.rect, ref_def.camera, ref_def.screen)
	sdl.SetRenderDrawColor(ref_def.renderer, 0, 255, 0, 255)
	sdl.RenderFillRect(ref_def.renderer, cast(^sdl.FRect)&screen_rect)
}

world_render :: proc(g_mem : Game_Memory, ref_def : Ref_Def) {
	// Draw the origin
	//render_circle_filled(renderer, {}, 1.0, camera, screen)

	avatar_render(g_mem.avatar, ref_def)
	wall_render(g_mem.left_wall, ref_def)
	wall_render(g_mem.right_wall, ref_def)
	wall_render(g_mem.top_wall, ref_def)
	wall_render(g_mem.bottom_wall, ref_def)

	ball_render(g_mem.ball, ref_def)
	
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

	sdl.SetRenderDrawColor(platform.renderer, 50, 50, 50, 255)
	sdl.RenderClear(platform.renderer)

	// Construct the Ref_Def
	ref_def : Ref_Def = {
		platform.renderer,
		game_cam,
		screen,
		alpha,
	}

	//world_render(g_mem^, ref_def)
	{
		g_mem.b2_debug_draw.userContext = &ref_def
		b2.World_Draw(g_mem.physics_world, &g_mem.b2_debug_draw)
	}

	im_render(platform, g_mem)
	
	//render_debug_text(ref_def, Vec2{0.0, 0.0}, "TEST TEXT", {255, 0, 0, 255})

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

	// TODO: Proper dpi handling
	// TODO: Proper window size settings
	// TODO: Proper window flags setting
	//g_mem.window = sdl.CreateWindow(GAME_TITLE, i32(1920 * main_scale), i32(1080 * main_scale), window_flags)
	platform_state.window = sdl.CreateWindow(GAME_TITLE, i32(2048), i32(1152), window_flags)
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
	game_backing_reset(platform)

	game_allocator := game_backing_allocator(platform)
when MEMORY_TRACKING {
	mem.tracking_allocator_init(&platform.game_memory_tracking.tracking_allocator, game_allocator, game_allocator)
	game_allocator = mem.tracking_allocator(&platform.game_memory_tracking.tracking_allocator)
}
	context.allocator = game_allocator

	g_mem, alloc_err := new(Game_Memory)
	if alloc_err != .None {
		log.error("Could not allocate game memory. Error:", alloc_err)
		os.exit(-1)
	}
	g_mem.allocator = game_allocator

	g_mem.sim_ctx = {dt=0.01}

	world_def := b2.DefaultWorldDef()
	world_def.gravity = GRAVITY
	world_def.enableContinuous = true
	g_mem.physics_world = b2.CreateWorld(world_def)	
	
	g_mem.avatar = avatar_make(g_mem, {2,2}, 30.0)
	g_mem.ball = ball_make(g_mem, {0, 0})
	
	field_width ::  32
	field_height :: 18 
	wall_thickness :: 1
	
	g_mem.left_wall = wall_make(g_mem, Rect{-field_width/2 - wall_thickness, -field_height/2, wall_thickness, field_height})
	g_mem.right_wall = wall_make(g_mem, Rect{field_width/2, -field_height/2, wall_thickness, field_height})
	g_mem.top_wall = wall_make(g_mem, Rect{-field_width/2, field_height/2, field_width, wall_thickness})
	g_mem.bottom_wall = wall_make(g_mem, Rect{-field_width/2, -field_height/2 - wall_thickness, field_width, wall_thickness})

	g_mem.b2_debug_draw = {
		DrawPolygonFcn = b2_debug_draw_polygon,
		DrawSolidPolygonFcn = b2_debug_draw_solid_polygon,
		DrawCircleFcn = b2_debug_draw_circle,
		DrawSolidCircleFcn = b2_debug_draw_solid_circle,
		DrawSolidCapsuleFcn = b2_debug_draw_solid_capsule,
		DrawSegmentFcn = b2_debug_draw_segment,
		DrawTransformFcn = b2_debug_draw_transform,
		DrawPointFcn = b2_debug_draw_point,
		DrawStringFcn = b2_debug_draw_string,
		drawingBounds = {},
		useDrawingBounds = false,
		drawShapes = true,
		drawJoints = true,
		drawJointExtras = false,
		drawBounds = false,
		drawMass = false,
		drawBodyNames = false,
		drawContacts = false,
		drawGraphColors = false,
		drawContactNormals = true,
		drawContactImpulses = true,
		drawContactFeatures = false,
		drawFrictionImpulses = false,
		drawIslands = false,
	}

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
	// TODO: Use new surface def for friction and restitution
	shape_def.material.friction = 0.7
	shape_def.filter = {
		categoryBits = u64(bit_set[Collision_Category] { .Wall }),
		maskBits = u64(bit_set[Collision_Category] { .Avatar, .Ball }),
	}

	w.shape = b2.CreatePolygonShape(w.body, shape_def, &box)
	return w
}

// TODO: Add this cleanup stuff from the imgui examples main.cpp
// TODO: Add cleanup from imgui example for sdl renderer 3

g_mem_shutdown :: proc(platform : ^Platform_State, g_mem : ^Game_Memory) {
	log.info("g_mem_shutdown...")
	//mem.free(g_mem.font.recs)
	//mem.free(g_mem.font.glyphs)
	free(g_mem)

when MEMORY_TRACKING {
	mem_tracking.reset_tracking_allocator(&platform.game_memory_tracking.tracking_allocator)
	mem.tracking_allocator_destroy(&platform.game_memory_tracking.tracking_allocator)
}
	log.info("g_mem_shutdown complete")

}

im_shutdown :: proc() {
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

