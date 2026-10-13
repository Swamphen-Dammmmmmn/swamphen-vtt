extends "res://ui/components/platform_preview.gd"
const MapData = preload("res://scripts/map_data.gd")
const TokenInstance = preload("res://scripts/token_instance.gd")
const Footprint = preload("res://scripts/token_footprint.gd")
const Weather = preload("res://scripts/map_weather.gd")
var weather := Weather.defaults()
var play_mode := false

var items: Dictionary = {}
var actors: Dictionary = {}
var paints: Dictionary = {}
var permission_lines: Dictionary = {}
var reference_lines: Dictionary = {}
var permission_fills: Dictionary = {}
var selected_outline: MeshInstance3D
var ghost: MeshInstance3D
var selected_id := ""
var map_grid: MeshInstance3D
var budget_clock := 0.0
var active_grass: Array = []
var build_cursor := 0
var ghost_cache: Array = []
var editing_id := ""
var render_origin := Vector3.ZERO

func apply_weather(data: Dictionary) -> void:
	var wind_changed: bool = weather["wind"]!=data["wind"]
	weather = data.duplicate(true)
	var environment := world.get_node("SceneEnvironment")
	Weather.apply_scene(environment,weather)
	Graphics.apply_environment(environment.get_node("WorldEnvironment").environment)
	if wind_changed:
		for root: Node3D in actors.values(): _apply_wind(root)
		if is_instance_valid(actor): _apply_wind(actor)

func _apply_wind(root: Node3D) -> void:
	var blades = root.get_node("GrassBlades")
	for key in weather["wind"]: blades.settings[key] = weather["wind"][key]
	blades._apply_material()

func begin_platform_edit(id: String) -> void:
	editing_id = id
	render_origin = items[id]["offset_feet"]
	highlight("")
	hide_ghost()
	camera.position -= render_origin/5.0
	target -= render_origin/5.0
	map_grid.position = -render_origin/5.0
	for key: String in actors:
		move_platform(key,items[key]["offset_feet"])
	actors[id].hide()
	var blades = actors[id].get_node("GrassBlades")
	blades.resident_chunk_limit = 0
	blades.candidate_load_limit = 0
	blades.builds_per_frame = 0
	budget_clock = 1

func configure(data: Dictionary, fit_camera := false) -> void:
	super.configure(data,fit_camera)
	_apply_wind(actor)
	if not editing_id.is_empty():
		var blades = actor.get_node("GrassBlades")
		blades.resident_chunk_limit = 0
		blades.candidate_load_limit = 0
		blades.builds_per_frame = 0
		budget_clock = 1

func finish_platform_edit() -> void:
	paint.shutdown()
	paint = Paint.new()
	for node in [actor,grid,landing_grid,permission_fill,brush,paint_rectangle,landing_brush,draft_overlay,expansion_outline,expansion_fill,expansion_volume]:
		if is_instance_valid(node):
			world.remove_child(node)
			node.queue_free()
	for label in direction_labels:
		if is_instance_valid(label): label.queue_free()
	direction_labels.clear()
	actor = null
	grid = null
	landing_grid = null
	permission_fill = null
	brush = null
	paint_rectangle = null
	landing_brush = null
	draft_overlay = null
	expansion_outline = null
	expansion_fill = null
	expansion_volume = null
	values = {}
	brush_cached = Vector4(-1,-1,-1,-1)
	paint_rectangle_cache = Rect2()
	landing_brush_cache = Rect2i()
	draft_cache = {}
	landing_cache = []
	set_range_handles([],"")
	camera.position += render_origin/5.0
	target += render_origin/5.0
	render_origin = Vector3.ZERO
	map_grid.position = Vector3.ZERO
	editing_id = ""
	for key: String in actors:
		actors[key].show()
		move_platform(key,items[key]["offset_feet"])
	budget_clock = 1

func hide_edit_markers() -> Array:
	var states: Array = []
	for node in [grid,landing_grid,permission_fill,brush,paint_rectangle,landing_brush,draft_overlay,expansion_outline,expansion_fill,expansion_volume,handles]+direction_labels:
		if is_instance_valid(node):
			states.append([node,node.visible])
			node.hide()
	return states

