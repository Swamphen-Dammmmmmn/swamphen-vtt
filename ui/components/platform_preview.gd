extends SubViewportContainer

const Typography = preload("res://ui/theme/typography.gd")
const Paint = preload("res://scripts/platform_paint.gd")
const Grid = preload("res://scripts/platform_grid.gd")
const Handles = preload("res://ui/components/range_handles.gd")
const Landing = preload("res://scripts/platform_landing.gd")
const Model = preload("res://scripts/platform_model.gd")
const EnvironmentProfile = preload("res://scripts/environment_profile.gd")
const OrbitCamera = preload("res://scripts/orbit_camera.gd")
var paint := Paint.new()
var brush: MeshInstance3D
var brush_mesh: ImmediateMesh
var paint_rectangle: Node3D
var paint_rectangle_cache := Rect2()
var landing_brush: Node3D
var landing_brush_cache := Rect2i()
var landing_brush_removing := false
var brush_cached := Vector4(-1,-1,-1,-1)
var viewport: SubViewport
var camera: Camera3D
var world: Node3D
var actor: Node3D
var grid: MeshInstance3D
var values: Dictionary
var target := Vector3.ZERO
var distance := 22.0
var yaw := 0.65
var pitch := 0.7
var free_yaw := 0.0
var free_pitch := 0.0
var clock := 0.0
var expansion_outline: MeshInstance3D
var direction_labels: Array[Label3D] = []
var landing_grid: MeshInstance3D
var landing_cache: Array = []
var landing_highlight := true
var permission_fill: MeshInstance3D
var draft_removing := false
var grid_shown := true
var draft_overlay: Node3D
var expansion_fill: Node3D
var expansion_volume: MeshInstance3D
var handles: Node3D
var handle_context := ""
var draft_cache := {}
var draft_invalid := false
var draft_editable := true
var overlay_scale_distance := 0.0

func _ready() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.handle_input_locally = false
	viewport.gui_disable_input = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	world = Node3D.new()
	viewport.add_child(world)
	var environment := EnvironmentProfile.create()
	world.add_child(environment)
	Graphics.apply_environment(environment.get_node("WorldEnvironment").environment)
	camera = Camera3D.new()
	camera.current = true
	camera.fov = 45
	world.add_child(camera)
	_position_camera()
	handles = Handles.new()
	handles.camera = camera
	world.add_child(handles)

func configure(data: Dictionary, fit_camera := false) -> void:
	values = data.duplicate(true)
	Landing.normalize(values)
	if actor != null:
		world.remove_child(actor)
		actor.queue_free()
	actor = Model.build(values)
	world.add_child(actor)
	var width := float(values["width_feet"])/5.0
	var length := float(values["length_feet"])/5.0
	var origin: Vector2 = values.get("bounds_origin_feet",values["grid_origin_feet"])/5.0
	if fit_camera:
		target = Vector3(origin.x+width/2.0,float(values["top_feet"])/5.0,origin.y+length/2.0)
		distance = maxf(6.0,Vector3(width,float(values["thickness_feet"])/5.0,length).length()*1.7)
	if fit_camera: _position_camera()
	paint.configure(values,actor.get_node("Surface"),actor.get_node("GrassBlades"))
	show_landing_cells(values.get("landing_cells",[]),true)

func set_grid_visible(shown: bool) -> void:
	grid_shown = shown
	_update_auxiliary_visibility()

func _refresh_grid() -> void:
	for node in [grid,landing_grid,permission_fill]:
		if is_instance_valid(node):
			world.remove_child(node)
			node.queue_free()
	var segments := Grid.segments(values,true)
	grid = _landing_lines(segments["dashed"],Color("8798a9"),0.015)
	landing_grid = _landing_lines(segments["solid"],Color("3c7899"),0.025)
	permission_fill = _make_permission_fill()
	_update_auxiliary_visibility()

