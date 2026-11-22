extends RefCounted

const Parameters = preload("res://scripts/scenery/wall_parameters.gd")
const Materials = preload("res://scripts/scenery/wall_material.gd")
const MeshQuality = preload("res://scripts/scenery/wall_mesh_quality.gd")
const Logs = preload("res://scripts/scenery/wall_log_geometry.gd")
const Openings = preload("res://scripts/scenery/wall_opening_layout.gd")

# Native Godot CSG difference, baked once into an ordinary mesh and collision.
# Origin = floor-level left end; local +X = wall length, Z = thickness.
static var _cache: Dictionary = {}
const CACHE_LIMIT := 128

static func build(values: Dictionary, end_slopes := Vector2.ZERO, placement := Transform3D.IDENTITY, log_joins: Array = [], opening_layout: Variant = null) -> Dictionary:
	var error := Parameters.validate(values)
	if not error.is_empty(): return {"ok": false, "message": error}
	error = _validate_log_joins(values.surface,log_joins)
	if not error.is_empty(): return {"ok":false,"message":error}
	var length := float(values.length) * Parameters.FEET
	var height := float(values.height) * Parameters.FEET
	var half_depth := float(values.thickness) * Parameters.FEET * 0.5
	if not end_slopes.is_finite(): return {"ok": false, "message": "转角接缝参数无效"}
	var start_inset := absf(end_slopes.x) * half_depth
	var end_inset := absf(end_slopes.y) * half_depth
	if not log_joins.is_empty():
		if not log_joins[0].is_empty(): start_inset=maxf(start_inset,float(log_joins[0].half_depth))
		if not log_joins[1].is_empty(): end_inset=maxf(end_inset,float(log_joins[1].half_depth))
	if start_inset + end_inset >= length:
		return {"ok": false, "message": "墙体太短，无法容纳两端转角"}
	if opening_layout!=null and not opening_layout is Array:
		return {"ok":false,"message":"洞口布局必须为数组"}
	var openings: Array = Openings.from_legacy(values) if opening_layout==null else opening_layout.duplicate()
	error = Openings.validate(values,openings,Vector2(start_inset,end_inset))
	if not error.is_empty(): return {"ok":false,"message":error}
	var opening: Rect2 = openings[0] if not openings.is_empty() else Rect2()
	var geometry_values := values.duplicate()
	geometry_values.erase("color")
	var pattern := Vector2(0,1)
	if Parameters.is_planks(values.surface) or Parameters.is_logs(values.surface):
		var yaw := placement.basis.get_euler().y
		if not placement.is_finite() or not placement.basis.is_equal_approx(Basis(Vector3.UP,yaw)) or not is_zero_approx(placement.origin.y) or absf(yaw/(PI*0.5)-roundf(yaw/(PI*0.5))) > 0.0001:
			return {"ok": false, "message": "木墙接缝只支持地面正交摆放"}
		# Two board widths retain odd/even column staggering for vertical boards.
		var repeat_length := Logs.LOG_LENGTH if Parameters.is_logs(values.surface) else (Materials.BOARD_HEIGHT * 2.0 if values.surface == "planks_vertical" else Materials.BOARD_LENGTH)
		var phase := fposmod(placement.origin.x + placement.origin.z, repeat_length)
		# Cardinal Basis/translation products carry float noise at exact half-board cuts.
		var half_board := repeat_length*0.5
		if absf(phase-snappedf(phase,half_board)) < 0.000001: phase = fposmod(snappedf(phase,half_board),repeat_length)
		pattern = Vector2(phase, roundf(placement.basis.x.x + placement.basis.x.z))
	var key := var_to_bytes([geometry_values, end_slopes, pattern, log_joins, openings]).hex_encode()
	if _cache.has(key): return recolor(_cache[key], values.color)
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null: return {"ok": false, "message": "布尔生成需要运行中的场景树"}
	var material := Materials.create(values.surface, values.color, length, end_slopes, Materials.join_margins(length, half_depth, end_slopes))
	if Parameters.is_logs(values.surface):
		material.set_shader_parameter("log_radius",half_depth)
		material.set_shader_parameter("course_height",Logs.COURSE_HEIGHT)
	var operation := CSGCombiner3D.new()
	operation.name = "TemporaryWallBoolean"
	operation.visible = false
	operation.calculate_tangents = false
	var solid: CSGShape3D
	if Parameters.is_logs(values.surface):
		solid = Logs.solid(length,height,half_depth,pattern,end_slopes,log_joins,material,values.surface=="logs_bark",values.surface=="logs_squared")
	elif Parameters.is_planks(values.surface):
		var timber := CSGMesh3D.new()
		timber.mesh = Materials.plank_solid(length, height, half_depth, end_slopes, material, pattern, values.surface == "planks_vertical")
		timber.material = material
		solid = timber
	else:
		var flat := CSGPolygon3D.new()
		# CSGPolygon extrudes along -Z. +90 degrees maps extrusion to world +Y.
		flat.rotation.x = PI * 0.5
		flat.depth = height
		flat.polygon = PackedVector2Array([
			Vector2(-end_slopes.x * half_depth, -half_depth),
			Vector2(end_slopes.x * half_depth, half_depth),
			Vector2(length + end_slopes.y * half_depth, half_depth),
			Vector2(length - end_slopes.y * half_depth, -half_depth)])
		flat.material = material
		solid = flat
	solid.name = "WallSolid"
	operation.add_child(solid)
	for opening_index in openings.size():
		var cut: Rect2 = openings[opening_index]
		var cutter: CSGPrimitive3D
		# Vertical joints coincide with common door jambs. Construct the cutter in
		# wall coordinates so its planes use the same float vertices as those joints;
		# Box center +/- half-size otherwise introduces sub-micron sliver faces.
		var padding := maxf(0.01, half_depth * 0.2)
		var below := padding if is_zero_approx(cut.position.y) else 0.0
		if values.surface=="planks_vertical" or Parameters.is_logs(values.surface):
			var cut_mesh := CSGMesh3D.new()
			cut_mesh.mesh = _opening_mesh(cut, half_depth + padding, below,Parameters.is_logs(values.surface))
			cutter = cut_mesh
		else:
			var box := CSGBox3D.new()
			box.size = Vector3(cut.size.x, cut.size.y + below, half_depth * 2.0 + padding * 2.0)
			box.position = Vector3(cut.get_center().x, cut.get_center().y - below * 0.5, 0)
			cutter = box
		cutter.name = "OpeningCut%d" % opening_index
		cutter.operation = CSGShape3D.OPERATION_SUBTRACTION
		cutter.material = material
		operation.add_child(cutter)
	tree.root.add_child.call_deferred(operation)
	# Public API: CSG geometry is updated through the deferred queue, never via _update_shape.
	await tree.process_frame
	if not operation.is_inside_tree():
		operation.queue_free()
		return {"ok": false, "message": "布尔生成节点未能进入场景树"}
	var mesh := operation.bake_static_mesh()
	operation.get_parent().remove_child(operation)
	operation.queue_free()
	if mesh == null or mesh.get_surface_count() != 1 or mesh.surface_get_array_len(0) == 0:
		return {"ok": false, "message": "布尔墙体生成失败，保留已有墙体"}
	if Parameters.is_planks(values.surface) or Parameters.is_logs(values.surface): mesh = MeshQuality.improve(mesh)
	var result := {"ok": true, "message": "", "mesh": mesh, "collision": _collision(mesh),
		"bounds": mesh.get_aabb(), "opening": opening, "openings":openings.duplicate(), "triangles": mesh.surface_get_array_len(0) / 3,
		"parameters": values.duplicate(true), "end_slopes": end_slopes, "pattern": pattern, "generator_version": Parameters.VERSION,
		"construction": "csg_difference_baked", "log_joins":log_joins.duplicate(true)}
	if _cache.size() >= CACHE_LIMIT: _cache.erase(_cache.keys()[0])
	_cache[key] = result
	return result.duplicate()

