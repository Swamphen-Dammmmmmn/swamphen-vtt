extends RefCounted

const Images = preload("res://scripts/token_image_store.gd")
const Sticker = preload("res://scripts/token_sticker.gd")
const SAMPLE_SIDE := 384
const MAX_SIDE := 512
static var meshes: Dictionary = {}

static func defaults() -> Dictionary:
	return {"hole_sq_in": 0.0, "border_ft": 0.1, "bridge_ft": 0.2, "smooth_pct": 40.0}

static func options_valid(value: Variant) -> bool:
	if not value is Dictionary: return false
	for key in ["hole_sq_in", "border_ft", "bridge_ft"]:
		if not Sticker._number(value.get(key)) or float(value[key]) < 0: return false
	var smooth = value.get("smooth_pct", 0.0)
	return float(value["bridge_ft"]) > 0 and Sticker._number(smooth) and float(smooth) >= 0 and float(smooth) <= 100

static func signature(component: Dictionary) -> String:
	var options: Dictionary = component.get("contour_options", defaults())
	if not component.has("contour_options") and component.has("contour") and int(component["contour"].get("version", 1)) < 3:
		options = options.duplicate()
		options.erase("smooth_pct")
	var parts: Array = [float(component["width_ft"]) if Sticker._number(component["width_ft"]) else component["width_ft"], float(component["height_ft"]) if Sticker._number(component["height_ft"]) else component["height_ft"]]
	for key in ["hole_sq_in", "border_ft", "bridge_ft"]:
		var value = options.get(key)
		parts.append(float(value) if Sticker._number(value) else value)
	# Missing smoothing preserves the signature of legacy contours.
	if options.has("smooth_pct"): parts.append(float(options["smooth_pct"]) if Sticker._number(options["smooth_pct"]) else options["smooth_pct"])
	for name in ["front", "back"]:
		var settings := Sticker.face(component.get("sticker", Sticker.defaults()), name)
		parts.append(settings["image_id"])
		for value in settings["offset"]: parts.append(float(value) if Sticker._number(value) else value)
		parts.append(float(settings["scale"]) if Sticker._number(settings["scale"]) else settings["scale"])
		parts.append(fmod(float(settings["rotation_deg"]), 360.0) if Sticker._number(settings["rotation_deg"]) else settings["rotation_deg"])
		for key in ["flip_x", "flip_y", "ignore_margin"]: parts.append(settings.get(key, false))
	parts.append(Sticker.migrate(component.get("sticker", Sticker.defaults()))["back_mirrored"])
	return JSON.stringify(parts).sha256_text()

static func current(component: Dictionary) -> bool:
	return component.get("contour") is Dictionary and component["contour"].get("signature", "") == signature(component)

static func validate(value: Variant) -> bool:
	if not value is Dictionary: return false
	var version: Variant = value.get("version")
	if not Sticker._number(version) or float(version) != floor(float(version)) or int(version) < 1 or int(version) > 3: return false
	if int(value["version"]) == 3 and (not Sticker._number(value.get("smooth_pct")) or float(value["smooth_pct"]) < 0 or float(value["smooth_pct"]) > 100): return false
	if value.has("connected") and not value["connected"] is bool: return false
	if value.has("parts") and (not Sticker._number(value["parts"]) or float(value["parts"]) != floor(float(value["parts"])) or int(value["parts"]) < 1 or int(value["parts"]) > 128): return false
	for key in ["columns", "rows"]:
		if not Sticker._number(value.get(key)) or float(value[key]) != floor(float(value[key])) or int(value[key]) < 1 or int(value[key]) > MAX_SIDE: return false
	if int(value["version"]) in [2, 3] and (int(value["columns"]) < 3 or int(value["rows"]) < 3): return false
	for key in ["pitch", "origin"]:
		if not value.get(key) is Array or value[key].size() != 2: return false
		for number in value[key]:
			if not Sticker._number(number): return false
	var pitch := Vector2(value["pitch"][0], value["pitch"][1])
	var origin := Vector2(value["origin"][0], value["origin"][1])
	if not pitch.is_finite() or not origin.is_finite() or pitch.x <= 0 or pitch.y <= 0: return false
	if not (origin + pitch * Vector2(value["columns"], value["rows"])).is_finite(): return false
	if not value.get("signature") is String or value["signature"].length() != 64: return false
	if not value.get("mask") is String: return false
	var text: String = value["mask"]
	var byte_count := ceili(float(int(value["columns"]) * int(value["rows"])) / 8.0)
	if text.length() != ceili(float(byte_count) / 3.0) * 4: return false
	var regex := RegEx.new()
	regex.compile("^[A-Za-z0-9+/]+={0,2}$")
	if regex.search(text) == null: return false
	var packed := Marshalls.base64_to_raw(text)
	if packed.size() != byte_count: return false
	var remaining := (int(value["columns"]) * int(value["rows"])) % 8
	if remaining != 0 and (packed[packed.size() - 1] >> remaining) != 0: return false
	if int(value["version"]) in [2, 3]:
		var columns := int(value["columns"])
		var rows := int(value["rows"])
		for x in range(columns):
			for index in [x, (rows - 1) * columns + x]:
				if (packed[index >> 3] >> (index & 7)) & 1: return false
		for y in range(rows):
			for index in [y * columns, y * columns + columns - 1]:
				if (packed[index >> 3] >> (index & 7)) & 1: return false
	for byte in packed:
		if byte != 0: return true
	return false

