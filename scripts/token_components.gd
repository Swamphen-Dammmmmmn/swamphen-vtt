extends RefCounted

const Contour = preload("res://scripts/token_contour.gd")
const InvisibleSurface = preload("res://shaders/token_image_carrier.gdshader")
const Sticker = preload("res://scripts/token_sticker.gd")
const Footprint = preload("res://scripts/token_footprint.gd")
const Appearance = preload("res://scripts/token_appearance.gd")
const Acrylic = preload("res://scripts/token_acrylic.gd")
const Surface = preload("res://scripts/token_surface.gd")
const FEET_PER_CELL := 5.0
const BOUNDARY_EPSILON := 0.000001

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _vector(value: Variant, count: int) -> bool:
	if not value is Array or value.size() != count:
		return false
	for item in value:
		if not _number(item):
			return false
	return true

static func _error(field: String, message: String) -> Dictionary:
	return {"ok": false, "field": field, "message": message}

static func validate(raw: Dictionary, extent: Vector2i, enforce_bounds := true) -> Dictionary:
	if not Footprint.valid({"width": extent.x, "length": extent.y}):
		return _error("footprint", "实际占地无效。")
	var components: Dictionary = {}
	var bounds := AABB()
	var has_bounds := false
	var outside: Array[String] = []
	for name in ["base", "standee"]:
		if not raw.get(name) is Dictionary:
			return _error(name, "底座和立牌参数必须同时提供。")
		var source: Dictionary = raw[name]
		var allowed := ["rectangle", "circle", "ellipse", "polygon", "hexagon"] if name == "base" else ["rectangle"]
		if source.get("shape") not in allowed or not source.get("visible") is bool:
			return _error(name, "组件样式或显示设置无效。")
		if source.get("shape") == "polygon" and (not _number(source.get("sides")) or float(source["sides"]) != floor(float(source["sides"])) or int(source["sides"]) < 3 or int(source["sides"]) > 12):
			return _error("base.sides", "多边形边数须为 3～12 的整数。")
		if name == "base" and source.get("shape") == "circle" and source.get("width_ft") != source.get("length_ft"):
			return _error("base", "圆形底座的宽长必须相同。")
		var dimension_keys := ["width_ft", "length_ft", "thickness_ft"] if name == "base" else ["width_ft", "height_ft", "thickness_ft"]
		for key in dimension_keys:
			if not _number(source.get(key)) or float(source[key]) <= 0:
				return _error(name + "." + key, "组件尺寸须为有限正数，单位为英尺。")
			var represented := Vector3(float(source[key]) / FEET_PER_CELL, 0, 0)
			if not represented.is_finite() or represented.x <= 0:
				return _error(name + "." + key, "尺寸超出引擎可表示的精度范围。")
		if not (_vector(source.get("offset_ft"), 2) or _vector(source.get("offset_ft"), 3)) or not _vector(source.get("rotation_deg"), 3):
			return _error(name, "位置和旋转须为有效的有限数值。")
		if not source.get("color") is String or not Color.html_is_valid(source["color"]):
			return _error(name + ".color", "组件颜色无效。")
		var component := source.duplicate(true)
		if component["offset_ft"].size() == 2:
			component["offset_ft"] = [component["offset_ft"][0], 0.0, component["offset_ft"][1]]
			if name == "standee":
				# Preserve legacy bottom-pivot appearance when migrating to a center pivot.
				var angles: Array = component["rotation_deg"]
				var old_basis := Basis.from_euler(Vector3(deg_to_rad(fmod(float(angles[0]), 360.0)), deg_to_rad(fmod(float(angles[1]), 360.0)), deg_to_rad(fmod(float(angles[2]), 360.0))))
				var center := Vector3.UP * float(component["height_ft"]) / 2.0
				var compensation := old_basis * center - center
				component["offset_ft"][0] += compensation.x
				component["offset_ft"][1] += compensation.y
				component["offset_ft"][2] += compensation.z
		component["color"] = Color(source["color"]).to_html(false)
		if name == "standee":
			if source.get("presentation", "solid") not in ["solid", "image"]:
				return _error("standee.presentation", "立牌类型无效。")
			component["presentation"] = source.get("presentation", "solid")
			var acrylic: Variant = source.get("acrylic", Acrylic.defaults())
			if not Acrylic.valid(acrylic): return _error("standee.acrylic", "亚克力材质参数无效：不透明度须为0～60%，粗糙度须为5～80%，颜色须有效。")
			component["acrylic"] = acrylic.duplicate(true)
			component["acrylic"]["color"] = Color(acrylic["color"]).to_html(false)
			if not Contour.options_valid(source.get("contour_options", Contour.defaults())):
				return _error("standee.contour", "轮廓参数无效：面积、包边须非负，连接条宽须为正数，圆滑程度须为0～100。")
			if source.has("contour") and not Contour.validate(source["contour"]):
				return _error("standee.contour", "轮廓数据无效，请重新生成。")
			var sticker := Sticker.validate(source.get("sticker", Sticker.defaults()))
			if not sticker["ok"]: return _error("standee.sticker", sticker["message"])
			component["sticker"] = sticker["sticker"]
			if enforce_bounds and component["presentation"] == "image" and Sticker.resource_ids(component["sticker"]).is_empty():
				return _error("standee.sticker", "图片立牌至少需要一面的图片。")
			if enforce_bounds and component["presentation"] == "image" and component.has("contour") and not Contour.current(component):
				return _error("standee.contour", "轮廓需要重新生成。")
		if source.has("material") and not Surface.valid(source.material):
			return _error(name + ".material", "材质参数无效，请检查颜色、不透明度、粗糙度和颗粒强度。")
		component.material = Surface.for_component(component, name)
		component.color = Color(component.material.color).to_html(false)
		component.material.color = component.color
		components[name] = component
	# Generate once; bounds inspect the same vertices and transforms used to render.
	for name in ["base", "standee"]:
		var component: Dictionary = components[name]
		var mesh := _mesh(component, name)
		var transform := _transform(component, name, components)
		var component_bounds := _bounds(mesh, transform)
		if not component_bounds.position.is_finite() or not component_bounds.end.is_finite():
			return _error(name, "尺寸或变换超出引擎可表示的范围。")
		if not component["visible"]:
			continue
		var margin := 0.0 if name == "base" else 1.0
		var half := Vector2(extent) / 2.0 + Vector2.ONE * margin
		if component_bounds.position.x < -half.x - BOUNDARY_EPSILON or component_bounds.end.x > half.x + BOUNDARY_EPSILON or component_bounds.position.z < -half.y - BOUNDARY_EPSILON or component_bounds.end.z > half.y + BOUNDARY_EPSILON:
			outside.append(name)
		bounds = bounds.merge(component_bounds) if has_bounds else component_bounds
		has_bounds = true
	if enforce_bounds and not outside.is_empty():
		return _error(outside[0], "底座超出实际占地。" if outside[0] == "base" else "立牌超出占地每侧外扩一格的范围。")
	return {"ok": true, "components": components, "bounds": bounds, "has_visible_geometry": has_bounds, "outside": outside}

