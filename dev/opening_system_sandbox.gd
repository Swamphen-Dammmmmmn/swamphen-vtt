extends Node3D

const Wall = preload("res://scripts/scenery/wall_parameters.gd")
const P = preload("res://scripts/scenery/opening_parameters.gd")
const Assembly = preload("res://scripts/scenery/wall_assembly.gd")
const Joiner = preload("res://scripts/scenery/wall_joiner.gd")
const FlyCamera = preload("res://dev/terrain_fly_camera.gd")
const SampleLabel = preload("res://ui/components/features/editor/wall_sample_label.gd")

@export_enum("全景","门近景","窗近景","背面与厚墙","多洞与转角","窗正面细节","开窗斜视细节","反向铰链细节","门五金对比") var view_mode := 0
@export var capture_initial := false
@export var enable_navigation := true
@export_dir var capture_directory := "res://artifacts/opening-system-2026-10-25/"
var _camera: Camera3D
var _ready_for_input := false

func _ready() -> void:
	_environment()
	_ground()
	_camera=FlyCamera.new()
	_camera.current=true
	_camera.near=0.02
	_camera.far=120
	_camera.fov=42
	add_child(_camera)
	get_window().focus_exited.connect(_camera.release_mouse)
	for i in Wall.SURFACES.size():
		var wall := Wall.defaults(0,Wall.SURFACES[i])
		var door := P.defaults("wood_door")
		door.seed=i*9
		door.angle=65.0 if i%2 else 0.0
		var window := P.defaults("wood_window")
		window.seed=i*9+3
		window.angle=50.0 if i%2 else 0.0
		window.hinge="right" if i%2 else "left"
		var x := (i-(Wall.SURFACES.size()-1)*0.5)*1.75
		if not await _sample(wall,[door],Vector3(x,0,1.8),"%s · 木门%s"%[Wall.SURFACE_TITLES[i]," 65°" if i%2 else ""]): return
		if not await _sample(wall,[window],Vector3(x,0,-1.6),"%s · 木窗%s"%[Wall.SURFACE_TITLES[i]," 50°" if i%2 else ""]): return
	var thick := Wall.defaults(0,"logs_bark")
	thick.thickness=1.5
	var back_door := P.defaults("wood_door")
	back_door.mounting="back"
	back_door.hinge="right"
	back_door.swing="back"
	back_door.angle=75.0
	if not await _sample(thick,[back_door],Vector3(-3.5,0,-5.4),"厚1.5尺 · 后侧安装/向后开"): return
	var empty := P.defaults("empty_window")
	if not await _sample(Wall.defaults(0,"planks_horizontal"),[empty],Vector3(-1.75,0,-5.4),"纯窗洞 · 关闭附加件"): return
	var unglazed := P.defaults("wood_window")
	unglazed.glass=false
	unglazed.mullions=false
	if not await _sample(Wall.defaults(0,"planks_vertical"),[unglazed],Vector3(0,0,-5.4),"无玻璃 / 无分格"): return
	await _multi_and_corner()
	if view_mode>=5:
		# Detail views only: a back-swinging right-hinged window seen from its hinge face.
		var reversed := P.defaults("wood_window")
		reversed.hinge="right"
		reversed.swing="back"
		reversed.angle=45.0
		reversed.seed=41
		if not await _sample(Wall.defaults(0,"planks_horizontal"),[reversed],Vector3(0,0,-9.0),"向后开 · 右铰链 45°"): return
	var positions := [Vector3(8,8,12),Vector3(0.5,2.8,9.2),Vector3(0.5,2.9,5.9),Vector3(-1.5,2.7,-10.8),Vector3(7,4,-0.3),
		Vector3(0.5,1.0,-0.45),Vector3(-0.55,1.25,-0.85),Vector3(1.25,1.2,-10.05),Vector3(0.75,0.85,3.05)]
	var targets := [Vector3(0.5,0.8,-1.4),Vector3(0.5,0.9,1.8),Vector3(0.5,1,-1.6),Vector3(-2,0.9,-5.4),Vector3(4,0.8,-5),
		Vector3(0.5,1.0,-1.6),Vector3(-1.05,1.0,-1.55),Vector3(0.65,1.0,-9.05),Vector3(0.45,0.75,1.8)]
	_camera.position=positions[view_mode]
	_camera.look_at(targets[view_mode])
	_camera.yaw=_camera.rotation.y
	_camera.pitch=_camera.rotation.x
	_camera.base_speed=3
	_camera.set_enabled(enable_navigation)
	_ready_for_input=enable_navigation
	print("OPENING_SANDBOX_READY presets=wood_door,wood_window materials=",Wall.SURFACES.size()," additional_examples=5")
	await get_tree().create_timer(0.3).timeout
	DisplayServer.window_set_title("门窗系统 · 木门 / 四格木窗 · 右键转向 WASD移动 QE升降")
	if capture_initial:
		await get_tree().create_timer(1.5).timeout
		await RenderingServer.frame_post_draw
		var file: String = ["overview.png","doors.png","windows.png","back.png","multi_corner.png",
			"window_front_detail.png","window_open_oblique.png","window_reversed_hinge.png","door_hardware.png"][view_mode]
		print("OPENING_CAPTURE result=",get_viewport().get_texture().get_image().save_png(capture_directory.path_join(file)))

