extends Node3D
## Decorative, segmented rectangular blades. Scene units represent five feet.

const BladeShader = preload("res://shaders/grass_blade.gdshader")
const Ground = preload("res://scripts/ground_material.gd")
const CHUNK_SIZE := 4.0
const CELL_SIZE := 0.1
const GEOMETRY_KEYS := ["min_height", "max_height", "width", "density", "seed"]
var material: ShaderMaterial
var blade_mesh: ArrayMesh
var settings: Dictionary = defaults()
var area := Rect2(Vector2(-16, -16), Vector2(16, 32))
var exclusion_center := Vector2(-8, 6)
var exclusion_radius := 0.75
var legend_area := Rect2(Vector2(-16,13.5), Vector2(32,3))
var distribution_mask: Image
var distribution_dirty: Dictionary = {}
var blade_count := 0
# Streaming is opt-in so the accepted material samples retain their existing setup.
var streaming := false
const MAX_RESIDENT_CHUNKS := 192
const CANDIDATE_LOAD_BUDGET := 200000
const BUILDS_PER_FRAME := 2
var resident_chunk_limit := MAX_RESIDENT_CHUNKS
var candidate_load_limit := CANDIDATE_LOAD_BUDGET
var builds_per_frame := BUILDS_PER_FRAME
var resident: Dictionary = {}
var desired: Dictionary = {}
var pending: Array[Vector2i] = []
var stream_elapsed := 0.0
var last_camera_transform := Transform3D()
var camera_seen := false
var density_noise: FastNoiseLite
var height_noise: FastNoiseLite
var detail_height_noise: FastNoiseLite
var wind_elapsed := 0.0
var rebuild_timer: Timer
var wind_ground: ShaderMaterial
signal rebuilt(count: int)

static func defaults() -> Dictionary:
	return {"enabled": true, "color": Color("40b85a"), "min_height": 0.3, "max_height": 1.8,
		"width": 0.18, "density": 3.3, "softness": 0.55, "seed": 470210,
		"wind_direction": 35.0, "wind_strength": 0.8, "gust_strength": 0.6,
		"gust_frequency": 0.18, "wave_width_feet": 30.0, "wave_speed_feet": 8.0,
		"sway_period": 1.0, "sway_amplitude": 0.51, "distant_width": 1.5, "ground_wave_strength": 0.07}

func _ready() -> void:
	material = ShaderMaterial.new()
	material.shader = BladeShader
	blade_mesh = _make_blade()
	rebuild_timer = Timer.new()
	rebuild_timer.one_shot = true
	rebuild_timer.wait_time = 0.22
	add_child(rebuild_timer)
	rebuild_timer.timeout.connect(_rebuild)
	_apply_material()
	_rebuild()

func apply(values: Dictionary) -> void:
	var geometry_changed := false
	for key in GEOMETRY_KEYS:
		if settings[key] != values[key]: geometry_changed = true
	settings = values.duplicate()
	visible = bool(settings["enabled"])
	_apply_material()
	if geometry_changed: rebuild_timer.start()

func update_distribution(mask: Image, dirty_area := Rect2()) -> void:
	distribution_mask = mask
	if streaming and dirty_area.has_area():
		for key: Vector2i in resident:
			var chunk := Rect2(Vector2(key)*CHUNK_SIZE,Vector2.ONE*CHUNK_SIZE)
			if not chunk.intersects(dirty_area): continue
			distribution_dirty[key] = true
			if not pending.has(key): pending.append(key)
		return
	if is_instance_valid(rebuild_timer): rebuild_timer.start()

func bind_distribution(texture: Texture2D, region: Rect2) -> void:
	material.set_shader_parameter("coverage_enabled",true)
	material.set_shader_parameter("coverage_mask",texture)
	material.set_shader_parameter("coverage_origin",region.position)
	material.set_shader_parameter("coverage_size",region.size)

func _apply_material() -> void:
	material.set_shader_parameter("grass_color", settings["color"])
	for key in ["softness", "wind_direction", "wind_strength", "gust_strength", "gust_frequency", "wave_width_feet", "wave_speed_feet", "sway_period", "sway_amplitude", "distant_width"]:
		material.set_shader_parameter(key, settings[key])
	if wind_ground != null: Ground.apply_wind(wind_ground, settings)

func bind_ground(material_to_bind: ShaderMaterial) -> void:
	wind_ground = material_to_bind
	Ground.apply_wind(wind_ground, settings)
	wind_ground.set_shader_parameter("wind_time", wind_elapsed)

