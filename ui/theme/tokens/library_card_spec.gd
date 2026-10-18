extends RefCounted
const Typography = preload("res://ui/theme/typography.gd")

# Godot 与 Python 直接读取同一规格；读取/解析失败明确报错，不使用手工常量兜底。
const PATH := "res://ui/theme/tokens/library_card_spec.json"
static var _data: Dictionary = {}

static func data() -> Dictionary:
	if _data.is_empty():
		var source := FileAccess.open(PATH, FileAccess.READ)
		assert(source != null, "无法读取卡片统一规格：" + PATH)
		if source == null:
			push_error("无法读取卡片统一规格：" + PATH)
			return {}
		var parser := JSON.new()
		var error := parser.parse(source.get_as_text())
		assert(error == OK and parser.data is Dictionary, "卡片统一规格解析失败")
		if error != OK or not parser.data is Dictionary:
			push_error("卡片统一规格解析失败：" + parser.get_error_message())
			return {}
		_data = parser.data
		_data.title.font_size = Typography.BODY
		_data.tags.font_size = Typography.TAG
	return _data

static func color(key: String) -> Color:
	return Color(str(data()["colors"][key]))
