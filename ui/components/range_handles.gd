extends Node3D
## Shared constant-screen-size range handles and fixed-axis drag projection.
var camera: Camera3D
var viewport_height := 720.0
var definitions: Array[Dictionary] = []
var nodes: Dictionary = {}
var invalid := false
var use_screen_axis := false
var hover_key := ""
var drag_key := ""
var drag_origin := Vector3.ZERO
var drag_axis := Vector3.RIGHT
var drag_start := 0.0
var fallback_start := Vector2.ZERO
var fallback_direction := Vector2.ZERO

func configure(items: Array[Dictionary]) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	definitions = items
	nodes.clear()
	for item in items:
		var node := MeshInstance3D.new()
		var mesh: PrimitiveMesh
		if item.get("corner",false):
			var box := BoxMesh.new()
			box.size = Vector3(1.4,1.4,1.4)
			mesh = box
		else:
			var sphere := SphereMesh.new()
			sphere.radius = 1
			sphere.height = 2
			sphere.radial_segments = 12
			sphere.rings = 6
			mesh = sphere
		node.mesh = mesh
		node.position = item["position"]
		var face := StandardMaterial3D.new()
		face.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		face.no_depth_test = true
		face.albedo_color = Color("f7fbff") if item.get("corner",false) else Color("2563a6")
		node.material_override = face
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		nodes[item["key"]] = node
	_update_size()

func _process(_delta: float) -> void:
	_update_size()

func _update_size() -> void:
	if camera==null: return
	for key: String in nodes:
		var node: MeshInstance3D = nodes[key]
		var per_pixel := camera.global_position.distance_to(to_global(node.position))*2.0*tan(deg_to_rad(camera.fov)*0.5)/maxf(1,viewport_height)
		node.scale = Vector3.ONE*maxf(0.025,per_pixel*8)
		var highlight := key==hover_key or key==drag_key
		node.material_override.albedo_color = Color("57b8ee") if highlight else (Color("f7fbff") if _item(key).get("corner",false) else (Color("d73535") if invalid else Color("2563a6")))

func _item(key: String) -> Dictionary:
	for item in definitions:
		if item["key"]==key: return item
	return {}

func hit(screen: Vector2) -> String:
	var best := Mobile.hit_radius() if Mobile.enabled else 15.0
	var found := ""
	if camera!=null and visible:
		for item in definitions:
			var point: Vector3 = to_global(item["position"])
			if not nodes[item["key"]].is_visible_in_tree() or not camera.is_position_in_frustum(point): continue
			var distance := camera.unproject_position(point).distance_to(screen)
			if distance<best:
				best = distance
				found = item["key"]
	hover_key = found
	return found

func begin_axis(key: String, screen: Vector2) -> void:
	drag_key = key
	var item := _item(key)
	drag_origin = to_global(item["position"])
	drag_axis = item.get("axis",Vector3.RIGHT)
	use_screen_axis = 1.0-pow(drag_axis.dot(camera.project_ray_normal(screen)),2)<0.08
	drag_start = _axis_scalar(screen)
	fallback_start = screen
	fallback_direction = camera.unproject_position(drag_origin+drag_axis)-camera.unproject_position(drag_origin)

func axis_feet(screen: Vector2) -> float:
	if use_screen_axis:
		return (screen-fallback_start).dot(fallback_direction)/maxf(1,fallback_direction.length_squared())*5.0
	return (_axis_scalar(screen)-drag_start)*5.0

func _axis_scalar(screen: Vector2) -> float:
	var origin := camera.project_ray_origin(screen)
	var ray := camera.project_ray_normal(screen)
	var dot := drag_axis.dot(ray)
	var offset := origin-drag_origin
	return (drag_axis.dot(offset)-dot*ray.dot(offset))/maxf(0.0001,1.0-dot*dot)

func end_drag() -> void:
	drag_key = ""
