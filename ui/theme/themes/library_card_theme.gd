# -*- coding: utf-8 -*-
extends RefCounted

const Typography = preload("res://ui/theme/typography.gd")

# Gemini 独立设计的卡片组件集中主题 (Revision 4)
# 遵循 Fluent 2 设计准则与项目 UI 规范
const CardSpec = preload("res://ui/theme/tokens/library_card_spec.gd")
static var _theme: Theme

static func get_theme() -> Theme:
	if _theme != null:
		return _theme

	var base_theme: Theme = _get_base_theme()
	var theme := base_theme.duplicate() if base_theme != null else Theme.new()

	# 配置支持 MSDF 的中文字体，消除小字号模糊
	var lib_font: Font = Typography.REGULAR
	theme.default_font = lib_font
	theme.set_font("font", "Label", lib_font)
	theme.set_font("font", "Button", lib_font)

	# 1. 标签变体 GeminiTag (纯文字次要色，无外框，无背景，无下划线，无焦点框)
	theme.set_type_variation("GeminiTag", "Button")
	theme.set_font_size("font_size", "GeminiTag", Typography.TAG)
	theme.set_constant("h_separation", "GeminiTag", 6)

	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		var empty_box := StyleBoxEmpty.new()
		empty_box.content_margin_left = 0
		empty_box.content_margin_right = 0
		empty_box.content_margin_top = 0
		empty_box.content_margin_bottom = 0
		theme.set_stylebox(state, "GeminiTag", empty_box)

		var fg_color := CardSpec.color("muted")
		if state == "hover": fg_color = CardSpec.color("text")
		elif state == "disabled": fg_color = Color("a0a0a0")
		theme.set_color("font_color" if state == "normal" else "font_" + state + "_color", "GeminiTag", fg_color)
		theme.set_color("icon_normal_color" if state == "normal" else "icon_" + state + "_color", "GeminiTag", fg_color)

	# 2. 常用操作变体 GeminiAction (如“编辑”)
	theme.set_type_variation("GeminiAction", "Button")
	theme.set_font_size("font_size", "GeminiAction", Typography.CAPTION)
	theme.set_constant("h_separation", "GeminiAction", 8)

	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		var box := StyleBoxFlat.new()
		box.set_corner_radius_all(6)
		box.content_margin_left = 10
		box.content_margin_right = 10
		box.content_margin_top = 0
		box.content_margin_bottom = 0

		var bg := Color.TRANSPARENT
		var border := Color("d1d1d1")
		var b_width := 1

		if state == "hover":
			bg = Color("f0f6fc")
			border = Color("c7c7c7")
		elif state in ["pressed", "hover_pressed"]:
			bg = Color("ebebeb")
			border = Color("b0b0b0")
		elif state == "disabled":
			bg = Color("f5f5f5")
			border = CardSpec.color("border")
		elif state == "focus":
			# 高对比 2px 键盘焦点外框
			border = Color("000000")
			b_width = 2

		box.bg_color = bg
		box.border_color = border
		box.set_border_width_all(b_width)
		theme.set_stylebox(state, "GeminiAction", box)

		var fg := CardSpec.color("text")
		if state == "disabled": fg = Color("a0a0a0")
		theme.set_color("font_color" if state == "normal" else "font_" + state + "_color", "GeminiAction", fg)
		theme.set_color("icon_normal_color" if state == "normal" else "icon_" + state + "_color", "GeminiAction", fg)

	# 3. 品牌主操作变体 GeminiPrimary (如“添加到托盘”)
	theme.set_type_variation("GeminiPrimary", "Button")
	theme.set_font_size("font_size", "GeminiPrimary", Typography.CAPTION)
	theme.set_constant("h_separation", "GeminiPrimary", 8)

	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		var box := StyleBoxFlat.new()
		box.set_corner_radius_all(6)
		box.content_margin_left = 12
		box.content_margin_right = 12
		box.content_margin_top = 0
		box.content_margin_bottom = 0

		var bg := CardSpec.color("border_selected")
		var border := Color.TRANSPARENT
		var b_width := 0

		if state == "hover":
			bg = Color("106ebe")
		elif state in ["pressed", "hover_pressed"]:
			bg = Color("004578")
		elif state == "disabled":
			bg = Color("f0f0f0")
			border = CardSpec.color("border")
			b_width = 1
		elif state == "focus":
			border = Color("000000")
			b_width = 2

		box.bg_color = bg
		box.border_color = border
		box.set_border_width_all(b_width)
		theme.set_stylebox(state, "GeminiPrimary", box)

		var fg := Color.WHITE if state != "disabled" else Color("a0a0a0")
		theme.set_color("font_color" if state == "normal" else "font_" + state + "_color", "GeminiPrimary", fg)
		theme.set_color("icon_normal_color" if state == "normal" else "icon_" + state + "_color", "GeminiPrimary", fg)

	# 4. 图标按钮变体 GeminiIcon (如“更多操作”三点按钮)
	# 明确取消鼠标点击后的持续黑色焦点框与底线，防止黑框残留
	theme.set_type_variation("GeminiIcon", "Button")
	theme.set_font_size("font_size", "GeminiIcon", Typography.CAPTION)

	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		var box := StyleBoxFlat.new()
		box.set_corner_radius_all(6)
		box.content_margin_left = 0
		box.content_margin_right = 0
		box.content_margin_top = 0
		box.content_margin_bottom = 0

		var bg := Color.TRANSPARENT
		var border := Color.TRANSPARENT
		var b_width := 0

		if state == "hover":
			bg = Color("f0f6fc")
		elif state in ["pressed", "hover_pressed"]:
			bg = Color("ebebeb")
		elif state == "focus":
			# 取消三点按钮黑框，焦点态与正常态一致，不留暗黑边框
			bg = Color.TRANSPARENT
			border = Color.TRANSPARENT
			b_width = 0

		box.bg_color = bg
		box.border_color = border
		box.set_border_width_all(b_width)
		theme.set_stylebox(state, "GeminiIcon", box)

		var fg := CardSpec.color("text")
		if state == "disabled": fg = Color("a0a0a0")
		theme.set_color("icon_normal_color" if state == "normal" else "icon_" + state + "_color", "GeminiIcon", fg)

	_theme = theme
	return _theme

static func _get_base_theme() -> Theme:
	if ResourceLoader.exists("res://addons/gohud/core/go_ui.gd"):
		var goui_script: Variant = load("res://addons/gohud/core/go_ui.gd")
		if goui_script != null and goui_script.has_method("theme"):
			var t: Theme = goui_script.theme()
			if t != null:
				return t
	return Theme.new()
