extends "res://ui/components/token_thumbnail.gd"

var yaw := 0.6
var pitch := 0.45
var distance := 3.2
var target := Vector3.ZERO
var footprint: Node3D
var size_label: Label3D
var preview_count := 1

func _ready() -> void:
	super._ready()
	var ground := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(80, 80)
	ground.mesh = mesh
	var surface := StandardMaterial3D.new()
	surface.albedo_color = Color("d4dce5")
	surface.roughness = 1.0
	ground.material_override = surface
	model_root.add_child(ground)
	footprint = Node3D.new()
	model_root.add_child(footprint)
	size_label = Label3D.new()
	size_label.font = preload("res://ui/theme/preview_size_font.tres")
	size_label.font_size = 40
	size_label.modulate = Color("334155")
	size_label.outline_modulate = Color("f8fafc")
	size_label.outline_size = 2
	size_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	model_root.add_child(size_label)

func configure(data: Dictionary) -> void:
	super.configure(data)
	var count := maxi(1, int(data.get("size", 1)))
	preview_count = count
	_build_footprint(count)
	distance = 3.2 * count
	target = Vector3(0, count * 0.4, 0)
	_position_camera()

func rotate_view(relative: Vector2) -> void:
	yaw -= relative.x * 0.008
	pitch = clampf(pitch + relative.y * 0.006, 0.1, 1.35)
	_position_camera()

func _position_camera() -> void:
	camera.position = target + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	camera.look_at(target)
	var side := camera.global_basis.x
	side.y = 0
	side = side.normalized()
	var half := preview_count / 2.0
	var edge := half * (absf(side.x) + absf(side.z))
	size_label.position = side * (edge + preview_count * 0.3) + Vector3.UP * (preview_count * 0.08)
	_refresh()

func _build_footprint(count: int) -> void:
	for child in footprint.get_children():
		footprint.remove_child(child)
		child.queue_free()
	var half := count / 2.0
	var surface := StandardMaterial3D.new()
	surface.albedo_color = Color("64748b")
	surface.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for index in range(count + 1):
		var thickness := count * (0.018 if index == 0 or index == count else 0.012)
		for axis in range(2):
			var line := MeshInstance3D.new()
			var mesh := BoxMesh.new()
			mesh.size = Vector3(count + thickness, 0.008, thickness) if axis == 0 else Vector3(thickness, 0.008, count + thickness)
			line.mesh = mesh
			line.material_override = surface
			line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			line.position = Vector3(0, 0.01, index - half) if axis == 0 else Vector3(index - half, 0.01, 0)
			footprint.add_child(line)
	size_label.text = "%d×%d" % [count, count]
	size_label.pixel_size = 0.0025 * count
