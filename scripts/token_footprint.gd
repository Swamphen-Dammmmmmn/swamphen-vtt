extends RefCounted

const MAX_EXTENT := 15

static func _valid_count(value: Variant) -> bool:
	if not (value is int or value is float):
		return false
	var number := float(value)
	return is_finite(number) and number == floor(number) and number >= 1 and number <= MAX_EXTENT

static func valid(data: Dictionary) -> bool:
	if data.has("width") or data.has("length"):
		return data.has("width") and data.has("length") and _valid_count(data["width"]) and _valid_count(data["length"])
	return _valid_count(data.get("size", 1))

static func dimensions(data: Dictionary) -> Vector2i:
	assert(valid(data), "棋子占地必须是 1～15 整数格，宽和长必须同时提供。")
	if data.has("width"):
		return Vector2i(int(data["width"]), int(data["length"]))
	return Vector2i.ONE * int(data.get("size", 1))

static func space(data: Dictionary) -> Rect2i:
	return Rect2i(data["cell"], dimensions(data))

static func fits(cell: Vector2i, extent: Vector2i, board_size: int) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x + extent.x <= board_size and cell.y + extent.y <= board_size

static func clamp_origin(cell: Vector2i, extent: Vector2i, board_size: int) -> Vector2i:
	return Vector2i(clampi(cell.x, 0, board_size - extent.x), clampi(cell.y, 0, board_size - extent.y))

static func center(cell: Vector2i, extent: Vector2i, board_size: int) -> Vector3:
	return Vector3(cell.x + extent.x / 2.0 - board_size / 2.0, 0, cell.y + extent.y / 2.0 - board_size / 2.0)
