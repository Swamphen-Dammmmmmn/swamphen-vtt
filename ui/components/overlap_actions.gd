extends ScrollContainer

signal action_requested(target: Dictionary, action: String, anchor_control: Control)
signal target_hovered(target: Dictionary)
var rows: VBoxContainer
var entries: Array[Dictionary] = []
var highlighted: Dictionary = {}
var motion: Tween
# Opt-in: other callers keep the existing presentation and pointer rules.
var fluent := false
const ContextCard = preload("res://ui/components/features/adventure/entity_context_card.gd")
const ContextSpec = preload("res://ui/theme/tokens/entity_context_tokens.gd")
var _inset: MarginContainer
var _placement: Dictionary = {}
var _refit_pending := false

func _ready() -> void:
	hide()
	z_index = 5
	theme = GoUi.theme()
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	rows = VBoxContainer.new()
	rows.add_theme_constant_override("separation", 6)
	if fluent:
		_inset = MarginContainer.new()
		for edge in ["left", "right", "top", "bottom"]:
			_inset.add_theme_constant_override("margin_" + edge, ContextSpec.DRAW_INSET)
		add_child(_inset)
		_inset.add_child(rows)
		rows.add_theme_constant_override("separation", ContextSpec.GAP)
		follow_focus = true
		Mobile.prepare_scrollbar(get_v_scroll_bar())
		rows.minimum_size_changed.connect(_queue_refit)
	else:
		add_child(rows)

func present(values: Array[Dictionary], at: Vector2, bounds: Vector2, margin: float, below: bool = false, top_margin := 64.0) -> void:
	if fluent:
		_placement = {"at": at, "bounds": bounds, "margin": margin, "below": below, "top_margin": top_margin}
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
			if fluent:
				var item := ContextCard.new()
				item.configure(entry)
				item.set_meta("target", entry)
				item.action_requested.connect(func(action: String, anchor: Control): action_requested.emit(entry, action, anchor))
				rows.add_child(item)
				continue
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
				button.pressed.connect(func(): action_requested.emit(entry, action, button if action == "more" else card))
				content.add_child(button)
	var fluent_rows := fluent
	if fluent_rows:
		horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_inset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var room := maxf(1, bounds.x - margin - ContextSpec.EDGE_MARGIN)
		var bar_width := get_v_scroll_bar().get_combined_minimum_size().x
		for child in rows.get_children():
			if child is ContextCard:
				child.set_available_width(room - ContextSpec.DRAW_INSET * 2 - bar_width)
	else:
		horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
		rows.size_flags_horizontal = Control.SIZE_FILL
	if _inset != null:
		for edge in ["left", "right", "top", "bottom"]:
			_inset.add_theme_constant_override("margin_" + edge, ContextSpec.DRAW_INSET if fluent_rows else 0)
	var desired := _inset.get_combined_minimum_size() if fluent_rows else rows.get_combined_minimum_size()
	var limit := maxf(44, minf(ContextSpec.MAX_LIST_HEIGHT if fluent_rows else 360.0, bounds.y - top_margin - 54.0))
	var scrollbar_width := get_v_scroll_bar().get_combined_minimum_size().x if desired.y > limit else 0.0
	size = Vector2(minf(desired.x + scrollbar_width, maxf(80, bounds.x - margin - 16)), minf(desired.y, limit))
	position = BoardUiStyle.floating_position(size, Rect2(at, Vector2.ZERO), bounds, margin, BoardUiStyle.FloatingRole.ACTION, below, top_margin)
	if not visible:
		show()
		modulate.a = 0
		if motion:
			motion.kill()
		motion = create_tween()
		motion.tween_property(self, "modulate:a", 1.0, preload("res://ui/components/page_motion.gd").duration(BoardUiStyle.FADE_TIME))

func _queue_refit() -> void:
	if _refit_pending or not is_inside_tree(): return
	_refit_pending = true
	(func():
		_refit_pending = false
		if is_inside_tree() and visible and not _placement.is_empty():
			present(entries, _placement.at, _placement.bounds, _placement.margin, _placement.below, _placement.top_margin)
	).call_deferred()

func update_available_area(bounds: Vector2, margin: float, top_margin: float) -> void:
	if not fluent or _placement.is_empty(): return
	_placement["bounds"] = bounds
	_placement["margin"] = margin
	_placement["top_margin"] = top_margin
	_queue_refit()

func layout_snapshot() -> Dictionary:
	return {"rect": str(get_global_rect()), "content": str(rows.get_global_rect()), "scroll_y": scroll_vertical, "top_margin": _placement.get("top_margin", 0)}

func pointer_near() -> bool:
	var hovered := get_viewport().gui_get_hovered_control()
	return visible and (owns_keyboard() or (hovered != null and (hovered == self or is_ancestor_of(hovered))))

func owns_keyboard() -> bool:
	var focused := get_viewport().gui_get_focus_owner()
	return has_context_entries() and focused != null and is_ancestor_of(focused)

func has_context_entries() -> bool:
	return fluent and visible and not entries.is_empty()

func _process(_delta: float) -> void:
	var target: Dictionary = {}
	if visible:
		var hovered := get_viewport().gui_get_hovered_control()
		if fluent and (hovered == null or not is_ancestor_of(hovered)):
			var focused := get_viewport().gui_get_focus_owner()
			if focused != null and is_ancestor_of(focused): hovered = focused
		while hovered != null and hovered != self:
			if hovered.has_meta("target"):
				target = hovered.get_meta("target")
				break
			hovered = hovered.get_parent() as Control
	if target != highlighted:
		highlighted = target
		target_hovered.emit(target)
