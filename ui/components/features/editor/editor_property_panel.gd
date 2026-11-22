# Editor property panel shell
extends PanelContainer

signal collapse_requested
signal collapsed_changed(is_collapsed: bool)
signal status_detail_requested(status_text: String)

enum PanelSide { LEFT, RIGHT }

const FluentTheme = preload("res://ui/theme/themes/fluent_theme.gd")
const T = preload("res://ui/theme/tokens/fluent_tokens.gd")
const ET = preload("res://ui/theme/tokens/editor_tokens.gd")
const Typography = preload("res://ui/theme/typography.gd")
const GoIconSet = preload("res://addons/gohud/core/go_icon_set.gd")
const GoStyle = preload("res://addons/gohud/widgets/go_style.gd")
const EditorLayout = preload("res://ui/components/editor_layout.gd")

var _shell: VBoxContainer
var _header: HBoxContainer
var _title_label: Label
var _scroll: ScrollContainer
var _content_container: VBoxContainer
var _status_container: HBoxContainer
var _status_label: Label
var _status_detail_btn: Button
var _action_container: HBoxContainer
var _collapsed := false
var _collapse_button: Button
var _restore_button: Button
var _fixed_header: VBoxContainer

# Configuration before tree entry
var _config_side := PanelSide.LEFT
var _config_title := "属性"
var _config_can_collapse := true

# Busy/disabled action state - track original state separately from restrictions
var _busy := false
var _actions_disabled := false
var _action_original_states: Dictionary = {}  # button -> original enabled state

