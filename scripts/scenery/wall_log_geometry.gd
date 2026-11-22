extends RefCounted

# Ten-sided section: four bevels on each side and flat bearing faces.
const PROFILE_Y := [0.0,0.18,0.5,0.82,1.0]
const PROFILE_DEPTH := [0.32,0.82,1.0,0.82,0.32]
const SQUARED_PROFILE_Y := [0.0,0.08,0.5,0.92,1.0]
const SQUARED_PROFILE_DEPTH := [0.9,1.0,1.0,1.0,0.9]
const BARK_COURSE_INSET := [0.0,0.012,0.006,0.018,0.010,0.004,0.015,0.008]
const BARK_PROFILE_WEIGHT := [0.0,0.8,1.0,0.6,0.0]
const LOG_LENGTH := 2.0 # Ten feet; alternate courses shift five feet.
const COURSE_HEIGHT := 0.2 # One-foot courses stay aligned across wall thicknesses.
const JOINT_HALF_WIDTH := 0.006
const JOINT_DEPTH := 0.025
const TAIL := 0.04 # 0.2 feet beyond the neighbouring log's outside face.

static func profile(t: float,bark := false,course := 0,squared := false) -> float:
	var levels: Array = SQUARED_PROFILE_Y if squared else PROFILE_Y
	var depths: Array = SQUARED_PROFILE_DEPTH if squared else PROFILE_DEPTH
	for i in levels.size()-1:
		if t <= levels[i+1]:
			var a: float = depths[i]
			var b: float = depths[i+1]
			if bark:
				var inset: float = BARK_COURSE_INSET[posmod(course,BARK_COURSE_INSET.size())]
				a *= 1.0-inset*BARK_PROFILE_WEIGHT[i]
				b *= 1.0-inset*BARK_PROFILE_WEIGHT[i+1]
			return lerpf(a,b,(t-levels[i])/(levels[i+1]-levels[i]))
	return depths.back()

static func solid(length: float, height: float, half_depth: float, pattern: Vector2,
		slopes: Vector2, joins: Array, material: Material,bark := false,squared := false) -> CSGCombiner3D:
	var body := CSGCombiner3D.new()
	body.calculate_tangents = false
	var pitch := COURSE_HEIGHT
	var profile_levels: Array = (SQUARED_PROFILE_Y if squared else PROFILE_Y).duplicate()
	for join: Dictionary in joins:
		if join.is_empty(): continue
		var neighbor_levels: Array = SQUARED_PROFILE_Y if join.get("squared",false) else PROFILE_Y
		for level in neighbor_levels:
			if not profile_levels.has(level): profile_levels.append(level)
	profile_levels.sort()
	var xs: Array[float] = [0.0,length]
	for k in range(floori((pattern.x-length)/LOG_LENGTH)-2,ceili((pattern.x+length)/LOG_LENGTH)+3):
		for parity in 2:
			for delta in [-JOINT_HALF_WIDTH,0.0,JOINT_HALF_WIDTH]:
				var u: float = (k*LOG_LENGTH+parity*LOG_LENGTH*0.5+delta-pattern.x)/pattern.y
				if u > 0.0000001 and u < length-0.0000001: xs.append(u)
	# End deformation never reaches a door/window: it stays within the end pier.
	var margin := Vector2(absf(slopes.x)*half_depth,absf(slopes.y)*half_depth)+Vector2.ONE*0.025
	for i in 2:
		if i < joins.size() and not joins[i].is_empty():
			margin[i] = float(joins[i].half_depth)+TAIL+0.025
	for u in [margin.x,length-margin.y]:
		if u > 0.0000001 and u < length-0.0000001: xs.append(u)
	xs.sort()
	# Shared scalar levels may coincide with join margins; keep one exact vertex.
	var unique: Array[float] = []
	for x in xs:
		if unique.is_empty() or absf(unique.back()-x) > 0.0000001: unique.append(x)
	for course in ceili(height/pitch):
		var bottom := course*pitch
		var top := minf(height,bottom+pitch)
		var splits: Array[float] = [bottom,top]
		for join: Dictionary in joins:
			if not join.is_empty() and float(join.height) > bottom+0.000001 and float(join.height) < top-0.000001:
				splits.append(float(join.height))
		splits.sort()
		for segment in splits.size()-1:
			var low := splits[segment]
			var high := splits[segment+1]
			if high-low < 0.0000001: continue
			var ys: Array[float] = [low,high]
			for t in profile_levels:
				var y: float = bottom+t*pitch
				if y > low+0.0000001 and y < high-0.0000001: ys.append(y)
			ys.sort()
			var tool := SurfaceTool.new()
			tool.begin(Mesh.PRIMITIVE_TRIANGLES)
			for side in [-1.0,1.0]:
				for j in ys.size()-1:
					for i in unique.size()-1:
						_quad(tool,_point(unique[i],ys[j],side,length,half_depth,course,pattern,slopes,joins,margin,(low+high)*0.5,bark,squared),
							_point(unique[i+1],ys[j],side,length,half_depth,course,pattern,slopes,joins,margin,(low+high)*0.5,bark,squared),
							_point(unique[i+1],ys[j+1],side,length,half_depth,course,pattern,slopes,joins,margin,(low+high)*0.5,bark,squared),
							_point(unique[i],ys[j+1],side,length,half_depth,course,pattern,slopes,joins,margin,(low+high)*0.5,bark,squared),side>0)
			for end in 2:
				var u: float = 0.0 if end==0 else length
				for j in ys.size()-1:
					_quad(tool,_point(u,ys[j],-1,length,half_depth,course,pattern,slopes,joins,margin,(low+high)*0.5,bark,squared),
						_point(u,ys[j],1,length,half_depth,course,pattern,slopes,joins,margin,(low+high)*0.5,bark,squared),
						_point(u,ys[j+1],1,length,half_depth,course,pattern,slopes,joins,margin,(low+high)*0.5,bark,squared),
						_point(u,ys[j+1],-1,length,half_depth,course,pattern,slopes,joins,margin,(low+high)*0.5,bark,squared),end==0)
			for end in 2:
				var y: float = low if end==0 else high
				for i in unique.size()-1:
					_quad(tool,_point(unique[i],y,-1,length,half_depth,course,pattern,slopes,joins,margin,(low+high)*0.5,bark,squared),
						_point(unique[i+1],y,-1,length,half_depth,course,pattern,slopes,joins,margin,(low+high)*0.5,bark,squared),
						_point(unique[i+1],y,1,length,half_depth,course,pattern,slopes,joins,margin,(low+high)*0.5,bark,squared),
						_point(unique[i],y,1,length,half_depth,course,pattern,slopes,joins,margin,(low+high)*0.5,bark,squared),end==0)
			tool.set_material(material)
			var row := CSGMesh3D.new()
			row.mesh = tool.commit()
			row.material = material
			row.calculate_tangents = false
			body.add_child(row)
	return body

