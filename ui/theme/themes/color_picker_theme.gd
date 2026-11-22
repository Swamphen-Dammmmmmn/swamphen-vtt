extends RefCounted
# Fluent theme for the native ColorPicker inside overlays/color_picker_popup.gd.
# Only theme items the picker's own controls read are defined; behaviour stays native.

const Typography = preload("res://ui/theme/typography.gd")
const Fluent = preload("res://ui/theme/themes/fluent_theme.gd")
const CommandMenuTheme = preload("res://ui/theme/themes/command_menu_theme.gd")
const T = preload("res://ui/theme/tokens/fluent_tokens.gd")
const ICONS := "res://ui/theme/icons/color_picker/"
const DOMAIN := &"color_picker"
# Engine texts of the picker (Godot 4.7.2), translated through the picker's own domain.
const TEXTS := {
	"Pick a color from the application window.": "从程序窗口取色",
	"Select a picker shape.": "选择色域形状",
	"HSV Rectangle": "HSV 矩形",
	"HSV Wheel": "HSV 色轮",
	"VHS Circle": "VHS 圆形",
	"OKHSL Circle": "OKHSL 圆形",
	"OK HS Rectangle": "OK HS 矩形",
	"OK HL Rectangle": "OK HL 矩形",
	"Select a picker mode.": "选择颜色模式",
	"Linear": "线性",
	"Colorized Sliders": "彩色滑条",
	"Hex": "色值",
	"Enter a hex code (\"#ff0000\") or named color (\"red\").": "输入十六进制色值（如 #ff0000）或颜色名称（如 red）",
	"Hex code or named color": "色值或颜色名称",
	"Copy the color value.": "复制色值",
	"Swatches": "色板",
	"Show all options available.": "色板选项",
	"Add current color as a preset.": "将当前颜色加入色板",
	"Recent Colors": "最近颜色",
	"Search": "搜索",
	"Screen Recording permission is required to pick colors from the other application windows.\nClick here to request access...": "从其他程序窗口取色需要屏幕录制权限。\n点击此处申请权限……",
}
static var _themes: Dictionary = {}
static var _domain_ready := false

