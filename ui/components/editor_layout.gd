extends RefCounted

# Shared desktop property layout; specialized board popovers keep their own sizes.
const Style = preload("res://ui/components/page_style.gd")
const PADDING := 16.0
const GAP := 12
const ROW_GAP := 8
const LABEL_GAP := 6
const STATUS_HEIGHT := 24.0

static func field(parent: Control, title: String) -> VBoxContainer:
	var group := Style.column(LABEL_GAP)
	parent.add_child(group)
	group.add_child(Style.text(title, 14, true))
	return group

static func status() -> Label:
	var label := Style.text("", 14, true)
	label.custom_minimum_size.y = STATUS_HEIGHT
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	label.clip_text = true
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_STOP
	return label

static func set_status(label: Label, text: String, error := false) -> void:
	label.visible = not text.is_empty()
	label.text = text.replace("\n", " · ")
	label.tooltip_text = text
	label.add_theme_color_override("font_color", Color("b33c3c") if error else Color("64748b"))

static func field_error(input: Control, message: String) -> void:
	input.add_theme_color_override("font_color", Color("b33c3c") if not message.is_empty() else Color("334155"))
	input.tooltip_text = message

static func scroll(scroll: ScrollContainer) -> void:
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var bar := scroll.get_v_scroll_bar()
	if Mobile.enabled:
		bar.custom_minimum_size.x = Mobile.SCROLLBAR_WIDTH
		scroll.add_theme_constant_override("scrollbar_h_separation",Mobile.SCROLLBAR_GAP)
	var track := StyleBoxFlat.new()
	track.bg_color = Color("e7edf4")
	track.set_corner_radius_all(6)
	track.set_content_margin_all(2)
	track.content_margin_left = 5
	track.content_margin_right = 5
	bar.add_theme_stylebox_override("scroll", track)
	bar.add_theme_stylebox_override("scroll_focus", track)
	for state in ["grabber", "grabber_highlight", "grabber_pressed"]:
		var thumb := StyleBoxFlat.new()
		thumb.bg_color = Color("71859e") if state == "grabber" else Color("4678b5")
		thumb.set_corner_radius_all(6)
		thumb.content_margin_left = 5
		thumb.content_margin_right = 5
		thumb.content_margin_top = 12
		thumb.content_margin_bottom = 12
		bar.add_theme_stylebox_override(state, thumb)
	if Mobile.enabled: Mobile.prepare_scrollbar(bar)

static func tabs(buttons: Array[Button]) -> void:
	for index in range(buttons.size()):
		for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
			var face := buttons[index].get_theme_stylebox(state) as StyleBoxFlat
			if face == null: continue
			face.set_corner_radius_all(0)
			face.set_border_width_all(2)
			if index == 0:
				face.corner_radius_top_left = 8
				face.corner_radius_bottom_left = 8
			else: face.border_width_left = 0
			if index == buttons.size() - 1:
				face.corner_radius_top_right = 8
				face.corner_radius_bottom_right = 8

static func fold(container: FoldableContainer) -> void:
	container.custom_minimum_size.y = 44
	var empty := StyleBoxEmpty.new()
	empty.content_margin_top = 8
	container.add_theme_stylebox_override("panel", empty)
	for state in ["title_panel", "title_collapsed_panel", "title_hover_panel", "title_collapsed_hover_panel"]:
		var face := StyleBoxFlat.new()
		face.bg_color = Color("eef3f9") if "hover" in state else Color.WHITE
		face.set_corner_radius_all(8)
		face.set_content_margin_all(8)
		container.add_theme_stylebox_override(state, face)

static func enabled(root: Control, active: bool) -> void:
	if not root.has_meta("editor_mouse_filter"): root.set_meta("editor_mouse_filter", root.mouse_filter)
	root.mouse_filter = root.get_meta("editor_mouse_filter") if active else Control.MOUSE_FILTER_IGNORE
	if not root.has_meta("editor_focus_mode"): root.set_meta("editor_focus_mode", root.focus_mode)
	root.focus_mode = root.get_meta("editor_focus_mode") if active else Control.FOCUS_NONE
	if not active and root.has_focus(): root.release_focus()
	for child in root.get_children():
		if child is Control: enabled(child, active)

static func pair(parent: Control, threshold := 280.0) -> BoxContainer:
	var row := BoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", ROW_GAP)
	parent.add_child(row)
	row.resized.connect(func(): row.vertical = row.size.x < threshold)
	return row

static func error_details(label: Label, page: Control = null, title := "读取详情") -> void:
	var button: Button = label.get_meta("error_details") if label.has_meta("error_details") else null
	if not is_instance_valid(button):
		button = Button.new()
		button.text = "查看原因"
		Style.card_button(button)
		label.get_parent().add_child(button)
		label.get_parent().move_child(button,label.get_index()+1)
		label.set_meta("error_details",button)
		button.pressed.connect(func():
			var modal := preload("res://ui/components/page_modal.gd").new()
			var owner: Node = page if is_instance_valid(page) else label
			while owner!=null and not owner.has_method("add_overlay"): owner = owner.get_parent()
			if owner!=null: owner.add_overlay(modal)
			else:
				var layer := CanvasLayer.new()
				var parent_layer := label.get_canvas_layer_node()
				layer.layer = parent_layer.layer+1 if parent_layer!=null else 1
				label.add_child(layer)
				layer.add_child(modal)
				modal.dismissed.connect(layer.queue_free)
			modal.configure(title,label.tooltip_text if not label.tooltip_text.is_empty() else label.text)
			modal.add_action("关闭",modal.dismiss)
		)
	button.visible = label.visible and not label.tooltip_text.is_empty()
