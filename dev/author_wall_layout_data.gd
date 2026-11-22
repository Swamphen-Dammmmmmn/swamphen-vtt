extends Node

# Offline layout/geometry authoring checks only: no input, player scene or physics world.
const Data = preload("res://scripts/scenery/wall_layout_data.gd")
const Query = preload("res://scripts/scenery/wall_surface_query.gd")
const W = preload("res://scripts/scenery/wall_parameters.gd")
const P = preload("res://scripts/scenery/opening_parameters.gd")
const Assembly = preload("res://scripts/scenery/wall_assembly.gd")
const Joiner = preload("res://scripts/scenery/wall_joiner.gd")
var _errors: Array[String] = []
var _checks := 0
var _products := 0
@export_file("*.json") var report_path := "res://artifacts/wall-opening-layout-2026-10-25/data-check.json"

func _ready() -> void:
	var wall := W.defaults(0,"gray")
	wall.length=15.0
	var door := P.defaults()
	door.offset=-4.0
	var layout := {"version":1,"walls":[{"id":"hall","parameters":wall,"transform":Transform3D.IDENTITY,
		"openings":[{"id":"door-a","spec":door}]}]}
	check(Data.validate(layout).ok,"valid complete layout")
	var serialized := Data.to_json(layout)
	check(serialized.ok,"encode")
	var decoded := Data.from_json(serialized.get("text",""))
	if not decoded.ok: print("DECODE_ERROR=",decoded.message)
	check(decoded.ok and decoded.get("layout",{})==layout,"lossless JSON round trip")
	var bad := layout.duplicate(true)
	bad.version=99
	check(not Data.validate(bad).ok,"unknown version rejected")
	bad=layout.duplicate(true)
	bad.walls[0].unexpected=true
	check(not Data.validate(bad).ok,"unknown field rejected")
	bad=layout.duplicate(true)
	bad.walls[0].openings.append(bad.walls[0].openings[0].duplicate(true))
	check(not Data.validate(bad).ok,"duplicate ID rejected")
	var raised := layout.duplicate(true)
	raised.walls[0].openings[0].spec.sill=1.0
	check(Data.validate(raised).ok,"elevated door accepted")
	var query := Query.pick(layout,Vector3(0.7,0.7,5),Vector3(0,0,-1))
	check(query.ok and query.wall_id=="hall" and query.opening_id=="door-a","pick aperture on logical surface")
	var projection := Query.project(layout.walls[0],Vector3(1,1,5),Vector3(0,0,-1),1)
	check(projection.ok and projection.point_feet.is_equal_approx(Vector2(5,5)),"known 5ft coordinate")
	check(not Query.project(layout.walls[0],Vector3.ZERO,Vector3.RIGHT,1).ok,"parallel ray rejected")
	var other := layout.duplicate(true)
	other.walls[0].transform=Transform3D(Basis(Vector3.UP,PI*0.5),Vector3(2,0,3))
	var ray_start: Vector3 = other.walls[0].transform*Vector3(1,1,5)
	var ray_dir: Vector3 = other.walls[0].transform.basis*Vector3(0,0,-1)
	projection=Query.project(other.walls[0],ray_start,ray_dir,1)
	check(projection.ok and projection.point_feet.is_equal_approx(Vector2(5,5)),"rotated wall coordinates")
	# Explicit boundary cases and portable format rejection, without a player scene.
	for mutation in ["overlap","edge","top","wrong-type","scale","floating-wall","unknown-opening"]:
		bad=layout.duplicate(true)
		match mutation:
			"overlap":
				var duplicate: Dictionary = bad.walls[0].openings[0].duplicate(true)
				duplicate.id="other-door"
				bad.walls[0].openings.append(duplicate)
			"edge": bad.walls[0].openings[0].spec.offset=-7.0
			"top": bad.walls[0].openings[0].spec.sill=10.0
			"wrong-type": bad.walls[0].openings[0].spec.width="3"
			"scale": bad.walls[0].transform.basis=Basis.from_scale(Vector3(2,1,1))
			"floating-wall": bad.walls[0].transform.origin.y=1.0
			"unknown-opening": bad.walls[0].openings[0].spec.unexpected=true
		check(not Data.validate(bad).ok,"reject "+mutation)
	check(not Data.from_json('{"version":1.5,"walls":[]}').ok,"fractional version rejected")
	check(not Data.from_json('{"version":1,"walls":[],"extra":0}').ok,"unknown JSON field rejected")
	check(Data.from_json('{"version":1.0,"walls":[]}').ok,"JSON integral float version accepted")
	var color_layout := layout.duplicate(true)
	color_layout.walls[0].parameters.color=Color(0.123456789,0.456789123,0.999123456,1.0)
	color_layout.walls[0].openings[0].spec.glass_color=Color(0.6,0.7,0.8,0.123456789)
	var color_json := Data.to_json(color_layout)
	check(Data.from_json(color_json.text).layout==color_layout,"unquantized RGBA round trip")
	var nearer := layout.duplicate(true)
	var second: Dictionary = nearer.walls[0].duplicate(true)
	second.id="nearer"
	second.openings=[]
	second.transform.origin.z=2.0
	nearer.walls.append(second)
	query=Query.pick(nearer,Vector3(0.7,0.7,5),Vector3(0,0,-1))
	check(query.ok and query.wall_id=="nearer","nearest logical wall occludes far aperture")
	for surface in W.SURFACES:
		var host := W.defaults(0,surface)
		host.length=15.0
		for preset in ["wood_door","wood_window"]:
			var spec := P.defaults(preset)
			if preset=="wood_door": spec.sill=1.0
			var built := await Assembly.build(host,[spec])
			check(built.ok,"build elevated/mounted product "+surface+" "+preset)
			if built.ok:
				_products+=1
				check(built.collision.get_faces().size()>0 and built.attachments.size()==1,"mesh/collision product present")
	# Joined asset authoring, not editing operations or game interaction.
	var first := W.defaults(0,"planks_horizontal")
	first.length=15.0
	var turn := W.defaults(0,"planks_vertical")
	turn.length=10.0
	var specs: Array[Dictionary] = [{"parameters":first,"openings":[P.defaults("wood_window")],"transform":Transform3D.IDENTITY},
		{"parameters":turn,"openings":[],"transform":Transform3D(Basis(Vector3.UP,PI*0.5),Vector3(3,0,0))}]
	var joined := await Joiner.build(specs)
	check(joined.ok and joined.corners==1,"shared corner analysis and build")
	var restored := await Assembly.build(first,[])
	check(restored.ok and restored.attachments.is_empty() and restored.openings.is_empty(),"empty definition produces intact wall")
	check(_products==W.SURFACES.size()*2,"all material/product sections reached")
	print("WALL_LAYOUT_DATA_CHECK checks=",_checks," products=",_products," errors=",_errors.size())
	for error in _errors: push_error(error)
	var file := FileAccess.open(report_path,FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":_checks,"products":_products,"errors":_errors},"\t"))
	get_tree().quit(0 if _errors.is_empty() else 1)

func check(value: bool, message: String) -> void:
	_checks+=1
	if not value: _errors.append(message)
