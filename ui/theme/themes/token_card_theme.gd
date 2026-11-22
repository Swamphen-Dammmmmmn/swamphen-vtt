extends RefCounted
const FluentTheme = preload("res://ui/theme/themes/fluent_theme.gd")
const T = preload("res://ui/theme/tokens/fluent_tokens.gd")
const Spec = preload("res://ui/theme/tokens/token_card_tokens.gd")
const Typography = preload("res://ui/theme/typography.gd")
static var _shared: Theme

static func shared() -> Theme:
	if _shared != null: return _shared
	_shared = FluentTheme.shared().duplicate()
	for selected in [false, true]:
		var variation := "TokenCardSelected" if selected else "TokenCard"
		_shared.set_type_variation(variation, "PanelContainer")
		var face := FluentTheme.face(T.NOTICE_BACKGROUND if selected else T.SURFACE, T.BRAND if selected else T.STROKE, T.RADIUS, 1)
		face.content_margin_left = Spec.PADDING_H
		face.content_margin_right = Spec.PADDING_H
		face.content_margin_top = Spec.PADDING_V
		face.content_margin_bottom = Spec.PADDING_V
		_shared.set_stylebox("panel", variation, face)
		var name_variation := "TokenCardNameSelected" if selected else "TokenCardName"
		_shared.set_type_variation(name_variation, "Label")
		_shared.set_font("font", name_variation, Typography.MEDIUM)
		_shared.set_font_size("font_size", name_variation, Typography.SUBTITLE)
		_shared.set_color("font_color", name_variation, T.BRAND if selected else T.FOREGROUND)
	for variation in ["TokenStat", "TokenCardExpand"]:
		_shared.set_type_variation(variation, "Button")
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
			var face := FluentTheme.shared().get_stylebox(state, "FluentCompact").duplicate() as StyleBoxFlat
			face.content_margin_left = Spec.GAP
			face.content_margin_right = Spec.GAP
			face.content_margin_top = 3
			face.content_margin_bottom = 3
			_shared.set_stylebox(state, variation, face)
			var ink := T.DISABLED if state == "disabled" else T.FOREGROUND
			_shared.set_color("font_color" if state == "normal" else "font_" + state + "_color", variation, ink)
			_shared.set_color("icon_" + state + "_color", variation, Color.WHITE if variation == "TokenStat" else ink)
		_shared.set_font_size("font_size", variation, Typography.CAPTION)
		_shared.set_constant("h_separation", variation, 4)
		_shared.set_constant("icon_max_width", variation, Spec.ICON_SIZE)
	_shared.set_type_variation("TokenCardNotes", "TextEdit")
	for state in ["normal", "focus", "read_only"]:
		_shared.set_stylebox(state, "TokenCardNotes", FluentTheme.face(T.SURFACE, T.BRAND if state == "focus" else T.STROKE, T.RADIUS, 1))
	_shared.set_color("font_color", "TokenCardNotes", T.FOREGROUND)
	_shared.set_color("font_readonly_color", "TokenCardNotes", T.SECONDARY)
	_shared.set_font_size("font_size", "TokenCardNotes", Typography.BODY)
	return _shared
