package game

// TODO: If ever targeting wasm/emscripten or mobile, need to set this to 0
SDL_HAS_CAPTURE_AND_GLOBAL_MOUSE :: true

import im "deps:odin-imgui"
import sdl "vendor:sdl3"
import "core:c"
import "core:c/libc"
import "core:fmt"
import "core:math"
import "base:runtime"
import "core:strings"
import "core:sys/windows"
import vk "vendor:vulkan"

// (Info: SDL3 is a cross-platform general purpose library for handling windows, inputs, graphics context creation, etc.)

// Implemented features:
//  [X] Platform: Clipboard support.
//  [X] Platform: Mouse support. Can discriminate Mouse/TouchScreen.
//  [X] Platform: Keyboard support. Since 1.87 we are using the io.AddKeyEvent() function. Pass ImGuiKey values to all key functions e.g. ImGui::IsKeyPressed(ImGuiKey_Space). [Legacy SDL_SCANCODE_* values are obsolete since 1.87 and not supported since 1.91.5]
//  [X] Platform: Gamepad support.
//  [X] Platform: Mouse cursor shape and visibility (ImGuiBackendFlags_HasMouseCursors). Disable with 'io.ConfigFlags |= ImGuiConfigFlags_NoMouseCursorChange'.
//  [x] Platform: Multi-viewport support (multiple windows). Enable with 'io.ConfigFlags |= ImGuiConfigFlags_ViewportsEnable' -> the OS animation effect when window gets created/destroyed is problematic. SDL2 backend doesn't have issue.
// Missing features or Issues:
//  [ ] Platform: Multi-viewport: Minimized windows seems to break mouse wheel events (at least under Windows).
//  [x] Platform: IME support. Position somehow broken in SDL3 + app needs to call 'SDL_SetHint(SDL_HINT_IME_SHOW_UI, "1");' before SDL_CreateWindow()!.

// You can use unmodified imgui_impl_* files in your project. See examples/ folder for examples of using this.
// Prefer including the entire imgui/ repository into your project (either as a copy or as a submodule), and only build the backends you need.
// Learn about Dear ImGui:
// - FAQ                  https://dearimgui.com/faq
// - Getting Started      https://dearimgui.com/getting-started
// - Documentation        https://dearimgui.com/docs (same as your local docs/ folder).
// - Introduction, links and more at the top of imgui.cpp

// CHANGELOG
// (minor and older changes stripped away, please see git history for details)
//  2025-XX-XX: Platform: Added support for multiple windows via the ImGuiPlatformIO interface.
//  2025-11-05: Fixed an issue with missing characters events when an already active text field changes viewports. (#9054)
//  2025-10-22: Fixed Platform_OpenInShellFn() return value (unused in core).
//  2025-09-24: Skip using the SDL_GetGlobalMouseState() state when one of our window is hovered, as the SDL_EVENT_MOUSE_MOTION data is reliable. Fix macOS notch mouse coordinates issue in fullscreen mode + better perf on X11. (#7919, #7786)
//  2025-09-18: Call platform_io.ClearPlatformHandlers() on shutdown.
//  2025-09-15: Use SDL_GetWindowDisplayScale() on Mac to output DisplayFrameBufferScale. The function is more reliable during resolution changes e.g. going fullscreen. (#8703, #4414)
//  2025-06-27: IME: avoid calling SDL_StartTextInput() again if already active. (#8727)
//  2025-05-15: [Docking] Add Platform_GetWindowFramebufferScale() handler, to allow varying Retina display density on multiple monitors.
//  2025-05-06: [Docking] macOS: fixed secondary viewports not appearing on other monitors before of parenting.
//  2025-04-09: [Docking] Revert update monitors and work areas information every frame. Only do it on Windows. (#8415, #8558)
//  2025-04-22: IME: honor ImGuiPlatformImeData->WantTextInput as an alternative way to call SDL_StartTextInput(), without IME being necessarily visible.
//  2025-04-09: Don't attempt to call SDL_CaptureMouse() on drivers where we don't call SDL_GetGlobalMouseState(). (#8561)
//  2025-03-30: Update for SDL3 api changes: Revert SDL_GetClipboardText() memory ownership change. (#8530, #7801)
//  2025-03-21: Fill gamepad inputs and set ImGuiBackendFlags_HasGamepad regardless of ImGuiConfigFlags_NavEnableGamepad being set.
//  2025-03-10: When dealing with OEM keys, use scancodes instead of translated keycodes to choose ImGuiKey values. (#7136, #7201, #7206, #7306, #7670, #7672, #8468)
//  2025-02-26: Only start SDL_CaptureMouse() when mouse is being dragged, to mitigate issues with e.g.Linux debuggers not claiming capture back. (#6410, #3650)
//  2025-02-25: [Docking] Revert to use SDL_GetDisplayBounds() for WorkPos/WorkRect if SDL_GetDisplayUsableBounds() failed.
//  2025-02-24: Avoid calling SDL_GetGlobalMouseState() when mouse is in relative mode.
//  2025-02-21: [Docking] Update monitors and work areas information every frame, as the later may change regardless of monitor changes. (#8415)
//  2025-02-18: Added ImGuiMouseCursor_Wait and ImGuiMouseCursor_Progress mouse cursor support.
//  2025-02-10: Using SDL_OpenURL() in platform_io.Platform_OpenInShellFn handler.
//  2025-01-20: Made ImGui_ImplSDL3_SetGamepadMode(ImGui_ImplSDL3_GamepadMode_Manual) accept an empty array.
//  2024-10-24: Emscripten: SDL_EVENT_MOUSE_WHEEL event doesn't require dividing by 100.0f on Emscripten.
//  2024-09-11: (Docking) Added support for viewport->ParentViewportId field to support parenting at OS level. (#7973)
//  2024-09-03: Update for SDL3 api changes: SDL_GetGamepads() memory ownership revert. (#7918, #7898, #7807)
//  2024-08-22: moved some OS/backend related function pointers from ImGuiIO to ImGuiPlatformIO:
//               - io.GetClipboardTextFn    -> platform_io.Platform_GetClipboardTextFn
//               - io.SetClipboardTextFn    -> platform_io.Platform_SetClipboardTextFn
//               - io.PlatformSetImeDataFn  -> platform_io.Platform_SetImeDataFn
//  2024-08-19: Storing SDL_WindowID inside ImGuiViewport::PlatformHandle instead of SDL_Window*.
//  2024-08-19: ImGui_ImplSDL3_ProcessEvent() now ignores events intended for other SDL windows. (#7853)
//  2024-07-22: Update for SDL3 api changes: SDL_GetGamepads() memory ownership change. (#7807)
//  2024-07-18: Update for SDL3 api changes: SDL_GetClipboardText() memory ownership change. (#7801)
//  2024-07-15: Update for SDL3 api changes: SDL_GetProperty() change to SDL_GetPointerProperty(). (#7794)
//  2024-07-02: Update for SDL3 api changes: SDLK_x renames and SDLK_KP_x removals (#7761, #7762).
//  2024-07-01: Update for SDL3 api changes: SDL_SetTextInputRect() changed to SDL_SetTextInputArea().
//  2024-06-26: Update for SDL3 api changes: SDL_StartTextInput()/SDL_StopTextInput()/SDL_SetTextInputRect() functions signatures.
//  2024-06-24: Update for SDL3 api changes: SDL_EVENT_KEY_DOWN/SDL_EVENT_KEY_UP contents.
//  2024-06-03; Update for SDL3 api changes: SDL_SYSTEM_CURSOR_ renames.
//  2024-05-15: Update for SDL3 api changes: SDLK_ renames.
//  2024-04-15: Inputs: Re-enable calling SDL_StartTextInput()/SDL_StopTextInput() as SDL3 no longer enables it by default and should play nicer with IME.
//  2024-02-13: Inputs: Fixed gamepad support. Handle gamepad disconnection. Added ImGui_ImplSDL3_SetGamepadMode().
//  2023-11-13: Updated for recent SDL3 API changes.
//  2023-10-05: Inputs: Added support for extra ImGuiKey values: F13 to F24 function keys, app back/forward keys.
//  2023-05-04: Fixed build on Emscripten/iOS/Android. (#6391)
//  2023-04-06: Inputs: Avoid calling SDL_StartTextInput()/SDL_StopTextInput() as they don't only pertain to IME. It's unclear exactly what their relation is to IME. (#6306)
//  2023-04-04: Inputs: Added support for io.AddMouseSourceEvent() to discriminate ImGuiMouseSource_Mouse/ImGuiMouseSource_TouchScreen. (#2702)
//  2023-02-23: Accept SDL_GetPerformanceCounter() not returning a monotonically increasing value. (#6189, #6114, #3644)
//  2023-02-07: Forked "imgui_impl_sdl2" into "imgui_impl_sdl3". Removed version checks for old feature. Refer to imgui_impl_sdl2.cpp for older changelog.

// Gamepad selection automatically starts in AutoFirst mode, picking first available SDL_Gamepad. You may override this.
// When using manual mode, caller is responsible for opening/closing gamepad.
ImGui_ImplSDL3_GamepadMode :: enum{
	AutoFirst, 
	AutoAll,
	Manual,
}

