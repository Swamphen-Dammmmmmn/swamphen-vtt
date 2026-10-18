extends HBoxContainer

const Typography = preload("res://ui/theme/typography.gd")
signal requested
const ButtonComponent = preload("res://ui/components/controls/fluent_button.gd")
var kind := "basic"
var tags: Array = []
var selection_only := false

func _ready() -> void:
	add_theme_constant_override("separation",8)
	var type_button := ButtonComponent.new()
	type_button.variant = "FluentCompact"
	type_button.text = "基础棋子" if kind=="basic" else "高级棋子"
	type_button.add_theme_font_size_override("font_size",Typography.CAPTION)
	type_button.disabled = selection_only
	type_button.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	add_child(type_button)
	type_button.pressed.connect(func(): requested.emit())
	if tags.is_empty(): return
	var tag_button := ButtonComponent.new()
	tag_button.variant = "FluentCompact"
	tag_button.text = str(tags[0]) + (" · 另有%d项" % (tags.size()-1) if tags.size()>1 else "")
	tag_button.add_theme_font_size_override("font_size",Typography.CAPTION)
	tag_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tag_button.clip_text = true
	tag_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tag_button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	tag_button.tooltip_text = "、".join(PackedStringArray(tags))
	tag_button.disabled = selection_only
	add_child(tag_button)
	tag_button.pressed.connect(func(): requested.emit())