func _sample(wall: Dictionary, specs: Array, at: Vector3, title: String) -> bool:
	var placement := Transform3D(Basis.IDENTITY,at)
	var result := await Assembly.build(wall,specs,Vector2.ZERO,placement)
	if not result.ok:
		push_error(title+": "+result.message)
		return false
	var instance := Assembly.instantiate(result)
	instance.transform=placement
	instance.visible=_visible_row(at.z)
	add_child(instance)
	_label(title,at+Vector3(wall.length*Wall.FEET*0.5,wall.height*Wall.FEET+0.23,0),instance.visible)
	return true

func _multi_and_corner() -> void:
	var wall := Wall.defaults(0,"planks_horizontal")
	wall.length=15.0
	var door := P.defaults("wood_door")
	door.offset=-4.0
	door.angle=35.0
	var window := P.defaults("wood_window")
	window.offset=3.5
	var position := Vector3(2,0,-5.4)
	var turn := Wall.defaults(0,"planks_horizontal")
	var entries: Array[Dictionary] = [
		{"parameters":wall,"openings":[door,window],"transform":Transform3D(Basis.IDENTITY,position)},
		{"parameters":turn,"openings":[],"transform":Transform3D(Basis(Vector3.UP,-PI*0.5),position+Vector3(3,0,0))}]
	var joined := await Joiner.build(entries)
	if not joined.ok:
		push_error(joined.message)
		return
	for i in entries.size():
		var instance := Assembly.instantiate(joined.parts[i])
		instance.transform=entries[i].transform
		instance.visible=view_mode in [0,4]
		add_child(instance)
	_label("同墙多洞 / 转角",position+Vector3(1.5,2.23,0),view_mode in [0,4])

func _visible_row(z: float) -> bool:
	if view_mode==0 or view_mode>=5: return true
	if view_mode==1: return z>0
	if view_mode==2: return is_equal_approx(z,-1.6)
	return view_mode==3 and is_equal_approx(z,-5.4)

func _label(title: String, at: Vector3, show := true) -> void:
	var label := SampleLabel.new()
	label.compact=true
	label.text=title
	label.position=at
	label.visible=show
	add_child(label)

func _environment() -> void:
	var world := WorldEnvironment.new()
	world.environment=Environment.new()
	world.environment.background_mode=Environment.BG_COLOR
	world.environment.background_color=Color("c4c7cc")
	world.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color=Color.WHITE
	world.environment.ambient_light_energy=0.65
	world.environment.tonemap_mode=Environment.TONE_MAPPER_FILMIC
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-45,-30,0)
	sun.light_energy=1.15
	sun.shadow_enabled=true
	add_child(sun)

func _ground() -> void:
	var mesh := BoxMesh.new()
	mesh.size=Vector3(20,0.2,18)
	var floor_mesh := MeshInstance3D.new()
	floor_mesh.mesh=mesh
	floor_mesh.position=Vector3(0,-0.1,-1.5)
	var material := StandardMaterial3D.new()
	material.albedo_color=Color("aeb2b8")
	material.roughness=1
	floor_mesh.material_override=material
	add_child(floor_mesh)

func _input(event: InputEvent) -> void:
	if not _ready_for_input: return
	if event is InputEventMouseMotion and _camera.turning:
		_camera.turn(event.relative)
		get_viewport().set_input_as_handled()
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_RIGHT and not event.pressed:
		_camera.release_mouse()

func _unhandled_input(event: InputEvent) -> void:
	if not _ready_for_input or not DisplayServer.window_is_focused(): return
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_RIGHT and event.pressed:
		_camera.begin_turn()
		get_viewport().set_input_as_handled()
