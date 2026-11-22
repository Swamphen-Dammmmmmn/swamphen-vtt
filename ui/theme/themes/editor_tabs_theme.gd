extends RefCounted

const FluentTheme = preload("res://ui/theme/themes/fluent_theme.gd")
const T = preload("res://ui/theme/tokens/fluent_tokens.gd")
static var _themes: Dictionary = {}

static func for_segment(selected: bool, first: bool, last: bool, next_selected: bool, compact := false) -> Theme:
	var key := str([selected, first, last, next_selected, compact])
	if _themes.has(key): return _themes[key]
	var result := FluentTheme.shared().duplicate() as Theme
	result.set_type_variation("EditorSegment", "Button")
	var source := ("FluentToolbarSelected" if selected else "FluentToolbar") if compact else ("FluentChoiceSelected" if selected else "FluentChoice")
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		var face := FluentTheme.shared().get_stylebox(state, source).duplicate() as StyleBoxFlat
		face.set_corner_radius_all(0)
		if first:
			face.corner_radius_top_left = T.RADIUS
			face.corner_radius_bottom_left = T.RADIUS
		if last:
			face.corner_radius_top_right = T.RADIUS
			face.corner_radius_bottom_right = T.RADIUS
		if state != "focus":
			# The selected segment owns both shared edges, without doubled strokes.
			face.border_width_left = 1 if first or selected else 0
			face.border_width_right = 0 if next_selected else 1
		result.set_stylebox(state, "EditorSegment", face)
	for color in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_disabled_color", "font_focus_color"]:
		result.set_color(color, "EditorSegment", FluentTheme.shared().get_color(color, source))
	result.set_font_size("font_size", "EditorSegment", T.CAPTION_SIZE if compact else T.BODY_SIZE)
	_themes[key] = result
	return result
