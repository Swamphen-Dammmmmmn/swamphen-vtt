extends RefCounted

enum Kind { CIRCLE, CONE, RECTANGLE, LINE }
const MAX_SHAPES := 100
var shapes: Array[Dictionary] = []
var next_display_id := 1
var selected := -1
var draft: Dictionary = {}
var moving := false
var position_ready := false
var deleted: Dictionary = {}
var deleted_index := -1

static func defaults() -> Dictionary:
	return {"kind": Kind.CIRCLE, "radius": 10.0, "length": 15.0, "width": 15.0, "angle": 90.0, "rotation": 0.0, "anchor": 0}

func new_shape(parameters: Dictionary) -> bool:
	if shapes.size() >= MAX_SHAPES:
		return false
	selected = -1
	draft = defaults()
	draft["cell"] = Vector2i(14, 14)
	update_parameters(parameters)
	draft["origin"] = snapped_origin(draft, Vector2(14.5, 14.5))
	moving = true
	position_ready = false
	return true

func update_parameters(parameters: Dictionary) -> void:
	if draft.is_empty():
		return
	draft["kind"] = clampi(int(parameters.get("kind", 0)), 0, 3)
	for key in ["radius", "length", "width"]:
		draft[key] = clampf(float(parameters.get(key, draft[key])), 1.0, 300.0)
	draft["angle"] = clampf(float(parameters.get("angle", draft["angle"])), 1.0, 180.0)
	draft["rotation"] = fposmod(float(parameters.get("rotation", draft["rotation"])), 360.0)
	draft["anchor"] = clampi(int(parameters.get("anchor", draft.get("anchor", 0))), 0, 1)

func select(index: int) -> void:
	clear_draft()
	if index >= 0 and index < shapes.size():
		selected = index
		draft = shapes[index].duplicate()
		position_ready = true

func clear_draft() -> void:
	selected = -1
	draft.clear()
	moving = false
	position_ready = false

func cancel() -> void:
	if selected >= 0:
		select(selected)
	else:
		clear_draft()

func commit() -> bool:
	if draft.is_empty() or moving or not position_ready:
		return false
	if selected < 0:
		if shapes.size() >= MAX_SHAPES:
			return false
		draft["display_id"] = next_display_id
		next_display_id += 1
		shapes.append(draft.duplicate())
		selected = shapes.size() - 1
	else:
		shapes[selected] = draft.duplicate()
	return true

func delete_selected() -> void:
	if selected >= 0:
		deleted = shapes[selected].duplicate()
		deleted_index = selected
		shapes.remove_at(selected)
	clear_draft()

func undo_delete() -> bool:
	if deleted.is_empty() or shapes.size() >= MAX_SHAPES:
		return false
	var index := clampi(deleted_index, 0, shapes.size())
	shapes.insert(index, deleted.duplicate())
	if selected >= index:
		selected += 1
	forget_delete()
	return true

func forget_delete() -> void:
	deleted.clear()
	deleted_index = -1

func start_move() -> void:
	if not draft.is_empty():
		moving = true

func move_to(at: Vector2) -> bool:
	if draft.is_empty() or not moving:
		return false
	var origin := snapped_origin(draft, at)
	if draft.get("origin") == origin:
		return false
	draft["origin"] = origin
	draft["cell"] = Vector2i(origin.floor())
	return true

func fix_position(at: Vector2) -> void:
	if not draft.is_empty():
		draft["origin"] = snapped_origin(draft, at)
		draft["cell"] = Vector2i(draft["origin"].floor())
		moving = false
		position_ready = true

func dirty() -> bool:
	return not draft.is_empty() and (selected < 0 or draft != shapes[selected] or moving)

func pick(at: Vector2) -> int:
	for index in range(shapes.size() - 1, -1, -1):
		if Geometry2D.is_point_in_polygon(at, polygon(shapes[index])):
			return index
	return -1

static func polygon(data: Dictionary) -> PackedVector2Array:
	var local := PackedVector2Array()
	var length: float = data["length"] / 5.0
	var width: float = data["width"] / 5.0
	match int(data["kind"]):
		Kind.CIRCLE:
			var radius: float = data["radius"] / 5.0
			for index in range(64):
				local.append(Vector2.from_angle(TAU * float(index) / 64.0) * radius)
		Kind.CONE:
			local.append(Vector2.ZERO)
			var half: float = deg_to_rad(data["angle"]) / 2.0
			for index in range(33):
				local.append(Vector2.from_angle(lerpf(-half, half, float(index) / 32.0)) * length)
		Kind.RECTANGLE:
			if int(data.get("anchor", 0)) == 0:
				local = PackedVector2Array([Vector2.ZERO, Vector2(length, 0), Vector2(length, width), Vector2(0, width)])
			else:
				local = PackedVector2Array([Vector2(-length / 2, -width / 2), Vector2(length / 2, -width / 2), Vector2(length / 2, width / 2), Vector2(-length / 2, width / 2)])
		Kind.LINE:
			local = PackedVector2Array([Vector2(0, -width / 2), Vector2(length, -width / 2), Vector2(length, width / 2), Vector2(0, width / 2)])
	var origin := get_origin(data)
	var rotation: float = deg_to_rad(data["rotation"])
	for index in range(local.size()):
		local[index] = local[index].rotated(rotation) + origin
	return local

static func get_origin(data: Dictionary) -> Vector2:
	return data.get("origin", Vector2(data["cell"]) + Vector2(0.5, 0.5))

static func snapped_origin(data: Dictionary, at: Vector2) -> Vector2:
	if int(data["kind"]) != Kind.RECTANGLE:
		return at.floor() + Vector2(0.5, 0.5)
	if int(data.get("anchor", 0)) == 0:
		return at.round()
	var dimensions := Vector2(float(data["length"]) / 5.0, float(data["width"]) / 5.0)
	var rotation: float = data["rotation"]
	if is_zero_approx(fposmod(rotation, 90.0)) and roundi(rotation / 90.0) % 2 == 1:
		dimensions = Vector2(dimensions.y, dimensions.x)
	var result := Vector2.ZERO
	for axis in range(2):
		var even := is_equal_approx(dimensions[axis], roundf(dimensions[axis])) and roundi(dimensions[axis]) % 2 == 0
		result[axis] = roundf(at[axis]) if even else floorf(at[axis]) + 0.5
	return result