func restore_edit_markers(states: Array) -> void:
	for state in states:
		if is_instance_valid(state[0]): state[0].visible = state[1]

func _ready() -> void:
	super._ready()
	camera.far = 10000
	var points: Array[Vector3] = []
	for index in range(-50,51):
		points.append_array([Vector3(index,-0.01,-50),Vector3(index,-0.01,50),Vector3(-50,-0.01,index),Vector3(50,-0.01,index)])
	map_grid = _lines(points,Color("8c9aaa"))
	world.add_child(map_grid)
	camera.position = Vector3(15,18,22)
	camera.look_at(Vector3.ZERO)
	free_yaw = camera.rotation.y
	free_pitch = camera.rotation.x

func _lines(points: Array[Vector3], color: Color) -> MeshInstance3D:
	var node := MeshInstance3D.new()
	var mesh := ImmediateMesh.new()
	if not points.is_empty():
		mesh.surface_begin(Mesh.PRIMITIVE_LINES)
		for point in points: mesh.surface_add_vertex(point)
		mesh.surface_end()
	node.mesh = mesh
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return node

func add_platform(item: Dictionary) -> void:
	var id: String = item["id"]
	items[id] = item
	var root := Model.build(item["data"])
	actors[id] = root
	var blades: Node3D = root.get_node("GrassBlades")
	blades.resident_chunk_limit = 0
	blades.candidate_load_limit = 0
	blades.builds_per_frame = 0
	world.add_child(root)
	var ground := Paint.new()
	paints[id] = ground
	ground.configure(item["data"],root.get_node("Surface"),blades)
	_apply_wind(root)
	var pixels: PackedByteArray = ground.effective.get_data()
	var has_grass := false
	for index in range(0,pixels.size(),4):
		if pixels[index]>=4:
			has_grass = true
			break
	blades.visible = has_grass and bool(blades.settings["enabled"])
	var data: Dictionary = item["data"]
	var origin: Vector2 = data["grid_origin_feet"]/5.0
	for token: Dictionary in data.get("tokens",[]):
		var actor := TokenInstance.build(token)
		root.add_child(actor)
		var cell: Vector2i = token["cell"]
		var extent := Footprint.dimensions(token)
		actor.position = Vector3(origin.x+cell.x+extent.x/2.0,float(data["top_feet"])/5.0,origin.y+cell.y+extent.y/2.0)
	var grid_segments := Grid.segments(data,true)
	var segments: Array[Vector2] = grid_segments["solid"]
	var points: Array[Vector3] = []
	for point in segments: points.append(Vector3(origin.x+point.x,float(data["top_feet"])/5.0+0.008,origin.y+point.y))
	var lines := _lines(points,Color("4a7991"))
	root.add_child(lines)
	permission_lines[id] = lines
	lines.visible = grid_shown
	var dashed_points: Array[Vector3] = []
	for point: Vector2 in grid_segments["dashed"]:
		dashed_points.append(Vector3(origin.x+point.x,float(data["top_feet"])/5.0+0.015,origin.y+point.y))
	var reference := _lines(dashed_points,Color("8798a9"))
	root.add_child(reference)
	reference.visible = grid_shown
	reference_lines[id] = reference
	var fill := _make_permission_fill(data,root)
	if is_instance_valid(fill): fill.visible = landing_highlight
	permission_fills[id] = fill
	move_platform(id,item["offset_feet"])
	budget_clock = 1

func remove_platform(id: String) -> void:
	if paints.has(id): paints[id].shutdown()
	paints.erase(id)
	if actors.has(id):
		world.remove_child(actors[id])
		actors[id].queue_free()
	actors.erase(id)
	permission_lines.erase(id)
	reference_lines.erase(id)
	permission_fills.erase(id)
	items.erase(id)
	if selected_id==id: highlight("")
	budget_clock = 1

