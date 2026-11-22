extends RefCounted

const Wall = preload("res://scripts/scenery/wall_parameters.gd")
const Layout = preload("res://scripts/scenery/wall_opening_layout.gd")
const VERSION := 4
const PRESETS := ["empty_door","empty_window","wood_door","wood_window"]
const FRAME := 0.18 * Wall.FEET
const OVERHANG := 0.32 * Wall.FEET
const TRIM_DEPTH := 0.10 * Wall.FEET
const GAP := 0.01 * Wall.FEET # ~3 mm, measured between sash and clear frame opening
const STOP_LIP := 0.04 * Wall.FEET
const STOP_DEPTH := 0.06 * Wall.FEET
const STOP_CLEARANCE := 0.004 * Wall.FEET
const HINGE_OFFSET := 0.022 * Wall.FEET
const DOOR_DEPTH := 0.16 * Wall.FEET
const WINDOW_DEPTH := 0.12 * Wall.FEET
const SASH_RAIL := 0.15 * Wall.FEET # window stile/rail face width; window hardware must sit inside it
const DOOR_RAIL := 0.22 * Wall.FEET
const DOOR_RAIL_DEPTH := 0.07 * Wall.FEET
const SILL_OVERHANG := 0.45 * Wall.FEET
const BOOLS := ["frame","trim","leaf","glass","mullions","sill_board","hardware","threshold"]

static func defaults(preset := "wood_door") -> Dictionary:
	var window := preset.ends_with("window")
	var dressed := preset.begins_with("wood_")
	return {"preset":preset,"width":3.0,"height":4.0 if window else 7.0,"sill":3.0 if window else 0.0,
		"offset":0.0,"mounting":"front","hinge":"left","swing":"front","angle":0.0,"seed":0,
		"frame":dressed,"trim":dressed,"leaf":dressed,"glass":dressed and window,
		"mullions":dressed and window,"sill_board":dressed and window,"hardware":dressed,"threshold":false,
		"wood_color":Color("8b7a65"),"metal_color":Color("45494a"),"glass_color":Color(0.65,0.81,0.86,0.26)}

static func validate(spec: Dictionary) -> String:
	var expected := defaults()
	if not spec.has_all(expected.keys()): return "门窗参数不完整"
	for key in spec:
		if not expected.has(key): return "未知门窗参数："+str(key)
	if spec.preset not in PRESETS: return "门窗型号尚未支持"
	for key in ["width","height","sill","offset","angle"]:
		if typeof(spec[key]) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(spec[key])): return "门窗尺寸或角度无效"
	if spec.width<1.0 or spec.width>30.0 or spec.height<1.0 or spec.height>25.0 or spec.sill<0 or spec.sill>20 or absf(spec.offset)>24:
		return "门窗尺寸超出支持范围"
	if spec.angle<0 or spec.angle>110: return "开合角度须在0—110度之间"
	if spec.mounting not in ["front","center","back"] or spec.hinge not in ["left","right"] or spec.swing not in ["front","back"]:
		return "门窗安装方向无效"
	if typeof(spec.seed)!=TYPE_INT or spec.seed<0 or spec.seed>65535: return "木纹种子须为0—65535的整数"
	for key in BOOLS:
		if typeof(spec[key])!=TYPE_BOOL: return "门窗部件开关须为布尔值"
	var window: bool = spec.preset.ends_with("window")
	if not window and spec.sill>0 and spec.sill<Wall.MIN_EDGE: return "抬高门洞时下方须保留至少0.25尺墙体"
	if window and spec.sill<0.25: return "窗下须保留至少0.25尺墙体"
	if not window and (spec.glass or spec.mullions or spec.sill_board): return "木门型号不含玻璃、分格条或窗台"
	if window and spec.threshold: return "窗不支持门槛"
	if spec.trim and not spec.frame: return "收边需要内框"
	if (spec.glass or spec.mullions or spec.hardware) and not spec.leaf: return "玻璃、分格条和五金需要门窗扇"
	if not spec.leaf and not is_zero_approx(spec.angle): return "无门窗扇时不能设置开合角度"
	if spec.preset.begins_with("empty_"):
		for key in BOOLS:
			if spec[key]: return "纯洞口型号不生成附加部件"
	for key in ["wood_color","metal_color","glass_color"]:
		if not spec[key] is Color: return "门窗颜色类型无效"
		var color: Color = spec[key]
		for channel in [color.r,color.g,color.b,color.a]:
			if not is_finite(channel) or channel<0 or channel>1: return "门窗颜色通道无效"
		if key!="glass_color" and not is_equal_approx(color.a,1): return "木材及金属须为不透明颜色"
	return ""

