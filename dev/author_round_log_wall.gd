extends "res://dev/author_wall_kit.gd"

const Materials = preload("res://scripts/scenery/wall_material.gd")
const Bank = preload("res://scripts/scenery/plank_texture_bank.gd")
const BarkBank = preload("res://scripts/scenery/bark_texture_bank.gd")
const OUTPUT := "res://artifacts/round-log-wall-2026-10-24/"
@export var surface := "logs_round"
@export var minimum_relief := 0.065
@export_file("*.json") var report_path := OUTPUT+"geometry-report.json"

func _ready() -> void:
	var records: Array = []
	for thickness in [0.75,1.0,1.5]:
		for kind in 3:
			var p := _recipe(kind)
			p.thickness = thickness
			var result := await Generator.build(p)
			if not _check(result.ok,"Round log wall refused: "+result.get("message","")): return
			if not _inspect(result,p): return
			var material := result.mesh.surface_get_material(0) as ShaderMaterial
			if not _check(material != null and material.get_shader_parameter("board_colors")== (BarkBank.COLORS if surface=="logs_bark" else Bank.COLORS),"Logs must share the wood bank"): return
			var tinted := Generator.recolor(result,Color("667744"))
			if not _check(tinted.ok and _digest(tinted.mesh)==_digest(result.mesh) and Materials.color_of(material)==p.color and Materials.color_of(tinted.mesh.surface_get_material(0))==Color("667744"),"Recolor mutated existing logs"): return
			Generator.clear_cache()
			var again := await Generator.build(p)
			if not _check(again.ok and _digest(again.mesh)==_digest(result.mesh),"Uncached logs differ"): return
			records.append({"kind":kind,"thickness_feet":thickness,"triangles":result.triangles,"geometry_sha256":_digest(result.mesh)})
	var solid := await Generator.build(_recipe())
	var ridge := _front_depth(solid.mesh,Vector2(0.4,0.1))
	var valley := _front_depth(solid.mesh,Vector2(0.4,0.2))
	if not _check(ridge-valley>minimum_relief and valley>0.03,"Timber layers lack specified relief / closed bearing core"): return
	# The first 5-foot segment has a butt joint on only alternate courses.
	if not _check(absf(_front_depth(solid.mesh,Vector2(0.95,0.1))-_front_depth(solid.mesh,Vector2(0.999,0.1)))<0.00001 and _front_depth(solid.mesh,Vector2(0.95,0.3))-_front_depth(solid.mesh,Vector2(0.999,0.3))>0.001,
		"Ten-foot log ends do not stagger five feet"): return
	var partial := _recipe(2)
	partial.merge({"length":7.3,"height":9.3,"sill":2.3,"opening_width":2.7,"opening_height":3.7,"opening_offset":0.2},true)
	var cropped := await Generator.build(partial)
	if not _check(cropped.ok,"Partial-course opening refused"): return
	if not _inspect(cropped,partial): return
	var boundaries := 0
	for kind in 3:
		for edits in [{"height":5.0,"thickness":0.75,"opening_width":1.0,"opening_height":1.0,"sill":0.5},
			{"length":50.0,"height":30.0,"thickness":3.0,"opening_width":1.0,"opening_offset":24.0},
			{"length":7.0,"height":9.0,"thickness":1.5,"opening_width":2.5,"opening_height":2.0,"opening_offset":-1.75,"sill":6.75}]:
			var p := _recipe(kind)
			p.merge(edits,true)
			var result := await Generator.build(p)
			if not _check(result.ok,"Log boundary refused: "+str(edits)): return
			if not _inspect(result,p): return
			boundaries+=1
	var phases := 0
	for yaw in 4:
		var transform := Transform3D(Basis(Vector3.UP,yaw*PI*0.5),Vector3(-0.25,0,0.1))
		var shifted := await Generator.build(_recipe(),Vector2.ZERO,transform)
		if not _check(shifted.ok,"Translated log wall refused"): return
		if not _inspect(shifted,_recipe()): return
		phases += 1
	var corners := await _log_corners()
	if corners<0: return
	for invalid in [[{}],[{"half_depth":NAN,"height":2.0,"even_through":true},{}],[{"half_depth":0.1,"height":2.0,"even_through":0},{}],[{"half_depth":0.1,"height":2.0,"even_through":true,"unknown":1},{}]]:
		if not _check(not (await Generator.build(_recipe(),Vector2.ZERO,Transform3D.IDENTITY,invalid)).ok,"Malformed log join accepted"): return
	for child in get_tree().root.get_children():
		if not _check(not child is CSGShape3D,"Temporary log CSG retained"): return
	if not await _additional_checks(): return
	var file := FileAccess.open(report_path,FileAccess.WRITE)
	if not _check(file!=null,"Cannot save log report"): return
	file.store_string(JSON.stringify({"surface":surface,"candidates":records,"corners":corners,"phases":phases,"boundaries":boundaries,"partial_courses":true,
		"relief_world":ridge-valley,"bearing_half_depth":valley,"shared_arrays":true,"closed_mesh_normals_volume_collision":true,
		"recolor_isolated":true,"uncached_deterministic":true,"gameplay_tested":false},"\t"))
	print("ROUND_LOG_WALL_ASSET_CHECK_COMPLETE candidates=9 corners=",corners," phases=",phases," boundaries=",boundaries," relief=true partial=true surface=",surface)
	get_tree().quit()

