extends ScrollContainer

signal action_requested(target: Dictionary, action: String, anchor: Rect2)
signal target_hovered(target: Dictionary)
var rows: VBoxContainer
var entries: Array[Dictionary] = []
var highlighted: Dictionary = {}
var motion: Tween

func _ready() -> void:
	hide()
	z_index = 5
	theme = GoUi.theme()
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	rows = VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	add_child(rows)

func present(values: Array[Dictionary], at: Vector2, bounds: Vector2, margin: float, below: bool = false) -> void:
	var normalized: Array[Dictionary] = []
	for value in values:
		var entry := value.duplicate()
		entry.erase("anchor")
		normalized.append(entry)
	if normalized != entries:
		entries = normalized
		for child in rows.get_children():
			rows.remove_child(child)
			child.queue_free()
		for entry in entries:
			var card := PanelContainer.new()
			card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			card.set_meta("target", entry)
			card.add_theme_stylebox_override("panel", BoardUiStyle.card_face(BoardUiStyle.ACTION_PADDING))
			rows.add_child(card)
			var content := HBoxContainer.new()
			content.add_theme_constant_override("separation", 4)
			card.add_child(content)
			var title := Label.new()
			title.text = entry["label"]
			title.tooltip_text = title.text
			title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			title.clip_text = true
			title.add_theme_color_override("font_color", Color("36516d"))
			content.add_child(title)
			title.custom_minimum_size.x = minf(180, title.get_theme_font("font").get_string_size(title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, title.get_theme_font_size("font_size")).x + 2)
			for item in entry["actions"]:
				var action: String = item[0]
				var button := Button.new()
				button.text = item[1]
				if action=="more":
					button.text = ""
					GoStyle.apply_icon(button,GoIconSet.MORE,16)
					button.tooltip_text = "更多操作"
				button.focus_mode = Control.FOCUS_NONE
				BoardUiStyle.action_button(button, BoardUiStyle.ACTION_HEIGHT, false, action.begins_with("delete"))
				button.pressed.connect(func(): action_requested.emit(entry, action, card.get_global_rect()))
				content.add_child(button)
	var desired := rows.get_combined_minimum_size()
	var limit := maxf(44, minf(360, bounds.y - 118))
	var scrollbar_width := get_v_scroll_bar().get_combined_minimum_size().x if desired.y > limit else 0.0
	size = Vector2(minf(desired.x + scrollbar_width, maxf(80, bounds.x - margin - 16)), minf(desired.y, limit))
	position = BoardUiStyle.floating_position(size, Rect2(at, Vector2.ZERO), bounds, margin, BoardUiStyle.FloatingRole.ACTION, below)
	if not visible:
		show()
		modulate.a = 0
		if motion:
			motion.kill()
		motion = create_tween()
		motion.tween_property(self, "modulate:a", 1.0, preload("res://ui/components/page_motion.gd").duration(BoardUiStyle.FADE_TIME))

func pointer_near() -> bool:
	var hovered := get_viewport().gui_get_hovered_control()
	return visible and hovered != null and (hovered == self or is_ancestor_of(hovered))

func _process(_delta: float) -> void:
	var target: Dictionary = {}
	if visible:
		var hovered := get_viewport().gui_get_hovered_control()
		while hovered != null and hovered != self:
			if hovered.has_meta("target"):
				target = hovered.get_meta("target")
				break
			hovered = hovered.get_parent() as Control
	if target != highlighted:
		highlighted = target
		target_hovered.emit(target)