// SDL Data
ImGui_ImplSDL3_Data :: struct {
	window : ^sdl.Window,
    window_id : sdl.WindowID,
    renderer: ^sdl.Renderer,
    time: u64,
    clipboard_text_data: cstring,
    backend_platform_name: string,
	use_vulkan: bool,
	want_update_monitors: bool,

    // IME handling
    ime_window: ^sdl.Window,
    ime_data: im.PlatformImeData,
    ime_dirty: bool,

    // Mouse handling
    mouse_window_id: u32,
    mouse_buttons_down: int,
    mouse_cursors: [im.MouseCursor.COUNT]^sdl.Cursor,
    mouse_last_cursor: ^sdl.Cursor,
	mouse_pending_leave_frame: int,
    mouse_can_use_global_state: bool,
    mouse_can_use_capture: bool,
	mouse_can_report_hovered_viewport: bool, // This is hard to use/unreliable on SDL so we'll set ImGuiBackendFlags_HasMouseHoveredViewport dynamically based on state.

    // Gamepad handling
    gamepads: [dynamic]^sdl.Gamepad,
    gamepad_mode: ImGui_ImplSDL3_GamepadMode,
    want_update_gamepads_list: bool,

	// @ph_begin
	// dear_bindings doesn't providing an interface to interact with ImVector<T> types so we will
	// handle them here and then assign to Size,Capacity,Data as needed
	platform_io_monitors : [dynamic]im.PlatformMonitor,
	// @ph_end
}

// Backend data stored in io.BackendPlatformUserData to allow support for multiple Dear ImGui contexts
// It is STRONGLY preferred that you use docking branch with multi-viewports (== single Dear ImGui context + multiple windows) instead of multiple Dear ImGui contexts.
// FIXME: multi-context support is not well tested and probably dysfunctional in this backend.
// FIXME: some shared resources (mouse cursor shape, gamepad) are mishandled when using multi-context.
ImGui_ImplSDL3_GetBackendData :: proc "contextless" () -> ^ImGui_ImplSDL3_Data {
    return im.GetCurrentContext() != nil ? (^ImGui_ImplSDL3_Data)(im.GetIO().BackendPlatformUserData) : nil
}

// Functions
ImGui_ImplSDL3_GetClipboardText :: proc "c" (im_ctx : ^im.Context) -> cstring {
    bd := ImGui_ImplSDL3_GetBackendData()
    if bd.clipboard_text_data != nil {
        sdl.free(cast([^]u8)bd.clipboard_text_data)
	}
    bd.clipboard_text_data = cstring(sdl.GetClipboardText())
    return bd.clipboard_text_data
}

ImGui_ImplSDL3_SetClipboardText :: proc "c" (im_ctx : ^im.Context, text : cstring) {
    sdl.SetClipboardText(text)
}

ImGui_ImplSDL3_GetViewportForWindowID :: proc(window_id : sdl.WindowID) -> ^im.Viewport {
	// TODO: Is the cast here correct?
    return im.FindViewportByPlatformHandle(rawptr(uintptr(window_id)))
}

ImGui_ImplSDL3_PlatformSetImeData :: proc "c" (ctx : ^im.Context, viewport : ^im.Viewport, data : ^im.PlatformImeData) {
	bd := ImGui_ImplSDL3_GetBackendData()
    bd.ime_data = data^
    bd.ime_dirty = true
    ImGui_ImplSDL3_UpdateIme()
}

// We discard viewport passed via ImGuiPlatformImeData and always call SDL_StartTextInput() on SDL_GetKeyboardFocus().
ImGui_ImplSDL3_UpdateIme :: proc "contextless" () {
	// TODO: Assign global logger in this function
	context = runtime.default_context()
	bd := ImGui_ImplSDL3_GetBackendData()
    data := &bd.ime_data
    window := sdl.GetKeyboardFocus()

    // Stop previous input
    if ((!(data.WantVisible || data.WantTextInput) || bd.ime_window != window) && bd.ime_window != nil) {
        if sdl.StopTextInput(bd.ime_window) {
			bd.ime_window = nil
		} else {
			// TODO: Use log
			fmt.println("sdl.StopTextInput() failed:", sdl.GetError())
		}
    }
    if ((!bd.ime_dirty && bd.ime_window == window) || (window == nil)) {
        return
	}

    // Start/update current input
    bd.ime_dirty = false
    if (data.WantVisible) {
		viewport_pos : im.Vec2
        if viewport := ImGui_ImplSDL3_GetViewportForWindowID(sdl.GetWindowID(window)); viewport != nil {
            viewport_pos = viewport.Pos
		}
		r : sdl.Rect
        r.x = i32((data.InputPos.x - viewport_pos.x))
        r.y = i32((data.InputPos.y - viewport_pos.y + data.InputLineHeight))
        r.w = 1
        r.h = i32(data.InputLineHeight)
        if sdl.SetTextInputArea(window, &r, 0) {
			bd.ime_window = window
		} else {
			// TODO: Use log
			fmt.println("sdl.SetTextInputArea() failed:", sdl.GetError())
		}
    }
    if !sdl.TextInputActive(window) && (data.WantVisible || data.WantTextInput) {
        if !sdl.StartTextInput(window) {
			// TODO: Use log
			fmt.println("sdl.StartTextInput() failed:", sdl.GetError())
		}
	}
}

ImGui_ImplSDL3_KeyEventToImGuiKey :: proc(keycode : sdl.Keycode, scancode : sdl.Scancode) -> im.Key {
    // Keypad doesn't have individual key values in SDL3
	#partial switch scancode {
	case .KP_0: return .Keypad0
	case .KP_1: return .Keypad1
	case .KP_2: return .Keypad2
	case .KP_3: return .Keypad3
	case .KP_4: return .Keypad4
	case .KP_5: return .Keypad5
	case .KP_6: return .Keypad6
	case .KP_7: return .Keypad7
	case .KP_8: return .Keypad8
	case .KP_9: return .Keypad9
	case .KP_PERIOD: return .KeypadDecimal
	case .KP_DIVIDE: return .KeypadDivide
	case .KP_MULTIPLY: return .KeypadMultiply
	case .KP_MINUS: return .KeypadSubtract
	case .KP_PLUS: return .KeypadAdd
	case .KP_ENTER: return .KeypadEnter
	case .KP_EQUALS: return .KeypadEqual
	case: break
    }
    switch keycode {
	case sdl.K_TAB: return .Tab
	case sdl.K_LEFT: return .LeftArrow
	case sdl.K_RIGHT: return .RightArrow
	case sdl.K_UP: return .UpArrow
	case sdl.K_DOWN: return .DownArrow
	case sdl.K_PAGEUP: return .PageUp
	case sdl.K_PAGEDOWN: return .PageDown
	case sdl.K_HOME: return .Home
	case sdl.K_END: return .End
	case sdl.K_INSERT: return .Insert
	case sdl.K_DELETE: return .Delete
	case sdl.K_BACKSPACE: return .Backspace
	case sdl.K_SPACE: return .Space
	case sdl.K_RETURN: return .Enter
	case sdl.K_ESCAPE: return .Escape
	//case sdl.K_APOSTROPHE: return .Apostrophe
	case sdl.K_COMMA: return .Comma
	//case sdl.K_MINUS: return .Minus
	case sdl.K_PERIOD: return .Period
	//case sdl.K_SLASH: return .Slash
	case sdl.K_SEMICOLON: return .Semicolon
	//case sdl.K_EQUALS: return .Equal
	//case sdl.K_LEFTBRACKET: return .LeftBracket
	//case sdl.K_BACKSLASH: return .Backslash
	//case sdl.K_RIGHTBRACKET: return .RightBracket
	//case sdl.K_GRAVE: return .GraveAccent
	case sdl.K_CAPSLOCK: return .CapsLock
	case sdl.K_SCROLLLOCK: return .ScrollLock
	case sdl.K_NUMLOCKCLEAR: return .NumLock
	case sdl.K_PRINTSCREEN: return .PrintScreen
	case sdl.K_PAUSE: return .Pause
	case sdl.K_LCTRL: return .LeftCtrl
	case sdl.K_LSHIFT: return .LeftShift
	case sdl.K_LALT: return .LeftAlt
	case sdl.K_LGUI: return .LeftSuper
	case sdl.K_RCTRL: return .RightCtrl
	case sdl.K_RSHIFT: return .RightShift
	case sdl.K_RALT: return .RightAlt
	case sdl.K_RGUI: return .RightSuper
	case sdl.K_APPLICATION: return .Menu
	case sdl.K_0: return ._0
	case sdl.K_1: return ._1
	case sdl.K_2: return ._2
	case sdl.K_3: return ._3
	case sdl.K_4: return ._4
	case sdl.K_5: return ._5
	case sdl.K_6: return ._6
	case sdl.K_7: return ._7
	case sdl.K_8: return ._8
	case sdl.K_9: return ._9
	case sdl.K_A: return .A
	case sdl.K_B: return .B
	case sdl.K_C: return .C
	case sdl.K_D: return .D
	case sdl.K_E: return .E
	case sdl.K_F: return .F
	case sdl.K_G: return .G
	case sdl.K_H: return .H
	case sdl.K_I: return .I
	case sdl.K_J: return .J
	case sdl.K_K: return .K
	case sdl.K_L: return .L
	case sdl.K_M: return .M
	case sdl.K_N: return .N
	case sdl.K_O: return .O
	case sdl.K_P: return .P
	case sdl.K_Q: return .Q
	case sdl.K_R: return .R
	case sdl.K_S: return .S
	case sdl.K_T: return .T
	case sdl.K_U: return .U
	case sdl.K_V: return .V
	case sdl.K_W: return .W
	case sdl.K_X: return .X
	case sdl.K_Y: return .Y
	case sdl.K_Z: return .Z
	case sdl.K_F1: return .F1
	case sdl.K_F2: return .F2
	case sdl.K_F3: return .F3
	case sdl.K_F4: return .F4
	case sdl.K_F5: return .F5
	case sdl.K_F6: return .F6
	case sdl.K_F7: return .F7
	case sdl.K_F8: return .F8
	case sdl.K_F9: return .F9
	case sdl.K_F10: return .F10
	case sdl.K_F11: return .F11
	case sdl.K_F12: return .F12
	case sdl.K_F13: return .F13
	case sdl.K_F14: return .F14
	case sdl.K_F15: return .F15
	case sdl.K_F16: return .F16
	case sdl.K_F17: return .F17
	case sdl.K_F18: return .F18
	case sdl.K_F19: return .F19
	case sdl.K_F20: return .F20
	case sdl.K_F21: return .F21
	case sdl.K_F22: return .F22
	case sdl.K_F23: return .F23
	case sdl.K_F24: return .F24
	case sdl.K_AC_BACK: return .AppBack
	case sdl.K_AC_FORWARD: return .AppForward
	case: break
    }

    // Fallback to scancode
	#partial switch scancode {
    case .GRAVE: return .GraveAccent
    case .MINUS: return .Minus
    case .EQUALS: return .Equal
    case .LEFTBRACKET: return .LeftBracket
    case .RIGHTBRACKET: return .RightBracket
    case .NONUSBACKSLASH: return .Oem102
    case .BACKSLASH: return .Backslash
    case .SEMICOLON: return .Semicolon
    case .APOSTROPHE: return .Apostrophe
    case .COMMA: return .Comma
    case .PERIOD: return .Period
    case .SLASH: return .Slash
    case: break
    }
    return .None
}