static func shared(mobile: bool) -> Theme:
	if _themes.has(mobile): return _themes[mobile]
	var theme := Fluent.shared().duplicate() as Theme
	# Native shape / mode / swatch menus are PopupMenus; reuse the project's command menu faces.
	theme.merge_with(CommandMenuTheme.shared(true, true, mobile))
	theme.set_constant("margin", "ColorPicker", 0)
	theme.set_constant("h_width", "ColorPicker", T.COLOR_HUE_WIDTH)
	theme.set_constant("label_width", "ColorPicker", T.COLOR_LABEL_WIDTH)
	theme.set_constant("center_slider_grabbers", "ColorPicker", 1)
	for entry in [["screen_picker", "eyedropper"], ["color_copy", "copy"], ["menu_option", "more"], ["add_preset", "plus"], ["shape_rect", "shape_rect"], ["shape_rect_wheel", "shape_rect_wheel"], ["shape_circle", "shape_circle"]]:
		theme.set_icon(entry[0], "ColorPicker", load(ICONS + entry[1] + ".svg"))
	theme.set_icon("expanded_arrow", "ColorPicker", preload("res://ui/theme/icons/property_group_down.svg"))
	theme.set_icon("folded_arrow", "ColorPicker", preload("res://ui/theme/icons/property_group_right.svg"))
	theme.set_color("font_color", "Label", T.SECONDARY)
	theme.set_font_size("font_size", "Label", T.CAPTION_SIZE)
	for type in ["Button", "FlatButton", "MenuButton", "FlatMenuButton"]:
		if type.begins_with("Flat"): theme.set_type_variation(type, type.trim_prefix("Flat"))
		var flat: bool = type.begins_with("Flat")
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			var background: Color = T.SURFACE
			if state == "hover": background = T.HOVER
			if state in ["pressed", "hover_pressed"]: background = T.PRESSED
			if flat and state in ["normal", "disabled"]: background = Color.TRANSPARENT
			var border: Color = Color.TRANSPARENT if flat else T.STROKE
			# Mode buttons are native toggles: pressed reads as the selected choice.
			if not flat and state in ["pressed", "hover_pressed"]:
				background = T.NOTICE_BACKGROUND
				border = T.BRAND
			theme.set_stylebox(state, type, _face(background, border))
			var foreground: Color = T.DISABLED if state == "disabled" else (T.BRAND if not flat and state in ["pressed", "hover_pressed"] else T.FOREGROUND)
			theme.set_color("font_color" if state == "normal" else "font_" + state + "_color", type, foreground)
		theme.set_color("font_focus_color", type, T.FOREGROUND)
		theme.set_stylebox("focus", type, _face(Color.TRANSPARENT, T.BRAND))
		theme.set_font("font", type, Typography.REGULAR)
		theme.set_font_size("font_size", type, T.CAPTION_SIZE)
		theme.set_constant("h_separation", type, 4)
	for state in ["normal", "focus", "read_only"]:
		theme.set_stylebox(state, "LineEdit", _face(T.SURFACE, T.BRAND if state == "focus" else T.STROKE))
	theme.set_font_size("font_size", "LineEdit", T.CAPTION_SIZE)
	theme.set_color("font_color", "LineEdit", T.FOREGROUND)
	theme.set_color("font_selected_color", "LineEdit", T.FOREGROUND)
	theme.set_color("selection_color", "LineEdit", T.NOTICE_STROKE)
	theme.set_color("caret_color", "LineEdit", T.BRAND)
	# The picker's RGB / HSV / Linear mode buttons read TabContainer tab faces.
	for entry in [["tab_unselected", T.SURFACE, T.STROKE], ["tab_hovered", T.HOVER, T.STROKE], ["tab_selected", T.NOTICE_BACKGROUND, T.BRAND], ["tab_disabled", T.HOVER, T.STROKE]]:
		theme.set_stylebox(entry[0], "TabContainer", _face(entry[1], entry[2]))
	theme.set_icon("grabber", "HSlider", load(ICONS + "grabber.svg"))
	theme.set_icon("grabber_highlight", "HSlider", load(ICONS + "grabber.svg"))
	theme.set_icon("up", "SpinBox", load(ICONS + "spin_up.svg"))
	theme.set_icon("down", "SpinBox", load(ICONS + "spin_down.svg"))
	for state in ["up_background", "up_background_hovered", "up_background_pressed", "up_background_disabled", "down_background", "down_background_hovered", "down_background_pressed", "down_background_disabled"]:
		var background: Color = T.HOVER if state.ends_with("hovered") else (T.PRESSED if state.ends_with("pressed") else Color.TRANSPARENT)
		var face := StyleBoxFlat.new()
		face.bg_color = background
		face.set_corner_radius_all(T.COLOR_CONTROL_RADIUS - 2)
		theme.set_stylebox(state, "SpinBox", face)
	theme.set_stylebox("field_and_buttons_separator", "SpinBox", StyleBoxEmpty.new())
	theme.set_stylebox("up_down_buttons_separator", "SpinBox", StyleBoxEmpty.new())
	theme.set_constant("buttons_width", "SpinBox", 18)
	theme.set_constant("set_min_buttons_width_from_icons", "SpinBox", 0)
	var track := StyleBoxFlat.new()
	track.bg_color = T.STROKE
	track.set_corner_radius_all(2)
	track.content_margin_top = 2
	track.content_margin_bottom = 2
	theme.set_stylebox("slider", "HSlider", track)
	for state in ["grabber_area", "grabber_area_highlight"]:
		var filled := track.duplicate() as StyleBoxFlat
		filled.bg_color = T.BRAND
		theme.set_stylebox(state, "HSlider", filled)
	theme.set_constant("separation", "HBoxContainer", T.COLOR_ROW_GAP)
	theme.set_constant("separation", "VBoxContainer", T.COLOR_ROW_GAP)
	theme.set_constant("h_separation", "GridContainer", T.COLOR_ROW_GAP)
	theme.set_constant("v_separation", "GridContainer", T.COLOR_ROW_GAP)
	_themes[mobile] = theme
	return theme

# Chinese texts for the picker's engine strings, scoped to its translation domain only.
static func translation_domain() -> StringName:
	if _domain_ready: return DOMAIN
	_domain_ready = true
	var translation := Translation.new()
	translation.locale = "zh_CN"
	for source in TEXTS: translation.add_message(source, TEXTS[source])
	var domain := TranslationServer.get_or_add_domain(DOMAIN)
	domain.add_translation(translation)
	domain.set_locale_override("zh_CN")
	return DOMAIN

static func _face(background: Color, border: Color) -> StyleBoxFlat:
	var style := Fluent.face(background, border, T.COLOR_CONTROL_RADIUS)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	return style
