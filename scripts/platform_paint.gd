extends RefCounted
const Ground = preload("res://scripts/ground_material.gd")
const Water = preload("res://scripts/water_material.gd")
const Shore = preload("res://scripts/paint_shore.gd")
const Blend = preload("res://shaders/ground_blend.gdshader")
const KINDS := ["grass","sand","beach","water"]
const HISTORY_LIMIT := 20
const HISTORY_BYTES := 64*1024*1024
signal changed
var coverage: Image
var effective: Image
var texture: ImageTexture
var shore_texture: ImageTexture
var material: ShaderMaterial
var grass: Node3D
var area := Rect2()
var origin_feet := Vector2.ZERO
var base_kind := "grass"
var undo_stack: Array[Image] = []
var redo_stack: Array[Image] = []
var stroke_before: Image
var stroke_changed := false
var stroke_region := Rect2i()
var has_last := false
var last_point := Vector2.ZERO
var edge_noise := FastNoiseLite.new()
var worker: Thread
var shore_revision := 0
var shore_pending := false
var configured := false

func configure(data: Dictionary, target: MeshInstance3D, blades: Node3D) -> void:
	finish_stroke()
	var next_origin: Vector2 = data.get("bounds_origin_feet",data["grid_origin_feet"])
	var dimensions := Vector2i(roundi(data["width_feet"]),roundi(data["length_feet"]))
	var incoming: Image = data.get("paint_overlay")
	var previous_origin: Vector2 = data.get("paint_origin_feet",origin_feet)
	var resized := configured and (origin_feet!=next_origin or coverage.get_size()!=dimensions)
	var fresh := incoming==null
	if incoming==null:
		coverage = Image.create(dimensions.x,dimensions.y,false,Image.FORMAT_RGBA8)
		coverage.fill(Color(0,0,0,0))
	elif incoming.get_size()!=dimensions or previous_origin!=next_origin:
		coverage = Image.create(dimensions.x,dimensions.y,false,Image.FORMAT_RGBA8)
		coverage.fill(Color(0,0,0,0))
		coverage.blit_rect(incoming,Rect2i(Vector2i.ZERO,incoming.get_size()),Vector2i(previous_origin-next_origin))
	else: coverage = incoming
	origin_feet = next_origin
	area = Rect2(origin_feet/5.0,Vector2(dimensions)/5.0)
	base_kind = str(data["material"])
	grass = blades
	edge_noise.seed = 470230
	edge_noise.frequency = 1.5
	edge_noise.fractal_octaves = 3
	effective = Image.create(dimensions.x,dimensions.y,false,Image.FORMAT_RGBA8)
	material = ShaderMaterial.new()
	material.shader = Blend
	material.set_shader_parameter("grass_masks",Ground.detail_texture("grass"))
	material.set_shader_parameter("sand_masks",Ground.detail_texture("sand"))
	material.set_shader_parameter("macro_mask",Ground.macro_texture())
	material.set_shader_parameter("sand_microstructure",Ground.micro_texture())
	material.set_shader_parameter("sand_grain_color",Ground.grain_color_texture())
	material.set_shader_parameter("wave_noise",Ground.macro_texture())
	material.set_shader_parameter("area_origin",area.position)
	material.set_shader_parameter("area_size",area.size)
	material.set_shader_parameter("grass_color",Ground.defaults("grass")["color"])
	material.set_shader_parameter("sand_color",Ground.defaults("sand")["color"])
	material.set_shader_parameter("beach_color",Ground.defaults("beach")["color"])
	for kind in ["sand","beach"]:
		var settings := Ground.defaults(kind)
		for entry in [["grain_feet","grain_feet"],["grain_color","color_strength"],["patch_strength","patch_strength"],["grain_normal","grain_strength"],["glint_strength","glint_strength"],["glint_density","glint_density"],["ripple_strength","ripple_strength"]]:
			material.set_shader_parameter(kind+"_"+entry[1],settings[entry[0]])
	material.set_shader_parameter("independent_sand_details",true)
	material.set_shader_parameter("top_scene_height",float(data["top_feet"])/5.0)
	Water.apply(material,Water.defaults())
	if fresh: effective.fill(_base_color())
	else: _publish_pixels(Rect2i(Vector2i.ZERO,dimensions))
	texture = ImageTexture.create_from_image(effective)
	material.set_shader_parameter("cover_mask",texture)
	var initial_shore := Image.create(1,1,false,Image.FORMAT_RF)
	initial_shore.fill(Color(0 if base_kind=="water" else -80,0,0))
	shore_texture = ImageTexture.create_from_image(initial_shore)
	material.set_shader_parameter("shore_mask",shore_texture)
	target.material_override = material
	grass.visible = bool(grass.settings["enabled"])
	grass.distribution_mask = effective
	grass.bind_ground(material)
	grass.bind_distribution(texture,area)
	configured = true
	data["paint_overlay"] = coverage
	data["paint_origin_feet"] = origin_feet
	if resized:
		undo_stack.clear()
		redo_stack.clear()
	_request_shore()
	changed.emit()

