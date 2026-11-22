extends "res://dev/author_horizontal_planks.gd"

const Bank = preload("res://scripts/scenery/plank_texture_bank.gd")
const OUTPUT := "res://artifacts/vertical-planks-2026-10-24/"
@export_file("*.json") var report_path := OUTPUT+"geometry-report.json"

# Asset-only inspection; no simulated input or saves.
func _ready() -> void:
	output_directory = OUTPUT
	var wall := await Generator.build(_recipe())
	if not _check(wall.ok, "Vertical plank recipe refused: " + wall.get("message", "")): return
	var panel := _front_depth(wall.mesh, Vector2(0.1,0.3))
	if not _check(panel-_front_depth(wall.mesh,Vector2(0.2,0.3)) > 0.0025, "Longitudinal seam lacks physical relief"): return
	if not _check(panel-_front_depth(wall.mesh,Vector2(0.3,0.5)) > 0.0025 and absf(panel-_front_depth(wall.mesh,Vector2(0.1,0.5))) < 0.00001,
		"Adjacent columns must stagger by 2.5 feet"): return
	if not _check(panel-_front_depth(wall.mesh,Vector2(0.1,1.0)) > 0.0025, "Five-foot board end has no physical recess"): return
	# All cardinal rotations, non-grid translations and reversed column parity.
	var phases := 0
	for yaw in 4:
		for origin in [-0.07,0.25]:
			var basis := Basis(Vector3.UP,yaw*PI*0.5)
			var direction := roundf(basis.x.x+basis.x.z)
			var shifted := await Generator.build(_recipe(),Vector2.ZERO,Transform3D(basis,Vector3(origin,0,0)))
			if not _check(shifted.ok,"Translated vertical wall refused"): return
			var x: float = (0.0-origin)/direction
			while x < 0.05: x += 0.2
			if not _check(_front_depth(shifted.mesh,Vector2(x+0.05,0.3))-_front_depth(shifted.mesh,Vector2(x,0.3)) > 0.0025,
				"Longitudinal groove lost world position: "+str([yaw,origin,x])): return
			if not _inspect(shifted,_recipe()): return
			phases += 1
	var candidates: Array = []
	for thickness in [0.25,0.5]:
		for kind in 3:
			var p := _recipe(kind)
			p.thickness = thickness
			var result := await Generator.build(p)
			if not _check(result.ok,"Vertical Boolean wall refused"): return
			if not _inspect(result,p): return
			var material := result.mesh.surface_get_material(0) as ShaderMaterial
			if not _check(material != null and material.get_shader_parameter("vertical_planks") == true and material.get_shader_parameter("board_colors") == Bank.COLORS,
				"Vertical orientation / shared bank lost during Boolean bake"): return
			var tinted := Generator.recolor(result,Color("668877"))
			if not _check(tinted.ok and _digest(tinted.mesh) == _digest(result.mesh) and Materials.color_of(material) == p.color and Materials.color_of(tinted.mesh.surface_get_material(0)) == Color("668877"),"Recolor changed an old wall"): return
			Generator.clear_cache()
			var again := await Generator.build(p)
			if not _check(again.ok and _digest(again.mesh) == _digest(result.mesh),"Vertical bake is not deterministic"): return
			candidates.append({"kind":kind,"thickness_feet":thickness,"triangles":result.triangles,"geometry_sha256":_digest(result.mesh)})
	# Cropped columns / board ends around an off-grid opening and both mitered ends.
	var partial := _recipe(2)
	partial.merge({"length":7.3,"height":9.3,"sill":2.3,"opening_height":3.7,"opening_width":2.7,"opening_offset":0.2},true)
	var cropped := await Generator.build(partial)
	if not _check(cropped.ok,"Partial-board window refused"): return
	if not _inspect(cropped,partial): return
	var boundary_count := 0
	for kind in 3:
		for edits in [{"height":5.0,"opening_width":1.0,"opening_height":1.0,"sill":0.5},
			{"length":50.0,"height":30.0,"thickness":3.0,"opening_width":1.0,"opening_offset":24.0},
			{"length":7.0,"height":9.0,"opening_width":2.5,"opening_height":2.0,"opening_offset":-1.75,"sill":6.75}]:
			var p := _recipe(kind)
			p.merge(edits,true)
			var result := await Generator.build(p)
			if not _check(result.ok,"Vertical boundary dimensions refused: "+str(edits)): return
			if not _inspect(result,p): return
			boundary_count += 1
	var corners := await _inspect_corners()
	if corners < 0: return
	var straight: Array[Dictionary] = [{"parameters":_recipe(),"transform":Transform3D.IDENTITY},
		{"parameters":_recipe(),"transform":Transform3D(Basis.IDENTITY,Vector3.RIGHT)}]
	var two := await Joiner.build(straight)
	if not _check(two.ok and _edge_profile(two.parts[0].mesh,1.0) == _edge_profile(two.parts[1].mesh,0.0),"Vertical module profiles differ"): return
	for transform in [Transform3D(Basis(Vector3.UP,PI*0.25),Vector3.ZERO),Transform3D(Basis.IDENTITY,Vector3.UP)]:
		if not _check(not (await Generator.build(_recipe(),Vector2.ZERO,transform)).ok,"Unsupported timber placement accepted"): return
	# Literal examples from the agreed orientation: one foot width, five feet length.
	var even := Bank.board_at(0.1,0.49,1,0,true)
	var odd := Bank.board_at(0.3,0.49,1,0,true)
	if not _check(even.row == 0 and odd.row == 1 and absf(even.uv.x-0.49) < 0.00001 and absf(odd.uv.x-0.99) < 0.00001,"Texture coordinates do not follow vertical boards"): return
	if not _check(Bank.board_at(0.3,0.51,1,0,true).piece == 1 and Bank.board_at(0.1,0.51,1,0,true).piece == 0,"Texture joint is not at the physical butt joint"): return
	for child in get_tree().root.get_children():
		if not _check(not child is CSGShape3D,"Temporary Boolean retained"): return
	var file := FileAccess.open(report_path,FileAccess.WRITE)
	if not _check(file != null,"Cannot save vertical geometry report"): return
	file.store_string(JSON.stringify({"candidates":candidates,"corners":corners,"world_phase_cases":phases,"groove_depth_world":panel-_front_depth(wall.mesh,Vector2(0.2,0.3)),
		"boundary_recipes":boundary_count,"half_board_stagger":true,"partial_boards":true,"closed_mesh_normals_volume_collision":true,"recolor_isolated":true,"uncached_deterministic":true,"gameplay_tested":false},"\t"))
	print("VERTICAL_PLANKS_ASSET_CHECK_COMPLETE candidates=6 corners=",corners," phases=",phases," boundaries=",boundary_count," relief=true half_stagger=true partial=true")
	get_tree().quit()

func _recipe(kind := 0) -> Dictionary:
	return Parameters.defaults(kind, "planks_vertical")

func _rectangle_area(x0: float, x1: float, y0: float, y1: float, pattern: Vector2) -> float:
	# Independent analytic cross-section integral: rotate the established specification,
	# not the generated mesh, into board-length / board-width coordinates.
	var a := pattern.x+pattern.y*x0
	var b := pattern.x+pattern.y*x1
	return super._rectangle_area(y0,y1,minf(a,b),maxf(a,b),Vector2(0,1))