func _update_auxiliary_visibility() -> void:
	var above := not values.is_empty() and camera.position.y>float(values["top_feet"])/5.0+0.001
	if is_instance_valid(grid): grid.visible = grid_shown and above
	if is_instance_valid(landing_grid): landing_grid.visible = grid_shown and above
	if is_instance_valid(permission_fill): permission_fill.visible = landing_highlight and above
	if is_instance_valid(draft_overlay): draft_overlay.visible = above
	if is_instance_valid(expansion_fill): expansion_fill.visible = above
	if is_instance_valid(handles):
		handles.viewport_height = float(viewport.size.y)
		for item in handles.definitions:
			handles.nodes[item["key"]].visible = above or (handle_context=="expand" and item["key"]=="bottom")

func turn(relative: Vector2) -> void:
	free_yaw -= relative.x*0.004
	free_pitch = clampf(free_pitch-relative.y*0.004,deg_to_rad(-89),deg_to_rad(89))
	camera.rotation = Vector3(free_pitch,free_yaw,0)

func move_free(direction: Vector3, speed_feet: float, delta: float) -> void:
	camera.position += direction.normalized()*(speed_feet/5.0)*minf(delta,0.1)

func _position_camera() -> void:
	pitch = OrbitCamera.clamp_pitch(pitch)
	camera.position = target+Vector3(sin(yaw)*cos(pitch),sin(pitch),cos(yaw)*cos(pitch))*distance
	camera.look_at(target)
	free_yaw = camera.rotation.y
	free_pitch = camera.rotation.x

func _process(delta: float) -> void:
	clock += delta
	_update_auxiliary_visibility()
	if not draft_cache.is_empty():
		var center := _region_center(draft_cache)
		var current_distance := camera.position.distance_to(center)
		if absf(current_distance-overlay_scale_distance)>maxf(0.1,current_distance*0.1): show_landing_draft(draft_cache,draft_invalid,draft_editable,draft_removing)
	if paint.configured: paint.advance(clock)

