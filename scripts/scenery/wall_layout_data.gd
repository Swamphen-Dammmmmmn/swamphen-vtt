extends RefCounted

# Canonical layout contract. No Nodes, input, files or UI; feet and wall-local XY.
const VERSION := 1
const Wall = preload("res://scripts/scenery/wall_parameters.gd")
const Opening = preload("res://scripts/scenery/opening_parameters.gd")
const Joiner = preload("res://scripts/scenery/wall_joiner.gd")
const MAX_WALLS := 128

static func empty() -> Dictionary:
	return {"version":VERSION,"walls":[]}

static func fail(message: String) -> Dictionary:
	return {"ok":false,"message":message}

static func exact(value: Dictionary, keys: Array) -> bool:
	return value.size()==keys.size() and value.has_all(keys)

static func valid_id(value: Variant) -> bool:
	if not value is String or value.is_empty() or value.length()>96: return false
	for character in value:
		if not character.to_lower() in "abcdefghijklmnopqrstuvwxyz0123456789_-": return false
	return true

static func validate(layout: Dictionary) -> Dictionary:
	if not exact(layout,["version","walls"]) or typeof(layout.version)!=TYPE_INT or layout.version!=VERSION:
		return fail("布局字段或版本不受支持")
	if not layout.walls is Array or layout.walls.size()>MAX_WALLS: return fail("墙体列表无效或超过128段")
	var ids := {}
	var descriptors: Array[Dictionary] = []
	for entry in layout.walls:
		if not entry is Dictionary or not exact(entry,["id","parameters","transform","openings"]): return fail("墙体记录字段不完整或含未知字段")
		if not valid_id(entry.id) or ids.has(entry.id): return fail("墙体/门窗编号无效或重复")
		ids[entry.id]=true
		if not entry.parameters is Dictionary: return fail("墙体参数类型无效")
		var error := Wall.validate(entry.parameters)
		if not error.is_empty(): return fail(error)
		if int(entry.parameters.kind)!=0: return fail("布局须保留实心原墙，洞口由门窗记录定义")
		if not entry.transform is Transform3D or not entry.transform.is_finite(): return fail("墙体变换无效")
		if not entry.openings is Array or entry.openings.size()>16: return fail("门窗列表无效或每段墙超过16个洞口")
		var specs: Array = []
		for item in entry.openings:
			if not item is Dictionary or not exact(item,["id","spec"]) or not item.spec is Dictionary: return fail("门窗记录字段无效")
			if not valid_id(item.id) or ids.has(item.id): return fail("墙体/门窗编号无效或重复")
			ids[item.id]=true
			error=Opening.validate(item.spec)
			if not error.is_empty(): return fail(error)
			if item.spec.angle>Opening.max_open_angle(item.spec): return fail("当前安装面与开向不支持此开合角度")
			specs.append(item.spec)
		descriptors.append({"parameters":entry.parameters,"transform":entry.transform,"openings":specs})
	var context := Joiner.prepare(descriptors)
	if not context.ok: return context
	for i in descriptors.size():
		var half := float(descriptors[i].parameters.thickness)*Wall.FEET*0.5
		var insets: Vector2 = context.cuts[i].abs()*half
		if Wall.is_logs(descriptors[i].parameters.surface):
			for end in 2:
				if context.log_joins[i][end].has("half_depth"): insets[end]=maxf(insets[end],float(context.log_joins[i][end].half_depth))
		if insets.x+insets.y>=float(descriptors[i].parameters.length)*Wall.FEET: return fail("墙体太短，无法容纳两端转角")
		var resolved := Opening.resolve(descriptors[i].parameters,descriptors[i].openings,insets)
		if not resolved.ok: return resolved
	return {"ok":true,"message":"","descriptors":descriptors}

static func find_wall(layout: Dictionary, id: String) -> int:
	for i in layout.walls.size():
		if layout.walls[i].id==id: return i
	return -1

