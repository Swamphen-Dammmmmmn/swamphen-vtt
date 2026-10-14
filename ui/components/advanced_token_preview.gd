extends "res://ui/components/token_preview.gd"

const Contour = preload("res://scripts/token_contour.gd")
const StickerGizmo = preload("res://ui/components/token_sticker_gizmo.gd")
var sticker_gizmo: Node3D
var face_outline: MeshInstance3D
const Gizmo = preload("res://ui/components/token_transform_gizmo.gd")
const FootprintRules = preload("res://scripts/token_footprint.gd")
var gizmo: Node3D
var framing_bounds := AABB()
var validation: Dictionary = {}
var current_extent := Vector2i.ONE
var configured := false
var facing_bounds := AABB()
var has_facing_bounds := false
const Acrylic = preload("res://scripts/token_acrylic.gd")

func configure_material(data: Dictionary) -> void:
	if actor == null or not validation.get("ok", false) or not FootprintRules.valid(data) or FootprintRules.dimensions(data) != current_extent:
		configure(data)
		return
	var surface = preload("res://scripts/token_surface.gd")
	var settings_by_part := {}
	for part in ["base", "standee"]:
		var source: Dictionary = data.components[part]
		if source.has("material") and not surface.valid(source.material):
			configure(data)
			return
		settings_by_part[part] = surface.for_component(source, part)
	var before: Dictionary = validation.components.standee
	if before.get("presentation", "solid") == "image" and not before.has("contour") and before.material.board_visible != settings_by_part.standee.board_visible:
		configure(data)
		return
	for part in ["base", "standee"]:
		var settings: Dictionary = settings_by_part[part]
		validation.components[part].material = settings
		validation.components[part].color = settings.color
		var mesh := actor.get_node_or_null("Base" if part == "base" else "Standee") as MeshInstance3D
		if mesh != null and not validation.get("outside", []).has(part):
			mesh.material_override = surface.material(settings, part)
			mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if settings.board_visible and float(settings.opacity) >= 0.9999 else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_refresh()
var designer_visibility := {"base": true, "standee": true}

func _ready() -> void:
	super._ready()
	size_label.hide()
	gizmo = Gizmo.new()
	gizmo.camera = camera
	model_root.add_child(gizmo)
	sticker_gizmo = StickerGizmo.new()
	sticker_gizmo.camera = camera
	model_root.add_child(sticker_gizmo)

func configure(data: Dictionary) -> void:
	if face_outline != null:
		face_outline.queue_free()
		face_outline = null
	designer_visibility = data.get("designer_visibility", {"base": true, "standee": true})
	if actor != null:
		model_root.remove_child(actor)
		actor.queue_free()
		actor = null
	if not FootprintRules.valid(data):
		validation = {"ok": false, "message": "占地宽长须为 1～15 的整数格。"}
		gizmo.end_drag()
		gizmo.hide()
		sticker_gizmo.end_drag()
		sticker_gizmo.hide()
		_refresh()
		return
	current_extent = FootprintRules.dimensions(data)
	validation = Components.validate(data["components"], current_extent, false)
	if validation["ok"]:
		actor = Components.build(validation)
		model_root.add_child(actor)
		_apply_designer_visibility()
		var active: String = data.get("active_component", "base")
		gizmo.configure(validation["components"], active, designer_visibility[active])
		var editing_image: bool = data.get("sticker_editing", false)
		sticker_gizmo.configure_sticker(validation["components"], data.get("sticker_face", "front"), editing_image and designer_visibility["standee"])
		if editing_image and designer_visibility["standee"]: _outline_face(data.get("sticker_face", "front"))
	else:
		gizmo.end_drag()
		gizmo.hide()
		sticker_gizmo.end_drag()
		sticker_gizmo.hide()
	_build_ranges(data.get("active_component", "base"))
	preview_count = maxi(current_extent.x, current_extent.y)
	var half := Vector2(current_extent) / 2.0 + Vector2(1.7, 1.7)
	framing_bounds = AABB(Vector3(-half.x, 0, -half.y), Vector3(half.x * 2, 0, half.y * 2))
	if validation["ok"]: framing_bounds = framing_bounds.merge(validation["bounds"])
	if has_facing_bounds: framing_bounds = framing_bounds.merge(facing_bounds)
	if not configured:
		configured = true
		fit_all()
	else: _position_camera()

func fit_all() -> void:
	target = framing_bounds.get_center()
	distance = maxf(4, framing_bounds.size.length() * 1.5)
	_position_camera()

func zoom_view(factor: float) -> void:
	distance = clampf(distance * factor, maxf(0.3, framing_bounds.size.length() * 0.06), maxf(50, framing_bounds.size.length() * 12))
	_position_camera()

func _position_camera() -> void:
	pitch = OrbitCamera.clamp_pitch(pitch)
	camera.far = maxf(100, distance * 4 + framing_bounds.size.length() * 2)
	camera.near = maxf(0.005, distance * 0.00002)
	camera.position = target + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	camera.look_at(target)
	if gizmo != null: gizmo.refresh_scale()
	if sticker_gizmo != null: sticker_gizmo.refresh_scale()
	_refresh()

