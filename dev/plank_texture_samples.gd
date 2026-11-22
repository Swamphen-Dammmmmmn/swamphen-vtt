extends Node3D

const Materials = preload("res://scripts/scenery/wall_material.gd")
const Bank = preload("res://scripts/scenery/plank_texture_bank.gd")
const BarkBank = preload("res://scripts/scenery/bark_texture_bank.gd")
const SampleLabel = preload("res://ui/components/features/editor/wall_sample_label.gd")
const FlyCamera = preload("res://dev/terrain_fly_camera.gd")
@export_dir var output_directory := "res://artifacts/plank-textures-64-2026-10-24/"
@export var bark_samples := false
@export_enum("直纹", "山形纹", "结疤纹", "混合纹") var sample_family := 0
const TITLES := ["直纹", "山形纹", "结疤纹", "混合纹"]
const BARK_TITLES := BarkBank.FAMILY_TITLES

func _ready() -> void:
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("c4c7cc")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color.WHITE
	world.environment.ambient_light_energy = 0.6
	world.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-30,-25,0)
	light.light_energy = 1.2
	add_child(light)
	# An opaque display backing keeps captions readable independently of autoload sky.
	var backing := MeshInstance3D.new()
	var backing_mesh := QuadMesh.new()
	backing_mesh.size = Vector2(20,12)
	var backing_material := StandardMaterial3D.new()
	backing_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	backing_material.albedo_color = Color("c4c7cc")
	backing_mesh.material = backing_material
	backing.mesh = backing_mesh
	backing.position = Vector3(0,1.85,-0.1)
	add_child(backing)
	for order in int(Bank.COLORS.get_layers()/4):
		var index := order*4+sample_family
		var material := Materials.create("logs_bark" if bark_samples else "planks_horizontal",BarkBank.REFERENCE_COLOR if bark_samples else Bank.REFERENCE_COLOR) as ShaderMaterial
		material.set_shader_parameter("showcase_layer",index)
		var rectangle := QuadMesh.new()
		rectangle.size = Vector2(2.5,0.5)
		rectangle.material = material
		var sample := MeshInstance3D.new()
		sample.mesh = rectangle
		sample.position = Vector3((order%4-1.5)*2.8,3.1-floori(float(order)/4)*0.85,0)
		add_child(sample)
		var label := SampleLabel.new()
		label.text = "%02d  %s" % [index+1,(BARK_TITLES if bark_samples else TITLES)[index%4]]
		label.position = sample.position+Vector3(0,0.4,0.01)
		label.scale = Vector3.ONE*0.4
		add_child(label)
	var camera := FlyCamera.new()
	camera.environment = world.environment
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 7
	camera.current = true
	camera.position = Vector3(0,1.85,12)
	add_child(camera)
	camera.look_at(Vector3(0,1.85,0))
	camera.set_enabled(true)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var code := get_viewport().get_texture().get_image().save_png(output_directory.path_join("samples_family_%d.png"%sample_family))
	print("PLANK_SAMPLES_READY layers=",Bank.COLORS.get_layers()," family=",sample_family," displayed=",Bank.COLORS.get_layers()/4," capture=",code)