func _init() -> void:
	# Panel face using FluentTheme - apply theme to self
	theme = FluentTheme.shared()
	var face := FluentTheme.face(T.SURFACE, T.STROKE, T.RADIUS, 1)
	face.content_margin_left = 0
	face.content_margin_right = 0
	face.content_margin_top = 0
	face.content_margin_bottom = 0
	add_theme_stylebox_override("panel", face)
	custom_minimum_size.x = T.SETTINGS_FIELD_COMPACT_WIDTH

	# Shell
	_shell = VBoxContainer.new()
	_shell.add_theme_constant_override("separation", 0)
	add_child(_shell)

	# Header
	_header = HBoxContainer.new()
	_header.add_theme_constant_override("separation", ET.PANEL_ACTION_GAP)
	_header.custom_minimum_size.y = ET.PANEL_HEADER_HEIGHT
	var header_margin := MarginContainer.new()
	header_margin.add_theme_constant_override("margin_left", int(ET.PANEL_HEADER_MARGIN_H))
	header_margin.add_theme_constant_override("margin_right", int(ET.PANEL_HEADER_MARGIN_H))
	header_margin.add_theme_constant_override("margin_top", int(ET.PANEL_HEADER_MARGIN_V))
	header_margin.add_theme_constant_override("margin_bottom", int(ET.PANEL_HEADER_MARGIN_V))
	header_margin.add_child(_header)
	_shell.add_child(header_margin)

	# Title
	_title_label = Label.new()
	_title_label.add_theme_font_override("font", Typography.MEDIUM)
	_title_label.add_theme_font_size_override("font_size", Typography.SECTION)
	_title_label.add_theme_color_override("font_color", T.FOREGROUND)
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_header.add_child(_title_label)

	# Collapse button
	_collapse_button = Button.new()
	_collapse_button.custom_minimum_size = Vector2(32, 32)
	_collapse_button.flat = true
	_collapse_button.visible = false
	_header.add_child(_collapse_button)

	# Restore button (hidden until collapsed)
	_restore_button = Button.new()
	_restore_button.custom_minimum_size = Vector2(32, 32)
	_restore_button.flat = true
	_restore_button.visible = false
	add_child(_restore_button)  # Sibling to shell

	# Header separator
	var sep_style := StyleBoxLine.new()
	sep_style.color = T.STROKE
	sep_style.thickness = 1
	var header_sep := HSeparator.new()
	header_sep.add_theme_constant_override("separation", 1)
	header_sep.add_theme_stylebox_override("separator", sep_style)
	_shell.add_child(header_sep)

	# Optional fixed area under the title (mode switch, tabs); hidden while empty
	# so panels that do not use it keep their original geometry.
	_fixed_header = VBoxContainer.new()
	_fixed_header.add_theme_constant_override("separation", int(ET.PANEL_CONTENT_GAP))
	_fixed_header.visible = false
	var fixed_margin := MarginContainer.new()
	for edge in ["margin_left", "margin_right", "margin_top"]:
		fixed_margin.add_theme_constant_override(edge, int(ET.PANEL_CONTENT_MARGIN))
	fixed_margin.add_theme_constant_override("margin_bottom", 0)
	fixed_margin.add_child(_fixed_header)
	fixed_margin.visible = false
	_shell.add_child(fixed_margin)
	_fixed_header.child_entered_tree.connect(func(_node: Node): _sync_slot.call_deferred(_fixed_header))
	_fixed_header.child_exiting_tree.connect(func(_node: Node): _sync_slot.call_deferred(_fixed_header))

	# Scroll container for content - MUST expand horizontally
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED


	var body_margin := MarginContainer.new()
	body_margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for edge in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		body_margin.add_theme_constant_override(edge, int(ET.PANEL_CONTENT_MARGIN))
	_scroll.add_child(body_margin)
	_shell.add_child(_scroll)

	# Content container (user fills this)
	_content_container = VBoxContainer.new()
	_content_container.add_theme_constant_override("separation", int(ET.PANEL_CONTENT_GAP))
	_content_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_margin.add_child(_content_container)

	# Footer separator
	var footer_sep := HSeparator.new()
	footer_sep.add_theme_constant_override("separation", 1)
	footer_sep.add_theme_stylebox_override("separator", sep_style)
	_shell.add_child(footer_sep)

	# Footer container
	var footer := VBoxContainer.new()
	footer.add_theme_constant_override("separation", int(ET.PANEL_FOOTER_GAP))
	var footer_margin := MarginContainer.new()
	footer_margin.add_theme_constant_override("margin_left", int(ET.PANEL_FOOTER_MARGIN_H))
	footer_margin.add_theme_constant_override("margin_right", int(ET.PANEL_FOOTER_MARGIN_H))
	footer_margin.add_theme_constant_override("margin_top", int(ET.PANEL_FOOTER_MARGIN_V))
	footer_margin.add_theme_constant_override("margin_bottom", int(ET.PANEL_FOOTER_MARGIN_V))
	footer_margin.add_child(footer)
	_shell.add_child(footer_margin)

	# Status container with label and detail button
	_status_container = HBoxContainer.new()
	_status_container.add_theme_constant_override("separation", 4)
	_status_container.visible = false
	footer.add_child(_status_container)

	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", T.CAPTION_SIZE)
	_status_label.custom_minimum_size.y = 24.0
	_status_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_status_label.clip_text = true
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_container.add_child(_status_label)

	_status_detail_btn = Button.new()
	_status_detail_btn.flat = true
	_status_detail_btn.custom_minimum_size = Vector2(24, 24)
	_status_detail_btn.visible = false
	_status_container.add_child(_status_detail_btn)

	# Action container
	_action_container = HBoxContainer.new()
	_action_container.add_theme_constant_override("separation", int(ET.PANEL_ACTION_GAP))
	_action_container.alignment = BoxContainer.ALIGNMENT_END
	footer.add_child(_action_container)

func _ready() -> void:
	_title_label.text = _config_title
	_collapse_button.visible = _config_can_collapse
	_collapse_button.pressed.connect(_on_collapse_pressed)
	_restore_button.pressed.connect(_on_restore_pressed)
	_status_detail_btn.pressed.connect(_on_status_detail_pressed)
	_update_collapse_icons()

	# get_node("/root/Mobile") scrollbar preparation
	if get_node("/root/Mobile").enabled:
		get_node("/root/Mobile").prepare_scrollbar(_scroll.get_v_scroll_bar())

func setup(side: PanelSide, title: String, collapsible: bool) -> void:
	"""Configure the panel. Can be called before or after _ready()."""
	if not (side in [PanelSide.LEFT, PanelSide.RIGHT]):
		push_error("EditorPropertyPanel: side must be PanelSide.LEFT or PanelSide.RIGHT")
		return
	_config_side = side
	_config_title = title
	_config_can_collapse = collapsible
	if is_inside_tree():
		_title_label.text = title
		_collapse_button.visible = collapsible
		_update_collapse_icons()

func content() -> VBoxContainer:
	"""Get the content container where fields should be added."""
	return _content_container

func add_action(button: Button) -> void:
	"""Add an action button to the footer. Tracks original disabled state."""
	if not button:
		push_error("EditorPropertyPanel: Cannot add null button")
		return
	_action_container.add_child(button)
	# Save original disabled state (what the host set)
	_action_original_states[button] = button.disabled
	# Apply current restrictions immediately
	_apply_action_restrictions(button)

