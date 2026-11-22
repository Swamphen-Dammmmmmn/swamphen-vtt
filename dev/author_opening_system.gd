extends Node

# Asset-production checks only: no input injection, scene gameplay or save writes.
const OUTPUT := "res://artifacts/opening-system-2026-10-25/"
@export_dir var output_directory := OUTPUT
var _failures: Array[String] = []
var _records: Array[Dictionary] = []
var _suite_completed := false
const Wall = preload("res://scripts/scenery/wall_parameters.gd")
const Generator = preload("res://scripts/scenery/wall_generator.gd")
const P = preload("res://scripts/scenery/opening_parameters.gd")
const Assembly = preload("res://scripts/scenery/wall_assembly.gd")
const Joiner = preload("res://scripts/scenery/wall_joiner.gd")
const Builder = preload("res://scripts/scenery/opening_attachment_builder.gd")
const LegacyInspector = preload("res://dev/author_wall_kit.gd")

func _ready() -> void:
	var path := "res://scripts/scenery/wall_opening_layout.gd"
	if not ResourceLoader.exists(path):
		_fail("Opening layout module is missing")
		_finish()
		return
	var layout = load(path)
	var wall = load("res://scripts/scenery/wall_parameters.gd").defaults(1)
	var holes: Array = layout.from_legacy(wall)
	_check(holes.size()==1 and holes[0].is_equal_approx(Rect2(0.2,0,0.6,1.4)), "Legacy door dimensions changed")
	wall.kind=0
	wall.length=15.0
	var pair: Array = [Rect2(0.2,0,0.6,1.4),Rect2(1.8,0.6,0.6,0.8)]
	_check(layout.validate(wall,pair).is_empty(), "Separated holes rejected")
	_check(not layout.validate(wall,[pair[0],pair[0]]).is_empty(), "Overlapping holes accepted")
	_check(not layout.validate(wall,[Rect2(-0.1,0,0.6,1.4)]).is_empty(), "Out-of-wall hole accepted")
	_check(not layout.validate(wall,[Rect2(0.2,0,0.6,NAN)]).is_empty(), "NaN hole accepted")
	_check(not layout.validate(wall,[Rect2(0.2,0,0.6,1.4)],Vector2(0.2,0)).is_empty(), "Unsafe corner hole accepted")
	await _parameters_and_geometry()
	_check(_suite_completed and _records.size()==12,"Asset inspection did not reach every section")
	_finish()