func show_expansion(data: Dictionary, active: bool, invalid := false) -> void:
	if is_instance_valid(expansion_outline):
		world.remove_child(expansion_outline)
		expansion_outline.queue_free()
	for label in direction_labels:
		world.remove_child(label)
		label.queue_free()
	direction_labels.clear()
	if is_instance_valid(expansion_fill):
		world.remove_child(expansion_fill)
		expansion_fill.queue_free()
	if is_instance_valid(expansion_volume):
		world.remove_child(expansion_volume)
		expansion_volume.queue_free()
	if not active:
		if handle_context=="expand": set_range_handles([],"")
		return
	var color := Color("d73535") if invalid else Color("2563a6")
	var origin: Vector2 = data.get("bounds_origin_feet",data["grid_origin_feet"])/5.0
	var w := float(data["width_feet"])/5.0
	var l := float(data["length_feet"])/5.0
	var y := float(data["top_feet"])/5.0+0.03
	var bottom := float(data["top_feet"]-data["thickness_feet"])/5.0
	var corners: Array[Vector3] = [Vector3(origin.x,y,origin.y),Vector3(origin.x+w,y,origin.y),Vector3(origin.x+w,y,origin.y+l),Vector3(origin.x,y,origin.y+l)]
	var lines := ImmediateMesh.new()
	lines.surface_begin(Mesh.PRIMITIVE_LINES)
	for index in range(4):
		var a := corners[index]
		var b := corners[(index+1)%4]
		lines.surface_add_vertex(a)
		lines.surface_add_vertex(b)
		lines.surface_add_vertex(Vector3(a.x,bottom,a.z))
		lines.surface_add_vertex(Vector3(b.x,bottom,b.z))
		lines.surface_add_vertex(a)
		lines.surface_add_vertex(Vector3(a.x,bottom,a.z))
	lines.surface_end()
	expansion_outline = MeshInstance3D.new()
	expansion_outline.mesh = lines
	var face := StandardMaterial3D.new()
	face.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	face.albedo_color = color
	expansion_outline.material_override = face
	expansion_outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(expansion_outline)
	var positions := [Vector3(origin.x-0.5,y,origin.y+l/2),Vector3(origin.x+w+0.5,y,origin.y+l/2),Vector3(origin.x+w/2,y,origin.y-0.5),Vector3(origin.x+w/2,y,origin.y+l+0.5)]
	for index in range(4):
		var label := Label3D.new()
		label.font = Typography.WORLD_REGULAR
		label.text = ["X−","X+","Z−","Z+"][index]
		label.font = ThemeDB.fallback_font
		label.font_size = Typography.PREVIEW_DIRECTION
		label.pixel_size = 0.008
		label.modulate = color
		label.outline_size = 0
		label.rotation_degrees.x = -90
		label.position = positions[index]
		world.add_child(label)
		direction_labels.append(label)
	expansion_fill = Node3D.new()
	world.add_child(expansion_fill)
	var original := Landing.bounds(values)
	var expanded := Landing.bounds(data)
	var strips: Array[Rect2i] = [Rect2i(expanded.position,Vector2i(original.position.x-expanded.position.x,expanded.size.y)),Rect2i(Vector2i(original.end.x,expanded.position.y),Vector2i(expanded.end.x-original.end.x,expanded.size.y)),Rect2i(Vector2i(original.position.x,expanded.position.y),Vector2i(original.size.x,original.position.y-expanded.position.y)),Rect2i(Vector2i(original.position.x,original.end.y),Vector2i(original.size.x,expanded.end.y-original.end.y))]
	for rect in strips:
		if rect.size.x>0 and rect.size.y>0: expansion_fill.add_child(_rect_overlay(rect,color,0.18,false))
	expansion_fill.add_child(_rect_overlay(expanded,color,0.0,false))
	var added_bottom := float(data["thickness_feet"]-values["thickness_feet"])/5.0
	if added_bottom>0:
		expansion_volume = MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(w,added_bottom,l)
		expansion_volume.mesh = box
		expansion_volume.position = Vector3(origin.x+w/2,bottom+added_bottom/2,origin.y+l/2)
		var volume_face := _overlay_material(color)
		volume_face.no_depth_test = false
		volume_face.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		volume_face.albedo_color.a = 0.2
		expansion_volume.material_override = volume_face
		expansion_volume.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world.add_child(expansion_volume)
	var items := side_handles(Rect2(Vector2(expanded.position),Vector2(expanded.size)),false)
	items.append({"key":"bottom","position":Vector3(origin.x-0.6,bottom-0.15,origin.y+l/2),"axis":Vector3.DOWN})
	handles.invalid = invalid
	set_range_handles(items,"expand")
	_update_auxiliary_visibility()


func top_point(global_point: Vector2):
	if values.is_empty() or size.x<=0 or size.y<=0: return null
	var screen := screen_point(global_point)
	var origin := camera.project_ray_origin(screen)
	var direction := camera.project_ray_normal(screen)
	var height := float(values["top_feet"])/5.0
	if origin.y<=height+0.001 or direction.y>=-0.0001: return null
	var distance_to_plane := (height-origin.y)/direction.y
	if distance_to_plane<0: return null
	var point := origin+direction*distance_to_plane
	return Vector2(point.x,point.z)*5.0

func set_landing_highlight(shown: bool) -> void:
	landing_highlight = shown
	_update_auxiliary_visibility()

func show_landing_cells(cells: Array, force := false) -> void:
	if not force and cells==landing_cache: return
	landing_cache = cells.duplicate(true)
	values["landing_cells"] = cells.duplicate(true)
	_refresh_grid()

