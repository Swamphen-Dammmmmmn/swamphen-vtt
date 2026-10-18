# -*- coding: utf-8 -*-
extends RefCounted

const Typography = preload("res://ui/theme/typography.gd")

# Gemini 独立设计的原生菜单主题 (Revision 3)
# 针对 Godot 4 嵌入式窗口弹出菜单圆角外围暗色残留与黑圈问题的实现假设与优化
static var _cached_themes: Dictionary = {}

static func get_theme(mobile: bool = false) -> Theme:
	var key := "mobile" if mobile else "desktop"
	if _cached_themes.has(key):
		return _cached_themes[key]

	var theme := Theme.new()

	# 配置支持 MSDF 的中文字体，消除小字号模糊
	var lib_font: Font = Typography.REGULAR
	theme.default_font = lib_font
	theme.set_font("font", "PopupMenu", lib_font)

	# 窗口边框清空：移除 Godot 默认 Window 嵌入边框与内建投影
	theme.set_stylebox("embedded_border", "Window", StyleBoxEmpty.new())
	theme.set_stylebox("embedded_unfocused_border", "Window", StyleBoxEmpty.new())

	# 字号与文字颜色设置 (原生菜单默认字色为暗深色 #242424)
	var font_size := Typography.CAPTION if not mobile else Typography.LEGACY_BODY
	theme.set_font_size("font_size", "PopupMenu", font_size)
	theme.set_color("font_color", "PopupMenu", Color("242424"))
	theme.set_color("font_hover_color", "PopupMenu", Color("242424"))
	theme.set_color("font_disabled_color", "PopupMenu", Color("a0a0a0"))

	# 菜单面板：纯白底色、细边框（与卡片一致）、无阴影
	const CardSpec := preload("res://ui/theme/tokens/library_card_spec.gd")
	var panel_box := StyleBoxFlat.new()
	panel_box.bg_color = Color.WHITE
	panel_box.border_color = CardSpec.color("border")  # #e0e0e0
	var border_width: int = CardSpec.data()["card"]["border_width_normal"]  # 1
	panel_box.set_border_width_all(border_width)
	panel_box.set_corner_radius_all(8)
	panel_box.shadow_size = 0
	panel_box.shadow_color = Color.TRANSPARENT
	panel_box.anti_aliasing = true
	panel_box.anti_aliasing_size = 1.0
	panel_box.corner_detail = 12
	panel_box.draw_center = true
	panel_box.border_blend = false
	panel_box.content_margin_left = 6
	panel_box.content_margin_right = 6
	panel_box.content_margin_top = 6
	panel_box.content_margin_bottom = 6
	theme.set_stylebox("panel", "PopupMenu", panel_box)

	# 悬停项样式：浅灰圆角胶囊
	var hover_box := StyleBoxFlat.new()
	hover_box.bg_color = Color("f5f5f5")
	hover_box.border_color = Color.TRANSPARENT
	hover_box.set_border_width_all(0)
	hover_box.set_corner_radius_all(4)
	hover_box.content_margin_left = 8
	hover_box.content_margin_right = 8
	hover_box.content_margin_top = 6
	hover_box.content_margin_bottom = 6
	theme.set_stylebox("hover", "PopupMenu", hover_box)

	# 分割线样式
	var separator_box := StyleBoxLine.new()
	separator_box.color = Color("e0e0e0")
	separator_box.thickness = 1
	separator_box.content_margin_top = 4
	separator_box.content_margin_bottom = 4
	theme.set_stylebox("separator", "PopupMenu", separator_box)

	# 尺寸与间距约束
	var v_sep := 12 if mobile else 6
	theme.set_constant("v_separation", "PopupMenu", v_sep)
	theme.set_constant("h_separation", "PopupMenu", 8)
	theme.set_constant("item_start_padding", "PopupMenu", 4)
	theme.set_constant("item_end_padding", "PopupMenu", 4)
	theme.set_constant("icon_max_width", "PopupMenu", 16)

	_cached_themes[key] = theme
	return theme

static func _get_base_theme() -> Theme:
	if ResourceLoader.exists("res://addons/gohud/core/go_ui.gd"):
		var goui_script: Variant = load("res://addons/gohud/core/go_ui.gd")
		if goui_script != null and goui_script.has_method("theme"):
			var t: Theme = goui_script.theme()
			if t != null:
				return t
	return Theme.new()
