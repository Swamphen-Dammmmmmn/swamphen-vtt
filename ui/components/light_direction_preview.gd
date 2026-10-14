extends SubViewportContainer

const Hemisphere = preload("res://ui/components/light_hemisphere.gd")
const OrbitCamera = preload("res://scripts/orbit_camera.gd")
signal direction_changed(azimuth: float, altitude: float)
var viewport: SubViewport
var camera: Camera3D
var hemisphere: Node3D
var turning := false
var yaw := 0.65
var pitch := 0.5

func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size.y = 200
	tooltip_text = "左键调整太阳方向；右键拖动旋转观察。"
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.gui_disable_input = true
	viewport.handle_input_locally = false
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("edf2f8")
	world.add_child(environment)
	var floor := MeshInstance3D.new()
	var disk := CylinderMesh.new()
	disk.top_radius = 8
	disk.bottom_radius = 8
	disk.height = 0.05
	floor.mesh = disk
	floor.position.y = -0.03
	var surface := StandardMaterial3D.new()
	surface.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	surface.albedo_color = Color("dce5ed")
	floor.material_override = surface
	world.add_child(floor)
	camera = Camera3D.new()
	camera.current = true
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 21
	world.add_child(camera)
	_turn(Vector2.ZERO)
	hemisphere = Hemisphere.new()
	world.add_child(hemisphere)
	hemisphere.camera = camera
	hemisphere.configure(Vector3.ZERO,8.0,10.2,39.704)
	hemisphere.cage.material_override.albedo_color = Color("71859e")
	hemisphere.show()
	hemisphere.direction_changed.connect(func(azimuth: float, altitude: float):
		direction_changed.emit(azimuth,altitude)
		_refresh()
	)
	visibility_changed.connect(_refresh)
	resized.connect(_refresh)
	_refresh.call_deferred()

func sync(azimuth: float, altitude: float) -> void:
	hemisphere.sync(azimuth,altitude)
	_refresh()

func _turn(relative: Vector2) -> void:
	yaw -= relative.x*0.008
	pitch = OrbitCamera.clamp_pitch(pitch+relative.y*0.008)
	var at := Vector3(0,3,0)
	camera.position = at+Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))*24
	camera.look_at(at)
	if is_instance_valid(hemisphere): hemisphere.sync(hemisphere.azimuth,hemisphere.altitude)
	_refresh()

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index==MOUSE_BUTTON_LEFT:
			hemisphere.start(event.position)
			accept_event()
		elif event.button_index==MOUSE_BUTTON_RIGHT:
			turning = true
			accept_event()

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		cancel()
		return
	if event is InputEventMouseButton and not event.pressed:
		if event.button_index==MOUSE_BUTTON_LEFT and hemisphere.dragging:
			hemisphere.dragging = false
			get_viewport().set_input_as_handled()
		elif event.button_index==MOUSE_BUTTON_RIGHT and turning:
			turning = false
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion:
		if turning:
			_turn(event.relative)
			get_viewport().set_input_as_handled()
		elif hemisphere.dragging:
			hemisphere.drag(event.position-get_global_rect().position)
			get_viewport().set_input_as_handled()

func interacting() -> bool:
	return turning or (is_instance_valid(hemisphere) and hemisphere.dragging)

func cancel() -> void:
	turning = false
	if is_instance_valid(hemisphere): hemisphere.dragging = false

func _notification(what: int) -> void:
	if what==NOTIFICATION_WM_WINDOW_FOCUS_OUT: cancel()

func _refresh() -> void:
	if is_instance_valid(viewport): viewport.render_target_update_mode = SubViewport.UPDATE_ONCE if is_visible_in_tree() else SubViewport.UPDATE_DISABLED
