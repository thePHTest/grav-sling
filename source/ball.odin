package game

import b2 "vendor:box2d"

Ball :: struct {
	body: b2.BodyId,
	shape: b2.ShapeId,

	render_state : Render_State,
}

ball_make :: proc(g_mem : ^Game_Memory, pos: Vec2) -> Ball {
	bd := b2.DefaultBodyDef()
	bd.type = .dynamicBody
	bd.position = pos
	// TODO: Instead of linearDamping, try using this for top down friction
	// https://github.com/erincatto/box2d/blob/af12713103083d4f853cfb1c65edaf96b0e43598/samples/sample_joints.cpp#L423 
	bd.linearDamping = 0.3
	bd.angularDamping = 0.3
	bd.name = "Ball"
	body := b2.CreateBody(g_mem.physics_world, bd)
	
	sd := b2.DefaultShapeDef()
	DENSITY :: 0.01
	sd.density = DENSITY
	sd.material.friction = 0.0
	sd.material.restitution = 0.2
	sd.filter = {
		categoryBits = u64(bit_set[Collision_Category] { .Ball }),
		maskBits = u64(bit_set[Collision_Category] { .Wall, .Avatar }),
	}

	circle := b2.Circle {
		center = {0, 0.0},
		radius = 0.50,
	}

	shape := b2.CreateCircleShape(body, sd, &circle)

	return {
		body = body,
		shape = shape,
	}
}

ball_tick_pre_physics :: proc(ball: ^Ball) {
}

ball_tick_post_physics :: proc(ball: ^Ball) {
	ball.render_state.prev_transform = ball.render_state.curr_transform
	ball.render_state.curr_transform = transmute(Transform)b2.Body_GetTransform(ball.body)
}

ball_render :: proc(ball: Ball, ref_def: Ref_Def) {
	circle_shape := b2.Shape_GetCircle(ball.shape)

	ball_color :: [4]u8{255, 0, 0, 255}
	render_interpolate_circle(ref_def, ball.render_state, circle_shape, ball_color)
}
