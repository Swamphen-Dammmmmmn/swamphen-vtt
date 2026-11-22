extends RefCounted

const Typography = preload("res://ui/theme/typography.gd")
const FluentTheme = preload("res://ui/theme/themes/fluent_theme.gd")
const T = preload("res://ui/theme/tokens/fluent_tokens.gd")
const Bar = preload("res://ui/theme/tokens/adventure_topbar_tokens.gd")

static var _shared: Theme

static func shared() -> Theme:
	if _shared != null:
		return _shared
	_shared = FluentTheme.shared().duplicate()
	_setup_surfaces()
	_setup_category_tabs()
	_setup_labels()
	return _shared

static func _setup_surfaces() -> void:
	_shared.set_type_variation("TopbarPrimarySurface", "PanelContainer")
	var primary := StyleBoxFlat.new()
	primary.bg_color = T.SURFACE
	primary.border_color = T.STROKE
	primary.border_width_bottom = 1
	primary.content_margin_left = Bar.PRIMARY_PADDING_H
	primary.content_margin_right = Bar.PRIMARY_PADDING_H
	primary.content_margin_top = Bar.PRIMARY_PADDING_V
	primary.content_margin_bottom = Bar.PRIMARY_PADDING_V
	_shared.set_stylebox("panel", "TopbarPrimarySurface", primary)

	_shared.set_type_variation("TopbarSecondarySurface", "PanelContainer")
	var secondary := StyleBoxFlat.new()
	secondary.bg_color = T.BACKGROUND
	secondary.border_color = T.STROKE
	secondary.border_width_bottom = 1
	secondary.content_margin_left = Bar.SECONDARY_PADDING_H
	secondary.content_margin_right = Bar.SECONDARY_PADDING_H
	secondary.content_margin_top = Bar.SECONDARY_PADDING_TOP
	secondary.content_margin_bottom = Bar.SECONDARY_PADDING_BOTTOM
	_shared.set_stylebox("panel", "TopbarSecondarySurface", secondary)

	_shared.set_type_variation("TopbarToolStripSurface", "PanelContainer")
	var strip := StyleBoxFlat.new()
	strip.bg_color = T.SURFACE
	strip.border_color = T.STROKE
	strip.border_width_bottom = 1
	strip.content_margin_left = Bar.TOOL_STRIP_PADDING_H
	strip.content_margin_right = Bar.TOOL_STRIP_PADDING_H
	strip.content_margin_top = Bar.TOOL_STRIP_PADDING_V
	strip.content_margin_bottom = Bar.TOOL_STRIP_PADDING_V
	_shared.set_stylebox("panel", "TopbarToolStripSurface", strip)

	_shared.set_type_variation("TopbarSummaryChip", "PanelContainer")
	var chip := FluentTheme.face(T.BACKGROUND, T.STROKE, 6, 1)
	chip.content_margin_left = 10
	chip.content_margin_right = 10
	chip.content_margin_top = 4
	chip.content_margin_bottom = 4
	_shared.set_stylebox("panel", "TopbarSummaryChip", chip)

	_shared.set_type_variation("TopbarVDivider", "VSeparator")
	var vline := StyleBoxLine.new()
	vline.color = T.STROKE
	vline.thickness = 1
	vline.vertical = true
	_shared.set_stylebox("separator", "TopbarVDivider", vline)
	_shared.set_constant("separation", "TopbarVDivider", 1)

static func _setup_category_tabs() -> void:
	# Categories share the selected choice face; navigation density stays compact.
	# Ordinary, primary, choice, and compact buttons reuse FluentTheme + FluentButton directly.
	for variant in ["TopbarTab", "TopbarTabActive"]:
		var active: bool = variant == "TopbarTabActive"
		_shared.set_type_variation(variant, "Button")
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			var bg := Color.TRANSPARENT
			if active:
				bg = T.NOTICE_BACKGROUND
			elif state == "hover":
				bg = T.HOVER
			elif state in ["pressed", "hover_pressed"]:
				bg = T.PRESSED
			var face: StyleBoxFlat
			if active:
				face = FluentTheme.shared().get_stylebox(state, "FluentChoiceSelected").duplicate() as StyleBoxFlat
			else:
				face = FluentTheme.face(bg, Color.TRANSPARENT, T.RADIUS, 1)
			face.content_margin_left = 12
			face.content_margin_right = 12
			face.content_margin_top = 6
			face.content_margin_bottom = 6
			_shared.set_stylebox(state, variant, face)
			var fg: Color = T.DISABLED if state == "disabled" else (T.BRAND if active else T.FOREGROUND)
			_shared.set_color("font_color" if state == "normal" else "font_" + state + "_color", variant, fg)
			_shared.set_color("icon_normal_color" if state == "normal" else "icon_" + state + "_color", variant, fg)
		_shared.set_color("font_focus_color", variant, T.BRAND if active else T.FOREGROUND)
		_shared.set_color("icon_focus_color", variant, T.BRAND if active else T.FOREGROUND)
		_shared.set_font("font", variant, Typography.MEDIUM if active else Typography.REGULAR)
		_shared.set_font_size("font_size", variant, Typography.CAPTION)
		_shared.set_constant("h_separation", variant, 6)
		_shared.set_constant("icon_max_width", variant, Bar.ICON_SIZE)
		_shared.set_stylebox("focus", variant, FluentTheme.shared().get_stylebox("focus", "FluentChoiceSelected" if active else "FluentChoice"))

static func _setup_labels() -> void:
	_shared.set_type_variation("TopbarToolTitle", "Label")
	_shared.set_font("font", "TopbarToolTitle", Typography.MEDIUM)
	_shared.set_font_size("font_size", "TopbarToolTitle", Typography.CAPTION)
	_shared.set_color("font_color", "TopbarToolTitle", T.BRAND)

	_shared.set_type_variation("TopbarSectionTitle", "Label")
	_shared.set_font("font", "TopbarSectionTitle", Typography.MEDIUM)
	_shared.set_font_size("font_size", "TopbarSectionTitle", Typography.CAPTION)
	_shared.set_color("font_color", "TopbarSectionTitle", T.FOREGROUND)

	_shared.set_type_variation("TopbarMuted", "Label")
	_shared.set_font_size("font_size", "TopbarMuted", Typography.STATUS)
	_shared.set_color("font_color", "TopbarMuted", T.SECONDARY)
