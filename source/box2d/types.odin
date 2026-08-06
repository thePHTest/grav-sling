package box2d

import "core:c"

DEFAULT_CATEGORY_BITS :: 1
DEFAULT_MASK_BITS :: max(u64)

// Task interface
// This is the prototype for a Box2D task. Your task system is expected to run this callback on a worker
// thread, exactly once per enqueue, passing back the same taskContext pointer supplied to b2EnqueueTaskCallback.
// @ingroup world
TaskCallback :: #type proc "c" (taskContext: rawptr)

// These functions can be provided to Box2D to invoke a task system.
// Returns a pointer to the user's task object. May be nullptr. A nullptr indicates to Box2D that the work
// was executed serially within the callback and there is no need to call b2FinishTaskCallback.
// @ingroup world
EnqueueTaskCallback :: #type proc "c" (task: TaskCallback, taskContext: rawptr, userContext: rawptr) -> rawptr

// Finishes a user task object that wraps a Box2D task.
// @ingroup world
FinishTaskCallback :: #type proc "c" (userTask: rawptr, userContext: rawptr)

// Optional friction mixing callback. This intentionally provides no context objects because this is called
// from a worker thread.
// @ingroup world
FrictionCallback :: #type proc "c" (frictionA: f32, userMaterialIdA: u64, frictionB: f32, userMaterialIdB: u64) -> f32

// Optional restitution mixing callback. This intentionally provides no context objects because this is called
// from a worker thread.
// @ingroup world
RestitutionCallback :: #type proc "c" (restitutionA: f32, userMaterialIdA: u64, restitutionB: f32, userMaterialIdB: u64) -> f32

// Result from b2World_RayCastClosest
// If there is initial overlap the fraction and normal will be zero while the point is an arbitrary point in the overlap region.
// @ingroup world
RayResult :: struct {
	shapeId:    ShapeId,
	point:      Pos,
	normal:     Vec2,
	fraction:   f32,
	nodeVisits: i32,
	leafVisits: i32,
	hit:        bool,
}

// Optional world capacities that can be used to avoid run-time allocations.
// @see b2World_GetMaxCapacity
// @ingroup world
Capacity :: struct {
	// Number of expected static shapes.
	staticShapeCount: i32,
	// Number of expected dynamic and kinematic shapes.
	dynamicShapeCount: i32,
	// Number of expected static bodies.
	staticBodyCount: i32,
	// Number of expected dynamic and kinematic bodies.
	dynamicBodyCount: i32,
	// Number of expected contacts.
	contactCount: i32,
}

// World definition used to create a simulation world.
// Must be initialized using b2DefaultWorldDef().
// @ingroup world
WorldDef :: struct {
	// Gravity vector. Box2D has no up-vector defined.
	gravity: Vec2,

	// Restitution speed threshold, usually in m/s. Collisions above this speed have restitution applied (will bounce).
	restitutionThreshold: f32,

	// Threshold speed for hit events. Usually meters per second.
	hitEventThreshold: f32,

	// Contact stiffness. Cycles per second.
	contactHertz: f32,

	// Contact bounciness. Non-dimensional.
	contactDampingRatio: f32,

	// This parameter controls how fast overlap is resolved and usually has units of meters per second.
	contactSpeed: f32,

	// Maximum linear speed. Usually meters per second.
	maximumLinearSpeed: f32,

	// Optional mixing callback for friction. The default uses sqrt(frictionA * frictionB).
	frictionCallback: FrictionCallback,

	// Optional mixing callback for restitution. The default uses max(restitutionA, restitutionB).
	restitutionCallback: RestitutionCallback,

	// Can bodies go to sleep to improve performance
	enableSleep: bool,

	// Enable continuous collision
	enableContinuous: bool,

	// Contact softening when mass ratios are large. Experimental.
	enableContactSoftening: bool,

	// Number of workers for multithreading. Clamped to [1, B2_MAX_WORKERS].
	workerCount: i32,

	// Function to spawn tasks
	enqueueTask: EnqueueTaskCallback,

	// Function to finish a task
	finishTask: FinishTaskCallback,

	// User context that is provided to enqueueTask and finishTask
	userTaskContext: rawptr,

	// User data
	userData: rawptr,

	// Optional initial capacities
	capacity: Capacity,

	// Used internally to detect a valid definition. DO NOT SET.
	internalValue: i32,
}

