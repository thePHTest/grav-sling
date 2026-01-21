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
g_context : runtime.Context
g_mem: ^Game_Memory
g_window: ^sdl.Window
when RENDERER_SDL_GPU {
g_gpu_device: ^sdl.GPUDevice
} else {
g_sdl_renderer: ^sdl.Renderer
}
//font: rl.Font

refresh_globals :: proc() {
	//atlas = g_mem.atlas
	//font = g_mem.font
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
		zoom = 10.0,
		//zoom = h/PIXEL_WINDOW_HEIGHT*GAME_SCALE,
		//offset = { w/2, h/2 },
	}
}

get_screen :: proc() -> Vec2 {
	w, h : i32
	sdl.GetWindowSizeInPixels(g_window, &w, &h)
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

GamepadButton :: struct {
	flags : bit_field u8 {
		pressed : bool | 1,
		repeat : bool | 1,
	},
}

GamepadAxis :: struct {
	// [-/+32767]
	pos : i16,
}

// Matches SDL except the omission of
//INVALID = -1,
EGamepadAxis :: enum {
	LEFTX,
	LEFTY,
	RIGHTX,
	RIGHTY,
	LEFT_TRIGGER,
	RIGHT_TRIGGER,
}

// Matches SDL except the omission of
//INVALID = -1,
EGamepadButton :: enum {
	SOUTH,           /**< Bottom face button (e.g. Xbox A button) */
	EAST,            /**< Right face button (e.g. Xbox B button) */
	WEST,            /**< Left face button (e.g. Xbox X button) */
	NORTH,           /**< Top face button (e.g. Xbox Y button) */
	BACK,
	GUIDE,
	START,
	LEFT_STICK,
	RIGHT_STICK,
	LEFT_SHOULDER,
	RIGHT_SHOULDER,
	DPAD_UP,
	DPAD_DOWN,
	DPAD_LEFT,
	DPAD_RIGHT,
	MISC1,           /**< Additional button (e.g. Xbox Series X share button, PS5 microphone button, Nintendo Switch Pro capture button, Amazon Luna microphone button, Google Stadia capture button) */
	RIGHT_PADDLE1,   /**< Upper or primary paddle, under your right hand (e.g. Xbox Elite paddle P1) */
	LEFT_PADDLE1,    /**< Upper or primary paddle, under your left hand (e.g. Xbox Elite paddle P3) */
	RIGHT_PADDLE2,   /**< Lower or secondary paddle, under your right hand (e.g. Xbox Elite paddle P2) */
	LEFT_PADDLE2,    /**< Lower or secondary paddle, under your left hand (e.g. Xbox Elite paddle P4) */
	TOUCHPAD,        /**< PS4/PS5 touchpad button */
	MISC2,           /**< Additional button */
	MISC3,           /**< Additional button */
	MISC4,           /**< Additional button */
	MISC5,           /**< Additional button */
	MISC6,           /**< Additional button */

}

// TODO: Array of gamepads
Gamepad_State :: struct {
	joystick_id : sdl.JoystickID,
	sdl_gamepad : ^sdl.Gamepad,
	buttons : [EGamepadButton]GamepadButton,
	axes : [EGamepadAxis]GamepadAxis,
}

g_gamepad : Gamepad_State


// This is copied from SDL.
// TODO: Trim this down to what is actually needed
EScancode :: enum {
	UNKNOWN = 0,

	/**
	*  \name Usage page 0x07
	*
	*  These values are from usage page 0x07 (USB keyboard page).
	*/
	/* @{ */

	A = 4,
	B = 5,
	C = 6,
	D = 7,
	E = 8,
	F = 9,
	G = 10,
	H = 11,
	I = 12,
	J = 13,
	K = 14,
	L = 15,
	M = 16,
	N = 17,
	O = 18,
	P = 19,
	Q = 20,
	R = 21,
	S = 22,
	T = 23,
	U = 24,
	V = 25,
	W = 26,
	X = 27,
	Y = 28,
	Z = 29,

	_1 = 30,
	_2 = 31,
	_3 = 32,
	_4 = 33,
	_5 = 34,
	_6 = 35,
	_7 = 36,
	_8 = 37,
	_9 = 38,
	_0 = 39,

	RETURN = 40,
	ESCAPE = 41,
	BACKSPACE = 42,
	TAB = 43,
	SPACE = 44,

	MINUS = 45,
	EQUALS = 46,
	LEFTBRACKET = 47,
	RIGHTBRACKET = 48,
	BACKSLASH = 49, /**< Located at the lower left of the return
	                 *   key on ISO keyboards and at the right end
	                 *   of the QWERTY row on ANSI keyboards.
	                 *   Produces REVERSE SOLIDUS (backslash) and
	                 *   VERTICAL LINE in a US layout, REVERSE
	                 *   SOLIDUS and VERTICAL LINE in a UK Mac
	                 *   layout, NUMBER SIGN and TILDE in a UK
	                 *   Windows layout, DOLLAR SIGN and POUND SIGN
	                 *   in a Swiss German layout, NUMBER SIGN and
	                 *   APOSTROPHE in a German layout, GRAVE
	                 *   ACCENT and POUND SIGN in a French Mac
	                 *   layout, and ASTERISK and MICRO SIGN in a
	                 *   French Windows layout.
	                 */
	NONUSHASH = 50, /**< ISO USB keyboards actually use this code
	                 *   instead of 49 for the same key, but all
	                 *   OSes I've seen treat the two codes
	                 *   identically. So, as an implementor, unless
	                 *   your keyboard generates both of those
	                 *   codes and your OS treats them differently,
	                 *   you should generate BACKSLASH
	                 *   instead of this code. As a user, you
	                 *   should not rely on this code because SDL
	                 *   will never generate it with most (all?)
	                 *   keyboards.
	                 */
	SEMICOLON = 51,
	APOSTROPHE = 52,
	GRAVE = 53, /**< Located in the top left corner (on both ANSI
	             *   and ISO keyboards). Produces GRAVE ACCENT and
	             *   TILDE in a US Windows layout and in US and UK
	             *   Mac layouts on ANSI keyboards, GRAVE ACCENT
	             *   and NOT SIGN in a UK Windows layout, SECTION
	             *   SIGN and PLUS-MINUS SIGN in US and UK Mac
	             *   layouts on ISO keyboards, SECTION SIGN and
	             *   DEGREE SIGN in a Swiss German layout (Mac:
	             *   only on ISO keyboards), CIRCUMFLEX ACCENT and
	             *   DEGREE SIGN in a German layout (Mac: only on
	             *   ISO keyboards), SUPERSCRIPT TWO and TILDE in a
	             *   French Windows layout, COMMERCIAL AT and
	             *   NUMBER SIGN in a French Mac layout on ISO
	             *   keyboards, and LESS-THAN SIGN and GREATER-THAN
	             *   SIGN in a Swiss German, German, or French Mac
	             *   layout on ANSI keyboards.
	             */
	COMMA = 54,
	PERIOD = 55,
	SLASH = 56,

	CAPSLOCK = 57,

	F1 = 58,
	F2 = 59,
	F3 = 60,
	F4 = 61,
	F5 = 62,
	F6 = 63,
	F7 = 64,
	F8 = 65,
	F9 = 66,
	F10 = 67,
	F11 = 68,
	F12 = 69,

	PRINTSCREEN = 70,
	SCROLLLOCK = 71,
	PAUSE = 72,
	INSERT = 73, /**< insert on PC, help on some Mac keyboards (but
	                           does send code 73, not 117) */
	HOME = 74,
	PAGEUP = 75,
	DELETE = 76,
	END = 77,
	PAGEDOWN = 78,
	RIGHT = 79,
	LEFT = 80,
	DOWN = 81,
	UP = 82,

	NUMLOCKCLEAR = 83, /**< num lock on PC, clear on Mac keyboards
	                             */
	KP_DIVIDE = 84,
	KP_MULTIPLY = 85,
	KP_MINUS = 86,
	KP_PLUS = 87,
	KP_ENTER = 88,
	KP_1 = 89,
	KP_2 = 90,
	KP_3 = 91,
	KP_4 = 92,
	KP_5 = 93,
	KP_6 = 94,
	KP_7 = 95,
	KP_8 = 96,
	KP_9 = 97,
	KP_0 = 98,
	KP_PERIOD = 99,

	NONUSBACKSLASH = 100, /**< This is the additional key that ISO
	                       *   keyboards have over ANSI ones,
	                       *   located between left shift and Y.
	                       *   Produces GRAVE ACCENT and TILDE in a
	                       *   US or UK Mac layout, REVERSE SOLIDUS
	                       *   (backslash) and VERTICAL LINE in a
	                       *   US or UK Windows layout, and
	                       *   LESS-THAN SIGN and GREATER-THAN SIGN
	                       *   in a Swiss German, German, or French
	                       *   layout. */
	APPLICATION = 101, /**< windows contextual menu, compose */
	POWER = 102, /**< The USB document says this is a status flag,
	              *   not a physical key - but some Mac keyboards
	              *   do have a power key. */
	KP_EQUALS = 103,
	F13 = 104,
	F14 = 105,
	F15 = 106,
	F16 = 107,
	F17 = 108,
	F18 = 109,
	F19 = 110,
	F20 = 111,
	F21 = 112,
	F22 = 113,
	F23 = 114,
	F24 = 115,
	EXECUTE = 116,
	HELP = 117,    /**< AL Integrated Help Center */
	MENU = 118,    /**< Menu (show menu) */
	SELECT = 119,
	STOP = 120,    /**< AC Stop */
	AGAIN = 121,   /**< AC Redo/Repeat */
	UNDO = 122,    /**< AC Undo */
	CUT = 123,     /**< AC Cut */
	COPY = 124,    /**< AC Copy */
	PASTE = 125,   /**< AC Paste */
	FIND = 126,    /**< AC Find */
	MUTE = 127,
	VOLUMEUP = 128,
	VOLUMEDOWN = 129,
	/* not sure whether there's a reason to enable these */
	/*     LOCKINGCAPSLOCK = 130,  */
	/*     LOCKINGNUMLOCK = 131, */
	/*     LOCKINGSCROLLLOCK = 132, */
	KP_COMMA = 133,
	KP_EQUALSAS400 = 134,

	INTERNATIONAL1 = 135, /**< used on Asian keyboards, see
	                                    footnotes in USB doc */
	INTERNATIONAL2 = 136,
	INTERNATIONAL3 = 137, /**< Yen */
	INTERNATIONAL4 = 138,
	INTERNATIONAL5 = 139,
	INTERNATIONAL6 = 140,
	INTERNATIONAL7 = 141,
	INTERNATIONAL8 = 142,
	INTERNATIONAL9 = 143,
	LANG1 = 144, /**< Hangul/English toggle */
	LANG2 = 145, /**< Hanja conversion */
	LANG3 = 146, /**< Katakana */
	LANG4 = 147, /**< Hiragana */
	LANG5 = 148, /**< Zenkaku/Hankaku */
	LANG6 = 149, /**< reserved */
	LANG7 = 150, /**< reserved */
	LANG8 = 151, /**< reserved */
	LANG9 = 152, /**< reserved */

	ALTERASE = 153,    /**< Erase-Eaze */
	SYSREQ = 154,
	CANCEL = 155,      /**< AC Cancel */
	CLEAR = 156,
	PRIOR = 157,
	RETURN2 = 158,
	SEPARATOR = 159,
	OUT = 160,
	OPER = 161,
	CLEARAGAIN = 162,
	CRSEL = 163,
	EXSEL = 164,

	KP_00 = 176,
	KP_000 = 177,
	THOUSANDSSEPARATOR = 178,
	DECIMALSEPARATOR = 179,
	CURRENCYUNIT = 180,
	CURRENCYSUBUNIT = 181,
	KP_LEFTPAREN = 182,
	KP_RIGHTPAREN = 183,
	KP_LEFTBRACE = 184,
	KP_RIGHTBRACE = 185,
	KP_TAB = 186,
	KP_BACKSPACE = 187,
	KP_A = 188,
	KP_B = 189,
	KP_C = 190,
	KP_D = 191,
	KP_E = 192,
	KP_F = 193,
	KP_XOR = 194,
	KP_POWER = 195,
	KP_PERCENT = 196,
	KP_LESS = 197,
	KP_GREATER = 198,
	KP_AMPERSAND = 199,
	KP_DBLAMPERSAND = 200,
	KP_VERTICALBAR = 201,
	KP_DBLVERTICALBAR = 202,
	KP_COLON = 203,
	KP_HASH = 204,
	KP_SPACE = 205,
	KP_AT = 206,
	KP_EXCLAM = 207,
	KP_MEMSTORE = 208,
	KP_MEMRECALL = 209,
	KP_MEMCLEAR = 210,
	KP_MEMADD = 211,
	KP_MEMSUBTRACT = 212,
	KP_MEMMULTIPLY = 213,
	KP_MEMDIVIDE = 214,
	KP_PLUSMINUS = 215,
	KP_CLEAR = 216,
	KP_CLEARENTRY = 217,
	KP_BINARY = 218,
	KP_OCTAL = 219,
	KP_DECIMAL = 220,
	KP_HEXADECIMAL = 221,

	LCTRL = 224,
	LSHIFT = 225,
	LALT = 226, /**< alt, option */
	LGUI = 227, /**< windows, command (apple), meta */
	RCTRL = 228,
	RSHIFT = 229,
	RALT = 230, /**< alt gr, option */
	RGUI = 231, /**< windows, command (apple), meta */

	MODE = 257,    /**< I'm not sure if this is really not covered
	                *   by any of the above, but since there's a
	                *   special SDL_KMOD_MODE for it I'm adding it here
	                */

	/* @} *//* Usage page 0x07 */

	/**
	*  \name Usage page 0x0C
	*
	*  These values are mapped from usage page 0x0C (USB consumer page).
	*
	*  There are way more keys in the spec than we can represent in the
	*  current scancode range, so pick the ones that commonly come up in
	*  real world usage.
	*/
	/* @{ */

	SLEEP = 258,                   /**< Sleep */
	WAKE = 259,                    /**< Wake */

	CHANNEL_INCREMENT = 260,       /**< Channel Increment */
	CHANNEL_DECREMENT = 261,       /**< Channel Decrement */

	MEDIA_PLAY = 262,          /**< Play */
	MEDIA_PAUSE = 263,         /**< Pause */
	MEDIA_RECORD = 264,        /**< Record */
	MEDIA_FAST_FORWARD = 265,  /**< Fast Forward */
	MEDIA_REWIND = 266,        /**< Rewind */
	MEDIA_NEXT_TRACK = 267,    /**< Next Track */
	MEDIA_PREVIOUS_TRACK = 268, /**< Previous Track */
	MEDIA_STOP = 269,          /**< Stop */
	MEDIA_EJECT = 270,         /**< Eject */
	MEDIA_PLAY_PAUSE = 271,    /**< Play / Pause */
	MEDIA_SELECT = 272,        /* Media Select */

	AC_NEW = 273,              /**< AC New */
	AC_OPEN = 274,             /**< AC Open */
	AC_CLOSE = 275,            /**< AC Close */
	AC_EXIT = 276,             /**< AC Exit */
	AC_SAVE = 277,             /**< AC Save */
	AC_PRINT = 278,            /**< AC Print */
	AC_PROPERTIES = 279,       /**< AC Properties */

	AC_SEARCH = 280,           /**< AC Search */
	AC_HOME = 281,             /**< AC Home */
	AC_BACK = 282,             /**< AC Back */
	AC_FORWARD = 283,          /**< AC Forward */
	AC_STOP = 284,             /**< AC Stop */
	AC_REFRESH = 285,          /**< AC Refresh */
	AC_BOOKMARKS = 286,        /**< AC Bookmarks */

	/* @} *//* Usage page 0x0C */


	/**
	*  \name Mobile keys
	*
	*  These are values that are often used on mobile phones.
	*/
	/* @{ */

	SOFTLEFT = 287, /**< Usually situated below the display on phones and
	                              used as a multi-function feature key for selecting
	                              a software defined function shown on the bottom left
	                              of the display. */
	SOFTRIGHT = 288, /**< Usually situated below the display on phones and
	                               used as a multi-function feature key for selecting
	                               a software defined function shown on the bottom right
	                               of the display. */
	CALL = 289, /**< Used for accepting phone calls. */
	ENDCALL = 290, /**< Used for rejecting phone calls. */

	/* @} *//* Mobile keys */

	/* Add any other keys here. */

	RESERVED = 400,    /**< 400-500 reserved for dynamic keycodes */

	_ = 511,
	// COUNT = 512 /**< not a key, just marks the number of scancodes for array bounds */
}

Key_State :: struct {
	// TODO: Fill this out and bit pack it
	pressed : bool,
}

Keyboard_State :: struct {
	keys : #sparse[EScancode]Key_State,
}
g_keyboard : Keyboard_State

gamepad_is_button_pressed :: proc(gamepad : Gamepad_State, button : EGamepadButton) -> bool {
	return gamepad.buttons[button].flags.pressed
}

gamepad_axis_normalize :: proc(gamepad : Gamepad_State, axis : EGamepadAxis) -> f32 {
	return f32(gamepad.axes[axis].pos) / f32(max(i16))
}

keyboard_is_key_pressed :: proc(keyboard : Keyboard_State, key : EScancode) -> bool {
	return keyboard.keys[key].pressed
}

poll_input :: proc() {
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
		if event.type == .WINDOW_CLOSE_REQUESTED && event.window.windowID == sdl.GetWindowID(g_window) {
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
			// TODO: Is this window id handling correct?
			g_gamepad.buttons[EGamepadButton(event.gbutton.button)].flags.pressed = event.gbutton.down 

			case .GAMEPAD_AXIS_MOTION:
			g_gamepad.axes[EGamepadAxis(event.gaxis.axis)].pos = event.gaxis.value

			case .KEY_DOWN:
			fallthrough
			case .KEY_UP:
			g_keyboard.keys[EScancode(event.key.scancode)].pressed = event.key.down
		}
	}

	// [If using SDL_MAIN_USE_CALLBACKS: all code below would likely be your SDL_AppIterate() function]
	if .MINIMIZED in sdl.GetWindowFlags(g_window) {
		sdl.Delay(10)
		return
	}
}