func set_action_enabled(button: Button, enabled: bool) -> void:
	"""Set the original enabled state of a specific action. Must be in action container."""
	if not button or not button.get_parent() == _action_container:
		push_error("EditorPropertyPanel: Button must be added via add_action first")
		return
	# Update the original state
	_action_original_states[button] = not enabled
	# Reapply restrictions
	_apply_action_restrictions(button)

func set_busy(busy: bool) -> void:
	"""Set busy state. When busy, all actions are disabled. Idempotent."""
	if _busy == busy:
		return  # Already in this state
	_busy = busy
	_update_all_action_states()

func set_actions_disabled(disabled: bool) -> void:
	"""Explicitly disable/enable all actions. Idempotent."""
	if _actions_disabled == disabled:
		return  # Already in this state
	_actions_disabled = disabled
	_update_all_action_states()

func _apply_action_restrictions(button: Button) -> void:
	"""Apply current restrictions to a single button."""
	if _busy or _actions_disabled:
		button.disabled = true
	else:
		# Restore original state
		button.disabled = _action_original_states.get(button, false)

func _update_all_action_states() -> void:
	"""Update all action buttons based on current restrictions."""
	for child in _action_container.get_children():
		if child is Button:
			_apply_action_restrictions(child)

func set_status(message: String, is_error := false) -> void:
	"""Set status message. Always shows detail button for keyboard accessibility."""
	_status_container.visible = not message.is_empty()
	_status_label.text = message
	_status_label.tooltip_text = message
	_status_label.add_theme_color_override("font_color", T.DANGER if is_error else T.SECONDARY)

	# Always show detail button when there's a message (keyboard accessible)
	_status_detail_btn.visible = not message.is_empty()
	if not message.is_empty():
		GoStyle.apply_icon(_status_detail_btn, GoIconSet.INFO, 16)

func _on_status_detail_pressed() -> void:
	if not _status_label.text.is_empty():
		status_detail_requested.emit(_status_label.text)

func _on_collapse_pressed() -> void:
	toggle_collapse()

func _on_restore_pressed() -> void:
	toggle_collapse()

func toggle_collapse() -> void:
	"""Collapse or expand the panel."""
	_collapsed = not _collapsed
	_shell.visible = not _collapsed
	_restore_button.visible = _collapsed
	_update_collapse_icons()
	custom_minimum_size.x = T.SETTINGS_FIELD_COMPACT_WIDTH if not _collapsed else 48.0
	collapse_requested.emit()
	collapsed_changed.emit(_collapsed)

func is_collapsed() -> bool:
	"""Check if panel is currently collapsed."""
	return _collapsed

func set_collapsed(collapsed: bool) -> void:
	"""Set collapse state. Idempotent and visibl-state-safe."""
	if _collapsed == collapsed:
		return  # Already in this state
	toggle_collapse()

func set_minimum_width(width: float) -> void:
	"""Set panel minimum width when expanded. Public configuration."""
	custom_minimum_size.x = width if not _collapsed else 48.0

func _update_collapse_icons() -> void:
	"""Update collapse/restore button icons based on side and state."""
	if _config_side == PanelSide.LEFT:
		var collapse_icon = GoIconSet.CHEVRON_LEFT if not _collapsed else GoIconSet.CHEVRON_RIGHT
		var restore_icon = GoIconSet.CHEVRON_RIGHT
		GoStyle.apply_icon(_collapse_button, collapse_icon, 16)
		GoStyle.apply_icon(_restore_button, restore_icon, 16)
	else:
		var collapse_icon = GoIconSet.CHEVRON_RIGHT if not _collapsed else GoIconSet.CHEVRON_LEFT
		var restore_icon = GoIconSet.CHEVRON_LEFT
		GoStyle.apply_icon(_collapse_button, collapse_icon, 16)
		GoStyle.apply_icon(_restore_button, restore_icon, 16)

func fixed_header() -> VBoxContainer:
	"""Non-scrolling area below the title, for mode switches and tabs."""
	return _fixed_header

func _sync_slot(slot: VBoxContainer) -> void:
	if not is_instance_valid(slot) or slot.is_queued_for_deletion(): return
	var used := slot.get_child_count() > 0
	slot.visible = used
	if slot == _fixed_header: slot.get_parent().visible = used