// The body simulation type.
// @ingroup body
BodyType :: enum c.int {
	// zero mass, zero velocity, may be manually moved
	staticBody = 0,
	// zero mass, velocity set by user, moved by solver
	kinematicBody = 1,
	// positive mass, velocity determined by forces, moved by solver
	dynamicBody = 2,
}

// number of body types
bodyTypeCount :: len(BodyType)

// Motion locks to restrict the body movement.
MotionLocks :: struct {
	// Prevent translation along the x-axis
	linearX: bool,
	// Prevent translation along the y-axis
	linearY: bool,
	// Prevent rotation around the z-axis
	angularZ: bool,
}

// A body definition holds all the data needed to construct a rigid body.
// Must be initialized using b2DefaultBodyDef().
// @ingroup body
BodyDef :: struct {
	// The body type: static, kinematic, or dynamic.
	type: BodyType,

	// The initial world position of the body.
	position: Pos,

	// The initial world rotation of the body. Use b2MakeRot() if you have an angle.
	rotation: Rot,

	// The initial linear velocity of the body's origin. Usually in meters per second.
	linearVelocity: Vec2,

	// The initial angular velocity of the body. Radians per second.
	angularVelocity: f32,

	// Linear damping is used to reduce the linear velocity.
	linearDamping: f32,

	// Angular damping is used to reduce the angular velocity.
	angularDamping: f32,

	// Scale the gravity applied to this body. Non-dimensional.
	gravityScale: f32,

	// Sleep speed threshold, default is 0.05 meters per second
	sleepThreshold: f32,

	// Optional body name for debugging. Up to B2_NAME_LENGTH characters
	name: cstring,

	// Use this to store application specific body data.
	userData: rawptr,

	// Motion locks to restrict linear and angular movement.
	motionLocks: MotionLocks,

	// Set this flag to false if this body should never fall asleep.
	enableSleep: bool,

	// Is this body initially awake or sleeping?
	isAwake: bool,

	// Treat this body as a high speed object that performs continuous collision detection.
	isBullet: bool,

	// Used to disable a body. A disabled body does not move or collide.
	isEnabled: bool,

	// This allows this body to bypass rotational speed limits. Should only be used for circular objects, like wheels.
	allowFastRotation: bool,

	// Enable contact recycling. True by default.
	enableContactRecycling: bool,

	// Used internally to detect a valid definition. DO NOT SET.
	internalValue: i32,
}

// This is used to filter collision on shapes.
// @ingroup shape
Filter :: struct {
	// The collision category bits. Normally you would just set one bit.
	categoryBits: u64,

	// The collision mask bits. This states the categories that this shape would accept for collision.
	maskBits: u64,

	// Collision groups allow a certain group of objects to never collide (negative) or always collide (positive).
	groupIndex: i32,
}

// The query filter is used to filter collisions between queries and shapes.
// @ingroup shape
QueryFilter :: struct {
	// The collision category bits of this query. Normally you would just set one bit.
	categoryBits: u64,

	// The collision mask bits. This states the shape categories that this query would accept for collision.
	maskBits: u64,
}

// Shape type
// @ingroup shape
ShapeType :: enum c.int {
	// A circle with an offset
	circleShape,
	// A capsule is an extruded circle
	capsuleShape,
	// A line segment
	segmentShape,
	// A convex polygon
	polygonShape,
	// A line segment owned by a chain shape
	chainSegmentShape,
}

// The number of shape types
shapeTypeCount :: len(ShapeType)

// Surface materials allow chain shapes to have per segment surface properties.
// @ingroup shape
SurfaceMaterial :: struct {
	// The Coulomb (dry) friction coefficient, usually in the range [0,1].
	friction: f32,

	// The coefficient of restitution (bounce) usually in the range [0,1].
	restitution: f32,

	// The rolling resistance usually in the range [0,1].
	rollingResistance: f32,

	// The tangent speed for conveyor belts
	tangentSpeed: f32,

	// User material identifier. Passed with query results and to friction/restitution combining functions.
	userMaterialId: u64,

	// Custom debug draw color.
	customColor: u32,
}

