package game

import b2 "box2d"
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
	render_state : Render_State,

	body: b2.BodyId,
	shape: b2.ShapeId,
	
	aim_range: f32,
	aim_direction: Vec2,

	ball_posession: bool,
	arm_body_id: b2.BodyId,
	prismatic_joint_id: b2.JointId,

	right_stick_pos : Vec2,
	arm_angular_velocity: f32, // integrated orbit speed, rad/s
	tether_length: f32, // current spring target in meters

	orbit_max_speed : f32, // rad/s
	orbit_accel : f32, // rad/s^2
	orbit_decel : f32, // rad/s^2
	orbit_damping : f32, //coast-down rate when no orbit input (1/s)
	reel_speed : f32, // m/s the tether target moves
	tether_hertz : f32, // spring stiffness
	tether_damping : f32, // spring damping ratio
	tether_min : f32,
	tether_max : f32,

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
	im.SeparatorText("Possession")
	im.SliderFloat("Orbit max speed", &avatar.orbit_max_speed, 0.0, 40.0)
	im.SliderFloat("Orbit accel", &avatar.orbit_accel, 0.0, 300.0)
	im.SliderFloat("Orbit decel", &avatar.orbit_decel, 0.0, 300.0)
	im.SliderFloat("Orbit damping", &avatar.orbit_damping, 0.0, 30.0)
	im.SliderFloat("Reel speed", &avatar.reel_speed, 0.0, 20.0)
	if im.SliderFloat("Tether hertz", &avatar.tether_hertz, 0.0, 15.0) && avatar.prismatic_joint_id != {} {
		b2.PrismaticJoint_SetSpringHertz(avatar.prismatic_joint_id, avatar.tether_hertz)
	}
	if im.SliderFloat("Tether damping", &avatar.tether_damping, 0.0, 2.0) && avatar.prismatic_joint_id != {} {
		b2.PrismaticJoint_SetSpringDampingRatio(avatar.prismatic_joint_id, avatar.tether_damping)
	}
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
	// box2d 3.2: fixedRotation is now expressed via motion locks.
	bd.motionLocks.angularZ = true
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

	shape := b2.CreateCapsuleShape(body, sd, &capsule)

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

		orbit_max_speed = 15.0,
		orbit_accel = 60.0, // ~0.25s to full orbit speed
		orbit_decel = 20.0,
		orbit_damping = 8.0,
		reel_speed = 6.0,
		tether_hertz = 4.0, // soft, bouncy
		tether_damping = 0.7,
		tether_min = 0.10,
		tether_max = 3.0,
	}
}

