extends Node

# Asset geometry inspection only. No simulated input, gameplay, physics step or save access.
const Generator = preload("res://scripts/scenery/wall_generator.gd")
const Parameters = preload("res://scripts/scenery/wall_parameters.gd")
const Joiner = preload("res://scripts/scenery/wall_joiner.gd")
@export var output_directory := "res://artifacts/wall-horizontal-planks-2026-10-24/gray/"

func _ready() -> void:
	if not _check(DirAccess.make_dir_recursive_absolute(output_directory) == OK, "Cannot create asset inspection output"): return
	var records: Array = []
	for kind in 3:
		var values := _recipe(kind)
		if not _check(values.length == 5.0 and values.opening_width == 3.0, "Default module / opening dimensions differ from the agreed sizes"): return
		var result := await Generator.build(values)
		if not _check(result.ok, "Default recipe refused"): return
		if not _inspect(result, values): return
		Generator.clear_cache()
		var repeat := await Generator.build(values)
		if not _check(_digest(result.mesh) == _digest(repeat.mesh), "Non-deterministic mesh"): return
		var tinted := Generator.recolor(result, Color("996633"))
		if not _check(tinted.ok and _digest(tinted.mesh) == _digest(result.mesh) and result.mesh.surface_get_material(0).albedo_color == values.color and tinted.mesh.surface_get_material(0).albedo_color == Color("996633"), "Recolor changed geometry or an existing material"): return
		for child in get_tree().root.get_children():
			if not _check(not child is CSGShape3D, "Temporary CSG node retained after bake"): return
		var root := Generator.instantiate_wall(result)
		for child in root.get_children(): child.owner = root
		var scene := PackedScene.new()
		var code := scene.pack(root)
		if code == OK: code = ResourceSaver.save(scene, output_directory + "wall_%d.scn" % kind, ResourceSaver.FLAG_COMPRESS)
		root.free()
		if not _check(code == OK, "Cannot save wall asset"): return
		records.append({"kind": kind, "title": Parameters.TITLES[kind], "triangles": result.triangles,
			"bounds": str(result.bounds), "sha256": _digest(result.mesh)})
	# Non-default sizes, asymmetric windows/doors and minimum legal border thickness.
	var boundary_count := 0
	for kind in 3:
		for edits in [{"length": 5.0, "height": 5.0, "thickness": 0.25, "opening_width": 1.0, "opening_height": 1.0, "sill": 0.5},
				{"length": 50.0, "height": 30.0, "thickness": 3.0, "opening_width": 1.0, "opening_offset": 24.0},
				{"length": 7.0, "height": 9.0, "opening_width": 2.5, "opening_height": 2.0, "opening_offset": -1.75, "sill": 6.75}]:
			var p := _recipe(kind)
			p.merge(edits, true)
			var result := await Generator.build(p)
			if not _check(result.ok, "Valid boundary recipe refused: " + str(p)): return
			if not _inspect(result, p): return
			boundary_count += 1
	var rejected := 0
	for edits in [{"length": NAN}, {"height": INF}, {"thickness": 0.0}, {"kind": 1.5}, {"kind": -1}, {"color": Color(1, 1, 1, 0.5)},
			{"unknown": 1}, {"opening_width": 10.0}, {"opening_offset": 4.0}, {"opening_height": 10.0}, {"sill": 9.0}]:
		var p := _recipe(2)
		p.merge(edits, true)
		if not _check(not (await Generator.build(p)).ok, "Invalid recipe was accepted: " + str(edits)): return
		rejected += 1
	if not _check(not (await Generator.build({})).ok, "Incomplete recipe accepted"): return
	var corner_count := await _inspect_corners()
	if corner_count < 0: return
	var file := FileAccess.open(output_directory + "geometry-report.json", FileAccess.WRITE)
	if not _check(file != null, "Cannot write geometry report"): return
	file.store_string(JSON.stringify({"defaults": records, "boundary_recipes": boundary_count,
		"invalid_recipes_rejected": rejected + 1, "corner_cases": corner_count,
		"construction": "csg_difference_baked", "checks": ["closed_manifold_edges", "outward_normals_clockwise", "volume_matches_opening", "uv_finite", "collision_matches_mesh", "opening_rays_clear", "solid_rays_blocked", "uncached_deterministic", "material_isolation", "temporary_csg_removed", "miter_faces_coincide", "corner_halfspaces_do_not_overlap", "unsafe_junctions_rejected"]}, "\t"))
	file.close()
	print("WALL_ASSET_CHECK_COMPLETE defaults=3 boundaries=", boundary_count, " invalid_rejected=", rejected + 1, " corner_cases=", corner_count)
	get_tree().quit()