// Used to create a shape.
// Must be initialized using b2DefaultShapeDef().
// @ingroup shape
ShapeDef :: struct {
	// Use this to store application specific shape data.
	userData: rawptr,

	// The surface material for this shape.
	material: SurfaceMaterial,

	// The density, usually in kg/m^2.
	density: f32,

	// Collision filtering data.
	filter: Filter,

	// Enable custom filtering. Only one of the two shapes needs to enable custom filtering. See b2WorldDef.
	enableCustomFiltering: bool,

	// A sensor shape generates overlap events but never generates a collision response.
	isSensor: bool,

	// Enable sensor events for this shape. Both shapes involved must have this flag set. False by default.
	enableSensorEvents: bool,

	// Enable contact events for this shape. Only one shape involved needs this flag set. False by default.
	enableContactEvents: bool,

	// Enable hit events for this shape. Only one shape involved needs this flag set. False by default.
	enableHitEvents: bool,

	// Enable pre-solve contact events for this shape. Only applies to dynamic bodies.
	enablePreSolveEvents: bool,

	// When shapes are created they will scan the environment for collision the next time step.
	invokeContactCreation: bool,

	// Should the body update the mass properties when this shape is created. Default is true.
	updateBodyMass: bool,

	// Used internally to detect a valid definition. DO NOT SET.
	internalValue: i32,
}

// Used to create a chain of line segments.
// Must be initialized using b2DefaultChainDef().
// @ingroup shape
ChainDef :: struct {
	// Use this to store application specific shape data.
	userData: rawptr,

	// An array of at least 4 points. These are cloned and may be temporary.
	points: [^]Vec2 `fmt:"v,count"`,

	// The point count, must be 4 or more.
	count: i32,

	// Surface materials for each segment. These are cloned.
	materials: [^]SurfaceMaterial `fmt:"v,materialCount"`,

	// The material count. Must be 1 or count.
	materialCount: i32,

	// Contact filtering data.
	filter: Filter,

	// Indicates a closed chain formed by connecting the first and last points
	isLoop: bool,

	// Enable sensors to detect this chain. False by default.
	enableSensorEvents: bool,

	// Used internally to detect a valid definition. DO NOT SET.
	internalValue: i32,
}

//! @cond
// Profiling data. Times are in milliseconds.
Profile :: struct {
	step:                f32,
	pairs:               f32,
	collide:             f32,
	solve:               f32,
	solverSetup:         f32,
	constraints:         f32,
	prepareConstraints:  f32,
	integrateVelocities: f32,
	warmStart:           f32,
	solveImpulses:       f32,
	integratePositions:  f32,
	relaxImpulses:       f32,
	applyRestitution:    f32,
	storeImpulses:       f32,
	splitIslands:        f32,
	transforms:          f32,
	sensorHits:          f32,
	jointEvents:         f32,
	hitEvents:           f32,
	refit:               f32,
	bullets:             f32,
	sleepIslands:        f32,
	sensors:             f32,
}

// Counters that give details of the simulation size.
Counters :: struct {
	byteCount:        i64,
	bodyCount:        i32,
	shapeCount:       i32,
	contactCount:     i32,
	jointCount:       i32,
	islandCount:      i32,
	stackUsed:        i32,
	staticTreeHeight: i32,
	treeHeight:       i32,
	taskCount:        i32,
	colorCounts:      [24]i32,
	// Number of contacts touched by the collide pass (graph contacts + awake-set non-touching).
	awakeContactCount: i32,
	// Number of contacts recycled in the most recent step.
	recycledContactCount: i32,
}
//! @endcond

// Joint type enumeration
// @ingroup joint
JointType :: enum c.int {
	distanceJoint,
	filterJoint,
	motorJoint,
	prismaticJoint,
	revoluteJoint,
	weldJoint,
	wheelJoint,
}

// Base joint definition used by all joint types.
// The local frames are measured from the body's origin rather than the center of mass.
JointDef :: struct {
	// User data pointer
	userData: rawptr,

	// The first attached body
	bodyIdA: BodyId,

	// The second attached body
	bodyIdB: BodyId,

	// The first local joint frame
	localFrameA: Transform,

	// The second local joint frame
	localFrameB: Transform,

	// Force threshold for joint events
	forceThreshold: f32,

	// Torque threshold for joint events
	torqueThreshold: f32,

	// Constraint hertz (advanced feature)
	constraintHertz: f32,

	// Constraint damping ratio (advanced feature)
	constraintDampingRatio: f32,

	// Debug draw scale
	drawScale: f32,

	// Set this flag to true if the attached bodies should collide
	collideConnected: bool,
}

