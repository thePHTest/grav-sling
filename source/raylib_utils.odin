package game

import "core:log"
import rl "vendor:raylib"

RAD2DEG :: rl.RAD2DEG

rect_world_to_screen :: proc(world_rect : Rect, camera : Camera2D, screen : Vec2) -> Rect {
	screen_rect : Rect
	screen_rect.w = world_rect.w * camera.zoom
	screen_rect.h = world_rect.h * camera.zoom
	screen_rect.x = (world_rect.x - camera.target.x) * camera.zoom + screen.x * 0.5
	screen_rect.y = screen.y * 0.5 - ((world_rect.y + world_rect.h - camera.target.y) * camera.zoom)
	log.info(screen_rect)
	return screen_rect
}

transform_to_rect :: proc(transform : Transform, width : f32, height : f32) -> Rect {
	return Rect{transform.pos.x - width/2.0, transform.pos.y - height/2.0, width, height}
}

draw_dest_rect :: proc(render_state : Render_State, source : Rect, camera : Camera2D, screen : Vec2) -> Rect {
	//world_rect := Rect {render_state.curr_transform.pos.x, -render_state.curr_transform.pos.y, source.w/GAME_SCALE, source.h/GAME_SCALE}
	// TODO: Wht did legend of tuna use this GAME_SCALE? Just for determining body size from texture? Seems weird if that is the
	// case
	SOURCE_SCALE :: 10
	world_rect := transform_to_rect(render_state.curr_transform, source.w / SOURCE_SCALE, source.h / SOURCE_SCALE)
	return rect_world_to_screen(world_rect, camera, screen)
}

//dest_rect :: proc(pos: Vec2, source: Rect) -> Rect {
//	return {
//		pos.x, -pos.y,
//		source.width/GAME_SCALE, source.height/GAME_SCALE,
//	}
//}
