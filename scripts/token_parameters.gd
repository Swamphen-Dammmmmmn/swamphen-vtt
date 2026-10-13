extends RefCounted

const Appearance = preload("res://scripts/token_appearance.gd")

static func validate(raw: Dictionary) -> Dictionary:
	var title := str(raw.get("title", "")).strip_edges()
	if title.is_empty() or title.length() > 40:
		return _error("title", "名称不能为空，且不能超过 40 个字符。")
	var count := int(raw.get("size", 1))
	var base := str(raw.get("base", "circle"))
	if count < 1 or count > 5 or base not in Appearance.BASES:
		return _error("size", "请选择有效的占地与底座。")
	var values: Dictionary = {}
	for key in ["hp", "max_hp", "ac"]:
		var text := str(raw.get(key, "")).strip_edges()
		if not text.is_empty() and (text.length() > 6 or not text.is_valid_int() or text.to_int() < 0):
			return _error(key, "HP 和 AC 请填写不超过六位的非负整数，或留空。")
		values[key] = -1 if text.is_empty() else text.to_int()
	var hp := int(values["hp"])
	var maximum := int(values["max_hp"])
	if hp >= 0 and maximum < 0: maximum = hp
	if maximum >= 0 and hp < 0: hp = maximum
	if maximum == 0 or hp > maximum:
		return _error("max_hp", "最大 HP 必须大于 0，当前 HP 不能超过最大 HP。")
	var color: Color = raw.get("color", Color("2e7ae0"))
	color.a = 1.0
	return {"ok": true, "parameters": {"title": title, "size": count, "base": base, "color": color, "hp": hp, "max_hp": maximum, "ac": int(values["ac"])}}

static func _error(field: String, message: String) -> Dictionary:
	return {"ok": false, "field": field, "message": message}