static func _unpack(data: Dictionary) -> PackedByteArray:
	var packed := Marshalls.base64_to_raw(data["mask"])
	var result := PackedByteArray()
	result.resize(int(data["columns"]) * int(data["rows"]))
	for index in range(result.size()): result[index] = (packed[index >> 3] >> (index & 7)) & 1
	return result

static func _pack(mask: PackedByteArray) -> String:
	var packed := PackedByteArray()
	packed.resize(ceili(float(mask.size()) / 8.0))
	for index in range(mask.size()):
		if mask[index]: packed[index >> 3] |= 1 << (index & 7)
	return Marshalls.raw_to_base64(packed)

static func _error(message: String) -> Dictionary:
	return {"ok": false, "message": message}

static func prepare(component: Dictionary) -> Dictionary:
	var options: Dictionary = component.get("contour_options", defaults())
	if not options_valid(options): return _error("孔洞面积和包边须为非负数，连接条宽须为正数，圆滑程度须为0～100。")
	var width := float(component["width_ft"])
	var height := float(component["height_ft"])
	var specification := Sticker.migrate(component.get("sticker", Sticker.defaults()))
	var sources: Array = []
	var canvas := Vector2.ZERO
	for face_name in ["front", "back"]:
		var settings := Sticker.face(specification, face_name)
		if settings["image_id"].is_empty(): continue
		var loaded := Images.load_image(settings["image_id"])
		if not loaded["ok"]: return _error(loaded["message"])
		var image: Image = loaded["image"]
		var region := Rect2(Vector2.ZERO, Vector2(image.get_size()))
		if settings.get("ignore_margin", false): region = Rect2(image.get_used_rect())
		var needed := Sticker.canvas_size(settings, region.size, width, height)
		canvas.x = maxf(canvas.x, needed.x)
		canvas.y = maxf(canvas.y, needed.y)
		sources.append({"name": face_name, "settings": settings, "image": image, "region": region})
	if sources.is_empty(): return _error("请先导入至少一面的图片。")
	var unit := maxf(canvas.x, canvas.y) / SAMPLE_SIDE
	var columns := maxi(1, ceili(canvas.x / unit))
	var rows := maxi(1, ceili(canvas.y / unit))
	var pitch := Vector2(canvas.x / columns, canvas.y / rows)
	var padding := maxf(float(options["border_ft"]), float(options["bridge_ft"]) / 2.0)
	if padding / minf(pitch.x, pitch.y) > MAX_SIDE: return _error("包边或连接条宽相对立牌尺寸过大，请减小后生成。")
	var pad_x := ceili(padding / pitch.x) + 1
	var pad_y := ceili(padding / pitch.y) + 1
	columns += pad_x * 2
	rows += pad_y * 2
	if columns > MAX_SIDE or rows > MAX_SIDE: return _error("包边相对立牌尺寸过大，请减小包边后生成。")
	var origin := Vector2(-canvas.x / 2 - pad_x * pitch.x, -canvas.y / 2 - pad_y * pitch.y)
	var mask := PackedByteArray()
	mask.resize(columns * rows)
	for source in sources:
		var face_name: String = source["name"]
		var settings: Dictionary = source["settings"]
		var image: Image = source["image"]
		var region: Rect2 = source["region"]
		var fit := minf(width / region.size.x, height / region.size.y)
		var size := region.size * fit * float(settings["scale"])
		var angle := deg_to_rad(float(settings["rotation_deg"]))
		var c := cos(angle)
		var s := sin(angle)
		var offset := Vector2(float(settings["offset"][0]) * width, -float(settings["offset"][1]) * height)
		for y in range(pad_y, rows - pad_y):
			for x in range(pad_x, columns - pad_x):
				var point := origin + (Vector2(x, y) + Vector2.ONE * 0.5) * pitch
				if face_name == "back": point.x = -point.x
				if face_name == "back" and specification["back_shared"] and specification["back_mirrored"]: point.x = -point.x
				point -= offset
				var uv := Vector2(c * point.x + s * point.y, -s * point.x + c * point.y) / size + Vector2.ONE * 0.5
				if uv.x < 0 or uv.y < 0 or uv.x >= 1 or uv.y >= 1: continue
				if settings["flip_x"]: uv.x = 1 - uv.x
				if settings["flip_y"]: uv.y = 1 - uv.y
				var at := region.position + uv * region.size
				if image.get_pixel(clampi(int(at.x), 0, image.get_width() - 1), clampi(int(at.y), 0, image.get_height() - 1)).a >= 0.05:
					mask[y * columns + x] = 1
	if not mask.has(1): return _error("当前图片布局没有可见轮廓，请调整图片位置或缩放。")
	var protected := mask.duplicate()
	_fill_holes(mask, columns, rows, float(options["hole_sq_in"]), pitch)
	if float(options["border_ft"]) > 0: mask = _dilate(mask, columns, rows, pitch, float(options["border_ft"]))
	var islands := _regions(mask, columns, rows, 1)
	if islands.size() > 128: return _error("检测到超过128个分离部分，请先清理图片中的细碎区域。")
	return {"ok": true, "mask": mask, "protected": protected, "columns": columns, "rows": rows, "origin": origin, "pitch": pitch, "islands": islands, "options": options, "signature": signature(component)}

