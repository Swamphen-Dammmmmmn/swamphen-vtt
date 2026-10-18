extends VBoxContainer

const Style = preload("res://ui/components/page_style.gd")
const Typography = preload("res://ui/theme/typography.gd")
const FluentTheme = preload("res://ui/theme/themes/fluent_theme.gd")
const FluentTokens = preload("res://ui/theme/tokens/fluent_tokens.gd")
const FluentButton = preload("res://ui/components/controls/fluent_button.gd")
const Modal = preload("res://ui/components/page_modal.gd")

var _use_fluent := false
var _license_layer: CanvasLayer

func _ready() -> void:
	_use_fluent = get_meta("fluent_variant", false)
	if _use_fluent:
		theme = FluentTheme.shared()
		add_theme_constant_override("separation", 8)
	else:
		add_theme_constant_override("separation", 8)

	_add_caption("本软件使用 HarmonyOS Sans 字体。\n© 2021 Huawei Device Co., Ltd.")
	var view_license := FluentButton.new()
	view_license.text = "查看字体许可"
	view_license.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	view_license.pressed.connect(_show_license)
	add_child(view_license)

func _show_license() -> void:
	if is_instance_valid(_license_layer): return
	# The official file has trailing NUL padding. Keep its bytes untouched on disk;
	# trim the padding before UTF-8 decoding for display.
	var source := FileAccess.get_file_as_bytes("res://ui/theme/fonts/LICENSE.txt")
	var padding := source.find(0)
	if padding >= 0: source = source.slice(0, padding)
	_license_layer = CanvasLayer.new()
	var parent_layer := get_canvas_layer_node()
	_license_layer.layer = parent_layer.layer + 1 if parent_layer != null else 1
	add_child(_license_layer)
	var dialog := Modal.new()
	dialog.document_variant = true
	_license_layer.add_child(dialog)
	var text := source.get_string_from_utf8().replace("\r\n", "\n").replace("\r", "\n")
	var blank_lines := RegEx.new()
	blank_lines.compile("\\n[ \\t]*\\n(?:[ \\t]*\\n)+")
	dialog.configure("HarmonyOS Sans 字体许可", blank_lines.sub(text, "\n\n", true))
	dialog.add_action("关闭", dialog.dismiss)
	dialog.dismissed.connect(_close_license)

func _close_license() -> void:
	if is_instance_valid(_license_layer): _license_layer.queue_free()
	_license_layer = null

func _add_caption(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", Typography.CAPTION)
	if _use_fluent:
		label.add_theme_color_override("font_color", FluentTokens.SECONDARY)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(label)
