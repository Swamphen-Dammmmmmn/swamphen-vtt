extends RefCounted

const Images = preload("res://scripts/token_image_store.gd")
const StickerShader = preload("res://shaders/token_sticker.gdshader")

static func face_defaults() -> Dictionary:
	return {"image_id": "", "backing_color": "ffffff", "flip_x": false, "flip_y": false, "ignore_margin": false, "offset": [0.0, 0.0], "scale": 1.0, "rotation_deg": 0.0}

static func defaults() -> Dictionary:
	return {"version": 3, "faces": {"front": face_defaults(), "back": face_defaults()}, "back_shared": false, "back_mirrored": true}

static func migrate(value: Dictionary) -> Dictionary:
	if value.get("version", 1) == 3: return value.duplicate(true)
	var result := defaults()
	for key in face_defaults(): result["faces"]["front"][key] = value.get(key, face_defaults()[key])
	result["back_shared"] = true
	result["back_mirrored"] = value.get("back_mirrored", true)
	return result

static func face(value: Dictionary, name: String) -> Dictionary:
	var normalized := migrate(value)
	return normalized["faces"]["front" if name == "back" and normalized["back_shared"] else name]

static func resource_ids(value: Dictionary) -> Array[String]:
	var normalized := migrate(value)
	var ids: Array[String] = []
	for name in ["front", "back"]:
		var id: String = normalized["faces"][name]["image_id"]
		if not id.is_empty() and not id in ids: ids.append(id)
	return ids

static func validate(value: Variant) -> Dictionary:
	if not value is Dictionary: return {"ok": false, "message": "贴图参数无效。"}
	var version: Variant = value.get("version", 1)
	if not _number(version) or float(version) != floor(float(version)) or int(version) < 1 or int(version) > 3: return {"ok": false, "message": "不支持的贴图参数版本。"}
	if value.get("version", 1) != 3:
		var legacy := _validate_face(value)
		if not legacy["ok"]: return legacy
		if not value.get("back_mirrored") is bool: return {"ok": false, "message": "背面镜像设置无效。"}
		var normalized := defaults()
		normalized["faces"]["front"] = legacy["face"]
		normalized["back_shared"] = true
		normalized["back_mirrored"] = value["back_mirrored"]
		return {"ok": true, "sticker": normalized}
	if not value.get("faces") is Dictionary or not value.get("back_shared") is bool or not value.get("back_mirrored") is bool:
		return {"ok": false, "message": "贴图面设置无效。"}
	var result := defaults()
	for name in ["front", "back"]:
		var checked := _validate_face(value["faces"].get(name))
		if not checked["ok"]: return {"ok": false, "message": ("正面：" if name == "front" else "背面：") + checked["message"]}
		result["faces"][name] = checked["face"]
	result["back_shared"] = value["back_shared"]
	result["back_mirrored"] = value["back_mirrored"]
	return {"ok": true, "sticker": result}

static func _validate_face(value: Variant) -> Dictionary:
	if not value is Dictionary: return {"ok": false, "message": "图片布局无效。"}
	var backing = value.get("backing_color", "ffffff")
	if not backing is String or not Color.html_is_valid(backing): return {"ok": false, "message": "图案背色无效。"}
	var id = value.get("image_id", "")
	if not id is String or (not id.is_empty() and not Images.valid_id(id)): return {"ok": false, "message": "贴图资源编号无效。"}
	var offset = value.get("offset")
	if not offset is Array or offset.size() != 2: return {"ok": false, "message": "贴图位置无效。"}
	for item in offset:
		if not _number(item) or absf(float(item)) > 10: return {"ok": false, "message": "贴图位置须在 -1000%～1000% 之间。"}
	if not _number(value.get("scale")) or float(value["scale"]) < 0.01 or float(value["scale"]) > 10:
		return {"ok": false, "message": "贴图缩放须为 1%～1000%。"}
	if not _number(value.get("rotation_deg")): return {"ok": false, "message": "贴图旋转须为有限数值。"}
	for key in ["flip_x", "flip_y", "ignore_margin"]:
		if not value.get(key, false) is bool: return {"ok": false, "message": "图片翻转或透明留白设置无效。"}
	return {"ok": true, "face": {"backing_color": Color(backing).to_html(false), "flip_x": value.get("flip_x", false), "flip_y": value.get("flip_y", false), "ignore_margin": value.get("ignore_margin", false), "image_id": id, "offset": [float(offset[0]), float(offset[1])], "scale": float(value["scale"]), "rotation_deg": fmod(float(value["rotation_deg"]), 360.0)}}

