package game

// TODO
// - Abstract over SDL. sys package, renderer package, etc
import "base:runtime"
import b2 "box2d"
//import rl "vendor:raylib"
import sdl "vendor:sdl3"
import im "deps:odin-imgui"
import "core:fmt"
import "core:log"
import "core:c"
//import "core:math"
import "core:mem"
import "core:strings"

GAME_TITLE :: "GravSling"
PIXEL_WINDOW_HEIGHT :: 1080

RENDERER_SDL_GPU :: false

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

Game_Memory :: struct {
	physics_world: b2.WorldId,
	starting_pos: Vec2,
	avatar: Avatar,
	
	pivots: [dynamic]Pivot,
	
	left_wall: Wall,
	right_wall: Wall,
	top_wall: Wall,
	bottom_wall: Wall,

	time_accumulator: f32,

	won: bool,
	won_at: f64,

	finished: bool,

	// TODO: Can't use when here
//when RENDERER_SDL_GPU {
//gpu_device: ^sdl.GPUDevice
//} else {
//sdl_renderer: ^sdl.Renderer
//}
	renderer : ^sdl.Renderer,
	window : ^sdl.Window,

	//font: rl.Font,
	//atlas: rl.Texture2D,
	// sounds
	//hit_sound: rl.Sound,
	//land_sound: rl.Sound,
	//win_sound: rl.Sound,
}

g_context : runtime.Context
g_mem: ^Game_Memory

on_hot_reload :: proc() {
	log.info("Start on_hot_reload()")
	g_context = context
	//atlas = g_mem.atlas
	//font = g_mem.font
	im_init()
	log.info("End on_hot_reload()")
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
		zoom = 20.0,
		//zoom = h/PIXEL_WINDOW_HEIGHT*GAME_SCALE,
		//offset = { w/2, h/2 },
	}
}

get_screen :: proc() -> Vec2 {
	w, h : i32
	sdl.GetWindowSizeInPixels(g_mem.window, &w, &h)
	return Vec2{f32(w), f32(h)}
}

ui_camera :: proc() -> Camera2D {
	assert(false, "unimplemented")
	return {
		//zoom = f32(rl.GetScreenHeight())/PIXEL_WINDOW_HEIGHT,
	}
}

physics_world :: proc() -> b2.WorldId {
	return g_mem.physics_world
}

poll_input :: proc() {
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
		if event.type == .WINDOW_CLOSE_REQUESTED && event.window.windowID == sdl.GetWindowID(g_mem.window) {
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
			log.info("key event")
			g_keyboard.keys[EScancode(event.key.scancode)].pressed = event.key.down
		}
	}

	// [If using SDL_MAIN_USE_CALLBACKS: all code below would likely be your SDL_AppIterate() function]
	if .MINIMIZED in sdl.GetWindowFlags(g_mem.window) {
		sdl.Delay(10)
		return
	}
}

show_demo_window := false
show_another_window := false
clear_color := [3]f32{0.45, 0.55, 0.60}
update :: proc(sim_ctx : Sim_Ctx) {
	if sim_ctx.frame_tick_num > 0 {
		// TODO: Is this the best way to represent not pressed this tick?
		g_gamepad.buttons_pressed = {}
	}
	b2.World_Step(physics_world(), f32(sim_ctx.dt), 4)	
	avatar_update(&g_mem.avatar, sim_ctx, g_mem.pivots, g_mem.physics_world)
}

Collision_Category :: enum u32 {
	Wall,
	Avatar,
	Pivot,
}

wall_render :: proc(wall : Wall, camera : Camera2D, screen : Vec2) {
	screen_rect := rect_world_to_screen(wall.rect, camera, screen)
	sdl.SetRenderDrawColor(g_mem.renderer, 0, 255, 0, 255)
	sdl.RenderFillRect(g_mem.renderer, cast(^sdl.FRect)&screen_rect)
}

pivot_render :: proc(pivot: Pivot, camera : Camera2D, screen : Vec2) {
	render_circle_filled(pivot.pos, pivot.radius, camera, screen)
}

