extends SubViewportContainer

const Profile = preload("res://scripts/environment_profile.gd")
const Weather = preload("res://scripts/map_weather.gd")
var data: Dictionary
var viewport: SubViewport
var environment: Node3D
var signature := ""
var dirty := true
var queued := false
var revision := 0
static var jobs: Array[WeakRef] = []
static var processing := false

func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size.y = 64
	viewport = SubViewport.new()
	viewport.size = Vector2i(96,64)
	viewport.own_world_3d = true
	viewport.gui_disable_input = true
	viewport.handle_input_locally = false
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	environment = Profile.create(false)
	world.add_child(environment)
	environment.get_node("WorldEnvironment").environment.sky.radiance_size = Sky.RADIANCE_SIZE_32
	var camera := Camera3D.new()
	camera.current = true
	camera.position = Vector3(6,4,7)
	camera.fov = 45
	world.add_child(camera)
	camera.look_at(Vector3(0,0.8,0))
	for item in [[Vector3(10,0.3,10),Vector3(0,-0.15,0),Color("8bb884")],[Vector3(1,2.5,1),Vector3(0,1.25,0),Color("ddd8cc")],[Vector3(1.4,0.7,1.4),Vector3(-2,0.35,-1),Color("b8b5ad")]]:
		var actor := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = item[0]
		actor.mesh = box
		actor.position = item[1]
		var material := StandardMaterial3D.new()
		material.albedo_color = item[2]
		actor.material_override = material
		world.add_child(actor)
	visibility_changed.connect(_refresh)
	resized.connect(func(): dirty = true; revision += 1; _refresh())
	configure(data)

func configure(values: Dictionary) -> void:
	var next := _signature(values)
	if next==signature: return
	signature = next
	data = values.duplicate(true)
	dirty = true
	revision += 1
	if not is_instance_valid(environment): return
	Weather.apply_scene(environment,data)
	Graphics.apply_environment(environment.get_node("WorldEnvironment").environment)
	_refresh.call_deferred()

func _refresh() -> void:
	if not is_instance_valid(viewport): return
	if not is_visible_in_tree():
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	if _signature(data)!=signature:
		configure(data)
		return
	if not dirty:
		viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	if queued: return
	queued = true
	jobs.append(weakref(self))
	if not processing:
		processing = true
		_drain_jobs()

static func _signature(values: Dictionary) -> String:
	var relevant := values.duplicate()
	relevant.erase("wind")
	return JSON.stringify([relevant,Graphics.values]).sha256_text()

static func _drain_jobs() -> void:
	var tree: SceneTree = Engine.get_main_loop()
	while not jobs.is_empty():
		await tree.process_frame
		var preview = jobs.pop_front().get_ref()
		if not is_instance_valid(preview): continue
		preview.queued = false
		if not preview.is_visible_in_tree() or not preview.dirty: continue
		var current_revision: int = preview.revision
		preview.viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		if is_instance_valid(preview):
			preview.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
			if preview.revision==current_revision: preview.dirty = false
	processing = false