func _process(delta: float) -> void:
	wind_elapsed += delta
	if visible: material.set_shader_parameter("wind_time", wind_elapsed)
	if wind_ground != null and visible: wind_ground.set_shader_parameter("wind_time", wind_elapsed)
	if streaming and visible:
		stream_elapsed += delta
		var camera := get_viewport().get_camera_3d()
		if camera != null and (not camera_seen or stream_elapsed >= 0.25):
			stream_elapsed = 0.0
			if not camera_seen or not last_camera_transform.is_equal_approx(camera.global_transform):
				_update_stream(camera)
				last_camera_transform = camera.global_transform
				camera_seen = true
		for index in range(mini(builds_per_frame,pending.size())):
			var key := pending.pop_front() as Vector2i
			if desired.has(key):
				_install_chunk(key,int(desired[key]))
				distribution_dirty.erase(key)

func _make_blade() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for segment in range(4):
		var low := float(segment) / 4.0
		var high := float(segment + 1) / 4.0
		for point in [Vector2(-0.5, low), Vector2(-0.5, high), Vector2(0.5, high),
			Vector2(-0.5, low), Vector2(0.5, high), Vector2(0.5, low)]:
			surface.set_normal(Vector3.BACK)
			surface.set_uv(Vector2(point.x + 0.5, point.y))
			surface.add_vertex(Vector3(point.x, point.y, 0))
	return surface.commit()

func _cell_hash(x: int, z: int, seed_value: int) -> int:
	var value := ((x * 73856093) ^ (z * 19349663) ^ (seed_value * 83492791)) & 0x7fffffff
	return ((value ^ (value >> 13)) * 1274126177) & 0x7fffffff

func _rebuild() -> void:
	for child in get_children():
		if child is MultiMeshInstance3D:
			remove_child(child)
			child.queue_free()
	blade_count = 0
	density_noise = FastNoiseLite.new()
	density_noise.seed = int(settings["seed"])
	density_noise.frequency = 0.38
	density_noise.fractal_octaves = 2
	height_noise = FastNoiseLite.new()
	height_noise.seed = int(settings["seed"]) + 19
	height_noise.frequency = 0.16
	height_noise.fractal_octaves = 2
	detail_height_noise = FastNoiseLite.new()
	detail_height_noise.seed = int(settings["seed"]) + 83
	detail_height_noise.frequency = 1.1
	detail_height_noise.fractal_octaves = 2
	resident.clear()
	distribution_dirty.clear()
	desired.clear()
	pending.clear()
	camera_seen = false
	if streaming:
		rebuilt.emit(blade_count)
		return
	for chunk_z in range(floori(area.position.y/CHUNK_SIZE),ceili(area.end.y/CHUNK_SIZE)):
		for chunk_x in range(floori(area.position.x/CHUNK_SIZE),ceili(area.end.x/CHUNK_SIZE)):
			_install_chunk(Vector2i(chunk_x,chunk_z),0)
	rebuilt.emit(blade_count)

func _generate_chunk(key: Vector2i, level: int) -> MultiMeshInstance3D:
	var chunk_origin := Vector2(key)*CHUNK_SIZE
	var transforms: Array[Transform3D] = []
	var customs: Array[Color] = []
	var rng := RandomNumberGenerator.new()
	var min_height := float(settings["min_height"])/5.0
	var max_height := float(settings["max_height"])/5.0
	var keep_limit := _keep_limit(level)
	for z in range(floori(chunk_origin.y/CELL_SIZE),ceili((chunk_origin.y+CHUNK_SIZE)/CELL_SIZE)):
		for x in range(floori(chunk_origin.x/CELL_SIZE),ceili((chunk_origin.x+CHUNK_SIZE)/CELL_SIZE)):
			rng.seed = _cell_hash(x,z,int(settings["seed"]))
			var point := Vector2(x+0.1+rng.randf()*0.8,z+0.1+rng.randf()*0.8)*CELL_SIZE
			if not area.has_point(point): continue
			if point.distance_to(exclusion_center)<exclusion_radius or legend_area.has_point(point): continue
			var cover := 1.0
			if distribution_mask != null:
				var uv := (point-area.position)/area.size
				cover = distribution_mask.get_pixel(clampi(int(uv.x*distribution_mask.get_width()),0,distribution_mask.get_width()-1),clampi(int(uv.y*distribution_mask.get_height()),0,distribution_mask.get_height()-1)).r
			var patch_density := clampf(0.7+density_noise.get_noise_2d(point.x,point.y)*0.65,0.15,1.0)
			if rng.randf()>float(settings["density"])/4.0*patch_density*cover: continue
			var regional_height := clampf(0.5+height_noise.get_noise_2d(point.x,point.y)*0.7,0,1)
			var detail_height := clampf(0.5+detail_height_noise.get_noise_2d(point.x,point.y)*0.7,0,1)
			var height_mix := rng.randf()*0.8+regional_height*0.12+detail_height*0.08
			var height := lerpf(min_height,max_height,height_mix)
			var width := float(settings["width"])/5.0*rng.randf_range(0.75,1.25)
			var basis := Basis(Vector3.UP,rng.randf()*TAU)*Basis.from_scale(Vector3(width,height,1))
			var custom := Color(rng.randf(),rng.randf(),rng.randf_range(0.8,1.2),rng.randf_range(0.05,0.95))
			# Remove only blades already collapsed by the existing distance shader.
			if custom.a>keep_limit: continue
			transforms.append(Transform3D(basis,Vector3(point.x-chunk_origin.x,0,point.y-chunk_origin.y)))
			customs.append(custom)
	if transforms.is_empty(): return null
	var multimesh := MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = blade_mesh
	multimesh.instance_count = transforms.size()
	for index in range(transforms.size()):
		multimesh.set_instance_transform(index,transforms[index])
		multimesh.set_instance_custom_data(index,customs[index])
	var instance := MultiMeshInstance3D.new()
	instance.name = "Grass_%d_%d" % [key.x,key.y]
	instance.multimesh = multimesh
	instance.material_override = material
	instance.position = Vector3(chunk_origin.x,0,chunk_origin.y)
	var margin := maxf(0.5,max_height*1.5)
	instance.custom_aabb = AABB(Vector3(-margin,-0.1,-margin),Vector3(CHUNK_SIZE+margin*2,max_height+0.2,CHUNK_SIZE+margin*2))
	instance.visibility_range_end = 80.0
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance

