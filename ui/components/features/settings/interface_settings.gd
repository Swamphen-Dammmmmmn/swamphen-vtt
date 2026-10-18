extends VBoxContainer

# Interface settings component with Fluent theme
# Emits: value_changed(key: String, value: Variant), reset_requested()

const Typography = preload("res://ui/theme/typography.gd")
const FluentTheme = preload("res://ui/theme/themes/fluent_theme.gd")
const FluentTokens = preload("res://ui/theme/tokens/fluent_tokens.gd")
const FluentButton = preload("res://ui/components/controls/fluent_button.gd")
const SettingsField = preload("res://ui/components/features/settings/settings_field.gd")
const Preferences = preload("res://scripts/ui_preferences.gd")

signal value_changed(key: String, value: Variant)
signal reset_requested()

var _fields: Dictionary = {}

func _ready() -> void:
	theme = FluentTheme.shared()
	add_theme_constant_override("separation", FluentTokens.GAP)

	# Motion section (most noticeable impact)
	_add_section("动效")
	_add_choice_field("motion", "过渡动画", ["标准", "减弱", "关闭"])

	# Interface size section
	_add_separator()
	_add_section("界面大小")
	_add_scale_field("ui_scale", "整体界面缩放", Preferences.UI_SCALES)
	_add_scale_field("info_scale", "棋子信息栏", Preferences.INFO_SCALES)
	_add_scale_field("floating_text", "对象浮窗文字", Preferences.TEXT_SCALES)
	_add_caption("信息栏和浮窗在整体界面缩放之外额外调整；信息栏仍保留镜头缩放限制。")

	# Creation bar section
	_add_separator()
	_add_section("底部创建栏")
	_add_choice_field("creation_rows", "显示行数", ["1 行", "2 行", "3 行"])
	_add_choice_field("creation_mode", "浏览方式", ["分页", "上下滚动"])
	_add_caption("共用于基础棋子、高级棋子及后续地景。窗口空间不足时暂时减少实际行数，空间恢复后使用原设置。")

	# Reset button
	var reset := FluentButton.new()
	reset.text = "恢复界面默认"
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

func _add_caption(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", Typography.CAPTION)
	label.add_theme_color_override("font_color", FluentTokens.SECONDARY)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(label)

func _add_scale_field(key: String, title: String, choices: Array) -> void:
	var labels: Array = []
	for value in choices:
		labels.append("%d%%" % roundi(value * 100))

	var field := SettingsField.new()
	add_child(field)
	field.setup(title, labels)
	_fields[key] = field.option

	field.option.item_selected.connect(func(index: int):
		value_changed.emit(key, float(choices[index]))
	)

func _add_choice_field(key: String, title: String, items: Array) -> void:
	var field := SettingsField.new()
	add_child(field)
	field.setup(title, items)
	_fields[key] = field.option

	field.option.item_selected.connect(func(index: int):
		value_changed.emit(key, index)
	)

func sync_preferences(prefs: RefCounted) -> void:
	"""Sync UI with current preference values. Called on init and preference changes."""
	for key in _fields:
		if key == "motion":
			_fields[key].select(int(prefs.motion))
		elif key == "creation_rows":
			_fields[key].select(int(prefs.creation_rows) - 1)
		elif key == "creation_mode":
			_fields[key].select(0 if prefs.creation_mode == "pages" else 1)
		elif key in ["ui_scale", "info_scale", "floating_text"]:
			var choices: Array = Preferences.UI_SCALES if key == "ui_scale" else (Preferences.INFO_SCALES if key == "info_scale" else Preferences.TEXT_SCALES)
			var value: float = prefs.get(key)
			var index := choices.find(value)
			if index >= 0:
				_fields[key].select(index)