func _inspect(result: Dictionary, p: Dictionary, joined := false) -> bool:
	var mesh: ArrayMesh = result.mesh
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var shape: ConcavePolygonShape3D = result.collision
	# ConcavePolygonShape3D may reorder faces when building its spatial index.
	var collision_faces := _face_keys(shape.get_faces())
	var visible_faces := _face_keys(vertices)
	if collision_faces != visible_faces:
		var missing: Array = []
		for face in visible_faces:
			if face not in collision_faces and missing.size() < 4: missing.append(face)
		var extra: Array = []
		for face in collision_faces:
			if face not in visible_faces and extra.size() < 4: extra.append(face)
		print("WALL_COLLISION_DIAGNOSTIC visible=", visible_faces.size(), " collision=", collision_faces.size(), " missing=", missing, " extra=", extra)
		if not _check(false, "Collision differs from visible mesh"): return false
	var edges: Dictionary = {}
	var balance: Dictionary = {}
	var volume := 0.0
	for i in range(0, vertices.size(), 3):
		var a := vertices[i]
		var b := vertices[i + 1]
		var c := vertices[i + 2]
		var cross := (c - a).cross(b - a)
		if not _check(cross.length() > 0.000001 and cross.normalized().dot(normals[i]) > 0.999,
				"Degenerate / inward triangle: " + str([cross.length(), cross.normalized().dot(normals[i]), a, b, c, result.end_slopes, p])): return false
		volume += a.dot(c.cross(b)) / 6.0
		for j in 3:
			if not _check(vertices[i+j].is_finite() and normals[i+j].is_finite() and uvs[i+j].is_finite(), "Non-finite mesh attribute"): return false
			var start := _point_key(vertices[i + j])
			var end := _point_key(vertices[i + (j + 1) % 3])
			var key := start + "|" + end if start < end else end + "|" + start
			edges[key] = int(edges.get(key, 0)) + 1
			balance[key] = int(balance.get(key, 0)) + (1 if start < end else -1)
	for edge in edges:
		if not _check(edges[edge] == 2 and balance[edge] == 0, "Unclosed / non-manifold mesh edge: " + edge): return false
	var expected := _expected_volume(p, result)
	if not _check(absf(volume - expected) < maxf(0.00001, expected * 0.00001), "Wall volume differs from requested hole: " + str([volume, expected, result.get("pattern"), result.end_slopes, p])): return false
	if not joined and not _check(result.bounds.position.is_equal_approx(Vector3(0, 0, -p.thickness * Parameters.FEET * 0.5)), "Incorrect origin"): return false
	var opening: Rect2 = result.opening
	if int(p.kind) != 0:
		if not _check(not _ray_hit(vertices, opening.get_center()), "Opening is blocked by a face"): return false
		if not _check(_ray_hit(vertices, Vector2(opening.position.x * 0.5, p.height * Parameters.FEET * 0.5)), "Side wall is missing"): return false
		if not _check(_ray_hit(vertices, Vector2(opening.get_center().x, (opening.end.y + p.height * Parameters.FEET) * 0.5)), "Lintel is missing"): return false
		if int(p.kind) == 2 and not _check(_ray_hit(vertices, Vector2(opening.get_center().x, opening.position.y * 0.5)), "Window sill wall is missing"): return false
	else:
		if not _check(_ray_hit(vertices, Vector2(p.length, p.height) * Parameters.FEET * 0.5), "Solid wall has a hole"): return false
	return true

func _recipe(kind := 0) -> Dictionary:
	return Parameters.defaults(kind)

func _expected_volume(p: Dictionary, _result: Dictionary = {}) -> float:
	var area := float(p.length * p.height)
	if int(p.kind) != 0: area -= float(p.opening_width * p.opening_height)
	return area * float(p.thickness) * pow(Parameters.FEET, 3)

