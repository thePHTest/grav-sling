package game

import b2 "box2d"
import rl "vendor:raylib"
import im "deps:odin-imgui"
import "core:fmt"
import "core:math"
import "core:mem"
import "core:strings"

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
	atlas: rl.Texture2D,
	
	pivots: [dynamic]Pivot,
	
	left_wall: Wall,
	right_wall: Wall,
	top_wall: Wall,
	bottom_wall: Wall,

	time_accumulator: f32,

	won: bool,
	won_at: f64,

	finished: bool,
	font: rl.Font,


	// sounds
	hit_sound: rl.Sound,
	land_sound: rl.Sound,
	win_sound: rl.Sound,
}

atlas: rl.Texture2D
g_mem: ^Game_Memory
font: rl.Font

refresh_globals :: proc() {
	atlas = g_mem.atlas
	font = g_mem.font
}

GAME_SCALE :: 10

game_camera :: proc() -> rl.Camera2D {
	w := f32(rl.GetScreenWidth())
	h := f32(rl.GetScreenHeight())

	return {
		zoom = h/PIXEL_WINDOW_HEIGHT*GAME_SCALE,
		//target = vec2_flip(round_cat_pos(g_mem.rc)),
		offset = { w/2, h/2 },
	}
}

ui_camera :: proc() -> rl.Camera2D {
	return {
		zoom = f32(rl.GetScreenHeight())/PIXEL_WINDOW_HEIGHT,
	}
}

physics_world :: proc() -> b2.WorldId {
	return g_mem.physics_world
}

dt: f32
real_dt: f32

got_tuna :: proc() {
	g_mem.won = true
	g_mem.won_at = rl.GetTime()
	rl.PlaySound(g_mem.win_sound)
}

update :: proc() {
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
	mid := Vec2 {wall.rect.width/2, wall.rect.height/2}
	rl.DrawRectanglePro(rect_offset(rect_flip(wall.rect), mid), mid, -wall.rot*RAD2DEG, rl.DARKGREEN)
}

draw_pivot :: proc(pivot: Pivot) {
	rl.DrawCircleV(vec2_flip(pivot.pos), pivot.radius, rl.YELLOW)
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
	rl.DrawCircle(0,0, 0.5 + 0.5*((1.0 + math.sin(f32(rl.GetTime()))) / 2.0), rl.BLACK)
}

draw :: proc() {
	//debug_draw()
	rl.BeginDrawing()
	//t := f32(rl.GetTime())
	game_cam := game_camera()

	rl.DrawRectangleRec({0, 0, f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}, rl.WHITE)
	rl.ClearBackground({0, 120, 153, 255})
	rl.BeginMode2D(game_cam)

	draw_world()

	rl.EndMode2D()
	rl.BeginMode2D(ui_camera())


	if g_mem.finished {
		rl.DrawTextEx(font, "YOU DID IT!! YOU FOUND\nTHE THREE MAGICAL\nTUNA CANS!!!\n\nGOOD BYE", {40, 40}, 20, 0, rl.WHITE)
	} else if g_mem.won {
		rl.DrawTextEx(font, "YAY!!! TUNA", {40, 40}, 40, 0, rl.WHITE)
	}

	rl.EndMode2D()
	rl.EndDrawing()
}

LEVEL_1_POS :: Vec2 {70, 70+10}
LEVEL_2_POS :: Vec2 {70, 90+10}
LEVEL_3_POS :: Vec2 {70, 110+10}
QUIT_POS :: Vec2 {70, 130+10}

MENU_BUTTON_SIZE :: Vec2 {120, 20}

get_world_mouse_pos :: proc(cam: rl.Camera2D) -> Vec2 {
	return vec2_flip(rl.GetScreenToWorld2D(rl.GetMousePosition(), cam))
}

get_mouse_pos :: proc() -> Vec2 {
	return vec2_flip(rl.GetMousePosition())
}


vec2_flip :: proc(p: Vec2) -> Vec2 {
	return {
		p.x, -p.y,
	}
}

IS_WASM :: ODIN_ARCH == .wasm32 || ODIN_ARCH == .wasm64p32

init_window :: proc() {
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
}

Vec2 :: [2]f32
Rect :: rl.Rectangle // x and y are bottom left
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
	atlas_image := rl.LoadImageFromMemory(".png", raw_data(ATLAS_DATA), i32(len(ATLAS_DATA)))

	g_mem^ = Game_Memory {
		atlas = rl.LoadTextureFromImage(atlas_image),
		hit_sound = rl.LoadSoundFromWave(rl.LoadWaveFromMemory(".wav", raw_data(HIT_SOUND), i32(len(HIT_SOUND)))),
		land_sound = rl.LoadSoundFromWave(rl.LoadWaveFromMemory(".wav", raw_data(LAND_SOUND), i32(len(LAND_SOUND)))),
		win_sound = rl.LoadSoundFromWave(rl.LoadWaveFromMemory(".wav", raw_data(WIN_SOUND), i32(len(WIN_SOUND)))),
	}
	
	rl.SetSoundVolume(g_mem.hit_sound, 0.5)
	rl.SetSoundVolume(g_mem.land_sound, 0.5)
	rl.SetSoundVolume(g_mem.win_sound, 0.3)

	rl.UnloadImage(atlas_image)

	num_glyphs := len(atlas_glyphs)
	font_rects := make([]Rect, num_glyphs)
	glyphs := make([]rl.GlyphInfo, num_glyphs)

	for ag, idx in atlas_glyphs {
		
		font_rects[idx] = ag.rect
		glyphs[idx] = {
			value = ag.value,
			offsetX = i32(ag.offset_x),
			offsetY = i32(ag.offset_y),
			advanceX = i32(ag.advance_x),
		}
	} 

	g_mem.font = {
		baseSize = ATLAS_FONT_SIZE,
		glyphCount = i32(num_glyphs),
		glyphPadding = 0,
		texture = g_mem.atlas,
		recs = raw_data(font_rects),
		glyphs = raw_data(glyphs),
	}
	
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
	mem.free(g_mem.font.recs)
	mem.free(g_mem.font.glyphs)
	mem.delete(g_mem.pivots)
	free(g_mem)
}

shutdown_window :: proc() {
	rl.CloseAudioDevice()
	rl.CloseWindow()
}

