extends Node3D
## Development-only paint surface. Raw coverage and edge noise stay separate.

const Ground = preload("res://scripts/ground_material.gd")
const Water = preload("res://scripts/water_material.gd")
const Grass = preload("res://scripts/grass_patch.gd")
const BlendShader = preload("res://shaders/ground_blend.gdshader")
const RESOLUTION := 192
const AREA := Rect2(Vector2(18,-8),Vector2(16,16))
const HISTORY_LIMIT := 20
var coverage: Image
var effective: Image
var edge_noise: Image
var texture: ImageTexture
var shore_texture: ImageTexture
var water_snapshot: Dictionary = {}
var beach_snapshot := Color(-1,-1,-1)
var surface: ShaderMaterial
var grass: Node3D
var undo_stack: Array[Image] = []
var redo_stack: Array[Image] = []
var stroke_before: Image
var stroke_changed := false
var last_point := Vector2.ZERO
var has_last := false
var stroke_count := 0
var dirty_region := Rect2i()
signal changed

func _ready() -> void:
	coverage = Image.create(RESOLUTION,RESOLUTION,false,Image.FORMAT_RGBA8)
	effective = Image.create(RESOLUTION,RESOLUTION,false,Image.FORMAT_RGBA8)
	edge_noise = Image.create(RESOLUTION,RESOLUTION,false,Image.FORMAT_R8)
	var noise := FastNoiseLite.new()
	noise.seed = 470230
	noise.frequency = 1.5
	noise.fractal_octaves = 3
	for y in range(RESOLUTION):
		for x in range(RESOLUTION):
			var p := AREA.position+Vector2(x+0.5,y+0.5)/RESOLUTION*AREA.size
			var n := clampf(0.5+noise.get_noise_2d(p.x,p.y)*0.8,0,1)
			edge_noise.set_pixel(x,y,Color(n,n,n))
	surface = ShaderMaterial.new()
	surface.shader = BlendShader
	surface.set_shader_parameter("grass_masks",Ground.detail_texture("grass"))
	surface.set_shader_parameter("sand_masks",Ground.detail_texture("sand"))
	surface.set_shader_parameter("macro_mask",Ground.macro_texture())
	surface.set_shader_parameter("sand_microstructure",Ground.micro_texture())
	surface.set_shader_parameter("sand_grain_color",Ground.grain_color_texture())
	surface.set_shader_parameter("area_origin",AREA.position)
	surface.set_shader_parameter("wave_noise",Ground.macro_texture())
	surface.set_shader_parameter("beach_color",Ground.defaults("beach")["color"])
	Water.apply(surface,Water.defaults())
	var plane := PlaneMesh.new()
	plane.size = AREA.size
	var mesh := MeshInstance3D.new()
	mesh.mesh = plane
	mesh.position = Vector3(26,0.002,0)
	mesh.material_override = surface
	add_child(mesh)
	grass = Grass.new()
	grass.position.y = 0.002
	grass.area = AREA
	grass.exclusion_center = Vector2(26,0)
	grass.legend_area = Rect2(Vector2(18,5.5),Vector2(16,2.5))
	_show_example()
	grass.distribution_mask = effective
	add_child(grass)
	set_colors(Ground.defaults("grass")["color"],Ground.defaults("sand")["color"])

func set_colors(grass_color: Color, sand_color: Color) -> void:
	surface.set_shader_parameter("grass_color",grass_color)
	surface.set_shader_parameter("sand_color",sand_color)

func apply_sand_settings(settings: Dictionary) -> void:
	surface.set_shader_parameter("sand_patch_strength",settings["patch_strength"])
	surface.set_shader_parameter("sand_grain_feet",settings["grain_feet"])
	surface.set_shader_parameter("sand_color_strength",settings["grain_color"])
	surface.set_shader_parameter("sand_grain_strength",settings["grain_normal"])
	surface.set_shader_parameter("sand_glint_strength",settings["glint_strength"])
	surface.set_shader_parameter("sand_glint_density",settings["glint_density"])
	surface.set_shader_parameter("sand_ripple_strength",settings["ripple_strength"])
	surface.set_shader_parameter("sand_seed_offset",float(int(settings["seed"]) % 97)/97.0)

func apply_grass(settings: Dictionary) -> void:
	grass.apply(settings)