func _make_permission_fill(data: Dictionary = {}, parent: Node3D = null) -> MeshInstance3D:
	if data.is_empty(): data = values
	if parent == null: parent = world
	var occupied := Landing.cells(data)
	if occupied.is_empty(): return null
	var bounds := Landing.bounds(data)
	var origin: Vector2 = data["grid_origin_feet"]/5.0
	var y := float(data["top_feet"])/5.0+0.02
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	# Merge adjacent cells in each row into one strip; holes remain unfilled.
	for z in range(bounds.position.y,bounds.end.y):
		var x := bounds.position.x
		while x<bounds.end.x:
			if not occupied.has(Vector2i(x,z)):
				x += 1
				continue
			var start := x
			while x<bounds.end.x and occupied.has(Vector2i(x,z)): x += 1
			var a := Vector3(origin.x+start,y,origin.y+z)
			var b := Vector3(origin.x+x,y,origin.y+z)
			var c := Vector3(origin.x+x,y,origin.y+z+1)
			var d := Vector3(origin.x+start,y,origin.y+z+1)
			for point in [a,c,b,a,d,c]: mesh.surface_add_vertex(point)
	mesh.surface_end()
	var node := MeshInstance3D.new()
	node.mesh = mesh
	var face := _overlay_material(Color("3b82c4"))
	face.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	face.albedo_color.a = 0.15
	face.render_priority = -1
	face.cull_mode = BaseMaterial3D.CULL_DISABLED
	node.material_override = face
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(node)
	return node

func show_landing_draft(region: Dictionary, invalid := false, editable := true, removing := false) -> void:
	if is_instance_valid(draft_overlay):
		world.remove_child(draft_overlay)
		draft_overlay.queue_free()
	draft_cache = region.duplicate(true)
	draft_invalid = invalid
	draft_editable = editable
	draft_removing = removing
	handles.invalid = invalid
	if region.is_empty():
		set_range_handles([],"landing")
		return
	var rect := Landing.rectangle(region)
	var color := Color("d73535") if invalid else (Color("bd7020") if removing else Color("2563a6"))
	draft_overlay = _rect_overlay(rect,color,0.18,true)
	world.add_child(draft_overlay)
	overlay_scale_distance = camera.position.distance_to(_region_center(region))
	set_range_handles(side_handles(Rect2(Vector2(rect.position),Vector2(rect.size)),true) if editable else [],"landing")
	_update_auxiliary_visibility()

func _region_center(region: Dictionary) -> Vector3:
	var rect := Landing.rectangle(region)
	var origin: Vector2 = values["grid_origin_feet"]/5.0
	return Vector3(origin.x+rect.position.x+rect.size.x/2.0,float(values["top_feet"])/5.0,origin.y+rect.position.y+rect.size.y/2.0)

func _rect_overlay(rect, color: Color, opacity: float, interior: bool) -> Node3D:
	var root := Node3D.new()
	var origin: Vector2 = values["grid_origin_feet"]/5.0
	var a := origin+Vector2(rect.position)
	var b := origin+Vector2(rect.end)
	var height := float(values["top_feet"])/5.0+0.04
	var center := Vector3((a.x+b.x)/2,height,(a.y+b.y)/2)
	var fill := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(rect.size)
	fill.mesh = plane
	fill.position = center
	var face := _overlay_material(color)
	face.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	face.albedo_color.a = opacity
	fill.material_override = face
	fill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(fill)
	var thickness := maxf(0.025,camera.position.distance_to(center)*2.0*tan(deg_to_rad(camera.fov)*0.5)/maxf(1,viewport.size.y)*3.5)
	for edge in [[Vector2(a.x,a.y),Vector2(b.x,a.y)],[Vector2(b.x,a.y),Vector2(b.x,b.y)],[Vector2(b.x,b.y),Vector2(a.x,b.y)],[Vector2(a.x,b.y),Vector2(a.x,a.y)]]:
		var border := MeshInstance3D.new()
		var band := PlaneMesh.new()
		var start: Vector2 = edge[0]
		var finish: Vector2 = edge[1]
		band.size = Vector2(maxf(thickness,absf(finish.x-start.x)),maxf(thickness,absf(finish.y-start.y)))
		border.mesh = band
		border.position = Vector3((start.x+finish.x)/2,height+0.001,(start.y+finish.y)/2)
		border.material_override = _overlay_material(color)
		border.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(border)
	if interior and (rect.size.x>1 or rect.size.y>1):
		var lines := ImmediateMesh.new()
		lines.surface_begin(Mesh.PRIMITIVE_LINES)
		for x in range(rect.position.x+1,rect.end.x):
			lines.surface_add_vertex(Vector3(origin.x+x,height,a.y))
			lines.surface_add_vertex(Vector3(origin.x+x,height,b.y))
		for z in range(rect.position.y+1,rect.end.y):
			lines.surface_add_vertex(Vector3(a.x,height,origin.y+z))
			lines.surface_add_vertex(Vector3(b.x,height,origin.y+z))
		# ImmediateMesh cannot end an empty surface.
		if rect.size.x>1 or rect.size.y>1:
			lines.surface_end()
			var node := MeshInstance3D.new()
			node.mesh = lines
			node.material_override = _overlay_material(color)
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(node)
	return root

