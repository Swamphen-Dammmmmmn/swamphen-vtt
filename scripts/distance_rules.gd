class_name DistanceRules
extends RefCounted

enum Mode { FIVE_PER_CELL, ALTERNATING, STRAIGHT }

static func closest_cells(from_space: Rect2i, to_space: Rect2i) -> Array[Vector2i]:
	var from_last := from_space.end - Vector2i.ONE
	var to_last := to_space.end - Vector2i.ONE
	var from_cell := Vector2i(
		clampi(to_space.position.x, from_space.position.x, from_last.x),
		clampi(to_space.position.y, from_space.position.y, from_last.y)
	)
	var to_cell := Vector2i(
		clampi(from_cell.x, to_space.position.x, to_last.x),
		clampi(from_cell.y, to_space.position.y, to_last.y)
	)
	return [from_cell, to_cell]

static func feet(from_cell: Vector2i, to_cell: Vector2i, mode: int) -> float:
	var delta := (to_cell - from_cell).abs()
	var diagonal := mini(delta.x, delta.y)
	var longest := maxi(delta.x, delta.y)
	match mode:
		Mode.ALTERNATING:
			return float(longest + floori(float(diagonal) / 2.0)) * 5.0
		Mode.STRAIGHT:
			return Vector2(delta).length() * 5.0
	return float(longest) * 5.0

static func route_feet(points: Array[Vector2i], mode: int) -> float:
	var total := 0.0
	var diagonals := 0
	var grid_steps := 0
	for index in range(1, points.size()):
		var delta := (points[index] - points[index - 1]).abs()
		if mode == Mode.ALTERNATING:
			diagonals += mini(delta.x, delta.y)
			grid_steps += maxi(delta.x, delta.y)
		else:
			total += feet(points[index - 1], points[index], mode)
	if mode == Mode.ALTERNATING:
		# Adding a waypoint must not reset the alternating diagonal count.
		return float(grid_steps + floori(float(diagonals) / 2.0)) * 5.0
	return total

static func segment_feet(points: Array[Vector2i], index: int, mode: int) -> float:
	if index <= 0 or index >= points.size():
		return 0.0
	if mode != Mode.ALTERNATING:
		return feet(points[index - 1], points[index], mode)
	var previous_diagonals := 0
	for previous in range(1, index):
		var delta := (points[previous] - points[previous - 1]).abs()
		previous_diagonals += mini(delta.x, delta.y)
	var segment := (points[index] - points[index - 1]).abs()
	var diagonals := mini(segment.x, segment.y)
	var extra := floori(float(previous_diagonals + diagonals) / 2.0) - floori(float(previous_diagonals) / 2.0)
	return float(maxi(segment.x, segment.y) + extra) * 5.0