func _show_example() -> void:
	for y in range(RESOLUTION):
		for x in range(RESOLUTION):
			var u := (float(x)+0.5)/RESOLUTION
			var v := (float(y)+0.5)/RESOLUTION
			var border := 0.34+sin(v*7.0)*0.04
			var grass_weight := 1.0-smoothstep(border-0.09,border+0.09,u)
			var water_radius := Vector2((u-0.75)/0.19,(v-0.46)/0.28).length()
			water_radius += sin(v*19.0+u*7.0)*0.07
			var water_weight := 1.0-smoothstep(0.92,1.08,water_radius)
			var beach_weight := (1.0-smoothstep(1.2,1.65,water_radius))*(1.0-water_weight)*(1.0-grass_weight)
			grass_weight *= 1.0-water_weight
			var sand_weight := maxf(0.0,1.0-grass_weight-water_weight-beach_weight)
			coverage.set_pixel(x,y,Color(grass_weight,sand_weight,beach_weight,water_weight))
	_publish()
	_update_shore()

func reset_example() -> void:
	finish_stroke()
	undo_stack.clear()
	redo_stack.clear()
	stroke_count = 0
	_show_example()
	grass.update_distribution(effective)
	changed.emit()

func _publish(region := Rect2i(0,0,RESOLUTION,RESOLUTION)) -> void:
	for y in range(region.position.y,region.end.y):
		for x in range(region.position.x,region.end.x):
			var c := coverage.get_pixel(x,y)
			var raw := Vector4(c.r,c.g,c.b,c.a)
			var n := edge_noise.get_pixel(x,y).r-0.5
			var adjusted := Vector4.ZERO
			for channel in range(4):
				var value := raw[channel]
				var offset := n if channel % 2 == 0 else -n
				adjusted[channel] = maxf(0.0,value+offset*0.6*value*(1.0-value))
			adjusted /= maxf(adjusted.x+adjusted.y+adjusted.z+adjusted.w,0.0001)
			effective.set_pixel(x,y,Color(adjusted.x,adjusted.y,adjusted.z,adjusted.w))
	if texture == null:
		texture = ImageTexture.create_from_image(effective)
		surface.set_shader_parameter("cover_mask",texture)
	else:
		texture.update(effective)

func hit(camera: Camera3D, screen: Vector2) -> Variant:
	var origin := camera.project_ray_origin(screen)
	var direction := camera.project_ray_normal(screen)
	if direction.y >= -0.00001: return null
	var distance := (0.002-origin.y)/direction.y
	if distance < 0: return null
	var at := origin+direction*distance
	var point := Vector2(at.x,at.z)
	return point if AREA.has_point(point) else null

func begin_stroke() -> void:
	stroke_before = coverage.duplicate()
	stroke_changed = false
	has_last = false

func break_segment() -> void:
	has_last = false

func paint(point: Vector2, target: int, size_feet: float, softness: float, strength: float) -> void:
	if stroke_before == null: return
	dirty_region = Rect2i()
	var radius := size_feet/10.0
	var spacing := maxf(radius*0.3,AREA.size.x/RESOLUTION)
	if has_last:
		var distance := last_point.distance_to(point)
		if distance < spacing: return
		var steps := ceili(distance/spacing)
		for index in range(1,steps+1):
			_stamp(last_point.lerp(point,float(index)/steps),target,radius,softness,strength)
	else:
		_stamp(point,target,radius,softness,strength)
	last_point = point
	has_last = true
	if dirty_region.has_area(): _publish(dirty_region)

func _stamp(point: Vector2, target: int, radius: float, softness: float, strength: float) -> void:
	var uv := (point-AREA.position)/AREA.size
	var r := radius/AREA.size.x*RESOLUTION
	var center := uv*RESOLUTION-Vector2(0.5,0.5)
	var low := Vector2i(maxi(0,floori(center.x-r)),maxi(0,floori(center.y-r)))
	var high := Vector2i(mini(RESOLUTION,ceili(center.x+r)+1),mini(RESOLUTION,ceili(center.y+r)+1))
	var rect := Rect2i(low,high-low)
	dirty_region = dirty_region.merge(rect) if dirty_region.has_area() else rect
	for y in range(maxi(0,floori(center.y-r)),mini(RESOLUTION,ceili(center.y+r)+1)):
		for x in range(maxi(0,floori(center.x-r)),mini(RESOLUTION,ceili(center.x+r)+1)):
			var distance := Vector2(x,y).distance_to(center)/r
			if distance > 1: continue
			var weight := 1.0-smoothstep(maxf(0,1.0-softness-0.001),1.0,distance)
			var old := coverage.get_pixel(x,y)
			var desired := Color(1,0,0,0) if target == 0 else (Color(0,1,0,0) if target == 1 else (Color(0,0,1,0) if target == 2 else Color(0,0,0,1)))
			var next := old.lerp(desired,weight*strength)
			if maxf(maxf(absf(next.r-old.r),absf(next.g-old.g)),maxf(absf(next.b-old.b),absf(next.a-old.a))) < 1.0/255.0: continue
			coverage.set_pixel(x,y,next)
			stroke_changed = true

