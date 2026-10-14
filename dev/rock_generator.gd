extends RefCounted

# Development-only convex rock generator. Polygons retain one normal across
# their fan triangles, so triangulation does not introduce extra stone faces.
const FEET := 0.2
const EPS := 0.00001

static func build(values: Dictionary) -> ArrayMesh:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(values.seed)
	var noise := FastNoiseLite.new()
	noise.seed = int(values.seed) % 2147483647
	noise.frequency = 1.2
	var shape := int(values.shape)
	var variation := float(values.variation)
	var rounding := float(values.rounding)
	var profile := int(values.get("profile", 0))
	var faces: Array[PackedVector3Array] = _box()
	# Broad fractures around the sides; uneven spacing avoids a regular prism.
	var sides := 7 if shape == 1 else 9
	var phase := rng.randf_range(-PI, PI)
	for i in range(sides):
		var angle := phase + TAU * (float(i) + rng.randf_range(-0.18, 0.18)) / sides
		var slope := rng.randf_range(-0.32, 0.32)
		var normal := Vector3(cos(angle), slope, sin(angle)).normalized()
		var radius := 0.83 + noise.get_noise_3dv(normal * 2.0) * variation * 0.48
		faces = _clip(faces, normal, radius)
	# Different upper slopes and an off-centre crown give the mass a direction.
	var crown := Vector3(rng.randf_range(-0.22, 0.22), 1, rng.randf_range(-0.22, 0.22)).normalized()
	faces = _clip(faces, crown, 0.79 + rng.randf_range(-0.1, 0.1) * variation)
	for i in range(6):
		var angle := phase + TAU * (float(i) + rng.randf_range(-0.2, 0.2)) / 6.0
		var normal := Vector3(cos(angle), rng.randf_range(0.85, 1.55), sin(angle)).normalized()
		var radius := 0.83 + noise.get_noise_3dv(normal * 2.6) * variation * 0.38
		faces = _clip(faces, normal, radius)
	# The underside remains part of the closed mesh, with a broad bearing area.
	faces = _clip(faces, Vector3.DOWN, 0.64)
	for i in range(5):
		var angle := phase + TAU * float(i) / 5.0
		faces = _clip(faces, Vector3(cos(angle), -1.2, sin(angle)).normalized(), 0.8)
	# Structural cuts affect whole faces, rather than just surface noise.
	match profile:
		1:
			faces = _clip(faces, Vector3(-0.9, 1.0, 0.1).normalized(), 0.63)
		2:
			faces = _clip(faces, Vector3(-0.8, 1.0, 0.0).normalized(), 0.66)
			faces = _clip(faces, Vector3(0.8, 1.0, 0.0).normalized(), 0.66)
		3:
			faces = _clip(faces, Vector3(1.0, 0.7, 0.5).normalized(), 0.59)
		4:
			faces = _clip(faces, Vector3(-1.0, 0.6, 0.2).normalized(), 0.60)
			faces = _clip(faces, Vector3(0.2, 0.45, 1.0).normalized(), 0.72)
		5:
			for i in range(5):
				var angle := phase + TAU * float(i) / 5.0
				faces = _clip(faces, Vector3(cos(angle), 0.75, sin(angle)).normalized(), 0.72)
		6:
			for i in range(3):
				var angle := phase + TAU * float(i) / 3.0
				faces = _clip(faces, Vector3(cos(angle), 0.05, sin(angle)).normalized(), 0.55)
		7:
			faces = _clip(faces, Vector3(0.6, 0.0, 1.0).normalized(), 0.59)
			faces = _clip(faces, Vector3(-0.6, 0.0, -1.0).normalized(), 0.66)
		9:
			faces = _clip(faces, Vector3(1.0, 0.1, 1.0).normalized(), 0.47)
	if rounding > 0.001:
		faces = _bevel(faces, rounding, rng)
	if profile == 8:
		for face_index in range(faces.size()):
			var shifted := PackedVector3Array()
			for point in faces[face_index]:
				shifted.append(point + Vector3(point.y * 0.45, 0, point.y * -0.20))
			faces[face_index] = shifted
	var low := Vector3(INF, INF, INF)
	var high := Vector3(-INF, -INF, -INF)
	for face in faces:
		for point in face:
			low = low.min(point)
			high = high.max(point)
	var span := (high - low).max(Vector3.ONE * EPS)
	var dimensions := Vector3(float(values.width), float(values.height), float(values.depth)) * FEET
	var centre := (low + high) * 0.5
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for face in faces:
		var points := PackedVector3Array()
		for point in face:
			var p := (point - centre) / span * dimensions
			p.y = (point.y - low.y) / span.y * dimensions.y - dimensions.y * float(values.burial)
			points.append(p)
		var normal := _normal(points)
		if normal.length_squared() < EPS: continue
		for i in range(1, points.size() - 1):
			if (points[i] - points[0]).cross(points[i + 1] - points[0]).length_squared() < EPS * EPS: continue
			# Godot's front faces use clockwise winding.
			for index in [0, i + 1, i]:
				tool.set_normal(normal)
				tool.add_vertex(points[index])
	return tool.commit()

