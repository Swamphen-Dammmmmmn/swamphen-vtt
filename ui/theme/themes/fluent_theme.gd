extends RefCounted

const Typography = preload("res://ui/theme/typography.gd")
const CardSpec = preload("res://ui/theme/tokens/library_card_spec.gd")
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
	_shared.set_type_variation("FluentSecondary", "Label")
	_shared.set_color("font_color", "FluentSecondary", T.SECONDARY)
	_setup_input_action()
	for variant in ["FluentButton", "FluentPrimary", "FluentDanger", "FluentDangerOutline", "FluentEntry", "FluentPrimaryEntry", "FluentFilter", "FluentCompact"]:
		_shared.set_type_variation(variant, "Button")
		var primary: bool = variant in ["FluentPrimary", "FluentPrimaryEntry"]
		var danger: bool = variant == "FluentDanger"
		var danger_outline: bool = variant == "FluentDangerOutline"
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
			if danger_outline and state != "disabled": fg = T.DANGER
			if variant=="FluentFilter" and state in ["pressed","hover_pressed"]: fg = Color.WHITE
			_shared.set_color("font_color" if state == "normal" else "font_"+state+"_color", variant, fg)
			_shared.set_color("icon_normal_color" if state == "normal" else "icon_"+state+"_color", variant, fg)
		_shared.set_color("font_focus_color", variant, T.DANGER if danger_outline else (Color.WHITE if primary or danger else T.FOREGROUND))
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
	_setup_controls()
	_shared.set_type_variation("FluentSeparator", "HSeparator")
	var separator := StyleBoxLine.new()
	separator.color = T.STROKE
	separator.thickness = 1
	_shared.set_stylebox("separator", "FluentSeparator", separator)
	_setup_property_group()
	_setup_selection_variants()
	_setup_toolbar_variants()
	_setup_asset_slot_variants()
	_setup_select_popup()
	_setup_color_well()
	return _shared

static func _setup_controls() -> void:
	# Explicit variations only: base HSlider / SpinBox / CheckBox defaults remain untouched
	# so existing accepted pages (e.g. token editors, settings) are unaffected.
	_shared.set_type_variation("FluentSlider", "HSlider")
	var track := StyleBoxFlat.new()
	track.bg_color = T.STROKE
	track.set_corner_radius_all(3)
	track.content_margin_top = 2
	track.content_margin_bottom = 2
	_shared.set_stylebox("slider", "FluentSlider", track)
	for state in ["grabber_area", "grabber_area_highlight"]:
		var filled := track.duplicate() as StyleBoxFlat
		filled.bg_color = T.BRAND
		_shared.set_stylebox(state, "FluentSlider", filled)
	_shared.set_icon("grabber", "FluentSlider", load("res://ui/theme/icons/color_picker/grabber.svg"))
	_shared.set_icon("grabber_highlight", "FluentSlider", load("res://ui/theme/icons/color_picker/grabber.svg"))

	_shared.set_type_variation("FluentSpinBox", "SpinBox")
	_shared.set_icon("up", "FluentSpinBox", load("res://ui/theme/icons/color_picker/spin_up.svg"))
	_shared.set_icon("down", "FluentSpinBox", load("res://ui/theme/icons/color_picker/spin_down.svg"))
	for state in ["up_background", "up_background_hovered", "up_background_pressed", "up_background_disabled", "down_background", "down_background_hovered", "down_background_pressed", "down_background_disabled"]:
		var bg: Color = T.HOVER if state.ends_with("hovered") else (T.PRESSED if state.ends_with("pressed") else Color.TRANSPARENT)
		var btn_face := StyleBoxFlat.new()
		btn_face.bg_color = bg
		btn_face.set_corner_radius_all(4)
		_shared.set_stylebox(state, "FluentSpinBox", btn_face)
	_shared.set_stylebox("field_and_buttons_separator", "FluentSpinBox", StyleBoxEmpty.new())
	_shared.set_stylebox("up_down_buttons_separator", "FluentSpinBox", StyleBoxEmpty.new())
	_shared.set_constant("buttons_width", "FluentSpinBox", 22)
	_shared.set_constant("set_min_buttons_width_from_icons", "FluentSpinBox", 0)

	_shared.set_type_variation("FluentCheckBox", "CheckBox")
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var check_face := StyleBoxEmpty.new()
		check_face.content_margin_left = 4
		check_face.content_margin_right = 4
		check_face.content_margin_top = 4
		check_face.content_margin_bottom = 4
		_shared.set_stylebox(state, "FluentCheckBox", check_face)
		var fg: Color = T.DISABLED if state == "disabled" else T.FOREGROUND
		_shared.set_color("font_color" if state == "normal" else "font_" + state + "_color", "FluentCheckBox", fg)
	_shared.set_color("font_focus_color", "FluentCheckBox", T.FOREGROUND)
	_shared.set_stylebox("focus", "FluentCheckBox", face(Color.TRANSPARENT, T.BRAND, 6, 2))
	_shared.set_font_size("font_size", "FluentCheckBox", T.BODY_SIZE)
	_shared.set_constant("h_separation", "FluentCheckBox", 8)