static func _regions(mask: PackedByteArray, columns: int, rows: int, value: int) -> Array:
	var seen := PackedByteArray()
	seen.resize(mask.size())
	var result: Array = []
	for index in range(mask.size()):
		if seen[index] or mask[index] != value: continue
		var queue := PackedInt32Array([index])
		seen[index] = 1
		var head := 0
		while head < queue.size():
			var current_index := queue[head]
			head += 1
			var x := current_index % columns
			var y := current_index / columns
			for next in [current_index - 1 if x > 0 else -1, current_index + 1 if x + 1 < columns else -1, current_index - columns if y > 0 else -1, current_index + columns if y + 1 < rows else -1]:
				if next < 0 or seen[next] or mask[next] != value: continue
				seen[next] = 1
				queue.append(next)
		result.append(queue)
	return result

static func _fill_holes(mask: PackedByteArray, columns: int, rows: int, area: float, pitch: Vector2) -> void:
	if area <= 0: return
	for region in _regions(mask, columns, rows, 0):
		var open := false
		for index in region:
			if index % columns == 0 or index % columns == columns - 1 or index < columns or index >= (rows - 1) * columns:
				open = true
				break
		if not open and region.size() * pitch.x * pitch.y * 144.0 <= area:
			for index in region: mask[index] = 1

# Exact separable squared Euclidean distance transform in physical units.
static func _distance_line(values: PackedFloat64Array, weight: float) -> PackedFloat64Array:
	var count := values.size()
	var vertices := PackedInt32Array()
	vertices.resize(count)
	var breaks := PackedFloat64Array()
	breaks.resize(count + 1)
	var k := 0
	breaks[0] = -INF
	breaks[1] = INF
	for q in range(1, count):
		var cut := ((values[q] + weight * q * q) - (values[vertices[k]] + weight * vertices[k] * vertices[k])) / (2.0 * weight * (q - vertices[k]))
		while k > 0 and cut <= breaks[k]:
			k -= 1
			cut = ((values[q] + weight * q * q) - (values[vertices[k]] + weight * vertices[k] * vertices[k])) / (2.0 * weight * (q - vertices[k]))
		k += 1
		vertices[k] = q
		breaks[k] = cut
		breaks[k + 1] = INF
	var result := PackedFloat64Array()
	result.resize(count)
	k = 0
	for q in range(count):
		while breaks[k + 1] < q: k += 1
		result[q] = weight * (q - vertices[k]) * (q - vertices[k]) + values[vertices[k]]
	return result

