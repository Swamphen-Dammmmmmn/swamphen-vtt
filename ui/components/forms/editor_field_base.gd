# Base class for editor field components
# Provides unified state management, theme application, and appearance updates
extends VBoxContainer

const FluentTheme = preload("res://ui/theme/themes/fluent_theme.gd")
const EditorTokens = preload("res://ui/theme/tokens/editor_tokens.gd")
const T = preload("res://ui/theme/tokens/fluent_tokens.gd")
const Typography = preload("res://ui/theme/typography.gd")

# Base field state
var _label: Label
var _error_label: Label
var _readonly := false
var _disabled := false
var _has_error := false

# Subclasses should initialize these in _init()
var _input_control: Control  # The primary input widget (LineEdit, CheckBox, etc)

func _init() -> void:
	set_meta("style_owned", true)
	add_theme_constant_override("separation", EditorTokens.FIELD_SEPARATION)

func _ready() -> void:
	# Apply theme
	theme = FluentTheme.shared()
	# Subclass _ready should call _update_appearance() after connecting signals

func _create_label(label_text: String) -> Label:
	"""Helper: Create and configure a field label."""
	var label := Label.new()
	label.add_theme_font_size_override("font_size", T.CAPTION_SIZE)
	label.add_theme_color_override("font_color", T.SECONDARY)
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.text = label_text
	return label

func _create_error_label() -> Label:
	"""Helper: Create and configure an error label."""
	var label := Label.new()
	label.add_theme_font_size_override("font_size", T.CAPTION_SIZE)
	label.add_theme_color_override("font_color", T.DANGER)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.visible = false
	return label

func set_error(message: String) -> void:
	"""Set error state and message."""
	_has_error = not message.is_empty()
	_error_label.text = message
	_error_label.visible = _has_error
	_update_appearance()

func set_invalid(invalid: bool) -> void:
	"""Mark the field red without its own message, for hosts that show one shared message."""
	_has_error = invalid
	_error_label.text = ""
	_error_label.visible = false
	_update_appearance()

func set_readonly(readonly: bool) -> void:
	"""Set readonly state."""
	_readonly = readonly
	_update_appearance()

func set_disabled(disabled: bool) -> void:
	"""Set disabled state."""
	_disabled = disabled
	_update_appearance()

func set_label_text(text: String) -> void:
	"""Display option: hosts that reuse one field for several meanings update its caption."""
	_label.text = text

func set_label_visible(shown: bool) -> void:
	"""Display option: hide the caption when the host supplies its own heading."""
	_label.visible = shown

func owns_keyboard() -> bool:
	var focused := get_viewport().gui_get_focus_owner()
	return focused != null and (focused == self or is_ancestor_of(focused))

func _clear_error_on_input() -> void:
	"""Helper: Clear error when user provides input (call from input callbacks)."""
	if _has_error:
		set_error("")

func _update_appearance() -> void:
	"""
	Update control appearance based on state flags.
	Subclasses override and call super() to ensure proper state management.
	Each subclass handles its own control properties (disabled, editable, etc).
	Base class provides the framework; subclasses implement specifics.
	"""
	# Base: no-op. Subclasses handle their specific controls.
