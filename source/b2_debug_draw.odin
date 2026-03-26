package game

import "core:c"
import b2 "box2d"

// Draw a closed polygon provided in CCW order.
b2_debug_draw_polygon :: proc "c" (vertices: [^]Vec2, vertexCount: c.int, color: b2.HexColor, ctx: rawptr) {

}

// Draw a solid closed polygon provided in CCW order.
b2_debug_draw_solid_polygon :: proc "c" (transform: Transform, vertices: [^]Vec2, vertexCount: c.int, radius: f32, colr: b2.HexColor,
ctx: rawptr ) {

}

// Draw a circle.
b2_debug_draw_circle :: proc "c" (center: Vec2, radius: f32, color: b2.HexColor, ctx: rawptr) {
}

// Draw a solid circle.
b2_debug_draw_solid_circle :: proc "c" (transform: Transform, radius: f32, color: b2.HexColor, ctx: rawptr) {
	//ref_def := cast(^Ref_Def)ctx
	//render_circle_filled(ref_def, transform.pos, radius, transmute([4]u8)color)
}

// Draw a solid capsule.
b2_debug_draw_solid_capsule :: proc "c" (p1, p2: Vec2, radius: f32, color: b2.HexColor, ctx: rawptr) {

}

// Draw a line segment.
b2_debug_draw_segment :: proc "c" (p1, p2: Vec2, color: b2.HexColor, ctx: rawptr) {

}

// Draw a transform. Choose your own length scale.
b2_debug_draw_transfrom :: proc "c" (transform: Transform, ctx: rawptr) {

}

// Draw a point.
b2_debug_draw_point :: proc "c" (p: Vec2, size: f32, color: b2.HexColor, ctx: rawptr) {

}

// Draw a string.
b2_debug_draw_string :: proc "c" (p: Vec2, s: cstring, ctx: rawptr) {

}