func set_adjustment_mode(mode: String) -> void:
	gizmo.set_mode(mode)
	if not validation.get("ok", false): gizmo.hide()
	_refresh()

func _ground_text(value: String, at: Vector3, color: Color, scale_factor: float) -> void:
	var mesh := TextMesh.new()
	mesh.text = value
	mesh.font = preload("res://ui/theme/preview_size_font.tres")
	mesh.font_size = 64
	mesh.pixel_size = 0.003 * scale_factor
	mesh.depth = 0.001
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _surface(color)
	node.position = at
	node.rotation.x = -PI / 2
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	footprint.add_child(node)

func _surface(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if color.a < 1: material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return material

func _polygon(points: PackedVector2Array, color: Color, height: float) -> void:
	if points.size() < 3: return
	var indices := Geometry2D.triangulate_polygon(points)
	if indices.is_empty(): return
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in indices: mesh.surface_add_vertex(Vector3(points[index].x, height, points[index].y))
	mesh.surface_end()
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _surface(color)
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	footprint.add_child(node)

func _rect(half: Vector2) -> PackedVector2Array:
	return PackedVector2Array([Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y)])

func _line(a: Vector2, b: Vector2, color: Color, height: float, dashed := false) -> void:
	var length := a.distance_to(b)
	if length < 0.000001: return
	var parts := maxi(1, ceili(length / 0.18)) if dashed else 1
	for part in range(parts):
		if dashed and part % 2: continue
		var start := a.lerp(b, float(part) / parts)
		var end := a.lerp(b, float(part + 1) / parts)
		var mesh := BoxMesh.new()
		mesh.size = Vector3(start.distance_to(end), 0.004, 0.018)
		var node := MeshInstance3D.new()
		node.mesh = mesh
		node.position = Vector3((start.x + end.x) / 2, height, (start.y + end.y) / 2)
		node.rotation.y = -atan2(end.y - start.y, end.x - start.x)
		node.material_override = _surface(color)
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		footprint.add_child(node)

func _outline(points: PackedVector2Array, color: Color, height: float, dashed := false) -> void:
	for index in range(points.size()): _line(points[index], points[(index + 1) % points.size()], color, height, dashed)

func _build_ranges(active: String) -> void:
	has_facing_bounds = false
	for node in footprint.get_children():
		footprint.remove_child(node)
		node.queue_free()
	var half := Vector2(current_extent) / 2.0
	var outer := half + Vector2.ONE
	var inner_points := _rect(half)
	_polygon(inner_points, Color(0.38, 0.48, 0.60, 0.06), 0.007)
	for points in _outside_parts(_rect(outer), half): _polygon(points, Color(0.27, 0.66, 0.68, 0.09), 0.009)
	for index in range(1, current_extent.x): _line(Vector2(index - half.x, -half.y), Vector2(index - half.x, half.y), Color("a0aebb"), 0.010)
	for index in range(1, current_extent.y): _line(Vector2(-half.x, index - half.y), Vector2(half.x, index - half.y), Color("a0aebb"), 0.010)
	_outline(inner_points, Color("52647d") if active == "base" else Color("8e9caf"), 0.017)
	_outline(_rect(outer), Color("308b92") if active == "standee" else Color("8bb7ba"), 0.017, true)
	var text_scale := maxf(1, sqrt(float(maxi(current_extent.x, current_extent.y))))
	_ground_text("实际占地", Vector3(0, 0.042, half.y + 0.35 * text_scale), Color("243e63"), text_scale)
	_ground_text("立牌外扩 5 英尺", Vector3(0, 0.042, -outer.y - 0.35 * text_scale), Color("126168"), text_scale)
	_ground_text("%d×%d" % [current_extent.x, current_extent.y], Vector3(half.x + 0.40 * text_scale, 0.042, 0), Color("243e63"), text_scale)
	if not validation.get("ok", false): return
	var components: Dictionary = validation["components"]
	_build_facing_arrow(components, outer)
	if not designer_visibility[active]: return
	var projection := Components.projection(components[active], active, components)
	_polygon(projection, Color(0.23, 0.52, 0.83, 0.12), 0.020)
	_outline(projection, Color("367cb5"), 0.025)
	if not components[active]["visible"]: return
	for points in _outside_parts(projection, half if active == "base" else outer):
		_polygon(points, Color(0.83, 0.22, 0.22, 0.23), 0.027)
		_outline(points, Color("c34444"), 0.030)

func _outside_parts(polygon: PackedVector2Array, half: Vector2) -> Array[PackedVector2Array]:
	var result: Array[PackedVector2Array] = []
	if polygon.size() < 3: return result
	var bounds := Rect2(polygon[0], Vector2.ZERO)
	for point in polygon: bounds = bounds.expand(point)
	var left := minf(bounds.position.x, -half.x) - 1
	var right := maxf(bounds.end.x, half.x) + 1
	var top := minf(bounds.position.y, -half.y) - 1
	var bottom := maxf(bounds.end.y, half.y) + 1
	# Four disjoint strips avoid polygons with holes when the projection surrounds the allowed area.
	for box in [Rect2(left, top, right - left, -half.y - top), Rect2(left, half.y, right - left, bottom - half.y), Rect2(left, -half.y, -half.x - left, half.y * 2), Rect2(half.x, -half.y, right - half.x, half.y * 2)]:
		var corners := PackedVector2Array([box.position, Vector2(box.end.x, box.position.y), box.end, Vector2(box.position.x, box.end.y)])
		for clipped in Geometry2D.intersect_polygons(polygon, corners): result.append(clipped)
	return result

