extends Node3D

signal values_changed(mode: String, values: Array)
const ComponentGeometry = preload("res://scripts/token_components.gd")
const AXES := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
const COLORS := [Color("de4c46"), Color("39a765"), Color("347ee7")]
var camera: Camera3D
var mode := ""
var components: Dictionary = {}
var component_name := "base"
var designer_visible := true
var pivot := Vector3.ZERO
var radius := 1.0
var hovered := -1
var dragged := -1
var drag_origin := Vector3.ZERO
var drag_values: Array = []
var drag_basis := Basis.IDENTITY
var last_angle := 0.0
var total_angle := 0.0
var snap_interval := 0.1
var drag_pivot := Vector3.ZERO

func configure(data: Dictionary, active: String, shown := true) -> void:
	designer_visible = shown
	components = data
	component_name = active
	var component: Dictionary = components[active]
	var transform := ComponentGeometry._transform(component, active, components)
	pivot = transform * ComponentGeometry._mesh(component, active).get_aabb().get_center()
	position = pivot
	visible = not mode.is_empty() and designer_visible
	refresh_scale()

func set_mode(next_mode: String) -> void:
	end_drag()
	mode = next_mode
	visible = not mode.is_empty() and not components.is_empty() and designer_visible
	_refresh()

func refresh_scale() -> void:
	if camera == null: return
	radius = maxf(0.05, camera.global_position.distance_to(pivot) * tan(deg_to_rad(camera.fov / 2.0)) * 2.0 * 82.0 / maxf(1, camera.get_viewport().get_visible_rect().size.y))
	scale = Vector3.ONE * radius
	_refresh()

func _material(axis: int) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = COLORS[axis]
	if axis == hovered or axis == dragged: material.albedo_color = material.albedo_color.lightened(0.35)
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	material.render_priority = 10
	return material

func _refresh() -> void:
	if camera != null:
		var viewport := camera.get_viewport() as SubViewport
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	for node in get_children():
		remove_child(node)
		node.queue_free()
	if mode.is_empty(): return
	for axis in _visible_axes():
		var node := MeshInstance3D.new()
		node.set_meta("axis", axis)
		node.material_override = _material(axis)
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if mode == "rotation":
			var mesh := TorusMesh.new()
			mesh.inner_radius = 0.98
			mesh.outer_radius = 1.02
			mesh.rings = 64
			mesh.ring_segments = 8
			node.mesh = mesh
			if axis == 0: node.rotation.z = PI / 2
			elif axis == 2: node.rotation.x = PI / 2
		else:
			var shaft := CylinderMesh.new()
			shaft.top_radius = 0.018
			shaft.bottom_radius = 0.018
			shaft.height = 0.85
			shaft.radial_segments = 12
			node.mesh = shaft
			node.position = _axis(axis) * 0.425
			node.quaternion = Quaternion(Vector3.UP, _axis(axis))
			var arrow := MeshInstance3D.new()
			var cone := CylinderMesh.new()
			cone.top_radius = 0
			cone.bottom_radius = 0.075
			cone.height = 0.2
			cone.radial_segments = 16
			if mode == "scale":
				var tip := BoxMesh.new()
				tip.size = Vector3.ONE * 0.15
				arrow.mesh = tip
			else: arrow.mesh = cone
			arrow.material_override = node.material_override
			arrow.position = _axis(axis) * 0.95
			arrow.rotation = node.rotation
			arrow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(arrow)
		add_child(node)

func _ring_point(axis: int, angle: float) -> Vector3:
	match axis:
		0: return Vector3(0, cos(angle), sin(angle))
		1: return Vector3(cos(angle), 0, sin(angle))
		_: return Vector3(cos(angle), sin(angle), 0)

func pick(mouse: Vector2, _include_locked := false) -> int:
	if not visible or camera.is_position_behind(pivot): return -1
	var best := Mobile.hit_radius() if Mobile.enabled else 11.0
	var picked := -1
	for axis in _visible_axes():
		var segments := 64 if mode == "rotation" else 1
		for segment in range(segments):
			var a: Vector3 = pivot + (_ring_point(axis, TAU * segment / segments) * radius if mode == "rotation" else _axis(axis) * radius * 0.12)
			var b: Vector3 = pivot + (_ring_point(axis, TAU * (segment + 1) / segments) * radius if mode == "rotation" else _axis(axis) * radius * 1.05)
			if camera.is_position_behind(a) or camera.is_position_behind(b): continue
			var distance := Geometry2D.get_closest_point_to_segment(mouse, camera.unproject_position(a), camera.unproject_position(b)).distance_to(mouse)
			if distance < best:
				best = distance
				picked = axis
	return picked

