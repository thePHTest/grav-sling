package box2d

import "base:intrinsics"

/**
 * @defgroup id Ids
 * These ids serve as handles to internal Box2D objects.
 * These should be considered opaque data and passed by value.
 * Include this header if you need the id types and not the whole Box2D API.
 * All ids are considered null if initialized to zero.
 *
 * For example in Odin:
 *
 * @code{.odin}
 * worldId := b2.WorldId{}
 * @endcode
 *
 * This is considered null.
 *
 * @warning Do not use the internals of these ids. They are subject to change. Ids should be treated as opaque objects.
 * @warning You should use ids to access objects in Box2D. Do not access files within the src folder. Such usage is unsupported.
 */

/// World id references a world instance. This should be treated as an opaque handle.
WorldId :: struct {
	index1:     u16,
	generation: u16,
}

/// Body id references a body instance. This should be treated as an opaque handle.
BodyId :: struct {
	index1:     i32,
	world0:     u16,
	generation: u16,
}

/// Shape id references a shape instance. This should be treated as an opaque handle.
ShapeId :: struct {
	index1:     i32,
	world0:     u16,
	generation: u16,
}

/// Chain id references a chain instances. This should be treated as an opaque handle.
ChainId :: struct {
	index1:     i32,
	world0:     u16,
	generation: u16,
}

/// Joint id references a joint instance. This should be treated as an opaque handle.
JointId :: struct {
	index1:     i32,
	world0:     u16,
	generation: u16,
}

/// Contact id references a contact instance. This should be treated as an opaque handle.
ContactId :: struct {
	index1:     i32,
	world0:     u16,
	padding:    i16,
	generation: u32,
}


/// Use these to make your identifiers null.
/// You may also use zero initialization to get null.
nullWorldId   :: WorldId{}
nullBodyId    :: BodyId{}
nullShapeId   :: ShapeId{}
nullChainId   :: ChainId{}
nullJointId   :: JointId{}
nullContactId :: ContactId{}

/// Macro to determine if any id is null.
IS_NULL :: #force_inline proc "c" (id: $T) -> bool
	where intrinsics.type_is_struct(T),
	      intrinsics.type_has_field(T, "index1") {
	return id.index1 == 0
}

/// Macro to determine if any id is non-null.
IS_NON_NULL :: #force_inline proc "c" (id: $T) -> bool
	where intrinsics.type_is_struct(T),
	      intrinsics.type_has_field(T, "index1") {
	return id.index1 != 0
}

/// Compare two ids for equality. Doesn't work for b2WorldId.
ID_EQUALS :: #force_inline proc "c" (id1, id2: $T) -> bool
	where intrinsics.type_is_struct(T),
	      intrinsics.type_has_field(T, "index1"),
	      intrinsics.type_has_field(T, "world0"),
	      intrinsics.type_has_field(T, "generation") {
	return id1.index1 == id2.index1 && id1.world0 == id2.world0 && id1.generation == id2.generation
}

// Store a world id into a u32.
StoreWorldId :: #force_inline proc "c" (id: WorldId) -> u32 {
	return (u32(id.index1) << 16) | u32(id.generation)
}

// Load a u32 into a world id.
LoadWorldId :: #force_inline proc "c" (x: u32) -> WorldId {
	return {
		u16(x >> 16),
		u16(x),
	}
}

// Store a contact id into three u32 values.
StoreContactId :: #force_inline proc "c" (id: ContactId, values: ^[3]u32) {
	values[0] = u32(id.index1)
	values[1] = u32(id.world0)
	values[2] = u32(id.generation)
}

// Load three u32 values into a contact id.
LoadContactId :: #force_inline proc "c" (values: [3]u32) -> ContactId {
	id: ContactId
	id.index1     = i32(values[0])
	id.world0     = u16(values[1])
	id.padding    = 0
	id.generation = u32(values[2])
	return id
}