ImGui_ImplSDL3_UpdateKeyModifiers :: proc(sdl_key_mods : sdl.Keymod) {
	io := im.GetIO()
    im.IO_AddKeyEvent(io, .ImGuiMod_Ctrl, (sdl_key_mods & sdl.KMOD_CTRL) != {})
    im.IO_AddKeyEvent(io, .ImGuiMod_Shift, (sdl_key_mods & sdl.KMOD_SHIFT) != {})
    im.IO_AddKeyEvent(io, .ImGuiMod_Alt, (sdl_key_mods & sdl.KMOD_ALT) != {})
    im.IO_AddKeyEvent(io, .ImGuiMod_Super, (sdl_key_mods & sdl.KMOD_GUI) != {})
}

// You can read the io.WantCaptureMouse, io.WantCaptureKeyboard flags to tell if dear imgui wants to use your inputs.
// - When io.WantCaptureMouse is true, do not dispatch mouse input data to your main application, or clear/overwrite your copy of the mouse data.
// - When io.WantCaptureKeyboard is true, do not dispatch keyboard input data to your main application, or clear/overwrite your copy of the keyboard data.
// Generally you may always pass all inputs to dear imgui, and hide them from your application based on those two flags.
ImGui_ImplSDL3_ProcessEvent :: proc(event : ^sdl.Event) -> bool {
	bd := ImGui_ImplSDL3_GetBackendData()
    assert(bd != nil, "Context or backend not initialized! Did you call ImGui_ImplSDL3_Init()?")
    io := im.GetIO()

	#partial switch event.type {
	case .MOUSE_MOTION: {
		if (ImGui_ImplSDL3_GetViewportForWindowID(event.motion.windowID) == nil) {
			return false
		}
		mouse_pos := im.Vec2{f32(event.motion.x), f32(event.motion.y)}
		if .ViewportsEnable in io.ConfigFlags {
			window_x, window_y : c.int
			sdl.GetWindowPosition(sdl.GetWindowFromID(event.motion.windowID), &window_x, &window_y)
			mouse_pos.x += f32(window_x)
			mouse_pos.y += f32(window_y)
		}
		im.IO_AddMouseSourceEvent(io, event.motion.which == sdl.TOUCH_MOUSEID ? .TouchScreen : .Mouse)
		im.IO_AddMousePosEvent(io, mouse_pos.x, mouse_pos.y)
		return true
	}
	case .MOUSE_WHEEL: {
		if (ImGui_ImplSDL3_GetViewportForWindowID(event.wheel.windowID) == nil) {
			return false
		}
		//IMGUI_DEBUG_LOG("wheel %.2f %.2f, precise %.2f %.2f\n", (float)event.wheel.x, (float)event.wheel.y,
		//event.wheel.preciseX, event.wheel.preciseY)
		wheel_x := -event.wheel.x
		wheel_y := event.wheel.y
		im.IO_AddMouseSourceEvent(io, event.wheel.which == sdl.TOUCH_MOUSEID ? .TouchScreen : .Mouse)
		im.IO_AddMouseWheelEvent(io, wheel_x, wheel_y)
		return true
	}
	case .MOUSE_BUTTON_DOWN, .MOUSE_BUTTON_UP: {
		if ImGui_ImplSDL3_GetViewportForWindowID(event.button.windowID) == nil {
			return false
		}

		mouse_button : c.int = -1
		if (event.button.button == sdl.BUTTON_LEFT) { mouse_button = 0 }
		if (event.button.button == sdl.BUTTON_RIGHT) { mouse_button = 1 }
		if (event.button.button == sdl.BUTTON_MIDDLE) { mouse_button = 2 }
		if (event.button.button == sdl.BUTTON_X1) { mouse_button = 3 }
		if (event.button.button == sdl.BUTTON_X2) { mouse_button = 4 }
		if (mouse_button == -1) {
			break
		}
		im.IO_AddMouseSourceEvent(io, event.button.which == sdl.TOUCH_MOUSEID ? .TouchScreen : .Mouse)
		im.IO_AddMouseButtonEvent(io, mouse_button, (event.type == .MOUSE_BUTTON_DOWN))
		bd.mouse_buttons_down = (event.type == .MOUSE_BUTTON_DOWN) ? (bd.mouse_buttons_down | (1 << uint(mouse_button))) :
		(bd.mouse_buttons_down & ~(1 << uint(mouse_button)))
		return true
	}
	case .TEXT_INPUT: {
		if (ImGui_ImplSDL3_GetViewportForWindowID(event.text.windowID) == nil) {
			return false
		}
		im.IO_AddInputCharactersUTF8(io, event.text.text)
		return true
	}
	case .KEY_DOWN, .KEY_UP: {
		viewport := ImGui_ImplSDL3_GetViewportForWindowID(event.key.windowID)
		if viewport == nil {
			return false
		}
		//IMGUI_DEBUG_LOG("SDL_EVENT_KEY_%s : key=0x%08X ('%s'), scancode=%d ('%s'), mod=%X, windowID=%d, viewport=%08X\n",
		//    (event.type == .KEY_DOWN) ? "DOWN" : "UP  ", event.key.key, SDL_GetKeyName(event.key.key),
		//    event.key.scancode, SDL_GetScancodeName(event.key.scancode), event.key.mod, event.key.windowID, viewport ?
		//    viewport.ID : 0)
		ImGui_ImplSDL3_UpdateKeyModifiers(event.key.mod)
		key := ImGui_ImplSDL3_KeyEventToImGuiKey(event.key.key, event.key.scancode)
		im.IO_AddKeyEvent(io, key, (event.type == .KEY_DOWN))
		im.IO_SetKeyEventNativeData(io, key, cast(c.int)event.key.key, cast(c.int)event.key.scancode, cast(c.int)event.key.scancode) // To support legacy indexing (<1.87 user code). Legacy backend uses SDLK_*** as indices to IsKeyXXX() functions.
		return true
	}
	case .DISPLAY_ORIENTATION, .DISPLAY_ADDED, .DISPLAY_REMOVED, .DISPLAY_MOVED, .DISPLAY_CONTENT_SCALE_CHANGED: {
		bd.want_update_monitors = true
		return true
	}
	case .WINDOW_MOUSE_ENTER: {
		if ImGui_ImplSDL3_GetViewportForWindowID(event.window.windowID) == nil {
			return false
		}
		bd.mouse_window_id = u32(event.window.windowID)
		bd.mouse_pending_leave_frame = 0
		return true
	}
	// - In some cases, when detaching a window from main viewport SDL may send SDL_WINDOWEVENT_ENTER one frame too late,
	//   causing SDL_WINDOWEVENT_LEAVE on previous frame to interrupt drag operation by clear mouse position. This is why
	//   we delay process the SDL_WINDOWEVENT_LEAVE events by one frame. See issue #5012 for details.
	// FIXME: Unconfirmed whether this is still needed with SDL3.
	case .WINDOW_MOUSE_LEAVE: {
		if ImGui_ImplSDL3_GetViewportForWindowID(event.window.windowID) == nil {
			return false
		}
		bd.mouse_pending_leave_frame = int(im.GetFrameCount() + 1)
		return true
	}
	case .WINDOW_FOCUS_GAINED, .WINDOW_FOCUS_LOST: {
		viewport := ImGui_ImplSDL3_GetViewportForWindowID(event.window.windowID)
		if viewport == nil {
			return false
		}
		//IMGUI_DEBUG_LOG("%s: windowId %d, viewport: %08X\n", (event.type == .WINDOW_FOCUS_GAINED) ?
		//".WINDOW_FOCUS_GAINED" : "SDL_WINDOWEVENT_FOCUS_LOST", event.window.windowID, viewport ? viewport.ID : 0)
		im.IO_AddFocusEvent(io, event.type == .WINDOW_FOCUS_GAINED)
		return true
	}
	case .WINDOW_CLOSE_REQUESTED, .WINDOW_MOVED, .WINDOW_RESIZED: {
		viewport := ImGui_ImplSDL3_GetViewportForWindowID(event.window.windowID)
		if (viewport == nil) {
			return false
		}
		if (event.type == .WINDOW_CLOSE_REQUESTED) {
			viewport.PlatformRequestClose = true
		}
		if (event.type == .WINDOW_MOVED) {
			viewport.PlatformRequestMove = true
		}
		if (event.type == .WINDOW_RESIZED) {
			viewport.PlatformRequestResize = true
		}
		return true
	}
	case .GAMEPAD_ADDED, .GAMEPAD_REMOVED: {
		bd.want_update_gamepads_list = true
		return true
	}
	case:
		break
    }
    return false
}