static func _mesh(component: Dictionary, name: String) -> Mesh:
	var width := float(component["width_ft"]) / FEET_PER_CELL
	var thickness := float(component["thickness_ft"]) / FEET_PER_CELL
	if name == "standee" and component.get("presentation", "solid") == "image":
		if component.has("contour"): return Contour.mesh(component["contour"], float(component["thickness_ft"]))
		if component.get("material", {}).get("board_visible", false):
			var board := BoxMesh.new()
			board.size = Vector3(width, float(component["height_ft"]) / FEET_PER_CELL, thickness)
			return board
		var plane := QuadMesh.new()
		plane.size = Vector2(width, float(component["height_ft"]) / FEET_PER_CELL)
		return plane
	if name == "standee" or component["shape"] == "rectangle":
		var box := BoxMesh.new()
		box.size = Vector3(width, thickness, float(component["length_ft"]) / FEET_PER_CELL) if name == "base" else Vector3(width, float(component["height_ft"]) / FEET_PER_CELL, thickness)
		return box
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = 0.5
	cylinder.bottom_radius = 0.5
	cylinder.height = thickness
	cylinder.radial_segments = int(component["sides"]) if component["shape"] == "polygon" else (6 if component["shape"] == "hexagon" else 32)
	# Normalize actual polygon bounds before stretching, including odd side counts.
	if component["shape"] in ["polygon", "hexagon"]:
		var bounds := cylinder.get_aabb()
		var surface := SurfaceTool.new()
		surface.begin(Mesh.PRIMITIVE_TRIANGLES)
		surface.set_smooth_group(-1)
		for point in cylinder.get_faces():
			point.x = (point.x - bounds.get_center().x) / bounds.size.x
			point.z = (point.z - bounds.get_center().z) / bounds.size.z
			surface.add_vertex(point)
		surface.generate_normals()
		return surface.commit()
	return cylinder