func _parameters_and_geometry() -> void:
	for preset in P.PRESETS:
		_check(P.validate(P.defaults(preset)).is_empty(),"Default preset refused: "+preset)
	for edit in [{"angle":NAN},{"width":INF},{"width":0.1},{"angle":111.0},{"hinge":"up"},{"seed":1.5},{"frame":1},{"unknown":3},{"glass":true},{"leaf":false}]:
		var spec := P.defaults()
		spec.merge(edit,true)
		_check(not P.validate(spec).is_empty(),"Bad attachment spec accepted: "+str(edit))
	var inspector := LegacyInspector.new()
	# Legacy mesh/collision checks applied to old five-material single holes.
	# Geometry hashes must also match the explicit-layout adapter.
	for surface in Wall.SURFACES:
		for kind in 3:
			var legacy := Wall.defaults(kind,surface)
			var old := await Generator.build(legacy)
			if not _check(old.ok,"Legacy wall refused: "+old.get("message","")): continue
			var raw := Wall.defaults(0,surface)
			var specs: Array = []
			if kind!=0: specs=[P.defaults("empty_door" if kind==1 else "empty_window")]
			var assembled := await Assembly.build(raw,specs)
			if not _check(assembled.ok,"Assembly refused: "+assembled.get("message","")): continue
			_check(inspector._digest(old.mesh)==inspector._digest(assembled.mesh),"Legacy/explicit opening geometry differs: "+str([surface,kind]))
			_check(old.collision.get_faces()==assembled.collision.get_faces(),"Legacy/assembly collision changed")
			for hole in assembled.openings: _check(not inspector._ray_hit(assembled.mesh.get_faces(),hole.get_center()),"A cut is visually blocked")
	# Independent analytical volume for an actual two-hole gray wall.
	var multi := Wall.defaults()
	multi.length=15.0
	var door := P.defaults()
	door.offset=-4.0
	var window := P.defaults("wood_window")
	window.offset=3.5
	var result := await Assembly.build(multi,[door,window])
	if _check(result.ok,"Multiple opening wall refused: "+result.get("message","")):
		_check(result.openings.size()==2 and result.attachments.size()==2,"Missing multi opening/attachments")
		# 15*10*0.5 - 3*7*0.5 - 3*4*0.5 = 58.5 ft³, world volume 0.468.
		_check(absf(_volume(result.mesh)-0.468)<0.00001,"Two-hole analytical volume mismatch")
		_closed(result.mesh)
		_check(inspector._face_keys(result.mesh.get_faces())==inspector._face_keys(result.collision.get_faces()),"Multi-hole collision differs from mesh")
		for hole in result.openings: _check(not inspector._ray_hit(result.mesh.get_faces(),hole.get_center()),"Multi-hole wall has blocked cut")
		var removed := await Assembly.build(multi,[])
		var original := await Generator.build(multi)
		_check(inspector._digest(removed.mesh)==inspector._digest(original.mesh),"Removing openings leaves stale cuts")
		var again := await Assembly.build(multi,[door,window])
		_check(inspector._digest(again.mesh)==inspector._digest(result.mesh),"Repeated assembly is not deterministic")
	_check(not (await Assembly.build(multi,[door,door])).ok,"Duplicate openings accepted")
	var near := P.defaults("wood_window")
	near.offset=-1.0
	_check(not (await Assembly.build(multi,[door,near])).ok,"Overlapping trim accepted")
	var door_wall := Wall.defaults()
	var plain_door := P.defaults("empty_door")
	_check(not (await Assembly.build(door_wall,[plain_door],Vector2(4.0,0))).ok,"Unsafe corner accepted")
	_check(not (await Assembly.build(Wall.defaults(0,"logs_round"),[P.defaults()],Vector2.ZERO,Transform3D.IDENTITY,[{"half_depth":Vector3.ONE},{}])).ok,"Invalid join context accepted")
	# First products across supported thicknesses; inspect generated data offline.
	for thickness in [0.25,0.5,0.75,1.0,1.5,3.0]:
		for preset in ["wood_door","wood_window"]:
			var spec := P.defaults(preset)
			var host := Wall.defaults()
			host.thickness=thickness
			var data := await Assembly.build(host,[spec])
			if not _check(data.ok,"Thickness refused: "+str([thickness,preset,data.get("message")])): continue
			var attachment: Dictionary = data.attachments[0]
			for key in ["fixed_mesh","moving_mesh","glass_mesh"]: _attributes(attachment[key])
			# Frame wood plus, when hardware is present, the fixed-side hinge leaves.
			_check(attachment.fixed_mesh.get_surface_count()==(2 if spec.hardware else 1),"Frame wood/metal batching incorrect")
			_check(attachment.moving_mesh.get_surface_count()==2,"Leaf wood/metal batching incorrect")
			for part in attachment.parts:
				if part.name.begins_with("Jamb"):
					_check(absf(part.bounds.size.z-(thickness*0.2+0.002))<0.00001,"Frame did not adapt to wall thickness")
			_check(attachment.spec.wood_color==spec.wood_color,"Attachment color mutated")
			var instance := Assembly.instantiate(data)
			_check(instance.get_child_count()==2,"Assembly lacks opening instance")
			_validate_bodies(instance)
			var wood: Material = attachment.fixed_mesh.surface_get_material(0)
			_check(wood.get_shader_parameter("board_colors")==load("res://scripts/scenery/plank_texture_bank.gd").COLORS,"Wood bank not shared")
			_records.append({"preset":preset,"wall_thickness_feet":thickness,"parts":attachment.parts.size(),"fixed_triangles":attachment.fixed_mesh.get_faces().size()/3,
				"moving_triangles":attachment.moving_mesh.get_faces().size()/3,"glass_triangles":attachment.glass_mesh.get_faces().size()/3})
			instance.free()
	# Both hinge sides and opening directions use the same pivot for wood/glass/shapes.
	for hinge in ["left","right"]:
		for swing in ["front","back"]:
			for mounting in ["front","center","back"]:
				var spec := P.defaults()
				spec.hinge=hinge
				spec.swing=swing
				spec.mounting=mounting
				spec.angle=90.0
				var data := Builder.new().build(spec,Rect2(0.2,0,0.6,1.4),0.2)
				var instance = load("res://scripts/scenery/opening_instance.gd").new()
				instance.configure(data)
				var leaf: StaticBody3D = instance.get_node("LeafPivot")
				var point: Vector3 = leaf.transform*Vector3(0.4 if hinge=="left" else -0.4,0,0)
				_check((point.z-data.hinge.z)*(1 if swing=="front" else -1)>0.39,"Leaf opens in wrong direction")
				_check(absf(point.x-data.hinge.x)<0.00001,"Pivot is displaced")
				_check(not instance.set_open_angle(NAN) and instance.get_open_angle()==90.0,"Invalid angle changed existing pose")
				instance.free()
	# Joiner consumes opening descriptors, keeps old neighboring walls supported.
	for surface in Wall.SURFACES:
		var host := Wall.defaults(0,surface)
		host.length=10.0
		var entries: Array[Dictionary] = [{"parameters":host,"openings":[P.defaults()],"transform":Transform3D.IDENTITY},
			{"parameters":Wall.defaults(0,surface),"transform":Transform3D(Basis(Vector3.UP,-PI*0.5),Vector3(2,0,0))}]
		var joined := await Joiner.build(entries)
		_check(joined.ok and joined.corners==1 and joined.parts[0].attachments.size()==1,"Joiner lost attachments or corner: "+surface)
	inspector.free()
	_suite_completed=true