static func _dilate(mask: PackedByteArray, columns: int, rows: int, pitch: Vector2, radius: float) -> PackedByteArray:
	var distances := PackedFloat64Array()
	distances.resize(mask.size())
	for y in range(rows):
		var line := PackedFloat64Array()
		line.resize(columns)
		for x in range(columns): line[x] = 0.0 if mask[y * columns + x] else 1.0e12
		line = _distance_line(line, pitch.x * pitch.x)
		for x in range(columns): distances[y * columns + x] = line[x]
	var result := mask.duplicate()
	for x in range(columns):
		var line := PackedFloat64Array()
		line.resize(rows)
		for y in range(rows): line[y] = distances[y * columns + x]
		line = _distance_line(line, pitch.y * pitch.y)
		for y in range(rows):
			if line[y] <= radius * radius: result[y * columns + x] = 1
	return result

static func finish(prepared: Dictionary, connect: bool) -> Dictionary:
	var mask: PackedByteArray = prepared["mask"].duplicate()
	if connect and prepared["islands"].size() > 1:
		if float(prepared["options"]["bridge_ft"]) < prepared["pitch"].length() * 1.02: return _error("连接条宽小于当前轮廓精度，请增大连接条宽。")
		_connect(mask, prepared["columns"], prepared["rows"], prepared["pitch"], prepared["islands"], float(prepared["options"]["bridge_ft"]))
		if _regions(mask, prepared["columns"], prepared["rows"], 1).size() > 1: return _error("连接条未能连接全部部分，请增大连接条宽后重新生成。")
	var smooth := float(prepared["options"].get("smooth_pct", 0.0))
	if smooth > 0: mask = _smooth_mask(mask, prepared["columns"], prepared["rows"], smooth, prepared["protected"])
	return {"ok": true, "contour": {"version": 3, "smooth_pct": smooth, "columns": prepared["columns"], "rows": prepared["rows"], "pitch": [prepared["pitch"].x, prepared["pitch"].y], "origin": [prepared["origin"].x, prepared["origin"].y], "mask": _pack(mask), "signature": prepared["signature"], "connected": connect, "parts": prepared["islands"].size()}}

static func _root(parents: PackedInt32Array, index: int) -> int:
	while parents[index] != index: index = parents[index]
	return index

static func _connect(mask: PackedByteArray, columns: int, rows: int, pitch: Vector2, islands: Array, width: float) -> void:
	var owner := PackedInt32Array()
	var seed := PackedInt32Array()
	var distance := PackedInt32Array()
	owner.resize(mask.size())
	owner.fill(-1)
	seed.resize(mask.size())
	distance.resize(mask.size())
	var queue := PackedInt32Array()
	for island in range(islands.size()):
		for index in islands[island]:
			owner[index] = island
			seed[index] = index
			queue.append(index)
	var candidates: Dictionary = {}
	var head := 0
	while head < queue.size():
		var index := queue[head]
		head += 1
		var x := index % columns
		var y := index / columns
		for next in [index - 1 if x > 0 else -1, index + 1 if x + 1 < columns else -1, index - columns if y > 0 else -1, index + columns if y + 1 < rows else -1]:
			if next < 0: continue
			if owner[next] == -1:
				owner[next] = owner[index]
				seed[next] = seed[index]
				distance[next] = distance[index] + 1
				queue.append(next)
			elif owner[next] != owner[index]:
				var a := mini(owner[next], owner[index])
				var b := maxi(owner[next], owner[index])
				var key := a * islands.size() + b
				var length := distance[next] + distance[index]
				if not candidates.has(key) or length < candidates[key]["length"]:
					candidates[key] = {"a": a, "b": b, "start": seed[index], "end": seed[next], "length": length}
	var edges: Array = candidates.values()
	edges.sort_custom(func(a: Dictionary, b: Dictionary): return a["length"] < b["length"])
	var parents := PackedInt32Array()
	for index in range(islands.size()): parents.append(index)
	for edge in edges:
		var a := _root(parents, edge["a"])
		var b := _root(parents, edge["b"])
		if a == b: continue
		parents[a] = b
		var start := (Vector2(int(edge["start"]) % columns, int(edge["start"]) / columns) + Vector2.ONE * 0.5) * pitch
		var end := (Vector2(int(edge["end"]) % columns, int(edge["end"]) / columns) + Vector2.ONE * 0.5) * pitch
		var radius := width / 2.0
		for y in range(maxi(0, floori((minf(start.y, end.y) - radius) / pitch.y)), mini(rows, ceili((maxf(start.y, end.y) + radius) / pitch.y))):
			for x in range(maxi(0, floori((minf(start.x, end.x) - radius) / pitch.x)), mini(columns, ceili((maxf(start.x, end.x) + radius) / pitch.x))):
				var point := (Vector2(x, y) + Vector2.ONE * 0.5) * pitch
				if point.distance_to(Geometry2D.get_closest_point_to_segment(point, start, end)) <= radius: mask[y * columns + x] = 1