func _base_color() -> Color:
	return _target_color(KINDS.find(base_kind))

func _target_color(index: int) -> Color:
	return Color(1,0,0,0) if index==0 else (Color(0,1,0,0) if index==1 else (Color(0,0,1,0) if index==2 else (Color(0,0,0,1) if index==3 else Color(0,0,0,0))))

func _publish_pixels(region: Rect2i) -> void:
	var base := _base_color()
	for y in range(region.position.y,region.end.y):
		for x in range(region.position.x,region.end.x):
			var c := coverage.get_pixel(x,y)
			var total := c.r+c.g+c.b+c.a
			c += base*maxf(0,1.0-total)
			var p := (origin_feet+Vector2(x+0.5,y+0.5))/5.0
			var n := clampf(0.5+edge_noise.get_noise_2d(p.x,p.y)*0.8,0,1)-0.5
			var adjusted := Vector4(c.r,c.g,c.b,c.a)
			for channel in range(4):
				var v := adjusted[channel]
				adjusted[channel] = maxf(0,v+(n if channel%2==0 else -n)*0.6*v*(1.0-v))
			adjusted /= maxf(adjusted.x+adjusted.y+adjusted.z+adjusted.w,0.0001)
			effective.set_pixel(x,y,Color(adjusted.x,adjusted.y,adjusted.z,adjusted.w))

func begin_stroke() -> void:
	if not configured: return
	stroke_before = coverage.duplicate()
	stroke_changed = false
	stroke_region = Rect2i()
	has_last = false

func break_segment() -> void:
	has_last = false

func paint(point_feet: Vector2, target: int, diameter: float, softness: float, strength: float) -> void:
	if stroke_before==null or strength<=0: return
	var radius := diameter/2.0
	var spacing := maxf(0.5,radius*0.25)
	var dirty := Rect2i()
	if has_last:
		var distance := last_point.distance_to(point_feet)
		if distance<spacing: return
		var count := ceili(distance/spacing)
		for index in range(1,count+1): dirty = _merge(dirty,_stamp(last_point.lerp(point_feet,float(index)/count),target,radius,softness,strength))
	else: dirty = _stamp(point_feet,target,radius,softness,strength)
	last_point = point_feet
	has_last = true
	if dirty.has_area():
		_publish_pixels(dirty)
		texture.update(effective)
		stroke_region = _merge(stroke_region,dirty)

func _merge(a: Rect2i,b: Rect2i) -> Rect2i:
	if not a.has_area(): return b
	if not b.has_area(): return a
	return a.merge(b)

func _stamp(point: Vector2, target: int, radius: float, softness: float, strength: float) -> Rect2i:
	var center := point-origin_feet-Vector2(0.5,0.5)
	var low := Vector2i(maxi(0,floori(center.x-radius)),maxi(0,floori(center.y-radius)))
	var high := Vector2i(mini(coverage.get_width(),ceili(center.x+radius)+1),mini(coverage.get_height(),ceili(center.y+radius)+1))
	var desired := _target_color(target)
	var result := Rect2i()
	for y in range(low.y,high.y):
		for x in range(low.x,high.x):
			var distance := Vector2(x,y).distance_to(center)/radius
			if distance>1: continue
			var weight := 1.0-smoothstep(maxf(0,1.0-softness-0.001),1.0,distance)
			var old := coverage.get_pixel(x,y)
			var next := old.lerp(desired,weight*strength)
			if maxf(maxf(absf(next.r-old.r),absf(next.g-old.g)),maxf(absf(next.b-old.b),absf(next.a-old.a)))<1.0/255.0: continue
			coverage.set_pixel(x,y,next)
			stroke_changed = true
			result = _merge(result,Rect2i(x,y,1,1))
	return result

func finish_stroke() -> void:
	if stroke_before==null: return
	if stroke_changed:
		undo_stack.append(stroke_before)
		redo_stack.clear()
		_trim_history()
		_request_shore()
		_refresh_grass(stroke_region)
	stroke_before = null
	has_last = false
	changed.emit()