static func _point(u: float, y: float, side: float, length: float, radius: float, course: int,
		pattern: Vector2, slopes: Vector2, joins: Array, margin: Vector2, band_height: float,bark: bool,squared: bool) -> Vector3:
	var t := clampf(y/COURSE_HEIGHT-course,0.0,1.0)
	var f := profile(t,bark,course,squared)
	var along := pattern.x+pattern.y*u+posmod(course,2)*LOG_LENGTH*0.5
	var seam := absf(fposmod(along+LOG_LENGTH*0.5,LOG_LENGTH)-LOG_LENGTH*0.5)
	var joint_strength := 1.0
	for end in 2:
		if end < joins.size() and not joins[end].is_empty() and band_height < float(joins[end].height):
			# A through-log must remain whole across the corner contact footprint.
			var distance := u if end==0 else length-u
			joint_strength = minf(joint_strength,clampf((distance-float(joins[end].half_depth)-TAIL)/0.025,0.0,1.0))
	var z := side*radius*f*(1.0-JOINT_DEPTH*maxf(0.0,1.0-seam/JOINT_HALF_WIDTH)*joint_strength)
	var x := u
	for end in 2:
		var weight := maxf(0.0,1.0-(u if end==0 else length-u)/margin[end])
		if end < joins.size() and not joins[end].is_empty():
			var join: Dictionary = joins[end]
			var through: bool = (course%2==0)==bool(join.even_through)
			# Neighbouring walls share the same course pitch; its curved side is
			# evaluated at this height, so the receiving end follows it exactly.
			var neighbor_profile := profile(t,bool(join.get("bark",false)),course,bool(join.get("squared",false)))
			var offset: float = -(float(join.half_depth)+TAIL) if through else float(join.half_depth)*neighbor_profile
			if band_height >= float(join.height): offset = 0.0
			x += (1.0 if end==0 else -1.0)*offset*weight
		else:
			x += slopes[end]*z*weight
	return Vector3(x,y,z)

static func _quad(tool: SurfaceTool,a: Vector3,b: Vector3,c: Vector3,d: Vector3,reverse: bool) -> void:
	for points in [[a,b,c],[a,c,d]]:
		if reverse: points.reverse()
		var normal: Vector3 = (points[2]-points[0]).cross(points[1]-points[0]).normalized()
		for point: Vector3 in points:
			tool.set_normal(normal)
			tool.set_uv(Vector2(point.x,point.y))
			tool.add_vertex(point)
