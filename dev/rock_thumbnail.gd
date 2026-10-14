extends SubViewportContainer

var viewport: SubViewport

func configure(mesh: ArrayMesh, material: Material) -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport = SubViewport.new()
	viewport.size = Vector2i(256, 176)
	viewport.own_world_3d = true
	viewport.handle_input_locally = false
	viewport.gui_disable_input = true
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	viewport.msaa_3d = Viewport.MSAA_2X
	add_child(viewport)
	var root := Node3D.new()
	viewport.add_child(root)
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("edf2f5")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("bdc9d6")
	environment.ambient_light_energy = 0.65
	world.environment = environment
	root.add_child(world)
	var light := DirectionalLight3D.new()
	light.light_color = Color("fff4e5")
	light.light_energy = 1.0
	light.rotation_degrees = Vector3(-40, 10, 0)
	root.add_child(light)
	var model := MeshInstance3D.new()
	model.mesh = mesh
	model.material_override = material
	root.add_child(model)
	var camera := Camera3D.new()
	camera.current = true
	camera.fov = 35
	camera.near = 0.02
	root.add_child(camera)
	var bounds := mesh.get_aabb()
	var target := bounds.get_center()
	var radius := maxf(0.5, bounds.size.length())
	camera.position = target + Vector3(1, 0.65, 1.2).normalized() * radius * 1.35
	camera.look_at(target)
	resized.connect(_refresh)
	visibility_changed.connect(_refresh)
	_refresh.call_deferred()

func _refresh() -> void:
	if is_instance_valid(viewport):
		viewport.render_target_update_mode = SubViewport.UPDATE_ONCE if is_visible_in_tree() else SubViewport.UPDATE_DISABLED

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_inside_tree():
		_refresh.call_deferred()
