extends "res://dev/author_wall_kit.gd"

const Materials = preload("res://scripts/scenery/wall_material.gd")

# Asset-only checks, no scene input or gameplay actions.
func _ready() -> void:
	output_directory = "res://artifacts/wall-vertical-grooves-2026-10-24/wood/"
	if not _check(DirAccess.make_dir_recursive_absolute(output_directory) == OK, "Cannot create timber inspection output"): return
	var seam_probe := await Generator.build(_recipe())
	if not _check(seam_probe.ok, "Cannot inspect butt-joint relief"): return
	var panel_depth := _front_depth(seam_probe.mesh, Vector2(0.45, 0.3))
	var joint_depth := _front_depth(seam_probe.mesh, Vector2(0.5, 0.3))
	var alternating_depth := _front_depth(seam_probe.mesh, Vector2(0.5, 0.1))
	if not _check(panel_depth - joint_depth > 0.0025 and absf(alternating_depth - panel_depth) < 0.00001,
		"Vertical joint has no geometric recess / wrong half-board row: " + str([panel_depth, joint_depth, alternating_depth])): return
	# Non-grid translations and all cardinal directions retain the same world seam.
	for yaw in 4:
		var basis := Basis(Vector3.UP,yaw*PI*0.5)
		var direction := roundf(basis.x.x+basis.x.z)
		var shifted := await Generator.build(_recipe(),Vector2.ZERO,Transform3D(basis,Vector3(0.25,0,0)))
		if not _check(shifted.ok,"Shifted wall refused"): return
		var seam_x: float = 0.25 if direction > 0 else 0.75
		if not _check(_front_depth(shifted.mesh,Vector2(seam_x+0.05,0.3))-_front_depth(shifted.mesh,Vector2(seam_x,0.3)) > 0.0025,
			"Translated / reversed wall groove lost world phase"): return
	var records: Array = []
	for thickness in [0.25, 0.5]:
		for kind in 3:
			var p := _recipe(kind)
			p.thickness = thickness
			var result := await Generator.build(p)
			if not _check(result.ok, "Timber Boolean failed"): return
			if not _inspect(result, p): return
			if not _check(result.mesh.surface_get_material(0) is ShaderMaterial, "Timber shader was lost during bake"): return
			var tinted := Generator.recolor(result, Color("667744"))
			if not _check(tinted.ok and Materials.color_of(result.mesh.surface_get_material(0)) == p.color and Materials.color_of(tinted.mesh.surface_get_material(0)) == Color("667744") and _digest(result.mesh) == _digest(tinted.mesh), "Timber recolor polluted mesh or old material"): return
			Generator.clear_cache()
			var again := await Generator.build(p)
			if not _check(again.ok and _digest(again.mesh) == _digest(result.mesh), "Uncached timber bake is not deterministic"): return
			var body := Generator.instantiate_wall(result)
			for child in body.get_children(): child.owner = body
			var packed := PackedScene.new()
			var code := packed.pack(body)
			if code == OK: code = ResourceSaver.save(packed, output_directory + "wall_%d_%s.scn" % [kind, str(thickness).replace(".", "_")], ResourceSaver.FLAG_COMPRESS)
			body.free()
			if not _check(code == OK, "Cannot save timber candidate"): return
			records.append({"kind": kind, "thickness_feet": thickness, "triangles": result.triangles,
				"bounds": str(result.bounds), "geometry_sha256": _digest(result.mesh)})
	# A full-width panel must have real geometric grooves, not merely painted stripes.
	var solid := await Generator.build(_recipe())
	var vertices: PackedVector3Array = solid.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var min_depth := INF
	var max_depth := 0.0
	for point in vertices:
		min_depth = minf(min_depth, absf(point.z))
		max_depth = maxf(max_depth, absf(point.z))
	if not _check(max_depth - min_depth > 0.0025 and min_depth > 0.02, "Grooves have no relief or cut through the wall core"): return
	# Fixed design dimensions, and a partially cut final plank, use independent analytic volume.
	var partial := _recipe(2)
	partial.height = 9.3
	partial.sill = 2.3
	partial.opening_height = 3.7
	var partial_result := await Generator.build(partial)
	if not _check(partial_result.ok, "Partial plank recipe refused"): return
	if not _inspect(partial_result, partial): return
	var corner_count := await _inspect_corners()
	if corner_count < 0: return
	# Two panels must have precisely the same physical boundary as one ten-foot wall.
	var two_entries: Array[Dictionary] = [
		{"parameters": _recipe(), "transform": Transform3D.IDENTITY},
		{"parameters": _recipe(), "transform": Transform3D(Basis.IDENTITY, Vector3.RIGHT)}]
	var two := await Joiner.build(two_entries)
	if not _check(two.ok, "Straight timber continuation failed"): return
	var edge_a := _edge_profile(two.parts[0].mesh, 1.0)
	var edge_b := _edge_profile(two.parts[1].mesh, 0.0)
	if not _check(edge_a == edge_b, "Plank profiles restart differently at module boundary"): return
	for child in get_tree().root.get_children():
		if not _check(not child is CSGShape3D, "Temporary Boolean node left in scene"): return
	var file := FileAccess.open(output_directory + "geometry-report.json", FileAccess.WRITE)
	if not _check(file != null, "Cannot write timber report"): return
	file.store_string(JSON.stringify({"candidates": records, "corner_cases": corner_count,
		"vertical_relief_checked": true, "half_board_stagger_checked": true, "translated_cardinal_phases_checked": 4,
		"partial_plank_checked": true, "continuation_profiles_match": true,
		"groove_depth_world": max_depth - min_depth, "core_half_thickness_world": min_depth,
		"checks": ["manifold", "analytic_volume", "opening_clear", "collision_matches", "material_isolation", "uncached_deterministic", "no_temporary_csg"]}, "\t"))
	file.close()
	print("HORIZONTAL_PLANKS_ASSET_CHECK_COMPLETE candidates=6 corners=", corner_count, " straight_profiles=true partial_plank=true vertical_relief=true half_stagger=true shifted_phases=4 groove_depth=", max_depth - min_depth)
	get_tree().quit()