ImGui_ImplSDL3_SetupPlatformHandles :: proc(viewport: ^im.Viewport, window: ^sdl.Window) {
    viewport.PlatformHandle = rawptr(uintptr(sdl.GetWindowID(window)))
    viewport.PlatformHandleRaw = nil
when ODIN_OS == .Windows {
    viewport.PlatformHandleRaw = sdl.GetPointerProperty(sdl.GetWindowProperties(window), sdl.PROP_WINDOW_WIN32_HWND_POINTER, nil)
} else when ODIN_OS == .Darwin {
    viewport.PlatformHandleRaw = sdl.GetPointerProperty(sdl.GetWindowProperties(window), SDL_PROP_WINDOW_COCOA_WINDOW_POINTER, nil)
}
}

ImGui_ImplSDL3_Init :: proc(window: ^sdl.Window, renderer: ^sdl.Renderer, sdl_gl_context: rawptr)  -> bool {
	io := im.GetIO()
	im.CHECKVERSION()
	assert(io.BackendPlatformUserData == nil, "Already initialized a platform backend!")
	//_ := sdl_gl_context // unused in imgui_impl_sdl3.cpp

	ver_linked := sdl.GetVersion()

	// Setup backend capabilities flags
	// TODO: free these things
	bd := new(ImGui_ImplSDL3_Data)
	// Note that this is null terminated so it can be used as a cstring
	bd.backend_platform_name = fmt.aprintf("imgui_impl_sdl3 (%d.%d.%d; %d.%d.%d)%s", sdl.MAJOR_VERSION, sdl.MINOR_VERSION,
	sdl.MICRO_VERSION, sdl.VERSIONNUM_MAJOR(ver_linked), sdl.VERSIONNUM_MINOR(ver_linked), sdl.VERSIONNUM_MICRO(ver_linked), '0')
	io.BackendPlatformUserData = bd
	io.BackendPlatformName = strings.unsafe_string_to_cstring(bd.backend_platform_name)
	io.BackendFlags += {.HasMouseCursors} // We can honor GetMouseCursor() values (optional)
	io.BackendFlags += {.HasSetMousePos} // We can honor io.WantSetMousePos requests (optional, rarely used)
	// (ImGuiBackendFlags_PlatformHasViewports and ImGuiBackendFlags_HasParentViewport may be set just below)
    // (ImGuiBackendFlags_HasMouseHoveredViewport is set dynamically in our _NewFrame function)

	bd.window = g_window
	bd.window_id = sdl.GetWindowID(g_window)
	bd.renderer = renderer
// SDL on Linux/OSX doesn't report events for unfocused windows (see https://github.com/ocornut/imgui/issues/4960)
    // We will use 'MouseCanReportHoveredViewport' to set 'ImGuiBackendFlags_HasMouseHoveredViewport' dynamically each frame.
	when ODIN_OS == .Darwin {
		bd.mouse_can_report_hovered_viewport = bd.mouse_can_use_global_state
	} else {
		bd.mouse_can_report_hovered_viewport = false
	}

	// Check and store if we are on a SDL backend that supports SDL_GetGlobalMouseState() and SDL_CaptureMouse()
    // ("wayland" and "rpi" don't support it, but we chose to use a white-list instead of a black-list)
    bd.mouse_can_use_global_state = false
    bd.mouse_can_use_capture = false
when SDL_HAS_CAPTURE_AND_GLOBAL_MOUSE {
    sdl_backend := sdl.GetCurrentVideoDriver()
    capture_and_global_state_whitelist := []cstring{ "windows", "cocoa", "x11", "DIVE", "VMAN" }
    for item in capture_and_global_state_whitelist {
        if (libc.strncmp(sdl_backend, item, libc.strlen(item)) == 0) {
            bd.mouse_can_use_global_state = true
			bd.mouse_can_use_capture = true
		}
	}
}
    if bd.mouse_can_use_global_state {
        io.BackendFlags += {.PlatformHasViewports}  // We can create multi-viewports on the Platform side (optional)
        io.BackendFlags += {.HasParentViewport}     // We can honor viewport->ParentViewportId by applying the corresponding parent/child relationship at platform level (optional)
    }

	platform_io := im.GetPlatformIO()
    platform_io.Platform_SetClipboardTextFn = ImGui_ImplSDL3_SetClipboardText
    platform_io.Platform_GetClipboardTextFn = ImGui_ImplSDL3_GetClipboardText
    platform_io.Platform_SetImeDataFn = ImGui_ImplSDL3_PlatformSetImeData
    platform_io.Platform_OpenInShellFn = proc "c" (im_ctx : ^im.Context, url : cstring) -> bool { return sdl.OpenURL(url) }

    // Update monitor a first time during init
    ImGui_ImplSDL3_UpdateMonitors()

    // Gamepad handling
    bd.gamepad_mode = .AutoFirst
    bd.want_update_gamepads_list = true

    // Load mouse cursors
    bd.mouse_cursors[im.MouseCursor.Arrow] = sdl.CreateSystemCursor(.DEFAULT)
    bd.mouse_cursors[im.MouseCursor.TextInput] = sdl.CreateSystemCursor(.TEXT)
    bd.mouse_cursors[im.MouseCursor.ResizeAll] = sdl.CreateSystemCursor(.MOVE)
    bd.mouse_cursors[im.MouseCursor.ResizeNS] = sdl.CreateSystemCursor(.NS_RESIZE)
    bd.mouse_cursors[im.MouseCursor.ResizeEW] = sdl.CreateSystemCursor(.EW_RESIZE)
    bd.mouse_cursors[im.MouseCursor.ResizeNESW] = sdl.CreateSystemCursor(.NESW_RESIZE)
    bd.mouse_cursors[im.MouseCursor.ResizeNWSE] = sdl.CreateSystemCursor(.NWSE_RESIZE)
    bd.mouse_cursors[im.MouseCursor.Hand] = sdl.CreateSystemCursor(.POINTER)
    bd.mouse_cursors[im.MouseCursor.Wait] = sdl.CreateSystemCursor(.WAIT)
    bd.mouse_cursors[im.MouseCursor.Progress] = sdl.CreateSystemCursor(.PROGRESS)
    bd.mouse_cursors[im.MouseCursor.NotAllowed] = sdl.CreateSystemCursor(.NOT_ALLOWED)


    // Set platform dependent data in viewport
    // Our mouse update function expect PlatformHandle to be filled for the main viewport
    main_viewport := im.GetMainViewport()
    ImGui_ImplSDL3_SetupPlatformHandles(main_viewport, window)

    // From 2.0.5: Set SDL hint to receive mouse click events on window focus, otherwise SDL doesn't emit the event.
    // Without this, when clicking to gain focus, our widgets wouldn't activate even though they showed as hovered.
    // (This is unfortunately a global SDL setting, so enabling it might have a side-effect on your application.
    // It is unlikely to make a difference, but if your app absolutely needs to ignore the initial on-focus click:
    // you can ignore SDL_EVENT_MOUSE_BUTTON_DOWN events coming right after a SDL_EVENT_WINDOW_FOCUS_GAINED)
    sdl.SetHint(sdl.HINT_MOUSE_FOCUS_CLICKTHROUGH, "1")

    // From 2.0.22: Disable auto-capture, this is preventing drag and drop across multiple windows (see #5710)
    sdl.SetHint(sdl.HINT_MOUSE_AUTO_CAPTURE, "0")

    // SDL 3.x : see https://github.com/libsdl-org/SDL/issues/6659
    sdl.SetHint("SDL_BORDERLESS_WINDOWED_STYLE", "0")

    // We need SDL_CaptureMouse(), SDL_GetGlobalMouseState() from SDL 2.0.4+ to support multiple viewports.
    // We left the call to ImGui_ImplSDL3_InitPlatformInterface() outside of #ifdef to avoid unused-function warnings.
    if .PlatformHasViewports in io.BackendFlags {
        ImGui_ImplSDL3_InitMultiViewportSupport(window, sdl_gl_context)
	}

	return true
}
// Should technically be a SDL_GLContext but due to typedef it is sane to keep it void* in public interface.
ImGui_ImplSDL3_InitForOpenGL :: proc(window : ^sdl.Window, sdl_gl_context : rawptr) -> bool {
    return ImGui_ImplSDL3_Init(window, nil, sdl_gl_context)
}

