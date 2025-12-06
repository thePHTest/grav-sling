package game

import b2 "box2d"
//import rl "vendor:raylib"
import sdl "vendor:sdl3"
import im "deps:odin-imgui"
import "core:fmt"
import "core:log"
//import "core:math"
import "core:mem"
import "core:strings"

GAME_TITLE :: "GravSling"
PIXEL_WINDOW_HEIGHT :: 1080

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
	rc: Round_Cat,
	//atlas: rl.Texture2D,
	
	pivots: [dynamic]Pivot,
	
	left_wall: Wall,
	right_wall: Wall,
	top_wall: Wall,
	bottom_wall: Wall,

	time_accumulator: f32,

	won: bool,
	won_at: f64,

	finished: bool,
	//font: rl.Font,


	// sounds
	//hit_sound: rl.Sound,
	//land_sound: rl.Sound,
	//win_sound: rl.Sound,
}

//atlas: rl.Texture2D
g_mem: ^Game_Memory
g_window: ^sdl.Window
//font: rl.Font

refresh_globals :: proc() {
	//atlas = g_mem.atlas
	//font = g_mem.font
}

GAME_SCALE :: 10

Camera2D :: struct {
	offset:   Vec2,            // Camera offset (displacement from target)
	target:   Vec2,            // Camera target (rotation and zoom origin)
	rotation: f32,                // Camera rotation in degrees
	zoom:     f32,                // Camera zoom (scaling), should be 1.0f by default
}

game_camera :: proc() -> Camera2D {
	assert(false, "unimplemented")

	//w := f32(rl.GetScreenWidth())
	//h := f32(rl.GetScreenHeight())

	return {
		//zoom = h/PIXEL_WINDOW_HEIGHT*GAME_SCALE,
		//offset = { w/2, h/2 },
	}
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

dt: f32
real_dt: f32
show_demo_window := true
show_another_window := false
clear_color := [3]f32{0.45, 0.55, 0.60}
update :: proc() {
	log.info("update start")
	/*
	dt = rl.GetFrameTime()
	real_dt = dt

	if rl.IsKeyPressed(.ENTER) && rl.IsKeyDown(.LEFT_ALT) {
		rl.ToggleBorderlessWindowed()
	}

	if rl.IsKeyPressed(.ESCAPE) {
		// TODO: Menu
	}

	if g_mem.finished {
		return
	}

	if g_mem.won {
		dt = 0

		if rl.IsMouseButtonPressed(.LEFT) && rl.GetTime() > g_mem.won_at + 0.5 {
			g_mem.won = false
		}
		return
	}

	g_mem.time_accumulator += dt

	PHYSICS_STEP :: 1/60.0

	for g_mem.time_accumulator >= PHYSICS_STEP {
		b2.World_Step(physics_world(), PHYSICS_STEP, 4)	
		g_mem.time_accumulator -= PHYSICS_STEP
	}

	round_cat_update(&g_mem.rc, g_mem.pivots, g_mem.physics_world)
	*/
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
			g_mem.finished = true
		}
		if event.type == .WINDOW_CLOSE_REQUESTED && event.window.windowID == sdl.GetWindowID(g_window) {
			g_mem.finished = true
		}
	}

	// [If using SDL_MAIN_USE_CALLBACKS: all code below would likely be your SDL_AppIterate() function]
	if .MINIMIZED in sdl.GetWindowFlags(g_window) {
		sdl.Delay(10)
		return
	}

	// Start the Dear ImGui frame
	ImGui_ImplSDLGPU3_NewFrame()
	ImGui_ImplSDL3_NewFrame()
	im.NewFrame()

	// 1. Show the big demo window (Most of the sample code is in ImGui::ShowDemoWindow()! You can browse its code to learn more about Dear ImGui!).
	if show_demo_window {
		im.ShowDemoWindow(&show_demo_window)
	}

	// 2. Show a simple window that we create ourselves. We use a Begin/End pair to create a named window.
	{
		f : f32 = 0.0
		counter : int = 0

		im.Begin("Hello, world!")                          // Create a window called "Hello, world!" and append into it.

		im.Text("This is some useful text.")               // Display some text (you can use a format strings too)
		im.Checkbox("Demo Window", &show_demo_window)      // Edit bools storing our window open/close state
		im.Checkbox("Another Window", &show_another_window)

		im.SliderFloat("float", &f, 0.0, 1.0)            // Edit 1 float using a slider from 0.0f to 1.0f
		im.ColorEdit3("clear color", &clear_color) // Edit 3 floats representing a color

		if im.Button("Button") {                           // Buttons return true when clicked (most widgets return true when edited/activated)
			counter += 1
		}
		im.SameLine()
		im.Text("counter = %d", counter)

		io := im.GetIO()
		im.Text("Application average %.3f ms/frame (%.1f FPS)", 1000.0 / io.Framerate, io.Framerate)
		im.End()
	}

	// 3. Show another simple window.
	if show_another_window {
		im.Begin("Another Window", &show_another_window)   // Pass a pointer to our bool variable (the window will have a closing button that will clear the bool when clicked)
		im.Text("Hello from another window!")
		if im.Button("Close Me") {
			show_another_window = false
		}
		im.End()
	}
	log.info("update end")
}

