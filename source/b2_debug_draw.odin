package game

import "core:c"
import b2 "vendor:box2d"

// Draw a closed polygon provided in CCW order.
b2_debug_draw_polygon :: proc "c" (vertices: [^]Vec2, vertexCount: c.int, color: b2.HexColor, ctx: rawptr) {
}

// Draw a solid closed polygon provided in CCW order.
b2_debug_draw_solid_polygon :: proc "c" (transform: b2.Transform, vertices: [^]Vec2, vertexCount: c.int, radius: f32, colr: b2.HexColor,
ctx: rawptr ) {

}

// Draw a circle.
b2_debug_draw_circle :: proc "c" (center: Vec2, radius: f32, color: b2.HexColor, ctx: rawptr) {
	context = g_context
	ref_def := cast(^Ref_Def)ctx
	render_circle(ref_def^, center, radius, transmute([4]u8)color)
}

// Draw a solid circle.
b2_debug_draw_solid_circle :: proc "c" (transform: b2.Transform, radius: f32, color: b2.HexColor, ctx: rawptr) {
	context = g_context
	ref_def := cast(^Ref_Def)ctx
	render_circle_filled(ref_def^, transform.p, radius, transmute([4]u8)color)
}

// Draw a solid capsule.
b2_debug_draw_solid_capsule :: proc "c" (p1, p2: Vec2, radius: f32, color: b2.HexColor, ctx: rawptr) {
	//context = g_context
	//ref_def := cast(^Ref_Def)ctx
	//render_b2_capsule(ref_def^, transform.pos, radius, transmute([4]u8)color)
}

// Draw a line segment.
b2_debug_draw_segment :: proc "c" (p1, p2: Vec2, color: b2.HexColor, ctx: rawptr) {
	context = g_context
	ref_def := cast(^Ref_Def)ctx
	render_line(ref_def^, p1, p2, transmute([4]u8)color)
}

// Draw a transform. Choose your own length scale.
b2_debug_draw_transform :: proc "c" (transform: b2.Transform, ctx: rawptr) {

}

// Draw a point.
b2_debug_draw_point :: proc "c" (p: Vec2, size: f32, color: b2.HexColor, ctx: rawptr) {
	context = g_context
	ref_def := cast(^Ref_Def)ctx
	render_point(ref_def^, p, size, transmute([4]u8)color)
}

// Draw a string.
b2_debug_draw_string :: proc "c" (p: Vec2, s: cstring, color: b2.HexColor, ctx: rawptr) {
	context = g_context
	ref_def := cast(^Ref_Def)ctx
	render_debug_text(ref_def^, p, string(s), transmute([4]u8)color)
}