// Distance joint definition
// @ingroup distance_joint
DistanceJointDef :: struct {
	// Base joint definition
	base: JointDef,

	// The rest length of this joint. Clamped to a stable minimum value.
	length: f32,

	// Enable the distance constraint to behave like a spring.
	enableSpring: bool,

	// The lower spring force controls how much tension it can sustain
	lowerSpringForce: f32,

	// The upper spring force controls how much compression it can sustain
	upperSpringForce: f32,

	// The spring linear stiffness Hertz, cycles per second
	hertz: f32,

	// The spring linear damping ratio, non-dimensional
	dampingRatio: f32,

	// Enable/disable the joint limit
	enableLimit: bool,

	// Minimum length for limit. Clamped to a stable minimum value.
	minLength: f32,

	// Maximum length for limit. Must be greater than or equal to the minimum length.
	maxLength: f32,

	// Enable/disable the joint motor
	enableMotor: bool,

	// The maximum motor force, usually in newtons
	maxMotorForce: f32,

	// The desired motor speed, usually in meters per second
	motorSpeed: f32,

	// Used internally to detect a valid definition. DO NOT SET.
	internalValue: i32,
}

// A motor joint is used to control the relative velocity and or transform between two bodies.
// @ingroup motor_joint
MotorJointDef :: struct {
	// Base joint definition
	base: JointDef,

	// The desired linear velocity
	linearVelocity: Vec2,

	// The maximum motor force in newtons
	maxVelocityForce: f32,

	// The desired angular velocity
	angularVelocity: f32,

	// The maximum motor torque in newton-meters
	maxVelocityTorque: f32,

	// Linear spring hertz for position control
	linearHertz: f32,

	// Linear spring damping ratio
	linearDampingRatio: f32,

	// Maximum spring force in newtons
	maxSpringForce: f32,

	// Angular spring hertz for position control
	angularHertz: f32,

	// Angular spring damping ratio
	angularDampingRatio: f32,

	// Maximum spring torque in newton-meters
	maxSpringTorque: f32,

	// Used internally to detect a valid definition. DO NOT SET.
	internalValue: i32,
}

// A filter joint is used to disable collision between two specific bodies.
// @ingroup filter_joint
FilterJointDef :: struct {
	// Base joint definition
	base: JointDef,

	// Used internally to detect a valid definition. DO NOT SET.
	internalValue: i32,
}

// Prismatic joint definition
// @ingroup prismatic_joint
PrismaticJointDef :: struct {
	// Base joint definition
	base: JointDef,

	// Enable a linear spring along the prismatic joint axis
	enableSpring: bool,

	// The spring stiffness Hertz, cycles per second
	hertz: f32,

	// The spring damping ratio, non-dimensional
	dampingRatio: f32,

	// The target translation for the joint in meters. The spring-damper will drive to this translation.
	targetTranslation: f32,

	// Enable/disable the joint limit
	enableLimit: bool,

	// The lower translation limit
	lowerTranslation: f32,

	// The upper translation limit
	upperTranslation: f32,

	// Enable/disable the joint motor
	enableMotor: bool,

	// The maximum motor force, typically in newtons
	maxMotorForce: f32,

	// The desired motor speed, typically in meters per second
	motorSpeed: f32,

	// Used internally to detect a valid definition. DO NOT SET.
	internalValue: i32,
}

// Revolute joint definition
// @ingroup revolute_joint
RevoluteJointDef :: struct {
	// Base joint definition
	base: JointDef,

	// The target angle for the joint in radians. The spring-damper will drive to this angle.
	targetAngle: f32,

	// Enable a rotational spring on the revolute hinge axis
	enableSpring: bool,

	// The spring stiffness Hertz, cycles per second
	hertz: f32,

	// The spring damping ratio, non-dimensional
	dampingRatio: f32,

	// A flag to enable joint limits
	enableLimit: bool,

	// The lower angle for the joint limit in radians. Minimum of -0.99*pi radians.
	lowerAngle: f32,

	// The upper angle for the joint limit in radians. Maximum of 0.99*pi radians.
	upperAngle: f32,

	// A flag to enable the joint motor
	enableMotor: bool,

	// The maximum motor torque, typically in newton-meters
	maxMotorTorque: f32,

	// The desired motor speed in radians per second
	motorSpeed: f32,

	// Used internally to detect a valid definition. DO NOT SET.
	internalValue: i32,
}

