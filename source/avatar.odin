package game

import b2 "vendor:box2d"
import "core:fmt"
import "core:log"
import "core:math"
import im "deps:odin-imgui"
import la "core:math/linalg"

_ :: fmt
_ :: math
_ :: log

Render_State :: struct {
	prev_transform : Transform,
	curr_transform : Transform,
}
Rotation :: struct {
	c, s: f32, // cosine and sine
}
Transform :: struct {
	pos : Vec2,
	rotation : Rotation,
}

Avatar :: struct {
	body: b2.BodyId,
	shape: b2.ShapeId,
	squish_amount: f32,
	squish_direction: Vec2,
	squish_start: f64,
	
	aim_range: f32,
	aim_direction: Vec2,

	ball_posession: bool,
	arm_body_id: b2.BodyId,
	prismatic_joint_id: b2.JointId,

	render_state : Render_State,

	// Editor vars
	move_force : f32,
	decel_force : f32,
	density : f32,
	max_velocity : f32,
}

avatar_im_render :: proc(avatar : ^Avatar) {
	im.Begin("Avatar Editor")
	im.SliderFloat("Move force", &avatar.move_force, 10.0, 4000.0)
	im.SliderFloat("Decel force", &avatar.decel_force, 0.0, 1000.0)
	if im.SliderFloat("Density", &avatar.density, 0.0, 6.0) {
		b2.Shape_SetDensity(avatar.shape, avatar.density, true)
		// TODO: Is Body_ApplyMassFromShapes needed now that Shape_SetDensity take a updateBosyMass param?
		b2.Body_ApplyMassFromShapes(avatar.body)
	}
	im.Text(fmt.ctprint("Body mass:", b2.Body_GetMass(avatar.body)))
	im.SliderFloat("Max velocity", &avatar.max_velocity, 5.0, 75.0)
	im.End()
}

avatar_make :: proc(g_mem : ^Game_Memory, pos: Vec2, aim_range: f32) -> Avatar {
	bd := b2.DefaultBodyDef()
	bd.type = .dynamicBody
	bd.position = pos
	// TODO: Instead of linearDamping, try using this for top down friction
	// https://github.com/erincatto/box2d/blob/af12713103083d4f853cfb1c65edaf96b0e43598/samples/sample_joints.cpp#L423 
	bd.linearDamping = 0.0
	//bd.angularDamping = 0.7
	bd.fixedRotation = true
	//bd.linearDamping = 0.0
	//bd.angularDamping = 0.0
	bd.name = "Avatar"
	body := b2.CreateBody(g_mem.physics_world, bd)

	sd := b2.DefaultShapeDef()
	DENSITY :: 1.00
	sd.density = DENSITY
	// TODO: Looks like friction and restitution moved to surface property. Configure that
	sd.material.friction = 0.0
	sd.material.restitution = 0.2
	sd.filter = {
		categoryBits = u64(bit_set[Collision_Category] { .Avatar }),
		maskBits = u64(bit_set[Collision_Category] { .Wall , .Ball}),
	}

	capsule := b2.Capsule {
		center1 = {0, -0.25},
		center2 = {0, 0.25},
		radius = 0.25,
	}

	shape := b2.CreateCapsuleShape(body, sd, capsule)

	arm_def := b2.DefaultBodyDef()
	arm_def.type = .kinematicBody
	arm_def.position = pos
	arm_def.name = "Arm"
	arm_body_id := b2.CreateBody(g_mem.physics_world, arm_def)
	//arm_mass_data : b2.MassData
	//arm_mass_data.mass = 0.001
	//arm_mass_data.rotationalInertia = 0.001
	//b2.Body_SetMassData(arm_body_id, arm_mass_data)

	log.info(body)
	log.info(shape)
	log.info(arm_body_id)
	return {
		body = body,
		arm_body_id = arm_body_id,
		shape = shape,
		aim_range = aim_range,
		move_force = 30.0,
		decel_force = 8.5,
		density = DENSITY,
		max_velocity = 30.0,
	}
}

avatar_pos :: proc(avatar: Avatar) -> Vec2 {
	return body_pos(avatar.body)
}


ease_peak :: proc(t: f32) -> f32 {
	return 64 * t * t * t * (1 - t) * (1 - t) * (1 - t)
}

ease_squish :: proc(t: f32) -> f32 {
	smoothstop := 1 - (1-t) * (1-t) * (1-t) * (1-t) * (1-t)
	return smoothstop
}

smoothstart5 :: proc(t: f32) -> f32 {
	return t * t * t * t * t
}

