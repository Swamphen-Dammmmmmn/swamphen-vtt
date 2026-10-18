# -*- coding: utf-8 -*-
extends RefCounted

const Typography = preload("res://ui/theme/typography.gd")

# 竖向命令菜单集中主题
# 为 VerticalCommandMenu 中的 Button 提供统一样式

static var _cached_theme: Theme = null

static func get_theme() -> Theme:
	if _cached_theme != null:
		return _cached_theme

	var theme := Theme.new()
	const CardSpec := preload("res://ui/theme/tokens/library_card_spec.gd")

	# 字体
	var lib_font: Font = Typography.REGULAR
	theme.default_font = lib_font
	theme.set_font("font", "Button", lib_font)
	theme.set_font_size("font_size", "Button", Typography.CAPTION)

	# 按钮颜色
	theme.set_color("font_color", "Button", Color("242424"))
	theme.set_color("font_hover_color", "Button", Color("242424"))
	theme.set_color("font_pressed_color", "Button", Color("242424"))
	theme.set_color("font_focus_color", "Button", Color("242424"))
	theme.set_color("font_disabled_color", "Button", Color("a0a0a0"))

	# 图标颜色（危险项单独覆盖）
	theme.set_color("icon_normal_color", "Button", Color("242424"))
	theme.set_color("icon_hover_color", "Button", Color("242424"))
	theme.set_color("icon_pressed_color", "Button", Color("242424"))
	theme.set_color("icon_disabled_color", "Button", Color("a0a0a0"))

	# 普通状态：透明背景
	var normal_box := StyleBoxFlat.new()
	normal_box.bg_color = Color.TRANSPARENT
	normal_box.set_border_width_all(0)
	normal_box.content_margin_left = 12
	normal_box.content_margin_right = 12
	normal_box.content_margin_top = 6
	normal_box.content_margin_bottom = 6
	theme.set_stylebox("normal", "Button", normal_box)

	# 悬停状态：浅灰圆角背景
	var hover_box := StyleBoxFlat.new()
	hover_box.bg_color = Color("f5f5f5")
	hover_box.set_border_width_all(0)
	hover_box.set_corner_radius_all(4)
	hover_box.content_margin_left = 12
	hover_box.content_margin_right = 12
	hover_box.content_margin_top = 6
	hover_box.content_margin_bottom = 6
	theme.set_stylebox("hover", "Button", hover_box)

	# 按下状态：更深灰背景
	var pressed_box := StyleBoxFlat.new()
	pressed_box.bg_color = Color("e8e8e8")
	pressed_box.set_border_width_all(0)
	pressed_box.set_corner_radius_all(4)
	pressed_box.content_margin_left = 12
	pressed_box.content_margin_right = 12
	pressed_box.content_margin_top = 6
	pressed_box.content_margin_bottom = 6
	theme.set_stylebox("pressed", "Button", pressed_box)

	# 焦点状态：细边框
	var focus_box := StyleBoxFlat.new()
	focus_box.bg_color = Color.TRANSPARENT
	focus_box.border_color = CardSpec.color("border")  # #e0e0e0
	focus_box.set_border_width_all(1)
	focus_box.set_corner_radius_all(4)
	focus_box.content_margin_left = 11  # 减1像素补偿边框
	focus_box.content_margin_right = 11
	focus_box.content_margin_top = 5
	focus_box.content_margin_bottom = 5
	theme.set_stylebox("focus", "Button", focus_box)

	# 禁用状态：透明背景
	var disabled_box := StyleBoxFlat.new()
	disabled_box.bg_color = Color.TRANSPARENT
	disabled_box.set_border_width_all(0)
	disabled_box.content_margin_left = 12
	disabled_box.content_margin_right = 12
	disabled_box.content_margin_top = 6
	disabled_box.content_margin_bottom = 6
	theme.set_stylebox("disabled", "Button", disabled_box)

	# 图标与文字间距
	theme.set_constant("h_separation", "Button", 8)
	theme.set_constant("icon_max_width", "Button", 16)
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color.WHITE
	panel.border_color = CardSpec.color("border")
	panel.set_border_width_all(int(CardSpec.data().card.border_width_normal))
	panel.set_corner_radius_all(8)
	panel.anti_aliasing = true
	panel.set_content_margin_all(6)
	theme.set_stylebox("panel", "PanelContainer", panel)
	var separator := StyleBoxLine.new()
	separator.color = CardSpec.color("border")
	separator.thickness = 1
	theme.set_stylebox("separator", "HSeparator", separator)
	theme.set_constant("separation", "HSeparator", 8)

	_cached_theme = theme
	return theme