func _apply_designer_visibility() -> void:
	for key in ["base", "standee"]:
		var node: MeshInstance3D = actor.get_node("Base" if key == "base" else "Standee")
		var actual: bool = validation["components"][key]["visible"]
		node.visible = actual and designer_visibility[key]
		if actual or not designer_visibility[key]: continue
		var component: Dictionary = validation["components"][key]
		var image_mode: bool = key == "standee" and component.get("presentation", "solid") == "image"
		if image_mode and not component.has("contour"): continue
		# Outline uses the real component transform but never alters saved visibility or support.
		var faces := node.mesh.get_faces()
		var lines := ImmediateMesh.new()
		lines.surface_begin(Mesh.PRIMITIVE_LINES)
		var edges: Dictionary = {}
		if image_mode:
			for back in [false, true]:
				for point in Contour.face_edges(component["contour"], float(component["thickness_ft"]), back): lines.surface_add_vertex(point)
		else:
			for index in range(0, faces.size(), 3):
				for edge in range(3):
					var a: Vector3 = faces[index + edge]
					var b: Vector3 = faces[index + (edge + 1) % 3]
					var edge_key := str(a) + ":" + str(b) if str(a) < str(b) else str(b) + ":" + str(a)
					if edges.has(edge_key): continue
					edges[edge_key] = true
					lines.surface_add_vertex(a)
					lines.surface_add_vertex(b)
		lines.surface_end()
		var outline := MeshInstance3D.new()
		outline.mesh = lines
		outline.transform = node.transform
		outline.material_override = _surface(Color("468ea0"))
		outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		actor.add_child(outline)

func set_sticker_mode(mode: String) -> void:
	sticker_gizmo.set_mode(mode)
	if not validation.get("ok", false): sticker_gizmo.hide()
	_refresh()

func _outline_face(name: String) -> void:
	var component: Dictionary = validation["components"]["standee"]
	var points := PackedVector3Array()
	if component.get("presentation", "solid") == "image":
		if not component.has("contour"): return
		points = Contour.face_edges(component["contour"], float(component["thickness_ft"]), name == "back")
	else:
		var half_w := float(component["width_ft"]) / 10.0
		var half_h := float(component["height_ft"]) / 10.0
		var z := (float(component["thickness_ft"]) / 10.0 + 0.001) * (-1.0 if name == "back" else 1.0)
		var corners := [Vector3(-half_w, -half_h, z), Vector3(half_w, -half_h, z), Vector3(half_w, half_h, z), Vector3(-half_w, half_h, z)]
		for index in range(4):
			points.append(corners[index])
			points.append(corners[(index + 1) % 4])
	if points.is_empty(): return
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for point in points: mesh.surface_add_vertex(point)
	mesh.surface_end()
	face_outline = MeshInstance3D.new()
	face_outline.mesh = mesh
	face_outline.material_override = _surface(Color("f1ad3d"))
	face_outline.transform = Components._transform(component, "standee", validation["components"])
	face_outline.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	model_root.add_child(face_outline)

func _build_facing_arrow(components: Dictionary, outer: Vector2) -> void:
	var transform := Components._transform(components["standee"], "standee", components)
	var normal := transform.basis * Vector3.BACK
	var direction := Vector2(normal.x, normal.z)
	if direction.length_squared() < 0.0001: return
	direction = direction.normalized()
	var side := Vector2(-direction.y, direction.x)
	var distance_x := outer.x / absf(direction.x) if absf(direction.x) > 0.00001 else INF
	var distance_y := outer.y / absf(direction.y) if absf(direction.y) > 0.00001 else INF
	var mark_scale := clampf(sqrt(float(maxi(current_extent.x, current_extent.y))), 1, 1.8)
	var center := direction * (minf(distance_x, distance_y) + 0.65 * mark_scale)
	var points := PackedVector2Array([
		center + direction * 0.36 * mark_scale,
		center + direction * 0.04 * mark_scale + side * 0.23 * mark_scale,
		center + direction * 0.04 * mark_scale + side * 0.09 * mark_scale,
		center - direction * 0.30 * mark_scale + side * 0.09 * mark_scale,
		center - direction * 0.30 * mark_scale - side * 0.09 * mark_scale,
		center + direction * 0.04 * mark_scale - side * 0.09 * mark_scale,
		center + direction * 0.04 * mark_scale - side * 0.23 * mark_scale
	])
	_polygon(points, Color("d87820"), 0.046)
	facing_bounds = AABB(Vector3(points[0].x, 0.046, points[0].y), Vector3.ZERO)
	for point in points: facing_bounds = facing_bounds.expand(Vector3(point.x, 0.046, point.y))
	has_facing_bounds = true