func _inspect_corners() -> int:
	var count := 0
	for yaw in 4:
		for end_a in 2:
			for end_b in 2:
				for kind in 3:
					var a := _recipe(kind)
					var b := _recipe((kind + 1) % 3)
					if kind == 2:
						# Extreme thickness needs enough pier: keep this valid large-wall case,
						# and separately verify that the short-wall version is refused below.
						a.length = 10.0
						b.length = 10.0
						a.thickness = 0.25
						b.thickness = 3.0
					var basis_a := Basis(Vector3.UP, yaw * PI * 0.5)
					var basis_b := Basis(Vector3.UP, (yaw + 1) * PI * 0.5)
					var ta := Transform3D(basis_a, -basis_a.x * float(a.length) * Parameters.FEET * end_a)
					var tb := Transform3D(basis_b, -basis_b.x * float(b.length) * Parameters.FEET * end_b)
					var entries: Array[Dictionary] = [{"parameters": a, "transform": ta}, {"parameters": b, "transform": tb}]
					var joined := await Joiner.build(entries)
					if not _check(joined.ok and joined.corners == 1, "Corner recipe refused: " + str([yaw,end_a,end_b,kind,joined])): return -1
					if not _inspect(joined.parts[0], a, true) or not _inspect(joined.parts[1], b, true): return -1
					var face_a := _miter_face(joined.parts[0].mesh, ta, joined.parts[0].end_slopes, a.length * Parameters.FEET)
					var face_b := _miter_face(joined.parts[1].mesh, tb, joined.parts[1].end_slopes, b.length * Parameters.FEET)
					# Different opening heights subdivide caps differently. Compare their actual
					# plane, outer rectangle and area rather than their triangulation vertices.
					if not _check(face_a.bounds.is_equal_approx(face_b.bounds) and is_equal_approx(face_a.area, face_b.area) and face_a.normal.dot(face_b.normal) < -0.999,
							"Corner faces do not meet: " + str([yaw, end_a, end_b, kind, face_a, face_b])): return -1
					# Every vertex belongs to its own side of the shared plane: no overlap volume.
					for index in 2:
						var transform: Transform3D = entries[index].transform
						var normal: Vector3 = face_a.normal if index == 0 else face_b.normal
						for vertex in joined.parts[index].mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
							if not _check(normal.dot(transform * vertex - face_a.point) <= 0.00001,
									"Corner meshes overlap: " + str([yaw, end_a, end_b, kind, index, vertex, normal, face_a.point, joined.parts[index].end_slopes])): return -1
					count += 1
	var thin_pier := _recipe(1)
	thin_pier.opening_offset = 0.75
	var thick := _recipe()
	thick.thickness = 3.0
	var unsafe: Array[Dictionary] = [{"parameters": thin_pier, "transform": Transform3D.IDENTITY},
		{"parameters": thick, "transform": Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(float(thin_pier.length) * Parameters.FEET, 0, 0))}]
	if not _check(Parameters.validate(thin_pier).is_empty(), "Unsafe corner case must start from valid standalone wall dimensions"): return -1
	if not _check(not (await Joiner.build(unsafe)).ok, "Corner cut invaded door opening"): return -1
	var wall_length := float(_recipe().length) * Parameters.FEET
	for overlap_case in 2:
		var origin := Vector3(wall_length * (0.5 if overlap_case == 0 else 1.0), 0, 0)
		var overlap: Array[Dictionary] = [{"parameters": _recipe(), "transform": Transform3D.IDENTITY},
			{"parameters": _recipe(), "transform": Transform3D(Basis.IDENTITY, origin)}]
		if overlap_case == 0:
			if not _check(not (await Joiner.build(overlap)).ok, "Overlapping collinear walls accepted"): return -1
		else:
			if not _check((await Joiner.build(overlap)).ok, "Straight continuation refused"): return -1
	var room: Array[Dictionary] = []
	var positions := [Vector3.ZERO, Vector3(wall_length, 0, 0), Vector3(wall_length, 0, -wall_length), Vector3(0, 0, -wall_length)]
	for i in 4:
		room.append({"parameters": _recipe(i % 3), "transform": Transform3D(Basis(Vector3.UP, i * PI * 0.5), positions[i])})
	var room_result := await Joiner.build(room)
	if not _check(room_result.ok and room_result.corners == 4, "Four-wall room did not close"): return -1
	for i in 4:
		if not _inspect(room_result.parts[i], room[i].parameters, true): return -1
		if not _check(absf(room_result.parts[i].end_slopes.x) > 0 and absf(room_result.parts[i].end_slopes.y) > 0, "Both room ends must be joined"): return -1
	room.pop_back()
	var removed := await Joiner.build(room)
	if not _check(removed.ok and removed.corners == 2 and is_zero_approx(removed.parts[0].end_slopes.x) and is_zero_approx(removed.parts[2].end_slopes.y), "Removing a wall did not restore flat ends"): return -1
	for transform in [Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(wall_length * 0.5, 0, 0)), Transform3D(Basis(Vector3.UP, PI * 0.25), Vector3(wall_length, 0, 0))]:
		var invalid: Array[Dictionary] = [{"parameters": _recipe(), "transform": Transform3D.IDENTITY},
			{"parameters": _recipe(), "transform": transform}]
		if not _check(not (await Joiner.build(invalid)).ok, "Unsupported junction was accepted"): return -1
	return count

