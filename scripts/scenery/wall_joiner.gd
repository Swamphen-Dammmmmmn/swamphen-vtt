extends RefCounted

const Generator = preload("res://scripts/scenery/wall_generator.gd")
const Parameters = preload("res://scripts/scenery/wall_parameters.gd")
const Assembly = preload("res://scripts/scenery/wall_assembly.gd")
const EPS := 0.0001

# Descriptors contain parameters + a yaw/translation transform. Logical endpoints
# remain on the grid; only mesh/collision profiles change, so undo restores joins.
static func prepare(walls: Array[Dictionary]) -> Dictionary:
	var cuts: Array[Vector2] = []
	var log_joins: Array[Array] = []
	var endpoints: Array[Dictionary] = []
	for i in walls.size():
		if not walls[i].has_all(["parameters","transform"]) or not walls[i].parameters is Dictionary or not walls[i].transform is Transform3D:
			return {"ok":false,"message":"墙体须包含参数字典和三维变换"}
		if not walls[i].transform.is_finite(): return {"ok":false,"message":"墙体变换须为有限数值"}
		if walls[i].has("openings") and not walls[i].openings is Array:
			return {"ok":false,"message":"墙体门窗定义须为数组"}
		var p: Dictionary = walls[i].parameters
		var error := Parameters.validate(p)
		if not error.is_empty(): return {"ok": false, "message": error}
		var transform: Transform3D = walls[i].transform
		var yaw := transform.basis.get_euler().y
		if not transform.basis.is_equal_approx(Basis(Vector3.UP, yaw)) or not is_zero_approx(transform.origin.y) or absf(yaw / (PI * 0.5) - roundf(yaw / (PI * 0.5))) > EPS:
			return {"ok": false, "message": "墙体接缝只支持地面上的正交摆放"}
		cuts.append(Vector2.ZERO)
		log_joins.append([{},{}])
		for end in 2:
			endpoints.append({"wall": i, "end": end, "point": transform * Vector3(p.length * Parameters.FEET * end, 0, 0),
				"away": transform.basis.x * (1.0 if end == 0 else -1.0)})
	for a in walls.size():
		for b in range(a + 1, walls.size()):
			var ta: Transform3D = walls[a].transform
			var tb: Transform3D = walls[b].transform
			var la := float(walls[a].parameters.length) * Parameters.FEET
			var lb := float(walls[b].parameters.length) * Parameters.FEET
			var delta := tb.origin - ta.origin
			if absf(ta.basis.x.dot(tb.basis.x)) > 1.0 - EPS:
				if absf(delta.dot(ta.basis.z)) > EPS: continue
				var first := delta.dot(ta.basis.x)
				var last := (delta + tb.basis.x * lb).dot(ta.basis.x)
				if minf(la, maxf(first, last)) - maxf(0, minf(first, last)) > EPS:
					return {"ok": false, "message": "墙段重叠，请沿格线接到墙端"}
			else:
				var along_a := delta.dot(ta.basis.x)
				var along_b := (-delta).dot(tb.basis.x)
				if along_a < -EPS or along_a > la + EPS or along_b < -EPS or along_b > lb + EPS: continue
				if (along_a > EPS and along_a < la - EPS) or (along_b > EPS and along_b < lb - EPS):
					return {"ok": false, "message": "请将墙端对齐；本轮先支持直线与90度转角，暂不支持墙中接入"}
	var corners := 0
	for a in endpoints.size():
		var matches: Array[int] = []
		for b in endpoints.size():
			if a != b and endpoints[a].point.distance_to(endpoints[b].point) < EPS: matches.append(b)
		if matches.size() > 1: return {"ok": false, "message": "同一端点目前支持两面墙衔接，请错开多墙接点"}
		if matches.is_empty() or matches[0] < a: continue
		var first: Dictionary = endpoints[a]
		var second: Dictionary = endpoints[matches[0]]
		var dot := float(first.away.dot(second.away))
		if dot > 1.0 - EPS: return {"ok": false, "message": "墙体在接点处方向重叠"}
		if dot < -1.0 + EPS: continue # Flat ends meet for a straight continuation.
		if absf(dot) > EPS: return {"ok": false, "message": "本轮转角支持90度衔接"}
		for pair in [[first, second], [second, first]]:
			var current: Dictionary = pair[0]
			var other: Dictionary = pair[1]
			var transform: Transform3D = walls[current.wall].transform
			var ratio := float(walls[other.wall].parameters.thickness) / float(walls[current.wall].parameters.thickness)
			var slope := float(other.away.dot(transform.basis.z)) * (1.0 if current.end == 0 else -1.0) * ratio
			var cut := cuts[current.wall]
			cut[current.end] = slope
			cuts[current.wall] = cut
			if Parameters.is_logs(walls[current.wall].parameters.surface) and Parameters.is_logs(walls[other.wall].parameters.surface):
				log_joins[current.wall][current.end] = {"half_depth":float(walls[other.wall].parameters.thickness)*Parameters.FEET*0.5,
					"height":float(walls[other.wall].parameters.height)*Parameters.FEET,
					"even_through":absf(transform.basis.x.x)>0.5,"bark":walls[other.wall].parameters.surface=="logs_bark"}
				if walls[other.wall].parameters.surface=="logs_squared": log_joins[current.wall][current.end]["squared"]=true
		corners += 1
	return {"ok":true,"message":"","cuts":cuts,"log_joins":log_joins,"corners":corners}

static func build(walls: Array[Dictionary]) -> Dictionary:
	var context := prepare(walls)
	if not context.ok: return context
	var cuts: Array = context.cuts
	var log_joins: Array = context.log_joins
	var parts: Array[Dictionary] = []
	for i in walls.size():
		var joins: Array = log_joins[i] if Parameters.is_logs(walls[i].parameters.surface) else []
		var result: Dictionary
		if walls[i].has("openings"):
			result=await Assembly.build(walls[i].parameters,walls[i].openings,cuts[i],walls[i].transform,joins)
		else:
			result=await Generator.build(walls[i].parameters,cuts[i],walls[i].transform,joins)
		if not result.ok: return result
		parts.append(result)
	return {"ok": true, "message": "", "parts": parts, "corners": context.corners}