func _keep_limit(level: int) -> float:
	if level == 0: return 1.0
	return minf(1.0,1.0-smoothstep(30.0,70.0,30.0+float(level)*8.0)+0.05)

func _install_chunk(key: Vector2i, level: int) -> void:
	var instance := _generate_chunk(key,level)
	_remove_chunk(key)
	var count := 0
	if instance != null:
		add_child(instance)
		count = instance.multimesh.instance_count
	resident[key] = {"node":instance,"level":level,"count":count}
	blade_count += count

func _remove_chunk(key: Vector2i) -> void:
	if not resident.has(key): return
	var entry: Dictionary = resident[key]
	blade_count -= int(entry["count"])
	var node = entry["node"]
	if is_instance_valid(node):
		remove_child(node)
		node.queue_free()
	resident.erase(key)
	distribution_dirty.erase(key)

func _chunk_visible(camera: Camera3D, center: Vector3, near_distance: float) -> bool:
	if near_distance<12.0: return true
	if camera.is_position_in_frustum(to_global(center)): return true
	# Include boundary corners and wind margin, not only the chunk center.
	for x in [-0.6,4.6]:
		for z in [-0.6,4.6]:
			for y in [0.0,0.8]:
				if camera.is_position_in_frustum(to_global(center+Vector3(x-2.0,y,z-2.0))): return true
	return false

func _update_stream(camera: Camera3D) -> void:
	var camera_local := to_local(camera.global_position)
	var choices: Array[Dictionary] = []
	for z in range(floori(area.position.y/CHUNK_SIZE),ceili(area.end.y/CHUNK_SIZE)):
		for x in range(floori(area.position.x/CHUNK_SIZE),ceili(area.end.x/CHUNK_SIZE)):
			var key := Vector2i(x,z)
			var center := Vector3((x+0.5)*CHUNK_SIZE,0,(z+0.5)*CHUNK_SIZE)
			# Conservative nearest distance includes half diagonal and blade height/wind.
			var near_distance := maxf(0.0,camera_local.distance_to(center)-4.0)
			if near_distance>=70.0 or not _chunk_visible(camera,center,near_distance): continue
			var level := maxi(0,floori((near_distance-30.0)/8.0))
			choices.append({"key":key,"distance":near_distance,"level":level})
	choices.sort_custom(func(a: Dictionary,b: Dictionary): return a["distance"]<b["distance"])
	desired.clear()
	pending.clear()
	var cost := 0.0
	for choice in choices:
		var level := int(choice["level"])
		var chunk_cost := 1600.0*_keep_limit(level)
		if desired.size()>=resident_chunk_limit: break
		if cost+chunk_cost>candidate_load_limit: continue
		cost += chunk_cost
		var key: Vector2i = choice["key"]
		desired[key] = level
		if not resident.has(key) or resident[key]["level"]!=level or distribution_dirty.has(key): pending.append(key)
	for key: Vector2i in resident.keys():
		if not desired.has(key): _remove_chunk(key)
