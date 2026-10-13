extends RefCounted

var points: Array[Vector2i] = []
var editing_index := -1
var original_cell := Vector2i.ZERO
var surface_context := ""
var point_surfaces: Array[String] = []
var original_surface := ""

func begin(origin: Vector2i) -> void:
	reset()
	points.append(origin)
	point_surfaces.append(surface_context)

func reset() -> void:
	points.clear()
	point_surfaces.clear()
	editing_index = -1

func add_point(cell: Vector2i) -> void:
	if not points.is_empty() and (points[-1] != cell or point_surfaces[-1]!=surface_context):
		points.append(cell)
		point_surfaces.append(surface_context)

func start_edit(index: int) -> void:
	if index > 0 and index < points.size():
		editing_index = index
		original_cell = points[index]
		original_surface = point_surfaces[index]

func update_edit(cell: Vector2i) -> void:
	if editing_index > 0:
		points[editing_index] = cell
		point_surfaces[editing_index] = surface_context

func finish_edit() -> void:
	editing_index = -1

func cancel_edit() -> void:
	if editing_index > 0:
		points[editing_index] = original_cell
		point_surfaces[editing_index] = original_surface
		editing_index = -1

func delete_point(index: int) -> void:
	if editing_index < 0 and index > 0 and index < points.size():
		points.remove_at(index)
		point_surfaces.remove_at(index)

func undo_point() -> void:
	if editing_index < 0 and points.size() > 1:
		points.remove_at(points.size() - 1)
		point_surfaces.pop_back()