func _refresh_grass(region: Rect2i) -> void:
	if not is_instance_valid(grass): return
	grass.update_distribution(effective,Rect2((origin_feet+Vector2(region.position))/5.0,Vector2(region.size)/5.0))

func undo() -> void:
	finish_stroke()
	if undo_stack.is_empty(): return
	redo_stack.append(coverage.duplicate())
	coverage = undo_stack.pop_back()
	_restore()

func redo() -> void:
	finish_stroke()
	if redo_stack.is_empty(): return
	undo_stack.append(coverage.duplicate())
	coverage = redo_stack.pop_back()
	_restore()

func cancel_stroke() -> void:
	if stroke_before==null: return
	var restore := stroke_changed
	if restore: coverage = stroke_before
	stroke_before = null
	stroke_changed = false
	has_last = false
	stroke_region = Rect2i()
	if restore: _restore()

func _restore() -> void:
	_publish_pixels(Rect2i(Vector2i.ZERO,coverage.get_size()))
	texture.update(effective)
	_request_shore()
	_refresh_grass(Rect2i(Vector2i.ZERO,coverage.get_size()))
	_trim_history()
	changed.emit()

func _trim_history() -> void:
	while undo_stack.size()>HISTORY_LIMIT: undo_stack.pop_front()
	while redo_stack.size()>HISTORY_LIMIT: redo_stack.pop_front()
	var bytes := (coverage.get_width()*coverage.get_height()*4)*(undo_stack.size()+redo_stack.size())
	while bytes>HISTORY_BYTES:
		if not undo_stack.is_empty(): undo_stack.pop_front()
		elif not redo_stack.is_empty(): redo_stack.pop_front()
		else: break
		bytes = (coverage.get_width()*coverage.get_height()*4)*(undo_stack.size()+redo_stack.size())

func _request_shore() -> void:
	shore_revision += 1
	shore_pending = true

func advance(elapsed: float) -> void:
	if material!=null: material.set_shader_parameter("water_time",elapsed)
	if worker!=null and not worker.is_alive():
		var result: Dictionary = worker.wait_to_finish()
		worker = null
		if int(result["revision"])==shore_revision:
			shore_texture = ImageTexture.create_from_image(result["image"])
			material.set_shader_parameter("shore_mask",shore_texture)
			var image: Image = result["image"]
			material.set_shader_parameter("shore_texel",Vector2.ONE/Vector2(image.get_size()))
	if worker==null and shore_pending:
		shore_pending = false
		var snapshot: Image = effective.duplicate()
		var scale := minf(1,512.0/maxi(snapshot.get_width(),snapshot.get_height()))
		if scale<1: snapshot.resize(maxi(1,roundi(snapshot.get_width()*scale)),maxi(1,roundi(snapshot.get_height()*scale)),Image.INTERPOLATE_BILINEAR)
		worker = Thread.new()
		var error := worker.start(_shore_job.bind(snapshot,area.size*5.0,shore_revision))
		if error!=OK:
			worker = null
			push_error("Shore worker could not start: %s" % error)

func _shore_job(snapshot: Image, extent: Vector2, revision: int) -> Dictionary:
	return {"image":Shore.build(snapshot,extent),"revision":revision}

func shutdown() -> void:
	if worker!=null:
		worker.wait_to_finish()
		worker = null

func sample_kind(point_feet: Vector2) -> int:
	if not configured: return -1
	var p := Vector2i((point_feet-origin_feet).floor())
	if not Rect2i(Vector2i.ZERO,effective.get_size()).has_point(p): return -1
	var color := effective.get_pixelv(p)
	var weights := [color.r,color.g,color.b,color.a]
	var best := 0
	for index in range(1,4):
		if weights[index]>weights[best]: best = index
	return best

func fill_rectangle(rect_feet: Rect2, target: int) -> void:
	if not configured: return
	finish_stroke()
	var low := Vector2i((rect_feet.position-origin_feet).floor())
	var high := Vector2i((rect_feet.end-origin_feet).ceil())
	var region := Rect2i(low,high-low).intersection(Rect2i(Vector2i.ZERO,coverage.get_size()))
	if not region.has_area(): return
	begin_stroke()
	var desired := _target_color(target)
	for y in range(region.position.y,region.end.y):
		for x in range(region.position.x,region.end.x):
			if coverage.get_pixel(x,y).is_equal_approx(desired): continue
			coverage.set_pixel(x,y,desired)
			stroke_changed = true
	if stroke_changed:
		stroke_region = region
		_publish_pixels(region)
		texture.update(effective)
	finish_stroke()

func fill_all(target: int) -> void:
	fill_rectangle(Rect2(origin_feet,Vector2(coverage.get_size())),target)
