extends Label3D

const Typography = preload("res://ui/theme/typography.gd")
const T = preload("res://ui/theme/tokens/fluent_tokens.gd")

# Dense asset galleries need the same typography at a smaller world-space scale.
# Default wall sandbox labels keep their accepted scale.
var compact := false:
	set(value):
		compact=value
		pixel_size=0.0018 if value else 0.0072

func _init() -> void:
	font = Typography.WORLD_REGULAR
	font_size = Typography.PREVIEW_MEASURE
	pixel_size = 0.0072
	billboard = BaseMaterial3D.BILLBOARD_ENABLED
	modulate = T.FOREGROUND
	outline_size = 0