static func mirror_face(settings: Dictionary) -> Dictionary:
	var result: Dictionary = settings.duplicate(true)
	result["offset"] = [-float(settings["offset"][0]), float(settings["offset"][1])]
	result["rotation_deg"] = -float(settings["rotation_deg"])
	result["flip_x"] = not settings["flip_x"]
	return result

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func attach(standee: MeshInstance3D, component: Dictionary, preview: bool) -> void:
	var specification := migrate(component.get("sticker", defaults()))
	var width := float(component["width_ft"]) / 5.0
	var height := float(component["height_ft"]) / 5.0
	var pure_image: bool = component.get("presentation", "solid") == "image" and not component.has("contour") and not component.get("material", {}).get("board_visible", false)
	var thickness := 0.0 if pure_image else float(component["thickness_ft"]) / 5.0
	for back in [false, true]:
		var settings := face(specification, "back" if back else "front")
		var id: String = settings["image_id"]
		if id.is_empty(): continue
		var texture := Images.texture(id)
		if texture == null:
			standee.set_meta("missing_image", true)
			continue
		var actual := settings.duplicate(true)
		if back and specification["back_shared"] and specification["back_mirrored"]:
			actual = mirror_face(settings)
		_attach_layer(standee, actual, texture, width, height, thickness, back, false, preview, component.get("presentation", "solid") == "image")
		_attach_layer(standee, mirror_face(actual), texture, width, height, thickness, not back, true, preview, component.get("presentation", "solid") == "image")

static func canvas_size(settings: Dictionary, region_size: Vector2, width: float, height: float) -> Vector2:
	var fit := minf(width / region_size.x, height / region_size.y)
	var size := region_size * fit * float(settings["scale"])
	var angle := deg_to_rad(float(settings["rotation_deg"]))
	var half := Vector2(absf(cos(angle)) * size.x + absf(sin(angle)) * size.y, absf(sin(angle)) * size.x + absf(cos(angle)) * size.y) / 2.0
	var offset := Vector2(absf(float(settings["offset"][0]) * width), absf(float(settings["offset"][1]) * height))
	return (half + offset) * 2.0

static func _attach_layer(standee: MeshInstance3D, settings: Dictionary, texture: Texture2D, width: float, height: float, thickness: float, back: bool, backing: bool, preview: bool, expanded: bool) -> void:
	var image_size := Vector2(texture.get_width(), texture.get_height())
	var region := Rect2(Vector2.ZERO, image_size)
	if settings.get("ignore_margin", false):
		var used: Rect2i = texture.get_meta("used_rect", Rect2i(Vector2i.ZERO, Vector2i(image_size)))
		if used.has_area(): region = Rect2(used)
	var fit := minf(width / region.size.x, height / region.size.y)
	var node := MeshInstance3D.new()
	node.name = ("Back" if back else "Front") + ("Backing" if backing else "Image")
	var mesh := QuadMesh.new()
	var canvas := canvas_size(settings, region.size, width, height) if expanded else Vector2(width, height)
	mesh.size = canvas
	node.mesh = mesh
	var gap := maxf(0.00002, minf(width, height) * 0.0002)
	node.position.z = (thickness / 2.0 + gap * (1.0 if backing else 2.0)) * (-1.0 if back else 1.0)
	if back: node.rotation.y = PI
	var material := ShaderMaterial.new()
	material.shader = StickerShader
	# Depth and physical face spacing determine order across different tokens.
	material.render_priority = 0
	material.set_shader_parameter("image_texture", texture)
	material.set_shader_parameter("board_size", canvas)
	material.set_shader_parameter("picture_size", region.size * fit)
	var offset: Array = settings["offset"]
	material.set_shader_parameter("offset_ratio", Vector2(float(offset[0]) * width / canvas.x, -float(offset[1]) * height / canvas.y))
	material.set_shader_parameter("image_region", Vector4(region.position.x / image_size.x, region.position.y / image_size.y, region.size.x / image_size.x, region.size.y / image_size.y))
	material.set_shader_parameter("flip_x", settings["flip_x"])
	material.set_shader_parameter("flip_y", settings["flip_y"])
	material.set_shader_parameter("picture_scale", settings["scale"])
	material.set_shader_parameter("angle", deg_to_rad(float(settings["rotation_deg"])))
	material.set_shader_parameter("backing_only", backing)
	material.set_shader_parameter("backing_color", Color(settings.get("backing_color", "ffffff")))
	material.set_shader_parameter("opacity", 0.65 if preview else 1.0)
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	standee.add_child(node)
