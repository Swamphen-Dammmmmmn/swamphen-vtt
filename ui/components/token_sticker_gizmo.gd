extends "res://ui/components/token_transform_gizmo.gd"

const Sticker = preload("res://scripts/token_sticker.gd")
var face_basis := Basis.IDENTITY
var settings: Dictionary = {}
var board_size := Vector2.ONE
var editable := false

func configure_sticker(data: Dictionary, face_name: String, shown: bool) -> void:
	components = data
	component_name = "standee"
	var component: Dictionary = data["standee"]
	var specification := Sticker.migrate(component.get("sticker", Sticker.defaults()))
	settings = Sticker.face(specification, face_name)
	editable = shown and not settings["image_id"].is_empty() and not (face_name == "back" and specification["back_shared"])
	designer_visible = editable
	var transform := ComponentGeometry._transform(component, "standee", data)
	board_size = Vector2(float(component["width_ft"]), float(component["height_ft"])) / 5.0
	var back := face_name == "back"
	face_basis = transform.basis * Basis(Vector3.UP, PI if back else 0.0)
	var surface_center := transform * Vector3(0, 0, ((0.0 if component.get("presentation", "solid") == "image" and not component.has("contour") else float(component["thickness_ft"]) / 10.0) + 0.001) * (-1.0 if back else 1.0))
	pivot = surface_center + face_basis * Vector3(float(settings["offset"][0]) * board_size.x, float(settings["offset"][1]) * board_size.y, 0)
	position = pivot
	visible = not mode.is_empty() and editable
	refresh_scale()

func _visible_axes() -> Array:
	return [2] if mode == "rotation" else [0, 1]

func _axis(index: int) -> Vector3:
	return face_basis * AXES[index]

func _ring_point(axis: int, angle: float) -> Vector3:
	return face_basis * super._ring_point(axis, angle)

func _refresh() -> void:
	super._refresh()
	if mode == "rotation":
		for node in get_children(): node.quaternion = Quaternion(Vector3.UP, _axis(2))

func _rotation_angle(mouse: Vector2, _axis_index: int) -> Variant:
	var point: Variant = Plane(_axis(2), drag_pivot).intersects_ray(camera.project_ray_origin(mouse), camera.project_ray_normal(mouse))
	if point == null: return null
	var offset: Vector3 = point - drag_pivot
	if offset.length_squared() < 0.000001: return null
	return atan2(offset.dot(_axis(1)), offset.dot(_axis(0)))

func begin_drag(mouse: Vector2) -> bool:
	if not is_finite(snap_interval) or snap_interval <= 0 or not editable: return false
	var axis := pick(mouse)
	if axis < 0: return false
	drag_pivot = pivot
	if mode == "position":
		var point: Variant = _drag_point(mouse, _axis(axis))
		if point == null: return false
		drag_origin = point
		drag_values = [float(settings["offset"][0]) * 100, float(settings["offset"][1]) * 100]
	else:
		var angle: Variant = _rotation_angle(mouse, axis)
		if angle == null: return false
		last_angle = angle
		total_angle = 0
		drag_values = [settings["rotation_deg"]]
	dragged = axis
	hovered = axis
	_refresh()
	return true

func drag(mouse: Vector2) -> void:
	if dragged < 0: return
	if mode == "position":
		var point: Variant = _drag_point(mouse, _axis(dragged))
		if point == null: return
		var offset: Vector3 = point - drag_origin
		var values := drag_values.duplicate()
		var dimension := board_size.x if dragged == 0 else board_size.y
		var delta := snappedf(offset.dot(_axis(dragged)) / dimension * 100.0, snap_interval)
		values[dragged] = clampf(float(drag_values[dragged]) + delta, -1000, 1000)
		values_changed.emit(mode, values)
	else:
		var angle: Variant = _rotation_angle(mouse, dragged)
		if angle == null: return
		total_angle += wrapf(float(angle) - last_angle, -PI, PI)
		last_angle = angle
		# Shader uses image coordinates with downward Y; clockwise angle is positive.
		values_changed.emit(mode, [float(drag_values[0]) - snappedf(rad_to_deg(total_angle), snap_interval)])
