package game

import m "core:math"
import "core:log"
import la "core:math/linalg"
import rl "vendor:raylib"
import b2 "box2d"
import sdl "vendor:sdl3"

_ :: log

RAD2DEG :: rl.RAD2DEG
SOURCE_SCALE :: 10

// TODO: Use Ref_Def everywhere
Ref_Def :: struct {
	camera : Camera2D,
	viewport : Vec2,
	// The alpha representing the time between the previous and current physics tick. Is there a better name for this?
	alpha : f64,
}

rect_world_to_screen :: proc(world_rect : Rect, camera : Camera2D, screen : Vec2) -> Rect {
	screen_rect : Rect
	screen_rect.w = world_rect.w * camera.zoom
	screen_rect.h = world_rect.h * camera.zoom
	screen_rect.x = (world_rect.x - camera.target.x) * camera.zoom + screen.x * 0.5
	screen_rect.y = screen.y * 0.5 - ((world_rect.y + world_rect.h - camera.target.y) * camera.zoom)
	return screen_rect
}

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
// TODO: Should there be a width and height (scale) on the transform?
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

render_rect :: proc(renderer : ^sdl.Renderer, render_state : Render_State, width : f32, height : f32, camera : Camera2D, screen : Vec2, alpha : f64) {
	interpolated_transform := render_state_interpolate(render_state, alpha)
	if interpolated_transform.rot == 0.0 {
		world_rect := render_transform_to_rect(interpolated_transform, width, height)
		screen_rect := rect_world_to_screen(world_rect, camera, screen)
		sdl.RenderFillRect(renderer, cast(^sdl.FRect)&screen_rect)
	} else {
		// Get the 4 corners
		// TODO: Just store the quat on the Render_State transform. Avoid having to do extra cos and sin
		c := m.cos(interpolated_transform.rot)
		s := m.sin(interpolated_transform.rot)

		half_w := width * 0.5
		half_h := height * 0.5
		local := [4]Vec2 {
			Vec2{-half_w, -half_h},
			Vec2{half_w, -half_h},
			Vec2{half_w, half_h},
			Vec2{-half_w, half_h},
		}

		obb : [4]Vec2
		for idx in 0..<len(local) {
			p := local[idx]

			r := Vec2{
				p.x * c - p.y * s,
				p.x * s + p.y * c,
			}

			obb[idx] = r + interpolated_transform.pos
		}

		vertices : [4]sdl.Vertex
		for idx in 0..<len(obb) {
			v := &vertices[idx]
			v.position = cast(sdl.FPoint)point_world_to_screen(obb[idx], camera, screen)
			v.color = sdl.FColor{1.0, 0.0, 0.0, 1.0}
			v.tex_coord = {}
		}

		indices : [6]i32 = {
			0, 1, 2,
			0, 2, 3,
		}
		sdl.RenderGeometry(renderer, nil, &vertices[0], len(vertices), &indices[0], len(indices))
	}
}

render_line :: proc(renderer : ^sdl.Renderer, a,b : Vec2, camera : Camera2D, screen : Vec2) {
	sdl.RenderLine(renderer, expand_values(point_world_to_screen(a, camera, screen)), expand_values(point_world_to_screen(b,
camera, screen)))
}

render_circle :: proc(renderer: ^sdl.Renderer, render_state : Render_State, circle : b2.Circle, camera : Camera2D, screen : Vec2, alpha : f64) {
	interpolated_transform := render_state_interpolate(render_state, alpha)
	render_circle_filled(renderer, interpolated_transform.pos, circle.radius, camera, screen)
}

render_capsule :: proc(renderer : ^sdl.Renderer, render_state : Render_State, capsule : b2.Capsule, camera : Camera2D, screen : Vec2, alpha : f64) {
	width := capsule.radius * 2.0
	height := la.distance(capsule.center1, capsule.center2)
	render_rect(renderer, render_state, width, height, camera, screen, alpha)

	sdl.SetRenderDrawColorFloat(renderer, 0.7, 0.0, 0.7, 1.0)
	interpolated_transform := render_state_interpolate(render_state, alpha)
	rot_mat : matrix[2,2]f32 = {
		m.cos(interpolated_transform.rot), m.sin(interpolated_transform.rot),
		-m.sin(interpolated_transform.rot), m.cos(interpolated_transform.rot),
	}

	circle1_pos := (interpolated_transform.pos) + (capsule.center1 * rot_mat)
	circle2_pos := interpolated_transform.pos + (capsule.center2 * rot_mat)

	render_circle_filled(renderer, circle1_pos, capsule.radius, camera, screen)
	render_circle_filled(renderer, circle2_pos, capsule.radius, camera, screen)
}

render_circle_filled :: proc(renderer : ^sdl.Renderer, c : Vec2, r : f32, camera : Camera2D, screen : Vec2) {
	screen_c := point_world_to_screen(c, camera, screen)
	screen_r := r * camera.zoom

	NUM_SEGMENTS :: 64

	vertices : [NUM_SEGMENTS+2]sdl.Vertex

	// Center vertex
	vertices[0] = sdl.Vertex {
		position = cast(sdl.FPoint)screen_c,
		color = {1.0, 0.0, 0.0, 1.0},
		tex_coord = {},
	}

	// Circle ring
	for idx in 0..<NUM_SEGMENTS+1 {
		t := f32(idx) / f32(NUM_SEGMENTS) * m.TAU

		x := screen_c.x + m.cos(t) * screen_r
		y := screen_c.y + m.sin(t) * screen_r

		vertices[idx + 1] = {
			position = {x,y},
			color = {1.0, 0.0, 0.0, 1.0},
			tex_coord = {},
		}
	}

	// indices for triangle fan
	indices : [NUM_SEGMENTS*3]i32
	for idx in 0..<NUM_SEGMENTS {
		base := idx * 3
		indices[base] = 0
		indices[base + 1] = i32(idx + 1)
		indices[base + 2] = i32(idx + 2)
	}

	sdl.RenderGeometry(renderer, nil, &vertices[0], len(vertices), &indices[0], len(indices))
}