func _recipe(kind := 0) -> Dictionary:
	return Parameters.defaults(kind, "planks_horizontal")

func _expected_volume(p: Dictionary, result: Dictionary = {}) -> float:
	# Independent integration of the specified V-groove cross sections. No mesh sampling.
	var pattern: Vector2 = result.get("pattern",Vector2(0,1))
	var length := float(p.length)*0.2
	var height := float(p.height)*0.2
	var area := _rectangle_area(0,length,0,height,pattern)
	if int(p.kind) != 0:
		var center := length*0.5 + float(p.opening_offset)*0.2
		var half_width := float(p.opening_width)*0.1
		var bottom := float(p.sill)*0.2 if int(p.kind) == 2 else 0.0
		area -= _rectangle_area(center-half_width,center+half_width,bottom,bottom+float(p.opening_height)*0.2,pattern)
	return area*float(p.thickness)*0.2

func _rectangle_area(x0: float, x1: float, y0: float, y1: float, pattern: Vector2) -> float:
	var along0 := pattern.x+pattern.y*x0
	var along1 := pattern.x+pattern.y*x1
	var left := minf(along0,along1)
	var right := maxf(along0,along1)
	var groove_integral := 0.0
	for row in range(floori(y0/0.2),ceili(y1/0.2)):
		var bottom := row*0.2
		var top := bottom+0.2
		var cuts: Array[float] = [maxf(y0,bottom),minf(y1,top)]
		var offset := posmod(row,2)*0.5
		var extra: Array[float] = [bottom+0.004,top-0.004]
		for edge in [left+offset,right+offset]:
			var distance := absf(edge-roundf(edge))
			if distance < 0.004:
				extra.append(bottom+distance)
				extra.append(top-distance)
		for y in extra:
			if y > cuts[0]+0.00000001 and y < cuts[1]-0.00000001: cuts.append(y)
		cuts.sort()
		for i in cuts.size()-1:
			var a := cuts[i]
			var b := cuts[i+1]
			# Each interval is quadratic: Simpson integrates it exactly.
			groove_integral += (b-a)/6.0*(_cross_area(left,right,a,bottom,top,offset)+4*_cross_area(left,right,(a+b)*0.5,bottom,top,offset)+_cross_area(left,right,b,bottom,top,offset))
	return (x1-x0)*(y1-y0)-0.12*groove_integral

func _cross_area(left: float, right: float, y: float, bottom: float, top: float, offset: float) -> float:
	var horizontal := maxf(0,1-minf(y-bottom,top-y)/0.004)
	var integral := horizontal*(right-left)
	var radius := 0.004*(1-horizontal)
	for k in range(floori(left+offset)-1,ceili(right+offset)+2):
		integral += _tent_integral(right+offset-k,radius)-_tent_integral(left+offset-k,radius)
	return integral

func _tent_integral(x: float, radius: float) -> float:
	var t := clampf(x,-radius,radius)
	if t <= 0: return (radius*t+0.5*t*t+0.5*radius*radius)/0.004
	return (0.5*radius*radius+radius*t-0.5*t*t)/0.004

func _edge_profile(mesh: ArrayMesh, x: float) -> Array:
	var points: Dictionary = {}
	for point in mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]:
		if absf(point.x - x) < 0.00001: points["%d,%d" % [roundi(point.y * 100000), roundi(point.z * 100000)]] = true
	var keys := points.keys()
	keys.sort()
	return keys

func _front_depth(mesh: ArrayMesh, at: Vector2) -> float:
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var closest := -INF
	for i in range(0, vertices.size(), 3):
		var hit = Geometry3D.segment_intersects_triangle(Vector3(at.x, at.y, 2), Vector3(at.x, at.y, -2), vertices[i], vertices[i+1], vertices[i+2])
		if hit != null: closest = maxf(closest, hit.z)
	return closest