static func _setup_selection_variants() -> void:
	# Persistent selection is expressed by swapping variants, not toggle_mode;
	# geometry stays identical between selected and unselected states.
	for variant in ["FluentChoice", "FluentChoiceSelected", "FluentListRow", "FluentListRowSelected"]:
		_shared.set_type_variation(variant, "Button")
		var selected: bool = variant.ends_with("Selected")
		var row: bool = variant.begins_with("FluentListRow")
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			var bg: Color = T.NOTICE_BACKGROUND if selected else (T.SURFACE if state == "normal" else T.HOVER)
			if state in ["pressed", "hover_pressed"] and not selected: bg = T.PRESSED
			if state == "disabled": bg = T.HOVER if not row else T.SURFACE
			var border: Color = T.BRAND if selected and not row else T.STROKE
			var style := face(bg, border, T.RADIUS, 0 if row else 1)
			if row:
				style.content_margin_left = 12
				style.content_margin_right = 8
			_shared.set_stylebox(state, variant, style)
			var fg: Color = T.DISABLED if state == "disabled" else (T.BRAND if selected else T.FOREGROUND)
			_shared.set_color("font_color" if state == "normal" else "font_" + state + "_color", variant, fg)
			_shared.set_color("icon_normal_color" if state == "normal" else "icon_" + state + "_color", variant, fg)
		_shared.set_color("font_focus_color", variant, T.BRAND if selected else T.FOREGROUND)
		_shared.set_font_size("font_size", variant, T.BODY_SIZE)
		_shared.set_constant("h_separation", variant, 8)
		_shared.set_stylebox("focus", variant, face(Color.TRANSPARENT, T.FOREGROUND, T.RADIUS, 2))

static func _setup_toolbar_variants() -> void:
	for variant in ["FluentToolbar", "FluentToolbarSelected", "FluentToolbarDanger"]:
		var selected: bool = variant.ends_with("Selected")
		var danger: bool = variant.ends_with("Danger")
		var source := "FluentChoiceSelected" if selected else ("FluentDangerOutline" if danger else "FluentChoice")
		_shared.set_type_variation(variant, "Button")
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
			var face := _shared.get_stylebox(state, source).duplicate() as StyleBoxFlat
			face.content_margin_left = T.TOOLBAR_PADDING_H
			face.content_margin_right = T.TOOLBAR_PADDING_H
			face.content_margin_top = T.TOOLBAR_PADDING_V
			face.content_margin_bottom = T.TOOLBAR_PADDING_V
			_shared.set_stylebox(state, variant, face)
			var ink: Color = T.DISABLED if state == "disabled" else (T.DANGER if danger else (T.BRAND if selected else T.FOREGROUND))
			_shared.set_color("font_color" if state == "normal" else "font_" + state + "_color", variant, ink)
			_shared.set_color("icon_" + state + "_color", variant, ink)
		_shared.set_font_size("font_size", variant, Typography.CAPTION)
		_shared.set_font("font", variant, Typography.MEDIUM if selected else Typography.REGULAR)
		_shared.set_constant("h_separation", variant, 6)
		_shared.set_constant("icon_max_width", variant, T.TOOLBAR_ICON_SIZE)