# Produces both the Boolean geometry and attachment envelopes from the SAME spec.
static func resolve(wall: Dictionary, specs: Array, end_insets := Vector2.ZERO) -> Dictionary:
	var error := Wall.validate(wall)
	if not error.is_empty(): return {"ok":false,"message":error}
	if int(wall.kind)!=0: return {"ok":false,"message":"统一门窗组装使用实心原墙，洞口仅由门窗列表定义"}
	var holes: Array = []
	var envelopes: Array[Rect2] = []
	for value in specs:
		if not value is Dictionary: return {"ok":false,"message":"门窗定义须为字典"}
		error = validate(value)
		if not error.is_empty(): return {"ok":false,"message":error}
		var hole := Rect2(Vector2((float(wall.length)-float(value.width))*0.5+float(value.offset),float(value.sill))*Wall.FEET,
			Vector2(value.width,value.height)*Wall.FEET)
		holes.append(hole)
		var x_margin := SILL_OVERHANG if value.sill_board else (OVERHANG if value.trim else 0.0)
		var top_margin := OVERHANG if value.trim else 0.0
		var bottom_margin := maxf(0.12*Wall.FEET,OVERHANG if value.trim else 0.0) if value.preset.ends_with("window") else 0.0
		if value.preset.begins_with("empty_"): bottom_margin=0.0
		var envelope := Rect2(hole.position-Vector2(x_margin,bottom_margin),hole.size+Vector2(x_margin*2,top_margin+bottom_margin))
		if envelope.position.x<end_insets.x-Layout.EPS or envelope.end.x>wall.length*Wall.FEET-end_insets.y+Layout.EPS or envelope.position.y<-Layout.EPS or envelope.end.y>wall.height*Wall.FEET+Layout.EPS:
			return {"ok":false,"message":"门窗收边或窗台超出墙体/转角，请移动洞口或加长墙体"}
		for previous in envelopes:
			if envelope.intersects(previous): return {"ok":false,"message":"门窗收边或窗台相互重叠"}
		envelopes.append(envelope)
	error = Layout.validate(wall,holes,end_insets)
	if not error.is_empty(): return {"ok":false,"message":error}
	return {"ok":true,"message":"","rects":holes,"specs":specs.duplicate(true),"envelopes":envelopes}

static func frame_opening(hole: Rect2, spec: Dictionary) -> Rect2:
	var frame := FRAME if spec.frame else 0.0
	var bottom_frame := frame if spec.preset.ends_with("window") else (0.10*Wall.FEET if spec.threshold else 0.0)
	return Rect2(hole.position+Vector2(frame,bottom_frame),hole.size-Vector2(frame*2,frame+bottom_frame))

static func leaf_rect(hole: Rect2, spec: Dictionary) -> Rect2:
	var clear := frame_opening(hole,spec)
	var gap := side_gap(hole,spec)
	return Rect2(clear.position+Vector2(gap,GAP),clear.size-Vector2(gap*2,GAP*2))

# Very narrow leaves need extra sweep clearance for their finite thickness.
# Solve the far-corner radius against the lock jamb; ordinary 3ft products use GAP.
static func side_gap(hole: Rect2, spec: Dictionary) -> float:
	var width := frame_opening(hole,spec).size.x
	var depth := (WINDOW_DEPTH if spec.preset.ends_with("window") else DOOR_DEPTH)+HINGE_OFFSET+STOP_CLEARANCE
	if spec.preset.ends_with("door") and spec.swing=="back": depth+=DOOR_RAIL_DEPTH
	return maxf(GAP,(width-sqrt(maxf(0.0,width*width-3.0*depth*depth)))/3.0)

static func stop_lip(hole: Rect2, spec: Dictionary) -> float:
	return maxf(STOP_LIP,side_gap(hole,spec)+GAP)

static func max_open_angle(spec: Dictionary) -> float:
	# A pivot recessed into a reveal cannot swing past a right angle without
	# striking its hinge jamb. Surface-mounted leaves can use the full 110° range.
	return 110.0 if spec.mounting==spec.swing else 90.0

static func mounting_z(thickness: float, spec: Dictionary) -> float:
	var depth := WINDOW_DEPTH if spec.preset.ends_with("window") else DOOR_DEPTH
	var face := maxf(0.0,(thickness-depth)*0.5)
	return face if spec.mounting=="front" else (-face if spec.mounting=="back" else 0.0)