avatar_render :: proc(avatar: Avatar, ref_def: Ref_Def) {
	capsule_shape := b2.Shape_GetCapsule(avatar.shape)
	//width := capsule_shape.radius * 2.0
	//height := la.distance(capsule_shape.center1, capsule_shape.center2) + capsule_shape.radius*2.0
	//render_rect(avatar.render_state, width, height, camera, screen, alpha)

	avatar_color :: [4]u8{0, 0, 255, 255}
	render_interpolate_capsule(ref_def, avatar.render_state, capsule_shape, avatar_color)

	// Try sdl rect render
	//source := atlas_textures[.Avatar].rect
	//dest := draw_dest_rect(avatar.render_state, source, camera, screen, alpha)
	//sdl.RenderFillRect(renderer, cast(^sdl.FRect)&dest)

	pos := body_pos(avatar.body)
	aim_pos := pos + avatar.aim_range * avatar.aim_direction
	//rl.DrawLineEx(vec2_flip(pos), vec2_flip(aim_pos), 0.5, rl.RED)
	aim_color :: [4]u8{128, 0, 128, 255}
	render_line(ref_def, pos, aim_pos, aim_color)
}

apply_deadzone :: proc(deadzone : f32, joystick_value : f32) -> f32{
	if abs(joystick_value) < deadzone {
		return 0
	}
	return math.sign(joystick_value) * math.remap(abs(joystick_value), deadzone, 1.0, 0.0, 1.0)
}

ray_intersects_circle_thick :: proc(
    p: Vec2,                // ray origin
    d: Vec2,                // ray direction (need NOT be normalized)
    max_range: f32,         // ray length
    c: Vec2,                // circle center
    circle_radius: f32,     // circle radius
    ray_thickness: f32,      // ray thickness
) -> bool {

    // Effective radius (circle radius + ray radius)
    eff_r := circle_radius + ray_thickness
    eff_r_sq := eff_r * eff_r

    // Extend usable ray range so the *tip* of the ray can hit the circle
    max_t := max_range + eff_r

    f := c - p

    // 1. Check if circle is in front of ray
    proj := la.dot(f, d)
    if proj < 0 {
        return false
    }

    d_sq := la.dot(d, d)
    cross_val := la.cross(d, f)          // scalar in 2D
    cross_sq  := cross_val * cross_val

    // 2. Perpendicular distance test (no sqrt)
    if cross_sq > eff_r_sq * d_sq {
        return false
    }

    // 3. Intersection distance check (no sqrt)
    //    Compute t₀², comparing to max_t².
    t_off_sq := (eff_r_sq * d_sq - cross_sq) / d_sq
    t0_sq := (proj*proj)/d_sq - t_off_sq

    return t0_sq <= max_t * max_t
}

MAX_POSSESS_DISTANCE :: 3.0
avatar_try_possess_ball :: proc(avatar: ^Avatar, ball: ^Ball, physics_world: b2.WorldId) -> bool {
	body_pos := b2.Body_GetPosition(avatar.body)
	arm_pos := b2.Body_GetPosition(avatar.arm_body_id)
	ball_pos := b2.Body_GetPosition(ball.body)
	ball_distance := b2.Distance(body_pos, ball_pos)
	if ball_distance > MAX_POSSESS_DISTANCE {
		return false
	}

	// On possess — reset arm state before creating joint
	//b2.Body_SetTransform(avatar.arm_body_id,
	//	b2.Body_GetPosition(avatar.body),
	//	b2.Body_GetRotation(avatar.arm_body_id))
	//b2.Body_SetLinearVelocity(avatar.arm_body_id, b2.Body_GetLinearVelocity(avatar.body))
	//b2.Body_SetAngularVelocity(avatar.arm_body_id, 0.0)

	// On possess — reset arm rotation to identity first
	b2.Body_SetTransform(avatar.arm_body_id, body_pos, b2.MakeRot(0.0))
	b2.Body_SetLinearVelocity(avatar.arm_body_id, b2.Body_GetLinearVelocity(avatar.body))
	b2.Body_SetAngularVelocity(avatar.arm_body_id, 0.0)

	ball_dir := b2.Normalize(ball_pos - arm_pos)
	prismatic_joint_def := b2.DefaultPrismaticJointDef()
	prismatic_joint_def.bodyIdA = avatar.arm_body_id
	prismatic_joint_def.bodyIdB = ball.body
	prismatic_joint_def.localAnchorA = {}
	prismatic_joint_def.localAnchorB = {}
	prismatic_joint_def.localAxisA = ball_dir

	prismatic_joint_def.enableLimit = true
	prismatic_joint_def.lowerTranslation = 0.10
	prismatic_joint_def.upperTranslation = 5.0

	prismatic_joint_def.enableMotor = true
	prismatic_joint_def.maxMotorForce = 50.0
	prismatic_joint_def.motorSpeed = 0.0

	avatar.prismatic_joint_id = b2.CreatePrismaticJoint(physics_world, prismatic_joint_def)
	return true
}

