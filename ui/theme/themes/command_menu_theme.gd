extends RefCounted

const Typography = preload("res://ui/theme/typography.gd")
const Fluent = preload("res://ui/theme/themes/fluent_theme.gd")
const T = preload("res://ui/theme/tokens/fluent_tokens.gd")
static var _themes: Dictionary = {}
static func shared(fluent: bool, compact: bool, mobile: bool) -> Theme:
	var key := str([fluent,compact,mobile])
	if _themes.has(key): return _themes[key]
	var source := Fluent.shared() if fluent else GoUi.theme()
	# Isolate the native popup from unrelated Window/Panel styles in the application theme.
	var result := Theme.new()
	result.default_font = source.get_font("font","Label")
	result.set_font("font","PopupMenu",result.default_font)
	result.set_stylebox("embedded_border","Window",StyleBoxEmpty.new())
	result.set_stylebox("embedded_unfocused_border","Window",StyleBoxEmpty.new())
	var font_size := Typography.CAPTION if compact else Typography.BODY
	result.set_font_size("font_size","PopupMenu",font_size)
	result.set_color("font_color","PopupMenu",T.FOREGROUND)
	result.set_color("font_hover_color","PopupMenu",T.FOREGROUND)
	result.set_color("font_disabled_color","PopupMenu",T.DISABLED)
	var face := Fluent.face(Color.WHITE,Color.TRANSPARENT,8,0)
	face.shadow_size = 0
	face.content_margin_left = 12
	face.content_margin_right = 12
	face.content_margin_top = 4
	face.content_margin_bottom = 4
	result.set_stylebox("panel","PopupMenu",face)
	var hover := Fluent.face(T.HOVER,Color.TRANSPARENT,4,0)
	hover.set_content_margin_all(0)
	result.set_stylebox("hover","PopupMenu",hover)
	var font := result.get_font("font","PopupMenu")
	if font==null: font = result.default_font
	var text_height := ceili(font.get_height(font_size)) if font!=null else ceili(font_size*1.4)
	result.set_constant("v_separation","PopupMenu",maxi(0,(48 if mobile else 34)-text_height))
	result.set_constant("h_separation","PopupMenu",8)
	result.set_constant("item_start_padding","PopupMenu",0)
	result.set_constant("item_end_padding","PopupMenu",0)
	result.set_constant("icon_max_width","PopupMenu",14)
	_themes[key] = result
	return result