func _recipe(kind := 0) -> Dictionary:
	return Parameters.defaults(kind,surface)

func _front_depth(mesh: ArrayMesh,at: Vector2) -> float:
	var closest := -INF
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	for i in range(0,vertices.size(),3):
		var hit = Geometry3D.segment_intersects_triangle(Vector3(at.x,at.y,2),Vector3(at.x,at.y,-2),vertices[i],vertices[i+1],vertices[i+2])
		if hit!=null: closest=maxf(closest,hit.z)
	return closest

func _log_corners() -> int:
	var count := 0
	for yaw in 4:
		for ea in 2:
			for eb in 2:
				for variant in (4 if surface=="logs_bark" else 3):
					var a := _recipe(variant%3)
					var b := _recipe((variant+1)%3)
					if variant==3: b=Parameters.defaults((variant+1)%3,"logs_round")
					if variant==2:
						a.thickness=0.75
						b.thickness=1.5
					var ba := Basis(Vector3.UP,yaw*PI*0.5)
					var bb := Basis(Vector3.UP,(yaw+1)*PI*0.5)
					var ta := Transform3D(ba,-ba.x*ea)
					var tb := Transform3D(bb,-bb.x*eb)
					var descriptors: Array[Dictionary] = [{"parameters":a,"transform":ta},{"parameters":b,"transform":tb}]
					var joined := await Joiner.build(descriptors)
					if not _check(joined.ok and joined.corners==1,"Interlocking corner refused: "+str([yaw,ea,eb,variant,joined.get("message")])): return -1
					for i in 2:
						if not _inspect(joined.parts[i],descriptors[i].parameters,true): return -1
					# At course centres the receiving end must exactly meet the through-log's
					# side at three cross-width samples, and reverse roles on the next course.
					for course in [2,3]:
						var receiver := 1 if (course%2==0)==(absf(ba.x.x)>0.5) else 0
						var end: int = ea if receiver==0 else eb
						var r := float(descriptors[1-receiver].parameters.thickness)*0.1
						var own_r := float(descriptors[receiver].parameters.thickness)*0.1
						var mesh: ArrayMesh = joined.parts[receiver].mesh
						var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
						var to_through: Transform3D = descriptors[1-receiver].transform.affine_inverse()*descriptors[receiver].transform
						for vertex in vertices:
							var t: float = vertex.y/0.2-course
							if t<=0.00001 or t>=0.99999: continue
							var f := _depth_spec(t,course,descriptors[1-receiver].parameters.surface=="logs_bark")
							if not _check(absf((to_through*vertex).z)>=r*f-0.00001,"Receiver penetrates through-log"): return -1
						for side in [-0.5,0.0,0.5]:
							var found := INF if end==0 else -INF
							for j in range(0,vertices.size(),3):
								var hit = Geometry3D.segment_intersects_triangle(Vector3(-1,(course+0.5)*0.2,side*own_r),Vector3(2,(course+0.5)*0.2,side*own_r),vertices[j],vertices[j+1],vertices[j+2])
								if hit!=null: found=minf(found,hit.x) if end==0 else maxf(found,hit.x)
							if not _check(absf(found-(r*_depth_spec(0.5,course,descriptors[1-receiver].parameters.surface=="logs_bark") if end==0 else 1-r*_depth_spec(0.5,course,descriptors[1-receiver].parameters.surface=="logs_bark")))<0.00001,"Receiving corner has a gap / overlap: "+str([yaw,ea,eb,variant,course,receiver,side,found,r])): return -1
					count+=1
	# Removing the neighbour must restore the original flat end, not retain a tail.
	var plain: Array[Dictionary] = [{"parameters":_recipe(),"transform":Transform3D.IDENTITY}]
	var restored := await Joiner.build(plain)
	if not _check(restored.ok and restored.parts[0].bounds.position.x==0 and is_equal_approx(restored.parts[0].bounds.end.x,1.0),"Removing neighbour retained interlocking ends"): return -1
	var room: Array[Dictionary] = []
	var positions := [Vector3.ZERO,Vector3.RIGHT,Vector3(1,0,-1),Vector3(0,0,-1)]
	for i in 4:
		room.append({"parameters":_recipe(i%3),"transform":Transform3D(Basis(Vector3.UP,i*PI*0.5),positions[i])})
	var joined_room := await Joiner.build(room)
	if not _check(joined_room.ok and joined_room.corners==4,"Log room did not close"): return -1
	for i in 4:
		if not _inspect(joined_room.parts[i],room[i].parameters,true): return -1
	# Unequal heights stop the lap at the actual neighbour height, leaving the
	# upper courses of the taller wall with ordinary flat ends.
	var short := _recipe()
	short.height=7.3
	var pair: Array[Dictionary] = [{"parameters":_recipe(),"transform":Transform3D.IDENTITY},
		{"parameters":short,"transform":Transform3D(Basis(Vector3.UP,PI*0.5),Vector3.RIGHT)}]
	var unequal := await Joiner.build(pair)
	if not _check(unequal.ok,"Unequal-height log corner refused"): return -1
	for i in 2:
		if not _inspect(unequal.parts[i],pair[i].parameters,true): return -1
	return count

