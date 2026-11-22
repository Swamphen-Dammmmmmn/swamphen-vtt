extends RefCounted

# Improve skinny CSG triangles by flipping interior diagonals of coplanar convex
# quads. No vertices, boundary edges, holes or faces are removed or displaced.
const MIN_DOUBLE_AREA := 0.000001

static func improve(mesh: ArrayMesh) -> ArrayMesh:
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var points := PackedVector3Array()
	var lookup: Dictionary = {}
	var triangles: Array[PackedInt32Array] = []
	for i in range(0, vertices.size(), 3):
		var ids := PackedInt32Array()
		for j in 3:
			var point := vertices[i+j]
			if not lookup.has(point):
				lookup[point] = points.size()
				points.append(point)
			ids.append(int(lookup[point]))
		triangles.append(ids)
	var changed := false
	for pass_index in 12:
		var edges: Dictionary = {}
		for i in triangles.size():
			for edge in 3:
				var a := triangles[i][edge]
				var b := triangles[i][(edge+1)%3]
				var key := Vector2i(mini(a,b), maxi(a,b))
				if not edges.has(key): edges[key] = []
				edges[key].append(Vector2i(i, triangles[i][(edge+2)%3]))
		var touched: Dictionary = {}
		var flips := 0
		for key: Vector2i in edges:
			var adjacent: Array = edges[key]
			if adjacent.size() != 2: continue
			var first: int = adjacent[0].x
			var second: int = adjacent[1].x
			if touched.has(first) or touched.has(second): continue
			var old_min := minf(_cross(points, triangles[first]).length(), _cross(points, triangles[second]).length())
			if old_min > MIN_DOUBLE_AREA: continue
			var normal := _cross(points, triangles[first]).normalized()
			var other := _cross(points, triangles[second]).normalized()
			if normal.dot(other) < 0.999999: continue
			var a := key.x
			var b := key.y
			var c: int = adjacent[0].y
			var d: int = adjacent[1].y
			if absf((points[d]-points[a]).dot(normal)) > 0.0000001: continue
			var diagonal := points[d] - points[c]
			if diagonal.cross(points[a]-points[c]).dot(normal) * diagonal.cross(points[b]-points[c]).dot(normal) >= 0: continue
			var next_first := _oriented(points, PackedInt32Array([c,d,a]), normal)
			var next_second := _oriented(points, PackedInt32Array([d,c,b]), normal)
			var new_min := minf(_cross(points, next_first).length(), _cross(points, next_second).length())
			if new_min <= maxf(MIN_DOUBLE_AREA, old_min * 1.1): continue
			triangles[first] = next_first
			triangles[second] = next_second
			touched[first] = true
			touched[second] = true
			flips += 1
		if flips == 0: break
		changed = true
	if not changed: return mesh
	var tool := SurfaceTool.new()
	tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	for triangle in triangles:
		var normal := _cross(points, triangle).normalized()
		for index in triangle:
			var point := points[index]
			tool.set_normal(normal)
			var uv := Vector2(point.x, point.y)
			if absf(normal.x) > 0.9: uv = Vector2(point.z, point.y)
			elif absf(normal.y) > 0.9: uv = Vector2(point.x, point.z)
			tool.set_uv(uv)
			tool.add_vertex(point)
	tool.set_material(mesh.surface_get_material(0))
	return tool.commit()

static func _cross(points: PackedVector3Array, triangle: PackedInt32Array) -> Vector3:
	return (points[triangle[2]] - points[triangle[0]]).cross(points[triangle[1]] - points[triangle[0]])

static func _oriented(points: PackedVector3Array, triangle: PackedInt32Array, normal: Vector3) -> PackedInt32Array:
	if _cross(points, triangle).dot(normal) < 0:
		var second := triangle[1]
		triangle[1] = triangle[2]
		triangle[2] = second
	return triangle