ImGui_ImplSDL3_InitForVulkan :: proc(window : ^sdl.Window) -> bool {
    if !ImGui_ImplSDL3_Init(window, nil, nil) {
        return false
	}

	bd := ImGui_ImplSDL3_GetBackendData()
    bd.use_vulkan = true
    return true
}

ImGui_ImplSDL3_InitForD3D :: proc(window : ^sdl.Window) -> bool {
when ODIN_OS != .Windows {
    assert(false, "Unsupported")
}
    return ImGui_ImplSDL3_Init(window, nil, nil)
}

ImGui_ImplSDL3_InitForMetal :: proc(window : ^sdl.Window) -> bool {
    return ImGui_ImplSDL3_Init(window, nil, nil)
}

ImGui_ImplSDL3_InitForSDLRenderer :: proc(window : ^sdl.Window, renderer : ^sdl.Renderer) -> bool {
    return ImGui_ImplSDL3_Init(window, renderer, nil)
}

ImGui_ImplSDL3_InitForSDLGPU :: proc(window: ^sdl.Window) -> bool {
	return ImGui_ImplSDL3_Init(window, nil, nil)
}

ImGui_ImplSDL3_InitForOther :: proc(window : ^sdl.Window) -> bool {
    return ImGui_ImplSDL3_Init(window, nil, nil)
}

ImGui_ImplSDL3_Shutdown :: proc() {
	bd := ImGui_ImplSDL3_GetBackendData()
    assert(bd != nil, "No platform backend to shutdown, or already shutdown?")
    io := im.GetIO()
    platform_io := im.GetPlatformIO()

    ImGui_ImplSDL3_ShutdownMultiViewportSupport()
    if bd.clipboard_text_data != nil {
        sdl.free(cast([^]u8)bd.clipboard_text_data)
	}

	for cursor_n in 0..<int(im.MouseCursor.COUNT) {
        sdl.DestroyCursor(bd.mouse_cursors[cursor_n])
	}

    ImGui_ImplSDL3_CloseGamepads()

    io.BackendPlatformName = nil
    io.BackendPlatformUserData = nil
    io.BackendFlags &= ~{.HasMouseCursors, .HasSetMousePos, .HasGamepad, .PlatformHasViewports, .HasMouseHoveredViewport, .HasParentViewport}
    im.PlatformIO_ClearPlatformHandlers(platform_io)
    free(bd)
}

// This code is incredibly messy because some of the functions we need for full viewport support are not available in SDL < 2.0.4.
ImGui_ImplSDL3_UpdateMouseData :: proc() {
	bd := ImGui_ImplSDL3_GetBackendData()
    io := im.GetIO()

    // We forward mouse input when hovered or captured (via SDL_EVENT_MOUSE_MOTION) or when focused (below)
when SDL_HAS_CAPTURE_AND_GLOBAL_MOUSE {
    // - SDL_CaptureMouse() let the OS know e.g. that our drags can extend outside of parent boundaries (we want updated position) and shouldn't trigger other operations outside.
    // - Debuggers under Linux tends to leave captured mouse on break, which may be very inconvenient, so to mitigate the issue we wait until mouse has moved to begin capture.
    if bd.mouse_can_use_capture {
		want_capture := false
        for button_n := 0; button_n < int(im.MouseButton.COUNT) && !want_capture; button_n += 1 {
            if im.IsMouseDragging(im.MouseButton(button_n), 1.0) {
                want_capture = true
			}
		}
        if !sdl.CaptureMouse(want_capture) {
			// TODO: log
			fmt.println("sdl.CaptureMouse() failed:", sdl.GetError())
		}
    }

	focused_window := sdl.GetKeyboardFocus()
    is_app_focused := (focused_window != nil && (bd.window == focused_window || ImGui_ImplSDL3_GetViewportForWindowID(sdl.GetWindowID(focused_window)) != nil))
} else {
	focused_window := bd.window
    is_app_focused := (sdl.GetWindowFlags(bd.window) & sdl.WINDOW_INPUT_FOCUS) != {} // SDL 2.0.3 and non-windowed systems: single-viewport only
}
    if is_app_focused {
        // (Optional) Set OS mouse position from Dear ImGui if requested (rarely used, only when io.ConfigNavMoveSetMousePos is enabled by user)
        if io.WantSetMousePos {
when SDL_HAS_CAPTURE_AND_GLOBAL_MOUSE {
            if .ViewportsEnable in io.ConfigFlags {
                if !sdl.WarpMouseGlobal(io.MousePos.x, io.MousePos.y) {
					// TODO: log
					fmt.println("sdl.WarpMouseGlobal() failed:", sdl.GetError())
				}
			} else {
                sdl.WarpMouseInWindow(bd.window, io.MousePos.x, io.MousePos.y)
			}
} else {
			sdl.WarpMouseInWindow(bd.window, io.MousePos.x, io.MousePos.y)
}
        }

        // (Optional) Fallback to provide unclamped mouse position when focused but not hovered (SDL_EVENT_MOUSE_MOTION already provides this when hovered or captured)
        // Note that SDL_GetGlobalMouseState() is in theory slow on X11, but this only runs on rather specific cases. If a problem we may provide a way to opt-out this feature.
		hovered_window := sdl.GetMouseFocus()
        is_relative_mouse_mode := sdl.GetWindowRelativeMouseMode(bd.window)
        if hovered_window == nil && bd.mouse_can_use_global_state && bd.mouse_buttons_down == 0 && !is_relative_mouse_mode {
            // Single-viewport mode: mouse position in client window coordinates (io.MousePos is (0,0) when the mouse is on the upper-left corner of the app window)
            // Multi-viewport mode: mouse position in OS absolute coordinates (io.MousePos is (0,0) when the mouse is on the upper-left of the primary monitor)
            mouse_x, mouse_y : f32
            window_x, window_y : c.int
            _ = sdl.GetGlobalMouseState(&mouse_x, &mouse_y)
            if !(.ViewportsEnable in io.ConfigFlags) {
                sdl.GetWindowPosition(focused_window, &window_x, &window_y)
                mouse_x -= f32(window_x)
                mouse_y -= f32(window_y)
            }
            im.IO_AddMousePosEvent(io, mouse_x, mouse_y)
        }
    }

    // (Optional) When using multiple viewports: call io.AddMouseViewportEvent() with the viewport the OS mouse cursor is hovering.
    // If ImGuiBackendFlags_HasMouseHoveredViewport is not set by the backend, Dear imGui will ignore this field and infer the information using its flawed heuristic.
    // - [!] SDL backend does NOT correctly ignore viewports with the _NoInputs flag.
    //       Some backend are not able to handle that correctly. If a backend report an hovered viewport that has the _NoInputs flag (e.g. when dragging a window
    //       for docking, the viewport has the _NoInputs flag in order to allow us to find the viewport under), then Dear ImGui is forced to ignore the value reported
    //       by the backend, and use its flawed heuristic to guess the viewport behind.
    // - [X] SDL backend correctly reports this regardless of another viewport behind focused and dragged from (we need this to find a useful drag and drop target).
    if .HasMouseHoveredViewport in io.BackendFlags {
		mouse_viewport_id : im.ID = 0
        if mouse_viewport := ImGui_ImplSDL3_GetViewportForWindowID(sdl.WindowID(bd.mouse_window_id)); mouse_viewport != nil {
            mouse_viewport_id = mouse_viewport.ID_
		}
        im.IO_AddMouseViewportEvent(io, mouse_viewport_id)
    }
}

ImGui_ImplSDL3_UpdateMouseCursor :: proc() {
	io := im.GetIO()
    if .NoMouseCursorChange in io.ConfigFlags {
        return
	}
	bd := ImGui_ImplSDL3_GetBackendData()

    imgui_cursor := im.GetMouseCursor()
    if io.MouseDrawCursor || imgui_cursor == .None {
        // Hide OS mouse cursor if imgui is drawing it or if it wants no cursor
        if !sdl.HideCursor() {
			// TODO: Use log
			fmt.println("sdl.HideCursor() failed:", sdl.GetError())
		}
    } else {
        // Show OS mouse cursor
		expected_cursor := bd.mouse_cursors[imgui_cursor] != nil ? bd.mouse_cursors[imgui_cursor] : bd.mouse_cursors[im.MouseCursor.Arrow]
        if bd.mouse_last_cursor != expected_cursor {
            if !sdl.SetCursor(expected_cursor) { // SDL function doesn't have an early out (see #6113)
			// TODO: Use log
			fmt.println("sdl.SetCursor() failed:", sdl.GetError())
			} else {
				bd.mouse_last_cursor = expected_cursor
			}
        }
        if !sdl.ShowCursor() {
			// TODO: Use log
			fmt.println("sdl.ShowCursor() failed:", sdl.GetError())
		}
    }
}