func finish_stroke() -> void:
	if stroke_before == null: return
	if stroke_changed:
		undo_stack.append(stroke_before)
		if undo_stack.size() > HISTORY_LIMIT: undo_stack.pop_front()
		redo_stack.clear()
		stroke_count += 1
		_update_shore()
		grass.update_distribution(effective)
	stroke_before = null
	has_last = false
	changed.emit()

func undo() -> void:
	finish_stroke()
	if undo_stack.is_empty(): return
	redo_stack.append(coverage.duplicate())
	coverage = undo_stack.pop_back()
	_publish()
	_update_shore()
	grass.update_distribution(effective)
	changed.emit()

func redo() -> void:
	finish_stroke()
	if redo_stack.is_empty(): return
	undo_stack.append(coverage.duplicate())
	coverage = redo_stack.pop_back()
	_publish()
	_update_shore()
	grass.update_distribution(effective)
	changed.emit()

func set_beach_color(color: Color) -> void:
	if beach_snapshot == color: return
	beach_snapshot = color
	surface.set_shader_parameter("beach_color",color)

func apply_water(settings: Dictionary, elapsed: float) -> void:
	if water_snapshot != settings:
		water_snapshot = settings.duplicate()
		Water.apply(surface,settings)
	surface.set_shader_parameter("water_time",elapsed)

func _update_shore() -> void:
	# Two chamfer passes; distance is measured from the final painted boundary.
	var distances := PackedFloat32Array()
	var inside := PackedByteArray()
	distances.resize(RESOLUTION*RESOLUTION)
	inside.resize(distances.size())
	for y in range(RESOLUTION):
		for x in range(RESOLUTION):
			inside[y*RESOLUTION+x] = 1 if effective.get_pixel(x,y).a >= 0.5 else 0
	for y in range(RESOLUTION):
		for x in range(RESOLUTION):
			var i := y*RESOLUTION+x
			var boundary := inside[i] == 1 and (x == 0 or y == 0 or x == RESOLUTION-1 or y == RESOLUTION-1)
			for step in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
				var at: Vector2i = Vector2i(x,y)+step
				if at.x >= 0 and at.y >= 0 and at.x < RESOLUTION and at.y < RESOLUTION:
					boundary = boundary or inside[i] != inside[at.y*RESOLUTION+at.x]
			distances[i] = 0.0 if boundary else 10000.0
	for pass_index in range(2):
		var order = range(RESOLUTION) if pass_index == 0 else range(RESOLUTION-1,-1,-1)
		var direction := -1 if pass_index == 0 else 1
		for y in order:
			for x in order:
				var i: int = y*RESOLUTION+x
				for step in [Vector2i(direction,0),Vector2i(0,direction),Vector2i(direction,direction),Vector2i(-direction,direction)]:
					var at: Vector2i = Vector2i(x,y)+step
					if at.x >= 0 and at.y >= 0 and at.x < RESOLUTION and at.y < RESOLUTION:
						var cost := 1.41421356 if step.x != 0 and step.y != 0 else 1.0
						distances[i] = minf(distances[i],distances[at.y*RESOLUTION+at.x]+cost)
	var image := Image.create(RESOLUTION,RESOLUTION,false,Image.FORMAT_RF)
	for y in range(RESOLUTION):
		for x in range(RESOLUTION):
			var i := y*RESOLUTION+x
			var feet := minf(80.0,distances[i]*AREA.size.x*5.0/RESOLUTION)
			if inside[i] == 0: feet = -feet
			image.set_pixel(x,y,Color(feet,0,0))
	if shore_texture == null:
		shore_texture = ImageTexture.create_from_image(image)
		surface.set_shader_parameter("shore_mask",shore_texture)
	else:
		shore_texture.update(image)