func _miter_face(mesh: ArrayMesh, transform: Transform3D, slopes: Vector2, length: float) -> Dictionary:
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var points: Dictionary = {}
	var normal := Vector3.ZERO
	var point := Vector3.ZERO
	var bounds := AABB()
	var initialized := false
	var area := 0.0
	for i in range(0, vertices.size(), 3):
		var on_cap := false
		for end in 2:
			if is_zero_approx(slopes[end]): continue
			var plane := true
			for j in 3:
				var v := vertices[i+j]
				if absf(v.x - (0.0 if end == 0 else length) - slopes[end]*v.z) / sqrt(1.0+slopes[end]*slopes[end]) > 0.000001: plane = false
			if plane: on_cap = true
		if not on_cap: continue
		for j in 3:
			point = transform * vertices[i+j]
			points[_point_key(point)] = true
			bounds = bounds.expand(point) if initialized else AABB(point, Vector3.ZERO)
			initialized = true
		var a := vertices[i]
		var b := vertices[i+1]
		var c := vertices[i+2]
		area += (b-a).cross(c-a).length() * 0.5
		normal = transform.basis * (c-a).cross(b-a).normalized()
	var keys := points.keys()
	keys.sort()
	return {"points": keys, "normal": normal, "point": point, "bounds": bounds, "area": area}

func _ray_hit(vertices: PackedVector3Array, point: Vector2) -> bool:
	for i in range(0, vertices.size(), 3):
		if Geometry3D.segment_intersects_triangle(Vector3(point.x, point.y, -10), Vector3(point.x, point.y, 10), vertices[i], vertices[i + 1], vertices[i + 2]) != null: return true
	return false

func _point_key(point: Vector3) -> String:
	return "%d,%d,%d" % [roundi(point.x * 100000), roundi(point.y * 100000), roundi(point.z * 100000)]

func _face_keys(vertices: PackedVector3Array) -> Array[String]:
	var faces: Array[String] = []
	for i in range(0, vertices.size(), 3):
		var keys := [_point_key(vertices[i]), _point_key(vertices[i+1]), _point_key(vertices[i+2])]
		var rotations: Array[String] = []
		for start in 3: rotations.append(keys[start] + "/" + keys[(start+1)%3] + "/" + keys[(start+2)%3])
		rotations.sort()
		faces.append(rotations[0])
	faces.sort()
	return faces

func _digest(mesh: ArrayMesh) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	for key in [Mesh.ARRAY_VERTEX, Mesh.ARRAY_NORMAL, Mesh.ARRAY_TEX_UV]: hash.update(mesh.surface_get_arrays(0)[key].to_byte_array())
	return hash.finish().hex_encode()

func _check(condition: bool, message: String) -> bool:
	if condition: return true
	push_error("WALL_ASSET_CHECK_FAILED " + message)
	get_tree().quit(1)
	return false