static func face_edges(data: Dictionary, thickness_ft: float, back: bool) -> PackedVector3Array:
	var arrays := mesh(data, thickness_ft).surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var plane_z := thickness_ft / 10.0 * (-1.0 if back else 1.0)
	var result := PackedVector3Array()
	for index in range(0, vertices.size(), 3):
		if absf(normals[index].z) > 0.5: continue
		var endpoints := PackedVector3Array()
		for corner in range(3):
			var point := vertices[index + corner]
			if absf(point.z - plane_z) < absf(plane_z) * 0.00001:
				point.z += -0.001 if back else 0.001
				endpoints.append(point)
		if endpoints.size() == 2: result.append_array(endpoints)
	return result

static func _quad(surface: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3) -> void:
	surface.set_normal(normal)
	for point in [a, c, b, a, d, c]: surface.add_vertex(point)

static func mesh(data: Dictionary, thickness_ft: float) -> Mesh:
	var key := (JSON.stringify(data) + str(thickness_ft)).sha256_text()
	if meshes.has(key): return meshes[key]
	if int(data["version"]) in [2, 3]:
		var smooth := _interpolated_mesh(data, thickness_ft)
		while meshes.size() >= 8: meshes.erase(meshes.keys()[0])
		meshes[key] = smooth
		return smooth
	var columns := int(data["columns"])
	var rows := int(data["rows"])
	var mask := _unpack(data)
	var used := PackedByteArray()
	used.resize(mask.size())
	var pitch := Vector2(data["pitch"][0], data["pitch"][1]) / 5.0
	var origin := Vector2(data["origin"][0], data["origin"][1]) / 5.0
	var depth := thickness_ft / 10.0
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for y in range(rows):
		for x in range(columns):
			var index := y * columns + x
			if not mask[index] or used[index]: continue
			var right := x + 1
			while right < columns and mask[y * columns + right] and not used[y * columns + right]: right += 1
			var bottom := y + 1
			while bottom < rows:
				var complete := true
				for at in range(x, right):
					if not mask[bottom * columns + at] or used[bottom * columns + at]: complete = false; break
				if not complete: break
				bottom += 1
			for yy in range(y, bottom):
				for xx in range(x, right): used[yy * columns + xx] = 1
			var left_x := origin.x + x * pitch.x
			var right_x := origin.x + right * pitch.x
			var top_y := -(origin.y + y * pitch.y)
			var bottom_y := -(origin.y + bottom * pitch.y)
			_quad(surface, Vector3(left_x, bottom_y, depth), Vector3(right_x, bottom_y, depth), Vector3(right_x, top_y, depth), Vector3(left_x, top_y, depth), Vector3.BACK)
			_quad(surface, Vector3(left_x, top_y, -depth), Vector3(right_x, top_y, -depth), Vector3(right_x, bottom_y, -depth), Vector3(left_x, bottom_y, -depth), Vector3.FORWARD)
	# Merge exposed edges into runs; includes every retained hole boundary.
	for y in range(rows + 1):
		for sign_value in [-1, 1]:
			var x := 0
			while x < columns:
				var above: bool = y > 0 and mask[(y - 1) * columns + x] == 1
				var below: bool = y < rows and mask[y * columns + x] == 1
				if not (above and not below if sign_value == -1 else below and not above): x += 1; continue
				var start := x
				x += 1
				while x < columns:
					above = y > 0 and mask[(y - 1) * columns + x] == 1
					below = y < rows and mask[y * columns + x] == 1
					if not (above and not below if sign_value == -1 else below and not above): break
					x += 1
				var left_x := origin.x + start * pitch.x
				var right_x := origin.x + x * pitch.x
				var at_y := -(origin.y + y * pitch.y)
				var a := Vector3(left_x, at_y, -depth)
				var b := Vector3(right_x, at_y, -depth)
				var c := Vector3(right_x, at_y, depth)
				var d := Vector3(left_x, at_y, depth)
				if sign_value == 1: _quad(surface, d, c, b, a, Vector3.UP)
				else: _quad(surface, a, b, c, d, Vector3.DOWN)
	for x in range(columns + 1):
		for sign_value in [-1, 1]:
			var y := 0
			while y < rows:
				var left: bool = x > 0 and mask[y * columns + x - 1] == 1
				var right: bool = x < columns and mask[y * columns + x] == 1
				if not (right and not left if sign_value == -1 else left and not right): y += 1; continue
				var start := y
				y += 1
				while y < rows:
					left = x > 0 and mask[y * columns + x - 1] == 1
					right = x < columns and mask[y * columns + x] == 1
					if not (right and not left if sign_value == -1 else left and not right): break
					y += 1
				var at_x := origin.x + x * pitch.x
				var top_y := -(origin.y + start * pitch.y)
				var bottom_y := -(origin.y + y * pitch.y)
				var a := Vector3(at_x, bottom_y, -depth)
				var b := Vector3(at_x, top_y, -depth)
				var c := Vector3(at_x, top_y, depth)
				var d := Vector3(at_x, bottom_y, depth)
				if sign_value == -1: _quad(surface, d, c, b, a, Vector3.LEFT)
				else: _quad(surface, a, b, c, d, Vector3.RIGHT)
	var result := surface.commit()
	while meshes.size() >= 8: meshes.erase(meshes.keys()[0])
	meshes[key] = result
	return result

