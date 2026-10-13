extends RefCounted
const Landing = preload("res://scripts/platform_landing.gd")

static func segments(data: Dictionary, editor_mode := true) -> Dictionary:
	var occupied := Landing.cells(data)
	var edges := {}
	for cell: Vector2i in occupied:
		edges[Vector3i(cell.x,cell.y,0)] = true
		edges[Vector3i(cell.x,cell.y+1,0)] = true
		edges[Vector3i(cell.x,cell.y,1)] = true
		edges[Vector3i(cell.x+1,cell.y,1)] = true
	var solid: Array[Vector2] = []
	var dashed: Array[Vector2] = []
	for edge: Vector3i in edges:
		var a := Vector2(edge.x,edge.y)
		var b := a+(Vector2.RIGHT if edge.z==0 else Vector2.DOWN)
		solid.append(a)
		solid.append(b)
	if editor_mode:
		var bounds := Landing.bounds(data)
		for z in range(bounds.position.y,bounds.end.y+1):
			for x in range(bounds.position.x,bounds.end.x):
				if not edges.has(Vector3i(x,z,0)): _dash(dashed,Vector2(x,z),Vector2(x+1,z))
		for x in range(bounds.position.x,bounds.end.x+1):
			for z in range(bounds.position.y,bounds.end.y):
				if not edges.has(Vector3i(x,z,1)): _dash(dashed,Vector2(x,z),Vector2(x,z+1))
	return {"solid":solid,"dashed":dashed}

static func _dash(target: Array[Vector2], a: Vector2, b: Vector2) -> void:
	for start in [0.08,0.58]:
		target.append(a.lerp(b,start))
		target.append(a.lerp(b,start+0.3))