show_demo_window := true
show_another_window := false
clear_color := [3]f32{0.45, 0.55, 0.60}
update :: proc(t: f64, dt: f64) {
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

	b2.World_Step(physics_world(), f32(dt), 4)	
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
		r.w,
		r.h,
	}
}

rect_flip :: proc(r: Rect) -> Rect {
	return {
		r.x, -r.y - r.h,
		r.w, r.h,
	}
}

wall_render :: proc(wall : Wall, camera : Camera2D, screen : Vec2) {
	screen_rect := rect_world_to_screen(wall.rect, camera, screen)
	sdl.SetRenderDrawColor(g_sdl_renderer, 0, 255, 0, 255)
	sdl.RenderFillRect(g_sdl_renderer, cast(^sdl.FRect)&screen_rect)
}

pivot_render :: proc(pivot: Pivot) {
	//rl.DrawCircleV(vec2_flip(pivot.pos), pivot.radius, rl.YELLOW)
}

world_render :: proc(camera : Camera2D, screen : Vec2, alpha : f64) {

	// Draw the origin
	sdl.SetRenderDrawColor(g_sdl_renderer, 255, 0, 0, 255)
	origin_dim :: 1.0
	origin_screen_rect := rect_world_to_screen(Rect{-0.5*origin_dim, -0.5*origin_dim, origin_dim, origin_dim}, camera, screen)
	sdl.RenderFillRect(g_sdl_renderer, cast(^sdl.FRect)&origin_screen_rect)

	round_cat_render(g_mem.rc, camera, screen, alpha)
	wall_render(g_mem.left_wall, camera, screen)
	wall_render(g_mem.right_wall, camera, screen)
	wall_render(g_mem.top_wall, camera, screen)
	wall_render(g_mem.bottom_wall, camera, screen)
	
	for pivot in g_mem.pivots {
		pivot_render(pivot)
	}
	
	// Origin
	//rl.DrawCircle(0,0, 0.5 + 0.5*((1.0 + math.sin(f32(rl.GetTime()))) / 2.0), rl.BLACK)
}

