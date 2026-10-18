extends RefCounted

const Typography = preload("res://ui/theme/typography.gd")
const Base = preload("res://ui/theme/themes/fluent_theme.gd")
const T = preload("res://ui/theme/tokens/fluent_tokens.gd")
static var _shared: Theme
static func shared() -> Theme:
	if _shared!=null: return _shared
	_shared = Base.shared().duplicate()
	for variant in ["LibraryAction","LibraryTag","LibraryTab","LibraryFilter","LibraryPrimary","LibraryIcon"]:
		_shared.set_type_variation(variant,"Button")
		_shared.set_font_size("font_size",variant,Typography.TAG if variant=="LibraryTag" else Typography.CAPTION)
		_shared.set_constant("h_separation",variant,8)
		for state in ["normal","hover","pressed","hover_pressed","disabled","focus"]:
			var color := Color.TRANSPARENT
			var border := Color.TRANSPARENT
			if state=="hover": color = Color("f5f5f5")
			if state in ["pressed","hover_pressed"]: color = Color("ebebeb")
			if variant in ["LibraryFilter","LibraryPrimary"]: border = Color("e0e0e0")
			if variant=="LibraryFilter" and state in ["pressed","hover_pressed"]:
				color = Color("e7f1fa")
				border = T.BRAND
			if state=="focus": border = T.FOREGROUND
			var face := Base.face(color,border,6,2 if state=="focus" else 1)
			face.content_margin_top = 0
			face.content_margin_bottom = 0
			face.content_margin_left = 8
			face.content_margin_right = 8
			if variant=="LibraryTag":
				face.bg_color = Color.TRANSPARENT
				face.set_border_width_all(0)
				face.content_margin_left = 0
				face.content_margin_right = 0
			if variant=="LibraryIcon" and state=="focus":
				face.bg_color = Color.TRANSPARENT
				face.set_border_width_all(0)
			_shared.set_stylebox(state,variant,face)
			var fg := T.DISABLED if state=="disabled" else (Color.WHITE if variant=="LibraryPrimary" else (T.SECONDARY if variant=="LibraryTag" else T.FOREGROUND))
			_shared.set_color("font_color" if state=="normal" else "font_"+state+"_color",variant,fg)
			_shared.set_color("icon_normal_color" if state=="normal" else "icon_"+state+"_color",variant,fg)
	return _shared