static func _validate_log_joins(surface: String, joins: Array) -> String:
	if joins.is_empty(): return ""
	if not Parameters.is_logs(surface) or joins.size()!=2: return "原木接头上下文无效"
	for join in joins:
		if not join is Dictionary: return "原木接头参数无效"
		if join.is_empty(): continue
		if not join.has_all(["half_depth","height","even_through"]): return "原木接头参数不完整"
		for key in join:
			if key not in ["half_depth","height","even_through","bark","squared"]: return "原木接头参数含未知项"
		if join.has("bark") and typeof(join.bark)!=TYPE_BOOL: return "邻接原木表面参数无效"
		if join.has("squared") and typeof(join.squared)!=TYPE_BOOL: return "邻接方木截面参数无效"
		if join.get("squared",false) and join.get("bark",false): return "邻木不能同时为方木和带皮圆木"
		if typeof(join.even_through)!=TYPE_BOOL: return "原木接头方向无效"
		for key in ["half_depth","height"]:
			if typeof(join[key]) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(join[key])) or float(join[key])<=0:
				return "原木接头尺寸无效"
	return ""

static func _opening_mesh(opening: Rect2, half_depth: float, below: float, align_log_planes := false) -> ArrayMesh:
	var box := BoxMesh.new()
	box.size = Vector3.ONE
	var arrays := box.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	for i in vertices.size():
		var v := vertices[i]
		var x := opening.position.x if v.x < 0 else opening.end.x
		var y := opening.position.y-below if v.y < 0 else opening.end.y
		# Rect2.end adds two float32 values; normalize sub-micron arithmetic noise
		# before comparing it with the independently constructed course planes.
		if align_log_planes:
			x = snappedf(x,0.000001)
			y = snappedf(y,0.000001)
		vertices[i] = Vector3(x,y,-half_depth if v.z < 0 else half_depth)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh

static func _collision(mesh: ArrayMesh) -> ConcavePolygonShape3D:
	# Mesh.create_trimesh_shape passes through TriangleMesh's 0.0001 vertex snap.
	# Use the baked surface directly so narrow grooves and fractional cuts stay identical.
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices := PackedInt32Array()
	if arrays[Mesh.ARRAY_INDEX] != null: indices = arrays[Mesh.ARRAY_INDEX]
	var faces := PackedVector3Array()
	if indices.is_empty(): faces = vertices
	else:
		for index in indices: faces.append(vertices[index])
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	return shape

static func clear_cache() -> void:
	_cache.clear()

static func recolor(result: Dictionary, color: Color) -> Dictionary:
	if not result.get("ok", false): return result.duplicate()
	var updated := result.duplicate()
	updated.parameters = result.parameters.duplicate(true)
	updated.parameters.color = color
	var error := Parameters.validate(updated.parameters)
	if not error.is_empty(): return {"ok": false, "message": error}
	# A material edit must never recolor previously placed walls or cached resources.
	updated.mesh = result.mesh.duplicate()
	var material := Materials.recolor(result.mesh.surface_get_material(0), color)
	updated.mesh.surface_set_material(0, material)
	return updated

static func instantiate_wall(result: Dictionary) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "Wall"
	var visible_mesh := MeshInstance3D.new()
	visible_mesh.name = "WallMesh"
	visible_mesh.mesh = result.mesh
	body.add_child(visible_mesh)
	var collision := CollisionShape3D.new()
	collision.shape = result.collision
	body.add_child(collision)
	body.set_meta("wall_parameters", result.parameters.duplicate(true))
	return body