func move_platform(id: String, offset: Vector3) -> void:
	offset -= render_origin
	actors[id].position = offset/5.0
	var ground = paints[id]
	ground.material.set_shader_parameter("area_origin",ground.area.position+Vector2(offset.x,offset.z)/5.0)
	ground.material.set_shader_parameter("top_scene_height",float(items[id]["data"]["top_feet"])/5.0+offset.y/5.0)
	var blades = actors[id].get_node("GrassBlades")
	blades.material.set_shader_parameter("coverage_origin",ground.area.position+Vector2(offset.x,offset.z)/5.0)
	blades.camera_seen = false
	if selected_id==id: highlight(id)
	budget_clock = 1

func highlight(id: String) -> void:
	selected_id = id
	if is_instance_valid(selected_outline): selected_outline.queue_free()
	selected_outline = null
	if not items.has(id): return
	var box := MapData.bounds(items[id])
	box = box.grow(0.03)
	var points: Array[Vector3] = []
	var corners: Array[Vector3] = []
	for x in [box.position.x,box.end.x]:
		for y in [box.position.y,box.end.y]:
			for z in [box.position.z,box.end.z]: corners.append(Vector3(x,y,z)/5.0)
	for index in range(8):
		for axis in [1,2,4]:
			if (index & axis)==0: points.append_array([corners[index],corners[index|axis]])
	selected_outline = _lines(points,Color("127cb5"))
	world.add_child(selected_outline)

func show_ghost(item: Dictionary, offset: Vector3, invalid: bool) -> void:
	var box := MapData.bounds(item,offset)
	var key: Array = [box,invalid]
	if key==ghost_cache and is_instance_valid(ghost):
		ghost.show()
		return
	ghost_cache = key
	if not is_instance_valid(ghost):
		ghost = MeshInstance3D.new()
		ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world.add_child(ghost)
	var mesh := BoxMesh.new()
	mesh.size = box.size/5.0
	ghost.mesh = mesh
	ghost.position = box.get_center()/5.0
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = Color(0.9,0.18,0.2,0.45) if invalid else Color(0.12,0.65,0.85,0.4)
	ghost.material_override = material
	ghost.show()

func hide_ghost() -> void:
	if is_instance_valid(ghost): ghost.hide()

func plane_point(point: Vector2, height_feet: float) -> Variant:
	var local := point-get_global_rect().position
	var origin := camera.project_ray_origin(local)
	var direction := camera.project_ray_normal(local)
	if absf(direction.y)<0.00001: return null
	var distance_to_plane := (height_feet/5.0-origin.y)/direction.y
	if distance_to_plane<0: return null
	return (origin+direction*distance_to_plane)*5.0

func picks(point: Vector2) -> Array[String]:
	var origin := camera.project_ray_origin(point-get_global_rect().position)*5.0
	var direction := camera.project_ray_normal(point-get_global_rect().position)
	var hits: Array = []
	for id: String in items:
		var box := MapData.bounds(items[id])
		var near := 0.0
		var far := INF
		for axis in range(3):
			if absf(direction[axis])<0.00001:
				if origin[axis]<box.position[axis] or origin[axis]>box.end[axis]: far = -1
			else:
				var a := (box.position[axis]-origin[axis])/direction[axis]
				var b := (box.end[axis]-origin[axis])/direction[axis]
				near = maxf(near,minf(a,b))
				far = minf(far,maxf(a,b))
		if far>=near: hits.append({"id":id,"distance":near})
	hits.sort_custom(func(a: Dictionary,b: Dictionary): return a["distance"]<b["distance"])
	var result: Array[String] = []
	for hit: Dictionary in hits: result.append(hit["id"])
	return result

func focus_platform(id: String) -> void:
	if not items.has(id): return
	var box := MapData.bounds(items[id])
	target = box.get_center()/5.0
	distance = maxf(8,box.size.length()/5.0*1.5)
	_position_camera()

