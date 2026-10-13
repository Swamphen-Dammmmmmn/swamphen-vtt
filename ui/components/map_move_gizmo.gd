extends "res://ui/components/token_transform_gizmo.gd"

func configure_platform(center: Vector3, offset: Vector3) -> void:
	pivot = center / 5.0
	position = pivot
	components = {"base":{"offset_ft":[offset.x,offset.y,offset.z]}}
	component_name = "base"
	visible = mode == "position"
	refresh_scale()

func refresh_scale() -> void:
	if camera == null: return
	radius = maxf(0.05,camera.global_position.distance_to(pivot) * tan(deg_to_rad(camera.fov/2.0)) * 2.0 * 82.0 / maxf(1,camera.get_viewport().get_visible_rect().size.y))
	scale = Vector3.ONE * radius

func begin_drag(mouse: Vector2) -> bool:
	var axis := pick(mouse)
	if axis < 0: return false
	snap_interval = 1.0 if axis == 1 else 5.0
	return super.begin_drag(mouse)

func _refresh() -> void:
	super._refresh()
	# The map contains animated water and grass; gizmo changes must not pause it.
	if camera != null:
		var viewport := camera.get_viewport() as SubViewport
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
