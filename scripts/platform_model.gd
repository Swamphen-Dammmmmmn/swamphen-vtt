extends RefCounted
const Ground = preload("res://scripts/ground_material.gd")
const Grass = preload("res://scripts/grass_patch.gd")
const Water = preload("res://scripts/water_material.gd")

static func build(data: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Platform"
	var width := float(data["width_feet"])/5.0
	var length := float(data["length_feet"])/5.0
	var thickness := float(data["thickness_feet"])/5.0
	var top := float(data["top_feet"])/5.0
	# Bounds may expand in negative directions; the grid reference stays fixed.
	var origin: Vector2 = data.get("bounds_origin_feet",data["grid_origin_feet"])/5.0
	var center := Vector3(origin.x+width/2.0,top,origin.y+length/2.0)
	var body := MeshInstance3D.new()
	body.name = "Base"
	var box := BoxMesh.new()
	box.size = Vector3(width,thickness,length)
	body.mesh = box
	body.position = center-Vector3(0,thickness/2.0,0)
	var side := StandardMaterial3D.new()
	side.albedo_color = Color("8996a6")
	side.roughness = 0.95
	body.material_override = side
	root.add_child(body)
	var surface := MeshInstance3D.new()
	surface.name = "Surface"
	var plane := PlaneMesh.new()
	plane.size = Vector2(width,length)
	surface.mesh = plane
	surface.position = center+Vector3(0,0.002,0)
	var kind: String = data["material"]
	var material := Water.create() if kind == "water" else Ground.create(kind,Vector2(center.x,center.z))
	if kind == "water": material.set_shader_parameter("half_extent_feet",Vector2(width,length)*2.5)
	else: material.set_shader_parameter("relief_feet",0.0)
	surface.material_override = material
	root.add_child(surface)
	var blades := Grass.new()
	blades.name = "GrassBlades"
	blades.area = Rect2(origin,Vector2(width,length))
	blades.position.y = top+0.003
	blades.exclusion_radius = 0.0
	blades.legend_area = Rect2()
	blades.streaming = true
	blades.visible = kind=="grass"
	if kind=="grass": blades.bind_ground(material)
	root.add_child(blades)
	root.set_meta("platform_data",data.duplicate(true))
	return root