world_render :: proc(camera : Camera2D, screen : Vec2, alpha : f64) {
	// Draw the origin
	render_circle_filled({}, 1.0, camera, screen)


	avatar_render(g_mem.avatar, camera, screen, alpha)
	wall_render(g_mem.left_wall, camera, screen)
	wall_render(g_mem.right_wall, camera, screen)
	wall_render(g_mem.top_wall, camera, screen)
	wall_render(g_mem.bottom_wall, camera, screen)
	
	for pivot in g_mem.pivots {
		pivot_render(pivot, camera, screen)
	}
	
	// Origin
	//rl.DrawCircle(0,0, 0.5 + 0.5*((1.0 + math.sin(f32(rl.GetTime()))) / 2.0), rl.BLACK)
}

render :: proc(alpha : f64) {
	//debug_draw()
	//rl.BeginDrawing()
	//t := f32(rl.GetTime())
	game_cam := game_camera()
	screen := get_screen()

	//rl.DrawRectangleRec({0, 0, f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}, rl.WHITE)
	//rl.ClearBackground({0, 120, 153, 255})
	//rl.BeginMode2D(game_cam)

	sdl.SetRenderDrawColor(g_mem.renderer, 0, 0, 0, 255)
	sdl.RenderClear(g_mem.renderer)
	world_render(game_cam, screen, alpha)
	im_render()
	sdl.RenderPresent(g_mem.renderer)

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

g_im_context : Im_Context
Im_Context :: struct {
	allocator : mem.Allocator,
}

im_init :: proc() {
/*
when ODIN_DEBUG {
	g_im_context.allocator = runtime.default_allocator()
	context.allocator = runtime.default_allocator()
} else {
	tracking_allocator : mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking_allocator, context.allocator)
	g_im_context.allocator = tracking_allocator
	context.allocator = tracking_allocator
}
*/

	main_scale := sdl.GetDisplayContentScale(sdl.GetPrimaryDisplay())
	// Setup Dear ImGui context
	im.CHECKVERSION()
	//im.SetAllocatorFunctions(im_mem_alloc_func, im_mem_free_func)
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
		ImGui_ImplSDL3_InitForSDLGPU(g_mem.window)
		init_info : ImGui_ImplSDLGPU3_InitInfo
		init_info.device = g_gpu_device
		init_info.color_target_format = sdl.GetGPUSwapchainTextureFormat(g_gpu_device, g_mem.window)
		init_info.msaa_samples = ._1                      // Only used in multi-viewports mode.
		init_info.swapchain_composition = .SDR  // Only used in multi-viewports mode.
		init_info.present_mode = .VSYNC
		ImGui_ImplSDLGPU3_Init(&init_info)
	} else {
		ImGui_ImplSDL3_InitForSDLRenderer(g_mem.window, g_mem.renderer)
		ImGui_ImplSDLRenderer3_Init(g_mem.renderer)
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
}

alloc_memory :: proc() {
	g_mem = new(Game_Memory)
}

init_window :: proc() -> bool {
	g_context = context
	log.info("init sdl and window...")
	/*
	flags: rl.ConfigFlags

	when ODIN_DEBUG {
		flags = {.WINDOW_RESIZABLE, .VSYNC_HINT}
	} else {
		flags = { .VSYNC_HINT }
	}

	when IS_WASM {
		flags += { .WINDOW_RESIZABLE }
	}

	rl.SetConfigFlags(flags)
	rl.InitWindow(1920, 1080, "The Legend of Tuna")
	rl.SetWindowPosition(200, 200)
	rl.SetTargetFPS(500)
	rl.InitAudioDevice()
	when !ODIN_DEBUG && !IS_WASM {
		rl.ToggleBorderlessWindowed()
	}
	rl.SetExitKey(.KEY_NULL)
	*/

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
	g_mem.window = sdl.CreateWindow(GAME_TITLE, i32(1920), i32(1080), window_flags)
	if g_mem.window == nil {
		log.error("sdl.CreateWindow() failed:", sdl.GetError())
		return false
	}
	log.info("init sdl and window success")

	when !RENDERER_SDL_GPU {
		g_mem.renderer = sdl.CreateRenderer(g_mem.window, nil)
		sdl.SetRenderVSync(g_mem.renderer, 1)
		if g_mem.renderer == nil {
			log.error("Error: SDL_CreateRenderer(): %s\n", sdl.GetError())
			return false
		}
	}

	sdl.SetWindowPosition(g_mem.window, sdl.WINDOWPOS_CENTERED, sdl.WINDOWPOS_CENTERED)
	sdl.ShowWindow(g_mem.window)

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
		if !sdl.ClaimWindowForGPUDevice(g_gpu_device, g_mem.window) {
			log.error("sdl.ClaimWindowForGPUDevice() failed:", sdl.GetError())
			return false
		}

		if !sdl.SetGPUSwapchainParameters(g_gpu_device, g_mem.window, .SDR, .VSYNC) {
			log.error("sdl.SetGPUSwapchainParameters() failed:", sdl.GetError())
			// TODO: Maybe it's okay to continue if setting params fails? Or try backup params?
			return false
		}
	}

	log.info("init_window finished")
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


init :: proc() {
	fmt.println("init")

	world_def := b2.DefaultWorldDef()
	world_def.gravity = GRAVITY
	world_def.enableContinous = true
	g_mem.physics_world = b2.CreateWorld(world_def)	
	
	g_mem.avatar = avatar_make({10,10}, 30.0)

	game_on_hot_reload(g_mem)
	
	field_width ::  190
	field_height :: 106 
	wall_thickness :: 1
	
	if USE_PIVOTS {
		for y := -field_height / 2; y < field_height/2; y += 30 {
			for x := -field_width / 2; x < field_width/2; x += 30 {
				append(&g_mem.pivots, pivot_make(Vec2{f32(x), f32(y)}, 2.0))
			}
		}
	}
	
	
	g_mem.left_wall = wall_make(Rect{-field_width/2 - wall_thickness, -field_height/2, wall_thickness, field_height})
	g_mem.right_wall = wall_make(Rect{field_width/2, -field_height/2, wall_thickness, field_height})
	g_mem.top_wall = wall_make(Rect{-field_width/2, field_height/2, field_width, wall_thickness})
	g_mem.bottom_wall = wall_make(Rect{-field_width/2, -field_height/2 - wall_thickness, field_width, wall_thickness})

	fmt.println("init finished")
}

wall_make :: proc(rect : Rect, rot : f32 = 0.0) -> Wall {
	w := Wall {
		rect = rect,
		rot = rot,
	}

	body_def := b2.DefaultBodyDef()
	body_def.position = b2.Vec2{rect.x + rect.w/2, rect.y + rect.h/2}
	body_def.rotation = b2.MakeRot(rot)
	w.body = b2.CreateBody(physics_world(), body_def)

	box := b2.MakeBox((rect.w/2), (rect.h/2))
	shape_def := b2.DefaultShapeDef()
	shape_def.friction = 0.7
	shape_def.filter = {
		categoryBits = u32(bit_set[Collision_Category] { .Wall }),
		maskBits = u32(bit_set[Collision_Category] { .Avatar }),
	}

	w.shape = b2.CreatePolygonShape(w.body, shape_def, box)
	return w
}

pivot_make :: proc(pos : Vec2, radius : f32) -> Pivot {
	pivot := Pivot {
		pos = pos,
		radius = radius,
	}

	body_def := b2.DefaultBodyDef()
	body_def.position = pos
	pivot.body = b2.CreateBody(physics_world(), body_def)

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

shutdown :: proc() {
	log.info("shutdown...")
	//mem.free(g_mem.font.recs)
	//mem.free(g_mem.font.glyphs)
	mem.delete(g_mem.pivots)
	free(g_mem)

	when RENDERER_SDL_GPU {
	} else {
	}

	log.info("shutdown complete")
}

shutdown_window :: proc() {
	log.info("shutdown sdl and window...")
	when RENDERER_SDL_GPU {
		// Shutdown imgui
		SDL_WaitForGPUIdle(g_gpu_device)
		ImGui_ImplSDL3_Shutdown()
		ImGui_ImplSDLGPU3_Shutdown()
		im.DestroyContext()

		// Shutdown sdl
		sdl.ReleaseWindowFromGPUDevice(g_gpu_device, g_mem.window)
		sdl.DestroyGPUDevice(g_gpu_device)
		sdl.DestroyWindow(g_mem.window)
		sdl.Quit()
	} else {
		// Shutdown imgui
		ImGui_ImplSDLRenderer3_Shutdown()
		ImGui_ImplSDL3_Shutdown()
		im.DestroyContext()

		// Shutdown sdl
		sdl.DestroyRenderer(g_mem.renderer)
		sdl.DestroyWindow(g_mem.window)
		sdl.Quit()
	}
	log.info("shutdown sdl and window complete")
}

