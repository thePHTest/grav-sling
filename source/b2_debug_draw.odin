package game

import "core:c"
import la "core:math/linalg"
import b2 "vendor:box2d"
import im "deps:odin-imgui"

b2_debug_draw_im_render :: proc(b2_debug_draw : ^b2.DebugDraw) {
	im.Begin("Box2D Debug Draw Settings")
	//im.SliderFloat4("Drawing Bounds", cast(^[4]f32)&b2_debug_draw.drawingBounds)
	im.Checkbox("Use Drawing Bounds", &b2_debug_draw.useDrawingBounds)
	im.Checkbox("Draw Shapes", &b2_debug_draw.drawShapes)
	im.Checkbox("Draw Joints", &b2_debug_draw.drawJoints)
	im.Checkbox("Draw Joint Extras", &b2_debug_draw.drawJointExtras)
	im.Checkbox("Draw Bounds", &b2_debug_draw.drawBounds)
	im.Checkbox("Draw Mass", &b2_debug_draw.drawMass)
	im.Checkbox("Draw Body Names", &b2_debug_draw.drawBodyNames)
	im.Checkbox("Draw Contacts", &b2_debug_draw.drawContacts)
	im.Checkbox("Draw Graph Colors", &b2_debug_draw.drawGraphColors)
	im.Checkbox("Draw Contact Normals", &b2_debug_draw.drawContactNormals)
	im.Checkbox("Draw Contact Impulses", &b2_debug_draw.drawContactImpulses)
	im.Checkbox("Draw Contact Features", &b2_debug_draw.drawContactFeatures)
	im.Checkbox("Draw Friciton Impulse", &b2_debug_draw.drawFrictionImpulses)
	im.Checkbox("Draw Islands", &b2_debug_draw.drawIslands)
	im.End()
}

bgr_to_rgba :: proc(color: u32) -> [4]u8 {
	return {
		u8((color >> 16) & 0xFF),
		u8((color >> 8) & 0xFF),
		u8(color & 0xFF),
		255,
	}
}

// Draw a closed polygon provided in CCW order.
b2_debug_draw_polygon :: proc "c" (vertices: [^]Vec2, vertexCount: c.int, color: b2.HexColor, ctx: rawptr) {
	context = g_context
	ref_def := cast(^Ref_Def)ctx
	render_polygon(ref_def^, vertices[:vertexCount], bgr_to_rgba(u32(color)))
}

// Draw a solid closed polygon provided in CCW order.
b2_debug_draw_solid_polygon :: proc "c" (transform: b2.Transform, vertices: [^]Vec2, vertexCount: c.int, radius: f32, color: b2.HexColor, ctx: rawptr ) {
	context = g_context
	ref_def := cast(^Ref_Def)ctx
	render_polygon_filled(ref_def^, transform, vertices[:vertexCount], radius, bgr_to_rgba(u32(color)))
}

// Draw a circle.
b2_debug_draw_circle :: proc "c" (center: Vec2, radius: f32, color: b2.HexColor, ctx: rawptr) {
	context = g_context
	ref_def := cast(^Ref_Def)ctx
	render_circle(ref_def^, center, radius, bgr_to_rgba(u32(color)))
}

// Draw a solid circle.
b2_debug_draw_solid_circle :: proc "c" (transform: b2.Transform, radius: f32, color: b2.HexColor, ctx: rawptr) {
	context = g_context
	ref_def := cast(^Ref_Def)ctx
	render_circle_filled(ref_def^, transform.p, radius, bgr_to_rgba(u32(color)))
}

// Draw a solid capsule.
b2_debug_draw_solid_capsule :: proc "c" (p1, p2: Vec2, radius: f32, color: b2.HexColor, ctx: rawptr) {
	context = g_context
	ref_def := cast(^Ref_Def)ctx

	dist := la.distance(p1, p2)
	v := la.normalize(p2 - p1)
	center := p1 + v * 0.5 * dist

	to_origin := p1 - center
	rot := la.atan2(to_origin.y, to_origin.x)
	transform := Render_Transform{
		pos = center,
		rot = rot,
	}

	render_capsule(ref_def^, transform, p1, p2, radius, bgr_to_rgba(u32(color)))
}

// Draw a line segment.
b2_debug_draw_segment :: proc "c" (p1, p2: Vec2, color: b2.HexColor, ctx: rawptr) {
	context = g_context
	ref_def := cast(^Ref_Def)ctx
	render_line(ref_def^, p1, p2, bgr_to_rgba(u32(color)))
}

// Draw a transform. Choose your own length scale.
b2_debug_draw_transform :: proc "c" (transform: b2.Transform, ctx: rawptr) {
	context = g_context
	ref_def := cast(^Ref_Def)ctx
	render_transform : Render_Transform
	render_transform.pos = transform.p
	render_transform.rot = b2.Rot_GetAngle(transform.q)
	render_rect(ref_def^, render_transform, 0.2, 0.2, [4]u8{0, 0, 0, 255})
}

// Draw a point.
b2_debug_draw_point :: proc "c" (p: Vec2, size: f32, color: b2.HexColor, ctx: rawptr) {
	context = g_context
	ref_def := cast(^Ref_Def)ctx
	radius_pixels := size / 2.0
	radius_world := radius_pixels / ref_def.camera.zoom
	render_point(ref_def^, p, radius_world, bgr_to_rgba(u32(color)))
}

// Draw a string.
b2_debug_draw_string :: proc "c" (p: Vec2, s: cstring, color: b2.HexColor, ctx: rawptr) {
	context = g_context
	ref_def := cast(^Ref_Def)ctx
	render_debug_text(ref_def^, p, string(s), bgr_to_rgba(u32(color)))
}