func frame_all() -> void:
	if items.is_empty(): return
	var box: AABB = MapData.bounds(items.values()[0])
	for item: Dictionary in items.values(): box = box.merge(MapData.bounds(item))
	target = box.get_center()/5.0
	distance = maxf(8,box.size.length()/5.0*1.4)
	_position_camera()

func set_map_grid(shown: bool) -> void:
	map_grid.visible = shown

func set_permissions(shown: bool) -> void:
	set_landing_highlight(shown)

func _make_permission_fill(data: Dictionary = {}, parent: Node3D = null) -> MeshInstance3D:
	var fill := super._make_permission_fill(data,parent)
	if is_instance_valid(fill): fill.material_override.no_depth_test = false
	return fill

func _landing_lines(segments: Array[Vector2], color: Color, height_offset: float) -> MeshInstance3D:
	var lines := super._landing_lines(segments,color,height_offset)
	if is_instance_valid(lines): lines.material_override.no_depth_test = false
	return lines

func set_grid_visible(shown: bool) -> void:
	super.set_grid_visible(shown)
	for lines: Node3D in reference_lines.values(): lines.visible = shown
	for lines: Node3D in permission_lines.values(): lines.visible = shown

func set_landing_highlight(shown: bool) -> void:
	super.set_landing_highlight(shown)
	for fill in permission_fills.values():
		if is_instance_valid(fill): fill.visible = shown

func _budget_grass() -> void:
	var choices: Array = []
	for id: String in actors:
		if id==editing_id: continue
		var blades = actors[id].get_node("GrassBlades")
		if not blades.visible: continue
		var box := MapData.bounds(items[id])
		box.position -= render_origin
		var nearest := (camera.global_position*5.0).clamp(box.position,box.end)/5.0
		var near_distance := camera.global_position.distance_to(nearest)
		if near_distance>=74:
			if blades.resident_chunk_limit!=0: blades.camera_seen = false
			blades.resident_chunk_limit = 0
			blades.candidate_load_limit = 0
			blades.builds_per_frame = 0
			continue
		choices.append({"blades":blades,"distance":near_distance})
	if not editing_id.is_empty() and is_instance_valid(actor):
		var blades = actor.get_node("GrassBlades")
		if blades.visible: choices.append({"blades":blades,"distance":0.0})
	choices.sort_custom(func(a: Dictionary,b: Dictionary): return a["distance"]<b["distance"])
	active_grass.clear()
	var count := mini(32,choices.size())
	for index in range(choices.size()):
		var blades = choices[index]["blades"]
		var limit := int(192/maxi(1,count)) if index<count else 0
		if blades.resident_chunk_limit!=limit: blades.camera_seen = false
		blades.resident_chunk_limit = limit
		blades.candidate_load_limit = int(200000/maxi(1,count)) if index<count else 0
		blades.builds_per_frame = 0
		if index<count: active_grass.append(blades)

func _process(delta: float) -> void:
	if editing_id.is_empty(): clock += delta
	else: super._process(delta)
	for id: String in actors:
		var above: bool = camera.position.y>(float(items[id]["data"]["top_feet"])+float(items[id]["offset_feet"].y)-render_origin.y)/5.0+0.001
		permission_lines[id].visible = grid_shown and above
		reference_lines[id].visible = grid_shown and above and not play_mode
		var fill = permission_fills[id]
		if is_instance_valid(fill): fill.visible = landing_highlight and above
	for ground in paints.values(): ground.advance(clock)
	for root: Node3D in actors.values(): root.get_node("GrassBlades").wind_elapsed = clock
	if is_instance_valid(actor): actor.get_node("GrassBlades").wind_elapsed = clock
	budget_clock += delta
	if budget_clock>=0.25:
		budget_clock = 0
		_budget_grass()
	for blades in active_grass:
		if is_instance_valid(blades): blades.builds_per_frame = 0
	if not active_grass.is_empty():
		build_cursor = (build_cursor+1)%active_grass.size()
		if is_instance_valid(active_grass[build_cursor]): active_grass[build_cursor].builds_per_frame = 2

func _exit_tree() -> void:
	paint.shutdown()
	for ground in paints.values(): ground.shutdown()