static func _interpolated_mesh(data: Dictionary, thickness_ft: float) -> Mesh:
	var columns := int(data["columns"])
	var rows := int(data["rows"])
	var mask := _unpack(data)
	var field := _boundary_field(mask, columns, rows, float(data.get("smooth_pct", 0.0))) if int(data["version"]) == 3 else _legacy_field(mask, columns, rows)
	var width := columns - 1
	var height := rows - 1
	var codes := PackedByteArray()
	codes.resize(width * height)
	for y in range(height):
		for x in range(width):
			codes[y * width + x] = mask[y * columns + x] + mask[y * columns + x + 1] * 2 + mask[(y + 1) * columns + x + 1] * 4 + mask[(y + 1) * columns + x] * 8
	var used := PackedByteArray()
	used.resize(codes.size())
	var pitch := Vector2(data["pitch"][0], data["pitch"][1]) / 5.0
	var origin := Vector2(data["origin"][0], data["origin"][1]) / 5.0
	var depth := thickness_ft / 10.0
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var shapes := {
		1: [[0, 4, 7]], 2: [[4, 1, 5]], 3: [[0, 1, 5, 7]],
		4: [[5, 2, 6]], 5: [[0, 4, 7], [5, 2, 6]], 6: [[4, 1, 2, 6]],
		7: [[0, 1, 2, 6, 7]], 8: [[7, 6, 3]], 9: [[0, 4, 6, 3]],
		10: [[4, 1, 5], [7, 6, 3]], 11: [[0, 1, 5, 6, 3]],
		12: [[7, 5, 2, 3]], 13: [[0, 4, 5, 2, 3]], 14: [[4, 1, 2, 3, 7]]
	}
	for y in range(height):
		for x in range(width):
			var code := int(codes[y * width + x])
			if code == 0 or used[y * width + x]: continue
			var corner := origin + (Vector2(x, y) + Vector2.ONE * 0.5) * pitch
			if code == 15:
				var right := x + 1
				while right < width and codes[y * width + right] == 15 and not used[y * width + right]: right += 1
				var bottom := y + 1
				while bottom < height:
					var complete := true
					for xx in range(x, right):
						if codes[bottom * width + xx] != 15 or used[bottom * width + xx]: complete = false; break
					if not complete: break
					bottom += 1
				for yy in range(y, bottom):
					for xx in range(x, right): used[yy * width + xx] = 1
				var polygon := PackedVector2Array([corner, corner + Vector2((right - x) * pitch.x, 0), corner + Vector2(right - x, bottom - y) * pitch, corner + Vector2(0, (bottom - y) * pitch.y)])
				_cap(surface, polygon, depth)
				continue
			var values := [field[y * columns + x], field[y * columns + x + 1], field[(y + 1) * columns + x + 1], field[(y + 1) * columns + x]]
			var points := [Vector2.ZERO, Vector2.RIGHT, Vector2.ONE, Vector2.DOWN]
			points.append(Vector2(_crossing(values[0], values[1]), 0))
			points.append(Vector2(1, _crossing(values[1], values[2])))
			points.append(Vector2(_crossing(values[3], values[2]), 1))
			points.append(Vector2(0, _crossing(values[0], values[3])))
			for indices in shapes[code]:
				var polygon := PackedVector2Array()
				for index in indices: polygon.append(corner + points[index] * pitch)
				_cap(surface, polygon, depth)
				for index in range(indices.size()):
					var from: Vector2 = points[indices[index]]
					var to: Vector2 = points[indices[(index + 1) % indices.size()]]
					# Grid-cell boundaries belong to neighboring caps, not exposed sides.
					if (from.x == to.x and (from.x == 0 or from.x == 1)) or (from.y == to.y and (from.y == 0 or from.y == 1)): continue
					var a2 := corner + from * pitch
					var b2 := corner + to * pitch
					var delta := b2 - a2
					var normal := Vector3(delta.y, delta.x, 0).normalized()
					var a := Vector3(a2.x, -a2.y, -depth)
					var b := Vector3(b2.x, -b2.y, -depth)
					var c := Vector3(b2.x, -b2.y, depth)
					var d := Vector3(a2.x, -a2.y, depth)
					if int(data["version"]) == 3 and float(data.get("smooth_pct", 0.0)) > 0:
						var na := _edge_normal(field, columns, rows, Vector2(x, y) + from, pitch, normal)
						var nb := _edge_normal(field, columns, rows, Vector2(x, y) + to, pitch, normal)
						for item in [[b, nb], [d, na], [a, na], [b, nb], [c, nb], [d, na]]:
							surface.set_normal(item[1])
							surface.add_vertex(item[0])
					else: _quad(surface, b, a, d, c, normal)
	return surface.commit()

