extends VBoxContainer

# Camera settings component with Fluent theme
# Emits: value_changed(key: String, value: Variant), reset_requested()

const Typography = preload("res://ui/theme/typography.gd")
const FluentTheme = preload("res://ui/theme/themes/fluent_theme.gd")
const FluentTokens = preload("res://ui/theme/tokens/fluent_tokens.gd")
const FluentButton = preload("res://ui/components/controls/fluent_button.gd")
const SettingsField = preload("res://ui/components/features/settings/settings_field.gd")
const CameraPreferences = preload("res://scripts/camera_preferences.gd")

signal value_changed(key: String, value: Variant)
signal reset_requested()

var _fields: Dictionary = {}

func _ready() -> void:
	theme = FluentTheme.shared()
	add_theme_constant_override("separation", FluentTokens.GAP)

	# Operation speed section
	_add_section("操作速度")
	_add_speed_field("pan", "平移速度")
	_add_speed_field("rotation", "旋转速度")
	_add_speed_field("zoom", "缩放速度")
	_add_choice_field("reverse_zoom", "缩放方向", ["正常", "反转"])

	# Smooth transition section
	_add_separator()
	_add_section("镜头平滑")
	_add_choice_field("smooth", "平滑过渡", ["关闭", "开启"])
	_add_choice_field("strength", "平滑强度", ["轻微", "标准", "明显"])

	# Reset button
	var reset := FluentButton.new()
	reset.text = "恢复镜头默认"
	reset.variant = "FluentButton"
	reset.minimum_height = 40
	reset.pressed.connect(func(): reset_requested.emit())
	add_child(reset)

func _add_section(title: String) -> void:
	var label := Label.new()
	label.text = title
	label.add_theme_font_override("font", Typography.MEDIUM)
	label.add_theme_font_size_override("font_size", Typography.SECTION)
	label.add_theme_color_override("font_color", FluentTokens.FOREGROUND)
	add_child(label)

func _add_separator() -> void:
	var sep := HSeparator.new()
	var style := StyleBoxFlat.new()
	style.bg_color = FluentTokens.STROKE
	sep.add_theme_stylebox_override("separator", style)
	add_child(sep)

func _add_speed_field(key: String, title: String) -> void:
	var labels: Array = []
	for value in CameraPreferences.SPEEDS:
		labels.append("%d%%" % roundi(value * 100))

	var field := SettingsField.new()
	add_child(field)
	field.setup(title, labels)
	_fields[key] = field.option

	field.option.item_selected.connect(func(index: int):
		value_changed.emit(key, CameraPreferences.SPEEDS[index])
	)

func _add_choice_field(key: String, title: String, items: Array) -> void:
	var field := SettingsField.new()
	add_child(field)
	field.setup(title, items)
	_fields[key] = field.option

	field.option.item_selected.connect(func(index: int):
		if key == "reverse_zoom":
			value_changed.emit(key, index == 1)
		elif key == "smooth":
			value_changed.emit(key, index == 1)
		else:
			value_changed.emit(key, index)
	)

func sync_preferences(prefs: RefCounted) -> void:
	"""Sync UI with current camera preference values. Called on init and preference changes."""
	for key in _fields:
		if key in ["pan", "rotation", "zoom"]:
			var value: float = prefs.values.get(key, 1.0)
			var index := CameraPreferences.SPEEDS.find(value)
			if index >= 0:
				_fields[key].select(index)
		elif key == "reverse_zoom":
			_fields[key].select(1 if prefs.values.get(key, false) else 0)
		elif key == "smooth":
			_fields[key].select(1 if prefs.values.get(key, false) else 0)
		elif key == "strength":
			_fields[key].select(int(prefs.values.get(key, 1)))

	# Disable strength when smooth is off
	if "strength" in _fields:
		_fields["strength"].disabled = not prefs.values.get("smooth", false)
