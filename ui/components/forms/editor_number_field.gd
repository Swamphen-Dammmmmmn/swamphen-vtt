# Editor number field component (with unit support)
extends "res://ui/components/forms/editor_field_base.gd"

signal value_submitted(value: float)

var _row: HBoxContainer
var _input: LineEdit
var _unit_label: Label
var _min_value := -INF
var _max_value := INF
var _allow_decimals := true

# State tracking
var _committed_value := NAN  # Last valid submitted value
var _draft_text := ""  # Current draft text (what user typed)
var _editing := false

func _init() -> void:
	super._init()

	# Label
	_label = _create_label("")
	add_child(_label)

	# Row for input + unit
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation", 8)
	add_child(_row)

	# Input
	_input = LineEdit.new()
	_input.custom_minimum_size.y = T.BUTTON_HEIGHT
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.add_theme_font_size_override("font_size", T.BODY_SIZE)
	_row.add_child(_input)
	_input_control = _input

	# Unit label
	_unit_label = Label.new()
	_unit_label.add_theme_font_size_override("font_size", T.BODY_SIZE)
	_unit_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_unit_label.visible = false
	_row.add_child(_unit_label)

	# Error label
	_error_label = _create_error_label()
	add_child(_error_label)

func _ready() -> void:
	super._ready()
	_input.text_changed.connect(_on_text_changed)
	_input.text_submitted.connect(_on_text_submitted)
	_input.focus_entered.connect(_on_focus_entered)
	_input.focus_exited.connect(_on_focus_exited)
	_update_appearance()

func setup(label_text: String, unit := "", min_val := -INF, max_val := INF, allow_decimals := true, initial_value := NAN) -> void:
	"""Configure the field. Can be called before or after _ready()."""
	_label.text = label_text
	_min_value = min_val
	_max_value = max_val
	_allow_decimals = allow_decimals

	# Validate initial value
	if is_finite(initial_value):
		if initial_value < _min_value or initial_value > _max_value:
			push_error("EditorNumberField.setup: initial_value %s out of range [%s, %s]" % [initial_value, _min_value, _max_value])
			return
		if not _allow_decimals:
			var rounded := roundi(initial_value)
			if initial_value != float(rounded):
				push_error("EditorNumberField.setup: initial_value %s is not integer but allow_decimals=false" % initial_value)
				return

	# Update unit visibility
	if not unit.is_empty():
		_unit_label.text = unit
		_unit_label.visible = true
	else:
		_unit_label.visible = false

	# Set initial value if valid
	if is_finite(initial_value):
		_committed_value = initial_value
		_draft_text = _format_for_display(initial_value)
		if not _editing:
			_input.text = _draft_text

func get_value() -> float:
	"""Get the last valid committed value. Returns NAN if no valid value submitted yet."""
	return _committed_value

func has_valid_value() -> bool:
	"""Check if a valid value has been committed."""
	return is_finite(_committed_value)

func set_value(value: float, overwrite_draft := false) -> bool:
	"""Program sets value. Does not emit signal. Rejects out-of-range values."""
	if not is_finite(value):
		push_error("EditorNumberField.set_value: Cannot set non-finite value")
		return false

	# REJECT out of range - do not clamp silently
	if value < _min_value or value > _max_value:
		push_error("EditorNumberField.set_value: Value %s out of range [%s, %s]" % [value, _min_value, _max_value])
		return false

	# Reject non-integer if required
	if not _allow_decimals:
		var rounded := roundi(value)
		if value != float(rounded):
			push_error("EditorNumberField.set_value: Cannot set non-integer value %s when allow_decimals=false" % value)
			return false
		value = float(rounded)
	# Previously the hidden draft changed while the visible input stayed unchanged.
	# A subsequent Enter could therefore commit a value the user had never seen.
	if _editing and not overwrite_draft: return false

	_committed_value = value
	_draft_text = _format_for_display(value)

	var caret_pos := _input.caret_column
	_input.text = _draft_text
	if _input.has_focus(): _input.caret_column = mini(caret_pos, _draft_text.length())
	set_error("")
	return true

func _update_appearance() -> void:
	"""Unified state refresh - applies colors based on all state flags."""
	super._update_appearance()
	_input.editable = not _readonly and not _disabled

	# Determine text color by priority: error > disabled > readonly > normal
	if _has_error:
		_input.add_theme_color_override("font_color", T.DANGER)
	elif _disabled:
		_input.add_theme_color_override("font_color", T.DISABLED)
	elif _readonly:
		_input.add_theme_color_override("font_color", T.SECONDARY)
	else:
		_input.add_theme_color_override("font_color", T.FOREGROUND)

func _on_focus_entered() -> void:
	_editing = true

func _on_focus_exited() -> void:
	_editing = false
	_commit_draft()

func _on_text_changed(new_text: String) -> void:
	_draft_text = new_text
	_clear_error_on_input()

func _on_text_submitted(_text: String) -> void:
	_commit_draft()

func _commit_draft() -> void:
	"""Parse and validate draft, emit if valid. Preserve valid draft text exactly."""
	var parsed := _parse_draft(_draft_text)
	if parsed.has("error"):
		set_error(parsed.error)
		return

	var value: float = parsed.value

	# Validate finite
	if not is_finite(value):
		set_error("无效值")
		return

	# Validate range - explicit feedback
	if value < _min_value or value > _max_value:
		set_error("值应在 %s 与 %s 之间" % [
			_format_for_display(_min_value) if is_finite(_min_value) else "-∞",
			_format_for_display(_max_value) if is_finite(_max_value) else "+∞"
		])
		return

	# Validate integer constraint
	if not _allow_decimals:
		var rounded := roundi(value)
		if value != float(rounded):
			set_error("请输入整数")
			return
		value = float(rounded)

	# Commit - preserve the valid draft text exactly for round-trip
	var changed := not is_finite(_committed_value) or _committed_value != value
	_committed_value = value
	# Keep the valid draft text as-is (round-trip guarantee)
	_input.text = _draft_text

	set_error("")
	if changed:
		value_submitted.emit(value)

func _parse_draft(text: String) -> Dictionary:
	"""Parse draft text. Returns {value: float} or {error: String}."""
	var cleaned := text.strip_edges()
	if cleaned.is_empty():
		return {"error": "不能为空"}
	# Allow intermediate states
	if cleaned in ["-", ".", "-."] or cleaned.ends_with("."):
		return {"error": "请输入完整数字"}
	if not cleaned.is_valid_float():
		return {"error": "无效数字"}
	var value := cleaned.to_float()
	if not is_finite(value):
		return {"error": "无效值"}
	return {"value": value}

func _format_for_display(value: float) -> String:
	"""Format a value for display. Uses str() which preserves precision for most values."""
	if not is_finite(value):
		return ""
	if _allow_decimals:
		# str() preserves decimal precision for round-trip in most cases
		# For values like 1.234, str(1.234) returns "1.234"
		return str(value)
	else:
		return str(roundi(value))

func validate_draft() -> Dictionary:
	var parsed := _parse_draft(_draft_text)
	if parsed.has("error"): return {"ok": false, "message": parsed.error}
	var value: float = parsed.value
	if value < _min_value or value > _max_value:
		return {"ok": false, "message": "值应在 %s 与 %s 之间" % [
			_format_for_display(_min_value) if is_finite(_min_value) else "-∞",
			_format_for_display(_max_value) if is_finite(_max_value) else "+∞"]}
	if not _allow_decimals and value != floor(value):
		return {"ok": false, "message": "请输入整数"}
	return {"ok": true, "value": value}