static func _crossing(a: float, b: float) -> float:
	return clampf((0.5 - a) / (b - a), 0.0, 1.0) if absf(b - a) > 0.000001 else 0.5

static func _cap(surface: SurfaceTool, polygon: PackedVector2Array, depth: float) -> void:
	for back in [false, true]:
		surface.set_normal(Vector3.FORWARD if back else Vector3.BACK)
		var z := -depth if back else depth
		for index in range(1, polygon.size() - 1):
			for vertex in [0, index + 1, index] if back else [0, index, index + 1]:
				var point := polygon[vertex]
				surface.add_vertex(Vector3(point.x, -point.y, z))

static func _legacy_field(mask: PackedByteArray, columns: int, rows: int) -> PackedFloat32Array:
	var field := PackedFloat32Array()
	field.resize(mask.size())
	for y in range(rows):
		for x in range(columns):
			var sum := 0.0
			for yy in range(maxi(0, y - 1), mini(rows, y + 2)):
				for xx in range(maxi(0, x - 1), mini(columns, x + 2)):
					sum += mask[yy * columns + xx] * (2.0 if xx == x else 1.0) * (2.0 if yy == y else 1.0)
			# Retain every binary corner's inside/outside classification.
			field[y * columns + x] = mask[y * columns + x] * 0.7 + sum / 16.0 * 0.3
	return field

