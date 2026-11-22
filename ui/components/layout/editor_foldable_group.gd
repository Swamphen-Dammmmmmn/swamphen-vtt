# Editor foldable property group
# Wraps content in Godot's native FoldableContainer
extends FoldableContainer

const ET = preload("res://ui/theme/tokens/editor_tokens.gd")
const FluentTheme = preload("res://ui/theme/themes/fluent_theme.gd")

var _content_container: VBoxContainer

func _init() -> void:
	set_meta("style_owned", true)
	theme = FluentTheme.shared()
	theme_type_variation = "FluentPropertyGroup"
	custom_minimum_size.y = ET.FOLD_GROUP_TITLE_HEIGHT

	# Create content container immediately in _init
	_content_container = VBoxContainer.new()
	_content_container.add_theme_constant_override("separation", ET.FIELD_SEPARATION)
	_content_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL

func _ready() -> void:
	# Mount the pre-created content container
	if _content_container and not _content_container.is_inside_tree():
		add_child(_content_container)

func set_group_title(group_title: String) -> void:
	"""Set the group title. Safe to call before or after tree entry."""
	title = group_title

func content() -> VBoxContainer:
	"""Get the content container to add fields to. Always returns the same instance."""
	return _content_container