static func _box() -> Array[PackedVector3Array]:
	var faces: Array[PackedVector3Array] = []
	for axis in range(3):
		for sign_value in [-1.0, 1.0]:
			var normal := Vector3.ZERO
			normal[axis] = sign_value
			var u := normal.cross(Vector3.UP if axis != 1 else Vector3.RIGHT).normalized()
			var v := normal.cross(u)
			faces.append(PackedVector3Array([normal - u - v, normal + u - v, normal + u + v, normal - u + v]))
	return faces

static func _normal(points: PackedVector3Array) -> Vector3:
	var result := Vector3.ZERO
	for i in range(points.size()):
		result += points[i].cross(points[(i + 1) % points.size()])
	return result.normalized()

static func _clip(faces: Array[PackedVector3Array], normal: Vector3, distance: float) -> Array[PackedVector3Array]:
	var result: Array[PackedVector3Array] = []
	var cap: Array[Vector3] = []
	for face in faces:
		var output := PackedVector3Array()
		for i in range(face.size()):
			var a := face[i]
			var b := face[(i + 1) % face.size()]
			var da := normal.dot(a) - distance
			var db := normal.dot(b) - distance
			if da <= EPS: _append_unique(output, a)
			if (da < -EPS and db > EPS) or (da > EPS and db < -EPS):
				var hit := a.lerp(b, da / (da - db))
				_append_unique(output, hit)
				var found := false
				for point in cap:
					if point.distance_squared_to(hit) < EPS * EPS:
						found = true
						break
				if not found: cap.append(hit)
		# Remove a repeated closing vertex before triangulation.
		if output.size() > 2 and output[0].distance_squared_to(output[-1]) < EPS * EPS:
			output.resize(output.size() - 1)
		if output.size() >= 3 and _normal(output).length_squared() > EPS:
			result.append(output)
	if cap.size() >= 3:
		var centre := Vector3.ZERO
		for point in cap: centre += point
		centre /= float(cap.size())
		var u := normal.cross(Vector3.UP if absf(normal.y) < 0.9 else Vector3.RIGHT).normalized()
		var v := normal.cross(u)
		cap.sort_custom(func(a: Vector3, b: Vector3) -> bool:
			var aa := a - centre
			var bb := b - centre
			return atan2(aa.dot(v), aa.dot(u)) < atan2(bb.dot(v), bb.dot(u))
		)
		result.append(PackedVector3Array(cap))
	return result

static func _append_unique(points: PackedVector3Array, point: Vector3) -> void:
	if points.is_empty() or points[-1].distance_squared_to(point) > EPS * EPS:
		points.append(point)

static func _bevel(faces: Array[PackedVector3Array], amount: float, rng: RandomNumberGenerator) -> Array[PackedVector3Array]:
	var edges: Dictionary = {}
	for face in faces:
		var normal := _normal(face)
		for i in range(face.size()):
			var a := face[i]
			var b := face[(i + 1) % face.size()]
			var ak := "%.5f,%.5f,%.5f" % [a.x, a.y, a.z]
			var bk := "%.5f,%.5f,%.5f" % [b.x, b.y, b.z]
			var key := ak + "/" + bk if ak < bk else bk + "/" + ak
			if edges.has(key):
				edges[key].normals.append(normal)
			else:
				edges[key] = {"a": a, "b": b, "normals": [normal]}
	var result := faces
	for edge: Dictionary in edges.values():
		if edge.normals.size() != 2: continue
		var n1: Vector3 = edge.normals[0]
		var n2: Vector3 = edge.normals[1]
		if n1.y < -0.85 or n2.y < -0.85: continue
		var normal := (n1 + n2).normalized()
		var midpoint: Vector3 = (edge.a + edge.b) * 0.5
		var length: float = edge.a.distance_to(edge.b)
		var inset := minf(0.075 * amount * rng.randf_range(0.65, 1.15), length * 0.12)
		if inset > EPS:
			result = _clip(result, normal, normal.dot(midpoint) - inset)
	return result