ImGui_ImplSDL3_CloseGamepads :: proc() {
	bd := ImGui_ImplSDL3_GetBackendData()
    if bd.gamepad_mode != .Manual {
        for gamepad in bd.gamepads {
            sdl.CloseGamepad(gamepad)
		}
	}
	resize(&bd.gamepads, 0)
    //bd.gamepads.resize(0);
}

ImGui_ImplSDL3_SetGamepadMode :: proc(mode : ImGui_ImplSDL3_GamepadMode, manual_gamepads_array : [^]^sdl.Gamepad,
manual_gamepads_count : int) {
	bd := ImGui_ImplSDL3_GetBackendData()
    ImGui_ImplSDL3_CloseGamepads()
    if mode == .Manual {
        assert(manual_gamepads_array != nil || manual_gamepads_count <= 0)
        for n := 0; n < manual_gamepads_count; n += 1 {
			append(&bd.gamepads, manual_gamepads_array[n])
            //bd.gamepads.push_back(manual_gamepads_array[n]);
		}
    } else {
        assert(manual_gamepads_array == nil && manual_gamepads_count <= 0)
        bd.want_update_gamepads_list = true
    }
    bd.gamepad_mode = mode
}

ImGui_ImplSDL3_UpdateGamepadButton :: proc(bd : ^ImGui_ImplSDL3_Data, io : ^im.IO, key :im.Key, button_no : sdl.GamepadButton) {
	merged_value := false
    for gamepad in bd.gamepads {
		// No idea why dear imgui has != 0 at the end here
        //merged_value |= sdl.GetGamepadButton(gamepad, button_no) != 0
        merged_value |= sdl.GetGamepadButton(gamepad, button_no)
	}
    im.IO_AddKeyEvent(io, key, merged_value)
}

Saturate :: proc(v : f32) -> f32 { return v < 0.0 ? 0.0 : v  > 1.0 ? 1.0 : v }
ImGui_ImplSDL3_UpdateGamepadAnalog :: proc(bd : ^ImGui_ImplSDL3_Data, io : ^im.IO, key : im.Key, axis_no : sdl.GamepadAxis, v0 : f32, v1 : f32) {
	merged_value : f32 = 0.0
    for gamepad in bd.gamepads {
		vn := Saturate((f32(sdl.GetGamepadAxis(gamepad, axis_no)) - v0) / (v1 - v0))
        if merged_value < vn {
            merged_value = vn
		}
    }
    im.IO_AddKeyAnalogEvent(io, key, merged_value > 0.1, merged_value)
}

ImGui_ImplSDL3_UpdateGamepads :: proc() {
	io := im.GetIO()
    bd := ImGui_ImplSDL3_GetBackendData()

    // Update list of gamepads to use
    if bd.want_update_gamepads_list && bd.gamepad_mode != .Manual {
        ImGui_ImplSDL3_CloseGamepads()
        sdl_gamepads_count : i32 = 0
        sdl_gamepads := sdl.GetGamepads(&sdl_gamepads_count)
        for n : i32 = 0; n < sdl_gamepads_count; n += 1 {
            if gamepad := sdl.OpenGamepad(sdl_gamepads[n]); gamepad != nil {
				append(&bd.gamepads, gamepad)
                //bd.gamepads.push_back(gamepad);
                if bd.gamepad_mode == .AutoFirst {
                    break
				}
            }
		}
        bd.want_update_gamepads_list = false
        sdl.free(sdl_gamepads)
    }

    io.BackendFlags &= ~{.HasGamepad}
    if len(bd.gamepads) == 0 {
        return
	}
    io.BackendFlags += {.HasGamepad}

    // Update gamepad inputs
    thumb_dead_zone :: 8000           // SDL_gamepad.h suggests using this value.
    ImGui_ImplSDL3_UpdateGamepadButton(bd, io, .GamepadStart,       .START)
    ImGui_ImplSDL3_UpdateGamepadButton(bd, io, .GamepadBack,        .BACK)
    ImGui_ImplSDL3_UpdateGamepadButton(bd, io, .GamepadFaceLeft,    .WEST)           // Xbox X, PS Square
    ImGui_ImplSDL3_UpdateGamepadButton(bd, io, .GamepadFaceRight,   .EAST)           // Xbox B, PS Circle
    ImGui_ImplSDL3_UpdateGamepadButton(bd, io, .GamepadFaceUp,      .NORTH)          // Xbox Y, PS Triangle
    ImGui_ImplSDL3_UpdateGamepadButton(bd, io, .GamepadFaceDown,    .SOUTH)          // Xbox A, PS Cross
    ImGui_ImplSDL3_UpdateGamepadButton(bd, io, .GamepadDpadLeft,    .DPAD_LEFT)
    ImGui_ImplSDL3_UpdateGamepadButton(bd, io, .GamepadDpadRight,   .DPAD_RIGHT)
    ImGui_ImplSDL3_UpdateGamepadButton(bd, io, .GamepadDpadUp,      .DPAD_UP)
    ImGui_ImplSDL3_UpdateGamepadButton(bd, io, .GamepadDpadDown,    .DPAD_DOWN)
    ImGui_ImplSDL3_UpdateGamepadButton(bd, io, .GamepadL1,          .LEFT_SHOULDER)
    ImGui_ImplSDL3_UpdateGamepadButton(bd, io, .GamepadR1,          .RIGHT_SHOULDER)
    ImGui_ImplSDL3_UpdateGamepadAnalog(bd, io, .GamepadL2,          .LEFT_TRIGGER,  0.0, 32767)
    ImGui_ImplSDL3_UpdateGamepadAnalog(bd, io, .GamepadR2,          .RIGHT_TRIGGER, 0.0, 32767)
    ImGui_ImplSDL3_UpdateGamepadButton(bd, io, .GamepadL3,          .LEFT_STICK)
    ImGui_ImplSDL3_UpdateGamepadButton(bd, io, .GamepadR3,          .RIGHT_STICK)
    ImGui_ImplSDL3_UpdateGamepadAnalog(bd, io, .GamepadLStickLeft,  .LEFTX,  -thumb_dead_zone, -32768)
    ImGui_ImplSDL3_UpdateGamepadAnalog(bd, io, .GamepadLStickRight, .LEFTX,  +thumb_dead_zone, +32767)
    ImGui_ImplSDL3_UpdateGamepadAnalog(bd, io, .GamepadLStickUp,    .LEFTY,  -thumb_dead_zone, -32768)
    ImGui_ImplSDL3_UpdateGamepadAnalog(bd, io, .GamepadLStickDown,  .LEFTY,  +thumb_dead_zone, +32767)
    ImGui_ImplSDL3_UpdateGamepadAnalog(bd, io, .GamepadRStickLeft,  .RIGHTX, -thumb_dead_zone, -32768)
    ImGui_ImplSDL3_UpdateGamepadAnalog(bd, io, .GamepadRStickRight, .RIGHTX, +thumb_dead_zone, +32767)
    ImGui_ImplSDL3_UpdateGamepadAnalog(bd, io, .GamepadRStickUp,    .RIGHTY, -thumb_dead_zone, -32768)
    ImGui_ImplSDL3_UpdateGamepadAnalog(bd, io, .GamepadRStickDown,  .RIGHTY, +thumb_dead_zone, +32767)
}

ImGui_ImplSDL3_UpdateMonitors :: proc() {
	bd := ImGui_ImplSDL3_GetBackendData()
    platform_io := im.GetPlatformIO()
	// TODO: Is the translation of resize here to Odin correct? I think so. No generated Vector_resize procs in the bindings.
	resize(&bd.platform_io_monitors, 0)
	platform_io.Monitors.Size = i32(len(bd.platform_io_monitors))
	platform_io.Monitors.Capacity = i32(cap(bd.platform_io_monitors))
	platform_io.Monitors.Data = raw_data(bd.platform_io_monitors)
    bd.want_update_monitors = false

    display_count : i32
    displays := sdl.GetDisplays(&display_count)
    for n : i32 = 0; n < display_count; n += 1 {
        // Warning: the validity of monitor DPI information on Windows depends on the application DPI awareness settings, which generally needs to be set in the manifest or at runtime.
		display_id := displays[n]
        monitor : im.PlatformMonitor
        r : sdl.Rect
        sdl.GetDisplayBounds(display_id, &r)
        monitor.MainPos = im.Vec2{f32(r.x), f32(r.y)}
        monitor.WorkPos = im.Vec2{f32(r.x), f32(r.y)}
		monitor.MainSize = im.Vec2{f32(r.w), f32(r.h)}
		monitor.WorkSize = im.Vec2{f32(r.w), f32(r.h)}
        if sdl.GetDisplayUsableBounds(display_id, &r) && r.w > 0 && r.h > 0 {
            monitor.WorkPos = im.Vec2{f32(r.x), f32(r.y)}
            monitor.WorkSize = im.Vec2{f32(r.w), f32(r.h)}
        }
        monitor.DpiScale = sdl.GetDisplayContentScale(display_id) // See https://wiki.libsdl.org/SDL3/README-highdpi for details.
        monitor.PlatformHandle = rawptr((uintptr(n)))
        if monitor.DpiScale <= 0.0 {
            continue // Some accessibility applications are declaring virtual monitors with a DPI of 0, see #7902.
		}
        //platform_io.Monitors.push_back(monitor)
		append(&bd.platform_io_monitors, monitor)
    }
	platform_io.Monitors.Size = i32(len(bd.platform_io_monitors))
	platform_io.Monitors.Capacity = i32(cap(bd.platform_io_monitors))
	platform_io.Monitors.Data = raw_data(bd.platform_io_monitors)

    sdl.free(displays)
}