static func _setup_asset_slot_variants() -> void:
	# Explicit variations for compact asset grid slots (creation_slot.gd when fluent=true).
	# Reuses FluentTokens + LibraryCardSpec hover border token without touching base Button or library cards.
	var hover_stroke: Color = CardSpec.color("border_hover")
	for variant in ["FluentAssetSlot", "FluentAssetSlotSelected"]:
		var selected: bool = variant == "FluentAssetSlotSelected"
		_shared.set_type_variation(variant, "Button")
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			var bg: Color = T.BACKGROUND if state == "disabled" else (T.NOTICE_BACKGROUND if selected else T.SURFACE)
			var border: Color = T.STROKE if state == "disabled" else (T.BRAND if selected else T.STROKE)
			if not selected and state != "disabled":
				if state == "hover":
					bg = T.HOVER
					border = hover_stroke
				elif state in ["pressed", "hover_pressed"]:
					bg = T.PRESSED
					border = hover_stroke
			var style := face(bg, border, T.COMPACT_SLOT_RADIUS, 2 if selected and state != "disabled" else 1)
			style.set_content_margin_all(0)
			_shared.set_stylebox(state, variant, style)
		var focus_box := face(Color.TRANSPARENT, T.FOREGROUND, T.COMPACT_SLOT_RADIUS, 2)
		focus_box.set_content_margin_all(0)
		_shared.set_stylebox("focus", variant, focus_box)

static func _setup_select_popup() -> void:
	# Shared select control: collapsed trigger, expanded panel and rows are all main-canvas Controls,
	# so no PopupMenu/Window theme is involved. Selection (check), hover and keyboard focus stay distinct.
	const Trigger := "FluentSelectTrigger"
	_shared.set_type_variation(Trigger, "Button")
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		var source := _shared.get_stylebox(state, "FluentButton") as StyleBoxFlat
		var style := source.duplicate() as StyleBoxFlat
		# Room on the right for the drawn chevron.
		style.content_margin_right = T.SELECT_TRIGGER_RIGHT
		_shared.set_stylebox(state, Trigger, style)
	for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_disabled_color", "font_focus_color"]:
		_shared.set_color(color_name, Trigger, _shared.get_color(color_name, "FluentButton"))
	_shared.set_font_size("font_size", Trigger, T.BODY_SIZE)
	const Panel := "FluentSelectPanel"
	_shared.set_type_variation(Panel, "PanelContainer")
	var panel := face(T.SURFACE, T.STROKE, T.RADIUS)
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		panel.set_content_margin(side, T.SELECT_PANEL_PADDING)
	_shared.set_stylebox("panel", Panel, panel)
	const Item := "FluentSelectItem"
	_shared.set_type_variation(Item, "Button")
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var background := Color.TRANSPARENT
		if state == "hover": background = T.HOVER
		if state in ["pressed", "hover_pressed"]: background = T.PRESSED
		var row := face(background, Color.TRANSPARENT, 6, 0)
		row.content_margin_left = 8
		row.content_margin_right = 8
		row.content_margin_top = 4
		row.content_margin_bottom = 4
		_shared.set_stylebox(state, Item, row)
		var foreground: Color = T.DISABLED if state == "disabled" else T.FOREGROUND
		_shared.set_color("font_color" if state == "normal" else "font_" + state + "_color", Item, foreground)
		_shared.set_color("icon_normal_color" if state == "normal" else "icon_" + state + "_color", Item, Color(1, 1, 1, 0.4 if state == "disabled" else 1.0))
	_shared.set_color("font_focus_color", Item, T.FOREGROUND)
	_shared.set_color("icon_focus_color", Item, Color.WHITE)
	_shared.set_stylebox("focus", Item, face(Color.TRANSPARENT, T.FOREGROUND, 6, 2))
	_shared.set_font("font", Item, Typography.REGULAR)
	_shared.set_font_size("font_size", Item, T.BODY_SIZE)
	_shared.set_constant("h_separation", Item, T.SELECT_ITEM_GAP)
	_shared.set_constant("icon_max_width", Item, T.SELECT_MARK_SIZE)
	# Group heading rows: caption text, no face; a heading without text is drawn as a thin rule.
	const Group := "FluentSelectGroup"
	_shared.set_type_variation(Group, "Button")
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		var heading := face(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0)
		heading.content_margin_left = 8
		heading.content_margin_right = 8
		heading.content_margin_top = 0
		heading.content_margin_bottom = 0
		_shared.set_stylebox(state, Group, heading)
	_shared.set_color("font_disabled_color", Group, T.SECONDARY)
	_shared.set_font("font", Group, Typography.REGULAR)
	_shared.set_font_size("font_size", Group, T.CAPTION_SIZE)
	const Rule := "FluentSelectRule"
	_shared.set_type_variation(Rule, "Panel")
	var rule_line := StyleBoxFlat.new()
	rule_line.bg_color = T.STROKE
	_shared.set_stylebox("panel", Rule, rule_line)