static func find_opening(layout: Dictionary, id: String) -> Vector2i:
	for w in layout.walls.size():
		for o in layout.walls[w].openings.size():
			if layout.walls[w].openings[o].id==id: return Vector2i(w,o)
	return Vector2i(-1,-1)

static func anchor(wall: Dictionary, spec: Dictionary) -> Vector2:
	return Vector2(float(wall.length)*0.5+float(spec.offset),float(spec.sill))

static func at_anchor(wall: Dictionary, spec: Dictionary, point_feet: Vector2) -> Dictionary:
	var copy := spec.duplicate(true)
	copy.offset=point_feet.x-float(wall.length)*0.5
	copy.sill=point_feet.y
	return copy

# Explicit portable JSON. No Variant object decoding, no dropping unknown fields.
static func to_json(layout: Dictionary) -> Dictionary:
	var result := validate(layout)
	if not result.ok: return result
	var copy := layout.duplicate(true)
	for wall in copy.walls:
		var pose: Transform3D = wall.transform
		wall.transform=[pose.basis.x.x,pose.basis.x.y,pose.basis.x.z,pose.basis.y.x,pose.basis.y.y,pose.basis.y.z,
			pose.basis.z.x,pose.basis.z.y,pose.basis.z.z,pose.origin.x,pose.origin.y,pose.origin.z]
		wall.parameters.color=_color_array(wall.parameters.color)
		for item in wall.openings:
			for key in ["wood_color","metal_color","glass_color"]: item.spec[key]=_color_array(item.spec[key])
	return {"ok":true,"message":"","text":JSON.stringify(copy,"\t",true,true)}

static func from_json(text: String) -> Dictionary:
	if text.length()>4*1024*1024: return fail("布局文本过大")
	var parser := JSON.new()
	if parser.parse(text)!=OK or not parser.data is Dictionary: return fail("布局JSON无效")
	var copy: Dictionary = parser.data
	if not exact(copy,["version","walls"]) or not _number(copy.version) or copy.version!=VERSION or not copy.walls is Array: return fail("布局字段或版本不受支持")
	copy.version=int(copy.version)
	for wall in copy.walls:
		if not wall is Dictionary or not exact(wall,["id","parameters","transform","openings"]): return fail("墙体字段无效")
		if not _numbers(wall.transform,12) or not wall.parameters is Dictionary or not _numbers(wall.parameters.get("color"),4) or not wall.openings is Array: return fail("墙体变换或颜色编码无效")
		var t: Array = wall.transform
		wall.transform=Transform3D(Vector3(t[0],t[1],t[2]),Vector3(t[3],t[4],t[5]),Vector3(t[6],t[7],t[8]),Vector3(t[9],t[10],t[11]))
		wall.parameters.color=_decode_color(wall.parameters.color)
		if not _number(wall.parameters.get("kind")) or wall.parameters.kind!=floorf(wall.parameters.kind): return fail("墙体类型编码无效")
		wall.parameters.kind=int(wall.parameters.kind)
		for item in wall.openings:
			if not item is Dictionary or not exact(item,["id","spec"]) or not item.spec is Dictionary: return fail("门窗字段无效")
			if not _number(item.spec.get("seed")) or item.spec.seed!=floorf(item.spec.seed): return fail("木纹种子编码无效")
			item.spec.seed=int(item.spec.seed)
			for key in ["wood_color","metal_color","glass_color"]:
				if not _numbers(item.spec.get(key),4): return fail("门窗颜色编码无效")
				item.spec[key]=_decode_color(item.spec[key])
	var result := validate(copy)
	if not result.ok: return result
	return {"ok":true,"message":"","layout":copy}

static func _color_array(c: Color) -> Array:
	return [c.r,c.g,c.b,c.a]

static func _decode_color(c: Array) -> Color:
	return Color(c[0],c[1],c[2],c[3])

static func _number(value: Variant) -> bool:
	return typeof(value) in [TYPE_FLOAT,TYPE_INT] and is_finite(float(value))

static func _numbers(value: Variant, count: int) -> bool:
	if not value is Array or value.size()!=count: return false
	for item in value:
		if not _number(item): return false
	return true