hi_res_time_in_seconds :: proc() -> f64 {
	@(static) start_counter : u64
	@(static) frequency : u64
	// TODO: Way to avoid this if check overhead? Does it matter?
	if start_counter == 0 {
		start_counter = sdl.GetPerformanceCounter()
		frequency = sdl.GetPerformanceFrequency()
	}

	current_counter := sdl.GetPerformanceCounter()
	return f64(current_counter - start_counter) / f64(frequency)
}

im_render :: proc() {
	// Start the Dear ImGui frame
	when RENDERER_SDL_GPU {
		ImGui_ImplSDLGPU3_NewFrame()
	} else {
		ImGui_ImplSDLRenderer3_NewFrame()
	}
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

	// Rendering
	when RENDERER_SDL_GPU {
		im.Render()
		draw_data := im.GetDrawData()
		is_minimized := draw_data.DisplaySize.x <= 0.0 || draw_data.DisplaySize.y <= 0.0

		command_buffer := sdl.AcquireGPUCommandBuffer(g_gpu_device) // Acquire a GPU command buffer

		swapchain_texture : ^sdl.GPUTexture
		if !sdl.WaitAndAcquireGPUSwapchainTexture(command_buffer, g_window, &swapchain_texture, nil, nil) {// Acquire a swapchain texture
			log.error("sdl.WaitAndAcquireGPUSwapchainTexture() failed:", sdl.GetError())
		}

		if swapchain_texture != nil && !is_minimized {
			// This is mandatory: call ImGui_ImplSDLGPU3_PrepareDrawData() to upload the vertex/index buffer!
			ImGui_ImplSDLGPU3_PrepareDrawData(draw_data, command_buffer)

			// Setup and start a render pass
			target_info : sdl.GPUColorTargetInfo
			target_info.texture = swapchain_texture
			target_info.clear_color = sdl.FColor { clear_color.x, clear_color.y, clear_color.z, 1.0 }
			target_info.load_op = .CLEAR
			target_info.store_op = .STORE
			target_info.mip_level = 0
			target_info.layer_or_depth_plane = 0
			target_info.cycle = false
			render_pass := sdl.BeginGPURenderPass(command_buffer, &target_info, 1, nil)

			// Render ImGui
			ImGui_ImplSDLGPU3_RenderDrawData(draw_data, command_buffer, render_pass)

			sdl.EndGPURenderPass(render_pass)
		}

		io := im.GetIO()
		// Update and Render additional Platform Windows
		if .ViewportsEnable in io.ConfigFlags {
			im.UpdatePlatformWindows()
			im.RenderPlatformWindowsDefault()
		}

		// Submit the command buffer
		if !sdl.SubmitGPUCommandBuffer(command_buffer) {
			log.error("sdl.SubmitGPUCommandBuffer() failed:", sdl.GetError())
		}
	} else {
		im.Render()
		io := im.GetIO()
        sdl.SetRenderScale(g_sdl_renderer, io.DisplayFramebufferScale.x, io.DisplayFramebufferScale.y)
        sdl.SetRenderDrawColorFloat(g_sdl_renderer, clear_color.x, clear_color.y, clear_color.z, 1.0)
        sdl.RenderClear(g_sdl_renderer)
        ImGui_ImplSDLRenderer3_RenderDrawData(im.GetDrawData(), g_sdl_renderer)
	}


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

	sdl.SetRenderDrawColor(g_sdl_renderer, 0, 0, 0, 255)
	sdl.RenderClear(g_sdl_renderer)
	world_render(game_cam, screen, alpha)
	//im_render()
	sdl.RenderPresent(g_sdl_renderer)

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

im_init :: proc(main_scale : f32) {
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
	// Setup Dear ImGui context
	im.CHECKVERSION()
	im.SetAllocatorFunctions(im_mem_alloc_func, im_mem_free_func)
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
		style.Colors[im.Col.WindowBg].w = 1.0
	}

	when RENDERER_SDL_GPU {
		// Setup Platform/Renderer backends
		ImGui_ImplSDL3_InitForSDLGPU(g_window)
		init_info : ImGui_ImplSDLGPU3_InitInfo
		init_info.device = g_gpu_device
		init_info.color_target_format = sdl.GetGPUSwapchainTextureFormat(g_gpu_device, g_window)
		init_info.msaa_samples = ._1                      // Only used in multi-viewports mode.
		init_info.swapchain_composition = .SDR  // Only used in multi-viewports mode.
		init_info.present_mode = .VSYNC
		ImGui_ImplSDLGPU3_Init(&init_info)
	} else {
		ImGui_ImplSDL3_InitForSDLRenderer(g_window, g_sdl_renderer)
		ImGui_ImplSDLRenderer3_Init(g_sdl_renderer)
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
	window_flags := sdl.WindowFlags{.RESIZABLE, .HIDDEN, .HIGH_PIXEL_DENSITY}

	// TODO: Proper window size settings
	// TODO: Proper indow flags setting
	//g_window = sdl.CreateWindow(GAME_TITLE, i32(1920 * main_scale), i32(1080 * main_scale), window_flags)
	g_window = sdl.CreateWindow(GAME_TITLE, i32(1920), i32(1080), window_flags)
	if g_window == nil {
		log.error("sdl.CreateWindow() failed:", sdl.GetError())
		return false
	}
	log.info("init sdl and window success")

	when !RENDERER_SDL_GPU {
		g_sdl_renderer = sdl.CreateRenderer(g_window, nil)
		sdl.SetRenderVSync(g_sdl_renderer, 1)
		if g_sdl_renderer == nil {
			log.error("Error: SDL_CreateRenderer(): %s\n", sdl.GetError())
			return false
		}
	}

	sdl.SetWindowPosition(g_window, sdl.WINDOWPOS_CENTERED, sdl.WINDOWPOS_CENTERED)
	sdl.ShowWindow(g_window)

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
		if !sdl.ClaimWindowForGPUDevice(g_gpu_device, g_window) {
			log.error("sdl.ClaimWindowForGPUDevice() failed:", sdl.GetError())
			return false
		}

		if !sdl.SetGPUSwapchainParameters(g_gpu_device, g_window, .SDR, .VSYNC) {
			log.error("sdl.SetGPUSwapchainParameters() failed:", sdl.GetError())
			// TODO: Maybe it's okay to continue if setting params fails? Or try backup params?
			return false
		}
	}

	im_init(main_scale)

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
	body_def.position = b2.Vec2{rect.x + rect.w/2, rect.y + rect.h/2}
	body_def.rotation = b2.MakeRot(rot)
	w.body = b2.CreateBody(physics_world(), body_def)

	box := b2.MakeBox((rect.w/2), (rect.h/2))
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
		sdl.ReleaseWindowFromGPUDevice(g_gpu_device, g_window)
		sdl.DestroyGPUDevice(g_gpu_device)
		sdl.DestroyWindow(g_window)
		sdl.Quit()
	} else {
		// Shutdown imgui
		ImGui_ImplSDLRenderer3_Shutdown()
		ImGui_ImplSDL3_Shutdown()
		im.DestroyContext()

		// Shutdown sdl
		sdl.DestroyRenderer(g_sdl_renderer)
		sdl.DestroyWindow(g_window)
		sdl.Quit()
	}
	log.info("shutdown sdl and window complete")
}

