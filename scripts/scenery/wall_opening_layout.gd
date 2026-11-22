extends RefCounted

const Wall = preload("res://scripts/scenery/wall_parameters.gd")
const EPS := 0.000001

# Wall-local XY rectangles, in world units. Empty explicit layout means no holes.
static func from_legacy(values: Dictionary) -> Array:
	if int(values.kind)==0: return []
	var width := float(values.opening_width)*Wall.FEET
	return [Rect2(Vector2((float(values.length)*Wall.FEET-width)*0.5+float(values.opening_offset)*Wall.FEET,
		float(values.sill)*Wall.FEET if int(values.kind)==2 else 0.0),Vector2(width,float(values.opening_height)*Wall.FEET))]

static func validate(wall: Dictionary, holes: Array, end_insets := Vector2.ZERO) -> String:
	if holes.size()>16: return "每段墙最多支持16个洞口"
	var edge := Wall.MIN_EDGE*Wall.FEET
	var length := float(wall.length)*Wall.FEET
	var height := float(wall.height)*Wall.FEET
	for i in holes.size():
		if not holes[i] is Rect2: return "洞口必须是矩形定义"
		var hole: Rect2 = holes[i]
		if not hole.position.is_finite() or not hole.size.is_finite() or hole.size.x<Wall.FEET-EPS or hole.size.y<Wall.FEET-EPS:
			return "洞口尺寸须为至少1尺的有限数值"
		if hole.position.x < end_insets.x+edge-EPS or hole.end.x>length-end_insets.y-edge+EPS:
			return "洞口左右及转角须各保留至少0.25尺墙体"
		if hole.position.y < -EPS or (hole.position.y>EPS and hole.position.y<edge-EPS) or hole.end.y>height-edge+EPS:
			return "洞口超出墙高或未保留足够过梁/窗下墙"
		for j in i:
			# A structural pier must remain between adjacent openings, also vertically.
			if hole.grow(edge*0.5-EPS).intersects((holes[j] as Rect2).grow(edge*0.5-EPS)):
				return "洞口相交或间距不足0.25尺"
	return ""