// Weld joint definition
// @ingroup weld_joint
WeldJointDef :: struct {
	// Base joint definition
	base: JointDef,

	// Linear stiffness expressed as Hertz (cycles per second). Use zero for maximum stiffness.
	linearHertz: f32,

	// Angular stiffness as Hertz (cycles per second). Use zero for maximum stiffness.
	angularHertz: f32,

	// Linear damping ratio, non-dimensional. Use 1 for critical damping.
	linearDampingRatio: f32,

	// Angular damping ratio, non-dimensional. Use 1 for critical damping.
	angularDampingRatio: f32,

	// Used internally to detect a valid definition. DO NOT SET.
	internalValue: i32,
}

// Wheel joint definition
// @ingroup wheel_joint
WheelJointDef :: struct {
	// Base joint definition
	base: JointDef,

	// Enable a linear spring along the local axis
	enableSpring: bool,

	// Spring stiffness in Hertz
	hertz: f32,

	// Spring damping ratio, non-dimensional
	dampingRatio: f32,

	// Enable/disable the joint linear limit
	enableLimit: bool,

	// The lower translation limit
	lowerTranslation: f32,

	// The upper translation limit
	upperTranslation: f32,

	// Enable/disable the joint rotational motor
	enableMotor: bool,

	// The maximum motor torque, typically in newton-meters
	maxMotorTorque: f32,

	// The desired motor speed in radians per second
	motorSpeed: f32,

	// Used internally to detect a valid definition. DO NOT SET.
	internalValue: i32,
}

// The explosion definition is used to configure options for explosions.
// @ingroup world
ExplosionDef :: struct {
	// Mask bits to filter shapes
	maskBits: u64,

	// The center of the explosion in world space
	position: Pos,

	// The radius of the explosion
	radius: f32,

	// The falloff distance beyond the radius.
	falloff: f32,

	// Impulse per unit length.
	impulsePerLength: f32,
}

/**
 * @defgroup events Events
 * World event types.
 * @{
 */

// A begin touch event is generated when a shape starts to overlap a sensor shape.
SensorBeginTouchEvent :: struct {
	// The id of the sensor shape
	sensorShapeId: ShapeId,
	// The id of the shape that began touching the sensor shape
	visitorShapeId: ShapeId,
}

// An end touch event is generated when a shape stops overlapping a sensor shape.
SensorEndTouchEvent :: struct {
	// The id of the sensor shape
	sensorShapeId: ShapeId,
	// The id of the shape that stopped touching the sensor shape
	visitorShapeId: ShapeId,
}

// Sensor events are buffered in the world.
SensorEvents :: struct {
	// Array of sensor begin touch events
	beginEvents: [^]SensorBeginTouchEvent `fmt:"v,beginCount"`,
	// Array of sensor end touch events
	endEvents: [^]SensorEndTouchEvent `fmt:"v,endCount"`,
	// The number of begin touch events
	beginCount: i32,
	// The number of end touch events
	endCount: i32,
}

// A begin touch event is generated when two shapes begin touching.
ContactBeginTouchEvent :: struct {
	// Id of the first shape
	shapeIdA: ShapeId,
	// Id of the second shape
	shapeIdB: ShapeId,
	// The transient contact id. Use b2Contact_IsValid before using this id.
	contactId: ContactId,
}

// An end touch event is generated when two shapes stop touching.
ContactEndTouchEvent :: struct {
	// Id of the first shape
	shapeIdA: ShapeId,
	// Id of the second shape
	shapeIdB: ShapeId,
	// Id of the contact.
	contactId: ContactId,
}

// A hit touch event is generated when two shapes collide with a speed faster than the hit speed threshold.
ContactHitEvent :: struct {
	// Id of the first shape
	shapeIdA: ShapeId,
	// Id of the second shape
	shapeIdB: ShapeId,
	// Id of the contact.
	contactId: ContactId,
	// Point where the shapes hit.
	point: Pos,
	// Normal vector pointing from shape A to shape B
	normal: Vec2,
	// The speed the shapes are approaching. Always positive. Typically in meters per second.
	approachSpeed: f32,
}