avatar_depossess_ball :: proc(avatar: ^Avatar) {
	log.info("Depossess Ball")
	b2.DestroyJoint(avatar.prismatic_joint_id)
	avatar.prismatic_joint_id = {}
}

avatar_tick_pre_physics :: proc(g_mem : ^Game_Memory, avatar: ^Avatar, sim_ctx : Sim_Ctx, physics_world: b2.WorldId) {
	contact_cap := b2.Body_GetContactCapacity(avatar.body)
	contact_data := make([]b2.ContactData, contact_cap, context.temp_allocator)
	contact_data = b2.Body_GetContactData(avatar.body, contact_data)

	for &c in contact_data {
		vel := c.manifold.points[0].normalVelocity

		if abs(vel) > 10 {
			//rl.PlaySound(g_mem.land_sound)
		}
	}
	swing_speed : f32 = 0.0
	if keyboard_is_key_down(g_keyboard, .LSHIFT) {
		swing_speed = 10.0
	}

	// Arm update
	b2.Body_SetTransform(avatar.arm_body_id, b2.Body_GetPosition(avatar.body), b2.Body_GetRotation(avatar.arm_body_id))
	b2.Body_SetLinearVelocity(avatar.arm_body_id, b2.Body_GetLinearVelocity(avatar.body))

	avatar_angular_velocity := b2.Body_GetAngularVelocity(avatar.body)
	b2.Body_SetAngularVelocity(avatar.arm_body_id, avatar_angular_velocity + swing_speed)

	if keyboard_is_key_pressed(g_keyboard, .SPACE) {
		if avatar.prismatic_joint_id == {} {
			avatar_try_possess_ball(avatar, &g_mem.ball, physics_world)
		} else {
			avatar_depossess_ball(avatar)
		}
	}

	deadzone :: 0.1
	// Apply force in WASD direction controls

	dir : Vec2 = proc() -> Vec2 {
		result : Vec2
		if keyboard_is_key_down(g_keyboard, .W) {
			result.y = 1.0
		} else if keyboard_is_key_down(g_keyboard, .S) {
			result.y = -1.0
		} else {
			result.y = gamepad_axis_normalize(g_gamepad, .LEFTY) * -1
			result.y = apply_deadzone(deadzone, result.y)
		}
		
		if keyboard_is_key_down(g_keyboard, .A) {
			result.x = -1.0
		} else if keyboard_is_key_down(g_keyboard, .D) {
			result.x = 1.0
		} else {
			result.x = gamepad_axis_normalize(g_gamepad, .LEFTX)
			result.x = apply_deadzone(deadzone, result.x)
		}

		return result
	}()

	b2.Body_ApplyForceToCenter(avatar.body, avatar.move_force*dir, true)
	//b2.Body_ApplyLinearImpulseToCenter(avatar.body, avatar.move_force*dir, true)
	
	aim_joystick_left := gamepad_axis_normalize(g_gamepad, .RIGHTX)
	aim_joystick_right := gamepad_axis_normalize(g_gamepad, .RIGHTY) * -1.0 // Invert
	aim_joystick_left = apply_deadzone(deadzone, aim_joystick_left)
	aim_joystick_right = apply_deadzone(deadzone, aim_joystick_right)
	avatar.aim_direction = Vec2{aim_joystick_left, aim_joystick_right}
	if la.length(avatar.aim_direction) > 1 {
		avatar.aim_direction = la.normalize0(avatar.aim_direction)
	}

	
	if gamepad_is_button_pressed(g_gamepad, .SOUTH) {
		// TODO
	}

	current_velocity := b2.Body_GetLinearVelocity(avatar.body)
	current_speed := la.length2(current_velocity)
	_ = current_speed
	if la.length(current_velocity) > avatar.max_velocity {
		b2.Body_SetLinearVelocity(avatar.body, la.normalize(current_velocity) * avatar.max_velocity)
	}

	if gamepad_is_button_pressed(g_gamepad, .SOUTH) {
		b2.Body_ApplyLinearImpulseToCenter(avatar.body, la.normalize(current_velocity) * -1.0 * avatar.move_force/2.0, true)
	}

	if dir == 0.0 {
		b2.Body_ApplyForceToCenter(avatar.body, current_velocity*-1.0*avatar.decel_force, true)
		// Could try to dampen like this, but it should take dt into account
		//b2.Body_SetLinearVelocity(avatar.body, current_velocity*0.98)
	}


}

avatar_tick_post_physics :: proc(g_mem : ^Game_Memory, avatar: ^Avatar, sim_ctx : Sim_Ctx, physics_world: b2.WorldId) {
	avatar.render_state.prev_transform = avatar.render_state.curr_transform
	avatar.render_state.curr_transform = transmute(Transform)b2.Body_GetTransform(avatar.body)
}