func _volume(mesh: ArrayMesh) -> float:
	var faces := mesh.get_faces()
	var volume := 0.0
	for i in range(0,faces.size(),3): volume+=faces[i].dot(faces[i+2].cross(faces[i+1]))/6.0
	return volume

func _closed(mesh: ArrayMesh) -> void:
	var counts: Dictionary = {}
	var faces := mesh.get_faces()
	for i in range(0,faces.size(),3):
		for j in 3:
			var a := str((faces[i+j]*100000).round())
			var b := str((faces[i+(j+1)%3]*100000).round())
			var key := a+"|"+b if a<b else b+"|"+a
			counts[key]=counts.get(key,0)+1
	for key in counts: _check(counts[key]==2,"Boolean mesh is not closed: "+key)

func _attributes(mesh: ArrayMesh) -> void:
	for surface in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface)
		for v in arrays[Mesh.ARRAY_VERTEX]: _check(v.is_finite(),"Nonfinite attachment vertex")
		for n in arrays[Mesh.ARRAY_NORMAL]: _check(n.is_finite() and n.length()>0.99,"Invalid attachment normal")
		for uv in arrays[Mesh.ARRAY_TEX_UV]: _check(uv.is_finite(),"Invalid attachment UV")
		for value in arrays[Mesh.ARRAY_TANGENT]: _check(is_finite(value),"Invalid tangent")

func _validate_bodies(node: Node) -> void:
	if node is CollisionShape3D:
		_check(node.get_parent() is PhysicsBody3D,"Attachment collider not directly under a body")
		_check(node.scale.is_equal_approx(Vector3.ONE),"Collider uses non-uniform scaling")
	for child in node.get_children(): _validate_bodies(child)

func _check(condition: bool, message: String) -> bool:
	if not condition: _fail(message)
	return condition

func _fail(message: String) -> void:
	_failures.append(message)
	push_error("OPENING_ASSET_CHECK: "+message)

func _finish() -> void:
	var file := FileAccess.open(output_directory.path_join("asset-check.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"ok":_failures.is_empty(),"failures":_failures,"products":_records},"\t"))
	file.close()
	print("OPENING_ASSET_CHECK_COMPLETE ok=",_failures.is_empty())
	get_tree().quit(0 if _failures.is_empty() else 1)