// Contact events are buffered in the Box2D world.
ContactEvents :: struct {
	// Array of begin touch events
	beginEvents: [^]ContactBeginTouchEvent `fmt:"v,beginCount"`,
	// Array of end touch events
	endEvents: [^]ContactEndTouchEvent `fmt:"v,endCount"`,
	// Array of hit events
	hitEvents: [^]ContactHitEvent `fmt:"v,hitCount"`,
	// Number of begin touch events
	beginCount: i32,
	// Number of end touch events
	endCount: i32,
	// Number of hit events
	hitCount: i32,
}

// Body move events triggered when a body moves.
BodyMoveEvent :: struct {
	userData:   rawptr,
	transform:  WorldTransform,
	bodyId:     BodyId,
	fellAsleep: bool,
}

// Body events are buffered in the Box2D world.
BodyEvents :: struct {
	// Array of move events
	moveEvents: [^]BodyMoveEvent `fmt:"v,moveCount"`,
	// Number of move events
	moveCount: i32,
}

// Joint events report joints that are awake and have a force and/or torque exceeding the threshold.
JointEvent :: struct {
	// The joint id
	jointId: JointId,
	// The user data from the joint for convenience
	userData: rawptr,
}

// Joint events are buffered in the world.
JointEvents :: struct {
	// Array of events
	jointEvents: [^]JointEvent `fmt:"v,count"`,
	// Number of events
	count: i32,
}

// The contact data for two shapes. By convention the manifold normal points from shape A to shape B.
// @see b2Shape_GetContactData() and b2Body_GetContactData()
ContactData :: struct {
	contactId: ContactId,
	shapeIdA:  ShapeId,
	shapeIdB:  ShapeId,
	manifold:  Manifold,
}

/**@}*/

// Prototype for a contact filter callback.
// Return false if you want to disable the collision.
// @ingroup world
CustomFilterFcn :: #type proc "c" (shapeIdA, shapeIdB: ShapeId, ctx: rawptr) -> bool

// Prototype for a pre-solve callback.
// Return false if you want to disable the contact this step.
// @ingroup world
PreSolveFcn :: #type proc "c" (shapeIdA, shapeIdB: ShapeId, point: Pos, normal: Vec2, ctx: rawptr) -> bool

// Prototype callback for overlap queries.
// @return false to terminate the query.
// @ingroup world
OverlapResultFcn :: #type proc "c" (shapeId: ShapeId, ctx: rawptr) -> bool

// Prototype callback for ray and shape casts.
// @return -1 to filter, 0 to terminate, fraction to clip the ray for closest hit, 1 to continue
// @ingroup world
CastResultFcn :: #type proc "c" (shapeId: ShapeId, point: Pos, normal: Vec2, fraction: f32, ctx: rawptr) -> f32

// Used to collect collision planes for character movers.
// Return true to continue gathering planes.
PlaneResultFcn :: #type proc "c" (shapeId: ShapeId, plane: ^PlaneResult, ctx: rawptr) -> bool

