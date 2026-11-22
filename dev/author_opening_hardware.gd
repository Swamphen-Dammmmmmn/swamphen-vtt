extends Node

# Offline asset-data inspection of opening hardware and timber UV ranges.
# Builds real attachment products only; no input, gameplay or save writes.
const P = preload("res://scripts/scenery/opening_parameters.gd")
const Builder = preload("res://scripts/scenery/opening_attachment_builder.gd")
const Bank = preload("res://scripts/scenery/plank_texture_bank.gd")
const EPS := 0.00002
@export_dir var output_directory := "res://artifacts/cc-opening-detail-2026-10-25/"
var _errors: Array[String] = []
var _metrics: Array[Dictionary] = []

func _ready() -> void:
	var count := 0
	for preset in ["wood_window","wood_door"]:
		for width in [1.0,3.0,6.0]:
			for hinge in ["left","right"]:
				for swing in ["front","back"]:
					for mounting in ["front","center","back"]:
						for thickness in [0.05,0.30]:
							var spec := P.defaults(preset)
							spec.width=width
							spec.hinge=hinge
							spec.swing=swing
							spec.mounting=mounting
							var data := Builder.new().build(spec,Rect2(Vector2(0.37,0.6),Vector2(width,spec.height)*0.2),thickness)
							if not data.ok:
								_errors.append(data.message)
								continue
							_inspect(data,"%s w=%s %s/%s/%s t=%s"%[preset,width,hinge,swing,mounting,thickness])
							count+=1
	var report := {"ok":_errors.is_empty(),"recipes":count,"error_count":_errors.size(),"errors":_errors.slice(0,80),"metrics":_metrics}
	var file := FileAccess.open(output_directory.path_join("hardware-check.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	if not _errors.is_empty(): push_error("OPENING_HARDWARE_CHECK: "+_errors[0])
	print("OPENING_HARDWARE_CHECK ok=",_errors.is_empty()," recipes=",count," errors=",_errors.size())
	get_tree().quit(0 if _errors.is_empty() else 1)

func _inspect(data: Dictionary, label: String) -> void:
	var window: bool = data.spec.preset.ends_with("window")
	var hinge: Vector3 = data.hinge
	var wood: Array[AABB] = []      # wall coordinates at angle 0, axis-aligned members only
	var leaf_wood: Array[AABB] = [] # moving frame
	var stiles: Array[AABB] = []
	var glass: Array[AABB] = []
	var fixed_wood: Array[AABB] = []
	var metal: Array[Dictionary] = []
	for part in data.parts:
		var box: AABB = part.bounds
		var straight: bool = part.transform.basis.is_equal_approx(Basis.IDENTITY)
		var wall_box := AABB(box.position+(hinge if part.group=="moving" else Vector3.ZERO),box.size)
		if part.material=="glass": glass.append(box)
		elif part.material=="metal": metal.append({"name":part.name,"group":part.group,"box":box,"wall":wall_box})
		elif straight:
			wood.append(wall_box)
			if part.group=="moving":
				leaf_wood.append(box)
				if part.name.begins_with("SashSide"): stiles.append(box)
			else: fixed_wood.append(wall_box)
	var leaf_area := _union_xy(leaf_wood)
	var fixed_metal := 0
	var widest := 0.0
	for item in metal:
		var box: AABB = item.box
		if item.group=="fixed":
			fixed_metal+=1
			for other in fixed_wood:
				if _overlap(item.wall,other): _errors.append(label+": fixed hinge leaf buried in frame "+item.name)
			continue
		var barrel := absf(box.get_center().x)<0.00001
		if barrel:
			for other in fixed_wood:
				if _overlap(item.wall,other): _errors.append(label+": hinge barrel embedded in fixed frame "+item.name)
			continue
		widest=maxf(widest,box.size.x)
		for pane in glass:
			if _overlap_xy(box,pane): _errors.append(label+": metal covers glass "+item.name)
		if window:
			var seated := false
			for stile in stiles: seated=seated or _inside_xy(box,stile)
			if not seated: _errors.append(label+": metal leaves sash stile "+item.name)
		elif not _inside_xy(box,leaf_area): _errors.append(label+": metal leaves door leaf "+item.name)
		for other in leaf_wood:
			if _overlap(box,other): _errors.append(label+": metal buried in leaf timber "+item.name)
	if bool(data.spec.hardware) and fixed_metal<2: _errors.append(label+": hinges lack fixed-side leaves")
	# Every metal piece touches timber, or touches a piece that does.
	var touching: Dictionary = {}
	for item in metal:
		for other in wood:
			if item.wall.grow(EPS).intersects(other): touching[item.name]=true
	for item in metal:
		if touching.has(item.name): continue
		var linked := false
		for other in metal:
			if touching.has(other.name) and item.wall.grow(EPS).intersects(other.wall): linked=true
		if not linked: _errors.append(label+": floating metal "+item.name)
	_uv(data,label)
	if label.contains("left/front/front t=0.05"):
		_metrics.append({"recipe":label,"sash_stile_feet":(stiles[0].size.x/0.2) if not stiles.is_empty() else 0.0,
			"widest_leaf_metal_feet":widest/0.2,"fixed_metal_parts":fixed_metal})

# Side-grain UVs stay inside one board tile unless the vertex is flagged as folded.
func _uv(data: Dictionary, label: String) -> void:
	for key in ["fixed_mesh","moving_mesh"]:
		var mesh: ArrayMesh = data[key]
		for surface in mesh.get_surface_count():
			if not mesh.surface_get_material(surface) is ShaderMaterial: continue
			var arrays := mesh.surface_get_arrays(surface)
			var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
			var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
			var bad := 0
			for i in uvs.size():
				if colors[i].g>0.5 or colors[i].b>0.5: continue
				var tile := Vector2(uvs[i].x/Bank.BOARD_LENGTH,uvs[i].y/Bank.BOARD_HEIGHT)
				if tile.x<-EPS or tile.x>1+EPS or tile.y<-EPS or tile.y>1+EPS: bad+=1
			if bad>0: _errors.append("%s: %d timber vertices cross a texture tile boundary (%s)"%[label,bad,key])

func _overlap(a: AABB, b: AABB) -> bool:
	var inter := a.intersection(b)
	return inter.size.x>EPS and inter.size.y>EPS and inter.size.z>EPS

func _overlap_xy(a: AABB, b: AABB) -> bool:
	return minf(a.end.x,b.end.x)-maxf(a.position.x,b.position.x)>EPS and minf(a.end.y,b.end.y)-maxf(a.position.y,b.position.y)>EPS

func _inside_xy(a: AABB, b: AABB) -> bool:
	return a.position.x>=b.position.x-EPS and a.end.x<=b.end.x+EPS and a.position.y>=b.position.y-EPS and a.end.y<=b.end.y+EPS

func _union_xy(boxes: Array[AABB]) -> AABB:
	var result: AABB = boxes[0]
	for box in boxes: result=result.merge(box)
	return result