avatar_pos :: proc(avatar: Avatar) -> Vec2 {
	return body_pos(avatar.body)
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

move_toward :: proc(current, target, step : f32) -> f32 {
	if abs(target - current) <= step {
		return target
	}
	return current + math.sign(target - current) * step
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

	// On possess, orient the arm so its local +X (the joint's slide axis) points at the ball.
	// With the arm rotated to axis_rot and localFrameA.q = identity, the arm's world rotation
	// is the world slide-axis angle. That's what makes positional control clean: to aim the ball at a world angle theta, drive
	// the arm rotation to theta. No localFrame offset to unwind.
	ball_dir := b2.Normalize(ball_pos - body_pos)
	axis_rot := b2.MakeRotFromUnitVector(ball_dir)

	b2.Body_SetTransform(avatar.arm_body_id, body_pos, axis_rot)
	b2.Body_SetLinearVelocity(avatar.arm_body_id, b2.Body_GetLinearVelocity(avatar.body))
	b2.Body_SetAngularVelocity(avatar.arm_body_id, 0.0)

	prismatic_joint_def := b2.DefaultPrismaticJointDef()
	prismatic_joint_def.base.bodyIdA = avatar.arm_body_id
	prismatic_joint_def.base.bodyIdB = ball.body
	prismatic_joint_def.base.localFrameA.p = {}
	prismatic_joint_def.base.localFrameA.q = b2.MakeRot(0.0) // identity
	prismatic_joint_def.base.localFrameB.p = {}
	prismatic_joint_def.base.localFrameB.q = b2.InvMulRot(b2.Body_GetRotation(ball.body), axis_rot)

	prismatic_joint_def.enableLimit = true
	prismatic_joint_def.lowerTranslation = avatar.tether_min
	prismatic_joint_def.upperTranslation = avatar.tether_max

	// Radial axis is a spring tether now instead of a velocity motor.
	// Seed the target at the current distance so the ball doesn't jump on possess
	initial_len := clamp(b2.Distance(body_pos, ball_pos), avatar.tether_min, avatar.tether_max)
	prismatic_joint_def.enableSpring = true
	prismatic_joint_def.hertz = avatar.tether_hertz
	prismatic_joint_def.dampingRatio = avatar.tether_damping
	prismatic_joint_def.targetTranslation = initial_len

	avatar.tether_length = initial_len
	avatar.arm_angular_velocity = 0.0

	// Old motor config
	//prismatic_joint_def.enableMotor = true
	//prismatic_joint_def.maxMotorForce = 50.0
	//prismatic_joint_def.motorSpeed = 0.0

	avatar.prismatic_joint_id = b2.CreatePrismaticJoint(physics_world, prismatic_joint_def)
	return true
}

avatar_depossess_ball :: proc(avatar: ^Avatar) {
	log.info("Depossess Ball")
	// wakeAttached=true so the ball (and arm) wake and respond to the release.
	b2.DestroyJoint(avatar.prismatic_joint_id, true)
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

	avatar_pos := b2.Body_GetPosition(avatar.body)
	ball_pos := b2.Body_GetPosition(g_mem.ball.body)
	avatar_to_ball_dir := la.normalize0(ball_pos - avatar_pos)

	// Arm update
	b2.Body_SetTransform(avatar.arm_body_id, avatar_pos, b2.Body_GetRotation(avatar.arm_body_id))
	b2.Body_SetLinearVelocity(avatar.arm_body_id, b2.Body_GetLinearVelocity(avatar.body))

	if avatar.prismatic_joint_id != {} {
		arrows_dir : Vec2
		if keyboard_is_key_down(g_keyboard, .UP) {
			arrows_dir.y = 1.0
		}
		if keyboard_is_key_down(g_keyboard, .LEFT) {
			arrows_dir.x = -1.0
		}
		if keyboard_is_key_down(g_keyboard, .DOWN) {
			arrows_dir.y = -1.0
		}
		if keyboard_is_key_down(g_keyboard, .RIGHT) {
			arrows_dir.x = 1.0
		}
		arrows_dir = la.normalize0(arrows_dir)
		// Need to figure out direction relative to the revolute joint

		if arrows_dir != {} {
			dt := f32(sim_ctx.dt)

			// Split input into orbit (tangential) and reel (radial), relative to the ball
			tangential := la.cross(avatar_to_ball_dir, arrows_dir)
			radial := la.dot(avatar_to_ball_dir, arrows_dir)

			// ORbit: ramp angular velocity toward target so it has momentum
			target_orbit := tangential * avatar.orbit_max_speed
			avatar.arm_angular_velocity = move_toward(avatar.arm_angular_velocity, target_orbit, avatar.orbit_accel * dt)
			if tangential == 0 {
				avatar.arm_angular_velocity *= math.exp(-avatar.orbit_damping * dt)
			}
			b2.Body_SetAngularVelocity(avatar.arm_body_id, avatar.arm_angular_velocity)

			// Reel: move the spring's target. The spring drags the ball there with bounce
			avatar.tether_length = clamp(avatar.tether_length + radial * avatar.reel_speed * dt, avatar.tether_min, avatar.tether_max)
			b2.PrismaticJoint_SetTargetTranslation(avatar.prismatic_joint_id, avatar.tether_length)
		} else {
			dt := f32(sim_ctx.dt)
			STICK_DEADZONE :: 0.15

			if gamepad_is_button_down(g_gamepad, .LEFT_SHOULDER) {
				avatar.right_stick_pos = Vec2{gamepad_axis_normalize(g_gamepad, .RIGHTX), gamepad_axis_normalize(g_gamepad, .RIGHTY) * -1.0}
			}
			stick := avatar.right_stick_pos

			mag := la.length(stick)
			if mag > 1.0 {
				stick /= mag
				mag = 1.0
			}

			target_len := avatar.tether_min
			if mag < STICK_DEADZONE {
				// Neutral stick. Stop orbiting and ball tucks in to tether_min
				avatar.arm_angular_velocity *= math.exp(-avatar.orbit_damping * dt)
			} else {
				// Aim the slide axis at the stick. Thanks to the possess-time setup,
				// the arm's world rotation is the aim angle, so RelativeAngle gives
				// the turn we still owe
				dir := stick / mag
				target_rot := b2.MakeRotFromUnitVector(dir)
				diff := b2.RelativeAngle(target_rot, b2.Body_GetRotation(avatar.arm_body_id)) // signed [-pi, pi]

				// Close that angle
				// and ramp toward it so the arm accelerates instead of jerking
				// Brake. Fastest we can be going and brake to a stop exactly at the target
				// (constant decel profile). Caps the flick so it eases in instead of overshooting.
				brake_speed := math.sqrt(2.0 * avatar.orbit_decel * abs(diff))
				max_w := min(avatar.orbit_max_speed, brake_speed)
				desired_w := clamp(diff / dt, -max_w, max_w)

				// Accelerate hard, brake gently. Use the matching rate so orbit_decel is authoritative
				rate := avatar.orbit_accel
				if abs(desired_w) < abs(avatar.arm_angular_velocity) {
					rate = avatar.orbit_decel // slowing down
				}
				avatar.arm_angular_velocity = move_toward(avatar.arm_angular_velocity, desired_w, rate * dt)

				strength := (mag - STICK_DEADZONE) / (1.0 - STICK_DEADZONE)
				target_len = math.lerp(avatar.tether_min, avatar.tether_max, strength)
			}

			// reel speed caps how fast the tether target moves. The spring (hertz/damping) then
			// physically drags the ball to it with bounce
			avatar.tether_length = move_toward(avatar.tether_length, target_len, avatar.reel_speed * dt)
			b2.Body_SetAngularVelocity(avatar.arm_body_id, avatar.arm_angular_velocity)
			b2.PrismaticJoint_SetTargetTranslation(avatar.prismatic_joint_id, avatar.tether_length)
		}
	}

	if keyboard_is_key_pressed(g_keyboard, .SPACE) || gamepad_is_button_pressed(g_gamepad, .RIGHT_SHOULDER) {
		if avatar.prismatic_joint_id == {} {
			avatar_try_possess_ball(avatar, &g_mem.ball, physics_world)
		} else {
			avatar_depossess_ball(avatar)
		}
	}

	deadzone :: 0.20
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
	
	//aim_joystick_left := gamepad_axis_normalize(g_gamepad, .RIGHTX)
	//aim_joystick_right := gamepad_axis_normalize(g_gamepad, .RIGHTY) * -1.0 // Invert
	//aim_joystick_left = apply_deadzone(deadzone, aim_joystick_left)
	//aim_joystick_right = apply_deadzone(deadzone, aim_joystick_right)
	//avatar.aim_direction = Vec2{aim_joystick_left, aim_joystick_right}
	//if la.length(avatar.aim_direction) > 1 {
	//	avatar.aim_direction = la.normalize0(avatar.aim_direction)
	//}

	
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
		//b2.Body_ApplyLinearImpulseToCenter(avatar.body, la.normalize(current_velocity) * -1.0 * avatar.move_force/2.0, true)
	}

	if dir == 0.0 {
		b2.Body_ApplyForceToCenter(avatar.body, current_velocity*-1.0*avatar.decel_force, true)
	}


}

avatar_tick_post_physics :: proc(g_mem : ^Game_Memory, avatar: ^Avatar, sim_ctx : Sim_Ctx, physics_world: b2.WorldId) {
	avatar.render_state.prev_transform = avatar.render_state.curr_transform
	avatar.render_state.curr_transform = transmute(Transform)b2.Body_GetTransform(avatar.body)
}