// These colors are used for debug draw and mostly match the named SVG colors.
HexColor :: enum c.int {
	AliceBlue            = 0xF0F8FF,
	AntiqueWhite         = 0xFAEBD7,
	Aqua                 = 0x00FFFF,
	Aquamarine           = 0x7FFFD4,
	Azure                = 0xF0FFFF,
	Beige                = 0xF5F5DC,
	Bisque               = 0xFFE4C4,
	Black                = 0x000000,
	BlanchedAlmond       = 0xFFEBCD,
	Blue                 = 0x0000FF,
	BlueViolet           = 0x8A2BE2,
	Brown                = 0xA52A2A,
	Burlywood            = 0xDEB887,
	CadetBlue            = 0x5F9EA0,
	Chartreuse           = 0x7FFF00,
	Chocolate            = 0xD2691E,
	Coral                = 0xFF7F50,
	CornflowerBlue       = 0x6495ED,
	Cornsilk             = 0xFFF8DC,
	Crimson              = 0xDC143C,
	Cyan                 = 0x00FFFF,
	DarkBlue             = 0x00008B,
	DarkCyan             = 0x008B8B,
	DarkGoldenRod        = 0xB8860B,
	DarkGray             = 0xA9A9A9,
	DarkGreen            = 0x006400,
	DarkKhaki            = 0xBDB76B,
	DarkMagenta          = 0x8B008B,
	DarkOliveGreen       = 0x556B2F,
	DarkOrange           = 0xFF8C00,
	DarkOrchid           = 0x9932CC,
	DarkRed              = 0x8B0000,
	DarkSalmon           = 0xE9967A,
	DarkSeaGreen         = 0x8FBC8F,
	DarkSlateBlue        = 0x483D8B,
	DarkSlateGray        = 0x2F4F4F,
	DarkTurquoise        = 0x00CED1,
	DarkViolet           = 0x9400D3,
	DeepPink             = 0xFF1493,
	DeepSkyBlue          = 0x00BFFF,
	DimGray              = 0x696969,
	DodgerBlue           = 0x1E90FF,
	FireBrick            = 0xB22222,
	FloralWhite          = 0xFFFAF0,
	ForestGreen          = 0x228B22,
	Fuchsia              = 0xFF00FF,
	Gainsboro            = 0xDCDCDC,
	GhostWhite           = 0xF8F8FF,
	Gold                 = 0xFFD700,
	GoldenRod            = 0xDAA520,
	Gray                 = 0x808080,
	Green                = 0x008000,
	GreenYellow          = 0xADFF2F,
	HoneyDew             = 0xF0FFF0,
	HotPink              = 0xFF69B4,
	IndianRed            = 0xCD5C5C,
	Indigo               = 0x4B0082,
	Ivory                = 0xFFFFF0,
	Khaki                = 0xF0E68C,
	Lavender             = 0xE6E6FA,
	LavenderBlush        = 0xFFF0F5,
	LawnGreen            = 0x7CFC00,
	LemonChiffon         = 0xFFFACD,
	LightBlue            = 0xADD8E6,
	LightCoral           = 0xF08080,
	LightCyan            = 0xE0FFFF,
	LightGoldenRodYellow = 0xFAFAD2,
	LightGray            = 0xD3D3D3,
	LightGreen           = 0x90EE90,
	LightPink            = 0xFFB6C1,
	LightSalmon          = 0xFFA07A,
	LightSeaGreen        = 0x20B2AA,
	LightSkyBlue         = 0x87CEFA,
	LightSlateGray       = 0x778899,
	LightSteelBlue       = 0xB0C4DE,
	LightYellow          = 0xFFFFE0,
	Lime                 = 0x00FF00,
	LimeGreen            = 0x32CD32,
	Linen                = 0xFAF0E6,
	Magenta              = 0xFF00FF,
	Maroon               = 0x800000,
	MediumAquaMarine     = 0x66CDAA,
	MediumBlue           = 0x0000CD,
	MediumOrchid         = 0xBA55D3,
	MediumPurple         = 0x9370DB,
	MediumSeaGreen       = 0x3CB371,
	MediumSlateBlue      = 0x7B68EE,
	MediumSpringGreen    = 0x00FA9A,
	MediumTurquoise      = 0x48D1CC,
	MediumVioletRed      = 0xC71585,
	MidnightBlue         = 0x191970,
	MintCream            = 0xF5FFFA,
	MistyRose            = 0xFFE4E1,
	Moccasin             = 0xFFE4B5,
	NavajoWhite          = 0xFFDEAD,
	Navy                 = 0x000080,
	OldLace              = 0xFDF5E6,
	Olive                = 0x808000,
	OliveDrab            = 0x6B8E23,
	Orange               = 0xFFA500,
	OrangeRed            = 0xFF4500,
	Orchid               = 0xDA70D6,
	PaleGoldenRod        = 0xEEE8AA,
	PaleGreen            = 0x98FB98,
	PaleTurquoise        = 0xAFEEEE,
	PaleVioletRed        = 0xDB7093,
	PapayaWhip           = 0xFFEFD5,
	PeachPuff            = 0xFFDAB9,
	Peru                 = 0xCD853F,
	Pink                 = 0xFFC0CB,
	Plum                 = 0xDDA0DD,
	PowderBlue           = 0xB0E0E6,
	Purple               = 0x800080,
	RebeccaPurple        = 0x663399,
	Red                  = 0xFF0000,
	RosyBrown            = 0xBC8F8F,
	RoyalBlue            = 0x4169E1,
	SaddleBrown          = 0x8B4513,
	Salmon               = 0xFA8072,
	SandyBrown           = 0xF4A460,
	SeaGreen             = 0x2E8B57,
	SeaShell             = 0xFFF5EE,
	Sienna               = 0xA0522D,
	Silver               = 0xC0C0C0,
	SkyBlue              = 0x87CEEB,
	SlateBlue            = 0x6A5ACD,
	SlateGray            = 0x708090,
	Snow                 = 0xFFFAFA,
	SpringGreen          = 0x00FF7F,
	SteelBlue            = 0x4682B4,
	Tan                  = 0xD2B48C,
	Teal                 = 0x008080,
	Thistle              = 0xD8BFD8,
	Tomato               = 0xFF6347,
	Turquoise            = 0x40E0D0,
	Violet               = 0xEE82EE,
	Wheat                = 0xF5DEB3,
	White                = 0xFFFFFF,
	WhiteSmoke           = 0xF5F5F5,
	Yellow               = 0xFFFF00,
	YellowGreen          = 0x9ACD32,
	Box2DRed             = 0xDC3132,
	Box2DBlue            = 0x30AEBF,
	Box2DGreen           = 0x8CC924,
	Box2DYellow          = 0xFFEE8C,
}