ImGui_ImplSDL3_GetWindowSizeAndFramebufferScale :: proc "contextless" (window: ^sdl.Window, out_size : ^im.Vec2, out_framebuffer_scale : ^im.Vec2) {
    w, h : c.int
    sdl.GetWindowSize(window, &w, &h)
    if .MINIMIZED in sdl.GetWindowFlags(window) {
		w,h = 0,0
	}

when ODIN_OS == .Darwin {
	fb_scale_x := sdl.GetWindowDisplayScale(window) // Seems more reliable during resolution change (#8703)
    fb_scale_y := fb_scale_x
} else {
    display_w, display_h : c.int
    sdl.GetWindowSizeInPixels(window, &display_w, &display_h)
    fb_scale_x := (w > 0) ? f32(display_w) / f32(w) : 1.0
	fb_scale_y := (h > 0) ? f32(display_h) / f32(h) : 1.0
}

    if out_size != nil {
        out_size^ = im.Vec2{f32(w), f32(h)}
	}
    if out_framebuffer_scale != nil {
        out_framebuffer_scale^ = im.Vec2{fb_scale_x, fb_scale_y}
	}
}

ImGui_ImplSDL3_NewFrame :: proc() {
	bd := ImGui_ImplSDL3_GetBackendData()
    assert(bd != nil, "Context or backend not initialized! Did you call ImGui_ImplSDL3_Init()?")
    io := im.GetIO()

    // Setup main viewport size (every frame to accommodate for window resizing)
    ImGui_ImplSDL3_GetWindowSizeAndFramebufferScale(bd.window, &io.DisplaySize, &io.DisplayFramebufferScale)

    // Update monitors
when ODIN_OS == .Windows {
    bd.want_update_monitors = true // Keep polling under Windows to handle changes of work area when resizing task-bar (#8415)
}
    if bd.want_update_monitors {
        ImGui_ImplSDL3_UpdateMonitors()
	}

    // Setup time step (we could also use SDL_GetTicksNS() available since SDL3)
    // (Accept SDL_GetPerformanceCounter() not returning a monotonically increasing value. Happens in VMs and Emscripten, see #6189, #6114, #3644)
	frequency := sdl.GetPerformanceFrequency()
    current_time := sdl.GetPerformanceCounter()
    if current_time <= bd.time {
        current_time = bd.time + 1
	}
    io.DeltaTime = bd.time > 0 ? cast(f32)(cast(f64)(current_time - bd.time) / f64(frequency)) : cast(f32)(1.0 / 60.0)
    bd.time = current_time

    if bd.mouse_pending_leave_frame > 0 && bd.mouse_pending_leave_frame >= int(im.GetFrameCount()) && bd.mouse_buttons_down == 0 {
        bd.mouse_window_id = 0
        bd.mouse_pending_leave_frame = 0
        im.IO_AddMousePosEvent(io, -math.F32_MAX, -math.F32_MAX)
    }

    // Our io.AddMouseViewportEvent() calls will only be valid when not capturing.
    // Technically speaking testing for 'bd->MouseButtonsDown == 0' would be more rigorous, but testing for payload reduces noise and potential side-effects.
    if bd.mouse_can_report_hovered_viewport && im.GetDragDropPayload() == nil {
        io.BackendFlags |= {.HasMouseHoveredViewport}
	} else {
        io.BackendFlags &= ~{.HasMouseHoveredViewport}
	}

    ImGui_ImplSDL3_UpdateMouseData()
    ImGui_ImplSDL3_UpdateMouseCursor()
    ImGui_ImplSDL3_UpdateIme()

    // Update game controllers (if enabled and available)
    ImGui_ImplSDL3_UpdateGamepads()
}

//--------------------------------------------------------------------------------------------------------
// MULTI-VIEWPORT / PLATFORM INTERFACE SUPPORT
// This is an _advanced_ and _optional_ feature, allowing the backend to create and handle multiple viewports simultaneously.
// If you are new to dear imgui or creating a new binding for dear imgui, it is recommended that you completely ignore this section first..
//--------------------------------------------------------------------------------------------------------

// Helper structure we store in the void* PlatformUserData field of each ImGuiViewport to easily retrieve our backend data.
ImGui_ImplSDL3_ViewportData :: struct {
	window : ^sdl.Window,
    parent_window : ^sdl.Window,
    window_id : u32, // Stored in ImGuiViewport::PlatformHandle. Use SDL_GetWindowFromID() to get SDL_Window* from Uint32 WindowID.
    window_owned : bool,
    gl_context : sdl.GLContext,

    //ImGui_ImplSDL3_ViewportData()   { Window = ParentWindow = nullptr; WindowID = 0; WindowOwned = false; GLContext = nullptr; }
    //~ImGui_ImplSDL3_ViewportData()  { IM_ASSERT(Window == nullptr && GLContext == nullptr); }
}

ImGui_ImplSDL3_GetSDLWindowFromViewport :: proc "c" (viewport : ^im.Viewport) -> ^sdl.Window {
    if viewport != nil {
		window_id := sdl.WindowID(uintptr(viewport.PlatformHandle))
        return sdl.GetWindowFromID(window_id)
    }

    return nil
}

ImGui_ImplSDL3_CreateWindow :: proc "c" (viewport : ^im.Viewport) {
	context = runtime.default_context()
	bd := ImGui_ImplSDL3_GetBackendData()
    vd := new(ImGui_ImplSDL3_ViewportData)
    viewport.PlatformUserData = vd

    vd.parent_window = ImGui_ImplSDL3_GetSDLWindowFromViewport(viewport.ParentViewport)

    main_viewport := im.GetMainViewport()
    main_viewport_data := cast(^ImGui_ImplSDL3_ViewportData)main_viewport.PlatformUserData

    // Share GL resources with main context
    use_opengl := main_viewport_data.gl_context != nil
    backup_context : sdl.GLContext = nil
    if use_opengl {
        backup_context = sdl.GL_GetCurrentContext()
        sdl.GL_SetAttribute(sdl.GL_SHARE_WITH_CURRENT_CONTEXT, 1)
        sdl.GL_MakeCurrent(main_viewport_data.window, main_viewport_data.gl_context)
    }

    sdl_flags : sdl.WindowFlags
    sdl_flags += {.HIDDEN}
    sdl_flags += use_opengl ? {.OPENGL} : (bd.use_vulkan ? {.VULKAN} : {})
    sdl_flags += sdl.GetWindowFlags(bd.window) & {.HIGH_PIXEL_DENSITY}
    sdl_flags += (.NoDecoration in viewport.Flags) ? {.BORDERLESS} : {}
    sdl_flags += (.NoDecoration in viewport.Flags) ? {} : {.RESIZABLE}
    sdl_flags += (.NoTaskBarIcon in viewport.Flags) ? {.UTILITY} : {}
    sdl_flags += (.TopMost in viewport.Flags) ? {.ALWAYS_ON_TOP} : {}
    vd.window = sdl.CreateWindow("No Title Yet", cast(c.int)viewport.Size.x, cast(c.int)viewport.Size.y, sdl_flags)
when ODIN_OS != .Darwin {
    sdl.SetWindowParent(vd.window, vd.parent_window)
}
    sdl.SetWindowPosition(vd.window, cast(c.int)viewport.Pos.x, cast(c.int)viewport.Pos.y)
    vd.window_owned = true
    if use_opengl {
        vd.gl_context = sdl.GL_CreateContext(vd.window)
        sdl.GL_SetSwapInterval(0)
    }
    if use_opengl && backup_context != nil {
        sdl.GL_MakeCurrent(vd.window, backup_context)
	}

    ImGui_ImplSDL3_SetupPlatformHandles(viewport, vd.window)
}

ImGui_ImplSDL3_DestroyWindow :: proc "c" (viewport : ^im.Viewport) {
	context = runtime.default_context()
    if vd := cast(^ImGui_ImplSDL3_ViewportData)viewport.PlatformUserData; vd != nil {
        if vd.gl_context != nil && vd.window_owned {
            sdl.GL_DestroyContext(vd.gl_context)
		}
        if vd.window != nil && vd.window_owned {
            sdl.DestroyWindow(vd.window)
		}
        vd.gl_context = nil
        vd.window = nil
        free(vd)
    }
    viewport.PlatformUserData = nil
	viewport.PlatformHandle = nil
}