func _expected_volume(p: Dictionary, result: Dictionary = {}) -> float:
	var pattern: Vector2 = result.get("pattern",Vector2(0,1))
	var length := float(p.length)*0.2
	var height := float(p.height)*0.2
	var area := _area(0,length,0,height,pattern,p.surface=="logs_bark")
	if int(p.kind)!=0:
		var left := length*0.5+float(p.opening_offset)*0.2-float(p.opening_width)*0.1
		var bottom := float(p.sill)*0.2 if int(p.kind)==2 else 0.0
		area -= _area(left,left+float(p.opening_width)*0.2,bottom,bottom+float(p.opening_height)*0.2,pattern,p.surface=="logs_bark")
	var volume := area*float(p.thickness)*0.2
	var joins: Array = result.get("log_joins",[])
	for end in mini(2,joins.size()):
		if joins[end].is_empty(): continue
		var join: Dictionary = joins[end]
		var until := minf(height,float(join.height))
		for row in ceili(until/0.2):
			var upper := minf(until,(row+1)*0.2)
			var lower := row*0.2
			var fy := _profile_integral(lower,upper,row,false,p.surface=="logs_bark")
			var fy2 := _profile_integral(lower,upper,row,true,p.surface=="logs_bark",bool(join.get("bark",false)))
			var through: bool = (row%2==0)==bool(join.even_through)
			volume += float(p.thickness)*0.2*((float(join.half_depth)+0.04)*fy if through else -float(join.half_depth)*fy2)
			# No butt recess across a corner's contact footprint.
			var along := pattern.x+pattern.y*(0.0 if end==0 else length)+posmod(row,2)
			if absf(along-snappedf(along,2.0))<0.00001:
				volume += float(p.thickness)*0.2*fy*0.025*0.003
	return volume