func _overlay_material(color: Color) -> StandardMaterial3D:
	var face := StandardMaterial3D.new()
	face.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	face.no_depth_test = true
	face.albedo_color = color
	return face

func side_handles(rect: Rect2, corners: bool) -> Array[Dictionary]:
	var origin: Vector2 = values["grid_origin_feet"]/5.0
	var a := origin+rect.position
	var b := origin+rect.end
	var y := float(values["top_feet"])/5.0+0.08
	var items: Array[Dictionary] = [{"key":"x_negative","position":Vector3(a.x,y,(a.y+b.y)/2),"axis":Vector3.LEFT},{"key":"x_positive","position":Vector3(b.x,y,(a.y+b.y)/2),"axis":Vector3.RIGHT},{"key":"z_negative","position":Vector3((a.x+b.x)/2,y,a.y),"axis":Vector3.FORWARD},{"key":"z_positive","position":Vector3((a.x+b.x)/2,y,b.y),"axis":Vector3.BACK}]
	if corners:
		for item in [["corner_nn",a],["corner_pn",Vector2(b.x,a.y)],["corner_pp",b],["corner_np",Vector2(a.x,b.y)]]:
			items.append({"key":item[0],"position":Vector3(item[1].x,y,item[1].y),"corner":true})
	return items

func set_range_handles(items: Array[Dictionary], context: String) -> void:
	handle_context = context
	handles.configure(items)

func screen_point(global_point: Vector2) -> Vector2:
	return (get_global_transform_with_canvas().affine_inverse()*global_point)/size*Vector2(viewport.size)

func hit_handles(global_point: Vector2) -> String:
	return handles.hit(screen_point(global_point))

func _landing_lines(segments: Array[Vector2], color: Color, height_offset: float) -> MeshInstance3D:
	if segments.is_empty(): return null
	var origin: Vector2 = values["grid_origin_feet"]/5.0
	var height := float(values["top_feet"])/5.0+height_offset
	var lines := ImmediateMesh.new()
	lines.surface_begin(Mesh.PRIMITIVE_LINES)
	for point in segments: lines.surface_add_vertex(Vector3(origin.x+point.x,height,origin.y+point.y))
	lines.surface_end()
	var node := MeshInstance3D.new()
	node.mesh = lines
	var face := StandardMaterial3D.new()
	face.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	face.albedo_color = color
	face.no_depth_test = true
	node.material_override = face
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(node)
	return node