ImGui_ImplSDL3_ShowWindow :: proc "c" (viewport: ^im.Viewport) {
	vd := cast(^ImGui_ImplSDL3_ViewportData)viewport.PlatformUserData
when ODIN_OS == .Windows {
	hwnd := cast(windows.HWND)viewport.PlatformHandleRaw

    // SDL hack: Show icon in task bar (#7989)
    // Note: sdl.WINDOW_UTILITY can be used to control task bar visibility, but on Windows, it does not affect child windows.
    if !(.NoTaskBarIcon in viewport.Flags) {
		ex_style : u32 = u32(windows.GetWindowLongW(hwnd, windows.GWL_EXSTYLE))
        ex_style |= windows.WS_EX_APPWINDOW
        ex_style &= ~windows.WS_EX_TOOLWINDOW
        windows.ShowWindow(hwnd, windows.SW_HIDE)
        windows.SetWindowLongW(hwnd, windows.GWL_EXSTYLE, windows.LONG(ex_style))
    }
}

when ODIN_OS == .Darwin {
    sdl.SetHint(sdl.HINT_WINDOW_ACTIVATE_WHEN_SHOWN, "1") // Otherwise new window appear under
} else {
    sdl.SetHint(sdl.HINT_WINDOW_ACTIVATE_WHEN_SHOWN, (.NoFocusOnAppearing in viewport.Flags) ? "0" : "1")
}
    sdl.ShowWindow(vd.window)
}

ImGui_ImplSDL3_UpdateWindow :: proc "c" (viewport : ^im.Viewport) {
	vd := cast(^ImGui_ImplSDL3_ViewportData)viewport.PlatformUserData
	_ = vd

when ODIN_OS != .Darwin {
    // On Mac, SDL3 Parenting appears to prevent viewport from appearing in another monitor
    // Update SDL3 parent if it changed _after_ creation.
    // This is for advanced apps that are manipulating ParentViewportID manually.
	new_parent := ImGui_ImplSDL3_GetSDLWindowFromViewport(viewport.ParentViewport)
    if new_parent != vd.parent_window {
        vd.parent_window = new_parent
        sdl.SetWindowParent(vd.window, vd.parent_window)
    }
}
}

ImGui_ImplSDL3_GetWindowPos :: proc "c" (viewport : ^im.Viewport) -> im.Vec2 {
	vd := cast(^ImGui_ImplSDL3_ViewportData)viewport.PlatformUserData
    x,y : c.int = 0,0
    sdl.GetWindowPosition(vd.window, &x, &y)
    return im.Vec2{f32(x), f32(y)}
}

ImGui_ImplSDL3_SetWindowPos :: proc "c" (viewport : ^im.Viewport, pos : im.Vec2) {
	vd := cast(^ImGui_ImplSDL3_ViewportData)viewport.PlatformUserData
    sdl.SetWindowPosition(vd.window, c.int(pos.x), c.int(pos.y))
}

ImGui_ImplSDL3_GetWindowSize :: proc "c" (viewport: ^im.Viewport) -> im.Vec2 {
	vd := cast(^ImGui_ImplSDL3_ViewportData)viewport.PlatformUserData
    w,h : c.int = 0,0
    sdl.GetWindowSize(vd.window, &w, &h)
    return im.Vec2{f32(w), f32(h)}
}

ImGui_ImplSDL3_SetWindowSize :: proc "c" (viewport : ^im.Viewport, size : im.Vec2) {
	vd := cast(^ImGui_ImplSDL3_ViewportData)viewport.PlatformUserData
    sdl.SetWindowSize(vd.window, c.int(size.x), c.int(size.y))
}

ImGui_ImplSDL3_GetWindowFramebufferScale :: proc "c" (viewport : ^im.Viewport) -> im.Vec2 {
	vd := cast(^ImGui_ImplSDL3_ViewportData)viewport.PlatformUserData
    framebuffer_scale : im.Vec2
    ImGui_ImplSDL3_GetWindowSizeAndFramebufferScale(vd.window, nil, &framebuffer_scale)
    return framebuffer_scale
}

ImGui_ImplSDL3_SetWindowTitle :: proc "c" (viewport : ^im.Viewport, title : cstring) {
	vd := cast(^ImGui_ImplSDL3_ViewportData)viewport.PlatformUserData
    sdl.SetWindowTitle(vd.window, title)
}

ImGui_ImplSDL3_SetWindowAlpha :: proc "c" (viewport : ^im.Viewport, alpha : f32) {
	vd := cast(^ImGui_ImplSDL3_ViewportData)viewport.PlatformUserData
    sdl.SetWindowOpacity(vd.window, alpha)
}

ImGui_ImplSDL3_SetWindowFocus :: proc "c" (viewport : ^im.Viewport) {
	vd := cast(^ImGui_ImplSDL3_ViewportData)viewport.PlatformUserData
    sdl.RaiseWindow(vd.window)
}

ImGui_ImplSDL3_GetWindowFocus :: proc "c" (viewport : ^im.Viewport) -> bool {
	vd := cast(^ImGui_ImplSDL3_ViewportData)viewport.PlatformUserData
    return (sdl.GetWindowFlags(vd.window) & sdl.WINDOW_INPUT_FOCUS) != {}
}

ImGui_ImplSDL3_GetWindowMinimized :: proc "c" (viewport : ^im.Viewport) -> bool {
	vd := cast(^ImGui_ImplSDL3_ViewportData)viewport.PlatformUserData
    return (sdl.GetWindowFlags(vd.window) & sdl.WINDOW_MINIMIZED) != {}
}

ImGui_ImplSDL3_RenderWindow :: proc "c" (viewport : ^im.Viewport, data : rawptr) {
	vd := cast(^ImGui_ImplSDL3_ViewportData)viewport.PlatformUserData
    if vd.gl_context != nil {
        sdl.GL_MakeCurrent(vd.window, vd.gl_context)
	}
}

ImGui_ImplSDL3_SwapBuffers :: proc "c" (viewport : ^im.Viewport, data : rawptr) {
	vd := cast(^ImGui_ImplSDL3_ViewportData)viewport.PlatformUserData
    if vd.gl_context != nil {
        sdl.GL_MakeCurrent(vd.window, vd.gl_context)
        sdl.GL_SwapWindow(vd.window)
    }
}

// Vulkan support (the Vulkan renderer needs to call a platform-side support function to create the surface)
// SDL is graceful enough to _not_ need <vulkan/vulkan.h> so we can safely include this.
//#include <SDL3/SDL_vulkan.h>
ImGui_ImplSDL3_CreateVkSurface :: proc "c" (viewport : ^im.Viewport, vk_instance : u64, vk_allocator : rawptr,
out_vk_surface : ^u64) -> c.int {
	vd := cast(^ImGui_ImplSDL3_ViewportData)viewport.PlatformUserData
    //(void)vk_allocator
    ret := sdl.Vulkan_CreateSurface(vd.window, cast(vk.Instance)uintptr(vk_instance), cast(^vk.AllocationCallbacks)vk_allocator, cast(^vk.SurfaceKHR)out_vk_surface)
    return ret ? 0 : 1 // ret ? VK_SUCCESS : VK_NOT_READY
}

ImGui_ImplSDL3_InitMultiViewportSupport :: proc(window: ^sdl.Window, sdl_gl_context: rawptr) {
    // Register platform interface (will be coupled with a renderer interface)
	platform_io := im.GetPlatformIO()
    platform_io.Platform_CreateWindow = ImGui_ImplSDL3_CreateWindow
    platform_io.Platform_DestroyWindow = ImGui_ImplSDL3_DestroyWindow
    platform_io.Platform_ShowWindow = ImGui_ImplSDL3_ShowWindow
    platform_io.Platform_UpdateWindow = ImGui_ImplSDL3_UpdateWindow
    platform_io.Platform_SetWindowPos = ImGui_ImplSDL3_SetWindowPos
    platform_io.Platform_GetWindowPos = ImGui_ImplSDL3_GetWindowPos
    platform_io.Platform_SetWindowSize = ImGui_ImplSDL3_SetWindowSize
    platform_io.Platform_GetWindowSize = ImGui_ImplSDL3_GetWindowSize
    platform_io.Platform_GetWindowFramebufferScale = ImGui_ImplSDL3_GetWindowFramebufferScale
    platform_io.Platform_SetWindowFocus = ImGui_ImplSDL3_SetWindowFocus
    platform_io.Platform_GetWindowFocus = ImGui_ImplSDL3_GetWindowFocus
    platform_io.Platform_GetWindowMinimized = ImGui_ImplSDL3_GetWindowMinimized
    platform_io.Platform_SetWindowTitle = ImGui_ImplSDL3_SetWindowTitle
    platform_io.Platform_RenderWindow = ImGui_ImplSDL3_RenderWindow
    platform_io.Platform_SwapBuffers = ImGui_ImplSDL3_SwapBuffers
    platform_io.Platform_SetWindowAlpha = ImGui_ImplSDL3_SetWindowAlpha
    platform_io.Platform_CreateVkSurface = ImGui_ImplSDL3_CreateVkSurface

    // Register main window handle (which is owned by the main application, not by us)
    // This is mostly for simplicity and consistency, so that our code (e.g. mouse handling etc.) can use same logic for main and secondary viewports.
	main_viewport := im.GetMainViewport()
    vd := new(ImGui_ImplSDL3_ViewportData)
    vd.window = window
    vd.window_id = u32(sdl.GetWindowID(window))
    vd.window_owned = false
    vd.gl_context = sdl.GLContext(sdl_gl_context)
    main_viewport.PlatformUserData = vd
    main_viewport.PlatformHandle = rawptr(uintptr(vd.window_id))
}

ImGui_ImplSDL3_ShutdownMultiViewportSupport :: proc() {
    im.DestroyPlatformWindows()
}
