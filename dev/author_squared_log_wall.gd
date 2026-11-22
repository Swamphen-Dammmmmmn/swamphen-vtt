extends "res://dev/author_round_log_wall.gd"

const Opening = preload("res://scripts/scenery/opening_parameters.gd")
const Assembly = preload("res://scripts/scenery/wall_assembly.gd")
const LayoutData = preload("res://scripts/scenery/wall_layout_data.gd")

func _ready() -> void:
	# Keep asset-authoring jobs out of the foreground; the actual preview stays visible.
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MINIMIZED)
	print("SQUARED_TIMBER_AUTHORING_START")
	await super._ready()

# Independent expected specification; never reads production profile constants.
func _profile_knots() -> Array:
	return [0.0,0.08,0.5,0.92,1.0]

func _section_spec(_row: int, _bark: bool) -> Array:
	return [0.9,1.0,1.0,1.0,0.9]

func _additional_checks() -> bool:
	print("SQUARED_TIMBER_MIXED_CHECK_START")
	var mixed := 0
	for other in ["logs_round","logs_bark"]:
		for yaw in 4:
			for ea in 2:
				for eb in 2:
					for unequal in 2:
						var a := _recipe(1)
						var b := Parameters.defaults(2,other)
						if unequal:
							a.thickness=0.75
							b.thickness=1.5
						var ba := Basis(Vector3.UP,yaw*PI*0.5)
						var bb := Basis(Vector3.UP,(yaw+1)*PI*0.5)
						var ta := Transform3D(ba,-ba.x*ea)
						var tb := Transform3D(bb,-bb.x*eb)
						var descriptors: Array[Dictionary] = [{"parameters":a,"transform":ta},{"parameters":b,"transform":tb}]
						var joined := await Joiner.build(descriptors)
						if not _check(joined.ok,"Mixed timber corner refused"): return false
						for i in 2:
							if not _inspect(joined.parts[i],descriptors[i].parameters,true): return false
						# Check contact throughout each profile, including bevel transitions.
						for course in [2,3]:
							var receiver := 1 if (course%2==0)==(absf(ba.x.x)>0.5) else 0
							var own: Dictionary = descriptors[receiver]
							var neighbor: Dictionary = descriptors[1-receiver]
							var end: int = ea if receiver==0 else eb
							var vertices: PackedVector3Array = joined.parts[receiver].mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
							var to_neighbor: Transform3D = neighbor.transform.affine_inverse()*own.transform
							for t in [0.04,0.08,0.12,0.18,0.35,0.5,0.7,0.82,0.88,0.92,0.96]:
								var y: float = (course+t)*0.2
								var extent := float(neighbor.parameters.thickness)*0.1*_section_at(neighbor.parameters.surface,t,course)
								var own_extent := float(own.parameters.thickness)*0.1*_section_at(own.parameters.surface,t,course)
								for side in [-0.5,0.0,0.5]:
									var found := INF if end==0 else -INF
									for index in range(0,vertices.size(),3):
										var hit = Geometry3D.segment_intersects_triangle(Vector3(-1,y,side*own_extent),Vector3(2,y,side*own_extent),vertices[index],vertices[index+1],vertices[index+2])
										if hit!=null: found=minf(found,hit.x) if end==0 else maxf(found,hit.x)
									if not _check(absf(found-(extent if end==0 else 1.0-extent))<0.00001,"Mixed profile contact gap "+str([other,yaw,ea,eb,course,t,found,extent])): return false
							for vertex in vertices:
								var t: float = vertex.y/0.2-course
								if t<=0.00001 or t>=0.99999: continue
								var extent := float(neighbor.parameters.thickness)*0.1*_section_at(neighbor.parameters.surface,t,course)
								if not _check(absf((to_neighbor*vertex).z)>=extent-0.00001,"Mixed corner penetrates neighbor"): return false
						mixed+=1
						if mixed%16==0: print("SQUARED_TIMBER_MIXED_CHECK_PROGRESS=",mixed)
	var assemblies := 0
	for thickness in [0.75,1.0,1.5]:
		for preset in ["wood_door","wood_window"]:
			var wall := _recipe()
			wall.thickness=thickness
			var spec := Opening.defaults(preset)
			var built := await Assembly.build(wall,[spec])
			if not _check(built.ok and built.attachments.size()==1,"Complete opening assembly refused"): return false
			var legacy := _recipe(1 if preset=="wood_door" else 2)
			legacy.thickness=thickness
			if not _inspect(built,legacy): return false
			assemblies+=1
	var layout := {"version":1,"walls":[{"id":"timber","parameters":_recipe(),"transform":Transform3D.IDENTITY,
		"openings":[{"id":"window","spec":Opening.defaults("wood_window")}]}]}
	var encoded := LayoutData.to_json(layout)
	if not _check(encoded.ok and LayoutData.from_json(encoded.get("text","")).get("layout",{})==layout,"Squared timber layout conversion failed"): return false
	for context in [[{"half_depth":0.1,"height":2.0,"even_through":true,"squared":"yes"},{}],
		[{"half_depth":0.1,"height":2.0,"even_through":true,"squared":true,"bark":true},{}]]:
		if not _check(not (await Generator.build(_recipe(),Vector2.ZERO,Transform3D.IDENTITY,context)).ok,"Invalid squared neighbor context accepted"): return false
	var file := FileAccess.open("res://artifacts/squared-log-wall-2026-10-25/integration-report.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"mixed_corners":mixed,"complete_assemblies":assemblies,"profile_samples_per_course":11,"layout_roundtrip":true,"gameplay_tested":false},"\t"))
	print("SQUARED_TIMBER_INTEGRATION_COMPLETE mixed_corners=",mixed," assemblies=",assemblies)
	return true

# Expected volume uses independent mathematical integration. Two-point Gaussian
# integration is exact for the product of two linear profiles between these knots.
func _expected_volume(p: Dictionary, result: Dictionary = {}) -> float:
	var pattern: Vector2 = result.get("pattern",Vector2(0,1))
	var length := float(p.length)*0.2
	var height := float(p.height)*0.2
	var area := _section_area(p.surface,0,length,0,height,pattern)
	if int(p.kind)!=0:
		var left := length*0.5+float(p.opening_offset)*0.2-float(p.opening_width)*0.1
		var bottom := float(p.sill)*0.2 if int(p.kind)==2 else 0.0
		area-=_section_area(p.surface,left,left+float(p.opening_width)*0.2,bottom,bottom+float(p.opening_height)*0.2,pattern)
	var width := float(p.thickness)*0.2
	var volume := area*width
	var joins: Array = result.get("log_joins",[])
	for end in mini(2,joins.size()):
		var join: Dictionary = joins[end]
		if join.is_empty(): continue
		var neighbor := "logs_squared" if join.get("squared",false) else ("logs_bark" if join.get("bark",false) else "logs_round")
		var until := minf(height,float(join.height))
		for row in ceili(until/0.2):
			var low := row*0.2
			var high := minf(until,low+0.2)
			var own := _section_integral(p.surface,"",low,high,row)
			var product := _section_integral(p.surface,neighbor,low,high,row)
			var through: bool = (row%2==0)==bool(join.even_through)
			volume+=width*((float(join.half_depth)+0.04)*own if through else -float(join.half_depth)*product)
			var along := pattern.x+pattern.y*(0.0 if end==0 else length)+posmod(row,2)
			if absf(along-snappedf(along,2.0))<0.00001: volume+=width*own*0.025*0.003
	return volume

func _section_area(kind: String,x0: float,x1: float,y0: float,y1: float,pattern: Vector2) -> float:
	var area := 0.0
	for row in range(floori(y0/0.2),ceili(y1/0.2)):
		var integral := _section_integral(kind,"",maxf(y0,row*0.2),minf(y1,(row+1)*0.2),row)
		var a := pattern.x+pattern.y*x0+posmod(row,2)
		var b := pattern.x+pattern.y*x1+posmod(row,2)
		var left := minf(a,b)
		var right := maxf(a,b)
		var groove := 0.0
		for joint in range(floori(left/2.0)-1,ceili(right/2.0)+1): groove+=_tent_area(right-joint*2.0)-_tent_area(left-joint*2.0)
		area+=integral*((x1-x0)-0.025*groove)
	return area

func _section_integral(kind: String,other: String,low: float,high: float,row: int) -> float:
	var total := 0.0
	var knots := [0.0,0.08,0.18,0.5,0.82,0.92,1.0]
	for i in knots.size()-1:
		var a := maxf(low,row*0.2+float(knots[i])*0.2)
		var b := minf(high,row*0.2+float(knots[i+1])*0.2)
		if b<=a: continue
		var midpoint := (a+b)*0.5
		var radius := (b-a)*0.5/sqrt(3.0)
		for y in [midpoint-radius,midpoint+radius]:
			var t: float = y/0.2-row
			total+=(b-a)*0.5*_section_at(kind,t,row)*(1.0 if other.is_empty() else _section_at(other,t,row))
	return total

func _section_at(kind: String,t: float,row: int) -> float:
	if kind=="logs_squared":
		if t<0.08: return 0.9+0.1*t/0.08
		if t>0.92: return 1.0-0.1*(t-0.92)/0.08
		return 1.0
	var values := [0.32,0.82,1.0,0.82,0.32]
	if kind=="logs_bark":
		var inset: float = [0.0,0.012,0.006,0.018,0.010,0.004,0.015,0.008][posmod(row,8)]
		values[1]*=1.0-inset*0.8
		values[2]*=1.0-inset
		values[3]*=1.0-inset*0.6
	var knots := [0.0,0.18,0.5,0.82,1.0]
	for i in 4:
		if t<=knots[i+1]: return lerpf(values[i],values[i+1],(t-knots[i])/(knots[i+1]-knots[i]))
	return 0.32