func _section_spec(row: int,bark: bool) -> Array:
	var depths := [0.32,0.82,1.0,0.82,0.32]
	if bark:
		var inset: float = [0.0,0.012,0.006,0.018,0.010,0.004,0.015,0.008][posmod(row,8)]
		depths[1] *= 1.0-inset*0.8
		depths[2] *= 1.0-inset
		depths[3] *= 1.0-inset*0.6
	return depths

func _profile_knots() -> Array:
	return [0.0,0.18,0.5,0.82,1.0]

func _additional_checks() -> bool:
	return true

func _depth_spec(t: float,row: int,bark: bool) -> float:
	var knots := _profile_knots()
	var depths := _section_spec(row,bark)
	for i in 4:
		if t<=knots[i+1]: return lerpf(depths[i],depths[i+1],(t-knots[i])/(knots[i+1]-knots[i]))
	return depths.back()

func _profile_integral(low: float,high: float,row: int,product: bool,own_bark := false,neighbor_bark := false) -> float:
	var knots := _profile_knots()
	var depths := _section_spec(row,own_bark)
	var other := _section_spec(row,neighbor_bark)
	var total := 0.0
	for i in 4:
		var a: float = maxf(low,row*0.2+knots[i]*0.2)
		var b: float = minf(high,row*0.2+knots[i+1]*0.2)
		if b<=a: continue
		var ta: float = ((a-row*0.2)/0.2-knots[i])/(knots[i+1]-knots[i])
		var tb: float = ((b-row*0.2)/0.2-knots[i])/(knots[i+1]-knots[i])
		var fa: float = lerpf(depths[i],depths[i+1],ta)
		var fb: float = lerpf(depths[i],depths[i+1],tb)
		if product:
			var ga: float = lerpf(other[i],other[i+1],ta)
			var gb: float = lerpf(other[i],other[i+1],tb)
			total += (b-a)/6.0*(fa*ga+(fa+fb)*(ga+gb)+fb*gb)
		else: total += (b-a)*(fa+fb)*0.5
	return total

func _area(x0: float,x1: float,y0: float,y1: float,pattern: Vector2,bark := false) -> float:
	# Integrate the specified ten-sided section and the independent 10-foot joint
	# triangle. This never reads mesh vertices or the geometry implementation.
	var total := 0.0
	for row in range(floori(y0/0.2),ceili(y1/0.2)):
		var knots := _profile_knots()
		var depths := _section_spec(row,bark)
		var y_area := 0.0
		for i in 4:
			var a: float = maxf(y0,row*0.2+knots[i]*0.2)
			var b: float = minf(y1,row*0.2+knots[i+1]*0.2)
			if b<=a: continue
			var fa: float = lerpf(depths[i],depths[i+1],((a-row*0.2)/0.2-knots[i])/(knots[i+1]-knots[i]))
			var fb: float = lerpf(depths[i],depths[i+1],((b-row*0.2)/0.2-knots[i])/(knots[i+1]-knots[i]))
			y_area += (b-a)*(fa+fb)*0.5
		var a := pattern.x+pattern.y*x0+posmod(row,2)
		var b := pattern.x+pattern.y*x1+posmod(row,2)
		var left := minf(a,b)
		var right := maxf(a,b)
		var groove := 0.0
		for joint in range(floori(left/2.0)-1,ceili(right/2.0)+1):
			groove += _tent_area(right-joint*2.0)-_tent_area(left-joint*2.0)
		total += y_area*((x1-x0)-0.025*groove)
	return total

func _tent_area(x: float) -> float:
	var t := clampf(x,-0.006,0.006)
	return t+t*t/0.012+0.003 if t<=0 else 0.003+t-t*t/0.012