func show_brush(point, diameter: float, softness: float) -> void:
	if point==null:
		if is_instance_valid(brush): brush.hide()
		return
	if not is_instance_valid(brush):
		brush = MeshInstance3D.new()
		brush_mesh = ImmediateMesh.new()
		brush.mesh = brush_mesh
		var face := _overlay_material(Color.WHITE)
		face.cull_mode = BaseMaterial3D.CULL_DISABLED
		face.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		face.vertex_color_use_as_albedo = true
		face.render_priority = 2
		brush.material_override = face
		brush.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		world.add_child(brush)
	brush.show()
	var y := float(values["top_feet"])/5.0+0.05
	var center := Vector3(point.x/5.0,y,point.y/5.0)
	var radius := diameter/10.0
	var width := minf(radius/4.0,maxf(0.008,camera.position.distance_to(center)*2.0*tan(deg_to_rad(camera.fov)*0.5)/maxf(1,viewport.size.y)*2.5))
	var key := Vector4(radius,softness,width,y)
	brush.position = center
	if brush_cached.is_equal_approx(key): return
	brush_cached = key
	brush_mesh.clear_surfaces()
	brush_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	# Concentric bands describe the same full-strength core and soft falloff as the stamp.
	for band in range(16):
		var inner := radius*band/16.0
		var outer := radius*(band+1)/16.0
		for i in range(64):
			var a := Vector2(cos(TAU*i/64),sin(TAU*i/64))
			var b := Vector2(cos(TAU*(i+1)/64),sin(TAU*(i+1)/64))
			for vertex in [a*inner,b*outer,a*outer,a*inner,b*inner,b*outer]:
				var falloff := 1.0 if softness<=0.001 else clampf((1.0-vertex.length()/radius)/softness,0,1)
				brush_mesh.surface_set_color(Color(0.14,0.45,0.72,0.04+falloff*0.18))
				brush_mesh.surface_add_vertex(Vector3(vertex.x,0,vertex.y))
	brush_mesh.surface_set_color(Color(0.08,0.31,0.58,0.95))
	for ring_index in range(2):
		if ring_index==1 and softness<=0.001: continue
		var ring: float = radius if ring_index==0 else radius*(1.0-softness)
		if ring<width*2: continue
		for i in range(64):
			if ring!=radius and i%2==1: continue
			var a := Vector2(cos(TAU*i/64),sin(TAU*i/64))
			var b := Vector2(cos(TAU*(i+1)/64),sin(TAU*(i+1)/64))
			var p := [a*(ring-width/2),a*(ring+width/2),b*(ring+width/2),b*(ring-width/2)]
			for index in [0,2,1,0,3,2]: brush_mesh.surface_add_vertex(Vector3(p[index].x,0,p[index].y))
	brush_mesh.surface_end()

func show_landing_brush(rect: Rect2i, removing := false) -> void:
	if rect.size.x<=0 or rect.size.y<=0:
		if is_instance_valid(landing_brush): landing_brush.hide()
		return
	if is_instance_valid(landing_brush) and rect==landing_brush_cache and removing==landing_brush_removing:
		landing_brush.show()
		return
	if is_instance_valid(landing_brush):
		world.remove_child(landing_brush)
		landing_brush.queue_free()
	landing_brush_cache = rect
	landing_brush_removing = removing
	landing_brush = _rect_overlay(rect,Color("bd7020") if removing else Color("2563a6"),0.25,true)
	world.add_child(landing_brush)

func _exit_tree() -> void:
	paint.shutdown()

func show_paint_rectangle(rect_feet: Rect2) -> void:
	if not rect_feet.has_area():
		if is_instance_valid(paint_rectangle): paint_rectangle.hide()
		return
	if is_instance_valid(paint_rectangle) and rect_feet==paint_rectangle_cache:
		paint_rectangle.show()
		return
	if is_instance_valid(paint_rectangle):
		world.remove_child(paint_rectangle)
		paint_rectangle.queue_free()
	paint_rectangle_cache = rect_feet
	var origin: Vector2 = values["grid_origin_feet"]
	paint_rectangle = _rect_overlay(Rect2((rect_feet.position-origin)/5.0,rect_feet.size/5.0),Color("2563a6"),0.22,false)
	world.add_child(paint_rectangle)