static func _setup_color_well() -> void:
	# Color entry: FluentButton faces with room on the left for the drawn swatch.
	const Well := "FluentColorWell"
	_shared.set_type_variation(Well, "Button")
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		var style := (_shared.get_stylebox(state, "FluentButton") as StyleBoxFlat).duplicate() as StyleBoxFlat
		style.content_margin_left = 16 + T.COLOR_SWATCH_SIZE + T.COLOR_SWATCH_GAP
		_shared.set_stylebox(state, Well, style)
	for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_hover_pressed_color", "font_disabled_color", "font_focus_color"]:
		_shared.set_color(color_name, Well, _shared.get_color(color_name, "FluentButton"))
	_shared.set_font_size("font_size", Well, T.BODY_SIZE)

static func _setup_input_action() -> void:
	# Actions embedded in a field: no face, icon color feedback, keyboard focus ring.
	const Action := "FluentInputAction"
	_shared.set_type_variation(Action, "Button")
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		_shared.set_stylebox(state, Action, StyleBoxEmpty.new())
		var icon: Color = T.DISABLED if state == "disabled" else (T.BRAND if state in ["hover", "pressed", "hover_pressed"] else T.SECONDARY)
		_shared.set_color("icon_normal_color" if state == "normal" else "icon_"+state+"_color", Action, icon)
	_shared.set_color("icon_focus_color", Action, T.SECONDARY)
	# Same ring geometry as the legacy action so field reserve and hit area stay unchanged.
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color.TRANSPARENT
	focus.set_border_width_all(2)
	focus.border_color = T.BRAND
	focus.set_corner_radius_all(4)
	_shared.set_stylebox("focus", Action, focus)

static func _setup_property_group() -> void:
	# Isolate the new property group from GoUi's legacy dark foldable styles.
	const Group := "FluentPropertyGroup"
	_shared.set_type_variation(Group, "FoldableContainer")
	for state in ["panel", "title_panel", "title_collapsed_panel", "title_hover_panel", "title_collapsed_hover_panel"]:
		var body: bool = state == "panel"
		var background: Color = T.HOVER if "hover" in state else T.SURFACE
		var source := _shared.get_stylebox(state, "FoldableContainer")
		var style := face(background, T.STROKE, 0 if body else T.RADIUS, 0 if body else 1)
		# Keep native title/content geometry when replacing the inherited colors.
		for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
			style.set_content_margin(side, source.get_content_margin(side))
		_shared.set_stylebox(state, Group, style)
	_shared.set_stylebox("focus", Group, face(Color.TRANSPARENT, T.FOREGROUND, T.RADIUS, 2))
	for color_name in ["font_color", "hover_font_color", "collapsed_font_color"]:
		_shared.set_color(color_name, Group, T.FOREGROUND)
	_shared.set_color("font_outline_color", Group, Color.TRANSPARENT)
	_shared.set_constant("outline_size", Group, 0)
	_shared.set_font("font", Group, Typography.REGULAR)
	_shared.set_font_size("font_size", Group, T.BODY_SIZE)
	_shared.set_icon("expanded_arrow", Group, preload("res://ui/theme/icons/property_group_down.svg"))
	_shared.set_icon("expanded_arrow_mirrored", Group, preload("res://ui/theme/icons/property_group_down.svg"))
	_shared.set_icon("folded_arrow", Group, preload("res://ui/theme/icons/property_group_right.svg"))
	_shared.set_icon("folded_arrow_mirrored", Group, preload("res://ui/theme/icons/property_group_left.svg"))

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
