extends RefCounted

const Typography = preload("res://ui/theme/typography.gd")

const T = preload("res://ui/theme/tokens/fluent_tokens.gd")
static var _shared: Theme

static func shared() -> Theme:
	if _shared != null: return _shared
	_shared = GoUi.theme().duplicate()
	Typography.apply_theme(_shared)
	_shared.set_color("font_color", "Label", T.FOREGROUND)
	_shared.set_font_size("font_size", "Label", T.BODY_SIZE)
	_shared.set_type_variation("FluentStrong", "Label")
	_shared.set_font("font", "FluentStrong", Typography.BOLD)
	for variant in ["FluentButton", "FluentPrimary", "FluentDanger", "FluentEntry", "FluentPrimaryEntry", "FluentFilter", "FluentCompact"]:
		_shared.set_type_variation(variant, "Button")
		var primary: bool = variant in ["FluentPrimary", "FluentPrimaryEntry"]
		var danger: bool = variant == "FluentDanger"
		var radius: int = T.ENTRY_RADIUS if variant.ends_with("Entry") else T.RADIUS
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			var bg: Color = T.SURFACE
			if state == "hover": bg = T.HOVER
			if state in ["pressed", "hover_pressed"]: bg = T.PRESSED
			if primary:
				bg = T.BRAND_HOVER if state == "hover" else (T.BRAND_PRESSED if state in ["pressed", "hover_pressed"] else T.BRAND)
			if danger:
				bg = T.DANGER_HOVER if state == "hover" else (T.DANGER_PRESSED if state in ["pressed", "hover_pressed"] else T.DANGER)
			if state == "disabled": bg = T.HOVER
			if variant=="FluentFilter" and state in ["pressed","hover_pressed"]: bg = T.BRAND
			_shared.set_stylebox(state, variant, face(bg, bg if primary or danger else T.STROKE, radius))
			var fg: Color = T.DISABLED if state == "disabled" else (Color.WHITE if primary or danger else T.FOREGROUND)
			if variant=="FluentFilter" and state in ["pressed","hover_pressed"]: fg = Color.WHITE
			_shared.set_color("font_color" if state == "normal" else "font_"+state+"_color", variant, fg)
			_shared.set_color("icon_normal_color" if state == "normal" else "icon_"+state+"_color", variant, fg)
		_shared.set_color("font_focus_color", variant, Color.WHITE if primary or danger else T.FOREGROUND)
		_shared.set_font_size("font_size", variant, T.BODY_SIZE)
		_shared.set_constant("h_separation", variant, 12)
		_shared.set_stylebox("focus", variant, face(Color.TRANSPARENT, T.FOREGROUND, radius, 2))
	for state in ["normal","focus","read_only"]:
		_shared.set_stylebox(state,"LineEdit",face(T.SURFACE,T.BRAND if state=="focus" else T.STROKE,T.RADIUS))
	_shared.set_color("font_color","LineEdit",T.FOREGROUND)
	_shared.set_color("caret_color","LineEdit",T.BRAND)
	_shared.set_color("font_placeholder_color","LineEdit",T.SECONDARY)
	_shared.set_font_size("font_size","LineEdit",T.BODY_SIZE)
	for state in ["normal","hover","pressed","hover_pressed","disabled","focus"]:
		_shared.set_stylebox(state,"OptionButton",_shared.get_stylebox(state,"FluentButton"))
	_shared.set_color("font_color","OptionButton",T.FOREGROUND)
	return _shared

static func face(background: Color, border: Color, radius: int, width := 1) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style

static func entry_face(primary: bool) -> StyleBoxFlat:
	var style := face(T.BRAND if primary else T.SURFACE, T.BRAND if primary else T.STROKE, T.ENTRY_RADIUS)
	style.shadow_color = Color(0.1, 0.2, 0.35, 0.06)
	style.shadow_size = 5
	style.shadow_offset = Vector2(0, 2)
	return style