func hover(mouse: Vector2) -> void:
	var next := pick(mouse)
	if next != hovered:
		hovered = next
		_refresh()

func _plane_point(mouse: Vector2, normal: Vector3) -> Variant:
	return Plane(normal, pivot).intersects_ray(camera.project_ray_origin(mouse), camera.project_ray_normal(mouse))

func _rotation_angle(mouse: Vector2, axis: int) -> Variant:
	var point: Variant = _plane_point(mouse, AXES[axis])
	if point == null: return null
	var offset: Vector3 = point - pivot
	if offset.length_squared() < 0.000001: return null
	match axis:
		0: return atan2(offset.z, offset.y)
		1: return atan2(offset.x, offset.z)
		_: return atan2(offset.y, offset.x)

func _axis(index: int) -> Vector3:
	if mode != "scale": return AXES[index]
	var angles: Array = components[component_name]["rotation_deg"]
	return Basis.from_euler(Vector3(deg_to_rad(fmod(float(angles[0]), 360.0)), deg_to_rad(fmod(float(angles[1]), 360.0)), deg_to_rad(fmod(float(angles[2]), 360.0)))) * AXES[index]

func _drag_point(mouse: Vector2, axis: Vector3) -> Variant:
	var normal: Vector3 = camera.global_basis.z - axis * camera.global_basis.z.dot(axis)
	if normal.length_squared() < 0.000001: return null
	return Plane(normal.normalized(), drag_pivot).intersects_ray(camera.project_ray_origin(mouse), camera.project_ray_normal(mouse))

func begin_drag(mouse: Vector2) -> bool:
	if not is_finite(snap_interval) or snap_interval <= 0: return false
	var axis := pick(mouse)
	if axis < 0: return false
	drag_pivot = pivot
	if mode in ["position", "scale"]:
		var point: Variant = _drag_point(mouse, _axis(axis))
		if point == null: return false
		drag_origin = point
		var component: Dictionary = components[component_name]
		drag_values = component["offset_ft"].duplicate() if mode == "position" else [component["width_ft"], component["thickness_ft"], component["length_ft"]]
	else:
		var angle: Variant = _rotation_angle(mouse, axis)
		if angle == null: return false
		last_angle = angle
		total_angle = 0
		var values: Array = components[component_name]["rotation_deg"]
		drag_values = values.duplicate()
		drag_basis = Basis.from_euler(Vector3(deg_to_rad(fmod(float(values[0]), 360.0)), deg_to_rad(fmod(float(values[1]), 360.0)), deg_to_rad(fmod(float(values[2]), 360.0))))
	dragged = axis
	hovered = axis
	_refresh()
	return true

func drag(mouse: Vector2) -> void:
	if dragged < 0: return
	if mode in ["position", "scale"]:
		var point: Variant = _drag_point(mouse, _axis(dragged))
		if point == null: return
		var offset: Vector3 = point - drag_origin
		var values := drag_values.duplicate()
		var delta := snappedf(offset.dot(_axis(dragged)) * 5.0, snap_interval)
		if mode == "scale":
			var original := float(drag_values[dragged])
			var min_delta := -maxf(0, floor((original - 0.000001) / snap_interval)) * snap_interval
			delta = maxf(delta, min_delta)
		values[dragged] = float(drag_values[dragged]) + delta
		if mode == "scale" and components[component_name]["shape"] == "circle" and dragged in [0, 2]:
			values[0] = values[dragged]
			values[2] = values[dragged]
		values_changed.emit(mode, values)
	else:
		var angle: Variant = _rotation_angle(mouse, dragged)
		if angle == null: return
		total_angle += wrapf(float(angle) - last_angle, -PI, PI)
		last_angle = angle
		var snapped_angle := snappedf(rad_to_deg(total_angle), snap_interval)
		# Quantize the dragged ring angle, not each derived Euler channel.
		if is_zero_approx(snapped_angle):
			values_changed.emit(mode, drag_values.duplicate())
			return
		var euler := (Basis(AXES[dragged], deg_to_rad(snapped_angle)) * drag_basis).get_euler()
		values_changed.emit(mode, [rad_to_deg(euler.x), rad_to_deg(euler.y), rad_to_deg(euler.z)])

func end_drag() -> void:
	dragged = -1
	hovered = -1
	_refresh()

func _visible_axes() -> Array:
	return [0, 1, 2]