static func _transform(component: Dictionary, name: String, components: Dictionary) -> Transform3D:
	var angles: Array = component["rotation_deg"]
	var basis := Basis.from_euler(Vector3(deg_to_rad(fmod(float(angles[0]), 360.0)), deg_to_rad(fmod(float(angles[1]), 360.0)), deg_to_rad(fmod(float(angles[2]), 360.0))))
	if name == "base" and component["shape"] != "rectangle":
		basis = basis * Basis.from_scale(Vector3(float(component["width_ft"]) / FEET_PER_CELL, 1, float(component["length_ft"]) / FEET_PER_CELL))
	var offset: Array = component["offset_ft"]
	if offset.size() == 2: offset = [offset[0], 0.0, offset[1]]
	var height := float(component["thickness_ft"]) / FEET_PER_CELL / 2.0
	if name == "standee":
		height = 0.0
		if components["base"]["visible"]:
			height += float(components["base"]["thickness_ft"]) / FEET_PER_CELL
	var origin := Vector3(float(offset[0]) / FEET_PER_CELL, height + float(offset[1]) / FEET_PER_CELL, float(offset[2]) / FEET_PER_CELL)
	if name == "standee":
		origin += Vector3.UP * (float(component["height_ft"]) / FEET_PER_CELL / 2.0)
	return Transform3D(basis, origin)

static func _bounds(mesh: Mesh, transform: Transform3D) -> AABB:
	var faces := mesh.get_faces()
	var result := AABB(transform * faces[0], Vector3.ZERO)
	for vertex in faces:
		result = result.expand(transform * vertex)
	return result

static func build(validated: Dictionary, preview := false) -> Node3D:
	assert(validated.get("ok", false), "生成组件前必须先通过校验。")
	var root := Node3D.new()
	var components: Dictionary = validated["components"]
	for name in ["base", "standee"]:
		var component: Dictionary = components[name]
		var node := MeshInstance3D.new()
		node.name = "Base" if name == "base" else "Standee"
		node.mesh = _mesh(component, name)
		node.transform = _transform(component, name, components)
		node.visible = component["visible"]
		node.material_override = Appearance.material(Color("ce5353"), preview) if validated.get("outside", []).has(name) else Surface.material(component.material, name, preview)
		if preview:
			node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if name == "standee":
			if component.get("presentation", "solid") == "image":
				if preview or not component.material.board_visible or float(component.material.opacity) < 0.9999:
					node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			Sticker.attach(node, component, preview)
		root.add_child(node)
	root.set_meta("appearance_bounds", validated["bounds"])
	return root

static func projection(component: Dictionary, name: String, components: Dictionary) -> PackedVector2Array:
	var vertices := PackedVector2Array()
	var transform := _transform(component, name, components)
	for point in _mesh(component, name).get_faces():
		var at := transform * point
		vertices.append(Vector2(at.x, at.z))
	var hull := Geometry2D.convex_hull(vertices)
	if hull.size() > 1 and hull[0] == hull[-1]: hull.remove_at(hull.size() - 1)
	return hull

static func defaults() -> Dictionary:
	return {"base": {"shape": "circle", "visible": true, "color": "225ca8", "width_ft": 4.3, "length_ft": 4.3, "thickness_ft": 0.75, "offset_ft": [0.0, 0.0, 0.0], "rotation_deg": [0.0, 0.0, 0.0], "sides": 6}, "standee": {"shape": "rectangle", "visible": true, "color": "2e7ae0", "width_ft": 3.5, "height_ft": 4.25, "thickness_ft": 0.7, "offset_ft": [0.0, 0.0, 0.0], "rotation_deg": [0.0, 0.0, 0.0]}}