// This struct holds callbacks you can implement to draw a Box2D world.
// Initialize with b2DefaultDebugDraw.
// @ingroup world
DebugDraw :: struct {
	// Draw a closed polygon provided in CCW order.
	DrawPolygonFcn: proc "c" (transform: WorldTransform, vertices: [^]Vec2, vertexCount: c.int, color: HexColor, ctx: rawptr),

	// Draw a solid closed polygon provided in CCW order.
	DrawSolidPolygonFcn: proc "c" (transform: WorldTransform, vertices: [^]Vec2, vertexCount: c.int, radius: f32, color: HexColor, ctx: rawptr),

	// Draw a circle.
	DrawCircleFcn: proc "c" (center: Pos, radius: f32, color: HexColor, ctx: rawptr),

	// Draw a solid circle.
	DrawSolidCircleFcn: proc "c" (transform: WorldTransform, center: Vec2, radius: f32, color: HexColor, ctx: rawptr),

	// Draw a solid capsule.
	DrawSolidCapsuleFcn: proc "c" (p1, p2: Pos, radius: f32, color: HexColor, ctx: rawptr),

	// Draw a line segment.
	DrawLineFcn: proc "c" (p1, p2: Pos, color: HexColor, ctx: rawptr),

	// Draw a transform. Choose your own length scale.
	DrawTransformFcn: proc "c" (transform: WorldTransform, ctx: rawptr),

	// Draw a point.
	DrawPointFcn: proc "c" (p: Pos, size: f32, color: HexColor, ctx: rawptr),

	// Draw a string in world space.
	DrawStringFcn: proc "c" (p: Pos, s: cstring, color: HexColor, ctx: rawptr),

	// Draw a bounding box.
	DrawBoundsFcn: proc "c" (aabb: AABB, color: HexColor, ctx: rawptr),

	// World bounds to use for debug draw
	drawingBounds: AABB,

	// Scale to use when drawing forces
	forceScale: f32,

	// Global scaling for joint drawing
	jointScale: f32,

	// Option to draw contact points
	drawContacts: bool,

	// Draw anchor A for contact points (instead of anchorB)
	drawAnchorA: bool,

	// Option to draw shapes
	drawShapes: bool,

	// Option to draw chain shape normals
	drawChainNormals: bool,

	// Option to draw joints
	drawJoints: bool,

	// Option to draw additional information for joints
	drawJointExtras: bool,

	// Option to draw the bounding boxes for shapes
	drawBounds: bool,

	// Option to draw the mass and center of mass of dynamic bodies
	drawMass: bool,

	// Option to draw body names
	drawBodyNames: bool,

	// Option to visualize the graph coloring used for contacts and joints
	drawGraphColors: bool,

	// Option to draw contact feature ids
	drawContactFeatures: bool,

	// Option to draw contact normals
	drawContactNormals: bool,

	// Option to draw contact normal forces
	drawContactForces: bool,

	// Option to draw contact friction forces
	drawFrictionForces: bool,

	// Option to draw islands as bounding boxes
	drawIslands: bool,

	// User context that is passed as an argument to drawing callback functions
	userContext: rawptr,
}
