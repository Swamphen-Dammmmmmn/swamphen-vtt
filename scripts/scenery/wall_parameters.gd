extends RefCounted

const VERSION := 8
const FEET := 0.2
const TITLES := ["实心墙", "门洞墙", "窗洞墙"]
const SURFACES := ["gray", "planks_horizontal", "planks_vertical", "logs_round", "logs_bark", "logs_squared"]
const SURFACE_TITLES := ["灰模", "横铺木板", "竖铺木板", "圆原木", "带皮原木", "削平方木"]
# Dimensions in feet; a 5-foot board square is one world unit.
const NUMBERS := [
	["length", "墙长", 5.0, 50.0],
	["height", "墙高", 5.0, 30.0],
	["thickness", "墙厚", 0.25, 3.0],
	["opening_width", "洞口宽", 1.0, 30.0],
	["opening_height", "洞口高", 1.0, 25.0],
	["opening_offset", "洞口水平偏移", -24.0, 24.0],
	["sill", "窗台离地", 0.5, 20.0]
]
const MIN_EDGE := 0.25

static func defaults(kind := 0, surface := "gray") -> Dictionary:
	return {"kind": kind, "surface": surface, "length": 5.0, "height": 10.0, "thickness": 1.0 if is_logs(surface) else (0.25 if is_planks(surface) else 0.5),
		"opening_width": 3.0, "opening_height": 7.0 if kind == 1 else 4.0,
		"opening_offset": 0.0, "sill": 3.0, "color": Color("6d6557") if surface=="logs_bark" else (Color("8b7a65") if is_logs(surface) else (Color("986039") if is_planks(surface) else Color("b6b8bc")))}

static func is_logs(surface: String) -> bool:
	return surface in ["logs_round","logs_bark","logs_squared"]

static func is_planks(surface: String) -> bool:
	return surface in ["planks_horizontal", "planks_vertical"]

static func validate(values: Dictionary) -> String:
	var expected := defaults()
	for key in values:
		if not expected.has(key): return "未知墙体参数：" + str(key)
	if not values.has_all(expected.keys()): return "墙体参数不完整"
	if values.surface not in SURFACES: return "墙体材质尚未支持"
	if typeof(values.kind) not in [TYPE_INT, TYPE_FLOAT]: return "墙体类型无效"
	if not is_finite(float(values.kind)) or float(values.kind) != floorf(float(values.kind)) or int(values.kind) not in [0, 1, 2]:
		return "墙体类型无效"
	for entry in NUMBERS:
		var key: String = entry[0]
		if typeof(values[key]) not in [TYPE_FLOAT, TYPE_INT]: return entry[1] + "必须是数值"
		var number := float(values[key])
		if not is_finite(number) or number < entry[2] or number > entry[3]:
			return "%s须在 %s–%s 英尺之间" % [entry[1], entry[2], entry[3]]
	if not values.color is Color: return "墙体颜色无效"
	var color: Color = values.color
	for channel in [color.r, color.g, color.b, color.a]:
		if not is_finite(channel) or channel < 0 or channel > 1: return "墙体颜色须在有效范围内"
	if not is_equal_approx(color.a, 1.0): return "墙体颜色不支持透明度"
	if int(values.kind) != 0:
		if values.opening_width + 2.0 * absf(values.opening_offset) > values.length - 2.0 * MIN_EDGE:
			return "洞口左右须各保留至少0.25英尺墙体"
		var bottom := float(values.sill) if int(values.kind) == 2 else 0.0
		if bottom + values.opening_height > values.height - MIN_EDGE:
			return "洞口上方须保留至少0.25英尺过梁"
	return ""