Collision_Category :: enum u32 {
	Wall,
	Long_Cat,
	Round_Cat,
	Pivot,
}

rect_offset :: proc(r: Rect, o: Vec2) -> Rect {
	return {
		r.x + o.x,
		r.y + o.y,
		r.width,
		r.height,
	}
}

rect_flip :: proc(r: Rect) -> Rect {
	return {
		r.x, -r.y - r.height,
		r.width, r.height,
	}
}

draw_wall :: proc(wall : Wall) {
	//mid := Vec2 {wall.rect.width/2, wall.rect.height/2}
	//rl.DrawRectanglePro(rect_offset(rect_flip(wall.rect), mid), mid, -wall.rot*RAD2DEG, rl.DARKGREEN)
}

draw_pivot :: proc(pivot: Pivot) {
	//rl.DrawCircleV(vec2_flip(pivot.pos), pivot.radius, rl.YELLOW)
}

draw_world :: proc() {
	round_cat_draw(g_mem.rc)
	draw_wall(g_mem.left_wall)
	draw_wall(g_mem.right_wall)
	draw_wall(g_mem.top_wall)
	draw_wall(g_mem.bottom_wall)
	
	for pivot in g_mem.pivots {
		draw_pivot(pivot)
	}
	
	// Origin
	//rl.DrawCircle(0,0, 0.5 + 0.5*((1.0 + math.sin(f32(rl.GetTime()))) / 2.0), rl.BLACK)
}

draw :: proc() {
	//debug_draw()
	//rl.BeginDrawing()
	//t := f32(rl.GetTime())
	//game_cam := game_camera()

	//rl.DrawRectangleRec({0, 0, f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}, rl.WHITE)
	//rl.ClearBackground({0, 120, 153, 255})
	//rl.BeginMode2D(game_cam)

	draw_world()

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

init_window :: proc() -> bool {
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
	window_flags := sdl.WindowFlags{.RESIZABLE, .HIDDEN, .HIGH_PIXEL_DENSITY}

	// TODO: Proper window size settings
	// TODO: Proper indow flags settings
	g_window = sdl.CreateWindow(GAME_TITLE, i32(1280 * main_scale), i32(1080 * main_scale), window_flags)
	if g_window == nil {
		log.error("sdl.CreateWindow() failed:", sdl.GetError())
		return false
	}
	log.info("init sdl and window success")

	sdl.SetWindowPosition(g_window, sdl.WINDOWPOS_CENTERED, sdl.WINDOWPOS_CENTERED)
	sdl.ShowWindow(g_window)

	// TODO: This following stuff should maybe be moved to init instead? Depends on what is needed for hot reload

	// Create GPU Device
	// TODO: disable debug mode in release builds. Name the device
	gpu_device := sdl.CreateGPUDevice({.SPIRV, .DXIL, .MSL, .METALLIB}, true, nil)
	if gpu_device == nil {
		log.error("sdl.CreateGPUDevice() failed:", sdl.GetError())
		return false
	}

	// Claim window for GPU Device
	if !sdl.ClaimWindowForGPUDevice(gpu_device, g_window) {
		log.error("sdl.ClaimWindowForGPUDevice() failed:", sdl.GetError())
		return false
	}

	if !sdl.SetGPUSwapchainParameters(gpu_device, g_window, .SDR, .VSYNC) {
		log.error("sdl.SetGPUSwapchainParameters() failed:", sdl.GetError())
		// TODO: Maybe it's okay to continue if setting params fails? Or try backup params?
		return false
	}

	// Setup Dear ImGui context
	im.CHECKVERSION()
	im.CreateContext()
	io := im.GetIO()
	io.ConfigFlags += {.NavEnableKeyboard}
	io.ConfigFlags += {.NavEnableGamepad}
	io.ConfigFlags += {.DockingEnable}
	io.ConfigFlags += {.ViewportsEnable}

	// Setup Deaf ImGui style
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
		style.Colors[im.Col.WindowBg] = 1.0
	}

	// Setup Platform/Renderer backends
	ImGui_ImplSDL3_InitForSDLGPU(g_window)
	init_info : ImGui_ImplSDLGPU3_InitInfo
    init_info.device = gpu_device
    init_info.color_target_format = sdl.GetGPUSwapchainTextureFormat(gpu_device, g_window)
    init_info.msaa_samples = ._1                      // Only used in multi-viewports mode.
    init_info.swapchain_composition = .SDR  // Only used in multi-viewports mode.
    init_info.present_mode = .VSYNC
    ImGui_ImplSDLGPU3_Init(&init_info)

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

	log.info("init_window finished")
	return true
}

