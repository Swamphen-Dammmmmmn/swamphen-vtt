# -*- coding: utf-8 -*-
extends RefCounted

const Typography = preload("res://ui/theme/typography.gd")
const T = preload("res://ui/theme/tokens/fluent_tokens.gd")
const P = preload("res://ui/theme/tokens/party_tokens.gd")
const CardSpec = preload("res://ui/theme/tokens/library_card_spec.gd")

# 团员卡片集中主题
# 卡片外框与大地图卡共用 CardSpec：白底、1px 普通/悬停描边、桌面12／手机10圆角；
# 为团员卡内的三点按钮提供协调样式

static var _cached_theme: Theme = null
static var _faces: Dictionary = {}

# 成员卡 PanelContainer 外框。normal 与 hover 只差描边颜色，边宽与内边距一致，切换不改变尺寸。
static func member_card_face(hovered: bool, mobile: bool) -> StyleBoxFlat:
	var key := "%s_%s" % [hovered, mobile]
	if _faces.has(key):
		return _faces[key]
	var card: Dictionary = CardSpec.data().card
	var box := StyleBoxFlat.new()
	box.bg_color = CardSpec.color("card_bg")
	box.border_color = CardSpec.color("border_hover" if hovered else "border")
	box.set_border_width_all(int(card.border_width_normal))
	box.set_corner_radius_all(int(card.border_radius_mobile) if mobile else int(card.border_radius))
	box.content_margin_left = P.CARD_PADDING_H
	box.content_margin_right = P.CARD_PADDING_H
	box.content_margin_top = P.CARD_PADDING_V
	box.content_margin_bottom = P.CARD_PADDING_V
	_faces[key] = box
	return box

static func text_color() -> Color:
	return CardSpec.color("text")

static func muted_color() -> Color:
	return CardSpec.color("muted")

static func get_theme() -> Theme:
	if _cached_theme != null:
		return _cached_theme

	var theme := Theme.new()

	# 默认字体
	theme.default_font = Typography.REGULAR

	# PartyCardMoreButton 变体：团员卡三点按钮
	# 与原双行卡片保持一致，不再嵌套常驻小方框；保留浅色反馈与键盘焦点。
	theme.set_type_variation("PartyCardMoreButton", "Button")

	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		var box := StyleBoxFlat.new()
		box.set_corner_radius_all(P.MORE_BUTTON_RADIUS)
		box.content_margin_left = 0
		box.content_margin_right = 0
		box.content_margin_top = 0
		box.content_margin_bottom = 0

		var bg := Color.TRANSPARENT
		var border := Color.TRANSPARENT
		var b_width := 0

		if state == "hover":
			bg = T.HOVER  # #f5f5f5
		elif state in ["pressed", "hover_pressed"]:
			bg = T.PRESSED  # #e0e0e0
		elif state == "focus":
			# 键盘焦点加强描边，不用黑底
			bg = Color.TRANSPARENT
			border = T.FOREGROUND  # #242424
			b_width = P.MORE_BUTTON_BORDER
		elif state == "disabled":
			bg = Color.TRANSPARENT
			border = T.DISABLED

		box.bg_color = bg
		box.border_color = border
		box.set_border_width_all(b_width)
		theme.set_stylebox(state, "PartyCardMoreButton", box)

		var fg := T.SECONDARY  # #616161
		if state == "hover": fg = T.FOREGROUND  # #242424
		elif state == "disabled": fg = T.DISABLED  # #bdbdbd
		theme.set_color("icon_normal_color" if state == "normal" else "icon_" + state + "_color", "PartyCardMoreButton", fg)

	_cached_theme = theme
	return theme