# Separable Gaussian filtering controls the boundary, not the source texture.
static func _blur(mask: PackedByteArray, columns: int, rows: int, strength: float) -> PackedFloat32Array:
	var sigma := 0.6 + strength / 100.0 * 3.4
	var radius := ceili(sigma * 3.0)
	var weights := PackedFloat32Array()
	var total := 0.0
	for index in range(-radius, radius + 1):
		var weight := exp(-float(index * index) / (2.0 * sigma * sigma))
		weights.append(weight)
		total += weight
	var intermediate := PackedFloat32Array()
	intermediate.resize(mask.size())
	for y in range(rows):
		for x in range(columns):
			var value := 0.0
			for dx in range(-radius, radius + 1):
				var xx := x + dx
				if xx >= 0 and xx < columns: value += mask[y * columns + xx] * weights[dx + radius]
			intermediate[y * columns + x] = value / total
	var result := PackedFloat32Array()
	result.resize(mask.size())
	for y in range(rows):
		for x in range(columns):
			var value := 0.0
			for dy in range(-radius, radius + 1):
				var yy := y + dy
				if yy >= 0 and yy < rows: value += intermediate[yy * columns + x] * weights[dy + radius]
			result[y * columns + x] = value / total
	return result

# Conservative local topology guard for both foreground and background.
static func _neighbor_groups(mask: PackedByteArray, at: int, columns: int, value: int, diagonal: bool) -> int:
	var cells := PackedByteArray()
	cells.resize(9)
	for y in range(3):
		for x in range(3):
			if x == 1 and y == 1: continue
			cells[y * 3 + x] = 1 if mask[at + (y - 1) * columns + x - 1] == value else 0
	var count := 0
	for index in range(9):
		if not cells[index]: continue
		count += 1
		var queue: Array[int] = [index]
		cells[index] = 0
		while not queue.is_empty():
			var current_index: int = queue.pop_back()
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if dx == 0 and dy == 0: continue
					if not diagonal and abs(dx) + abs(dy) != 1: continue
					var x := current_index % 3 + dx
					var y := int(current_index / 3) + dy
					if x < 0 or x > 2 or y < 0 or y > 2: continue
					var next := y * 3 + x
					if cells[next]:
						cells[next] = 0
						queue.append(next)
	return count

static func _smooth_mask(original: PackedByteArray, columns: int, rows: int, strength: float, protected: PackedByteArray) -> PackedByteArray:
	var mask := original.duplicate()
	var field := _blur(original, columns, rows, strength)
	var candidates: Array[int] = []
	for y in range(1, rows - 1):
		for x in range(1, columns - 1):
			var at := y * columns + x
			if (field[at] >= 0.5) != (mask[at] == 1): candidates.append(at)
	candidates.sort_custom(func(a: int, b: int):
		var first := absf(field[a] - 0.5)
		var second := absf(field[b] - 0.5)
		return a < b if first == second else first > second
	)
	# Confidence order, one cell at a time: never erase a hole, part, or bridge.
	for at in candidates:
		if protected[at] and mask[at]: continue
		if _neighbor_groups(mask, at, columns, 1, false) != 1 or _neighbor_groups(mask, at, columns, 0, false) != 1: continue
		if _neighbor_groups(mask, at, columns, 1, true) != 1 or _neighbor_groups(mask, at, columns, 0, true) != 1: continue
		mask[at] = 1 - mask[at]
	return mask

static func _boundary_field(mask: PackedByteArray, columns: int, rows: int, strength: float) -> PackedFloat32Array:
	var field := PackedFloat32Array()
	if strength <= 0:
		for value in mask: field.append(float(value))
		return field
	field = _blur(mask, columns, rows, strength)
	for index in range(mask.size()):
		# Retain corner signs during interpolation to protect topology.
		field[index] = maxf(0.501, field[index]) if mask[index] else minf(0.499, field[index])
	return field

static func _edge_normal(field: PackedFloat32Array, columns: int, rows: int, at: Vector2, pitch: Vector2, fallback: Vector3) -> Vector3:
	var x := clampi(roundi(at.x), 1, columns - 2)
	var y := clampi(roundi(at.y), 1, rows - 2)
	var dx := (field[y * columns + x + 1] - field[y * columns + x - 1]) / pitch.x
	var dy := (field[(y + 1) * columns + x] - field[(y - 1) * columns + x]) / pitch.y
	var normal := Vector3(-dx, dy, 0)
	return normal.normalized() if normal.length_squared() > 0.000001 and normal.dot(fallback) > 0 else fallback
