package game

import m "core:math"
import rl "vendor:raylib"
import b2 "box2d"
import sdl "vendor:sdl3"

RAD2DEG :: rl.RAD2DEG

rect_world_to_screen :: proc(world_rect : Rect, camera : Camera2D, screen : Vec2) -> Rect {
	screen_rect : Rect
	screen_rect.w = world_rect.w * camera.zoom
	screen_rect.h = world_rect.h * camera.zoom
	screen_rect.x = (world_rect.x - camera.target.x) * camera.zoom + screen.x * 0.5
	screen_rect.y = screen.y * 0.5 - ((world_rect.y + world_rect.h - camera.target.y) * camera.zoom)
	return screen_rect
}

// TODO: Should there be a width and height (scale) on the transform?
render_transform_to_rect :: proc(transform : Render_Transform, width : f32, height : f32) -> Rect {
	return Rect{transform.pos.x - width/2.0, transform.pos.y - height/2.0, width, height}
}

position_interpolate :: proc(prev : Vec2, curr : Vec2, alpha : f64) -> Vec2 {
	return (1.0 - f32(alpha)) * prev + f32(alpha) * curr
}

rotation_interpolate :: proc(prev : Rotation, curr : Rotation, alpha : f64) -> f32 {
	prev_angle := b2.Rot_GetAngle(cast(b2.Rot)prev)
	curr_angle := b2.Rot_GetAngle(cast(b2.Rot)curr)
	result := prev_angle + b2.UnwindAngle(curr_angle - prev_angle) * f32(alpha)
	return result
}

// TODO: Should I have a separate Transform and RenderTransform? it changes rotation from quaternion to angle
Render_Transform :: struct {
	pos : Vec2,
	rot : f32,
}

render_state_interpolate :: proc(render_state : Render_State, alpha : f64) ->  Render_Transform {
	return Render_Transform{
		position_interpolate(render_state.prev_transform.pos, render_state.curr_transform.pos, alpha),
		rotation_interpolate(render_state.prev_transform.rotation, render_state.curr_transform.rotation, alpha),
	}
}

point_world_to_screen :: proc(p : Vec2, camera : Camera2D, screen : Vec2) -> Vec2 {
	result : Vec2
	result.x = (p.x - camera.target.x) * camera.zoom + screen.x * 0.5
	result.y = screen.y * 0.5 - ((p.y - camera.target.y) * camera.zoom)
	return result
}

render_line :: proc(a,b : Vec2, camera : Camera2D, screen : Vec2) {
	sdl.RenderLine(g_sdl_renderer, expand_values(point_world_to_screen(a, camera, screen)), expand_values(point_world_to_screen(b,
camera, screen)))
}

render_circle_filled :: proc(c : Vec2, r : f32, camera : Camera2D, screen : Vec2) {
	screen_c := point_world_to_screen(c, camera, screen)
	screen_r := r * camera.zoom

	min_y := int(m.ceil(screen_c.y - screen_r))
	max_y := int(m.floor(screen_c.y + screen_r))

	r2 := screen_r*screen_r

	// Scanlines
	for y in min_y..=max_y {
		dy := f32(y) - screen_c.y
		dx := m.sqrt(r2 - dy * dy)

		x1 := int(m.ceil(screen_c.x - dx))
		x2 := int(m.floor(screen_c.x + dx))

		sdl.RenderLine(g_sdl_renderer, f32(x1), f32(y), f32(x2), f32(y))
	}
}

draw_dest_rect :: proc(render_state : Render_State, source : Rect, camera : Camera2D, screen : Vec2, alpha : f64) -> Rect {
	//world_rect := Rect {render_state.curr_transform.pos.x, -render_state.curr_transform.pos.y, source.w/GAME_SCALE, source.h/GAME_SCALE}
	// TODO: Wht did legend of tuna use this GAME_SCALE? Just for determining body size from texture? Seems weird if that is the
	// case
	SOURCE_SCALE :: 10
	interpolated_transform := render_state_interpolate(render_state, alpha)
	world_rect := render_transform_to_rect(interpolated_transform, source.w / SOURCE_SCALE, source.h / SOURCE_SCALE)
	return rect_world_to_screen(world_rect, camera, screen)
}

//dest_rect :: proc(pos: Vec2, source: Rect) -> Rect {
//	return {
//		pos.x, -pos.y,
//		source.width/GAME_SCALE, source.height/GAME_SCALE,
//	}
//}
