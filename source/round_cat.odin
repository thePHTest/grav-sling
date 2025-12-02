package game

import b2 "box2d"
import rl "vendor:raylib"
import "core:fmt"
import "core:math"
import la "core:math/linalg"

_ :: math
_ :: fmt

USE_PIVOTS :: false
USE_JETS :: false

Round_Cat :: struct {
	body: b2.BodyId,
	shape: b2.ShapeId,
	squish_amount: f32,
	squish_direction: Vec2,
	squish_start: f64,
	
	jet_vertical_count : int,
	jet_horizontal_count : int,
	
	aim_range: f32,
	aim_direction: Vec2,

	pivot: Pivot,
	
	distance_joint_pivot_id: b2.BodyId,
	distance_joint: b2.JointId,
}

round_cat_make :: proc(pos: Vec2, aim_range: f32) -> Round_Cat {
	bd := b2.DefaultBodyDef()
	bd.type = .dynamicBody
	bd.position = pos
	// TODO: Instead of linearDamping, try using this for top down friction
	// https://github.com/erincatto/box2d/blob/af12713103083d4f853cfb1c65edaf96b0e43598/samples/sample_joints.cpp#L423 
	bd.linearDamping = 0.3
	bd.angularDamping = 0.7
	//bd.linearDamping = 0.0
	//bd.angularDamping = 0.0
	body := b2.CreateBody(g_mem.physics_world, bd)

	sd := b2.DefaultShapeDef()
	sd.density = 1.5
	sd.friction = 0.3
	sd.restitution = 0.0
	sd.filter = {
		categoryBits = u32(bit_set[Collision_Category] { .Round_Cat }),
		maskBits = u32(bit_set[Collision_Category] { .Long_Cat, .Wall }),
	}

	capsule := b2.Capsule {
		center1 = {0, -0.2},
		center2 = {0, 0.2},
		radius = 1,
	}

	shape := b2.CreateCapsuleShape(body, sd, capsule)

	fmt.println(body)
	fmt.println(shape)
	return {
		body = body,
		shape = shape,
		aim_range = aim_range,
	}
}