Vec2 :: [2]f32
Rect :: struct {
	x:      f32,                  // Rectangle bottom-left corner position x
	y:      f32,                  // Rectangle bottom-left corner position y
	width:  f32,                  // Rectangle width
	height: f32,                  // Rectangle height
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
	g_mem = new(Game_Memory)
	//atlas_image := rl.LoadImageFromMemory(".png", raw_data(ATLAS_DATA), i32(len(ATLAS_DATA)))

	g_mem^ = Game_Memory {
		//atlas = rl.LoadTextureFromImage(atlas_image),
		//hit_sound = rl.LoadSoundFromWave(rl.LoadWaveFromMemory(".wav", raw_data(HIT_SOUND), i32(len(HIT_SOUND)))),
		//land_sound = rl.LoadSoundFromWave(rl.LoadWaveFromMemory(".wav", raw_data(LAND_SOUND), i32(len(LAND_SOUND)))),
		//win_sound = rl.LoadSoundFromWave(rl.LoadWaveFromMemory(".wav", raw_data(WIN_SOUND), i32(len(WIN_SOUND)))),
	}
	
	//rl.SetSoundVolume(g_mem.hit_sound, 0.5)
	//rl.SetSoundVolume(g_mem.land_sound, 0.5)
	//rl.SetSoundVolume(g_mem.win_sound, 0.3)

	//rl.UnloadImage(atlas_image)

	//num_glyphs := len(atlas_glyphs)
	//font_rects := make([]Rect, num_glyphs)
	//glyphs := make([]rl.GlyphInfo, num_glyphs)

	//for ag, idx in atlas_glyphs {
	//	
	//	font_rects[idx] = ag.rect
	//	glyphs[idx] = {
	//		value = ag.value,
	//		offsetX = i32(ag.offset_x),
	//		offsetY = i32(ag.offset_y),
	//		advanceX = i32(ag.advance_x),
	//	}
	//} 

	//g_mem.font = {
	//	baseSize = ATLAS_FONT_SIZE,
	//	glyphCount = i32(num_glyphs),
	//	glyphPadding = 0,
	//	texture = g_mem.atlas,
	//	recs = raw_data(font_rects),
	//	glyphs = raw_data(glyphs),
	//}
	
	world_def := b2.DefaultWorldDef()
	world_def.gravity = GRAVITY
	world_def.enableContinous = true
	g_mem.physics_world = b2.CreateWorld(world_def)	
	
	g_mem.rc = round_cat_make({10,10}, 30.0)

	game_hot_reloaded(g_mem)
	
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
	body_def.position = b2.Vec2{rect.x + rect.width/2, rect.y + rect.height/2}
	body_def.rotation = b2.MakeRot(rot)
	w.body = b2.CreateBody(physics_world(), body_def)

	box := b2.MakeBox((rect.width/2), (rect.height/2))
	shape_def := b2.DefaultShapeDef()
	shape_def.friction = 0.7
	shape_def.filter = {
		categoryBits = u32(bit_set[Collision_Category] { .Wall }),
		maskBits = u32(bit_set[Collision_Category] { .Round_Cat, .Long_Cat }),
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
		//maskBits = u32(bit_set[Collision_Category] { .Round_Cat, .Long_Cat }),
	}

	pivot.shape = b2.CreateCircleShape(pivot.body, shape_def, circle)
	return pivot
}

shutdown :: proc() {
	log.info("shutdown...")
	//mem.free(g_mem.font.recs)
	//mem.free(g_mem.font.glyphs)
	mem.delete(g_mem.pivots)
	free(g_mem)
	log.info("shutdown complete")
}

shutdown_window :: proc() {
	log.info("shutdown sdl and window...")
	//rl.CloseAudioDevice()
	//rl.CloseWindow()
	log.info("shutdown sdl and window complete")
}