round_cat_pos :: proc(rc: Round_Cat) -> Vec2 {
	return body_pos(rc.body)
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

round_cat_draw :: proc(rc: Round_Cat) {
	a := b2.Rot_GetAngle(b2.Body_GetRotation(rc.body))
	source := atlas_textures[.Round_Cat].rect
	pos := body_pos(rc.body)
	aim_pos := pos + rc.aim_range * rc.aim_direction
	dest := draw_dest_rect(pos, source)
	
	//rl.DrawCircleV(vec2_flip(pos), rc.aim_range, rl.BLACK)

	/*t := f32(remap(rl.GetTime(), rc.squish_start, rc.squish_start + 0.5, 0, 1))

	sq := math.lerp(rc.squish_direction * rc.squish_amount, Vec2{}, smoothstart5(t))

	dest.width *= 1-sq.x
	dest.height *= 1-sq.y
	dest.x += sq.x*2
	dest.y += sq.y*2

	// rlgl scale?*/

	rl.DrawTexturePro(atlas, source, dest, {dest.width/2, dest.height/2}, -a*rl.RAD2DEG, rl.WHITE)
	
	rl.DrawLineEx(vec2_flip(pos), vec2_flip(aim_pos), 0.5, rl.RED)
	
	if rc.distance_joint_pivot_id != {} {
		pivot_pos := body_pos(rc.distance_joint_pivot_id)
		rl.DrawLineEx(vec2_flip(pos), vec2_flip(pivot_pos), 0.5, rl.DARKPURPLE)
	}

	if rc.pivot.body != {} {
		draw_pivot(rc.pivot)
	}

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

round_cat_make_distance_joint :: proc(rc: ^Round_Cat, other_body_id: b2.BodyId, physics_world: b2.WorldId) {
	// Distance joint
	joint_def := b2.DefaultDistanceJointDef()
	joint_def.bodyIdA = rc.body
	joint_def.bodyIdB = other_body_id

	joint_def.localAnchorA = Vec2{0, 0}
	joint_def.localAnchorB = Vec2{0, 0}

	anchor_a := b2.Body_GetWorldPoint(rc.body, joint_def.localAnchorA)
	anchor_b := b2.Body_GetWorldPoint(other_body_id, joint_def.localAnchorB)
	joint_def.length = b2.Distance(anchor_a, anchor_b)
	joint_def.enableLimit = true
	joint_def.minLength = 4.0
	joint_def.maxLength = max(joint_def.length + 5.0, joint_def.minLength + 1.0)
	joint_def.collideConnected = true

	// TODO: hertz value here depends on the update frequency.
	// TODO: Tune these values
	joint_def.enableSpring = true
	joint_def.hertz = 1.0
	joint_def.dampingRatio = 1.0
	
	joint_def.enableMotor = true
	joint_def.motorSpeed = -40.0
	joint_def.maxMotorForce = 10000.0

	rc.distance_joint_pivot_id = other_body_id
	rc.distance_joint = b2.CreateDistanceJoint(physics_world, joint_def)
}

round_cat_update :: proc(rc: ^Round_Cat, pivots: [dynamic]Pivot, physics_world: b2.WorldId) {
	contact_cap := b2.Body_GetContactCapacity(rc.body)
	contact_data := make([]b2.ContactData, contact_cap, context.temp_allocator)
	contact_data = b2.Body_GetContactData(rc.body, contact_data)

	for &c in contact_data {
		vel := c.manifold.points[0].normalVelocity

		if abs(vel) > 10 {
			rl.PlaySound(g_mem.land_sound)
		}
	}

	deadzone :: 0.1
	// Apply force in WASD direction controls

	dir : Vec2 = USE_JETS ? proc() -> Vec2 {
		result : Vec2
		if rl.IsKeyDown(.W) {
			result.y = 1.0
		} else if rl.IsKeyDown(.S) {
			result.y = -1.0
		} else {
			result.y = rl.GetGamepadAxisMovement(0, .LEFT_Y) * -1
			result.y = apply_deadzone(deadzone, result.y)
		}
		
		if rl.IsKeyDown(.A) {
			result.x = -1.0
		} else if rl.IsKeyDown(.D) {
			result.x = 1.0
		} else {
			result.x = rl.GetGamepadAxisMovement(0, .LEFT_X)
			result.x = apply_deadzone(deadzone, result.x)
		}
		
		return la.normalize0(result)
	}() : Vec2{}
	
	MAX_VERTICAL_JET :: 3
	MAX_HORIZONTAL_JET :: 3
	// Jet lash controls
	//if rl.IsGamepadButtonPressed(0, .LEFT_FACE_UP) {
	//	rc.jet_horizontal_count = 0
	//	rc.jet_vertical_count = clamp(rc.jet_vertical_count + 1, -MAX_VERTICAL_JET, MAX_VERTICAL_JET) 
	//} else if rl.IsGamepadButtonPressed(0, .LEFT_FACE_DOWN) {
	//	rc.jet_horizontal_count = 0
	//	rc.jet_vertical_count = clamp(rc.jet_vertical_count - 1, -MAX_VERTICAL_JET, MAX_VERTICAL_JET)
	//}
	//
	//if rl.IsGamepadButtonPressed(0, .LEFT_FACE_LEFT) {
	//	rc.jet_vertical_count = 0
	//	rc.jet_horizontal_count = clamp(rc.jet_horizontal_count - 1, -MAX_HORIZONTAL_JET, MAX_HORIZONTAL_JET)
	//} else if rl.IsGamepadButtonPressed(0, .LEFT_FACE_RIGHT) {
	//	rc.jet_vertical_count = 0
	//	rc.jet_horizontal_count = clamp(rc.jet_horizontal_count + 1, -MAX_HORIZONTAL_JET, MAX_HORIZONTAL_JET)
	//}
	//dir := la.normalize0(Vec2{f32(math.sign(rc.jet_horizontal_count)), f32(math.sign(rc.jet_vertical_count))})
	//force : f32 = 200.0
	//jet_count := math.abs(rc.jet_horizontal_count) + math.abs(rc.jet_vertical_count)
	//b2.Body_ApplyForceToCenter(rc.body, force*f32(jet_count)*dir, true)
	
	force : f32 = 400.0
	b2.Body_ApplyForceToCenter(rc.body, force*dir, true)
	
	aim_joystick_left := USE_JETS ? rl.GetGamepadAxisMovement(0, .RIGHT_X) : rl.GetGamepadAxisMovement(0, .LEFT_X)
	aim_joystick_right := USE_JETS ? rl.GetGamepadAxisMovement(0, .RIGHT_Y) : rl.GetGamepadAxisMovement(0, .LEFT_Y) * -1.0 // Invert
	aim_joystick_left = apply_deadzone(deadzone, aim_joystick_left)
	aim_joystick_right = apply_deadzone(deadzone, aim_joystick_right)
	rc.aim_direction = Vec2{aim_joystick_left, aim_joystick_right}
	if la.length(rc.aim_direction) > 1 {
		rc.aim_direction = la.normalize0(rc.aim_direction)
	}

	
	if rl.IsGamepadButtonPressed(0, .RIGHT_FACE_DOWN) {
		// TODO: Bool instead of comparing to zero struct?
		if rc.distance_joint_pivot_id == {} {
			rc_pos := body_pos(rc.body)
			// Check if our aim vector intersects a pivot
			// TODO: put aim range on rc
			RAY_THICKNESS :: 0.5


			if USE_PIVOTS {
				for pivot in pivots {
					if ray_intersects_circle_thick(rc_pos, rc.aim_direction, rc.aim_range, pivot.pos, pivot.radius, RAY_THICKNESS) {
						round_cat_make_distance_joint(rc, pivot.body, physics_world)
						break
					}
				}
			} else if rc.aim_direction != {} {
				rc.pivot = pivot_make(rc_pos + rc.aim_direction * rc.aim_range, 2.0)
				round_cat_make_distance_joint(rc, rc.pivot.body, physics_world)
			}
		
		} else {
			b2.DestroyJoint(rc.distance_joint)
			rc.distance_joint_pivot_id = {}

			if !USE_PIVOTS {
				b2.DestroyBody(rc.pivot.body)
				rc.pivot = {}
			}
		}
	}

	max_velocity :: 75.0
	current_velocity := b2.Body_GetLinearVelocity(rc.body)
	if la.length(current_velocity) > max_velocity {
		b2.Body_SetLinearVelocity(rc.body, la.normalize(current_velocity) * max_velocity)
	}
	
}
